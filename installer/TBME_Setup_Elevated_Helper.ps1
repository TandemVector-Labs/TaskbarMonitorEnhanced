param(
    [Parameter(Mandatory=$true)][ValidateSet('Install','Uninstall')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$PayloadDir,
    [Parameter(Mandatory=$true)][string]$AppRoot,
    [Parameter(Mandatory=$true)][string]$UserId,
    [string]$ExpectedBrokerSHA256='',
    [string]$ExpectedSupervisorSHA256='',
    [string]$ExpectedBackendZipSHA256=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# R291: privileged sensor preflight runs before ANY result/log creation.
# Ordinary per-user Setup stays unelevated; only optional sensors use UAC.
function Assert-SensorBoundaryNoReparse([string]$Path){
    if([string]::IsNullOrWhiteSpace($Path)){throw 'SENSOR_BOUNDARY_EMPTY_PATH'}
    $cursor=[IO.Path]::GetFullPath($Path)
    while(-not [string]::IsNullOrEmpty($cursor)){
        try{
            if(([IO.File]::GetAttributes($cursor) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                throw [IO.IOException]::new('SENSOR_BOUNDARY_REPARSE_REFUSED: '+$cursor)
            }
        }catch [IO.FileNotFoundException]{
            # Absent output may be created later; other I/O errors fail closed.
        }catch [IO.DirectoryNotFoundException]{
        }
        $parent=[IO.Path]::GetDirectoryName($cursor)
        if([string]::IsNullOrEmpty($parent) -or $parent -ceq $cursor){break}
        $cursor=$parent
    }
}
function Assert-SensorPrivilegedBoundary(
    [string]$RequestedMode,[string]$RequestedPayload,[string]$RequestedAppRoot,[string]$RequestedUser
){
    if($RequestedMode -cne 'Install' -and $RequestedMode -cne 'Uninstall'){
        throw 'SENSOR_BOUNDARY_INVALID_MODE'
    }
    if([string]::IsNullOrWhiteSpace($RequestedUser)){throw 'SENSOR_BOUNDARY_EMPTY_USER'}
    $sid=if($RequestedUser -match '^S-1-5-21-(?:\d+-){3}\d+$'){
        $RequestedUser
    }else{
        try{
            [string]([Security.Principal.NTAccount]::new($RequestedUser)).Translate(
                [Security.Principal.SecurityIdentifier]
            ).Value
        }catch{
            throw 'SENSOR_BOUNDARY_USER_ID_UNRESOLVABLE'
        }
    }
    if($sid -cnotmatch '^S-1-5-21-(?:\d+-){3}\d+$'){
        throw 'SENSOR_BOUNDARY_USER_PROFILE_NOT_INTERACTIVE'
    }
    # R305: runas with a credential prompt can launch as a different admin.
    # Fail BEFORE any sensor log/result/ProgramFiles/task mutation if the
    # actual elevated process identity is not the intended user's SID.
    $effective=[Security.Principal.WindowsIdentity]::GetCurrent()
    if($null -eq $effective -or $null -eq $effective.User -or
       -not [string]::Equals([string]$effective.User.Value,$sid,[StringComparison]::OrdinalIgnoreCase)){
        throw 'SENSOR_BOUNDARY_ELEVATED_TOKEN_ACCOUNT_MISMATCH'
    }
    $profileKey='HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\'+$sid
    $entry=Get-ItemProperty -LiteralPath $profileKey -ErrorAction Stop
    if([string]::IsNullOrWhiteSpace([string]$entry.ProfileImagePath)){
        throw 'SENSOR_BOUNDARY_PROFILE_MISSING'
    }
    $profile=[IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables([string]$entry.ProfileImagePath)
    ).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if($profile.StartsWith('\\') -or [IO.Path]::GetPathRoot($profile) -ceq $profile){
        throw 'SENSOR_BOUNDARY_PROFILE_NOT_LOCAL'
    }
    $expectedRoot=[IO.Path]::GetFullPath((Join-Path $profile 'AppData\Local\TaskbarMonitorEnhanced'))
    if(-not [IO.Path]::IsPathRooted($RequestedAppRoot) -or
       -not [string]::Equals([IO.Path]::GetFullPath($RequestedAppRoot),
               $expectedRoot,[StringComparison]::OrdinalIgnoreCase)){
        throw 'SENSOR_BOUNDARY_APP_ROOT_OUTSIDE_USER_PROFILE'
    }
    if(-not [IO.Path]::IsPathRooted($RequestedPayload)){
        throw 'SENSOR_BOUNDARY_PAYLOAD_NOT_ABSOLUTE'
    }
    $payload=[IO.Path]::GetFullPath($RequestedPayload)
    $name=[IO.Path]::GetFileName($payload.TrimEnd([IO.Path]::DirectorySeparatorChar))
    $prefix=if($RequestedMode -ceq 'Install'){'tbme_setup_'}else{'tbme_uninstall_'}
    # Only direct children of this user's default Temp root are trusted. A
    # profile-wide prefix would also accept Downloads or arbitrary subfolders.
    # Nonstandard redirected TEMP locations fail closed (optional sensors degrade).
    $expectedTempParent=[IO.Path]::GetFullPath(
        (Join-Path $profile 'AppData\Local\Temp')
    ).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if(-not [string]::Equals([IO.Path]::GetDirectoryName($payload),
                             $expectedTempParent,[StringComparison]::OrdinalIgnoreCase) -or
       $name -cnotmatch ('^'+$prefix+'[0-9a-f]{32}$')){
        throw 'SENSOR_BOUNDARY_PAYLOAD_OUTSIDE_USER_TEMP'
    }
    $trustedProgramFiles=[Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
    if(-not [string]::Equals([IO.Path]::GetFullPath($trustedProgramFiles),
              [IO.Path]::GetFullPath($env:ProgramFiles),[StringComparison]::OrdinalIgnoreCase)){
        throw 'SENSOR_BOUNDARY_PROGRAMFILES_REDIRECT'
    }
    $brokerRoot=Join-Path $trustedProgramFiles 'TaskbarMonitorEnhanced\SensorBroker'
    $candidates=@(
       $profile,$expectedRoot,$payload,$brokerRoot,
       (Join-Path $expectedRoot 'Logs'),
       (Join-Path $expectedRoot 'Logs\sensor_install.log'),
       (Join-Path $expectedRoot 'Logs\sensor_install_result.json'),
       (Join-Path $expectedRoot 'SensorBackend\LibreHardwareMonitor-0.9.6\LibreHardwareMonitorLib.dll'),
       (Join-Path $expectedRoot 'cpu_temp_broker.json'),
       (Join-Path $expectedRoot 'gpu_temp_broker.json'),
       (Join-Path $expectedRoot 'storage_temp_broker.json'),
       (Join-Path $expectedRoot 'sensor_supervisor_state.json'),
       (Join-Path $payload 'TBME_Setup_Elevated_Helper.ps1'),
       (Join-Path $payload 'TaskbarMonitorSensorBroker.exe'),
       (Join-Path $payload 'TaskbarMonitorSensorSupervisor.exe'),
       (Join-Path $brokerRoot 'TaskbarMonitorSensorBroker.exe'),
       (Join-Path $brokerRoot 'TaskbarMonitorSensorSupervisor.exe')
    )
    foreach($path in $candidates){Assert-SensorBoundaryNoReparse $path}
    $script:ValidatedSensorProfileRoot=$profile
    return $sid
}
$validatedSensorSid=Assert-SensorPrivilegedBoundary $Mode $PayloadDir $AppRoot $UserId

# R335: native in-memory handle guards pin canonical per-user profile
# ancestry and exact file handles across log/result writes. Refuse reparse
# points by handle, never create a user-writable script or change UAC policy.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public sealed class TBMEScopedUserLogLease : IDisposable {
const uint FILE_LIST_DIRECTORY=0x0001;
const uint GENERIC_READ=0x80000000;
const uint GENERIC_WRITE=0x40000000;
const uint FILE_SHARE_READ=1,FILE_SHARE_WRITE=2;
const uint OPEN_EXISTING=3, OPEN_ALWAYS=4;
const uint FILE_FLAG_BACKUP_SEMANTICS=0x02000000;
const uint FILE_FLAG_OPEN_REPARSE_POINT=0x00200000;
const uint FILE_ATTRIBUTE_DIRECTORY=0x10;
const uint FILE_ATTRIBUTE_REPARSE_POINT=0x400;
[DllImport("kernel32.dll",EntryPoint="CreateFileW",SetLastError=true,CharSet=CharSet.Unicode)]
static extern SafeFileHandle OpenNative(string name,uint access,uint share,IntPtr sec,uint disposition,uint flags,IntPtr template);
[StructLayout(LayoutKind.Sequential)]
public struct TagInfo { public uint FileAttributes; public uint ReparseTag; }
[DllImport("kernel32.dll",SetLastError=true)]
static extern bool GetFileInformationByHandleEx(SafeFileHandle handle,int kind,out TagInfo data,uint size);
readonly SafeFileHandle[] guard=new SafeFileHandle[5];
int guardCount=0;
FileStream stream;
bool disposed;
static SafeFileHandle OpenChecked(string path,uint access,uint share,uint disposition,uint flags,bool isDirectory){
SafeFileHandle handle=OpenNative(path,access,share,IntPtr.Zero,disposition,flags,IntPtr.Zero);
if(handle.IsInvalid){
int e=Marshal.GetLastWin32Error();
handle.Dispose();
throw new IOException("SENSOR_LOG_HANDLE_CREATEFILE_FAILED_WIN32_"+e+" "+Path.GetFileName(path));
}
TagInfo info;
if(!GetFileInformationByHandleEx(handle,9,out info,(uint)Marshal.SizeOf(typeof(TagInfo)))){
int e=Marshal.GetLastWin32Error();
handle.Dispose();
throw new IOException("SENSOR_LOG_HANDLE_ATTRIBUTE_TAG_QUERY_FAILED_WIN32_"+e);
}
if((info.FileAttributes&FILE_ATTRIBUTE_REPARSE_POINT)!=0 ||
((info.FileAttributes&FILE_ATTRIBUTE_DIRECTORY)!=0)!=isDirectory){
handle.Dispose();
throw new IOException("SENSOR_LOG_HANDLE_REPARSE_OR_COMPONENT_TYPE_REFUSED");
}
return handle;
}
public TBMEScopedUserLogLease(string profile,string appRoot,string logDir,string exactFile){
if(String.IsNullOrWhiteSpace(profile) || String.IsNullOrWhiteSpace(appRoot) ||
String.IsNullOrWhiteSpace(logDir) || String.IsNullOrWhiteSpace(exactFile))
throw new IOException("SENSOR_LOG_HANDLE_EMPTY_LOG_BOUNDARY");
string p=Path.GetFullPath(profile);
string appdata=Path.Combine(p,"AppData");
string local=Path.Combine(appdata,"Local");
string expected=Path.GetFullPath(Path.Combine(local,"TaskbarMonitorEnhanced"));
string logs=Path.GetFullPath(Path.Combine(expected,"Logs"));
string file=Path.GetFullPath(exactFile);
string log=Path.GetFullPath(Path.Combine(logs,"sensor_install.log"));
string result=Path.GetFullPath(Path.Combine(logs,"sensor_install_result.json"));
if(!String.Equals(Path.GetFullPath(appRoot),expected,StringComparison.OrdinalIgnoreCase) ||
!String.Equals(Path.GetFullPath(logDir),logs,StringComparison.OrdinalIgnoreCase) ||
!(String.Equals(file,log,StringComparison.OrdinalIgnoreCase) ||
String.Equals(file,result,StringComparison.OrdinalIgnoreCase))){
throw new IOException("SENSOR_LOG_HANDLE_CANONICAL_LOG_PATH_MISMATCH");
}
try{
foreach(string dir in new string[]{p,appdata,local,expected,logs}){
SafeFileHandle parent=OpenChecked(dir,FILE_LIST_DIRECTORY,FILE_SHARE_READ|FILE_SHARE_WRITE,
OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,true);
guard[guardCount++]=parent;
}
SafeFileHandle h=OpenChecked(file,GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ,
OPEN_ALWAYS,FILE_FLAG_OPEN_REPARSE_POINT,false);
try{
stream=new FileStream(h,FileAccess.ReadWrite);
stream.Seek(0,SeekOrigin.End);
}catch{h.Dispose();throw;}
}catch{Dispose();throw;}
}
public void Append(string text){
if(disposed || stream==null)throw new ObjectDisposedException("TBMEScopedUserLogLease");
if(stream.Length==0){
byte[] bom=new System.Text.UTF8Encoding(true).GetPreamble();
stream.Write(bom,0,bom.Length);
}
byte[] data=System.Text.Encoding.UTF8.GetBytes(text);
stream.Write(data,0,data.Length);
stream.Flush(true);
}
public void Overwrite(string text){
if(disposed || stream==null)throw new ObjectDisposedException("TBMEScopedUserLogLease");
stream.SetLength(0);stream.Position=0;
byte[] bom=new System.Text.UTF8Encoding(true).GetPreamble();
stream.Write(bom,0,bom.Length);
byte[] data=System.Text.Encoding.UTF8.GetBytes(text);
stream.Write(data,0,data.Length);
stream.Flush(true);
}
public void Dispose(){
if(disposed)return;
disposed=true;
if(stream!=null){stream.Dispose();stream=null;}
for(int i=guardCount-1;i>=0;i--)if(guard[i]!=null)guard[i].Dispose();
guardCount=0;
}
}
public sealed class TBMEProtectedBrokerLease : IDisposable {
const uint FILE_LIST_DIRECTORY=0x00000001;
const uint SHARE_READ=1, SHARE_WRITE=2, OPEN_EXISTING=3;
const uint BACKUP_SEMANTICS=0x02000000, OPEN_REPARSE_POINT=0x00200000;
const uint ATTR_DIRECTORY=0x10, ATTR_REPARSE=0x400;
[DllImport("kernel32.dll",EntryPoint="CreateFileW",SetLastError=true,CharSet=CharSet.Unicode)]
static extern SafeFileHandle OpenNative(string path,uint access,uint share,IntPtr sec,
uint creation,uint flags,IntPtr template);
[StructLayout(LayoutKind.Sequential)]
struct FILE_ATTRIBUTE_TAG_INFO { public uint Attributes; public uint Tag; }
[DllImport("kernel32.dll",SetLastError=true)]
static extern bool GetFileInformationByHandleEx(SafeFileHandle handle,int kind,
out FILE_ATTRIBUTE_TAG_INFO data,uint size);
readonly SafeFileHandle[] parents=new SafeFileHandle[3];
int count;
bool disposed;
static SafeFileHandle OpenExactDir(string path) {
SafeFileHandle h=OpenNative(path,FILE_LIST_DIRECTORY,
SHARE_READ|SHARE_WRITE,IntPtr.Zero,OPEN_EXISTING,
BACKUP_SEMANTICS|OPEN_REPARSE_POINT,IntPtr.Zero);
if(h.IsInvalid) {
int error=Marshal.GetLastWin32Error();
h.Dispose();
throw new IOException("SENSOR_BROKER_DIRECTORY_LEASE_OPEN_FAILED_WIN32_"+error);
}
FILE_ATTRIBUTE_TAG_INFO info;
if(!GetFileInformationByHandleEx(h,9,out info,
(uint)Marshal.SizeOf(typeof(FILE_ATTRIBUTE_TAG_INFO)))) {
int error=Marshal.GetLastWin32Error(); h.Dispose();
throw new IOException("SENSOR_BROKER_DIRECTORY_LEASE_TAG_FAILED_WIN32_"+error);
}
if((info.Attributes&ATTR_DIRECTORY)==0||(info.Attributes&ATTR_REPARSE)!=0) {
h.Dispose();
throw new IOException("SENSOR_BROKER_DIRECTORY_LEASE_REPARSE_REFUSED");
}
return h;
}
public TBMEProtectedBrokerLease(string liveBroker) {
string program=Path.GetFullPath(Environment.GetFolderPath(
Environment.SpecialFolder.ProgramFiles)).TrimEnd(Path.DirectorySeparatorChar);
string root=Path.Combine(program,"TaskbarMonitorEnhanced");
string broker=Path.Combine(root,"SensorBroker");
if(String.IsNullOrWhiteSpace(liveBroker) ||
!String.Equals(Path.GetFullPath(liveBroker).TrimEnd(Path.DirectorySeparatorChar),
broker,StringComparison.OrdinalIgnoreCase)) {
throw new IOException("SENSOR_BROKER_DIRECTORY_LEASE_NOT_EXACT_SYSTEM_PROGRAMFILES");
}
try {
parents[count++]=OpenExactDir(program);
parents[count++]=OpenExactDir(root);
if(!Directory.Exists(broker))Directory.CreateDirectory(broker);
parents[count++]=OpenExactDir(broker);
canonicalBroker=broker;
}catch {Dispose();throw;}
}
const uint GENERIC_READ=0x80000000, GENERIC_WRITE=0x40000000;
const uint OPEN_ALWAYS=4, ATTR_REPARSE_POINT=0x400;
[StructLayout(LayoutKind.Sequential)]
struct FILE_TIME_PAIR { public uint Low; public uint High; }
[StructLayout(LayoutKind.Sequential)]
struct FILE_HANDLE_INFO {
public uint FileAttributes;
public FILE_TIME_PAIR Created, Accessed, Modified;
public uint VolumeSerial, SizeHigh, SizeLow, NumberOfLinks, IndexHigh, IndexLow;
}
[DllImport("kernel32.dll",SetLastError=true)]
static extern bool GetFileInformationByHandle(SafeFileHandle h,out FILE_HANDLE_INFO info);
[DllImport("kernel32.dll",EntryPoint="GetFinalPathNameByHandleW",
SetLastError=true,CharSet=CharSet.Unicode)]
static extern uint FinalNative(SafeFileHandle h,System.Text.StringBuilder path,
uint capacity,uint flags);
readonly System.Collections.Generic.Dictionary<string,FileStream> leaves=
new System.Collections.Generic.Dictionary<string,FileStream>(
StringComparer.OrdinalIgnoreCase);
readonly System.Collections.Generic.List<SafeFileHandle> childDirectories=
new System.Collections.Generic.List<SafeFileHandle>();
string canonicalBroker;
public FileStream OpenReplayLeaf(string relative) {
if(!IsPinned||String.IsNullOrWhiteSpace(relative)){
throw new IOException("SENSOR_REPLAY_LEAF_LEASE_NOT_PINNED");
}
relative=relative.Replace('/',Path.DirectorySeparatorChar);
string[] parts=relative.Split(Path.DirectorySeparatorChar);
if(parts.Length==0||parts.Length>8){
throw new IOException("SENSOR_REPLAY_LEAF_TOO_DEEP");
}
foreach(string part in parts) {
if(part=="."||part==".."||
!System.Text.RegularExpressions.Regex.IsMatch(part,@"^[A-Za-z0-9_.-]+$")){
throw new IOException("SENSOR_REPLAY_LEAF_BAD_COMPONENT");
}
}
string path=Path.GetFullPath(Path.Combine(canonicalBroker,relative));
if(!path.StartsWith(canonicalBroker+Path.DirectorySeparatorChar,
StringComparison.OrdinalIgnoreCase)){
throw new IOException("SENSOR_REPLAY_LEAF_OUTSIDE_FIXED_BROKER");
}
FileStream already;
if(leaves.TryGetValue(relative,out already)){return already;}
string parent=canonicalBroker;
for(int i=0;i<parts.Length-1;i++){
parent=Path.Combine(parent,parts[i]);
if(!Directory.Exists(parent)){
throw new IOException("SENSOR_REPLAY_LEAF_NESTED_PARENT_ABSENT");
}
childDirectories.Add(OpenExactDir(parent));
}
SafeFileHandle h=OpenNative(path,GENERIC_READ|GENERIC_WRITE,SHARE_READ,
IntPtr.Zero,OPEN_ALWAYS,OPEN_REPARSE_POINT,IntPtr.Zero);
if(h.IsInvalid){
int err=Marshal.GetLastWin32Error();h.Dispose();
throw new IOException("SENSOR_REPLAY_LEAF_EXCLUSIVE_OPEN_FAILED_WIN32_"+err);
}
try {
FILE_ATTRIBUTE_TAG_INFO tag;
if(!GetFileInformationByHandleEx(h,9,out tag,
(uint)Marshal.SizeOf(typeof(FILE_ATTRIBUTE_TAG_INFO))) ||
(tag.Attributes&(ATTR_DIRECTORY|ATTR_REPARSE_POINT))!=0){
throw new IOException("SENSOR_REPLAY_LEAF_REPARSE_OR_DIRECTORY_REFUSED");
}
FILE_HANDLE_INFO id;
if(!GetFileInformationByHandle(h,out id) || id.NumberOfLinks!=1){
throw new IOException("SENSOR_REPLAY_LEAF_HARDLINK_OR_UNKNOWN_ID");
}
System.Text.StringBuilder buffer=new System.Text.StringBuilder(2048);
uint n=FinalNative(h,buffer,(uint)buffer.Capacity,0);
if(n==0||n>=buffer.Capacity||
!String.Equals(buffer.ToString(),"\\\\?\\"+path,
StringComparison.OrdinalIgnoreCase)){
throw new IOException("SENSOR_REPLAY_LEAF_FINAL_PATH_IDENTITY_MISMATCH");
}
FileStream fs=new FileStream(h,FileAccess.ReadWrite);
leaves.Add(relative,fs);
return fs;
}catch{h.Dispose();throw;}
}
public byte[] ReadReplayLeaf(string relative) {
FileStream fs=OpenReplayLeaf(relative);
if(fs.Length>16777216){throw new IOException("SENSOR_REPLAY_LEAF_SIZE_LIMIT");}
byte[] result=new byte[(int)fs.Length];
fs.Position=0;
int pos=0;
while(pos<result.Length){
int n=fs.Read(result,pos,result.Length-pos);
if(n<=0){throw new IOException("SENSOR_REPLAY_LEAF_SHORT_READ");}
pos+=n;
}
return result;
}
public byte[] ReplaceReplayLeaf(string relative,byte[] oldBytes) {
if(oldBytes==null||oldBytes.Length>16777216){
throw new IOException("SENSOR_REPLAY_LEAF_DATA_BOUND");
}
FileStream fs=OpenReplayLeaf(relative);
fs.Position=0;
fs.SetLength(oldBytes.Length);
fs.Write(oldBytes,0,oldBytes.Length);
fs.Flush(true);
return ReadReplayLeaf(relative);
}
public bool IsPinned {get{return !disposed&&count==3;}}
public void Dispose() {
if(disposed)return;
disposed=true;
foreach(FileStream fs in leaves.Values)fs.Dispose();
leaves.Clear();
for(int i=childDirectories.Count-1;i>=0;i--)childDirectories[i].Dispose();
childDirectories.Clear();
for(int i=count-1;i>=0;i--)if(parents[i]!=null)parents[i].Dispose();
count=0;
}
}
'@

$TaskName='TaskbarMonitorEnhanced Sensor Broker'
$BrokerRoot=Join-Path $env:ProgramFiles 'TaskbarMonitorEnhanced\SensorBroker'
$SensorOwnerMarker=Join-Path $BrokerRoot '.tbme-owner.sid'
$script:SensorJournalRoot=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)) 'TaskbarMonitorEnhanced\.tbme-sensor-rollback'
$LogsRoot=Join-Path $AppRoot 'Logs'
$ResultPath=Join-Path $LogsRoot 'sensor_install_result.json'
$LogPath=Join-Path $LogsRoot 'sensor_install.log'
# R328: the user owns this tree and can replace its directories between
# the original privileged preflight and its later log/result writes.
# Recheck immediately around creation; this does not close atomic races.
Assert-SensorBoundaryNoReparse $LogsRoot
New-Item -ItemType Directory -Force -Path $LogsRoot | Out-Null
Assert-SensorBoundaryNoReparse $LogsRoot

# R21 health channels are initialized before any early-return/uninstall branch so
# Write-Result can always emit a stable schema under StrictMode.
$SupervisorHealthy=$false
$CpuTransportHealthy=$false
$GpuTransportHealthy=$false
$StorageTransportHealthy=$false
$CpuDataAvailable=$false
# R344-F06: Setup executes the embedded Helper inside a nested scriptblock.
# Later functions write $script: state; initialize those same variables in
# script scope too, otherwise local bootstrap fields shadow the snapshots.
$script:RollbackPerformed=$false
$script:RollbackSucceeded=$false
$script:PreviousSensorLayerPresent=$false
$script:ActiveArchitecture='R21_PROCESS_ISOLATED'
$script:RollbackFiles=@()
$script:RollbackTaskXmlText=$null
$script:RollbackCaptured=$false

# Fail closed when a user-writable profile log path was replaced after the
# initial elevated token/boundary verification. Write-time inspection is
# not an atomic handle-bound proof against concurrent rename/symlink swaps.
function Assert-SensorUserLogSink([string]$Target){
    if([string]::IsNullOrWhiteSpace($Target) -or
       [string]::IsNullOrWhiteSpace($AppRoot)){
        throw 'SENSOR_LOG_BOUNDARY_MISSING'
    }
    $expectedRoot=[IO.Path]::GetFullPath((Join-Path $AppRoot 'Logs')).TrimEnd('\')
    $actualRoot=[IO.Path]::GetFullPath($LogsRoot).TrimEnd('\')
    if(-not [string]::Equals($expectedRoot,$actualRoot,[StringComparison]::OrdinalIgnoreCase)){
        throw 'SENSOR_LOG_BOUNDARY_CHANGED_ROOT'
    }
    $actual=[IO.Path]::GetFullPath($Target)
    $log=[IO.Path]::GetFullPath((Join-Path $expectedRoot 'sensor_install.log'))
    $result=[IO.Path]::GetFullPath((Join-Path $expectedRoot 'sensor_install_result.json'))
    if(-not([string]::Equals($actual,$log,[StringComparison]::OrdinalIgnoreCase) -or
             [string]::Equals($actual,$result,[StringComparison]::OrdinalIgnoreCase))){
        throw 'SENSOR_LOG_BOUNDARY_CHANGED_TARGET'
    }
    Assert-SensorBoundaryNoReparse $AppRoot
    Assert-SensorBoundaryNoReparse $actualRoot
    Assert-SensorBoundaryNoReparse $actual
    if(-not [IO.Directory]::Exists($actualRoot)){
        throw 'SENSOR_LOG_BOUNDARY_MISSING_LOG_DIRECTORY'
    }
}

function Write-Log([string]$Message){
    Assert-SensorUserLogSink $LogPath
    $line=(Get-Date).ToString('o')+' '+$Message+[Environment]::NewLine
    $lease=[TBMEScopedUserLogLease]::new($script:ValidatedSensorProfileRoot,$AppRoot,$LogsRoot,$LogPath)
    try{$lease.Append($line)}finally{$lease.Dispose()}
}
function Write-Result(
    [string]$Status,
    [string]$Message,
    [string]$PawnStatus,
    [Nullable[int]]$PawnExitCode,
    [bool]$RebootRequired,
    [bool]$TaskInstalled,
    [bool]$SensorHealthy
){
    Assert-SensorUserLogSink $ResultPath
    $json=[ordered]@{
        Status=$Status
        Message=$Message
        PawnIOStatus=$PawnStatus
        PawnIOExitCode=$(if($null -eq $PawnExitCode){$null}else{[int]$PawnExitCode})
        RebootRequired=$RebootRequired
        TaskInstalled=$TaskInstalled
        SensorHealthy=$SensorHealthy
        SupervisorHealthy=$SupervisorHealthy
        CpuTransportHealthy=$CpuTransportHealthy
        GpuTransportHealthy=$GpuTransportHealthy
        StorageTransportHealthy=$StorageTransportHealthy
        CpuDataAvailable=$CpuDataAvailable
        Architecture=$ActiveArchitecture
        RollbackPerformed=$RollbackPerformed
        RollbackSucceeded=$RollbackSucceeded
        PreviousSensorLayerPresent=$PreviousSensorLayerPresent
        Time=(Get-Date).ToString('o')
        LogPath=$LogPath
    } | ConvertTo-Json -Depth 5
    $lease=[TBMEScopedUserLogLease]::new($script:ValidatedSensorProfileRoot,$AppRoot,$LogsRoot,$ResultPath)
    try{$lease.Overwrite($json+[Environment]::NewLine)}finally{$lease.Dispose()}
}
function Get-PawnIOVersion {
    foreach($key in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\PawnIO'
    )){
        try{
            if(Test-Path -LiteralPath $key){
                $value=(Get-ItemProperty -LiteralPath $key -ErrorAction Stop).DisplayVersion
                if($value){return [string]$value}
            }
        }catch{}
    }
    return ''
}

# R296: no privileged rollback snapshot is staged to user-writable Temp.
function Get-SensorRollbackFiles([string]$Folder){
    Assert-SensorBoundaryNoReparse $Folder
    $root=[IO.Path]::GetFullPath($Folder).TrimEnd('\')
    $prefix=$root+'\'
    $items=@(Get-ChildItem -LiteralPath $root -Force -Recurse -ErrorAction Stop)
    foreach($item in $items){Assert-SensorBoundaryNoReparse $item.FullName}
    $files=@($items|Where-Object {-not $_.PSIsContainer})
    if($files.Count -gt 128){throw 'ROLLBACK_FILE_COUNT'}
    $saved=[Collections.Generic.List[object]]::new()
    [long]$total=0
    foreach($file in $files){
        $path=[IO.Path]::GetFullPath($file.FullName)
        if(-not $path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'ROLLBACK_PATH_ESCAPE'}
        Assert-SensorBoundaryNoReparse $path
        $rel=$path.Substring($prefix.Length)
        foreach($part in $rel.Split('\')){
            if($part -ceq '.' -or $part -ceq '..' -or $part -cnotmatch '^[A-Za-z0-9_.-]+$'){
                throw 'ROLLBACK_BAD_NAME'
            }
        }
        $fs=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
        try{
            if($fs.Length -gt 16777216){throw 'ROLLBACK_FILE_TOO_LARGE'}
            $total+=$fs.Length
            if($total -gt 67108864){throw 'ROLLBACK_TOTAL_TOO_LARGE'}
            $bytes=[byte[]]::new([int]$fs.Length)
            $n=0
            while($n -lt $bytes.Length){
                $k=$fs.Read($bytes,$n,$bytes.Length-$n)
                if($k -lt 1){throw 'ROLLBACK_SHORT_READ'}
                $n+=$k
            }
            $saved.Add([pscustomobject]@{Rel=$rel;Data=$bytes})
        }finally{$fs.Dispose()}
    }
    return ,$saved.ToArray()
}
function Restore-SensorRollbackFiles([string]$Folder,[object[]]$Saved){
    Assert-SensorBoundaryNoReparse $Folder
    New-Item -ItemType Directory -Force -Path $Folder|Out-Null
    foreach($entry in $Saved){
        foreach($part in ([string]$entry.Rel).Split('\')){
            if($part -ceq '.' -or $part -ceq '..' -or $part -cnotmatch '^[A-Za-z0-9_.-]+$'){
                throw 'ROLLBACK_RESTORE_BAD_NAME'
            }
        }
        $path=Join-Path $Folder $entry.Rel
        Assert-SensorBoundaryNoReparse $path
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path)|Out-Null
        Assert-SensorBoundaryNoReparse $path
        [IO.File]::WriteAllBytes($path,[byte[]]$entry.Data)
    }
}
function Clear-SensorRollbackBuffer {
    $script:RollbackFiles=@()
    $script:RollbackTaskXmlText=$null
    $script:RollbackCaptured=$false
}

# R308 experimental protected write-ahead snapshot. The current review stage
# deliberately refuses preexisting/stale journals rather than consuming them.
# Crash recovery and terminal cleanup need separate native acceptance.
function Get-SensorJournalHash([byte[]]$Value){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return [BitConverter]::ToString($sha.ComputeHash($Value)).Replace('-','')}
    finally{$sha.Dispose()}
}
function Assert-SensorJournalRelative([string]$Rel){
    if([string]::IsNullOrWhiteSpace($Rel) -or $Rel.Length -gt 240 -or
       [IO.Path]::IsPathRooted($Rel) -or $Rel.Contains('/') -or
       $Rel.Contains(':') -or $Rel.StartsWith('\') -or $Rel.EndsWith('\')){
        throw 'SENSOR_JOURNAL_UNSAFE_RELATIVE_NAME'
    }
    foreach($part in $Rel.Split('\')){
        if($part -ceq '.' -or $part -ceq '..' -or $part.EndsWith('.') -or
           $part -cnotmatch '^[A-Za-z0-9_.-]+$'){
            throw 'SENSOR_JOURNAL_UNSAFE_RELATIVE_NAME'
        }
    }
}
function Assert-SensorJournalTrustedAcl([string]$Path,[bool]$RequireProtected){
    Assert-SensorBoundaryNoReparse $Path
    $acl=Get-Acl -LiteralPath $Path -ErrorAction Stop
    $owner=([Security.Principal.NTAccount]::new([string]$acl.Owner)).Translate(
        [Security.Principal.SecurityIdentifier]).Value
    $trusted=@('S-1-5-18','S-1-5-32-544',
        'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
    if($trusted -cnotcontains $owner){throw 'SENSOR_JOURNAL_UNTRUSTED_OWNER'}
    if($RequireProtected -and -not $acl.AreAccessRulesProtected){
        throw 'SENSOR_JOURNAL_UNPROTECTED_DACL'
    }
    # R344-F03: FileSystemRights.Modify includes ReadAndExecute.
    # Bitwise testing the composite Modify value wrongly treated benign
    # BUILTIN Users ReadAndExecute as a write ACE. Check only mutation
    # capabilities; never loosen the trusted owner or SID allowlist.
    $write=[Security.AccessControl.FileSystemRights]::Write -bor
        [Security.AccessControl.FileSystemRights]::Delete -bor
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [Security.AccessControl.FileSystemRights]::TakeOwnership
    foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
        if($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow){continue}
        if($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly){continue}
        if(($trusted -cnotcontains [string]$rule.IdentityReference.Value) -and
           ($rule.FileSystemRights -band $write)){
            throw 'SENSOR_JOURNAL_UNTRUSTED_WRITE_ACE'
        }
    }
}
function Write-SensorJournalUnique([string]$Root,[string]$Relative,[byte[]]$Bytes){
    Assert-SensorJournalRelative $Relative
    $file=Join-Path $Root $Relative
    $parent=[IO.Path]::GetDirectoryName($file)
    Assert-SensorBoundaryNoReparse $parent
    [void][IO.Directory]::CreateDirectory($parent)
    Assert-SensorJournalTrustedAcl $parent $false
    Assert-SensorBoundaryNoReparse $file
    $fs=[IO.FileStream]::new($file,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$fs.Write($Bytes,0,$Bytes.Length);$fs.Flush($true)}
    finally{$fs.Dispose()}
    Assert-SensorJournalTrustedAcl $file $false
}
function Assert-SensorDurableJournal([string]$Root,[string]$ExpectedSid){
    Assert-SensorJournalTrustedAcl $Root $true
    $ready=Join-Path $Root 'READY'
    Assert-SensorBoundaryNoReparse $ready
    if(-not [IO.File]::Exists($ready) -or
       [IO.File]::ReadAllText($ready,[Text.Encoding]::ASCII) -cne 'TBME_SENSOR_READY_V1'){
        throw 'SENSOR_JOURNAL_INCOMPLETE_OR_UNREADY'
    }
    foreach($name in @('READY','manifest.json','task.xml')){
        Assert-SensorJournalTrustedAcl (Join-Path $Root $name) $false
    }
    $file=Join-Path $Root 'manifest.json'
    if(([IO.FileInfo]::new($file)).Length -gt 65536){throw 'SENSOR_JOURNAL_MANIFEST_OVERSIZE'}
    $manifest=[IO.File]::ReadAllText($file,[Text.Encoding]::UTF8)|ConvertFrom-Json
    if($manifest.Schema -ne 1 -or $manifest.Phase -cne 'PREPARED' -or
       $manifest.Sid -cne $ExpectedSid){throw 'SENSOR_JOURNAL_OWNER_OR_PHASE_MISMATCH'}
    $bytes=[IO.File]::ReadAllBytes((Join-Path $Root 'task.xml'))
    if($bytes.Length -gt 262144 -or
       (Get-SensorJournalHash $bytes) -cne [string]$manifest.TaskHash){
        throw 'SENSOR_JOURNAL_TASK_XML_HASH_MISMATCH'
    }
    $allowed=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($n in @('READY','manifest.json','task.xml')){[void]$allowed.Add((Join-Path $Root $n))}
    [void]$allowed.Add((Join-Path $Root 'files'))
    # R309 terminal markers are known members, but only a valid bounded
    # marker and exact protected ownership may be accepted.
    foreach($phase in @('COMMITTED','ROLLED_BACK')){
        $p=Join-Path $Root ($phase+'.terminal')
        if([IO.File]::Exists($p)){
            Assert-SensorJournalTrustedAcl $p $false
            if([IO.File]::ReadAllText($p,[Text.Encoding]::ASCII) -cne
               ('TBME_SENSOR_'+$phase+'_V1')){
                throw 'SENSOR_JOURNAL_UNKNOWN_TERMINAL_MARKER'
            }
            [void]$allowed.Add($p)
        }
    }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if(@($manifest.Files).Count -gt 128){throw 'SENSOR_JOURNAL_SNAPSHOT_COUNT_INVALID'}
    [long]$total=0
    foreach($row in @($manifest.Files)){
        $rel=[string]$row.Rel
        Assert-SensorJournalRelative $rel
        if(-not $seen.Add($rel)){throw 'SENSOR_JOURNAL_DUPLICATE_SNAPSHOT'}
        $path=Join-Path (Join-Path $Root 'files') $rel
        Assert-SensorJournalTrustedAcl $path $false
        $blob=[IO.File]::ReadAllBytes($path)
        $total+=$blob.Length
        if($blob.Length -gt 16777216 -or $total -gt 67108864 -or
           $blob.Length -ne [long]$row.Length -or
           (Get-SensorJournalHash $blob) -cne [string]$row.Hash){
            throw 'SENSOR_JOURNAL_SNAPSHOT_HASH_MISMATCH'
        }
        [void]$allowed.Add($path)
        $parent=[IO.Path]::GetDirectoryName($path)
        while($parent.StartsWith((Join-Path $Root 'files')+'\',[StringComparison]::OrdinalIgnoreCase)){
            [void]$allowed.Add($parent)
            $parent=[IO.Path]::GetDirectoryName($parent)
        }
    }
    if(-not [IO.Directory]::Exists((Join-Path $Root 'files'))){
        throw 'SENSOR_JOURNAL_FILES_DIRECTORY_MISSING'
    }
    # Check each child before recursing; never follow a junction while merely
    # enumerating the rollback journal (PowerShell provider behavior varies).
    $pending=[Collections.Generic.List[string]]::new()
    $pending.Add($Root)
    while($pending.Count -gt 0){
        $directory=$pending[$pending.Count-1]
        $pending.RemoveAt($pending.Count-1)
        Assert-SensorBoundaryNoReparse $directory
        foreach($member in [IO.Directory]::GetFileSystemEntries($directory)){
            $full=[IO.Path]::GetFullPath($member)
            $attrs=[IO.File]::GetAttributes($full)
            if(($attrs -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                throw 'SENSOR_JOURNAL_REPARSE_MEMBER'
            }
            if(-not $allowed.Contains($full)){
                throw 'SENSOR_JOURNAL_UNKNOWN_MEMBER'
            }
            if(($attrs -band [IO.FileAttributes]::Directory) -ne 0){
                $pending.Add($full)
            }
        }
    }
    return $manifest
}
function New-SensorDurableJournal(
    [string]$Root,[string]$Sid,[object[]]$Rows,[string]$TaskXml,
    [string[]]$NewNames,[bool]$OldRootPresent
){
    $token=[Security.Principal.WindowsIdentity]::GetCurrent().User
    if($null -eq $token -or $token.Value -cne $Sid){
        throw 'SENSOR_JOURNAL_TOKEN_MISMATCH'
    }
    Assert-SensorBoundaryNoReparse $Root
    if(Test-Path -LiteralPath $Root){throw 'SENSOR_JOURNAL_ALREADY_EXISTS'}
    $parent=[IO.Path]::GetDirectoryName($Root)
    Assert-SensorJournalTrustedAcl $parent $false
    $all=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if(@($Rows).Count -gt 128 -or @($NewNames).Count -gt 64){
        throw 'SENSOR_JOURNAL_INVENTORY_TOO_LARGE'
    }
    $index=[Collections.Generic.List[object]]::new()
    [long]$sum=0
    foreach($r in @($Rows)){
        $rel=[string]$r.Rel
        Assert-SensorJournalRelative $rel
        if(-not $all.Add($rel)){throw 'SENSOR_JOURNAL_DUPLICATE_ORIGINAL'}
        $payload=[byte[]]$r.Data
        $sum+=$payload.Length
        if($payload.Length -gt 16777216 -or $sum -gt 67108864){
            throw 'SENSOR_JOURNAL_TOO_LARGE'
        }
        $index.Add([pscustomobject]@{Rel=$rel;Length=$payload.Length;Hash=(Get-SensorJournalHash $payload)})
    }
    $newList=[Collections.Generic.List[string]]::new()
    $newSeen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($name in $NewNames){
        Assert-SensorJournalRelative $name
        if(-not $newSeen.Add($name)){throw 'SENSOR_JOURNAL_DUPLICATE_NEXT_FILE'}
        $newList.Add($name)
    }
    $xml=[Text.Encoding]::UTF8.GetBytes([string]$TaskXml)
    if($xml.Length -gt 262144){throw 'SENSOR_JOURNAL_XML_TOO_LARGE'}
    $admins=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $system=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $acl=[Security.AccessControl.DirectorySecurity]::new()
    $acl.SetOwner($admins)
    $acl.SetAccessRuleProtection($true,$false)
    foreach($principal in @($admins,$system)){
        $ace=[Security.AccessControl.FileSystemAccessRule]::new(
            $principal,[Security.AccessControl.FileSystemRights]::FullControl,
            [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow)
        [void]$acl.AddAccessRule($ace)
    }
    [void][IO.Directory]::CreateDirectory($Root,$acl)
    Assert-SensorJournalTrustedAcl $Root $true
    [void][IO.Directory]::CreateDirectory((Join-Path $Root 'files'))
    Assert-SensorJournalTrustedAcl (Join-Path $Root 'files') $false
    foreach($r in @($Rows)){
        Write-SensorJournalUnique $Root ('files\'+[string]$r.Rel) ([byte[]]$r.Data)
    }
    Write-SensorJournalUnique $Root 'task.xml' $xml
    $manifest=[ordered]@{
        Schema=1;Phase='PREPARED';Sid=$Sid;OldRootPresent=$OldRootPresent
        TaskPresent=($xml.Length -gt 0);TaskHash=(Get-SensorJournalHash $xml)
        Files=@($index);ExpectedNewFiles=@($newList)
    }
    $json=[Text.Encoding]::UTF8.GetBytes(($manifest|ConvertTo-Json -Depth 6 -Compress))
    if($json.Length -gt 65536){throw 'SENSOR_JOURNAL_MANIFEST_TOO_LARGE'}
    Write-SensorJournalUnique $Root 'manifest.json' $json
    # READY is written and flushed LAST, before any service/task mutation.
    Write-SensorJournalUnique $Root 'READY' ([Text.Encoding]::ASCII.GetBytes('TBME_SENSOR_READY_V1'))
    $verified=Assert-SensorDurableJournal $Root $Sid
    if($verified.Phase -cne 'PREPARED'){throw 'SENSOR_JOURNAL_READY_READBACK_FAILED'}
}

# R309: terminal state and byte-exact file replay are designed as replayable,
# bounded operations. Scheduled Task XML restoration/actual protected UAC
# recovery are separate acceptance gates; this file-only primitive must
# never be interpreted as proof of task/service recovery.
function Get-SensorJournalTerminal([string]$Root,[string]$Sid){
    # R309: bind all phase/replay calls to the actual effective Windows
    # token, not merely to a caller-provided or journal-stored SID.
    $effective=[Security.Principal.WindowsIdentity]::GetCurrent()
    if($null -eq $effective -or $null -eq $effective.User -or
       -not [string]::Equals([string]$effective.User.Value,$Sid,[StringComparison]::OrdinalIgnoreCase)){
        throw 'SENSOR_JOURNAL_EFFECTIVE_TOKEN_SID_MISMATCH'
    }
    [void](Assert-SensorDurableJournal $Root $Sid)
    $found=''
    foreach($phase in @('COMMITTED','ROLLED_BACK')){
        $path=Join-Path $Root ($phase+'.terminal')
        if(-not [IO.File]::Exists($path)){continue}
        Assert-SensorJournalTrustedAcl $path $false
        $expected='TBME_SENSOR_'+$phase+'_V1'
        if([IO.File]::ReadAllText($path,[Text.Encoding]::ASCII) -cne $expected){
            throw 'SENSOR_JOURNAL_UNTRUSTED_TERMINAL_MARKER'
        }
        if($found){throw 'SENSOR_JOURNAL_CONFLICTING_TERMINAL_PHASE'}
        $found=$phase
    }
    if(!$found){return 'PREPARED'}
    return $found
}
function Write-SensorJournalTerminal([string]$Root,[string]$Sid,[string]$Phase){
    if($Phase -cne 'COMMITTED' -and $Phase -cne 'ROLLED_BACK'){
        throw 'SENSOR_JOURNAL_TERMINAL_PHASE_NOT_ALLOWED'
    }
    $current=Get-SensorJournalTerminal $Root $Sid
    if($current -ceq $Phase){return}
    if($current -cne 'PREPARED'){throw 'SENSOR_JOURNAL_TERMINAL_CONFLICT'}
    $target=Join-Path $Root ($Phase+'.terminal')
    $bytes=[Text.Encoding]::ASCII.GetBytes('TBME_SENSOR_'+$Phase+'_V1')
    Write-SensorJournalUnique $Root ($Phase+'.terminal') $bytes
    if([IO.File]::ReadAllText($target,[Text.Encoding]::ASCII) -cne
       ('TBME_SENSOR_'+$Phase+'_V1')){
        throw 'SENSOR_JOURNAL_TERMINAL_DURABLE_READBACK'
    }
    if((Get-SensorJournalTerminal $Root $Sid) -cne $Phase){
        throw 'SENSOR_JOURNAL_TERMINAL_STATE_READBACK'
    }
}
function Restore-SensorJournalOldFilesOnly(
    [string]$Root,[string]$Sid,[string]$LiveRoot,
    [object]$PinnedBrokerLease=$null
){
    $state=Get-SensorJournalTerminal $Root $Sid
    if($state -cne 'PREPARED' -and $state -cne 'ROLLED_BACK'){
        throw 'SENSOR_JOURNAL_REPLAY_REQUIRES_PREPARED_STATE'
    }
    $manifest=Assert-SensorDurableJournal $Root $Sid
    # Cache and verify every snapshot and prior task XML BEFORE any live
    # synthetic file changes. Never reread saved bytes after validation.
    $prior=[Collections.Generic.List[object]]::new()
    $original=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [long]$total=0
    foreach($row in @($manifest.Files)){
        $rel=[string]$row.Rel
        Assert-SensorJournalRelative $rel
        if(-not $original.Add($rel)){throw 'SENSOR_JOURNAL_DUPLICATE_ORIGINAL'}
        $path=Join-Path (Join-Path $Root 'files') $rel
        Assert-SensorJournalTrustedAcl $path $false
        $fs=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
        try{
            if($fs.Length -ne [long]$row.Length -or $fs.Length -gt 16777216){
                throw 'SENSOR_JOURNAL_REPLAY_SIZE_INVALID'
            }
            $total+=$fs.Length
            if($total -gt 67108864){throw 'SENSOR_JOURNAL_REPLAY_TOTAL_INVALID'}
            $bytes=[byte[]]::new([int]$fs.Length)
            $position=0
            while($position -lt $bytes.Length){
                $got=$fs.Read($bytes,$position,$bytes.Length-$position)
                if($got -lt 1){throw 'SENSOR_JOURNAL_REPLAY_SHORT_READ'}
                $position+=$got
            }
            if((Get-SensorJournalHash $bytes) -cne [string]$row.Hash){
                throw 'SENSOR_JOURNAL_REPLAY_SHA_MISMATCH'
            }
            $prior.Add([pscustomobject]@{Rel=$rel;Bytes=$bytes;Sha=[string]$row.Hash})
        }finally{$fs.Dispose()}
    }
    $xmlPath=Join-Path $Root 'task.xml'
    Assert-SensorJournalTrustedAcl $xmlPath $false
    $xml=[IO.File]::ReadAllBytes($xmlPath)
    if($xml.Length -gt 262144 -or
       (Get-SensorJournalHash $xml) -cne [string]$manifest.TaskHash){
        throw 'SENSOR_JOURNAL_REPLAY_XML_SHA_INVALID'
    }
    # Validate an EXACT allowlist for the live tree before a single delete
    # or overwrite. Real privileged service/task mutation is never executed
    # by this primitive and must be guarded at its own ownership boundary.
    $known=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($item in @($manifest.ExpectedNewFiles)){
        $rel=[string]$item
        Assert-SensorJournalRelative $rel
        if(-not $known.Add($rel)){throw 'SENSOR_JOURNAL_REPLAY_DUPLICATE_NEW'}
    }
    foreach($item in $prior){[void]$known.Add([string]$item.Rel)}
    $dirs=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($rel in $known){
        $parts=$rel.Split('\')
        for($k=1;$k -lt $parts.Length;$k++){
            [void]$dirs.Add(($parts[0..($k-1)] -join '\'))
        }
    }
    Assert-SensorBoundaryNoReparse $LiveRoot
    if([IO.Directory]::Exists($LiveRoot)){
        $prefix=[IO.Path]::GetFullPath($LiveRoot).TrimEnd('\')+'\'
        $pending=[Collections.Generic.List[string]]::new()
        $pending.Add($LiveRoot)
        while($pending.Count){
            $directory=$pending[$pending.Count-1]
            $pending.RemoveAt($pending.Count-1)
            Assert-SensorBoundaryNoReparse $directory
            foreach($member in [IO.Directory]::GetFileSystemEntries($directory)){
                $full=[IO.Path]::GetFullPath($member)
                $attrs=[IO.File]::GetAttributes($full)
                if(($attrs -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                    throw 'SENSOR_JOURNAL_REPLAY_LIVE_REPARSE_REFUSED'
                }
                if(-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){
                    throw 'SENSOR_JOURNAL_REPLAY_LIVE_PATH_ESCAPE'
                }
                $rel=$full.Substring($prefix.Length)
                if(($attrs -band [IO.FileAttributes]::Directory) -ne 0){
                    if(-not $dirs.Contains($rel)){
                        throw 'SENSOR_JOURNAL_REPLAY_UNKNOWN_DIRECTORY'
                    }
                    $pending.Add($full)
                }elseif(-not $known.Contains($rel)){
                    throw 'SENSOR_JOURNAL_REPLAY_UNKNOWN_FILE'
                }
            }
        }
    }
    # R349: acquire native READ/WRITE, NO SHARE_WRITE/DELETE, no-reparse
    # handles for every original leaf BEFORE the first rollback write.  The
    # lease stays open across original Task restoration and journal terminal
    # cleanup in the caller. Any privileged pre-opened writer or DELETE handle
    # causes a fail-closed error while PREPARED remains intact.
    if($null -ne $PinnedBrokerLease){
        if(-not $PinnedBrokerLease.IsPinned){
            throw 'SENSOR_REPLAY_LEAF_BROKER_PARENT_LEASE_LOST'
        }
        foreach($entry in $prior){
            $null=$PinnedBrokerLease.OpenReplayLeaf([string]$entry.Rel)
        }
    }
    # Stage validated originals back into the live synthetic tree.
    # A process death mid-copy leaves READY and intact old snapshots, so a
    # subsequent same-account invocation can resume. This isn't an atomic
    # multi-file transaction or proof of OS power-cut durability.
    if(-not [IO.Directory]::Exists($LiveRoot)){
        [void][IO.Directory]::CreateDirectory($LiveRoot)
    }
    foreach($entry in $prior){
        $dest=Join-Path $LiveRoot $entry.Rel
        $parent=[IO.Path]::GetDirectoryName($dest)
        Assert-SensorBoundaryNoReparse $dest
        [void][IO.Directory]::CreateDirectory($parent)
        Assert-SensorBoundaryNoReparse $dest
        if($null -ne $PinnedBrokerLease){
            $verifiedBytes=[byte[]]$PinnedBrokerLease.ReplaceReplayLeaf(
                [string]$entry.Rel,[byte[]]$entry.Bytes)
        }else{
            [IO.File]::WriteAllBytes($dest,[byte[]]$entry.Bytes)
            $verifiedBytes=[IO.File]::ReadAllBytes($dest)
        }
        if((Get-SensorJournalHash $verifiedBytes) -cne $entry.Sha){
            throw 'SENSOR_JOURNAL_REPLAY_WRITE_SHA_FAILED'
        }
    }
    foreach($rel in $known){
        if($original.Contains($rel)){continue}
        $dest=Join-Path $LiveRoot $rel
        Assert-SensorBoundaryNoReparse $dest
        if([IO.File]::Exists($dest)){[IO.File]::Delete($dest)}
    }
    foreach($entry in $prior){
        $dest=Join-Path $LiveRoot $entry.Rel
        if($null -ne $PinnedBrokerLease){
            $bytes=[byte[]]$PinnedBrokerLease.ReadReplayLeaf([string]$entry.Rel)
        }else{
            if(-not [IO.File]::Exists($dest)){
                throw 'SENSOR_JOURNAL_REPLAY_FINAL_MISSING_FILE'
            }
            $bytes=[IO.File]::ReadAllBytes($dest)
        }
        if((Get-SensorJournalHash $bytes) -cne $entry.Sha){
            throw 'SENSOR_JOURNAL_REPLAY_FINAL_SHA_FAILED'
        }
    }
    # R337: a first protected-sensor installation has NO previous BrokerRoot.
    # A killed helper may leave only newly added nested files and directories.
    # After validated snapshot replay and allowlisted file deletion, remove
    # ONLY now-empty known directories, deepest first, using nonrecursive
    # Directory.Delete. Refuse any surprise member or reparse point. Keeping
    # an empty unowned BrokerRoot would block the next same-owner repair.
    if(-not [bool]$manifest.OldRootPresent){
        if($prior.Count -ne 0){
            throw 'SENSOR_JOURNAL_ABSENT_OLD_ROOT_HAS_SNAPSHOT_FILES'
        }
        foreach($relDir in @($dirs | Sort-Object Length -Descending)){
            $emptyDir=Join-Path $LiveRoot $relDir
            Assert-SensorBoundaryNoReparse $emptyDir
            if([IO.Directory]::Exists($emptyDir)){
                [IO.Directory]::Delete($emptyDir,$false)
            }
        }
        Assert-SensorBoundaryNoReparse $LiveRoot
        if([IO.Directory]::Exists($LiveRoot)){
            [IO.Directory]::Delete($LiveRoot,$false)
        }
    }
    return [Text.Encoding]::UTF8.GetString($xml)
}

# R310: terminal journal cleanup is a separate, bounded state machine.
# Never recursively delete or follow a reparse member. Retire the complete
# terminal journal to a fixed sibling before deleting any saved old bytes.
function Assert-SensorRetiredJournalSafe([string]$Retired,[string]$Sid){
    Assert-SensorJournalTrustedAcl $Retired $true
    $effective=[Security.Principal.WindowsIdentity]::GetCurrent()
    if($null -eq $effective -or $null -eq $effective.User -or
       -not [string]::Equals($effective.User.Value,$Sid,[StringComparison]::OrdinalIgnoreCase)){
        throw 'SENSOR_RETIRED_JOURNAL_WRONG_EFFECTIVE_TOKEN'
    }
    $members=@([IO.Directory]::GetFileSystemEntries($Retired))
    if($members.Count -eq 0){return $null}
    $phase=''
    $marker=''
    foreach($p in @('COMMITTED','ROLLED_BACK')){
        $file=Join-Path $Retired ($p+'.terminal')
        Assert-SensorBoundaryNoReparse $file
        if(-not [IO.File]::Exists($file)){continue}
        Assert-SensorJournalTrustedAcl $file $false
        if([IO.File]::ReadAllText($file,[Text.Encoding]::ASCII) -cne
           ('TBME_SENSOR_'+$p+'_V1')){
            throw 'SENSOR_RETIRED_JOURNAL_BAD_TERMINAL'
        }
        if($phase){throw 'SENSOR_RETIRED_JOURNAL_TWO_TERMINALS'}
        $phase=$p
        $marker=$file
    }
    if(!$phase){throw 'SENSOR_RETIRED_JOURNAL_NO_TERMINAL'}
    $allowed=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [void]$allowed.Add($marker)
    $manifestFile=Join-Path $Retired 'manifest.json'
    $saved=@()
    if([IO.File]::Exists($manifestFile)){
        Assert-SensorJournalTrustedAcl $manifestFile $false
        if(([IO.FileInfo]::new($manifestFile)).Length -gt 65536){
            throw 'SENSOR_RETIRED_JOURNAL_MANIFEST_OVERSIZE'
        }
        $m=[IO.File]::ReadAllText($manifestFile,[Text.Encoding]::UTF8)|ConvertFrom-Json
        if($m.Schema -ne 1 -or $m.Phase -cne 'PREPARED' -or
           $m.Sid -cne $Sid){throw 'SENSOR_RETIRED_JOURNAL_MANIFEST_OWNER_PHASE'}
        if(@($m.Files).Count -gt 128 -or @($m.ExpectedNewFiles).Count -gt 64){
            throw 'SENSOR_RETIRED_JOURNAL_INVENTORY_SIZE'
        }
        $known=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $paths=[Collections.Generic.List[string]]::new()
        foreach($row in @($m.Files)){
            $rel=[string]$row.Rel
            Assert-SensorJournalRelative $rel
            if(-not $known.Add($rel)){throw 'SENSOR_RETIRED_JOURNAL_DUPLICATE_ENTRY'}
            $path=Join-Path (Join-Path $Retired 'files') $rel
            $paths.Add($path)
            [void]$allowed.Add($path)
            $dir=[IO.Path]::GetDirectoryName($path)
            $prefix=(Join-Path $Retired 'files')
            while($dir.StartsWith($prefix+'\', [StringComparison]::OrdinalIgnoreCase)){
                [void]$allowed.Add($dir)
                $dir=[IO.Path]::GetDirectoryName($dir)
            }
        }
        $saved=@($paths.ToArray())
        foreach($name in @('manifest.json','task.xml','READY','files')){
            [void]$allowed.Add((Join-Path $Retired $name))
        }
        # Terminal phase is published only after a fully verified snapshot.
        # During cleanup any subset of previously saved files may be absent,
        # but an unknown added file must still prevent destructive progress.
    }
    # Validate every present member before deleting anything.
    $stack=[Collections.Generic.List[string]]::new()
    $stack.Add($Retired)
    while($stack.Count){
        $dir=$stack[$stack.Count-1]
        $stack.RemoveAt($stack.Count-1)
        Assert-SensorBoundaryNoReparse $dir
        foreach($item in [IO.Directory]::GetFileSystemEntries($dir)){
            $full=[IO.Path]::GetFullPath($item)
            $attributes=[IO.File]::GetAttributes($full)
            if(($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                throw 'SENSOR_RETIRED_JOURNAL_REPARSE_REFUSED'
            }
            if(-not $allowed.Contains($full)){
                throw 'SENSOR_RETIRED_JOURNAL_UNKNOWN_MEMBER'
            }
            Assert-SensorJournalTrustedAcl $full $false
            if(($attributes -band [IO.FileAttributes]::Directory) -ne 0){
                $stack.Add($full)
            }
        }
    }
    return [pscustomobject]@{Phase=$phase;Marker=$marker;Manifest=[IO.File]::Exists($manifestFile);Saved=$saved}
}
function Finish-SensorRetiredJournal([string]$Retired,[string]$Sid){
    if(-not [IO.Directory]::Exists($Retired)){return}
    $info=Assert-SensorRetiredJournalSafe $Retired $Sid
    if($null -eq $info){
        [IO.Directory]::Delete($Retired,$false)
        return
    }
    if($info.Manifest){
        foreach($path in @($info.Saved)){
            Assert-SensorBoundaryNoReparse $path
            if([IO.File]::Exists($path)){
                Assert-SensorJournalTrustedAcl $path $false
                [IO.File]::Delete($path)
            }
        }
        $files=Join-Path $Retired 'files'
        if([IO.Directory]::Exists($files)){
            $folders=[Collections.Generic.List[string]]::new()
            $pending=[Collections.Generic.List[string]]::new()
            $pending.Add($files)
            while($pending.Count){
                $current=$pending[$pending.Count-1]
                $pending.RemoveAt($pending.Count-1)
                $folders.Add($current)
                foreach($entry in [IO.Directory]::GetFileSystemEntries($current)){
                    $attrs=[IO.File]::GetAttributes($entry)
                    if(($attrs -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                        throw 'SENSOR_RETIRED_JOURNAL_REPARSE_REFUSED'
                    }
                    if(($attrs -band [IO.FileAttributes]::Directory) -ne 0){
                        $pending.Add($entry)
                    }else{
                        throw 'SENSOR_RETIRED_JOURNAL_NONEMPTY_FILES_DIR'
                    }
                }
            }
            $order=@($folders|Sort-Object Length -Descending)
            foreach($dir in $order){
                Assert-SensorBoundaryNoReparse $dir
                [IO.Directory]::Delete($dir,$false)
            }
        }
        foreach($name in @('task.xml','READY','manifest.json')){
            $path=Join-Path $Retired $name
            Assert-SensorBoundaryNoReparse $path
            if([IO.File]::Exists($path)){
                Assert-SensorJournalTrustedAcl $path $false
                [IO.File]::Delete($path)
            }
        }
    }
    # Once manifest is gone ONLY the verified terminal marker may remain.
    $remaining=@([IO.Directory]::GetFileSystemEntries($Retired))
    if($remaining.Count -ne 1 -or
       -not [string]::Equals($remaining[0],$info.Marker,[StringComparison]::OrdinalIgnoreCase)){
        throw 'SENSOR_RETIRED_JOURNAL_CLEANUP_HAS_UNKNOWN_RESIDUE'
    }
    Assert-SensorJournalTrustedAcl $info.Marker $false
    [IO.File]::Delete($info.Marker)
    [IO.Directory]::Delete($Retired,$false)
}
function Finish-SensorTerminalJournal([string]$Root,[string]$Sid){
    $root=[IO.Path]::GetFullPath($Root)
    $retired=$root+'-retired'
    if(-not [string]::Equals([IO.Path]::GetDirectoryName($root),
                            [IO.Path]::GetDirectoryName($retired),
                            [StringComparison]::OrdinalIgnoreCase)){
        throw 'SENSOR_JOURNAL_RETIRED_DIFFERENT_PARENT'
    }
    Assert-SensorBoundaryNoReparse $root
    Assert-SensorBoundaryNoReparse $retired
    # Always finish a previously retired journal first. If it fails, do not
    # touch active journal or any protected Broker bytes.
    if([IO.Directory]::Exists($retired)){
        Finish-SensorRetiredJournal $retired $Sid
    }
    if(-not [IO.Directory]::Exists($root)){return}
    $terminal=Get-SensorJournalTerminal $root $Sid
    if($terminal -ne 'COMMITTED' -and $terminal -ne 'ROLLED_BACK'){
        throw 'SENSOR_JOURNAL_NOT_TERMINAL_DO_NOT_RETIRE'
    }
    if([IO.Directory]::Exists($retired)){throw 'SENSOR_JOURNAL_RETIRED_COLLISION'}
    [IO.Directory]::Move($root,$retired)
    Finish-SensorRetiredJournal $retired $Sid
}

# R311 integrates already-tested R309/R310 terminal machinery into the
# normal protected install success path, not into unverified task restoration.
function Resume-SensorCompletedJournal([string]$Root,[string]$Sid){
    Assert-SensorBoundaryNoReparse $Root
    Assert-SensorBoundaryNoReparse ($Root+'-retired')
    # R310 prioritizes finishing a prior retired state. Then an active,
    # uncommitted PREPARED state MUST fail closed, never guessed complete.
    Finish-SensorTerminalJournal $Root $Sid
    if([IO.Directory]::Exists($Root) -or [IO.Directory]::Exists($Root+'-retired')){
        throw 'SENSOR_JOURNAL_RECOVERY_REQUIRED'
    }
}
function Complete-HealthySensorJournal(
    [string]$Root,[string]$Sid,[bool]$TaskInstalled,[bool]$SupervisorHealthy
){
    if(-not $TaskInstalled -or -not $SupervisorHealthy){
        throw 'SENSOR_JOURNAL_SUPERVISOR_NOT_HEALTHY_NO_COMMIT'
    }
    $effective=[Security.Principal.WindowsIdentity]::GetCurrent()
    if($null -eq $effective -or $null -eq $effective.User -or
       -not [string]::Equals([string]$effective.User.Value,$Sid,[StringComparison]::OrdinalIgnoreCase)){
        throw 'SENSOR_JOURNAL_COMMIT_EFFECTIVE_SID_MISMATCH'
    }
    $phase=Get-SensorJournalTerminal $Root $Sid
    if($phase -cne 'PREPARED'){
        throw 'SENSOR_JOURNAL_COMMIT_NONPREPARED_REFUSED'
    }
    Write-SensorJournalTerminal $Root $Sid 'COMMITTED'
    # A crash after writing COMMITTED is recoverable by the entrypoint
    # above; a crash during retirement is recoverable by R310's bounded
    # nonrecursive retired journal cleanup.
    Finish-SensorTerminalJournal $Root $Sid
    if([IO.Directory]::Exists($Root) -or [IO.Directory]::Exists($Root+'-retired')){
        throw 'SENSOR_JOURNAL_COMMIT_RETIRE_RESIDUE'
    }
}

# R312: replaying a prior Scheduled Task XML can register executable actions.
# Only the exact prior same-SID LogonTrigger and pinned Supervisor Exec are
# allowed. Never permit RegistrationTrigger, alternate command or XML DTD.
function Resolve-SensorPriorTaskPrincipalSid([string]$name){
 if([string]::IsNullOrWhiteSpace($name)){throw 'SENSOR_JOURNAL_TASK_XML_EMPTY_IDENTITY'}
 if($name -match '^S-1-5-(?:\d+-)+\d+$'){return $name}
 try{
  return [string]([Security.Principal.NTAccount]::new($name)).Translate(
   [Security.Principal.SecurityIdentifier]).Value
 }catch{throw 'SENSOR_JOURNAL_TASK_XML_IDENTITY_UNRESOLVABLE'}
}
function Assert-SensorTrustedOldTaskXml(
 [string]$Text,[string]$ExpectedSid,[string]$TrustedBrokerRoot,[string]$TrustedAppRoot
){
 if([string]::IsNullOrWhiteSpace($Text) -or $Text.Length -gt 262144){
  throw 'SENSOR_JOURNAL_TASK_XML_MISSING_OR_OVERSIZE'
 }
 if($ExpectedSid -cnotmatch '^S-1-5-21-(?:\d+-){3}\d+$'){
  throw 'SENSOR_JOURNAL_TASK_XML_EXPECTED_SID_UNTRUSTED'
 }
 $xml=[Xml.XmlDocument]::new()
 $xml.XmlResolver=$null
 $settings=[Xml.XmlReaderSettings]::new()
 $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit
 $settings.XmlResolver=$null
 $settings.MaxCharactersInDocument=262144
 $settings.MaxCharactersFromEntities=0
 $settings.IgnoreComments=$false
 $sr=[IO.StringReader]::new($Text)
 $reader=$null
 try{
  $reader=[Xml.XmlReader]::Create($sr,$settings)
  $xml.Load($reader)
 }finally{
  if($reader){$reader.Dispose()}
  $sr.Dispose()
 }
 $n=[Xml.XmlNamespaceManager]::new($xml.NameTable)
 $n.AddNamespace('t','http://schemas.microsoft.com/windows/2004/02/mit/task')
 if($null -eq $xml.DocumentElement -or
    $xml.DocumentElement.LocalName -cne 'Task' -or
    $xml.DocumentElement.NamespaceURI -cne 'http://schemas.microsoft.com/windows/2004/02/mit/task'){
  throw 'SENSOR_JOURNAL_TASK_XML_UNSUPPORTED_NAMESPACE'
 }
 $principals=@($xml.SelectNodes('/t:Task/t:Principals/t:Principal',$n))
 $actions=@($xml.SelectNodes('/t:Task/t:Actions/*',$n))
 $triggers=@($xml.SelectNodes('/t:Task/t:Triggers/*',$n))
 if($principals.Count -ne 1 -or $actions.Count -ne 1 -or
    $triggers.Count -ne 1 -or $actions[0].LocalName -cne 'Exec' -or
    $triggers[0].LocalName -cne 'LogonTrigger'){
  throw 'SENSOR_JOURNAL_TASK_XML_UNEXPECTED_ACTION_OR_TRIGGER'
 }
 $principal=$principals[0]
 $uid=$principal.SelectSingleNode('t:UserId',$n)
 $logon=$principal.SelectSingleNode('t:LogonType',$n)
 $run=$principal.SelectSingleNode('t:RunLevel',$n)
 if(!$uid -or !$logon -or !$run -or
    (Resolve-SensorPriorTaskPrincipalSid ([string]$uid.InnerText)) -cne $ExpectedSid -or
    [string]$logon.InnerText -cne 'InteractiveToken' -or
    [string]$run.InnerText -cne 'HighestAvailable'){
  throw 'SENSOR_JOURNAL_TASK_XML_FOREIGN_PRINCIPAL_OR_PRIVILEGES'
 }
 $triggerUid=$triggers[0].SelectSingleNode('t:UserId',$n)
 if(!$triggerUid -or
    (Resolve-SensorPriorTaskPrincipalSid ([string]$triggerUid.InnerText)) -cne $ExpectedSid){
  throw 'SENSOR_JOURNAL_TASK_XML_WRONG_LOGON_USER'
 }
 $exe=$actions[0]
 $command=$exe.SelectSingleNode('t:Command',$n)
 $args=$exe.SelectSingleNode('t:Arguments',$n)
 if(!$command -or !$args -or $exe.SelectSingleNode('t:WorkingDirectory',$n)){
  throw 'SENSOR_JOURNAL_TASK_XML_EXEC_SHAPE_UNEXPECTED'
 }
 $expectedExe=Join-Path $TrustedBrokerRoot 'TaskbarMonitorSensorSupervisor.exe'
 $expectedBroker=Join-Path $TrustedBrokerRoot 'TaskbarMonitorSensorBroker.exe'
 $expectedOutput=Join-Path $TrustedAppRoot 'cpu_temp_broker.json'
 $expectedArgs='--broker "'+$expectedBroker+'" --output "'+$expectedOutput+'"'
 if(-not [string]::Equals([string]$command.InnerText,$expectedExe,[StringComparison]::OrdinalIgnoreCase) -or
    -not [string]::Equals([string]$args.InnerText,$expectedArgs,[StringComparison]::OrdinalIgnoreCase)){
  throw 'SENSOR_JOURNAL_TASK_XML_EXEC_NOT_PINNED'
 }
 $uri=$xml.SelectSingleNode('/t:Task/t:RegistrationInfo/t:URI',$n)
 if($uri -and [string]$uri.InnerText -cne '\TaskbarMonitorEnhanced Sensor Broker'){
  throw 'SENSOR_JOURNAL_TASK_XML_URI_UNPINNED'
 }
 if($principal.SelectSingleNode('t:GroupId',$n)){
  throw 'SENSOR_JOURNAL_TASK_XML_GROUP_PRINCIPAL_FORBIDDEN'
 }
 if($xml.SelectSingleNode('/t:Task/t:RegistrationInfo/t:SecurityDescriptor',$n)){
  throw 'SENSOR_JOURNAL_TASK_XML_EMBEDDED_SECURITY_DESCRIPTOR_REFUSED'
 }
 return $true
}

# R314: isolated experimental cold replay of a fully validated PREPARED
# journal and its prior ScheduledTask XML. The production entrypoint remains
# fail-closed until a separate actual elevated-helper death test is accepted.
function Test-SensorOwnedTaskRegistration(
    [string]$TaskName,[string]$ExpectedSid,[string]$TrustedBrokerRoot,[string]$TrustedAppRoot
){
    if([string]::IsNullOrWhiteSpace($TaskName) -or $TaskName.Length -gt 100 -or
       $TaskName -notmatch '^[A-Za-z0-9 _-]+$'){
        throw 'SENSOR_COLD_TASK_INVALID_NAME'
    }
    Import-Module ScheduledTasks -ErrorAction Stop
    $existing=@(Get-ScheduledTask -TaskPath '\' -TaskName $TaskName -ErrorAction SilentlyContinue|
        Where-Object {$null -ne $_})
    if($existing.Count -gt 1){throw 'SENSOR_COLD_TASK_DUPLICATE_NAME'}
    if($existing.Count -eq 0){return $false}
    $task=$existing[0]
    $sid=Resolve-SensorPriorTaskPrincipalSid ([string]$task.Principal.UserId)
    if($sid -cne $ExpectedSid -or
       @($task.Actions).Count -ne 1 -or
       @($task.Triggers).Count -ne 1){
        throw 'SENSOR_COLD_TASK_PRINCIPAL_OR_SHAPE_MISMATCH'
    }
    $expectedExe=Join-Path $TrustedBrokerRoot 'TaskbarMonitorSensorSupervisor.exe'
    $expectedArgs='--broker "'+(Join-Path $TrustedBrokerRoot 'TaskbarMonitorSensorBroker.exe')+
        '" --output "'+(Join-Path $TrustedAppRoot 'cpu_temp_broker.json')+'"'
    if(-not [string]::Equals([string]$task.Actions[0].Execute,$expectedExe,[StringComparison]::OrdinalIgnoreCase) -or
       -not [string]::Equals([string]$task.Actions[0].Arguments,$expectedArgs,[StringComparison]::OrdinalIgnoreCase)){
        throw 'SENSOR_COLD_TASK_UNTRUSTED_EXISTING_ACTION'
    }
    # Export and validate all privilege-bearing XML fields, including
    # highest runlevel, interactive logon and trigger UserId.
    $currentXml=[string](Export-ScheduledTask -TaskPath '\' -TaskName $TaskName -ErrorAction Stop)
    if($TaskName -cne 'TaskbarMonitorEnhanced Sensor Broker'){
        # Test-only URI variation: the real task must always use its fixed
        # URI; hosted ephemeral tests are named explicitly and never started.
        $xmlDoc=[Xml.XmlDocument]::new()
        $xmlDoc.XmlResolver=$null
        $settings=[Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver=$null
        $settings.MaxCharactersInDocument=262144
        $sr=[IO.StringReader]::new($currentXml)
        $reader=$null
        try{
            $reader=[Xml.XmlReader]::Create($sr,$settings)
            $xmlDoc.Load($reader)
        }finally{if($reader){$reader.Dispose()};$sr.Dispose()}
        $namespace=[Xml.XmlNamespaceManager]::new($xmlDoc.NameTable)
        $namespace.AddNamespace('t','http://schemas.microsoft.com/windows/2004/02/mit/task')
        $uri=$xmlDoc.SelectSingleNode('/t:Task/t:RegistrationInfo/t:URI',$namespace)
        if($uri -and [string]$uri.InnerText -cne ('\'+$TaskName)){
            throw 'SENSOR_COLD_TASK_EPHEMERAL_URI_MISMATCH'
        }
        # Drop only the Scheduler-generated URI before passing it through
        # the exact production policy. No other XML fields are changed.
        if($uri){[void]$uri.ParentNode.RemoveChild($uri)}
        $currentXml=$xmlDoc.OuterXml
    }
    if(-not (Assert-SensorTrustedOldTaskXml $currentXml $ExpectedSid $TrustedBrokerRoot $TrustedAppRoot)){
        throw 'SENSOR_COLD_TASK_EXPORTED_XML_UNTRUSTED'
    }
    return $true
}
function Restore-SensorJournalPriorLayerAndTask(
    [string]$Journal,[string]$ExpectedSid,[string]$LiveBrokerRoot,
    [string]$TrustedAppRoot,[string]$TaskName
){
    # Trusted production code passes the fixed TaskName. The alternate
    # prefix is reserved exclusively for bounded disposable test fixtures;
    # never register a task under arbitrary string input.
    if($TaskName -cne 'TaskbarMonitorEnhanced Sensor Broker' -and
       $TaskName -cnotmatch '^TBME-R314-Disposable-[0-9]{5,20}-[AB]$'){
        throw 'SENSOR_COLD_TASK_NAME_NOT_ALLOWLISTED'
    }
    $effective=[Security.Principal.WindowsIdentity]::GetCurrent()
    if($null -eq $effective -or $null -eq $effective.User -or
       -not [string]::Equals([string]$effective.User.Value,$ExpectedSid,[StringComparison]::OrdinalIgnoreCase)){
        throw 'SENSOR_COLD_JOURNAL_EFFECTIVE_SID_MISMATCH'
    }
    if((Get-SensorJournalTerminal $Journal $ExpectedSid) -cne 'PREPARED'){
        throw 'SENSOR_COLD_JOURNAL_NOT_PREPARED'
    }
    $record=Assert-SensorDurableJournal $Journal $ExpectedSid
    $savedXmlFile=Join-Path $Journal 'task.xml'
    Assert-SensorJournalTrustedAcl $savedXmlFile $false
    $xmlBytes=[IO.File]::ReadAllBytes($savedXmlFile)
    if($xmlBytes.Length -gt 262144 -or
       (Get-SensorJournalHash $xmlBytes) -cne [string]$record.TaskHash){
        throw 'SENSOR_COLD_SAVED_TASK_XML_HASH_MISMATCH'
    }
    $oldXml=[Text.Encoding]::UTF8.GetString($xmlBytes)
    if([bool]$record.TaskPresent){
        if(-not (Assert-SensorTrustedOldTaskXml $oldXml $ExpectedSid $LiveBrokerRoot $TrustedAppRoot)){
            throw 'SENSOR_COLD_PRIOR_XML_POLICY_INVALID'
        }
    }elseif($oldXml.Length -gt 0){
        throw 'SENSOR_COLD_UNEXPECTED_SAVED_TASK_XML'
    }
    # Reject a foreign or altered live task BEFORE any files are changed.
    $previousTaskPresent=Test-SensorOwnedTaskRegistration $TaskName $ExpectedSid $LiveBrokerRoot $TrustedAppRoot
    # R347: the original old protected tree is known from the validated
    # journal. Pin ProgramFiles/product/Broker directory handles across both
    # file replay and Task XML restoration; no DELETE sharing is granted.
    # R337 first-install journals are intentionally excluded because the
    # expected old BrokerRoot is absent and must be deleted on rollback.
    $brokerDirectoryLease=$null
    if($TaskName -ceq 'TaskbarMonitorEnhanced Sensor Broker' -and
       [bool]$record.OldRootPresent){
        $brokerDirectoryLease=[TBMEProtectedBrokerLease]::new($LiveBrokerRoot)
        Assert-SensorJournalTrustedAcl $LiveBrokerRoot $false
    }
    try {
    # R309 prevalidates every saved file/hash, XML and all current live
    # member names before the first synthetic file write. Retrying after a
    # crash is safe for the same allowlisted bytes and expected task.
    $decoded=Restore-SensorJournalOldFilesOnly $Journal $ExpectedSid $LiveBrokerRoot $brokerDirectoryLease
    if(-not [string]::Equals($decoded,$oldXml,[StringComparison]::Ordinal)){
        throw 'SENSOR_COLD_REPLAY_XML_DATA_CHANGED'
    }
    if([bool]$record.TaskPresent){
        if(-not $previousTaskPresent){
            # A unique known task name is required absent, and we never
            # use -Force (which could overwrite an unrelated task).
            Register-ScheduledTask -TaskPath '\' -TaskName $TaskName -Xml $oldXml -ErrorAction Stop|Out-Null
        }
        if(-not (Test-SensorOwnedTaskRegistration $TaskName $ExpectedSid $LiveBrokerRoot $TrustedAppRoot)){
            throw 'SENSOR_COLD_REGISTERED_TASK_READBACK_INVALID'
        }
    }else{
        if($previousTaskPresent){
            Unregister-ScheduledTask -TaskPath '\' -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        }
        if(Test-SensorOwnedTaskRegistration $TaskName $ExpectedSid $LiveBrokerRoot $TrustedAppRoot){
            throw 'SENSOR_COLD_ABSENT_TASK_NOT_RESTORED'
        }
    }
    Write-SensorJournalTerminal $Journal $ExpectedSid 'ROLLED_BACK'
    Finish-SensorTerminalJournal $Journal $ExpectedSid
    if([IO.Directory]::Exists($Journal) -or [IO.Directory]::Exists($Journal+'-retired')){
        throw 'SENSOR_COLD_ROLLBACK_JOURNAL_RESIDUE'
    }
    }finally{
        if($null -ne $brokerDirectoryLease){$brokerDirectoryLease.Dispose()}
    }
}

# R315: verified cold replay is now callable from the trusted PE entrypoint
# before new protected sensor install/uninstall mutation. The operation stays
# fail-closed on another account, foreign global task, invalid journal or
# path/reparse ambiguity; no automatic destructive retry from user Temp.
function Resume-SensorPendingJournal(
    [string]$Journal,[string]$Sid,[string]$BrokerRoot,
    [string]$AppRoot,[string]$OwnedTaskName
){
    $effective=[Security.Principal.WindowsIdentity]::GetCurrent()
    if($null -eq $effective -or $null -eq $effective.User -or
       -not [string]::Equals([string]$effective.User.Value,$Sid,[StringComparison]::OrdinalIgnoreCase)){
        throw 'SENSOR_COLD_ENTRYPOINT_EFFECTIVE_TOKEN_SID_MISMATCH'
    }
    Assert-SensorBoundaryNoReparse $Journal
    Assert-SensorBoundaryNoReparse ($Journal+'-retired')
    if(-not [IO.Directory]::Exists($Journal)){
        # Only a fully terminal, trusted retired stage may be removed.
        Resume-SensorCompletedJournal $Journal $Sid
        return 'NONE_OR_TERMINAL_COMPLETED'
    }
    $phase=Get-SensorJournalTerminal $Journal $Sid
    if($phase -ne 'PREPARED'){
        Resume-SensorCompletedJournal $Journal $Sid
        return 'TERMINAL_COMPLETED'
    }
    $parent=[IO.Path]::GetDirectoryName($Journal)
    Assert-SensorJournalTrustedAcl $parent $false
    Assert-SensorBoundaryNoReparse $BrokerRoot
    if([IO.Directory]::Exists($BrokerRoot)){
        Assert-SensorJournalTrustedAcl $BrokerRoot $false
    }
    # The R314 replay function validates every saved file and the prior XML,
    # refuses alternate task actions/principal, restores old bytes, confirms
    # real Scheduler state, publishes ROLLED_BACK and retires known files.
    Restore-SensorJournalPriorLayerAndTask $Journal $Sid $BrokerRoot $AppRoot $OwnedTaskName
    if([IO.Directory]::Exists($Journal) -or [IO.Directory]::Exists($Journal+'-retired')){
        throw 'SENSOR_COLD_ENTRYPOINT_RESIDUAL_JOURNAL'
    }
    return 'PREVIOUS_LAYER_RESTORED'
}

function Capture-PreviousSensorLayer {
    try{
        Clear-SensorRollbackBuffer
        if(Test-Path -LiteralPath $BrokerRoot){
            $script:RollbackFiles=Get-SensorRollbackFiles $BrokerRoot
            $script:PreviousSensorLayerPresent=$true
        }
        Import-Module ScheduledTasks
        $task=Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if($task){
            $script:RollbackTaskXmlText=[string](Export-ScheduledTask -TaskName $TaskName)
            if([string]::IsNullOrWhiteSpace([string]$script:RollbackTaskXmlText) -or
               ([string]$script:RollbackTaskXmlText).Length -gt 262144){throw 'ROLLBACK_XML_MISSING_OR_TOO_LARGE'}
            $script:PreviousSensorLayerPresent=$true
        }
        $script:RollbackCaptured=$true
        Write-Log ("ROLLBACK_CAPTURE_PASS previous="+$PreviousSensorLayerPresent)
        return $true
    }catch{
        Clear-SensorRollbackBuffer
        Write-Log ('ROLLBACK_CAPTURE_FAIL '+$_.Exception.ToString())
        return $false
    }
}

function Restore-PreviousSensorLayer([string]$Reason){
    $script:RollbackPerformed=$true
    $script:RollbackSucceeded=$false
    try{
        Write-Log ("ROLLBACK_BEGIN reason="+$Reason+" previous="+$PreviousSensorLayerPresent)
        if(-not $RollbackCaptured){throw 'ROLLBACK_NOT_CAPTURED'}
        Get-Process TaskbarMonitorSensorSupervisor,TaskbarMonitorSensorBroker -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Remove-Item -LiteralPath $BrokerRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $LiveJson,$GpuJson,$StorageJson,$SupervisorState -Force -ErrorAction SilentlyContinue

        if(@($RollbackFiles).Count -gt 0){
            Restore-SensorRollbackFiles $BrokerRoot $RollbackFiles
        }
        if(-not [string]::IsNullOrEmpty($RollbackTaskXmlText)){
            Register-ScheduledTask -TaskName $TaskName -Xml $RollbackTaskXmlText -Force|Out-Null
            Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        }

        $script:ActiveArchitecture=$(if($PreviousSensorLayerPresent){'PREVIOUS_SENSOR_LAYER_RESTORED'}else{'NO_PROTECTED_SENSOR_LAYER'})
        $script:RollbackSucceeded=$true
        Write-Log ("ROLLBACK_PASS architecture="+$ActiveArchitecture)
        return $true
    }catch{
        $script:ActiveArchitecture='ROLLBACK_FAILED'
        Write-Log ('ROLLBACK_FAIL '+$_.Exception.ToString())
        return $false
    }
}

Write-Log "BEGIN mode=$Mode user=$UserId"

# R264-SENSOR-GUARD-BOUNDARY-BEGIN
# Before any shared task/process/file mutation, fail closed if a different
# Windows account owns the fixed legacy machinewide sensor task or processes.
# This is defensive per-account isolation, NOT a machinewide singleton policy.
function Resolve-SensorPrincipalSid([string]$AccountName){
    if([string]::IsNullOrWhiteSpace($AccountName)){throw 'EMPTY_SENSOR_PRINCIPAL'}
    if($AccountName -match '^S-1-5-(?:\d+-)+\d+$'){return $AccountName}
    $account=[Security.Principal.NTAccount]::new($AccountName)
    return [string]$account.Translate([Security.Principal.SecurityIdentifier]).Value
}
function Preserve-OtherUserSensorLayer([string]$Why){
    $script:ActiveArchitecture='SHARED_PROTECTED_SENSOR_LAYER_LEFT_UNTOUCHED'
    Write-Log ('CROSS_USER_SENSOR_SAFETY_REFUSAL reason='+$Why+' mode='+$Mode)
    Write-Result 'DEGRADED_OTHER_USER_SENSOR_LAYER_PRESERVED' ('Protected sensors were not changed: '+$Why+'. The per-user main app remains available with unavailable protected metrics as N/A.') 'NOT_STARTED' $null $false $false $false
    exit 0
}
try{
    $expectedUserSid=Resolve-SensorPrincipalSid $UserId
    Import-Module ScheduledTasks -ErrorAction Stop
    $lookupErrors=@()
    $existing=@(Get-ScheduledTask -TaskPath '\' -TaskName $TaskName -ErrorAction SilentlyContinue -ErrorVariable +lookupErrors |
        Where-Object {$null -ne $_})
    if(@($lookupErrors|Where-Object {$_.CategoryInfo.Category -ne [Management.Automation.ErrorCategory]::ObjectNotFound}).Count){
        throw 'TASK_SCHEDULER_LOOKUP_NOT_TRUSTED'
    }
    if($existing.Count -gt 1){throw 'MULTIPLE_GLOBAL_TASK_MATCHES'}
    if($existing.Count -eq 1){
        $oldSid=Resolve-SensorPrincipalSid ([string]$existing[0].Principal.UserId)
        if($oldSid -cne $expectedUserSid){
            Preserve-OtherUserSensorLayer 'ANOTHER_ACCOUNT_OWNS_GLOBAL_SCHEDULED_TASK'
        }
    }elseif(Test-Path -LiteralPath $BrokerRoot){
        # R344: Uninstall can be killed after deleting the owner marker but
        # before removing BrokerRoot (R343 native A/B reproduced this). Never
        # trust a markerless tree merely because the caller requests Uninstall.
        # Only an admin-owned, fully hashed PREPARED journal with the old owner
        # marker itself among its verified snapshots proves this same-account
        # partial deletion. Other modes/foreign roots continue to fail closed.
        Assert-SensorBoundaryNoReparse $SensorOwnerMarker
        if(-not (Test-Path -LiteralPath $SensorOwnerMarker -PathType Leaf)){
            $trustedPartialUninstall=$false
            if($Mode -ceq 'Uninstall' -and
               [IO.Directory]::Exists($SensorJournalRoot)){
                $pending=Assert-SensorDurableJournal $SensorJournalRoot $expectedUserSid
                $newList=@($pending.ExpectedNewFiles|Where-Object{$null -ne $_})
                $ownerRecords=@($pending.Files|Where-Object{
                    [string]$_.Rel -ceq '.tbme-owner.sid'
                })
                if([bool]$pending.OldRootPresent -and $newList.Count -eq 0 -and
                   $ownerRecords.Count -eq 1 -and
                   (Get-SensorJournalTerminal $SensorJournalRoot $expectedUserSid) -ceq 'PREPARED'){
                    $savedMarker=Join-Path (Join-Path $SensorJournalRoot 'files') '.tbme-owner.sid'
                    Assert-SensorJournalTrustedAcl $savedMarker $false
                    if([IO.File]::ReadAllText($savedMarker,[Text.Encoding]::ASCII).Trim() -ceq $expectedUserSid){
                        $trustedPartialUninstall=$true
                    }
                }
            }
            if(-not $trustedPartialUninstall){
                Preserve-OtherUserSensorLayer 'UNOWNED_SHARED_PROGRAMFILES_BROKER_WITHOUT_TASK'
            }
            Write-Log 'R344_SAME_OWNER_PREPARED_UNINSTALL_SNAPSHOT_ACCEPTED'
        }elseif([IO.File]::ReadAllText($SensorOwnerMarker,[Text.Encoding]::ASCII).Trim() -cne $expectedUserSid){
            Preserve-OtherUserSensorLayer 'PROTECTED_SENSOR_OWNER_MARKER_MISMATCH'
        }
        Write-Log 'PARTIAL_PROTECTED_SENSOR_BROKER_SAME_OWNER_ACCEPTED'
    }
    $sensorProcesses=@(Get-CimInstance Win32_Process -Filter "Name='TaskbarMonitorSensorBroker.exe' OR Name='TaskbarMonitorSensorSupervisor.exe'" -ErrorAction Stop |
       Where-Object {$null -ne $_})
    foreach($proc in $sensorProcesses){
        $owner=Invoke-CimMethod -InputObject $proc -MethodName GetOwnerSid -ErrorAction Stop
        if([int]$owner.ReturnValue -ne 0 -or
            [String]::IsNullOrWhiteSpace([string]$owner.Sid) -or
            [string]$owner.Sid -cne $expectedUserSid){
            Preserve-OtherUserSensorLayer 'SENSOR_PROCESS_OWNER_IS_UNKNOWN_OR_OTHER_ACCOUNT'
        }
    }
}catch{
    Preserve-OtherUserSensorLayer ('UNVERIFIED_MACHINEWIDE_SENSOR_OWNERSHIP_'+$_.Exception.GetType().Name)
}
# R264-SENSOR-GUARD-BOUNDARY-END

# R315: BEFORE new install/uninstall mutations, restore an interrupted
# PREPARED previous protected layer only under exact same-account proof.
# The old saved task/files are independently authenticated before replay.
try{
    $resumeResult=Resume-SensorPendingJournal $SensorJournalRoot $validatedSensorSid $BrokerRoot $AppRoot $TaskName
    if($resumeResult -ceq 'PREVIOUS_LAYER_RESTORED'){
        $script:ActiveArchitecture='PREVIOUS_PROTECTED_SENSOR_LAYER_RESTORED'
        Write-Log 'R315_PRIOR_PROTECTED_SENSOR_COLD_RECOVERY_COMPLETE'
        Write-Result 'DEGRADED_PREVIOUS_LAYER_RESTORED' 'The interrupted protected sensor update was rolled back to the previous verified owner task and exact prior binaries. The per-user application remains available; run Repair sensors again for a new update.' 'NOT_STARTED' $null $false $false $false
        exit 0
    }
}catch{
    $script:ActiveArchitecture='PROTECTED_JOURNAL_RECOVERY_REQUIRED'
    Write-Log ('R315_PENDING_PROTECTED_JOURNAL_COLD_RESTORE_NOT_COMPLETE '+$_.Exception.Message)
    Write-Result 'DEGRADED_ROLLBACK_RECOVERY_REQUIRED' 'Protected sensor recovery could not be fully verified; the prior journal was retained, and no subsequent new protected installation was started. A verified same-owner recovery is required.' 'NOT_STARTED' $null $false $false $false
    exit 0
}

if($Mode -eq 'Uninstall'){
    try{
        # R344: authenticated write-ahead snapshot before the FIRST task or
        # protected Broker deletion. A torn uninstall must restore the exact
        # previous owner task/files, not silently leave a markerless folder.
        $oldRootPresent=[IO.Directory]::Exists($BrokerRoot)
        $oldTaskPresent=@(Get-ScheduledTask -TaskPath '\' -TaskName $TaskName -ErrorAction SilentlyContinue |
            Where-Object{$null -ne $_}).Count -ne 0
        if($oldRootPresent -or $oldTaskPresent){
            if(-not(Capture-PreviousSensorLayer)){
                throw 'R344_UNINSTALL_PRIOR_OWNER_SNAPSHOT_NOT_CAPTURED'
            }
            $snapshotParent=[IO.Path]::GetDirectoryName($SensorJournalRoot)
            Assert-SensorBoundaryNoReparse $snapshotParent
            if(-not [IO.Directory]::Exists($snapshotParent)){
                [void][IO.Directory]::CreateDirectory($snapshotParent)
            }
            Assert-SensorJournalTrustedAcl $snapshotParent $false
            # Empty expected-new set distinguishes an uninstall snapshot
            # from the existing install PREPARED journals. Hashes and SID are
            # checked during markerless cold recovery before any mutation.
            New-SensorDurableJournal $SensorJournalRoot $validatedSensorSid $RollbackFiles $RollbackTaskXmlText ([string[]]@()) $oldRootPresent
            Write-Log 'R344_DURABLE_PREPARED_BEFORE_UNINSTALL_TASK_FILE_DELETION'
        }
        Get-Process TaskbarMonitorSensorSupervisor,TaskbarMonitorSensorBroker -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
        $liveTasks=@(Get-ScheduledTask -TaskPath '\' -TaskName $TaskName -ErrorAction SilentlyContinue |
            Where-Object{$null -ne $_})
        if($liveTasks.Count -gt 1){throw 'R344_UNINSTALL_MULTIPLE_GLOBAL_TASKS'}
        if($liveTasks.Count -eq 1){
            Unregister-ScheduledTask -TaskPath '\' -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        }
        Assert-SensorBoundaryNoReparse $BrokerRoot
        if([IO.Directory]::Exists($BrokerRoot)){
            Remove-Item -LiteralPath $BrokerRoot -Recurse -Force -ErrorAction Stop
        }
        if([IO.Directory]::Exists($BrokerRoot) -or
           @((Get-ScheduledTask -TaskPath '\' -TaskName $TaskName -ErrorAction SilentlyContinue |
               Where-Object{$null -ne $_})).Count){
            throw 'R344_PROTECTED_UNINSTALL_POSTCONDITION_FAILED'
        }
        if([IO.Directory]::Exists($SensorJournalRoot)){
            Write-SensorJournalTerminal $SensorJournalRoot $validatedSensorSid 'COMMITTED'
            Finish-SensorTerminalJournal $SensorJournalRoot $validatedSensorSid
        }
        if([IO.Directory]::Exists($SensorJournalRoot) -or
           [IO.Directory]::Exists($SensorJournalRoot+'-retired')){
            throw 'R344_UNINSTALL_TERMINAL_JOURNAL_RESIDUE'
        }
        Write-Log 'UNINSTALL protected sensor layer removed'
        Write-Result 'UNINSTALLED' 'Protected sensor layer removed.' 'NOT_APPLICABLE' $null $false $false $false
        exit 0
    }catch{
        Write-Log ('UNINSTALL_ERROR '+$_.Exception.ToString())
        Write-Result 'UNINSTALL_WARNING' $_.Exception.Message 'NOT_APPLICABLE' $null $false $false $false
        exit 0
    }
}

# R294: one exclusive read; installed bytes are the same verified buffer.
function Get-VerifiedSensorPayloadBytes([string]$File,[string]$Expected,[long]$MaxBytes){
    if($Expected -cnotmatch '^[A-F0-9]{64}$'){throw 'SENSOR_PAYLOAD_SHA_NOT_PINNED'}
    Assert-SensorBoundaryNoReparse $File
    $stream=[IO.FileStream]::new($File,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try{
        if($stream.Length -lt 1 -or $stream.Length -gt $MaxBytes){throw 'SENSOR_PAYLOAD_SIZE_INVALID'}
        $buffer=[byte[]]::new([int]$stream.Length)
        $offset=0
        while($offset -lt $buffer.Length){
            $count=$stream.Read($buffer,$offset,$buffer.Length-$offset)
            if($count -le 0){throw 'SENSOR_PAYLOAD_SHORT_READ'}
            $offset+=$count
        }
        $sha=[Security.Cryptography.SHA256]::Create()
        try{$actual=[BitConverter]::ToString($sha.ComputeHash($buffer)).Replace('-','')}
        finally{$sha.Dispose()}
        if($actual -cne $Expected){throw 'SENSOR_PAYLOAD_EMBEDDED_SHA_MISMATCH'}
        return ,$buffer
    }finally{$stream.Dispose()}
}

# R295: only the PE-pinned, single-read ZIP buffer supplies protected dependency bytes.
function Get-VerifiedSensorBackendEntries([string]$ZipFile,[string]$ExpectedZipSHA256){
    $bytes=Get-VerifiedSensorPayloadBytes $ZipFile $ExpectedZipSHA256 16777216
    Add-Type -AssemblyName System.IO.Compression
    $mem=[IO.MemoryStream]::new([byte[]]$bytes)
    $archive=[IO.Compression.ZipArchive]::new($mem,[IO.Compression.ZipArchiveMode]::Read,$false)
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $result=[Collections.Generic.List[object]]::new()
    [long]$sum=0
    try{
        if($archive.Entries.Count -ne 43){throw 'SENSOR_BACKEND_ZIP_ENTRY_COUNT'}
        foreach($entry in $archive.Entries){
            $name=[string]$entry.FullName
            if([string]::IsNullOrWhiteSpace($name) -or $name.Contains('\') -or
               $name.Contains(':') -or $name.StartsWith('/') -or
               [IO.Path]::IsPathRooted($name)){throw 'SENSOR_BACKEND_ZIP_UNSAFE_ENTRY'}
            $parts=@($name.Split('/'))
            foreach($part in $parts){
                if($part -ceq '.' -or $part -ceq '..' -or
                   $part.EndsWith('.') -or $part.EndsWith(' ') -or
                   $part -cnotmatch '^[A-Za-z0-9_.-]+$'){
                    throw 'SENSOR_BACKEND_ZIP_UNSAFE_ENTRY'
                }
            }
            if(-not $names.Add($name)){throw 'SENSOR_BACKEND_ZIP_DUPLICATE_ENTRY'}
            $fileType=($entry.ExternalAttributes -shr 16) -band 0xF000
            if($fileType -eq 0xA000){throw 'SENSOR_BACKEND_ZIP_LINK_REFUSED'}
            if($entry.Length -le 0 -or $entry.Length -gt 8388608){
                throw 'SENSOR_BACKEND_ZIP_FILE_SIZE'
            }
            $sum+=$entry.Length
            if($sum -gt 33554432){throw 'SENSOR_BACKEND_ZIP_TOTAL_SIZE'}
            $buffer=[byte[]]::new([int]$entry.Length)
            $input=$entry.Open()
            try{
                $offset=0
                while($offset -lt $buffer.Length){
                    $read=$input.Read($buffer,$offset,$buffer.Length-$offset)
                    if($read -le 0){throw 'SENSOR_BACKEND_ZIP_TRUNCATED_ENTRY'}
                    $offset+=$read
                }
                if($input.ReadByte() -ne -1){throw 'SENSOR_BACKEND_ZIP_UNDECLARED_EXTRA_DATA'}
            }finally{$input.Dispose()}
            $result.Add([pscustomobject]@{Rel=$name;Bytes=$buffer})
        }
        if(-not $names.Contains('LibreHardwareMonitorLib.dll')){
            throw 'SENSOR_BACKEND_ZIP_MISSING_LIBRARY'
        }
        return ,$result.ToArray()
    }finally{$archive.Dispose();$mem.Dispose()}
}

$BrokerPayload=Join-Path $PayloadDir 'TaskbarMonitorSensorBroker.exe'
$SupervisorPayload=Join-Path $PayloadDir 'TaskbarMonitorSensorSupervisor.exe'
$BackendRoot=Join-Path $AppRoot 'SensorBackend\LibreHardwareMonitor-0.9.6'
$LiveJson=Join-Path $AppRoot 'cpu_temp_broker.json'
$GpuJson=Join-Path $AppRoot 'gpu_temp_broker.json'
$StorageJson=Join-Path $AppRoot 'storage_temp_broker.json'
$SupervisorState=Join-Path $AppRoot 'sensor_supervisor_state.json'

$requiredOk=$true
foreach($required in @(
    $BrokerPayload,$SupervisorPayload,
    (Join-Path $BackendRoot 'LibreHardwareMonitorLib.dll')
)){
    if(-not(Test-Path -LiteralPath $required)){
        Write-Log "MISSING_PAYLOAD $required"
        $requiredOk=$false
    }
}
if(-not$requiredOk){
    Write-Result 'DEGRADED' 'Hardware sensor payload is incomplete. The main application can still run; protected temperature fields will show N/A.' 'NOT_STARTED' $null $false $false $false
    exit 0
}

# R297: NEVER execute a user-writable PawnIO installer from Temp under UAC.
# A forged PawnIO_setup.exe can be created after payload extraction, even if
# the official open-source PE carries no proprietary PawnIO resource.
# Only an already installed compatible PawnIO is reused; otherwise fail closed
# and request a separate, explicit upstream installer with user consent.
$existingPawn=Get-PawnIOVersion
$pawnAlreadyCompatible=$false
if($existingPawn){
    try{if([version]$existingPawn -ge [version]'2.2.0'){$pawnAlreadyCompatible=$true}}catch{}
}
if(-not $pawnAlreadyCompatible){
    $ActiveArchitecture='PAWNIO_EXTERNAL_INSTALL_REQUIRED'
    Write-Log 'PAWNIO_UPSTREAM_EXTERNAL_INSTALL_REQUIRED never executing mutable Temp PawnIO binary under UAC'
    Write-Result 'DEGRADED' ('Optional protected hardware sensors require the official PawnIO 2.2.0 driver, installed separately with user consent from https://github.com/namazso/PawnIO.Setup/releases/tag/2.2.0 . The main application works without it and unavailable temperatures show N/A. No driver or protected sensor service was modified.') 'EXTERNAL_INSTALL_REQUIRED' $null $false $false $false
    exit 0
}

# R294: Verify pinned embedded identity before touching protected services.
try{
    $VerifiedBrokerBytes=Get-VerifiedSensorPayloadBytes $BrokerPayload $ExpectedBrokerSHA256 16777216
    $VerifiedSupervisorBytes=Get-VerifiedSensorPayloadBytes $SupervisorPayload $ExpectedSupervisorSHA256 16777216
    $VerifiedBackendEntries=Get-VerifiedSensorBackendEntries (Join-Path $PayloadDir 'LibreHardwareMonitor.zip') $ExpectedBackendZipSHA256
}catch{
    Write-Log ('SENSOR_PAYLOAD_PROVENANCE_REFUSED '+$_.Exception.Message)
    Write-Result 'DEGRADED' 'Protected sensor payload provenance not verified; prior service preserved.' 'NOT_STARTED' $null $false $false $false
    exit 0
}
if(-not(Capture-PreviousSensorLayer)){
    $ActiveArchitecture='PREVIOUS_SENSOR_LAYER_UNCHANGED'
    Write-Result 'DEGRADED' 'Setup could not capture a rollback snapshot of the existing protected sensor layer, so it did not modify that layer.' 'NOT_STARTED' $null $false $false $false
    exit 0
}
# R308: preserve old protected bytes and task XML BEFORE writing ownership
# markers, stopping tasks or replacing protected files.
try{
    $parent=[IO.Path]::GetDirectoryName($SensorJournalRoot)
    Assert-SensorBoundaryNoReparse $parent
    if(-not [IO.Directory]::Exists($parent)){
        [void][IO.Directory]::CreateDirectory($parent)
    }
    Assert-SensorJournalTrustedAcl $parent $false
    $expectedNew=[Collections.Generic.List[string]]::new()
    foreach($name in @('TaskbarMonitorSensorBroker.exe','TaskbarMonitorSensorSupervisor.exe','.tbme-owner.sid')){
        $expectedNew.Add($name)
    }
    foreach($verified in $VerifiedBackendEntries){
        $expectedNew.Add(([string]$verified.Rel).Replace('/','\'))
    }
    New-SensorDurableJournal $SensorJournalRoot $validatedSensorSid $RollbackFiles $RollbackTaskXmlText $expectedNew.ToArray() ([IO.Directory]::Exists($BrokerRoot))
    Write-Log 'R308_DURABLE_READY_VERIFIED_BEFORE_PROTECTED_MUTATION'
}catch{
    Clear-SensorRollbackBuffer
    Write-Log ('R308_PROTECTED_JOURNAL_PREWRITE_REFUSED '+$_.Exception.Message)
    Write-Result 'DEGRADED' 'Protected sensor snapshot could not be durably verified before mutation; prior protected services were preserved.' 'NOT_STARTED' $null $false $false $false
    exit 0
}

$pawnStatus='ALREADY_PRESENT'
$pawnExit=$null
$rebootRequired=$false
Write-Log "PAWNIO_ALREADY_PRESENT version=$existingPawn"

# R303: publish protected SID ownership BEFORE unregistering the old task.
# The marker is never accepted from writable Temp/AppData and is exclusive.
function Assert-OrRecordSensorOwner {
    Assert-SensorBoundaryNoReparse $BrokerRoot
    Assert-SensorBoundaryNoReparse $SensorOwnerMarker
    if(Test-Path -LiteralPath $SensorOwnerMarker){
        if([IO.File]::ReadAllText($SensorOwnerMarker,[Text.Encoding]::ASCII).Trim() -cne $validatedSensorSid){
            throw 'PROTECTED_SENSOR_OWNER_MARKER_MISMATCH'
        }
        return
    }
    [void][IO.Directory]::CreateDirectory($BrokerRoot)
    Assert-SensorBoundaryNoReparse $SensorOwnerMarker
    $bytes=[Text.Encoding]::ASCII.GetBytes($validatedSensorSid)
    $stream=[IO.FileStream]::new($SensorOwnerMarker,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}
    finally{$stream.Dispose()}
}
try{
    Assert-OrRecordSensorOwner
}catch{
    Write-Log ('PROTECTED_SENSOR_OWNER_MARKER_SETUP_REFUSED '+$_.Exception.Message)
    Write-Result 'DEGRADED' 'Protected sensor ownership could not be persisted before modification; existing services were preserved.' 'NOT_STARTED' $null $false $false $false
    exit 0
}
$taskInstalled=$false
try{
    Get-Process TaskbarMonitorSensorSupervisor,TaskbarMonitorSensorBroker -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    $drainDeadline=(Get-Date).AddSeconds(5)
    do{
        Start-Sleep -Milliseconds 250
        $remaining=@(Get-Process TaskbarMonitorSensorSupervisor,TaskbarMonitorSensorBroker -ErrorAction SilentlyContinue)
    }while($remaining.Count -gt 0 -and (Get-Date) -lt $drainDeadline)
    if($remaining.Count -gt 0){
        throw ('SENSOR_PROCESS_DRAIN_FAILED pids='+($remaining.Id -join ','))
    }
    Remove-Item -LiteralPath $LiveJson,$GpuJson,$StorageJson,$SupervisorState -Force -ErrorAction SilentlyContinue

    New-Item -ItemType Directory -Force -Path $BrokerRoot|Out-Null
    [IO.File]::WriteAllBytes((Join-Path $BrokerRoot 'TaskbarMonitorSensorBroker.exe'),$VerifiedBrokerBytes)
    [IO.File]::WriteAllBytes((Join-Path $BrokerRoot 'TaskbarMonitorSensorSupervisor.exe'),$VerifiedSupervisorBytes)

    foreach($verified in $VerifiedBackendEntries){
        $destination=Join-Path $BrokerRoot ($verified.Rel.Replace('/','\'))
        Assert-SensorBoundaryNoReparse $destination
        $parent=Split-Path -Parent $destination
        if($parent){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
        Assert-SensorBoundaryNoReparse $destination
        [IO.File]::WriteAllBytes($destination,[byte[]]$verified.Bytes)
    }

    Import-Module ScheduledTasks
    $SupervisorExe=Join-Path $BrokerRoot 'TaskbarMonitorSensorSupervisor.exe'
    $BrokerExe=Join-Path $BrokerRoot 'TaskbarMonitorSensorBroker.exe'
    $Action=New-ScheduledTaskAction -Execute $SupervisorExe -Argument ('--broker "'+$BrokerExe+'" --output "'+$LiveJson+'"')
    $Trigger=New-ScheduledTaskTrigger -AtLogOn -User $UserId
    $Principal=New-ScheduledTaskPrincipal -UserId $UserId -LogonType Interactive -RunLevel Highest
    $Settings=New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force|Out-Null
    Start-ScheduledTask -TaskName $TaskName
    $taskInstalled=$true
    Write-Log 'SUPERVISOR_TASK_INSTALLED_AND_STARTED restartCount=3 restartInterval=PT1M multipleInstances=IgnoreNew'
}catch{
    Write-Log ('SUPERVISOR_TASK_SETUP_WARNING '+$_.Exception.ToString())
    Restore-PreviousSensorLayer 'TASK_SETUP_EXCEPTION'|Out-Null
    $taskInstalled=$false
}

$healthy=$false
$currentC=$null
if($taskInstalled -and -not$rebootRequired){
    for($i=0;$i -lt 90;$i++){
        Start-Sleep -Milliseconds 500
        $task=Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        $supervisor=@(Get-Process TaskbarMonitorSensorSupervisor -ErrorAction SilentlyContinue)

        if($task -and [string]$task.State -eq 'Running' -and $supervisor.Count -eq 1){
            try{
                if(Test-Path -LiteralPath $SupervisorState){
                    $state=Get-Content -LiteralPath $SupervisorState -Raw|ConvertFrom-Json
                    $stateTs=[datetime]::Parse([string]$state.TimestampUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime()
                    $stateAge=([datetime]::UtcNow-$stateTs).TotalSeconds
                    $version=[string]$state.BrokerVersion
                    $supervisorVersion=[string]$state.SupervisorVersion
                    $CpuTransportHealthy=[bool]$state.CpuTransportHealthy
                    $GpuTransportHealthy=[bool]$state.GpuTransportHealthy
                    $StorageTransportHealthy=[bool]$state.StorageTransportHealthy
                    $JobContainmentHealthy=(
                        [bool]$state.ChildJobKillOnClose -and
                        [bool]$state.CpuJobContained -and
                        [bool]$state.GpuJobContained -and
                        [bool]$state.StorageJobContained
                    )
                    $SupervisorHealthy=(
                        $stateAge -ge 0 -and $stateAge -lt 15 -and
                        $version -eq '1.1.2+r21' -and
                        $supervisorVersion -eq '1.3.0+r33' -and
                        $JobContainmentHealthy -and
                        $CpuTransportHealthy -and $GpuTransportHealthy -and $StorageTransportHealthy
                    )
                }
            }catch{
                $SupervisorHealthy=$false
            }

            try{
                if(Test-Path -LiteralPath $LiveJson){
                    $j=Get-Content -LiteralPath $LiveJson -Raw|ConvertFrom-Json
                    $ts=[datetime]::Parse([string]$j.TimestampUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime()
                    $age=([datetime]::UtcNow-$ts).TotalSeconds
                    $sensorName=[string]$j.Sensor
                    $current=[double]$j.CurrentC
                    if([bool]$j.Available -eq $true -and
                       [bool]$j.Is64BitProcess -eq $true -and
                       [bool]$j.IsElevated -eq $true -and
                       -not[String]::IsNullOrWhiteSpace($sensorName) -and
                       $current -gt 0 -and $current -lt 130 -and
                       $age -lt 15){
                        $healthy=$true
                        $CpuDataAvailable=$true
                        $currentC=$current
                    }
                }
            }catch{}

            if($SupervisorHealthy -and $healthy){
                Write-Log ("R33_READY_MATCH supervisor="+$supervisorVersion+" brokerProtocol="+$version+" cpu="+$currentC+" jobContainment="+$JobContainmentHealthy+" cpuTransport="+$CpuTransportHealthy+" gpuTransport="+$GpuTransportHealthy+" storageTransport="+$StorageTransportHealthy)
                break
            }
        }
    }
}

if($taskInstalled -and -not$SupervisorHealthy -and -not$rebootRequired){
    Restore-PreviousSensorLayer 'R21_HEALTH_GATE_FAILED'|Out-Null
    $taskInstalled=$false
}

if($RollbackPerformed){
    # The in-memory rollback may have returned success, but its old task XML
    # has NOT yet been independently verified by a cold privileged process.
    # Keep PREPARED and its prior bytes; do not assert ROLLED_BACK or delete.
    Write-Log ('R311_INPROCESS_ROLLBACK_JOURNAL_PENDING verifiedInMemory='+$RollbackSucceeded)
    Clear-SensorRollbackBuffer
    Write-Result 'DEGRADED_ROLLBACK_RECOVERY_REQUIRED' 'Protected sensor installation attempted rollback, but durable previous task and file recovery is not yet independently verified. The journal was retained for verified recovery; per-user monitoring remains usable.' $pawnStatus $pawnExit $false $false $false
    exit 0
}
if(-not $taskInstalled -or -not $SupervisorHealthy){
    # No claim that a partially installed protected layer is committed.
    Write-Log 'R311_PROTECTED_HEALTH_NOT_COMMITTED_KEEP_READY'
    Clear-SensorRollbackBuffer
    Write-Result 'DEGRADED_ROLLBACK_RECOVERY_REQUIRED' 'Protected sensor activation was not verified healthy; the rollback snapshot is retained rather than incorrectly committed or discarded.' $pawnStatus $pawnExit $false $false $false
    exit 0
}
try{
    Complete-HealthySensorJournal $SensorJournalRoot $validatedSensorSid $taskInstalled $SupervisorHealthy
    Write-Log 'R311_PROTECTED_JOURNAL_COMMITTED_AND_RETIRED'
}catch{
    Write-Log ('R311_TERMINAL_COMMIT_CLEANUP_DEGRADED '+$_.Exception.Message)
    Clear-SensorRollbackBuffer
    Write-Result 'DEGRADED_ROLLBACK_RECOVERY_REQUIRED' 'Protected sensors reached their health check, but the journal terminal completion could not be verified. The retained journal must be reconciled before another protected update.' $pawnStatus $pawnExit $false $false $false
    exit 0
}
# Verified protected healthy path completed and the durable terminal
# snapshot was retired; now release its redundant in-memory backup.
Clear-SensorRollbackBuffer
if($SupervisorHealthy -and $healthy){
    Write-Log "R21_SENSOR_READY cpu=$currentC"
    Write-Result 'READY' 'R21 protected sensor supervisor is healthy across CPU, GPU and storage lanes; CPU temperature data is active.' $pawnStatus $pawnExit $false $taskInstalled $true
}elseif($SupervisorHealthy){
    Write-Log 'R21_SENSOR_TRANSPORT_READY_DATA_DEGRADED'
    Write-Result 'DEGRADED_DATA' 'The R21 protected sensor supervisor is healthy across CPU, GPU and storage lanes, but CPU temperature data is not currently available on this machine.' $pawnStatus $pawnExit $false $taskInstalled $false
}elseif($rebootRequired){
    Write-Log 'SENSOR_REBOOT_REQUIRED'
    Write-Result 'REBOOT_REQUIRED' 'The application installed successfully. Restart Windows to finish activating CPU temperature monitoring.' $pawnStatus $pawnExit $true $taskInstalled $false
}elseif($pawnStatus -eq 'TIMEOUT'){
    Write-Log 'SENSOR_DEGRADED pawnio-timeout'
    Write-Result 'DEGRADED' 'The application installed successfully, but the PawnIO driver installer timed out. CPU temperature will show N/A until the sensor layer is repaired.' $pawnStatus $pawnExit $false $taskInstalled $false
}elseif($pawnStatus -eq 'FAILED' -or $pawnStatus -eq 'EXCEPTION'){
    Write-Log "SENSOR_DEGRADED pawnio=$pawnStatus"
    Write-Result 'DEGRADED' 'The application installed successfully, but CPU temperature could not be activated on this machine. Other monitoring features remain available.' $pawnStatus $pawnExit $false $taskInstalled $false
}elseif(-not$taskInstalled){
    Write-Log 'SENSOR_DEGRADED task-not-installed'
    Write-Result 'DEGRADED' 'The application installed successfully, but the protected sensor task could not be created. CPU temperature will show N/A.' $pawnStatus $pawnExit $false $false $false
}else{
    Write-Log ("R21_SUPERVISOR_UNAVAILABLE_AFTER_STARTUP_WINDOW cpuTransport="+$CpuTransportHealthy+" gpuTransport="+$GpuTransportHealthy+" storageTransport="+$StorageTransportHealthy)
    Write-Result 'UNAVAILABLE' 'The application installed successfully, but the R21 protected sensor supervisor did not reach a fresh healthy state across all worker lanes in time. Use Diagnostics > Repair protected sensors.' $pawnStatus $pawnExit $false $taskInstalled $false
}
exit 0
