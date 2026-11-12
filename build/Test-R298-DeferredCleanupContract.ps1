[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$source=Join-Path $repo 'installer/TaskbarMonitorEnhanced_Setup.cs'
$exe=Join-Path $repo 'build/_out/Setup/TaskbarMonitorEnhanced_Setup_1.7.10.exe'
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'R298_WINDOWS_ONLY'}
if(!(Test-Path $exe) -or !(Test-Path $source)){throw 'R298_MISSING_EXACT_CANDIDATE'}
$src=[IO.File]::ReadAllText($source)
if($src -notmatch 'R298: port the previously reviewed R356 handle-bound deferred cleanup' -or
   $src -cmatch 'rmdir /s /q|tbme_cleanup_' -or
   @([regex]::Matches($src,'static ProcessStartInfo BuildDeferredUninstallCleanupProcessInfo')).Count -ne 1){
 throw 'R298_SOURCE_CONTRACT_REJECTED'
}
$asm=[Reflection.Assembly]::LoadFrom((Resolve-Path $exe).Path)
$embedded=$asm.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced_Setup.cs')
if(!$embedded){throw 'R298_EMBEDDED_SETUP_SOURCE_MISSING'}
$reader=[IO.StreamReader]::new($embedded,[Text.Encoding]::UTF8)
try{$embeddedSource=$reader.ReadToEnd()}finally{$reader.Dispose()}
$eol=[string][char]13+[string][char]10
if($embeddedSource.Replace($eol,[string][char]10) -cne $src.Replace($eol,[string][char]10)){throw 'R298_BUILT_BINARY_SOURCE_MISMATCH'}
$flags=[Reflection.BindingFlags]'NonPublic,Static'
$type=$asm.GetType('SetupProgram',$true)
$method=$type.GetMethod('BuildDeferredUninstallCleanupProcessInfo',$flags)
if(!$method){throw 'R298_PRIVATE_FACTORY_MISSING'}
$owner=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$identity=[Diagnostics.Process]::GetCurrentProcess()
try{
 $argList=[object[]]::new(3)
 $argList[0]=[string]$owner
 $argList[1]=[int]$identity.Id
 $argList[2]=[long]$identity.StartTime.ToUniversalTime().Ticks
 $psi=[Diagnostics.ProcessStartInfo]$method.Invoke($null,$argList)
}finally{$identity.Dispose()}
$trusted=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell/v1.0/powershell.exe'
if(![string]::Equals([IO.Path]::GetFullPath($psi.FileName),[IO.Path]::GetFullPath($trusted),[StringComparison]::OrdinalIgnoreCase) -or
   $psi.UseShellExecute -or $psi.WorkingDirectory -cne [Environment]::SystemDirectory -or
   $psi.Arguments -cnotmatch '^-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand ([A-Za-z0-9+/=]+)$'){
 throw 'R298_UNTRUSTED_OR_UNBOUNDED_EXECUTION_FACTORY'
}
$encoded=$Matches[1]
$script=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
$tokens=$null;$parseErrors=$null
[void][Management.Automation.Language.Parser]::ParseInput($script,[ref]$tokens,[ref]$parseErrors)
if($parseErrors -and @($parseErrors).Count){throw ('R298_EMBEDDED_POWERSHELL_PARSE_'+$parseErrors[0].Message)}
foreach($must in @('TBME_CLEANUP_ROOT_NOT_CANONICAL','TBME_CLEANUP_WRONG_EFFECTIVE_TOKEN','TBME_CLEANUP_ANCESTOR_REPARSE','TBME_CLEANUP_CHILD_REPARSE','TBME_CLEANUP_UNEXPECTED_MEMBER','GetFinalPathNameByHandleW','GetFileInformationByHandleEx','SetFileInformationByHandle','DirectoryLeaseSet','WaitForExit(300000)')){
 if(!$script.Contains($must)){throw ('R298_MISSING_RUNTIME_GUARD_'+$must)}
}
if($script.Contains('__ROOT_B64__') -or $script.Contains('rmdir /s /q') -or $script.Contains('Remove-Item -Recurse')){throw 'R298_RUNTIME_TRANSPORT_TAINTED'}
$badCases=[Collections.ArrayList]::new();[void]$badCases.Add([object[]]@([string]$owner,[int]0,[long]1));[void]$badCases.Add([object[]]@([string](Join-Path $env:TEMP 'different'),[int]1,[long]1));[void]$badCases.Add([object[]]@([string]$owner,[int]1,[long]0));foreach($bad in $badCases){
 $denied=$false
 try{$null=$method.Invoke($null,$bad)}catch{if($_.Exception.Message -match 'Uninstall cleanup requires the exact owner root and parent identity'){$denied=$true}else{throw}}
 if(!$denied){throw 'R298_FACTORY_ACCEPTED_BAD_ARGUMENT'}
}
# Compile the native handle code but never execute the real uninstall command.
$match=[regex]::Match($script,"(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
if(!$match.Success){throw 'R298_NATIVE_TYPE_SOURCE_MISSING'}
$native=$match.Groups[1].Value
Add-Type -TypeDefinition $native -ErrorAction Stop
$leaseType='TBMEDeferredDirectoryLeaseSet' -as [type]
if(!$leaseType){throw 'R298_NATIVE_PIN_CLASS_NOT_COMPILED'}
$fixture=Join-Path $env:TEMP ('tbme_r298_native_handle_'+[guid]::NewGuid().ToString('N'))
$owned=Join-Path $fixture 'owned-empty'
$outside=Join-Path $fixture 'outside-keep'
if(Test-Path $fixture){throw 'R298_FIXTURE_PREEXISTS'}
New-Item -ItemType Directory -Path $owned -Force | Out-Null
New-Item -ItemType Directory -Path $outside -Force | Out-Null
$canary=Join-Path $outside 'keep.txt'
[IO.File]::WriteAllText($canary,'R298 outside canary')
$hash=(Get-FileHash $canary).Hash
try{
 $lease=New-Object TBMEDeferredDirectoryLeaseSet
 try{$lease.Pin($owned,$true);$lease.DeletePinned($owned)}finally{$lease.Dispose()}
 if(Test-Path $owned){throw 'R298_PINNED_EMPTY_DELETE_NOT_COMPLETED'}
 if((Get-FileHash $canary).Hash -cne $hash){throw 'R298_CANARY_CHANGED'}
 $junc=Join-Path $fixture 'owned-junction'
 $junctionCreated=$false
 try{New-Item -ItemType Junction -Path $junc -Target $outside -ErrorAction Stop | Out-Null;$junctionCreated=$true}catch{}
 if($junctionCreated){
  $lease=New-Object TBMEDeferredDirectoryLeaseSet
  $blocked=$false
  try{$lease.Pin($junc,$true)}catch{$blocked=$true}finally{$lease.Dispose()}
  if(!$blocked){throw 'R298_JUNCTION_ACCEPTED'}
  if((Get-FileHash $canary).Hash -cne $hash){throw 'R298_JUNCTION_TARGET_CHANGED'}
  'R298_JUNCTION_REJECTED=PASS'
 }else{'R298_JUNCTION_REJECTED=NOT_RUN_CREATION_UNAVAILABLE'}
}finally{
 if(Test-Path $fixture){
  $candidates=@(Get-ChildItem $fixture -Force -ErrorAction SilentlyContinue)
  if(@($candidates|Where-Object {$_.Name -notin @('outside-keep','owned-junction')}).Count){throw 'R298_UNEXPECTED_TEST_MEMBER'}
  $link=Join-Path $fixture 'owned-junction'
  if(Test-Path $link){[IO.Directory]::Delete($link)}
  [IO.Directory]::Delete($outside,$true)
  [IO.Directory]::Delete($fixture)
 }
}
'R298_PASS_EMBEDDED_SOURCE_AND_FACTORY'
'R298_PASS_TRUSTED_HOST_NO_CMD_NO_TEMP_SCRIPT'
'R298_PASS_POWERSHELL_PARSE_AND_NATIVE_HANDLE_COMPILE'
'R298_PASS_FAIL_CLOSED_ARGUMENTS'
'R298_PASS_DISPOSABLE_EMPTY_DIRECTORY_PINNED_DELETE'
