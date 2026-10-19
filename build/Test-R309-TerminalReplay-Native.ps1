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
 [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
 [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
 [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'R309_ONLY_DISPOSABLE_HOSTED_WINDOWS'
}
function SHA([string]$f){
 if(-not [IO.File]::Exists($f)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash
}
function AssertFails([string]$key,[scriptblock]$probe,[string]$pattern){
 $rejected=$false
 try{& $probe}catch{
  if($_.Exception.ToString() -match $pattern){$rejected=$true}else{throw}
 }
 if(-not $rejected){throw ('R309_EXPECTED_REFUSAL_NOT_OBSERVED_'+$key)}
 $script:checks.Add($key)
}
$root=Join-Path $env:RUNNER_TEMP ('R309_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $root 'R309_TERMINAL_REPLAY_RECEIPT.json'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R308_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R308_JOURNAL_PREWRITE_RECEIPT.json')
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$config=Join-Path $app 'config.json'
$state=Join-Path $app 'install_state.json'
$checks=[Collections.Generic.List[string]]::new()
# Load ONLY extracted PE-source security functions. Never invoke the actual
# elevated Helper entrypoint, UAC, any task or real ProgramFiles files.
$asm=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
$resource=$asm.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
if(!$resource){throw 'R309_COMPILED_PE_HELPER_RESOURCE_MISSING'}
$reader=[IO.StreamReader]::new($resource)
try{$src=$reader.ReadToEnd()}finally{$reader.Dispose()}
$helper=(Resolve-Path (Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1')).Path
$normalize={param([string]$s) $s.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $normalize $src) -cne (& $normalize ([IO.File]::ReadAllText($helper)))){
 throw 'R309_PE_HELPER_SOURCE_NOT_EXACT'
}
$t=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($helper,[ref]$t,[ref]$errors)
if(@($errors).Count){throw 'R309_SOURCE_WINPS51_PARSER_FAILURE'}
$names=@('Assert-SensorBoundaryNoReparse','Get-SensorJournalHash',
 'Assert-SensorJournalRelative','Assert-SensorJournalTrustedAcl',
 'Write-SensorJournalUnique','Assert-SensorDurableJournal','New-SensorDurableJournal',
 'Get-SensorJournalTerminal','Write-SensorJournalTerminal','Restore-SensorJournalOldFilesOnly')
$found=@($ast.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
 $node.Name -in $names
},$true))
if($found.Count -ne $names.Count){throw 'R309_EXACT_PE_PRODUCTION_REPLAY_FUNCTIONS_MISSING'}
. ([scriptblock]::Create(($found|ForEach-Object {$_.Extent.Text}) -join [Environment]::NewLine))
$identity=[string]([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
if($identity -cnotmatch '^S-1-5-21-(?:\d+-){3}\d+$'){throw 'R309_NONINTERACTIVE_RUNNER_SID'}
if($Mode -ne 'Driver'){
 if([IO.Path]::GetFullPath($Fixture) -cne [IO.Path]::GetFullPath($root) -or
    -not [IO.Directory]::Exists($root)){throw 'R309_UNTRUSTED_PROOF_WORKER_FIXTURE'}
 $live=Join-Path $root 'live-broker'
 $journal=Join-Path (Join-Path $root 'protected-parent') 'stage'
 $old=Join-Path $live 'TaskbarMonitorSensorBroker.exe'
 $newFile=Join-Path $live 'TaskbarMonitorSensorSupervisor.exe'
 if($Mode -eq 'Worker'){
  [IO.File]::WriteAllBytes($old,[Text.Encoding]::ASCII.GetBytes('R309_NEW_DIFFERENT_BROKER'))
  [IO.File]::WriteAllBytes($newFile,[Text.Encoding]::ASCII.GetBytes('R309_NEW_SUPERVISOR'))
  [IO.File]::WriteAllText((Join-Path $root 'WORKER_CHECKPOINT'),'LIVE_MUTATED_AFTER_READY',[Text.Encoding]::ASCII)
  Start-Sleep -Seconds 28
  exit 0
 }
 if($Mode -eq 'Recover'){
  $xml=Restore-SensorJournalOldFilesOnly $journal $identity $live
  if($xml -cne '<Task>R309_OLD_TASK_XML</Task>'){throw 'R309_RECOVERY_TASK_XML_NOT_RESTORED'}
  Write-SensorJournalTerminal $journal $identity 'ROLLED_BACK'
  [IO.File]::WriteAllText((Join-Path $root 'RECOVERED'),'COLD_PROOF_WORKER_COMPLETED',[Text.Encoding]::ASCII)
  exit 0
 }
}
if(Test-Path -LiteralPath $root){throw 'R309_TEST_ROOT_ALREADY_EXISTS'}
[void][IO.Directory]::CreateDirectory($root)
$before=@{Main=(SHA $main);Config=(SHA $config);State=(SHA $state)}
$c=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
$p=Get-Content -LiteralPath $prior -Raw|ConvertFrom-Json
if($c.Commit -cne $env:GITHUB_SHA -or $c.SetupSHA256 -cne (SHA $setup) -or
   $c.MainSHA256 -cne $before.Main -or
   $p.SourceCommit -cne $env:GITHUB_SHA -or $p.Host -cne $HostLabel -or
   $p.Status -cne 'PASS_PRODUCTION_JOURNAL_PREWRITE_FUNCTIONS_SYNTHETIC'){
 throw 'R309_EXACT_SOURCE_OR_PREVIOUS_WITNESS_MISMATCH'
}
$checks.Add('EXACT_PE_HELPER_AND_PREDECESSOR_SOURCE_BOUND')
$admins=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
$sys=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
$sec=[Security.AccessControl.DirectorySecurity]::new()
$sec.SetOwner($admins)
$sec.SetAccessRuleProtection($true,$false)
foreach($id in @($admins,$sys)){
 $rule=[Security.AccessControl.FileSystemAccessRule]::new($id,
 [Security.AccessControl.FileSystemRights]::FullControl,
 [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
 [Security.AccessControl.PropagationFlags]::None,
 [Security.AccessControl.AccessControlType]::Allow)
 $sec.AddAccessRule($rule)
}
$parent=Join-Path $root 'protected-parent'
[void][IO.Directory]::CreateDirectory($parent,$sec)
Assert-SensorJournalTrustedAcl $parent $true
$checks.Add('PRIVATE_TRUSTED_DACL_WITH_SYSTEM_ADMIN_OWNERSHIP')
$live=Join-Path $root 'live-broker'
[void][IO.Directory]::CreateDirectory($live)
$old=Join-Path $live 'TaskbarMonitorSensorBroker.exe'
$cfg=Join-Path $live 'settings\sensor.bin'
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($cfg))
[IO.File]::WriteAllBytes($old,[Text.Encoding]::ASCII.GetBytes('R309_ORIGINAL_BROKER'))
[IO.File]::WriteAllBytes($cfg,[Text.Encoding]::ASCII.GetBytes('R309_ORIGINAL_CONFIG'))
$oldHash=SHA $old;$configHash=SHA $cfg
$external=Join-Path $root 'unrelated'
[void][IO.Directory]::CreateDirectory($external)
$canary=Join-Path $external 'canary.txt'
[IO.File]::WriteAllText($canary,'R309_KEEP_OUTSIDE',[Text.Encoding]::ASCII)
$externalHash=SHA $canary
$journal=Join-Path $parent 'stage'
$rows=[object[]]@(
 [pscustomobject]@{Rel='TaskbarMonitorSensorBroker.exe';Data=[IO.File]::ReadAllBytes($old)},
 [pscustomobject]@{Rel='settings\sensor.bin';Data=[IO.File]::ReadAllBytes($cfg)}
)
$next=[string[]]@('TaskbarMonitorSensorBroker.exe','TaskbarMonitorSensorSupervisor.exe','settings\sensor.bin')
New-SensorDurableJournal $journal $identity $rows '<Task>R309_OLD_TASK_XML</Task>' $next $true
if((Get-SensorJournalTerminal $journal $identity) -cne 'PREPARED'){throw 'R309_NEW_JOURNAL_NOT_PREPARED'}
$checks.Add('READY_PUBLISHED_AND_PREPARED_STATE_VALIDATED')
function StartProof([string]$mode){
 $exe=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
 $psi=[Diagnostics.ProcessStartInfo]::new()
 $psi.FileName=$exe
 $psi.Arguments=('-NoLogo -NoProfile -NonInteractive -File "'+$PSCommandPath+
  '" -Mode '+$mode+' -HostLabel '+$HostLabel+
  ' -CandidateDir "'+$CandidateDir+'" -Fixture "'+$root+'"')
 $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
 $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
 return [Diagnostics.Process]::Start($psi)
}
$worker=StartProof Worker
if(!$worker){throw 'R309_SYNTHETIC_MUTATOR_NOT_STARTED'}
$workerPid=$worker.Id
$timer=[Diagnostics.Stopwatch]::StartNew()
try{
 while(-not [IO.File]::Exists((Join-Path $root 'WORKER_CHECKPOINT')) -and
  -not $worker.HasExited -and $timer.ElapsedMilliseconds -lt 17000){
  Start-Sleep -Milliseconds 100
 }
 if(-not [IO.File]::Exists((Join-Path $root 'WORKER_CHECKPOINT')) -or
    $worker.HasExited){
  throw ('R309_WORKER_NEVER_REACHED_MUTATION '+$worker.StandardError.ReadToEnd())
 }
 if((SHA $old) -ceq $oldHash -or
    (Get-SensorJournalTerminal $journal $identity) -cne 'PREPARED'){
  throw 'R309_MUTATION_BEFORE_REAL_WORKER_DEATH_MISSING'
 }
 $worker.Kill()
 if(-not $worker.WaitForExit(10000) -or $worker.ExitCode -eq 0){
  throw 'R309_ACTUAL_SYNTHETIC_WORKER_KILL_NOT_CONFIRMED'
 }
 $checks.Add('REAL_SEPARATE_PROOF_WORKER_KILLED_AFTER_LIVE_MUTATION')
}finally{
 if(-not $worker.HasExited){$worker.Kill();[void]$worker.WaitForExit(10000)}
 $worker.Dispose()
}
$recover=StartProof Recover
if(!$recover){throw 'R309_RECOVERY_PROCESS_NOT_CREATED'}
$recoveryPid=$recover.Id
try{
 if(-not $recover.WaitForExit(20000) -or $recover.ExitCode -ne 0){
  $err=if($recover.HasExited){$recover.StandardError.ReadToEnd()}else{'TIMEOUT'}
  if($err.Length -gt 1500){$err=$err.Substring(0,1500)}
  throw ('R309_NATIVE_FRESH_RECOVERY_FAILED '+$err)
 }
}finally{
 if(-not $recover.HasExited){$recover.Kill();[void]$recover.WaitForExit(10000)}
 $recover.Dispose()
}
if(-not [IO.File]::Exists((Join-Path $root 'RECOVERED')) -or
   $workerPid -eq $recoveryPid -or (SHA $old) -cne $oldHash -or
   (SHA $cfg) -cne $configHash -or
   [IO.File]::Exists((Join-Path $live 'TaskbarMonitorSensorSupervisor.exe')) -or
   (Get-SensorJournalTerminal $journal $identity) -cne 'ROLLED_BACK'){
 throw 'R309_COLD_WORKER_RECOVERY_DATA_OR_STATE_FAILED'
}
$checks.Add('FRESH_SEPARATE_PROCESS_RESTORES_EXACT_OLD_BYTES')
$checks.Add('ROLLED_BACK_TERMINAL_MARKER_DURABLE')
$xml=Restore-SensorJournalOldFilesOnly $journal $identity $live
if($xml -cne '<Task>R309_OLD_TASK_XML</Task>'){throw 'R309_REPEAT_RECOVERY_TASK_XML_WRONG'}
Write-SensorJournalTerminal $journal $identity 'ROLLED_BACK'
$checks.Add('REPEAT_RECOVERY_IDEMPOTENT_AFTER_TERMINAL')
AssertFails 'CONFLICTING_COMMIT_MARKER_REJECTED' {
 Write-SensorJournalTerminal $journal $identity 'COMMITTED'
} 'SENSOR_JOURNAL_TERMINAL_CONFLICT'
# Reject tainted old snapshot before any live byte is replaced.
$sourceBlob=Join-Path $journal 'files\TaskbarMonitorSensorBroker.exe'
$trusted=[IO.File]::ReadAllBytes($sourceBlob)
[IO.File]::WriteAllBytes($old,[Text.Encoding]::ASCII.GetBytes('R309_LIVE_PRESERVE_ON_ERROR'))
$beforeRefuse=SHA $old
[IO.File]::WriteAllBytes($sourceBlob,[Text.Encoding]::ASCII.GetBytes('R309_TAMPERED_BACKUP'))
AssertFails 'INVALID_SNAPSHOT_PREWRITE_REFUSED' {
 [void](Restore-SensorJournalOldFilesOnly $journal $identity $live)
} 'SENSOR_JOURNAL_SNAPSHOT_HASH_MISMATCH|SENSOR_JOURNAL_REPLAY_SHA_MISMATCH'
if((SHA $old) -cne $beforeRefuse){throw 'R309_TAMPERED_BACKUP_CHANGED_LIVE_FILE'}
[IO.File]::WriteAllBytes($sourceBlob,$trusted)
# Unknown live member must block any attempted restore.
$extra=Join-Path $live 'unauthorized-user.txt'
[IO.File]::WriteAllText($extra,'UNAUTHORIZED',[Text.Encoding]::ASCII)
AssertFails 'UNKNOWN_LIVE_MEMBER_REFUSED_PREWRITE' {
 [void](Restore-SensorJournalOldFilesOnly $journal $identity $live)
} 'SENSOR_JOURNAL_REPLAY_UNKNOWN_FILE'
if((SHA $old) -cne $beforeRefuse){throw 'R309_UNKNOWN_LIVE_MEMBER_CHANGED_LIVE_FILE'}
[IO.File]::Delete($extra)
$junction=Join-Path $live 'rogue-junction'
New-Item -ItemType Junction -Path $junction -Target $external -ErrorAction Stop|Out-Null
AssertFails 'LIVE_JUNCTION_REFUSED_BEFORE_REPLAY' {
 [void](Restore-SensorJournalOldFilesOnly $journal $identity $live)
} 'SENSOR_JOURNAL_REPLAY_LIVE_REPARSE_REFUSED'
[IO.Directory]::Delete($junction)
$taskPath=Join-Path $journal 'task.xml'
$taskOriginal=[IO.File]::ReadAllBytes($taskPath)
[IO.File]::WriteAllText($taskPath,'R309_TAMPER',[Text.Encoding]::ASCII)
AssertFails 'SAVED_TASK_XML_TAMPER_REFUSED' {
 [void](Restore-SensorJournalOldFilesOnly $journal $identity $live)
} 'SENSOR_JOURNAL_TASK_XML_HASH_MISMATCH'
[IO.File]::WriteAllBytes($taskPath,$taskOriginal)
AssertFails 'CROSS_USER_SID_REPLAY_REFUSED' {
 [void](Restore-SensorJournalOldFilesOnly $journal 'S-1-5-21-111-222-333-444' $live)
} 'SENSOR_JOURNAL_EFFECTIVE_TOKEN_SID_MISMATCH'
# COMMITTED is terminal and never authorizes rollback.
$other=Join-Path $parent 'committed'
New-SensorDurableJournal $other $identity $rows '<Task>R309_OLD_TASK_XML</Task>' $next $true
Write-SensorJournalTerminal $other $identity 'COMMITTED'
if((Get-SensorJournalTerminal $other $identity) -cne 'COMMITTED'){
 throw 'R309_COMMITTED_MARKER_NOT_READ_BACK'
}
AssertFails 'COMMITTED_JOURNAL_CANNOT_REVERT_LIVE_LAYER' {
 [void](Restore-SensorJournalOldFilesOnly $other $identity $live)
} 'SENSOR_JOURNAL_REPLAY_REQUIRES_PREPARED_STATE'
$checks.Add('COMMITTED_TERMINAL_READBACK_PASS')
# End-of-test invariants: no user/system service/registry mutation.
if((SHA $canary) -cne $externalHash -or
   (SHA $main) -cne $before.Main -or
   (SHA $config) -cne $before.Config -or
   (SHA $state) -cne $before.State){
 throw 'R309_GUEST_OWNER_OR_UNRELATED_CANARY_CHANGED'
}
$checks.Add('GUEST_INSTALLED_USER_AND_UNRELATED_BYTES_IMMUTABLE')
$result=[ordered]@{
 Schema=1;Revision='R309'
 Status='PASS_SYNTHETIC_TERMINAL_AND_REAL_WORKER_COLD_FILE_REPLAY'
 Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
 ActualOriginalElevatedHelperKilled=$false;ActualProtectedTaskTouched=$false
 RealProgramFilesWritten=$false;UACInvoked=$false;OwnerComputerTouched=$false
 ActualSyntheticWorkerKilled=$true;FreshPowerShellRecoveredOldFiles=$true
 ProductionPEReplayFunctionsVerified=$true
 TerminalCommittedAndRolledBackVerified=$true
 PinnedTaskXmlRecoveredAsDataNotRegistered=$true
 TamperAndForeignSidFailedClosed=$true
 UnknownFileAndJunctionFailedClosed=$true
 OfficialInstalledMainAndUserConfigUnchanged=$true
 WorkerPid=$workerPid;RecoveryPid=$recoveryPid
 Checks=@($checks);RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receipt,($result|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
'R309_NATIVE_'+$HostLabel+'_TERMINAL_AND_COLD_FILE_REPLAY_PASS'
