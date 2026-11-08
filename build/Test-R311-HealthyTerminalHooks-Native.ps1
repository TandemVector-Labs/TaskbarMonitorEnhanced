[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$CandidateDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'R311_DISPOSABLE_GITHUB_WINDOWS_ONLY'
}
function FileSha([string]$path){
 if(-not [IO.File]::Exists($path)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
function MustReject([string]$label,[scriptblock]$callback,[string]$pattern){
 $rejected=$false
 try{& $callback}catch{
  if($_.Exception.ToString() -match $pattern){$rejected=$true}else{throw}
 }
 if(-not $rejected){throw ('R311_MISSING_REQUIRED_REFUSAL_'+$label)}
 $script:checks.Add($label)
}
$root=Join-Path $env:RUNNER_TEMP ('R311_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $root 'R311_HEALTHY_TERMINAL_HOOK_RECEIPT.json'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R310_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R310_RETIRED_JOURNAL_CLEANUP_RECEIPT.json')
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$config=Join-Path $app 'config.json'
$state=Join-Path $app 'install_state.json'
$checks=[Collections.Generic.List[string]]::new()
if([IO.Directory]::Exists($root)){throw 'R311_TEST_ROOT_PREEXISTS'}
[void][IO.Directory]::CreateDirectory($root)
$source=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
$previous=Get-Content -LiteralPath $prior -Raw|ConvertFrom-Json
$original=@{Main=(FileSha $main);Config=(FileSha $config);State=(FileSha $state)}
if($source.Commit -cne $env:GITHUB_SHA -or $source.SetupSHA256 -cne (FileSha $setup) -or
 $source.MainSHA256 -cne $original.Main -or
 $previous.SourceCommit -cne $env:GITHUB_SHA -or
 $previous.Host -cne $HostLabel -or
 $previous.Status -cne 'PASS_SYNTHETIC_RETIRED_TERMINAL_PARTIAL_CLEANUP_RESTART'){
 throw 'R311_PREDECESSOR_OR_EXACT_PE_CANDIDATE_INVALID'
}
$assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
$res=$assembly.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
if(!$res){throw 'R311_TRUSTED_EMBEDDED_HELPER_MISSING'}
$reader=[IO.StreamReader]::new($res)
try{$embedded=[string]$reader.ReadToEnd()}finally{$reader.Dispose()}
$helper=(Resolve-Path (Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1')).Path
$raw=[IO.File]::ReadAllText($helper)
$normalize={param([string]$s) $s.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $normalize $embedded) -cne (& $normalize $raw)){throw 'R311_PE_RESOURCE_SOURCE_NOT_IDENTICAL'}
$checks.Add('EMBEDDED_PE_RESOURCE_EQUALS_CURRENT_SECURITY_HELPER')
$ownerGuard=$raw.IndexOf('# R264-SENSOR-GUARD-BOUNDARY-END',[StringComparison]::Ordinal)
$preflight=[Math]::Max(
 $raw.IndexOf('Resume-SensorCompletedJournal $SensorJournalRoot $validatedSensorSid',[StringComparison]::Ordinal),
 $raw.IndexOf('Resume-SensorPendingJournal $SensorJournalRoot $validatedSensorSid $BrokerRoot $AppRoot $TaskName',[StringComparison]::Ordinal))
$uninstall=$raw.IndexOf('if($Mode -eq ''Uninstall'')',[StringComparison]::Ordinal)
$writeAhead=$raw.IndexOf('New-SensorDurableJournal $SensorJournalRoot $validatedSensorSid',[StringComparison]::Ordinal)
$health=$raw.IndexOf('if(-not $taskInstalled -or -not $SupervisorHealthy)',[StringComparison]::Ordinal)
$finalize=$raw.IndexOf('Complete-HealthySensorJournal $SensorJournalRoot $validatedSensorSid $taskInstalled $SupervisorHealthy',[StringComparison]::Ordinal)
$memRelease=$raw.LastIndexOf('Clear-SensorRollbackBuffer',[StringComparison]::Ordinal)
if($ownerGuard -lt 0 -or $preflight -le $ownerGuard -or $uninstall -le $preflight -or
   $writeAhead -le $uninstall -or $health -le $writeAhead -or
   $finalize -le $health -or $memRelease -le $finalize){
 throw 'R311_REAL_HELPER_HOOK_ORDER_NOT_PREWRITE_OR_PRE_RESULT'
}
$checks.Add('PREWRITE_OWNER_GUARD_BEFORE_INSTALL_AND_TERMINAL_BEFORE_RESULT')
$tok=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($helper,[ref]$tok,[ref]$errors)
if(@($errors).Count){throw 'R311_WINPS51_PARSE_OF_PE_RESOURCE_FAILED'}
$wanted=@('Assert-SensorBoundaryNoReparse','Get-SensorJournalHash',
 'Assert-SensorJournalRelative','Assert-SensorJournalTrustedAcl','Write-SensorJournalUnique',
 'Assert-SensorDurableJournal','New-SensorDurableJournal','Get-SensorJournalTerminal',
 'Write-SensorJournalTerminal','Restore-SensorJournalOldFilesOnly','Assert-SensorRetiredJournalSafe',
 'Finish-SensorRetiredJournal','Finish-SensorTerminalJournal',
 'Resume-SensorCompletedJournal','Complete-HealthySensorJournal')
$found=@($ast.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $wanted
},$true))
if($found.Count -ne $wanted.Count){throw 'R311_TRUSTED_PRODUCTION_HOOK_FUNCTIONS_MISSING'}
. ([scriptblock]::Create(($found|ForEach-Object {$_.Extent.Text}) -join [Environment]::NewLine))
$checks.Add('FIFTEEN_PRODUCTION_SECURITY_FUNCTIONS_LOAD_NATIVE')
$sid=[string]([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
if($sid -cnotmatch '^S-1-5-21-(?:\d+-){3}\d+$'){throw 'R311_RUNNER_SID_NOT_INTERACTIVE'}
$admin=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
$system=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
$acl=[Security.AccessControl.DirectorySecurity]::new()
$acl.SetOwner($admin)
$acl.SetAccessRuleProtection($true,$false)
foreach($principal in @($admin,$system)){
 $entry=[Security.AccessControl.FileSystemAccessRule]::new(
  $principal,[Security.AccessControl.FileSystemRights]::FullControl,
  [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
  [Security.AccessControl.PropagationFlags]::None,
  [Security.AccessControl.AccessControlType]::Allow)
 $acl.AddAccessRule($entry)
}
$parent=Join-Path $root 'protected-parent'
[void][IO.Directory]::CreateDirectory($parent,$acl)
Assert-SensorJournalTrustedAcl $parent $true
$checks.Add('SYNTHETIC_PROTECTED_PARENT_ACL_ACCEPTED')
$stage=Join-Path $parent 'journal'
$originalData=[Text.Encoding]::ASCII.GetBytes('R311_PREVIOUS_TRUSTED_BROKER')
$rows=[object[]]@([pscustomobject]@{Rel='TaskbarMonitorSensorBroker.exe';Data=$originalData})
$names=[string[]]@('TaskbarMonitorSensorBroker.exe','TaskbarMonitorSensorSupervisor.exe','.tbme-owner.sid')
$task='<Task>R311_KNOWN_PREVIOUS</Task>'
Resume-SensorCompletedJournal $stage $sid
$checks.Add('CLEAN_FIRST_INSTALL_PRECHECK_NOOP')
function NewFixture(){
 New-SensorDurableJournal $stage $sid $rows $task $names $true
 if((Get-SensorJournalTerminal $stage $sid) -cne 'PREPARED'){
  throw 'R311_NEW_FIXTURE_NOT_PREPARED'
 }
}
NewFixture
MustReject 'UNHEALTHY_SUPERVISOR_NEVER_COMMITS' {
 Complete-HealthySensorJournal $stage $sid $true $false
} 'SENSOR_JOURNAL_SUPERVISOR_NOT_HEALTHY_NO_COMMIT'
if((Get-SensorJournalTerminal $stage $sid) -cne 'PREPARED'){
 throw 'R311_UNHEALTHY_BRANCH_REMOVED_READY'
}
MustReject 'NO_OWNED_TASK_NEVER_COMMITS' {
 Complete-HealthySensorJournal $stage $sid $false $true
} 'SENSOR_JOURNAL_SUPERVISOR_NOT_HEALTHY_NO_COMMIT'
if((Get-SensorJournalTerminal $stage $sid) -cne 'PREPARED'){
 throw 'R311_NO_TASK_WAS_INCORRECTLY_COMMITTED'
}
MustReject 'PARTIAL_UNCOMMITTED_JOURNAL_BLOCKS_NEW_INSTALL' {
 Resume-SensorCompletedJournal $stage $sid
} 'SENSOR_JOURNAL_NOT_TERMINAL_DO_NOT_RETIRE'
if(-not [IO.Directory]::Exists($stage)){throw 'R311_PARTIAL_JOURNAL_REMOVED'}
Complete-HealthySensorJournal $stage $sid $true $true
if([IO.Directory]::Exists($stage) -or [IO.Directory]::Exists($stage+'-retired')){
 throw 'R311_HEALTHY_COMMIT_LEFT_RESIDUE'
}
$checks.Add('HEALTHY_TASK_AND_SUPERVISOR_COMMIT_AND_RETIRE')
Resume-SensorCompletedJournal $stage $sid
$checks.Add('REPEAT_ENTRYPOINT_AFTER_CLEAN_COMMIT_NOOP')
NewFixture
Write-SensorJournalTerminal $stage $sid 'COMMITTED'
Resume-SensorCompletedJournal $stage $sid
if([IO.Directory]::Exists($stage) -or [IO.Directory]::Exists($stage+'-retired')){
 throw 'R311_COLD_COMMITTED_COMPLETION_LEFT_RESIDUE'
}
$checks.Add('NEXT_PROCESS_VALID_COMMITTED_MARKER_RETIRED')
NewFixture
Write-SensorJournalTerminal $stage $sid 'ROLLED_BACK'
Resume-SensorCompletedJournal $stage $sid
if([IO.Directory]::Exists($stage) -or [IO.Directory]::Exists($stage+'-retired')){
 throw 'R311_VERIFIED_ROLLED_BACK_TERMINAL_WAS_NOT_RETIRED'
}
$checks.Add('OLD_TERMINAL_ROLLED_BACK_RETIRED_ON_ENTRY')
NewFixture
MustReject 'FOREIGN_EFFECTIVE_SID_CANNOT_COMPLETE_TERMINAL' {
 Complete-HealthySensorJournal $stage 'S-1-5-21-111-222-333-444' $true $true
} 'SENSOR_JOURNAL_COMMIT_EFFECTIVE_SID_MISMATCH'
if((Get-SensorJournalTerminal $stage $sid) -cne 'PREPARED'){
 throw 'R311_FOREIGN_SID_COMMITTED_JOURNAL'
}
MustReject 'FOREIGN_ID_CANNOT_CLEAN_EXISTING_READY' {
 Resume-SensorCompletedJournal $stage 'S-1-5-21-111-222-333-444'
} 'SENSOR_JOURNAL_EFFECTIVE_TOKEN_SID_MISMATCH'
$unknown=Join-Path $stage 'unowned.txt'
[IO.File]::WriteAllText($unknown,'R311_UNKNOWN',[Text.Encoding]::ASCII)
MustReject 'UNKNOWN_JOURNAL_MEMBER_NEVER_RETIRED' {
 Resume-SensorCompletedJournal $stage $sid
} 'SENSOR_JOURNAL_UNKNOWN_MEMBER'
if(-not [IO.Directory]::Exists($stage)){throw 'R311_UNKNOWN_JOURNAL_DELETED'}
[IO.File]::Delete($unknown)
$extern=Join-Path $root 'unrelated'
[void][IO.Directory]::CreateDirectory($extern)
$canary=Join-Path $extern 'preserve.txt'
[IO.File]::WriteAllText($canary,'R311_USER_CANARY',[Text.Encoding]::ASCII)
$canarySha=FileSha $canary
$junction=Join-Path $stage 'fake-junction'
New-Item -ItemType Junction -Path $junction -Target $extern -ErrorAction Stop|Out-Null
MustReject 'JUNCTION_JOURNAL_NEVER_RETIRED' {
 Resume-SensorCompletedJournal $stage $sid
} 'SENSOR_JOURNAL_REPARSE_MEMBER'
if((FileSha $canary) -cne $canarySha){throw 'R311_JUNCTION_CANARY_MODIFIED'}
[IO.Directory]::Delete($junction)
if((Get-SensorJournalTerminal $stage $sid) -cne 'PREPARED'){
 throw 'R311_NEGATIVE_BRANCH_CHANGED_JOURNAL'
}
$checks.Add('PREPARED_SNAPSHOT_UNCHANGED_AFTER_NEGATIVE_CASES')
if((FileSha $main) -cne $original.Main -or
   (FileSha $config) -cne $original.Config -or
   (FileSha $state) -cne $original.State -or
   (FileSha $canary) -cne $canarySha){
 throw 'R311_GUEST_OR_EXTERNAL_DATA_CHANGED'
}
$checks.Add('OFFICIAL_MAIN_SETTINGS_AND_OUTSIDE_CANARY_PRESERVED')
$result=[ordered]@{
 Schema=1;Revision='R311';Status='PASS_SYNTHETIC_NORMAL_HEALTHY_TERMINAL_HOOKS'
 Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
 OriginalOwnerComputerTouched=$false;ActualProgramFilesWritten=$false
 ActualUACPerformed=$false;ActualScheduledTaskModified=$false
 OriginalElevatedHelperKilled=$false
 ExactPeEntrypointHookOrderValidated=$true
 HealthyCommittedAndRetired=$true
 UnhealthyAndPreparedPreserved=$true
 ColdTerminalCleanupCompleted=$true
 WrongSidReparseUnknownRefused=$true
 ActualTaskXmlColdRestoreDone=$false
 InstalledOwnerDataUnchanged=$true
 Checks=@($checks)
 RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receipt,($result|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
'R311_'+$HostLabel+'_PRODUCTION_HEALTHY_HOOKS_SYNTHETIC_PASS'
