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
 $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
 $env:RUNNER_OS -cne 'Windows' -or $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
 [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
 [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'R310_DISPOSABLE_WINDOWS_ONLY'}
function SHA([string]$p){
 if(-not [IO.File]::Exists($p)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
}
function Reject([string]$label,[scriptblock]$probe,[string]$pattern){
 $denied=$false
 try{& $probe}catch{
  if($_.Exception.ToString() -match $pattern){$denied=$true}else{throw}
 }
 if(!$denied){throw ('R310_EXPECTED_NEGATIVE_NOT_REFUSED_'+$label)}
 $script:checks.Add($label)
}
$base=Join-Path $env:RUNNER_TEMP ('R310_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $base 'R310_RETIRED_JOURNAL_CLEANUP_RECEIPT.json'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R309_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R309_TERMINAL_REPLAY_RECEIPT.json')
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$config=Join-Path $app 'config.json'
$state=Join-Path $app 'install_state.json'
$checks=[Collections.Generic.List[string]]::new()
$asm=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
$stream=$asm.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
if(!$stream){throw 'R310_SETUP_PE_EMBEDDED_HELPER_MISSING'}
$reader=[IO.StreamReader]::new($stream)
try{$code=$reader.ReadToEnd()}finally{$reader.Dispose()}
$helper=(Resolve-Path (Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1')).Path
$normal={param([string]$s) $s.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $normal $code) -cne (& $normal ([IO.File]::ReadAllText($helper)))){
 throw 'R310_PRIVATE_PE_HELPER_SOURCE_IDENTITY_WRONG'
}
$t=$null;$err=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($helper,[ref]$t,[ref]$err)
if(@($err).Count){throw 'R310_COMPILED_WINPS51_HELPER_PARSE_FAILED'}
$wanted=@('Assert-SensorBoundaryNoReparse','Get-SensorJournalHash',
 'Assert-SensorJournalRelative','Assert-SensorJournalTrustedAcl','Write-SensorJournalUnique',
 'Assert-SensorDurableJournal','New-SensorDurableJournal','Get-SensorJournalTerminal',
 'Write-SensorJournalTerminal','Restore-SensorJournalOldFilesOnly',
 'Assert-SensorRetiredJournalSafe','Finish-SensorRetiredJournal',
 'Finish-SensorTerminalJournal')
$funcs=@($ast.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $wanted
},$true))
if($funcs.Count -ne 13){throw 'R310_PE_EXACT_13_FUNCTIONS_NOT_FOUND'}
. ([scriptblock]::Create(($funcs|ForEach-Object {$_.Extent.Text}) -join [Environment]::NewLine))
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($sid -cnotmatch '^S-1-5-21-(?:\d+-){3}\d+$'){throw 'R310_GUEST_ACCOUNT_NOT_INTERACTIVE'}
if($Mode -ne 'Driver'){
 if(-not [string]::Equals([IO.Path]::GetFullPath($Fixture),
 [IO.Path]::GetFullPath($base),[StringComparison]::OrdinalIgnoreCase) -or
 -not [IO.Directory]::Exists($base)){throw 'R310_UNKNOWN_CHILD_FIXTURE'}
 $root=Join-Path (Join-Path $base 'protected') 'stage'
 if($Mode -eq 'Worker'){
  if((Get-SensorJournalTerminal $root $sid) -cne 'COMMITTED'){
   throw 'R310_CHILD_SOURCE_NOT_COMMITTED'
  }
  [IO.Directory]::Move($root,$root+'-retired')
  $part=Join-Path ($root+'-retired') 'files\TaskbarMonitorSensorBroker.exe'
  if(-not [IO.File]::Exists($part)){throw 'R310_CHILD_SNAPSHOT_MISSING'}
  [IO.File]::Delete($part)
  [IO.File]::WriteAllText((Join-Path $base 'INTERRUPTION_CHECKPOINT'),'RETIRED_AFTER_FIRST_DELETE')
  Start-Sleep -Seconds 30
  exit 0
 }
 if($Mode -eq 'Recover'){
  Finish-SensorTerminalJournal $root $sid
  [IO.File]::WriteAllText((Join-Path $base 'CLEANUP_RECOVERED'),'RETIRED_JOURNAL_CLEAN')
  exit 0
 }
}
if([IO.Directory]::Exists($base)){throw 'R310_EXISTING_GUEST_TEST_ROOT'}
[void][IO.Directory]::CreateDirectory($base)
$oldHashes=@{Main=(SHA $main);Config=(SHA $config);State=(SHA $state)}
$c=Get-Content $manifest -Raw|ConvertFrom-Json
$p=Get-Content $prior -Raw|ConvertFrom-Json
if($c.Commit -cne $env:GITHUB_SHA -or $c.SetupSHA256 -cne (SHA $setup) -or
 $c.MainSHA256 -cne $oldHashes.Main -or $p.SourceCommit -cne $env:GITHUB_SHA -or
 $p.Host -cne $HostLabel -or
 $p.Status -cne 'PASS_SYNTHETIC_TERMINAL_AND_REAL_WORKER_COLD_FILE_REPLAY'){
 throw 'R310_EXACT_PREDECESSOR_OR_CANDIDATE_UNVERIFIED'
}
$checks.Add('COMPILED_PE_AND_PREDECESSOR_EXACT_SOURCE')
$admins=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
$system=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
$acl=[Security.AccessControl.DirectorySecurity]::new()
$acl.SetOwner($admins)
$acl.SetAccessRuleProtection($true,$false)
foreach($id in @($admins,$system)){
 $rule=[Security.AccessControl.FileSystemAccessRule]::new(
  $id,[Security.AccessControl.FileSystemRights]::FullControl,
  [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
  [Security.AccessControl.PropagationFlags]::None,
  [Security.AccessControl.AccessControlType]::Allow)
 $acl.AddAccessRule($rule)
}
$parent=Join-Path $base 'protected'
[void][IO.Directory]::CreateDirectory($parent,$acl)
Assert-SensorJournalTrustedAcl $parent $true
$checks.Add('TRUSTED_PROTECTED_PARENT_ACL')
$root=Join-Path $parent 'stage'
$rows=[object[]]@(
 [pscustomobject]@{Rel='TaskbarMonitorSensorBroker.exe';Data=[Text.Encoding]::ASCII.GetBytes('R310_PRIOR_BROKER')},
 [pscustomobject]@{Rel='settings\old.config';Data=[Text.Encoding]::ASCII.GetBytes('R310_PRIOR_CONFIG')}
)
$next=[string[]]@('TaskbarMonitorSensorBroker.exe','TaskbarMonitorSensorSupervisor.exe','settings\old.config')
$xml='<Task>R310_PRIOR_TASK</Task>'
New-SensorDurableJournal $root $sid $rows $xml $next $true
Write-SensorJournalTerminal $root $sid 'COMMITTED'
if((Get-SensorJournalTerminal $root $sid) -cne 'COMMITTED'){throw 'R310_NO_TERMINAL_STATE'}
$checks.Add('COMMITTED_TERMINAL_PUBLISHED_AND_PINNED')
function Child([string]$mode){
 $native=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
 $start=[Diagnostics.ProcessStartInfo]::new()
 $start.FileName=$native
 $start.Arguments=('-NoLogo -NoProfile -NonInteractive -File "'+$PSCommandPath+'"'+
 ' -Mode '+$mode+' -HostLabel '+$HostLabel+
 ' -CandidateDir "'+$CandidateDir+'" -Fixture "'+$base+'"')
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true
 $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 return [Diagnostics.Process]::Start($start)
}
$worker=Child Worker
if(!$worker){throw 'R310_WORKER_CREATE_FAILED'}
$workerPid=$worker.Id
$timer=[Diagnostics.Stopwatch]::StartNew()
try{
 while(-not [IO.File]::Exists((Join-Path $base 'INTERRUPTION_CHECKPOINT')) -and
        -not $worker.HasExited -and $timer.ElapsedMilliseconds -lt 18000){
  Start-Sleep -Milliseconds 100
 }
 if(-not [IO.File]::Exists((Join-Path $base 'INTERRUPTION_CHECKPOINT')) -or
    $worker.HasExited){
  throw ('R310_CHILD_CHECKPOINT_FAILED '+$worker.StandardError.ReadToEnd())
 }
 if([IO.Directory]::Exists($root) -or
    -not [IO.Directory]::Exists($root+'-retired')){
  throw 'R310_ATOMIC_RENAME_NOT_OBSERVED'
 }
 $worker.Kill()
 if(-not $worker.WaitForExit(9000) -or $worker.ExitCode -eq 0){
  throw 'R310_REAL_TEST_WORKER_DEATH_NOT_PROVEN'
 }
 $checks.Add('REAL_WORKER_KILLED_INSIDE_PARTIAL_RETIRED_CLEANUP')
}finally{
 if(-not $worker.HasExited){$worker.Kill();[void]$worker.WaitForExit(9000)}
 $worker.Dispose()
}
$restart=Child Recover
if(!$restart){throw 'R310_COLD_RECOVERY_CHILD_NOT_STARTED'}
$restartPid=$restart.Id
try{
 if(-not $restart.WaitForExit(20000) -or $restart.ExitCode -ne 0){
  $errorText=if($restart.HasExited){$restart.StandardError.ReadToEnd()}else{'TIMEOUT'}
  if($errorText.Length -gt 1600){$errorText=$errorText.Substring(0,1600)}
  throw ('R310_COLD_CLEANUP_FAILED '+$errorText)
 }
}finally{
 if(-not $restart.HasExited){$restart.Kill();[void]$restart.WaitForExit(9000)}
 $restart.Dispose()
}
if(-not [IO.File]::Exists((Join-Path $base 'CLEANUP_RECOVERED')) -or
   [IO.Directory]::Exists($root) -or [IO.Directory]::Exists($root+'-retired') -or
   $workerPid -eq $restartPid){throw 'R310_COLD_REPLAY_DID_NOT_RESTORE_EMPTY_JOURNAL'}
$checks.Add('SECOND_PROCESS_CLEARED_PARTIAL_TERMINAL_JOURNAL')
Finish-SensorTerminalJournal $root $sid
$checks.Add('EMPTY_COMPLETED_JOURNAL_CLEANUP_IDEMPOTENT')
# Negative: PREPARED journal may never be retired before rollback.
New-SensorDurableJournal $root $sid $rows $xml $next $true
Reject 'UNTERMINATED_PREPARED_JOURNAL_REFUSED' {
 Finish-SensorTerminalJournal $root $sid
} 'SENSOR_JOURNAL_NOT_TERMINAL_DO_NOT_RETIRE'
if(-not [IO.Directory]::Exists($root)){throw 'R310_UNTERMINATED_JOURNAL_REMOVED'}
Write-SensorJournalTerminal $root $sid 'ROLLED_BACK'
$checks.Add('ROLLED_BACK_TERMINAL_IS_VALID_CLEANUP_TARGET')
# Unknown entry must fail BEFORE removing any existing snapshot.
$unexpected=Join-Path $root 'unknown.bin'
[IO.File]::WriteAllText($unexpected,'R310_UNKNOWN')
$backup=Join-Path $root 'files\TaskbarMonitorSensorBroker.exe'
$before=SHA $backup
Reject 'UNKNOWN_ACTIVE_MEMBER_FAIL_CLOSED' {
 Finish-SensorTerminalJournal $root $sid
} 'SENSOR_JOURNAL_UNKNOWN_MEMBER'
if((SHA $backup) -cne $before){throw 'R310_UNKNOWN_MEMBER_DELETED_KNOWN_SNAPSHOT'}
[IO.File]::Delete($unexpected)
# Wrong token SID must refuse and leave full journal.
Reject 'FOREIGN_TOKEN_JOURNAL_PRESERVED' {
 Finish-SensorTerminalJournal $root 'S-1-5-21-111-222-333-444'
} 'SENSOR_JOURNAL_EFFECTIVE_TOKEN_SID_MISMATCH'
if((SHA $backup) -cne $before){throw 'R310_FOREIGN_SID_DESTROYED_DATA'}
$outside=Join-Path $base 'unrelated-user'
[void][IO.Directory]::CreateDirectory($outside)
$canary=Join-Path $outside 'canary.txt'
[IO.File]::WriteAllText($canary,'R310_DO_NOT_DELETE')
$canaryHash=SHA $canary
$junction=Join-Path $root 'junction'
New-Item -ItemType Junction -Path $junction -Target $outside -ErrorAction Stop|Out-Null
Reject 'ACTIVE_JUNCTION_REFUSED' {
 Finish-SensorTerminalJournal $root $sid
} 'SENSOR_JOURNAL_REPARSE_MEMBER'
if((SHA $canary) -cne $canaryHash){throw 'R310_JUNCTION_TARGET_TOUCHED'}
[IO.Directory]::Delete($junction)
Finish-SensorTerminalJournal $root $sid
if([IO.Directory]::Exists($root) -or [IO.Directory]::Exists($root+'-retired')){
 throw 'R310_ROLLED_BACK_FINISH_LEFT_RESIDUE'
}
$checks.Add('ROLLBACK_TERMINAL_NONRECURSIVE_CLEANUP')
# A retired journal containing an unknown file must not be silently purged.
New-SensorDurableJournal $root $sid $rows $xml $next $true
Write-SensorJournalTerminal $root $sid 'COMMITTED'
[IO.Directory]::Move($root,$root+'-retired')
$unknown=Join-Path ($root+'-retired') 'hostile.txt'
[IO.File]::WriteAllText($unknown,'USER_ADDED_FILE')
$protectedSnapshot=Join-Path ($root+'-retired') 'files\TaskbarMonitorSensorBroker.exe'
$priorHash=SHA $protectedSnapshot
Reject 'UNKNOWN_RETIRED_MEMBER_REFUSED_BEFORE_DELETE' {
 Finish-SensorTerminalJournal $root $sid
} 'SENSOR_RETIRED_JOURNAL_UNKNOWN_MEMBER'
if((SHA $protectedSnapshot) -cne $priorHash){throw 'R310_UNKNOWN_RETIRED_DELETED_SNAPSHOT'}
[IO.File]::Delete($unknown)
Finish-SensorTerminalJournal $root $sid
if([IO.Directory]::Exists($root) -or [IO.Directory]::Exists($root+'-retired')){
 throw 'R310_RETIRED_RECOVERY_NOT_COMPLETE'
}
$checks.Add('UNKNOWN_RETIRED_NEGATIVE_AND_RETRY_CLEANUP')
if((SHA $canary) -cne $canaryHash -or (SHA $main) -cne $oldHashes.Main -or
 (SHA $config) -cne $oldHashes.Config -or (SHA $state) -cne $oldHashes.State){
 throw 'R310_OWNER_OR_UNRELATED_CANARY_CHANGED'
}
$checks.Add('INSTALLED_MAIN_CONFIG_STATE_AND_CANARY_UNCHANGED')
$report=[ordered]@{
 Schema=1;Revision='R310';Status='PASS_SYNTHETIC_RETIRED_TERMINAL_PARTIAL_CLEANUP_RESTART'
 Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
 OriginalOwnerComputerTouched=$false;RealProgramFilesWritten=$false
 ActualUACOrProtectedTaskModified=$false;ActualOriginalElevatedHelperKilled=$false
 RealProofWorkerKilledDuringCleanup=$true;FreshProcessFinishedRetiredCleanup=$true
 NonrecursiveKnownMemberDeletion=$true;UnknownFilesAndJunctionFailClosed=$true
 ForeignSIDAndPreparedPhaseRefused=$true;TerminatedJournalEventuallyRemoved=$true
 UserDataAndCanaryUnchanged=$true
 WorkerPid=$workerPid;RestartPid=$restartPid
 Checks=@($checks);RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receipt,($report|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
'R310_NATIVE_'+$HostLabel+'_PARTIAL_NONRECURSIVE_CLEANUP_PASS'
