[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$CandidateDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
 $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
 $env:RUNNER_OS -cne 'Windows' -or $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
 [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
 [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
 [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'R308_DISPOSABLE_WINDOWS_ONLY'
}
function FileHash([string]$path){
 if(!(Test-Path -LiteralPath $path -PathType Leaf)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
function Refused([string]$name,[scriptblock]$test,[string]$pattern){
 $caught=$false
 try{& $test}catch{
  if($_.Exception.ToString() -match $pattern){$caught=$true}else{throw}
 }
 if(!$caught){throw ('R308_TEST_FAILED_OPEN_'+$name)}
 $script:checks.Add($name)
}
$dir=Join-Path $env:RUNNER_TEMP ('R308_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $dir 'R308_JOURNAL_PREWRITE_RECEIPT.json'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R307_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R307_PROTECTED_JOURNAL_ACL_RECEIPT.json')
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$config=Join-Path $app 'config.json'
$state=Join-Path $app 'install_state.json'
$checks=[Collections.Generic.List[string]]::new()
if(Test-Path -LiteralPath $dir){throw 'R308_GUEST_TEST_ROOT_ALREADY_EXISTS'}
[void][IO.Directory]::CreateDirectory($dir)
$live=@{Main=(FileHash $main);Config=(FileHash $config);State=(FileHash $state)}
$source=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
$previous=Get-Content -LiteralPath $prior -Raw|ConvertFrom-Json
if($source.Commit -cne $env:GITHUB_SHA -or $source.SetupSHA256 -cne (FileHash $setup) -or
 $source.MainSHA256 -cne $live.Main -or
 $previous.SourceCommit -cne $env:GITHUB_SHA -or $previous.Host -cne $HostLabel -or
 $previous.Status -cne 'PASS_PROTECTED_JOURNAL_ACL_TRUST_BOUNDARY_SYNTHETIC'){
 throw 'R308_CANDIDATE_OR_R307_EVIDENCE_NOT_EXACT'
}
$assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
$stream=$assembly.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
if(!$stream){throw 'R308_PE_EMBEDDED_HELPER_MISSING'}
$reader=[IO.StreamReader]::new($stream)
try{$embedded=[string]$reader.ReadToEnd()}finally{$reader.Dispose()}
$helper=(Resolve-Path (Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1')).Path
$raw=[IO.File]::ReadAllText($helper)
$normalize={param([string]$s) $s.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $normalize $embedded) -cne (& $normalize $raw)){
 throw 'R308_SOURCE_DIFFERS_FROM_COMPILED_SETUP_PE'
}
$checks.Add('SAME_EXACT_PE_EMBEDDED_HELPER_SOURCE')
$save=$raw.IndexOf('New-SensorDurableJournal $SensorJournalRoot $validatedSensorSid ',[StringComparison]::Ordinal)
$mutation=$raw.IndexOf('    Assert-OrRecordSensorOwner',[StringComparison]::Ordinal)
$ownerBoundary=$raw.IndexOf('# R264-SENSOR-GUARD-BOUNDARY-END',[StringComparison]::Ordinal)
$legacyStale=$raw.IndexOf('if(Test-Path -LiteralPath $SensorJournalRoot)',[StringComparison]::Ordinal)
$protectedPreflight=[Math]::Max(
 $raw.IndexOf('Resume-SensorCompletedJournal $SensorJournalRoot $validatedSensorSid',[StringComparison]::Ordinal),
 $raw.IndexOf('Resume-SensorPendingJournal $SensorJournalRoot $validatedSensorSid $BrokerRoot $AppRoot $TaskName',[StringComparison]::Ordinal))
if($save -lt 0 -or $mutation -le $save -or $ownerBoundary -lt 0 -or
   ($legacyStale -lt 0 -and $protectedPreflight -lt 0) -or
   ($protectedPreflight -ge 0 -and
    ($protectedPreflight -le $ownerBoundary -or $protectedPreflight -ge $save))){
 throw 'R308_JOURNAL_NOT_BEFORE_FIRST_PROTECTED_MUTATION'
}
$checks.Add('STALE_JOURNAL_REFUSAL_AND_PREMUTATION_ORDER')
$tok=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($helper,[ref]$tok,[ref]$errors)
if(@($errors).Count){throw 'R308_POWERSHELL51_PARSER_REJECTED_HELPER'}
$names=@('Assert-SensorBoundaryNoReparse','Get-SensorJournalHash',
 'Assert-SensorJournalRelative','Assert-SensorJournalTrustedAcl',
 'Write-SensorJournalUnique','Assert-SensorDurableJournal','New-SensorDurableJournal')
$defs=@($ast.FindAll({param($n)
 $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in $names
},$true))
if($defs.Count -ne 7){throw 'R308_EXACT_SEVEN_FUNCTIONS_MISSING'}
. ([scriptblock]::Create(($defs|ForEach-Object {$_.Extent.Text}) -join [Environment]::NewLine))
$checks.Add('COMPILED_PRODUCTION_FUNCTIONS_LOADED_NATIVE_PS51')
$admin=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
$system=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
$acl=[Security.AccessControl.DirectorySecurity]::new()
$acl.SetOwner($admin);$acl.SetAccessRuleProtection($true,$false)
foreach($sid in @($admin,$system)){
 $rule=[Security.AccessControl.FileSystemAccessRule]::new(
  $sid,[Security.AccessControl.FileSystemRights]::FullControl,
  [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
  [Security.AccessControl.PropagationFlags]::None,
  [Security.AccessControl.AccessControlType]::Allow)
 $acl.AddAccessRule($rule)
}
$parent=Join-Path $dir 'trusted-synthetic-parent'
[void][IO.Directory]::CreateDirectory($parent,$acl)
Assert-SensorJournalTrustedAcl $parent $true
$checks.Add('OWNER_AND_EXPLICIT_PROTECTED_PARENT_DACL')
$broker=Join-Path $dir 'synthetic-broker'
[void][IO.Directory]::CreateDirectory($broker)
$oldFile=Join-Path $broker 'TaskbarMonitorSensorBroker.exe'
$oldConfig=Join-Path $broker 'lang\config.bin'
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($oldConfig))
[IO.File]::WriteAllBytes($oldFile,[Text.Encoding]::ASCII.GetBytes('R308_KNOWN_OLD_BROKER'))
[IO.File]::WriteAllBytes($oldConfig,[Text.Encoding]::ASCII.GetBytes('R308_KNOWN_OLD_CONFIG'))
$originalBroker=FileHash $oldFile;$originalConfig=FileHash $oldConfig
$outside=Join-Path $dir 'external'
[void][IO.Directory]::CreateDirectory($outside)
$canary=Join-Path $outside 'preserve.txt'
[IO.File]::WriteAllText($canary,'R308_OUTSIDE_CANARY',[Text.Encoding]::ASCII)
$canaryHash=FileHash $canary
$rows=[object[]]@(
 [pscustomobject]@{Rel='TaskbarMonitorSensorBroker.exe';Data=[IO.File]::ReadAllBytes($oldFile)},
 [pscustomobject]@{Rel='lang\config.bin';Data=[IO.File]::ReadAllBytes($oldConfig)}
)
$next=[string[]]@('TaskbarMonitorSensorBroker.exe','TaskbarMonitorSensorSupervisor.exe','.tbme-owner.sid','lang\config.bin')
$identity=[string]([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
if($identity -cnotmatch '^S-1-5-21-(?:\d+-){3}\d+$'){throw 'R308_GUEST_NOT_INTERACTIVE_USER'}
$xml='<Task>R308_ORIGINAL_SYNTHETIC_TASK</Task>'
$journal=Join-Path $parent '.tbme-sensor-rollback'
New-SensorDurableJournal $journal $identity $rows $xml $next $true
if(!(Test-Path (Join-Path $journal 'READY')) -or
 (FileHash $oldFile) -cne $originalBroker -or (FileHash $oldConfig) -cne $originalConfig){
 throw 'R308_DURABLE_READY_NOT_PREMUTATION'
}
$validated=Assert-SensorDurableJournal $journal $identity
if(@($validated.Files).Count -ne 2 -or @($validated.ExpectedNewFiles).Count -ne 4 -or
 $validated.TaskPresent -ne $true -or $validated.OldRootPresent -ne $true){
 throw 'R308_SERIALIZED_DURABLE_MANIFEST_INVALID'
}
$checks.Add('DURABLE_READY_AND_MANIFEST_OLD_BYTES_XML_VERIFIED')
Refused 'DUPLICATE_JOURNAL_REFUSED' {
 New-SensorDurableJournal $journal $identity $rows $xml $next $true
} 'SENSOR_JOURNAL_ALREADY_EXISTS'
$foreign='S-1-5-21-111-222-333-444'
Refused 'FOREIGN_EFFECTIVE_SID_REFUSED_PREWRITE' {
 New-SensorDurableJournal (Join-Path $parent 'other-sid') $foreign $rows $xml $next $true
} 'SENSOR_JOURNAL_TOKEN_MISMATCH'
if(Test-Path (Join-Path $parent 'other-sid')){throw 'R308_FOREIGN_SID_CREATED_JOURNAL'}
Refused 'SAVED_JOURNAL_FOREIGN_SID_REFUSED' {
 [void](Assert-SensorDurableJournal $journal $foreign)
} 'SENSOR_JOURNAL_OWNER_OR_PHASE_MISMATCH'
$taskFile=Join-Path $journal 'task.xml'
$originalTask=[IO.File]::ReadAllBytes($taskFile)
[IO.File]::WriteAllText($taskFile,'R308_FAKE_XML',[Text.Encoding]::ASCII)
Refused 'TASK_XML_TAMPER_DETECTED' {
 [void](Assert-SensorDurableJournal $journal $identity)
} 'SENSOR_JOURNAL_TASK_XML_HASH_MISMATCH'
[IO.File]::WriteAllBytes($taskFile,$originalTask)
$saved=Join-Path $journal 'files\TaskbarMonitorSensorBroker.exe'
$originalSaved=[IO.File]::ReadAllBytes($saved)
[IO.File]::WriteAllText($saved,'R308_TAMPERED',[Text.Encoding]::ASCII)
Refused 'SNAPSHOT_BYTE_TAMPER_DETECTED' {
 [void](Assert-SensorDurableJournal $journal $identity)
} 'SENSOR_JOURNAL_SNAPSHOT_HASH_MISMATCH'
[IO.File]::WriteAllBytes($saved,$originalSaved)
$unexpected=Join-Path $journal 'unexpected.txt'
[IO.File]::WriteAllText($unexpected,'R308_UNEXPECTED',[Text.Encoding]::ASCII)
Refused 'UNKNOWN_MEMBER_REJECTED' {
 [void](Assert-SensorDurableJournal $journal $identity)
} 'SENSOR_JOURNAL_UNKNOWN_MEMBER'
[IO.File]::Delete($unexpected)
$link=Join-Path $journal 'junction'
New-Item -ItemType Junction -Path $link -Target $outside -ErrorAction Stop|Out-Null
Refused 'NATIVE_JUNCTION_NOT_FOLLOWED' {
 [void](Assert-SensorDurableJournal $journal $identity)
} 'SENSOR_JOURNAL_REPARSE_MEMBER'
[IO.Directory]::Delete($link)
$incomplete=Join-Path $parent 'incomplete'
[void][IO.Directory]::CreateDirectory($incomplete,$acl)
Refused 'INCOMPLETE_READY_REFUSED' {
 [void](Assert-SensorDurableJournal $incomplete $identity)
} 'SENSOR_JOURNAL_INCOMPLETE_OR_UNREADY'
$unsafe=Join-Path $dir 'user-writable-parent'
[void][IO.Directory]::CreateDirectory($unsafe)
Refused 'WRITABLE_PARENT_REFUSED_BEFORE_CREATE' {
 New-SensorDurableJournal (Join-Path $unsafe '.tbme-sensor-rollback') $identity $rows $xml $next $true
} 'SENSOR_JOURNAL_UNTRUSTED_OWNER|SENSOR_JOURNAL_UNTRUSTED_WRITE_ACE'
if(Test-Path (Join-Path $unsafe '.tbme-sensor-rollback')){
 throw 'R308_INSECURE_PARENT_JOURNAL_CREATED'
}
if((FileHash $oldFile) -cne $originalBroker -or (FileHash $oldConfig) -cne $originalConfig -or
 (FileHash $canary) -cne $canaryHash -or
 (FileHash $main) -cne $live.Main -or (FileHash $config) -cne $live.Config -or
 (FileHash $state) -cne $live.State){throw 'R308_INSTALLED_OR_SYNTHETIC_LIVE_DATA_CHANGED'}
$checks.Add('MAIN_CONFIG_STATE_AND_EXTERNAL_CANARY_IMMUTABLE')
$data=[ordered]@{
 Schema=1;Revision='R308';Status='PASS_PRODUCTION_JOURNAL_PREWRITE_FUNCTIONS_SYNTHETIC'
 Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
 OwnerComputerTouched=$false;ActualProgramFilesWritten=$false
 ActualScheduledTaskModified=$false;ActualUACInvoked=$false
 ActualProtectedSensorHelperKilled=$false
 ProductionFunctionsExtractedFromExactPE=$true
 JournalReadyPublishedPreMutation=$true
 StaleJournalFailsClosed=$true
 SIDAndHashAndReparseFailClosed=$true
 ExternalUserDataUnchanged=$true
 TerminalCleanupAndColdRecoveryImplemented=$false
 Checks=@($checks)
 RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receipt,($data|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
'R308_'+$HostLabel+'_PRODUCTION_JOURNAL_PREWRITE_SYNTHETIC_PASS'
