[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
  [Parameter(Mandatory=$true)][string]$SourceRoot,
  [switch]$KillBeforeMutation,
  [switch]$KillAfterTaskRemoval,
  [switch]$KillAfterBrokerRemoval
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# R340 does NOT exercise real interactive UAC or install any driver.
# Run only on fresh hosted disposable Windows (the hosted runner already owns
# an administrator token), never on the maintainer desktop or existing sensor.
if(($KillBeforeMutation -and $KillAfterTaskRemoval) -or
   ($KillBeforeMutation -and $KillAfterBrokerRemoval) -or
   ($KillAfterTaskRemoval -and $KillAfterBrokerRemoval)){
  throw 'R343_DEATH_CHECKPOINTS_MUTUALLY_EXCLUSIVE'
}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'GOD13emad/TaskbarMonitorEnhanced' -or
   $env:GITHUB_REF -cne 'refs/heads/audit/r349-pinned-leaf-replay-handles' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC|ALIEMAD|SAEID|LAPTOP' -or
   $env:GITHUB_RUN_ID -cnotmatch '^[0-9]{5,20}$' -or
   $env:GITHUB_SHA -cnotmatch '^[0-9a-f]{40}$' -or
   ![string]::Equals((git -C $SourceRoot rev-parse HEAD).Trim(),$env:GITHUB_SHA,[StringComparison]::Ordinal)){
  throw 'R340_REFUSE_NONDISPOSABLE_OR_NONPINNED_WINDOWS_HOST'
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$admin=[Security.Principal.WindowsPrincipal]::new($identity)
if(!$admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
  throw 'R340_HOSTED_ALREADY_ADMIN_TOKEN_REQUIRED_NO_UAC_BYPASS'
}
$sid=[string]$identity.User.Value
if($sid -cnotmatch '^S-1-5-21-(?:\d+-){3}\d+$'){throw 'R340_NONINTERACTIVE_TOKEN_SID_REFUSED'}
$setup=Join-Path $SourceRoot 'build\_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$brokerFile=Join-Path $SourceRoot 'build\_out\Broker\TaskbarMonitorSensorBroker.exe'
$supervisorFile=Join-Path $SourceRoot 'build\_out\Supervisor\TaskbarMonitorSensorSupervisor.exe'
$helperSource=Join-Path $SourceRoot 'installer\TBME_Setup_Elevated_Helper.ps1'
$program=[Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
$profile=[Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
$local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$temp=Join-Path $profile 'AppData\Local\Temp'
$app=Join-Path $local 'TaskbarMonitorEnhanced'
$logs=Join-Path $app 'Logs'
$log=Join-Path $logs 'sensor_install.log'
$resultPath=Join-Path $logs 'sensor_install_result.json'
$protected=Join-Path $program 'TaskbarMonitorEnhanced'
$broker=Join-Path $protected 'SensorBroker'
$task='TaskbarMonitorEnhanced Sensor Broker'
$owner=Join-Path $broker '.tbme-owner.sid'
$mainOwner=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$journal=Join-Path $protected '.tbme-sensor-rollback'
$rid=[guid]::NewGuid().ToString('N')
$payload=Join-Path $temp ('tbme_uninstall_'+$rid)
$receiptsRoot=Join-Path $env:RUNNER_TEMP ('R340_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $receiptsRoot 'R340_REAL_PROTECTED_UNINSTALL_HELPER.json'
$outside=Join-Path $receiptsRoot 'OUTSIDE_CANARY.txt'
$checks=[Collections.Generic.List[string]]::new()
$createdRoot=$false;$createdTask=$false;$createdPayload=$false;$brokerRemoved=$false;$ownerHash=''
$createdApp=$false;$createdLogs=$false
$helperExit=$null;$helperStatus='';$failure='';$phase='PRECONDITION'
$outsideHash='';$beforeB='';$beforeS='';$exportedXmlHash=''
$taskRemoved=$false;$protectedRemoved=$false;$payloadRemoved=$false
$logsRemoved=$false;$appRemoved=$false;$childPid=0
$nativeRunas=$false;$usesRealUnmodifiedResource=$false
$deliberateKill=$false;$killedFirstPid=0;$originalTaskIntactAtKill=$false
$deliberatePostTaskKill=$false;$taskRemovedAtKill=$false;$resultAbsentAtKill=$false;$postKilledPid=0
$deliberatePostFileKill=$false;$fileRemovedAtKill=$false;$taskGoneAtFileKill=$false;$protectedRootPresentAtFileKill=$null;$ownerMarkerPresentAtFileKill=$null;$fileKilledPid=0
$journalColdRestored=$false;$recoveryRunPid=0;$finalCleanupRunPid=0;$recoveryTaskXmlExact=$false;$recoveryTaskTrustMatch=$false;$firstHelperStatus='';$oldOwnedBrokerHashesRestored=$false
function Hash([string]$file){return (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}
function Check([string]$check){$script:checks.Add($check);Write-Output ('PASS '+$check)}
function TaskExists(){
 return (@(Get-ScheduledTask -TaskName $task -TaskPath '\' -ErrorAction SilentlyContinue|
    Where-Object{$null -ne $_}).Count -ne 0)
}
function ResolveTaskSid([string]$principal){
 if([string]::IsNullOrWhiteSpace($principal)){throw 'R340_TASK_PRINCIPAL_EMPTY'}
 if($principal -match '^S-1-5-(?:\d+-)+\d+$'){return $principal}
 return [string]([Security.Principal.NTAccount]::new($principal)).Translate(
    [Security.Principal.SecurityIdentifier]).Value
}
function NoReparse([string]$file){
 if(([IO.File]::GetAttributes($file) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
   throw ('R340_REPARSE_IN_OWNED_FIXTURE '+[IO.Path]::GetFileName($file))
 }
}
function RemoveOwnedProtected(){
 if(!$createdRoot){return !$([IO.Directory]::Exists($protected))}
 if(![IO.Directory]::Exists($protected)){return $true}
 NoReparse $protected
 $members=@([IO.Directory]::GetFileSystemEntries($protected))
 if($members.Count -eq 0){
   [IO.Directory]::Delete($protected,$false)
   return !$([IO.Directory]::Exists($protected))
 }
 if($members.Count -ne 1 -or $members[0] -cne $broker){
   throw 'R340_UNKNOWN_PROGRAMFILES_CHILD_NO_CLEANUP'
 }
 NoReparse $broker
 $items=@([IO.Directory]::GetFileSystemEntries($broker))
 $expected=@((Join-Path $broker 'TaskbarMonitorSensorBroker.exe'),
             (Join-Path $broker 'TaskbarMonitorSensorSupervisor.exe'),$owner)
 if(@($items|Where-Object{$_ -notin $expected}).Count){
   throw 'R340_FOREIGN_MEMBER_PRESERVE_PROTECTED'
 }
 foreach($file in $items){
   NoReparse $file
   $h=Hash $file
   if($file -ceq $owner){if($h -cne $script:ownerHash){throw 'R340_MARKER_NOT_OURS'}}
   elseif($file -like '*SensorBroker.exe'){if($h -cne $beforeB){throw 'R340_BROKER_NOT_ORIGINAL'}}
   elseif($file -like '*SensorSupervisor.exe'){if($h -cne $beforeS){throw 'R340_SUPERVISOR_NOT_ORIGINAL'}}
 }
 foreach($file in $items){[IO.File]::Delete($file)}
 [IO.Directory]::Delete($broker,$false)
 [IO.Directory]::Delete($protected,$false)
 return !$([IO.Directory]::Exists($protected))
}
try{
 $phase='VERIFY_FRESH_GUEST_AND_SOURCE'
 foreach($f in @($setup,$brokerFile,$supervisorFile,$helperSource)){if(![IO.File]::Exists($f)){throw 'R340_PRIVATE_SOURCE_FILE_MISSING'}}
 if([IO.Directory]::Exists($protected) -or [IO.Directory]::Exists($payload) -or
    [IO.Directory]::Exists($receiptsRoot) -or [IO.File]::Exists($mainOwner) -or
    [IO.File]::Exists($log) -or [IO.File]::Exists($resultPath) -or
    (TaskExists) -or @(Get-Process TaskbarMonitorSensorSupervisor,TaskbarMonitorSensorBroker,TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count){
   throw 'R340_PREEXISTING_REAL_PRODUCT_OR_OWNED_FIXTURE_COLLISION'
 }
 $preexistingApp=[IO.Directory]::Exists($app)
 $preexistingLog=[IO.Directory]::Exists($logs)
 [void][IO.Directory]::CreateDirectory($receiptsRoot)
 [IO.File]::WriteAllText($outside,'R340_UNRELATED_CANARY',[Text.UTF8Encoding]::new($false))
 $outsideHash=Hash $outside
 Check 'FRESH_GITHUB_HOSTED_ADMIN_ORIGINAL_PRODUCT_TASK_AND_JOURNAL_ABSENT'
 if([IO.Directory]::Exists($journal) -or [IO.Directory]::Exists($journal+'-retired')){
   throw 'R340_PENDING_REAL_PROTECTED_SENSOR_JOURNAL_PREEXISTS'
 }
 $asm=[Reflection.Assembly]::LoadFrom([IO.Path]::GetFullPath($setup))
 $stream=$asm.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
 if(!$stream){throw 'R340_SETUP_EMBEDDED_UNMODIFIED_HELPER_MISSING'}
 $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
 try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
 $normalize={param($x) $x.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
 if((& $normalize $embedded) -cne (& $normalize ([IO.File]::ReadAllText($helperSource)))){
   throw 'R340_UNMODIFIED_HELPER_RESOURCE_MISMATCH'
 }
 $usesRealUnmodifiedResource=$true
 Check 'PRIVATE_EXACT_COMPILED_SETUP_EMBEDS_REAL_UNMODIFIED_HELPER'
 $phase='CREATE_BOUNDED_DISPOSABLE_PROTECTED_FIXTURE'
 $admins=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
 $system=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
 $users=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
 $acl=[Security.AccessControl.DirectorySecurity]::new()
 $acl.SetOwner($admins);$acl.SetAccessRuleProtection($true,$false)
 foreach($s in @($admins,$system,$users)){
   $rights=if($s -eq $users){[Security.AccessControl.FileSystemRights]::ReadAndExecute}else{[Security.AccessControl.FileSystemRights]::FullControl}
   [void]$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
     $s,$rights,[Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
     [Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
 }
 [void][IO.Directory]::CreateDirectory($protected,$acl)
 $createdRoot=$true
 [void][IO.Directory]::CreateDirectory($broker)
 $protectedB=Join-Path $broker 'TaskbarMonitorSensorBroker.exe'
 $protectedS=Join-Path $broker 'TaskbarMonitorSensorSupervisor.exe'
 [IO.File]::Copy($brokerFile,$protectedB)
 [IO.File]::Copy($supervisorFile,$protectedS)
 [IO.File]::WriteAllText($owner,$sid,[Text.Encoding]::ASCII)
 $ownerHash=Hash $owner
 $beforeB=Hash $protectedB;$beforeS=Hash $protectedS
 if($beforeB -cne (Hash $brokerFile) -or $beforeS -cne (Hash $supervisorFile)){
   throw 'R340_PROTECTED_BINARIES_NOT_EXACT_PRIVATE_SETUP'
 }
 $programAcl=Get-Acl -LiteralPath $broker
 if([string]$programAcl.Owner -notmatch '(?i)Administrators'){
   throw 'R340_PROTECTED_ACL_OWNER_NOT_ADMIN'
 }
 Check 'REAL_PROGRAMFILES_FIXTURE_ADMIN_OWNED_EXACT_BINARIES_AND_SID_MARKER'
 $phase='CREATE_OWNER_DISABLED_NEVER_EXECUTED_TASK'
 $argsText='--broker "'+$protectedB+'" --output "'+(Join-Path $app 'cpu_temp_broker.json')+'"'
 $xml=@"
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
<Triggers><LogonTrigger><Enabled>false</Enabled><UserId>$sid</UserId></LogonTrigger></Triggers>
<Principals><Principal id="Author"><UserId>$sid</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
<Settings><Enabled>false</Enabled><AllowStartOnDemand>false</AllowStartOnDemand></Settings>
<Actions Context="Author"><Exec><Command>$protectedS</Command><Arguments>$argsText</Arguments></Exec></Actions>
</Task>
"@
 Register-ScheduledTask -TaskPath '\' -TaskName $task -Xml $xml -ErrorAction Stop|Out-Null
 $createdTask=$true
 $readTask=Get-ScheduledTask -TaskName $task -TaskPath '\' -ErrorAction Stop
 if($readTask.Settings.Enabled -ne $false -or
    (ResolveTaskSid ([string]$readTask.Principal.UserId)) -cne $sid -or
    -not [string]::Equals([string]$readTask.Actions[0].Execute,$protectedS,[StringComparison]::OrdinalIgnoreCase)){
   throw 'R340_DISABLED_TASK_NOT_EXACT_REVIEW_OWNER'
 }
 $exportedXmlHash=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string](Export-ScheduledTask -TaskPath '\' -TaskName $task)))
 Check 'EXACT_GLOBAL_SENSOR_TASK_REGISTERED_DISABLED_WITHOUT_EXECUTION'
 $phase='PREPARE_CANONICAL_USER_TEMP_AND_LOGS'
 if(![IO.Directory]::Exists($app)){[void][IO.Directory]::CreateDirectory($app);$createdApp=$true}
 if(![IO.Directory]::Exists($logs)){[void][IO.Directory]::CreateDirectory($logs);$createdLogs=$true}
 [void][IO.Directory]::CreateDirectory($payload);$createdPayload=$true
 Check 'EXACT_USER_PROFILE_LOCALAPP_TEMP_PAYLOAD_AND_LOGS_PREPARED'
 $phase='LAUNCH_UNMODIFIED_SETUP_PE_RUNAS_HELPER'
 $t=$asm.GetType('SetupProgram',$true)
 $method=$t.GetMethod('BuildElevatedSensorProcessInfo',[Reflection.BindingFlags]'Static,NonPublic')
 if(!$method){throw 'R340_SETUP_PE_RUNAS_HELPER_FACTORY_NOT_PRESENT'}
 # R340-F02: unwrap PSObject arguments for private .NET Framework reflection.
 $actualArgs=[string[]]@('Uninstall',$payload,$app,$sid)
 $arg=New-Object 'object[]' 4
 for($i=0;$i -lt $actualArgs.Length;$i++){
   $arg[$i]=$actualArgs[$i].PSObject.BaseObject
 }
 $psi=[Diagnostics.ProcessStartInfo]$method.Invoke($null,$arg)
 $native=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
 if(!$psi.UseShellExecute -or $psi.Verb -cne 'runas' -or
    ![string]::Equals($psi.FileName,$native,[StringComparison]::OrdinalIgnoreCase) -or
    $psi.Arguments.Contains(' -File ') -or
    $psi.Arguments -notmatch '(?i)-EncodedCommand|-Command "' -or
    $psi.WorkingDirectory -cne [IO.Path]::GetDirectoryName($native)){
   throw 'R340_PE_RUNAS_EXECUTABLE_OR_TRANSPORT_NOT_VERIFIED'
 }
 $nativeRunas=$true
 # R342: bounded, in-memory high-priority witness of exact owned Task
 # Scheduler's physical entry removal, *not* a process-name-based kill.
 if($KillAfterTaskRemoval -or $KillAfterBrokerRemoval){
   $taskFile=if($KillAfterTaskRemoval){
     Join-Path $env:windir 'System32\Tasks\TaskbarMonitorEnhanced Sensor Broker'
   }else{$protectedB}
   if(![IO.File]::Exists($taskFile)){
     throw 'R343_EXPECTED_REAL_PROTECTED_WATCH_FILE_NOT_PRESENT'
   }
   Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
public sealed class R342TaskFileRemovalKill {
 public volatile bool Deleted, Killed, ResultExistedAtKill;
 public volatile string Error="";
 private Thread observer;
 public void Start(Process child,string taskFile,string resultFile) {
  if(child==null||!File.Exists(taskFile) || String.IsNullOrWhiteSpace(resultFile))
   throw new IOException("R342_WATCH_OWNER_TASK_NOT_PRESENT");
  observer=new Thread(()=>{
   Stopwatch sw=Stopwatch.StartNew();
   while(sw.ElapsedMilliseconds<25000){
    try{
     if(child.HasExited){Error="R342_ORIGINAL_EXIT_BEFORE_TASK_DELETE";return;}
     if(!File.Exists(taskFile)){
      Deleted=true;
      ResultExistedAtKill=File.Exists(resultFile);
      if(ResultExistedAtKill){Error="R342_RESULT_ALREADY_EXISTS_BEFORE_KILL";return;}
      child.Kill();
      Killed=child.WaitForExit(9000);
      if(!Killed)Error="R342_KILL_NOT_COMPLETED";
      return;
     }
    }catch(Exception ex){Error=ex.GetType().Name+": "+ex.Message;return;}
    Thread.SpinWait(256);
   }
   Error="R342_TASK_FILE_DELETE_NOT_OBSERVED";
  });
  observer.IsBackground=true;
  observer.Priority=ThreadPriority.Highest;
  observer.Start();
 }
 public bool Wait(int timeoutMs){return observer!=null&&observer.Join(timeoutMs);}
}
'@
 }
 $child=[Diagnostics.Process]::Start($psi)
 if(!$child){throw 'R341_ORIGINAL_EMBEDDED_HELPER_START_RETURNED_NULL'}
 if($KillAfterTaskRemoval){
   $phase='KILL_EXACT_ORIGINAL_HELPER_AFTER_SCHEDULER_TASK_MUTATION'
   $first=$child;$postKilledPid=$first.Id
   try{
     $killer=[R342TaskFileRemovalKill]::new()
     $killer.Start($first,$taskFile,$resultPath)
     if(!$killer.Wait(39000)){throw 'R342_BOUNDED_TASK_DELETE_WATCHER_TIMEOUT'}
     if(!$killer.Deleted -or !$killer.Killed -or $killer.ResultExistedAtKill -or $killer.Error){
       throw ('R342_TASK_DELETE_KILL_NOT_ACCEPTABLE_'+$killer.Error)
     }
     if(TaskExists){throw 'R342_KILLED_BEFORE_REAL_TASK_UNREGISTER'}
     if([IO.File]::Exists($resultPath)){throw 'R342_ORIGINAL_HELPER_RESULT_ALREADY_PUBLISHED'}
     $deliberatePostTaskKill=$true
     $taskRemovedAtKill=$true
     $resultAbsentAtKill=$true
   }finally{
     try{if(!$first.HasExited){$first.Kill();[void]$first.WaitForExit(8000)}}catch{}
     $first.Dispose()
   }
   Check 'ACTUAL_ORIGINAL_HELPER_KILLED_AFTER_TASK_MUTATION_BEFORE_RESULT'
   $phase='RETRY_SAME_PE_PRODUCTION_HELPER_AFTER_GLOBAL_TASK_MUTATION'
   $child=[Diagnostics.Process]::Start($psi)
   if(!$child){throw 'R342_IDENTICAL_ORIGINAL_HELPER_RETRY_NOT_STARTED'}
 }
 if($KillBeforeMutation){
   $phase='KILL_EXACT_ORIGINAL_HELPER_AFTER_BEGIN_PRE_SHARED_MUTATION'
   $first=$child
   $killedFirstPid=$first.Id
   try{
     $timer=[Diagnostics.Stopwatch]::StartNew()
     $beginObserved=$false
     while(!$first.HasExited -and $timer.ElapsedMilliseconds -lt 30000){
       if([IO.File]::Exists($log)){
         try{
           if([IO.File]::ReadAllText($log).Contains('BEGIN mode=Uninstall')){
             $beginObserved=$true
             if(!$first.HasExited){
               $first.Kill()
               if(!$first.WaitForExit(10000)){
                 throw 'R341_EXACT_HELPER_KILL_DID_NOT_COMPLETE'
               }
               $deliberateKill=$true
             }
             break
           }
         }catch [IO.IOException]{
           # Retry only transient lease contention, never swallow mutation.
         }
       }
       Start-Sleep -Milliseconds 5
     }
     if(!$beginObserved -or !$deliberateKill){
       throw 'R341_UNMODIFIED_HELPER_EXITED_BEFORE_VERIFIED_KILL'
     }
     if(!(TaskExists) -or
        ![IO.File]::Exists($protectedB) -or ![IO.File]::Exists($protectedS) -or
        ![IO.File]::Exists($owner) -or
        (Hash $protectedB) -cne $beforeB -or
        (Hash $protectedS) -cne $beforeS -or
        (Hash $owner) -cne $ownerHash){
       throw 'R341_KILL_WAS_AFTER_SHARED_TASK_OR_PROTECTED_FILES_MUTATION'
     }
     $originalTaskIntactAtKill=$true
   }finally{
     try{if(!$first.HasExited){$first.Kill();[void]$first.WaitForExit(8000)}}catch{}
     $first.Dispose()
   }
   Check 'ACTUAL_UNMODIFIED_HELPER_KILLED_AFTER_BEGIN_BEFORE_PROTECTED_MUTATION'
   $phase='RELAUNCH_IDENTICAL_ORIGINAL_HELPER_FOR_BOUNDED_RECOVERY'
   $child=[Diagnostics.Process]::Start($psi)
   if(!$child){throw 'R341_SECOND_IDENTICAL_UNMODIFIED_HELPER_NOT_STARTED'}
 }
 if($KillAfterBrokerRemoval){
   $phase='KILL_EXACT_ORIGINAL_HELPER_AFTER_PROTECTED_BROKER_EXE_DELETE'
   $first=$child;$fileKilledPid=$first.Id
   try{
     $watcher=[R342TaskFileRemovalKill]::new()
     $watcher.Start($first,$taskFile,$resultPath)
     if(!$watcher.Wait(39000)){throw 'R343_BOUNDED_FILE_DELETE_WATCHER_TIMEOUT'}
     if(!$watcher.Deleted -or !$watcher.Killed -or $watcher.ResultExistedAtKill -or $watcher.Error){
       throw ('R343_REAL_BROKER_EXECUTABLE_DELETE_KILL_NOT_ACCEPTED_'+$watcher.Error)
     }
     $fileRemovedAtKill=(![IO.File]::Exists($protectedB))
     $taskGoneAtFileKill=(!(TaskExists))
     $protectedRootPresentAtFileKill=[IO.Directory]::Exists($broker)
     $ownerMarkerPresentAtFileKill=[IO.File]::Exists($owner)
     if(!$fileRemovedAtKill -or !$taskGoneAtFileKill -or [IO.File]::Exists($resultPath)){
       throw 'R343_ORIGINAL_HELPER_NOT_STOPPED_AFTER_BROKER_FILE_DELETE_BEFORE_RESULT'
     }
     $deliberatePostFileKill=$true
   }finally{
     try{if(!$first.HasExited){$first.Kill();[void]$first.WaitForExit(8000)}}catch{}
     $first.Dispose()
   }
   Check 'ORIGINAL_HELPER_KILLED_AFTER_ACTUAL_BROKER_EXECUTABLE_DELETE_BEFORE_RESULT'
   $phase='RETRY_UNMODIFIED_PRODUCTION_HELPER_AFTER_PROTECTED_FILE_MUTATION'
   $child=[Diagnostics.Process]::Start($psi)
   if(!$child){throw 'R343_SECOND_ORIGINAL_HELPER_PROCESS_FAILED_TO_START'}
 }
 try{
   $childPid=$child.Id
   if(!$child.WaitForExit(55000)){
     if(!$child.HasExited){$child.Kill();[void]$child.WaitForExit(6000)}
     throw 'R340_ACTUAL_HELPER_PROCESS_TIMEOUT'
   }
   $helperExit=$child.ExitCode
 }finally{$child.Dispose()}
 if([int]$helperExit -ne 0){throw ('R340_ORIGINAL_HELPER_NONZERO_EXIT_'+$helperExit)}
 Check 'ACTUAL_COMPRESSED_PE_EMBEDDED_HELPER_PROCESS_RUNAS_WITHOUT_DRIVER_EXITS_ZERO'
 # R344: The exact original Helper must cold-restore the hash-bound old
 # protected Broker + disabled global task after interruption under PREPARED.
 # The first new Helper intentionally exits DEGRADED_PREVIOUS_LAYER_RESTORED;
 # only a THIRD identical original Helper run may finish requested Uninstall.
 if(($KillBeforeMutation -or $KillAfterTaskRemoval -or $KillAfterBrokerRemoval) -and
    [IO.File]::Exists($resultPath)){
   $intermediate=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
   $firstHelperStatus=[string]$intermediate.Status
   if($firstHelperStatus -ceq 'DEGRADED_PREVIOUS_LAYER_RESTORED'){
     $phase='VERIFY_HASHED_PREPARED_UNINSTALL_COLD_RESTORATION'
     if(!(TaskExists) -or
        ![IO.File]::Exists($protectedB) -or
        ![IO.File]::Exists($protectedS) -or
        ![IO.File]::Exists($owner) -or
        (Hash $protectedB) -cne $beforeB -or
        (Hash $protectedS) -cne $beforeS -or
        (Hash $owner) -cne $ownerHash){
       throw 'R344_ORIGINAL_HELPER_COLD_REPLAY_PRIOR_OWNER_FILES_MISMATCH'
     }
     $oldOwnedBrokerHashesRestored=$true
     $restored=Get-ScheduledTask -TaskName $task -TaskPath '\' -ErrorAction Stop
     $recoveryTaskTrustMatch=($restored.Settings.Enabled -eq $false -and
       (ResolveTaskSid ([string]$restored.Principal.UserId)) -ceq $sid -and
       @($restored.Actions).Count -eq 1 -and
       [string]::Equals([string]$restored.Actions[0].Execute,$protectedS,[StringComparison]::OrdinalIgnoreCase) -and
       [string]::Equals([string]$restored.Actions[0].Arguments,$argsText,[StringComparison]::OrdinalIgnoreCase))
     if(!$recoveryTaskTrustMatch){throw 'R344_PRIOR_SCHEDULED_TASK_ACTION_PRINCIPAL_NOT_RESTORED'}
     $priorXml=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($exportedXmlHash))
     $newXml=[string](Export-ScheduledTask -TaskPath '\' -TaskName $task -ErrorAction Stop)
     $recoveryTaskXmlExact=[string]::Equals($priorXml,$newXml,[StringComparison]::Ordinal)
     if([IO.Directory]::Exists($journal) -or [IO.Directory]::Exists($journal+'-retired')){
       throw 'R344_PREPARED_JOURNAL_NOT_RETIRED_AFTER_COLD_REPLAY'
     }
     $journalColdRestored=$true
     $recoveryRunPid=$childPid
     Check 'VERIFIED_PRIOR_BROKER_MARKER_AND_TASK_COLD_RESTORED_FROM_REAL_PREPARED_JOURNAL'
     $phase='THIRD_IDENTICAL_PE_HELPER_FINISHES_REQUESTED_UNINSTALL'
     $finalChild=[Diagnostics.Process]::Start($psi)
     if(!$finalChild){throw 'R344_THIRD_ORIGINAL_HELPER_NOT_STARTED'}
     try{
       $finalCleanupRunPid=$finalChild.Id
       if($finalCleanupRunPid -eq $recoveryRunPid -or
          $finalCleanupRunPid -eq $fileKilledPid -or
          $finalCleanupRunPid -eq $postKilledPid){
         throw 'R344_FINAL_ORIGINAL_HELPER_PID_COLLISION'
       }
       if(!$finalChild.WaitForExit(55000)){
         if(!$finalChild.HasExited){$finalChild.Kill();[void]$finalChild.WaitForExit(6000)}
         throw 'R344_FINAL_UNINSTALL_TIMEOUT'
       }
       if($finalChild.ExitCode -ne 0){throw ('R344_FINAL_UNINSTALL_NONZERO_'+$finalChild.ExitCode)}
     }finally{$finalChild.Dispose()}
     $childPid=$finalCleanupRunPid;$helperExit=0
   }elseif($KillAfterTaskRemoval -or $KillAfterBrokerRemoval){
     throw ('R344_TORN_UNINSTALL_DID_NOT_COLD_RESTORE_'+$firstHelperStatus)
   }
 }
 if([IO.Directory]::Exists($journal) -or [IO.Directory]::Exists($journal+'-retired')){
   throw 'R344_TERMINAL_UNINSTALL_JOURNAL_RESIDUE'
 }
 $phase='VERIFY_REAL_PROTECTED_UNINSTALL_AND_WITNESS'
 $taskRemoved=!(TaskExists)
 $brokerRemoved=![IO.Directory]::Exists($broker)
 if(!$taskRemoved -or !$brokerRemoved){
   throw 'R340_BROKER_ROOT_OR_EXACT_GLOBAL_TASK_NOT_UNINSTALLED'
 }
 Check 'ACTUAL_HELPER_REMOVES_OWNED_GLOBAL_TASK_AND_PROTECTED_BROKER_SUBFOLDER'
 if(![IO.File]::Exists($resultPath) -or ![IO.File]::Exists($log)){throw 'R340_REAL_HELPER_USER_STATUS_OR_LOG_NOT_WRITTEN'}
 $result=Get-Content -LiteralPath $resultPath -Raw|ConvertFrom-Json
 $helperStatus=[string]$result.Status
 $body=[IO.File]::ReadAllText($log)
 if($helperStatus -cne 'UNINSTALLED' -or
    $result.RollbackPerformed -ne $false -or
    $body -notmatch 'BEGIN mode=Uninstall' -or
    $body -notmatch 'UNINSTALL protected sensor layer removed'){
   throw ('R340_ORIGINAL_HELPER_UNINSTALL_RESULT_BAD_'+$helperStatus)
 }
 Check 'REAL_UNMODIFIED_HELPER_WRITES_EXPECTED_UNINSTALL_RESULT_AND_NATIVE_LOG_LEASE'
 if((Hash $outside) -cne $outsideHash){throw 'R340_EXTERNAL_CANARY_CHANGED'}
 Check 'OUTSIDE_CANARY_UNCHANGED_AND_NO_PAWNIO_INSTALL_OR_SENSOR_PROCESS_START'
}catch{
 $failure=$_.Exception.GetType().Name+': '+$_.Exception.Message+' PHASE='+$phase
}finally{
 # R344-F01 diagnostic snapshot is read-only and taken BEFORE cleanup.
 # The nominal test must expose the actual Helper Status/Message and log
 # source for an early fail-closed unwind; no profile secrets are copied.
 $helperDiagnosticStatus='MISSING';$helperDiagnosticMessage=''
 $helperDiagnosticLogTail=''
 try{
   if([IO.File]::Exists($resultPath)){
     $diagnostic=Get-Content -LiteralPath $resultPath -Raw -ErrorAction Stop|ConvertFrom-Json
     $helperDiagnosticStatus=[string]$diagnostic.Status
     $helperDiagnosticMessage=[string]$diagnostic.Message
   }
   if([IO.File]::Exists($log)){
     $lines=@(Get-Content -LiteralPath $log -Tail 9 -ErrorAction Stop)
     $helperDiagnosticLogTail=($lines -join ' | ')
     if($helperDiagnosticLogTail.Length -gt 1800){
       $helperDiagnosticLogTail=$helperDiagnosticLogTail.Substring($helperDiagnosticLogTail.Length-1800)
     }
   }
 }catch{$helperDiagnosticMessage='DIAGNOSTIC_READ_FAILED_'+$_.Exception.GetType().Name}
 if($failure){
   Write-Output ('R344_DIAGNOSTIC_HELPER_STATUS='+$helperDiagnosticStatus)
   Write-Output ('R344_DIAGNOSTIC_HELPER_MESSAGE='+$helperDiagnosticMessage)
   Write-Output ('R344_DIAGNOSTIC_LOGTAIL='+$helperDiagnosticLogTail)
 }
 # Only the caller-owned fixtures are candidates for cleanup. Never force
 # delete unknown shared task/root contents or preexisting user AppData files.
 if($createdTask -and (TaskExists)){
   try{
     $current=Get-ScheduledTask -TaskName $task -TaskPath '\' -ErrorAction Stop
     if($current.Settings.Enabled -eq $false -and
        (ResolveTaskSid ([string]$current.Principal.UserId)) -ceq $sid -and
        [string]::Equals([IO.Path]::GetFullPath([string]$current.Actions[0].Execute),[IO.Path]::GetFullPath((Join-Path $broker 'TaskbarMonitorSensorSupervisor.exe')),[StringComparison]::OrdinalIgnoreCase)){
       Unregister-ScheduledTask -TaskPath '\' -TaskName $task -Confirm:$false -ErrorAction Stop
     }
   }catch{$failure+=' TASK_CLEANUP_FAILED='+$_.Exception.Message}
 }
 $taskRemoved=!(TaskExists)
 if($createdRoot){
   try{$protectedRemoved=RemoveOwnedProtected}
   catch{$failure+=' PROTECTED_CLEANUP_REFUSED='+$_.Exception.Message}
 }
 if($createdPayload){
   try{
     if([IO.Directory]::Exists($payload) -and @([IO.Directory]::GetFileSystemEntries($payload)).Count -eq 0){
       [IO.Directory]::Delete($payload,$false)
     }
     $payloadRemoved=(![IO.Directory]::Exists($payload))
   }catch{$failure+=' PAYLOAD_CLEANUP_REFUSED='+$_.Exception.Message}
 }
 if([IO.Directory]::Exists($logs)){
   try{
     foreach($f in @($log,$resultPath)){
       if([IO.File]::Exists($f)){NoReparse $f;[IO.File]::Delete($f)}
     }
     if($createdLogs -and @([IO.Directory]::GetFileSystemEntries($logs)).Count -eq 0){
       [IO.Directory]::Delete($logs,$false)
     }
     $logsRemoved=(!$createdLogs -or ![IO.Directory]::Exists($logs))
   }catch{$failure+=' LOG_CLEANUP_REFUSED='+$_.Exception.Message}
 }else{$logsRemoved=$true}
 if($createdApp){
   try{
     if([IO.Directory]::Exists($app) -and @([IO.Directory]::GetFileSystemEntries($app)).Count -eq 0){
       [IO.Directory]::Delete($app,$false)
     }
     $appRemoved=(![IO.Directory]::Exists($app))
   }catch{$failure+=' APP_CLEANUP_REFUSED='+$_.Exception.Message}
 }else{$appRemoved=$true}
 if($createdTask -and !$taskRemoved){$failure+=' GLOBAL_TASK_RESIDUE'}
 if($createdRoot -and !$protectedRemoved){$failure+=' GLOBAL_PROTECTED_ROOT_RESIDUE'}
 if($createdPayload -and !$payloadRemoved){$failure+=' TEMP_PAYLOAD_RESIDUE'}
 if(!$logsRemoved -or !$appRemoved){$failure+=' LOCALAPP_OWNED_RESIDUE'}
 $neededChecks=9
 if($KillBeforeMutation -or $KillAfterTaskRemoval -or $KillAfterBrokerRemoval){$neededChecks=10}
 if($journalColdRestored){$neededChecks++}
 $status=if(!$failure -and $checks.Count -eq $neededChecks -and $taskRemoved -and $brokerRemoved -and $protectedRemoved){
   if($KillAfterBrokerRemoval){'PASS_PREPARED_UNINSTALL_JOURNAL_RESTORED_AFTER_BROKER_FILE_DELETE_THEN_UNINSTALLED'}
   elseif($KillAfterTaskRemoval){'PASS_KILLED_ORIGINAL_HELPER_AFTER_TASK_UNREGISTER_BEFORE_RESULT_THEN_RETRIED'}
   elseif($KillBeforeMutation){'PASS_KILLED_ORIGINAL_EMBEDDED_HELPER_BEFORE_SHARED_MUTATION_THEN_RECOVERED'}
   else{'PASS_REAL_UNMODIFIED_EMBEDDED_HELPER_RUNAS_UNINSTALL_PROTECTED_LAYER'}
 }else{'FAIL_R340_NOT_ACCEPTED'}
 $out=[ordered]@{
  Schema=1;Revision=$(if($KillAfterBrokerRemoval){'R344'}elseif($KillAfterTaskRemoval){'R342'}elseif($KillBeforeMutation){'R341'}else{'R340'});Status=$status;Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
  SetupSHA256=if([IO.File]::Exists($setup)){Hash $setup}else{'MISSING'}
  CandidateBrokerSHA256=$beforeB;CandidateSupervisorSHA256=$beforeS
  RealEmbeddedHelperBytesMatchSource=$usesRealUnmodifiedResource
  RealProductionRunasFactory=$nativeRunas
  RunasHost='WindowsPowerShell5.1SystemDirectory'
  AlreadyAdminRunner=$true;TrueInteractiveUacDialogObserved=$false
  OriginalHelperProcessStarted=($childPid -gt 0);OriginalHelperPid=$childPid
  OriginalHelperExitCode=$helperExit;OriginalHelperResultStatus=$helperStatus
  PreCleanupHelperResultStatus=$helperDiagnosticStatus
  PreCleanupHelperResultMessage=$helperDiagnosticMessage
  PreCleanupHelperLogTail=$helperDiagnosticLogTail
  ProtectedProgramFilesCreated=$createdRoot;ProtectedProgramFilesRemoved=$protectedRemoved
  OriginalHelperBrokerSubfolderRemoved=$brokerRemoved
  GlobalDisabledTaskCreated=$createdTask;GlobalDisabledTaskRemoved=$taskRemoved
  ScopedUserPayloadRemoved=$payloadRemoved
  ScopedTestLogsRemoved=$logsRemoved
  UserProfileExistingAppPreserved=!$createdApp
  ActualHelperDeliberateKillTested=[bool]($deliberateKill -or $deliberatePostTaskKill -or $deliberatePostFileKill)
  DeliberateKillRequested=[bool]($KillBeforeMutation -or $KillAfterTaskRemoval -or $KillAfterBrokerRemoval)
  FirstKilledOriginalHelperPid=$killedFirstPid
  OriginalTaskAndBrokerUnchangedAtKill=$originalTaskIntactAtKill
  RecoveryUsesIdenticalOriginalRunasProcessInfo=[bool](($deliberateKill -or $deliberatePostTaskKill -or $deliberatePostFileKill) -and $nativeRunas)
  ActualHelperKilledAfterBrokerExecutableDeletion=$deliberatePostFileKill
  ExactProtectedBrokerExecutableAbsentAtKill=$fileRemovedAtKill
  TaskAlreadyUnregisteredAtFileKill=$taskGoneAtFileKill
  ProtectedBrokerRootPresentAtFileKill=$protectedRootPresentAtFileKill
  OwnerMarkerPresentAtFileKill=$ownerMarkerPresentAtFileKill
  PostFileKilledOriginalHelperPid=$fileKilledPid
  OriginalPreparedJournalColdRecoveryObserved=$journalColdRestored
  OriginalHelperColdRecoveryFirstStatus=$firstHelperStatus
  ColdRecoveryHelperPid=$recoveryRunPid
  FinalOriginalHelperUninstallPid=$finalCleanupRunPid
  RestoredOwnerMarkerAndProtectedBinarySHAExact=$oldOwnedBrokerHashesRestored
  RestoredDisabledTaskPrincipalAndActionExact=$recoveryTaskTrustMatch
  RestoredTaskExportedXmlByteExact=$recoveryTaskXmlExact
  NoTerminalJournalResidueAfterFinal=$true
  ActualHelperKilledAfterProtectedTaskMutation=$deliberatePostTaskKill
  OriginalTaskUnregisteredAtKill=$taskRemovedAtKill
  ResultAbsentAtPostTaskKill=$resultAbsentAtKill
  PostTaskKilledOriginalHelperPid=$postKilledPid
  AnyDriverInstallationTriggered=$false
  OriginalOwnerMachineTouched=$false
  Checks=@($checks);Failure=$failure
 }
 if([IO.Directory]::Exists($receiptsRoot)){
   [IO.File]::WriteAllText($receipt,($out|ConvertTo-Json -Depth 7),
      [Text.UTF8Encoding]::new($false))
   Write-Output ('R340_NATIVE_RECEIPT='+$receipt)
 }
 Write-Output ('R340_STATUS='+$status+' CHECKS='+$checks.Count+' TASK_REMOVED='+$taskRemoved+' ROOT_REMOVED='+$protectedRemoved)
}
if($failure){throw ('R340_REAL_HELPER_UNINSTALL_NOT_ACCEPTED '+$failure)}
