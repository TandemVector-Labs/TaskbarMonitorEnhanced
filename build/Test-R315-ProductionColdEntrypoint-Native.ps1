[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$CandidateDir,
 [ValidateSet('Driver','Worker','Recover')][string]$Mode='Driver',
 [string]$Fixture=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrEmpty($env:GITHUB_SHA) -or
   [string]::IsNullOrEmpty($env:GITHUB_RUN_ID) -or
   [string]::IsNullOrEmpty($env:RUNNER_TEMP)){
 throw 'R315_HOSTED_WINDOWS_DISPOSABLE_ONLY'
}
function FileHash([string]$path){
 if(-not [IO.File]::Exists($path)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
function Absent([string]$name){
 $items=@(Get-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction SilentlyContinue|Where-Object {$null -ne $_})
 if($items.Count){throw 'R315_PREEXISTING_DISPOSABLE_TASK'}
}
function Reject([string]$label,[scriptblock]$fn,[string]$pattern){
 $failed=$false
 try{& $fn}catch{if($_.Exception.ToString() -match $pattern){$failed=$true}else{throw}}
 if(-not $failed){throw ('R315_EXPECTED_PREWRITE_REFUSAL_MISSING_'+$label)}
 $script:checks.Add($label)
}
$run=Join-Path $env:RUNNER_TEMP ('R315_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $run 'R315_TASK_COLD_RESTORE_RECEIPT.json'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R314_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R314_TASK_COLD_RESTORE_RECEIPT.json')
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$config=Join-Path $app 'config.json'
$state=Join-Path $app 'install_state.json'
$checks=[Collections.Generic.List[string]]::new()
$assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
$res=$assembly.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
if(!$res){throw 'R315_COMPILED_PE_HELPER_RESOURCE_MISSING'}
$reader=[IO.StreamReader]::new($res)
try{$source=[string]$reader.ReadToEnd()}finally{$reader.Dispose()}
$helper=(Resolve-Path (Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1')).Path
$normal={param([string]$s) $s.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $normal $source) -cne (& $normal ([IO.File]::ReadAllText($helper)))){
 throw 'R315_SETUP_PE_HELPER_SOURCE_MISMATCH'
}
$t=$null;$e=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($helper,[ref]$t,[ref]$e)
if(@($e).Count){throw 'R315_HELPER_PS51_PARSER_INVALID'}
$names=@(
 'Assert-SensorBoundaryNoReparse','Get-SensorJournalHash','Assert-SensorJournalRelative',
 'Assert-SensorJournalTrustedAcl','Write-SensorJournalUnique','Assert-SensorDurableJournal',
 'New-SensorDurableJournal','Get-SensorJournalTerminal','Write-SensorJournalTerminal',
 'Restore-SensorJournalOldFilesOnly','Assert-SensorRetiredJournalSafe',
 'Finish-SensorRetiredJournal','Finish-SensorTerminalJournal',
 'Resolve-SensorPriorTaskPrincipalSid','Assert-SensorTrustedOldTaskXml',
 'Test-SensorOwnedTaskRegistration','Restore-SensorJournalPriorLayerAndTask','Resume-SensorPendingJournal'
)
$defs=@($ast.FindAll({param($n)
 $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in $names
},$true))
if($defs.Count -ne $names.Count){throw 'R315_EXACT_COMPILED_FUNCTIONS_NOT_FOUND'}
. ([scriptblock]::Create(($defs|ForEach-Object {$_.Extent.Text}) -join [Environment]::NewLine))
Import-Module ScheduledTasks -ErrorAction Stop
$sid=[string]([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
if($sid -cnotmatch '^S-1-5-21-(?:\d+-){3}\d+$'){throw 'R315_RUNNER_SID_NOT_INTERACTIVE'}
$name='TBME-R314-Disposable-'+$env:GITHUB_RUN_ID+'-'+$HostLabel
if($name -cnotmatch '^TBME-R314-Disposable-[0-9]{5,20}-[AB]$'){throw 'R315_UNSAFE_TASK_NAME'}
$journal=Join-Path (Join-Path $run 'trusted') 'snapshot'
$live=Join-Path $run 'live-broker'
$appRoot=Join-Path $run 'user-data'
$oldBroker=Join-Path $live 'TaskbarMonitorSensorBroker.exe'
$oldCfg=Join-Path $live 'settings\old.bin'
$newSupervisor=Join-Path $live 'TaskbarMonitorSensorSupervisor.exe'
$outside=Join-Path $run 'unrelated'
$canary=Join-Path $outside 'leave-alone.txt'
if($Mode -ne 'Driver'){
 if(-not [string]::Equals([IO.Path]::GetFullPath($Fixture),[IO.Path]::GetFullPath($run),[StringComparison]::OrdinalIgnoreCase) -or
    -not [IO.Directory]::Exists($run)){
  throw 'R315_CHILD_FIXTURE_IDENTITY_MISMATCH'
 }
 if($Mode -eq 'Worker'){
  if(-not (Test-SensorOwnedTaskRegistration $name $sid $live $appRoot)){
   throw 'R315_WORKER_PREVIOUS_TASK_NOT_PRESENT'
  }
  Unregister-ScheduledTask -TaskPath '\' -TaskName $name -Confirm:$false -ErrorAction Stop
  [IO.File]::WriteAllBytes($oldBroker,[Text.Encoding]::ASCII.GetBytes('R315_WRONG_NEW_BROKER'))
  [IO.File]::WriteAllBytes($newSupervisor,[Text.Encoding]::ASCII.GetBytes('R315_WRONG_NEW_SUPERVISOR'))
  [IO.File]::WriteAllText((Join-Path $run 'WORKER_CHECKPOINT'),'TASK_REMOVED_AND_LIVE_BROKER_MUTATED')
  Start-Sleep -Seconds 30
  exit 0
 }
 if($Mode -eq 'Recover'){
  $status=Resume-SensorPendingJournal $journal $sid $live $appRoot $name
  if($status -cne 'PREVIOUS_LAYER_RESTORED'){
   throw 'R315_COLD_ENTRYPOINT_DID_NOT_RETURN_RECOVERED'
  }
  [IO.File]::WriteAllText((Join-Path $run 'RECOVERED'),'OLD_TASK_AND_FILES_RESTORED')
  exit 0
 }
}
if([IO.Directory]::Exists($run)){throw 'R315_TEST_ROOT_ALREADY_EXISTS'}
[void][IO.Directory]::CreateDirectory($run)
$initial=@{Main=(FileHash $main);Config=(FileHash $config);State=(FileHash $state)}
$c=Get-Content $manifest -Raw|ConvertFrom-Json
$p=Get-Content $prior -Raw|ConvertFrom-Json
if($c.Commit -cne $env:GITHUB_SHA -or
   $c.SetupSHA256 -cne (FileHash $setup) -or
   $c.MainSHA256 -cne $initial.Main -or
   $p.SourceCommit -cne $env:GITHUB_SHA -or
   $p.Host -cne $HostLabel -or
   $p.Status -cne 'PASS_DISPOSABLE_TASK_AND_FILES_COLD_RESTORE_AFTER_KILLED_WORKER'){
 throw 'R315_CANDIDATE_OR_PREVIOUS_RECEIPT_NOT_EXACT'
}
$checks.Add('EXACT_PE_HELPER_AND_PREVIOUS_HOST_RECEIPT')
$helperText=[IO.File]::ReadAllText($helper)
$ownerAt=$helperText.IndexOf('# R264-SENSOR-GUARD-BOUNDARY-END',[StringComparison]::Ordinal)
$hookAt=$helperText.IndexOf('Resume-SensorPendingJournal $SensorJournalRoot $validatedSensorSid $BrokerRoot $AppRoot $TaskName',[StringComparison]::Ordinal)
$uninstallAt=$helperText.IndexOf('if($Mode -eq ''Uninstall'')',[StringComparison]::Ordinal)
$writeAt=$helperText.IndexOf('New-SensorDurableJournal $SensorJournalRoot $validatedSensorSid ',[StringComparison]::Ordinal)
if($ownerAt -lt 0 -or $hookAt -le $ownerAt -or $uninstallAt -le $hookAt -or
   $writeAt -le $uninstallAt){throw 'R315_HELPER_COLD_ENTRYPOINT_ORDER_INVALID'}
$checks.Add('EXACT_PE_OWNER_GUARD_COLD_REPLAY_BEFORE_NEW_MUTATION')

Absent $name
$existingReal=@(Get-ScheduledTask -TaskPath '\' -TaskName 'TaskbarMonitorEnhanced Sensor Broker' -ErrorAction SilentlyContinue|Where-Object {$null -ne $_})
if($existingReal.Count){throw 'R315_REAL_PROTECTED_TASK_PREEXISTS_GUEST'}
$checks.Add('ONLY_UNIQUE_EPHEMERAL_TASK_ALLOWED')
$admins=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
$system=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
$acl=[Security.AccessControl.DirectorySecurity]::new()
$acl.SetOwner($admins);$acl.SetAccessRuleProtection($true,$false)
foreach($s in @($admins,$system)){
 $entry=[Security.AccessControl.FileSystemAccessRule]::new(
  $s,[Security.AccessControl.FileSystemRights]::FullControl,
  [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
  [Security.AccessControl.PropagationFlags]::None,
  [Security.AccessControl.AccessControlType]::Allow)
 $acl.AddAccessRule($entry)
}
[void][IO.Directory]::CreateDirectory((Join-Path $run 'trusted'),$acl)
Assert-SensorJournalTrustedAcl (Join-Path $run 'trusted') $true
$checks.Add('PROTECTED_JOURNAL_DACL_OWNER_VERIFIED')
# Owner-protected live broker root is required by the production preflight;
# this fixture is disposable and never touches ProgramFiles.
[void][IO.Directory]::CreateDirectory($live,$acl)
[void][IO.Directory]::CreateDirectory((Join-Path $live 'settings'))
[void][IO.Directory]::CreateDirectory($appRoot)
[void][IO.Directory]::CreateDirectory($outside)
[IO.File]::WriteAllBytes($oldBroker,[Text.Encoding]::ASCII.GetBytes('R315_TRUSTED_PREVIOUS_BROKER'))
[IO.File]::WriteAllBytes($oldCfg,[Text.Encoding]::ASCII.GetBytes('R315_TRUSTED_PREVIOUS_CONFIG'))
[IO.File]::WriteAllText($canary,'R315_CANARY_IMMUTABLE')
$oldHash=FileHash $oldBroker;$cfgHash=FileHash $oldCfg;$canaryHash=FileHash $canary
$supervisor=Join-Path $live 'TaskbarMonitorSensorSupervisor.exe'
$broker=Join-Path $live 'TaskbarMonitorSensorBroker.exe'
$target=Join-Path $appRoot 'cpu_temp_broker.json'
$args='--broker "'+$broker+'" --output "'+$target+'"'
$escapedSid=[Security.SecurityElement]::Escape($sid)
$escapedCmd=[Security.SecurityElement]::Escape($supervisor)
$escapedArgs=[Security.SecurityElement]::Escape($args)
$xml=@"
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
<Triggers><LogonTrigger><Enabled>false</Enabled><UserId>$escapedSid</UserId></LogonTrigger></Triggers>
<Principals><Principal id="Author"><UserId>$escapedSid</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
<Settings><Enabled>false</Enabled><AllowStartOnDemand>false</AllowStartOnDemand></Settings>
<Actions Context="Author"><Exec><Command>$escapedCmd</Command><Arguments>$escapedArgs</Arguments></Exec></Actions>
</Task>
"@
if(-not (Assert-SensorTrustedOldTaskXml $xml $sid $live $appRoot)){
 throw 'R315_OLD_TASK_XML_NOT_PREVALIDATED'
}
$rows=[object[]]@(
 [pscustomobject]@{Rel='TaskbarMonitorSensorBroker.exe';Data=[IO.File]::ReadAllBytes($oldBroker)},
 [pscustomobject]@{Rel='settings\old.bin';Data=[IO.File]::ReadAllBytes($oldCfg)}
)
$next=[string[]]@('TaskbarMonitorSensorBroker.exe','TaskbarMonitorSensorSupervisor.exe','settings\old.bin')
New-SensorDurableJournal $journal $sid $rows $xml $next $true
$checks.Add('JOURNAL_READY_WITH_HASHED_PRIOR_TASK_AND_FILES')
$created=$false
$workerPid=0
$recoveryPid=0
try{
 Register-ScheduledTask -TaskPath '\' -TaskName $name -Xml $xml -ErrorAction Stop|Out-Null
 $created=$true
 if(-not (Test-SensorOwnedTaskRegistration $name $sid $live $appRoot)){
  throw 'R315_INITIAL_TASK_NOT_OWNED_AND_PINNED'
 }
 $checks.Add('DISABLED_PRIOR_SCHEDULER_TASK_REGISTERED_AND_VERIFIED')
 # Reject foreign SID, tainted XML, or rogue live files before interrupting.
 $foreign='S-1-5-21-101-202-303-404'
 Reject 'FOREIGN_SID_COLD_REPLAY_REFUSED' {
  Resume-SensorPendingJournal $journal $foreign $live $appRoot $name
 } 'SENSOR_COLD_ENTRYPOINT_EFFECTIVE_TOKEN_SID_MISMATCH'
 $taskFile=Join-Path $journal 'task.xml'
 $oldXmlBytes=[IO.File]::ReadAllBytes($taskFile)
 [IO.File]::WriteAllText($taskFile,'R315_TAINTED_XML')
 Reject 'TAMPERED_SAVED_TASK_REFUSED_PREWRITE' {
  Resume-SensorPendingJournal $journal $sid $live $appRoot $name
 } 'SENSOR_JOURNAL_TASK_XML_HASH_MISMATCH'
 [IO.File]::WriteAllBytes($taskFile,$oldXmlBytes)
 $bad=Join-Path $live 'unknown-file.txt'
 [IO.File]::WriteAllText($bad,'R315_UNKNOWN')
 Reject 'UNKNOWN_LIVE_FILE_REFUSED_BEFORE_REPLAY' {
  Resume-SensorPendingJournal $journal $sid $live $appRoot $name
 } 'SENSOR_JOURNAL_REPLAY_UNKNOWN_FILE'
 [IO.File]::Delete($bad)
 if((FileHash $oldBroker) -cne $oldHash -or (FileHash $oldCfg) -cne $cfgHash -or
    -not (Test-SensorOwnedTaskRegistration $name $sid $live $appRoot)){
  throw 'R315_NEGATIVE_CASE_MUTATED_LIVE_DATA'
 }
 $checks.Add('ALL_NEGATIVES_LEAVE_LIVE_AND_TASK_UNCHANGED')
 function Child([string]$mode){
  $native=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
  $psi=[Diagnostics.ProcessStartInfo]::new()
  $psi.FileName=$native
  $psi.Arguments=('-NoLogo -NoProfile -NonInteractive -File "'+$PSCommandPath+'"'+
    ' -Mode '+$mode+' -HostLabel '+$HostLabel+
    ' -CandidateDir "'+$CandidateDir+'" -Fixture "'+$run+'"')
  $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
  $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  return [Diagnostics.Process]::Start($psi)
 }
 $worker=Child Worker
 if(!$worker){throw 'R315_WORKER_START_FAIL'}
 $workerPid=$worker.Id
 try{
  $clock=[Diagnostics.Stopwatch]::StartNew()
  while(-not [IO.File]::Exists((Join-Path $run 'WORKER_CHECKPOINT')) -and
         -not $worker.HasExited -and $clock.ElapsedMilliseconds -lt 18000){
   Start-Sleep -Milliseconds 100
  }
  if(-not [IO.File]::Exists((Join-Path $run 'WORKER_CHECKPOINT')) -or $worker.HasExited){
   throw ('R315_MUTATION_CHECKPOINT_NOT_REACHED '+$worker.StandardError.ReadToEnd())
  }
  Absent $name
  if((FileHash $oldBroker) -ceq $oldHash -or
     (Get-SensorJournalTerminal $journal $sid) -cne 'PREPARED'){
   throw 'R315_TASK_LOSS_OR_MUTATION_NOT_REPRODUCED'
  }
  $worker.Kill()
  if(-not $worker.WaitForExit(9000) -or $worker.ExitCode -eq 0){
   throw 'R315_TEST_WORKER_KILL_NOT_REAL'
  }
  $checks.Add('REAL_CHILD_KILLED_AFTER_SCHEDULED_TASK_DELETION_AND_FILE_MUTATION')
 }finally{
  if(-not $worker.HasExited){$worker.Kill();[void]$worker.WaitForExit(9000)}
  $worker.Dispose()
 }
 $child=Child Recover
 if(!$child){throw 'R315_RECOVERY_CHILD_NOT_STARTED'}
 $recoveryPid=$child.Id
 try{
  if(-not $child.WaitForExit(22000) -or $child.ExitCode -ne 0){
   $msg=if($child.HasExited){$child.StandardError.ReadToEnd()}else{'TIMEOUT'}
   if($msg.Length -gt 1800){$msg=$msg.Substring(0,1800)}
   throw ('R315_FRESH_PROCESS_TASK_RESTORE_FAILED '+$msg)
  }
 }finally{
  if(-not $child.HasExited){$child.Kill();[void]$child.WaitForExit(9000)}
  $child.Dispose()
 }
 if(-not [IO.File]::Exists((Join-Path $run 'RECOVERED')) -or
    $recoveryPid -eq $workerPid -or
    (FileHash $oldBroker) -cne $oldHash -or
    (FileHash $oldCfg) -cne $cfgHash -or
    [IO.File]::Exists($newSupervisor) -or
    [IO.Directory]::Exists($journal) -or [IO.Directory]::Exists($journal+'-retired') -or
    -not (Test-SensorOwnedTaskRegistration $name $sid $live $appRoot)){
  throw 'R315_NATIVE_TASK_OR_FILES_NOT_RESTORED'
 }
 $checks.Add('FRESH_PROCESS_RESTORED_PRIOR_TASK_AND_EXACT_FILES')
 $t=Get-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction Stop
 if([string]$t.State -cne 'Disabled' -or
    [bool]$t.Settings.Enabled -ne $false -or
    [bool]$t.Triggers[0].Enabled -ne $false -or
    [IO.File]::Exists($supervisor)){
  throw 'R315_RESTORED_TASK_WAS_EXECUTABLE_OR_RUN'
 }
 $checks.Add('DISABLED_PRIOR_TASK_REINSTATED_WITHOUT_EXECUTING_SUPERVISOR')
}finally{
 if($created){
  $items=@(Get-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction SilentlyContinue | Where-Object {$null -ne $_})
  if($items.Count -eq 1){
   # Delete only the exact bounded disposable name created above.
   Unregister-ScheduledTask -TaskPath '\' -TaskName $name -Confirm:$false -ErrorAction Stop
  }
 }
}
Absent $name
$checks.Add('EPHEMERAL_TASK_REMOVED_AFTER_COLD_RESTORE')
if(@(Get-ScheduledTask -TaskPath '\' -TaskName 'TaskbarMonitorEnhanced Sensor Broker' -ErrorAction SilentlyContinue|Where-Object {$null -ne $_}).Count -ne 0){
 throw 'R315_ACTUAL_PROTECTED_SENSOR_TASK_TOUCHED'
}
if((FileHash $main) -cne $initial.Main -or
   (FileHash $config) -cne $initial.Config -or
   (FileHash $state) -cne $initial.State -or
   (FileHash $canary) -cne $canaryHash){
 throw 'R315_INSTALLED_USER_OR_CANARY_CHANGED'
}
$checks.Add('ACTUAL_MAIN_SETTINGS_AND_CANARY_IMMUTABLE')
$data=[ordered]@{
 Schema=1;Revision='R315'
 Status='PASS_PREPARED_PRODUCTION_ENTRYPOINT_COLD_REPLAY_DISPOSABLE_TASK'
 Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
 OriginalOwnerHostTouched=$false;OriginalProtectedTaskTouched=$false
 RealProgramFilesWritten=$false;ActualUACInvoked=$false
 OriginalElevatedHelperKilled=$false
 RealSyntheticWorkerKilled=$true
 FreshProcessRestoredActualDisposableScheduledTask=$true
 ProductionColdEntrypointInvoked=$true
 FilesRestoredByteExact=$true
 TaskDisabledNeverExecuted=$true
 JournalTerminalAndRetiredCleanupComplete=$true
 ForeignSidTamperAndUnknownFileRejectedPrewrite=$true
 OriginalAppDataUnchanged=$true
 WorkerPid=$workerPid;RecoveryPid=$recoveryPid
 Checks=@($checks)
 RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receipt,($data|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
'R315_NATIVE_'+$HostLabel+'_TASK_AND_FILES_COLD_REPLAY_PASS'
