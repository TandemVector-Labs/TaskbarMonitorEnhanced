[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$CandidateDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# User's running desktop must never receive staged files or process kills.
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'R302_ONLY_FRESH_GITHUB_HOSTED_WINDOWS_GUEST'
}

function SHA([string]$path){
 if(!(Test-Path -LiteralPath $path -PathType Leaf)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
$repo='GOD13emad/TaskbarMonitorEnhanced'
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$stage=Join-Path $app '.tbme-upgrade'
$retired=Join-Path $app '.tbme-upgrade-retired'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$prior=Join-Path $env:RUNNER_TEMP ('R301_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R301_ROLLBACK_RETRY_RECEIPT.json')
$root=Join-Path $env:RUNNER_TEMP ('R302_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $root 'R302_REAL_SETUP_CLEANUP_KILL_RECEIPT.json'
$registry='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TaskbarMonitorEnhanced'
$program=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$config=Join-Path $app 'config.json'
$backupConfig=Join-Path $app 'config.json.bak'
$userState=Join-Path $app 'install_state.json'
$setupInstalled=Join-Path $app 'Uninstall.exe'
$native=$null;$retry=$null;$watcher=$null
$phase='INITIAL';$accepted=$false;$failure=''
$checks=[Collections.Generic.List[string]]::new()
if((Test-Path -LiteralPath $stage) -or (Test-Path -LiteralPath $retired) -or
   (Test-Path -LiteralPath $root) -or
   @(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count -ne 0){
 throw 'R302_GUEST_HAS_UNEXPECTED_JOURNAL_OR_RUNNING_MAIN'
}
[void][IO.Directory]::CreateDirectory($root)
$source=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
$previous=Get-Content -LiteralPath $prior -Raw|ConvertFrom-Json
if($source.Commit -cne $env:GITHUB_SHA -or
   $source.SetupSHA256 -cne (SHA $setup) -or
   $source.MainSHA256 -cne (SHA $program) -or
   $previous.Host -cne $HostLabel -or
   $previous.SourceCommit -cne $env:GITHUB_SHA -or
   $previous.Status -cne 'PASS_ROLLED_BACK_JOURNAL_RETRY_REAL_WORKER_TERMINATION'){
 throw 'R302_SOURCE_OR_PREDECESSOR_RECEIPT_UNVERIFIED'
}
$before=[ordered]@{}
foreach($file in @($program,$config,$backupConfig,$userState,$setupInstalled)){
 $before[$file]=SHA $file
}
if($before[$setupInstalled] -cne $source.SetupSHA256){
 throw 'R302_INSTALLED_GUEST_SETUP_NOT_EXACT_CANDIDATE'
}
$display=[string](Get-ItemProperty -LiteralPath $registry -ErrorAction Stop).DisplayVersion
if($display -cne '1.7.8'){throw 'R302_GUEST_INSTALLED_VERSION_NOT_MATCHED'}
$checks.Add('GUEST_MAIN_SETUP_CONFIG_STATE_AND_REGISTRY_PINNED')

# .NET Framework 4.8 compatibility: callback kills exactly the Process object
# started below. No process-name search and no host-wide/process-tree kill.
$sourceCode=@'
using System;
using System.IO;
using System.Diagnostics;
using System.Threading;
using System.Text;
using System.ComponentModel;
using System.Runtime.InteropServices;
// R320 test-only: create the UNMODIFIED candidate Setup suspended, arm and
// bind the watcher to its exact process ID, then resume. IDLE priority gives
// the watcher a better chance to preempt fast NTFS cleanup on Windows 2022.
public static class R320SuspendedSetupLauncher {
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]
 private struct STARTUPINFO {
   public uint cb;public string lpReserved;public string lpDesktop;public string lpTitle;
   public uint dwX;public uint dwY;public uint dwXSize;public uint dwYSize;
   public uint dwXCountChars;public uint dwYCountChars;public uint dwFillAttribute;
   public uint dwFlags;public ushort wShowWindow;public ushort cbReserved2;
   public IntPtr lpReserved2;public IntPtr hStdInput;public IntPtr hStdOutput;public IntPtr hStdError;
 }
 [StructLayout(LayoutKind.Sequential)]
 private struct PROCESS_INFORMATION {
   public IntPtr hProcess;public IntPtr hThread;public uint dwProcessId;public uint dwThreadId;
 }
 [DllImport("kernel32.dll",EntryPoint="CreateProcessW",CharSet=CharSet.Unicode,SetLastError=true)]
 private static extern bool CreateProcess(string app,StringBuilder command,
    IntPtr procSecurity,IntPtr threadSecurity,bool inheritHandles,uint flags,
    IntPtr environment,string workingDir,ref STARTUPINFO startup,out PROCESS_INFORMATION process);
 [DllImport("kernel32.dll",SetLastError=true)]
 private static extern uint ResumeThread(IntPtr thread);
 [DllImport("kernel32.dll",SetLastError=true)]
 private static extern bool TerminateProcess(IntPtr process,uint exit);
 [DllImport("kernel32.dll",SetLastError=true)]
 private static extern bool CloseHandle(IntPtr handle);
 [DllImport("kernel32.dll",SetLastError=true)]
 private static extern bool GetExitCodeProcess(IntPtr handle,out uint exitCode);
 public static bool NonzeroNativeExitCode(Process process) {
   if(process==null || !process.HasExited)
      throw new InvalidOperationException("R320_NATIVE_EXIT_QUERY_BEFORE_TERMINATION");
   uint exit;
   if(!GetExitCodeProcess(process.Handle,out exit))
      throw new Win32Exception(Marshal.GetLastWin32Error(),"R320_NATIVE_EXITCODE_QUERY_FAILED");
   return exit!=0 && exit!=259; // STILL_ACTIVE and success are not kill witnesses
 }
 public static Process StartOriginalSuspended(string setup,string args,string directory,R302RealSetupDeleteWatcher watcher){
   if(watcher==null || String.IsNullOrWhiteSpace(setup) ||
      !Path.IsPathRooted(setup) || !File.Exists(setup) ||
      args!="/update /quiet" || !Directory.Exists(directory) ||
      !String.Equals(Path.GetDirectoryName(Path.GetFullPath(setup)),Path.GetFullPath(directory),
                     StringComparison.OrdinalIgnoreCase))
     throw new InvalidOperationException("R320_TEST_ONLY_UNTRUSTED_SETUP_LAUNCH_ARGUMENT");
   STARTUPINFO si=new STARTUPINFO();
   si.cb=(uint)Marshal.SizeOf(typeof(STARTUPINFO));
   PROCESS_INFORMATION pi;
   StringBuilder line=new StringBuilder("\""+Path.GetFullPath(setup)+"\" "+args);
   const uint CREATE_SUSPENDED=0x00000004,IDLE_PRIORITY_CLASS=0x00000040,CREATE_NO_WINDOW=0x08000000;
   if(!CreateProcess(Path.GetFullPath(setup),line,IntPtr.Zero,IntPtr.Zero,false,
                     CREATE_SUSPENDED|IDLE_PRIORITY_CLASS|CREATE_NO_WINDOW,
                     IntPtr.Zero,directory,ref si,out pi))
     throw new Win32Exception(Marshal.GetLastWin32Error(),"R320_ORIGINAL_SETUP_CREATE_SUSPENDED_FAILED");
   bool resumed=false;Process child=null;
   try{
     child=Process.GetProcessById(checked((int)pi.dwProcessId));
     // Materialize and retain the actual native handle before resuming, so
     // GetExitCodeProcess remains usable after this short-lived process dies.
     if(child.Handle==IntPtr.Zero)
        throw new InvalidOperationException("R320_PROCESS_HANDLE_NOT_PINNED");
     watcher.Bind(child); // guaranteed before the suspended primary thread runs
     uint previous=ResumeThread(pi.hThread);
     if(previous!=1)throw new Win32Exception(Marshal.GetLastWin32Error(),"R320_ORIGINAL_SETUP_RESUME_FAILED");
     resumed=true;
     return child;
   }finally{
     if(!resumed){
       if(pi.hProcess!=IntPtr.Zero)TerminateProcess(pi.hProcess,125);
       if(child!=null)child.Dispose();
     }
     if(pi.hThread!=IntPtr.Zero)CloseHandle(pi.hThread);
     if(pi.hProcess!=IntPtr.Zero)CloseHandle(pi.hProcess);
   }
 }
}
public sealed class R302RealSetupDeleteWatcher : IDisposable {
  public readonly ManualResetEventSlim TerminatedEvent=new ManualResetEventSlim(false);
  private FileSystemWatcher oldWatcher, newWatcher;
  private Process child;
  private int once, notifications, nativeObservations, disposed;
  private IntPtr nativeNotify=IntPtr.Zero;
  private Thread nativeObserver;
  private string[] ownedStageFiles;
  public string TriggerFile="";
  public string TriggerOrigin="";
  public string Failure="";
  public bool Killed=false;
  public int Notifications { get { return notifications; } }
  public int NativeKnownDeleteObservations { get { return nativeObservations; } }
  [DllImport("kernel32.dll",EntryPoint="FindFirstChangeNotificationW",CharSet=CharSet.Unicode,SetLastError=true)]
  private static extern IntPtr FindFirstChangeNotification(string path,bool subtree,uint filter);
  [DllImport("kernel32.dll",SetLastError=true)]
  private static extern bool FindNextChangeNotification(IntPtr handle);
  [DllImport("kernel32.dll",SetLastError=true)]
  private static extern bool FindCloseChangeNotification(IntPtr handle);
  [DllImport("kernel32.dll",SetLastError=true)]
  private static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
  private static bool KnownLeaf(string path){
    string ext=Path.GetExtension(path).ToLowerInvariant();
    return ext==".exe" || ext==".cs" || ext==".md" ||
           ext==".json" || ext==".config" || ext==".ico";
  }
  public void Arm(string oldPath,string newPath){
    if(!Directory.Exists(oldPath) || !Directory.Exists(newPath) ||
       !String.Equals(Path.GetDirectoryName(Path.GetFullPath(oldPath)),
                      Path.GetDirectoryName(Path.GetFullPath(newPath)),
                      StringComparison.OrdinalIgnoreCase))
      throw new InvalidOperationException("R330_NATIVE_WATCH_PATHS_NOT_SIBLINGS");
    var originals=new System.Collections.Generic.List<string>();
    foreach(string directory in new string[]{oldPath,newPath})
      foreach(string file in Directory.GetFiles(directory,"*",SearchOption.AllDirectories))
        if(KnownLeaf(file)) originals.Add(Path.GetFullPath(file));
    if(originals.Count<20 || originals.Count>100)
      throw new InvalidOperationException("R330_STAGE_LEAF_COUNT_OUT_OF_BOUNDS");
    ownedStageFiles=originals.ToArray();
    oldWatcher=CreateManagedObserver(oldPath);
    newWatcher=CreateManagedObserver(newPath);
    // The Win32 directory notification is armed before resuming the original
    // test-only Setup. Managed FileSystemWatcher callback delivery can be late.
    string parent=Path.GetDirectoryName(Path.GetFullPath(oldPath));
    nativeNotify=FindFirstChangeNotification(parent,true,0x00000001u|0x00000002u);
    if(nativeNotify==IntPtr.Zero || nativeNotify==new IntPtr(-1))
      throw new Win32Exception(Marshal.GetLastWin32Error(),"R330_NATIVE_DIR_NOTIFY_ARM_FAILED");
    oldWatcher.EnableRaisingEvents=true;
    newWatcher.EnableRaisingEvents=true;
  }
  private FileSystemWatcher CreateManagedObserver(string path){
    var watcher=new FileSystemWatcher(path);
    watcher.IncludeSubdirectories=true;
    watcher.Filter="*";
    watcher.NotifyFilter=NotifyFilters.FileName | NotifyFilters.DirectoryName;
    watcher.InternalBufferSize=32768;
    watcher.Deleted+=OnDeleted;
    return watcher;
  }
  public void Bind(Process p){
    if(p==null || ownedStageFiles==null || nativeNotify==IntPtr.Zero)
      throw new InvalidOperationException("R330_NATIVE_OBSERVER_NOT_ARMED");
    Interlocked.Exchange(ref child,p);
    nativeObserver=new Thread(NativeObserveKnownStageDeletion);
    nativeObserver.IsBackground=true;
    nativeObserver.Priority=ThreadPriority.Highest;
    nativeObserver.Start();
  }
  private void NativeObserveKnownStageDeletion(){
    while(Interlocked.CompareExchange(ref disposed,0,0)==0 &&
          Interlocked.CompareExchange(ref once,0,0)==0){
      uint result=WaitForSingleObject(nativeNotify,200);
      if(result==0x00000102u)continue; // WAIT_TIMEOUT
      if(result!=0){Failure="NATIVE_NOTIFY_WAIT_FAILED_"+result;break;}
      foreach(string file in ownedStageFiles){
        if(File.Exists(file))continue;
        Interlocked.Increment(ref nativeObservations);
        AttemptTerminateExactChild(file,"NATIVE_KNOWN_STAGE_LEAF_DELETION");
        return;
      }
      if(!FindNextChangeNotification(nativeNotify)){
        Failure="NATIVE_NOTIFY_REARM_FAILED_"+Marshal.GetLastWin32Error();
        break;
      }
    }
  }
  private void OnDeleted(object sender,FileSystemEventArgs e){
    Interlocked.Increment(ref notifications);
    if(!KnownLeaf(e.FullPath))return;
    bool owned=false;
    foreach(string original in ownedStageFiles)
      if(String.Equals(original,e.FullPath,StringComparison.OrdinalIgnoreCase)){
        owned=true;break;
      }
    if(owned)AttemptTerminateExactChild(e.FullPath,"FILESYSTEMWATCHER_KNOWN_STAGE_LEAF_DELETION");
  }
  private void AttemptTerminateExactChild(string knownStageFile,string mechanism){
    if(Interlocked.CompareExchange(ref once,1,0)!=0)return;
    TriggerFile=Path.GetFileName(knownStageFile);
    TriggerOrigin=mechanism;
    try{
      Process exact=child;
      if(exact==null)throw new Exception("PROCESS_NOT_BOUND");
      exact.Refresh();
      if(exact.HasExited)throw new Exception("SETUP_ALREADY_EXITED");
      exact.Kill();
      Killed=exact.WaitForExit(10000) && exact.HasExited &&
             R320SuspendedSetupLauncher.NonzeroNativeExitCode(exact);
      if(!Killed)Failure="EXACT_CHILD_TERMINATION_UNCONFIRMED";
    }catch(Exception err){Failure=err.GetType().Name+":"+err.Message;}
    finally{TerminatedEvent.Set();}
  }
  public void Dispose(){
    Interlocked.Exchange(ref disposed,1);
    if(nativeObserver!=null && !nativeObserver.Join(2000))
      throw new InvalidOperationException("R330_NATIVE_OBSERVER_THREAD_NOT_STOPPED");
    if(nativeNotify!=IntPtr.Zero && nativeNotify!=new IntPtr(-1)){
      FindCloseChangeNotification(nativeNotify);nativeNotify=IntPtr.Zero;
    }
    if(oldWatcher!=null){oldWatcher.EnableRaisingEvents=false;oldWatcher.Dispose();}
    if(newWatcher!=null){newWatcher.EnableRaisingEvents=false;newWatcher.Dispose();}
  }
}
'@
Add-Type -TypeDefinition $sourceCode -ErrorAction Stop

# Build a genuine ROLLED_BACK journal; hashes are from the live disposable
# installed guest. Stage payload files are disposable and exactly named by
# the candidate's compiled inventory, never unknown owner data.
$assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
$type=$assembly.GetType('SetupProgram',$true)
$static=[Reflection.BindingFlags]'Static,NonPublic'
$instance=[Reflection.BindingFlags]'Instance,NonPublic,Public'
$field=$type.GetField('UpgradeTargets',$static)
if(!$field){throw 'R302_COMPILED_TARGET_INVENTORY_MISSING'}
$targets=[array]$field.GetValue($null)
if($targets.Count -lt 25 -or $targets.Count -gt 40){throw 'R302_UNEXPECTED_TARGET_COUNT'}
$lines=[Collections.Generic.List[string]]::new()
$staged=0
$old=Join-Path $stage 'old'
$new=Join-Path $stage 'new'
[void][IO.Directory]::CreateDirectory($old)
[void][IO.Directory]::CreateDirectory($new)
foreach($target in $targets){
 $relField=$target.GetType().GetField('Rel',$instance)
 if(!$relField){throw 'R302_TARGET_REL_FIELD_MISSING'}
 $rel=[string]$relField.GetValue($target)
 if(!$rel -or $rel -match '(^|[/\\])\.\.([/\\]|$)' -or
    [IO.Path]::IsPathRooted($rel) -or $rel -match '[:*?"<>|]'){
   throw 'R302_UNSAFE_COMPILED_TARGET'
 }
 $live=Join-Path $app ($rel.Replace('/',[IO.Path]::DirectorySeparatorChar))
 $prev=SHA $live
 if($prev -ceq 'MISSING'){$prev='-'}
 if($prev -cne '-' -and $prev -cnotmatch '^[A-F0-9]{64}$'){
  throw 'R302_BAD_PINNED_PREVIOUS_DIGEST'
 }
 $lines.Add($rel+'|'+$prev+'|-')
 foreach($part in @($old,$new)){
  $name=Join-Path $part ($rel.Replace('/',[IO.Path]::DirectorySeparatorChar))
  $parent=[IO.Path]::GetDirectoryName($name)
  [void][IO.Directory]::CreateDirectory($parent)
  [IO.File]::WriteAllText($name,('R302_STAGE_ONLY_'+$HostLabel+'_'+$rel),[Text.UTF8Encoding]::new($false))
  $staged++
 }
}
if($staged -ne ($targets.Count*2)){throw 'R302_STAGE_FIXTURE_COUNT_INCORRECT'}
$marker='TBME_UPGRADE_R92_OWNED_STAGE_V1'
[IO.File]::WriteAllText((Join-Path $stage 'owner.txt'),$marker,[Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $stage 'index.txt'),
 ($lines.ToArray() -join ([string][char]10)),[Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $stage 'previous_version.txt'),'1.7.8',[Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $stage 'phase.txt'),($marker+'|ROLLED_BACK'),[Text.Encoding]::ASCII)
$checks.Add('COMPLETE_PINNED_ROLLED_BACK_JOURNAL_WITH_KNOWN_STAGE_PAYLOADS')

try {
 $phase='START_EXACT_ORIGINAL_SETUP_AND_ARM_DELETE_WATCH'
 $watcher=[R302RealSetupDeleteWatcher]::new()
 $watcher.Arm($old,$new)
 $psi=[Diagnostics.ProcessStartInfo]::new()
 $psi.FileName=$setup
 $psi.Arguments='/update /quiet'
 $psi.UseShellExecute=$false
 $psi.CreateNoWindow=$true
 $psi.WorkingDirectory=[IO.Path]::GetDirectoryName($setup)
  $native=[R320SuspendedSetupLauncher]::StartOriginalSuspended(
    $setup,'/update /quiet',[IO.Path]::GetDirectoryName($setup),$watcher)
 if(!$native){throw 'R302_ORIGINAL_SETUP_FAILED_TO_START'}
 $realSetupPid=$native.Id
  $checks.Add('R320_EXACT_ORIGINAL_SETUP_LAUNCHED_SUSPENDED_WATCHER_BOUND_BEFORE_RESUME')
 $clock=[Diagnostics.Stopwatch]::StartNew()
 while(-not $watcher.TerminatedEvent.Wait(75) -and $clock.ElapsedMilliseconds -lt 45000){
  $native.Refresh()
  if($native.HasExited){break}
 }
 $native.Refresh()
 if(!$watcher.Killed){
  throw ('R302_SETUP_NOT_KILLED_ON_A_KNOWN_STAGE_FILE_DELETE; cause='+
     $watcher.Failure+' events='+$watcher.Notifications+
     ' setupExited='+$native.HasExited)
 }
 if(!$native.HasExited -or -not [R320SuspendedSetupLauncher]::NonzeroNativeExitCode($native)){
  throw 'R302_ACTUAL_SETUP_PID_TERMINATION_NOT_PROVEN'
 }
 $checks.Add('REAL_ORIGINAL_SETUP_PID_KILLED_BY_NATIVE_FILE_DELETION_EVENT')
 $activeRemaining=@(Get-ChildItem $stage -Recurse -File -ErrorAction SilentlyContinue).Count
 $retiredRemaining=@(Get-ChildItem $retired -Recurse -File -ErrorAction SilentlyContinue).Count
 if(($activeRemaining+$retiredRemaining) -le 0 -or
    (!(Test-Path $stage) -and !(Test-Path $retired))){
  throw 'R302_NO_PARTIAL_JOURNAL_WITNESS_AFTER_SETUP_KILL'
 }
 $checks.Add('SOME_RECOVERABLE_STAGE_METADATA_SURVIVES_ACTUAL_SETUP_KILL')
 $phase='COLD_RETRY_EXACT_ORIGINAL_SETUP'
 $retry=[Diagnostics.Process]::Start($psi)
 if(!$retry){throw 'R302_COLD_RESTART_SETUP_NOT_LAUNCHED'}
 $retryPid=$retry.Id
 if(!$retry.WaitForExit(90000)){
  $retry.Kill();[void]$retry.WaitForExit(9000)
  throw 'R302_COLD_RETRY_EXCEEDED_BOUNDED_BUDGET'
 }
 if($retry.ExitCode -ne 0){
  throw ('R302_NATIVE_SETUP_RECOVERY_NONZERO_'+$retry.ExitCode)
 }
 if((Test-Path $stage) -or (Test-Path $retired)){
  throw 'R302_RECOVERY_DID_NOT_CLEAR_BOTH_JOURNAL_NAMES'
 }
 $checks.Add('EXACT_SAME_BINARY_RESTART_RETIRES_PARTIAL_JOURNAL')
 foreach($path in $before.Keys){
  if((SHA $path) -cne $before[$path]){
   throw ('R302_GUEST_DATA_BINARY_OR_SETTING_CHANGED_'+$path)
  }
 }
 if([string](Get-ItemProperty -LiteralPath $registry).DisplayVersion -cne $display){
  throw 'R302_HKCU_INSTALLED_VERSION_CHANGED'
 }
 if(@(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count -ne 0){
  throw 'R302_UNEXPECTED_BACKGROUND_APP_STARTED'
 }
 $checks.Add('BYTE_EXACT_SETUP_MAIN_USER_SETTINGS_AND_REGISTRY_PRESERVED')
 $data=[ordered]@{
  Schema=1;Revision='R302';Status='PASS_NATIVE_SETUP_KILLED_DURING_STAGE_CLEANUP_RECOVERED'
  Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
  OriginalOwnerComputerTouched=$false;UnmodifiedCandidateSetupExecuted=$true
   NativeExactSetupSuspendedBoundBeforeResume=$true
  ActualSetupPid=$realSetupPid;ActualSetupProcessTerminated=$true
  DeletedStageFileTrigger=$watcher.TriggerFile
  FileDeletionNotifications=$watcher.Notifications
  NativeKnownDeletedLeafObservations=$watcher.NativeKnownDeleteObservations
  NativeWatcherOrFileSystemWatcherOrigin=$watcher.TriggerOrigin
  JournalFilesAfterKill=($activeRemaining+$retiredRemaining)
  RecoveredBySecondActualSetupProcess=$true;SecondSetupPid=$retryPid
  MainSetupConfigStateAndRegistryPreserved=$true
  NoStageOrRetiredResidue=$true
  CurrentVersion='1.7.8';Tests=@($checks)
  RecordedUtc=[DateTime]::UtcNow.ToString('o')
 }
 [IO.File]::WriteAllText($receipt,($data|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
 $accepted=$true
 'R302_'+$HostLabel+'_EXACT_UNMODIFIED_SETUP_KILL_AND_RESTART_PASS'
}catch{
 $failure=$_.Exception.ToString()
 throw
}finally{
 if($watcher){$watcher.Dispose()}
 foreach($process in @($native,$retry)){
  if($null -ne $process){
   try{
    $process.Refresh()
    if(!$process.HasExited){
     $process.Kill()
     [void]$process.WaitForExit(10000)
    }
   }finally{$process.Dispose()}
  }
 }
 if(!$accepted){
  $bad=[ordered]@{
   Schema=1;Revision='R302';Status='FAIL_NOT_ACCEPTED'
   Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
   Phase=$phase;Failure=$failure
   OriginalOwnerComputerTouched=$false
   RecordedUtc=[DateTime]::UtcNow.ToString('o')
  }
  [IO.File]::WriteAllText($receipt,($bad|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
 }
}
