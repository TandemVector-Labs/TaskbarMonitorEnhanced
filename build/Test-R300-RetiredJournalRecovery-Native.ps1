[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$CandidateDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# No permission to run against owner desktop or mutate its running installation.
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'R300_ONLY_DISPOSABLE_WINDOWS_RUNNER'
}
function Hash([string]$file){
 if(!(Test-Path -LiteralPath $file -PathType Leaf)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
}
function Invoke-Recover([Reflection.MethodInfo]$method){
 [void]$method.Invoke($null,[object[]]::new(0))
}
function Expect-Refused([string]$label,[Reflection.MethodInfo]$method,[string]$pattern){
 $refused=$false
 try{Invoke-Recover $method}catch{
  if($_.Exception.ToString() -match $pattern){$refused=$true}else{throw}
 }
 if(!$refused){throw ('R300_FAIL_OPEN_'+$label)}
 $script:checks.Add($label)
}
$testRoot=Join-Path $env:RUNNER_TEMP ('R300_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $testRoot 'R300_RETIRED_JOURNAL_RECEIPT.json'
$outside=Join-Path $testRoot 'external-canary'
$canary=Join-Path $outside 'never-delete.txt'
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$stage=Join-Path $app '.tbme-upgrade'
$retired=Join-Path $app '.tbme-upgrade-retired'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R299_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R299_NONRECURSIVE_CLEANUP_RECEIPT.json')
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$config=Join-Path $app 'config.json'
$state=Join-Path $app 'install_state.json'
$checks=[Collections.Generic.List[string]]::new()
if((Test-Path -LiteralPath $testRoot) -or
   (Test-Path -LiteralPath $stage) -or
   (Test-Path -LiteralPath $retired) -or
   @((Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue)).Count -ne 0){
 throw 'R300_UNEXPECTED_STAGE_FIXTURE_OR_RUNNING_APP'
}
$candidate=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
$old=Get-Content -LiteralPath $prior -Raw|ConvertFrom-Json
if($candidate.Commit -cne $env:GITHUB_SHA -or
   (Hash $setup) -cne $candidate.SetupSHA256 -or
   (Hash $main) -cne $candidate.MainSHA256 -or
   $old.Revision -cne 'R299' -or
   $old.Status -cne 'PASS_NONRECURSIVE_ALLOWLISTED_STAGE_CLEANUP' -or
   $old.SourceCommit -cne $env:GITHUB_SHA -or
   $old.Host -cne $HostLabel){
 throw 'R300_SOURCE_OR_PREVIOUS_NATIVE_PROOF_UNTRUSTED'
}
$before=@{ Main=(Hash $main);Config=(Hash $config);State=(Hash $state) }
[void][IO.Directory]::CreateDirectory($outside)
[IO.File]::WriteAllText($canary,'R300_CROSS_DIRECTORY_CANARY',[Text.UTF8Encoding]::new($false))
$canarySHA=Hash $canary
$assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
$type=$assembly.GetType('SetupProgram',$true)
$flags=[Reflection.BindingFlags]'Static,NonPublic'
$method=$type.GetMethod('RecoverUpgradeStageIfAny',$flags)
$retiredProp=$type.GetProperty('RetiredUpgradeRoot',$flags)
if(!$method -or !$retiredProp){throw 'R300_PRODUCTION_RECOVERY_ENTRYPOINT_MISSING'}
$actualRetired=[string]$retiredProp.GetValue($null,$null)
if(-not [string]::Equals($retired,$actualRetired,[StringComparison]::OrdinalIgnoreCase)){
 throw 'R300_RETIRED_ROOT_NOT_EXACT_CANONICAL_SIBLING'
}
$checks.Add('EXACT_CANONICAL_RETIRED_ROOT')
$marker='TBME_UPGRADE_R92_OWNED_STAGE_V1'
function Write-Metadata([string]$directory,[string[]]$members){
 [void][IO.Directory]::CreateDirectory($directory)
 foreach($name in $members){
  $value=if($name -ceq 'owner.txt'){$marker}else{'R300_TEST_'+$name}
  [IO.File]::WriteAllText((Join-Path $directory $name),$value,[Text.Encoding]::ASCII)
 }
}
# Emulate the filesystem state *after* a completed same-parent Directory.Move,
# but before tombstone metadata deletion. Does not assert actual process death.
Write-Metadata $stage @('owner.txt','index.txt','phase.txt','previous_version.txt','phase.tmp')
[IO.Directory]::Move($stage,$retired)
if((Test-Path -LiteralPath $stage) -or !(Test-Path -LiteralPath $retired)){
 throw 'R300_SAME_PARENT_DIRECTORY_MOVE_DID_NOT_RETIRE_STAGE'
}
$checks.Add('NATIVE_SAME_PARENT_RENAME_RETIRES_ACTIVE_STAGE')
Invoke-Recover $method
if(Test-Path -LiteralPath $retired){throw 'R300_POST_RENAME_RECOVERY_NOT_CLEAN'}
$checks.Add('POST_RENAME_RESTART_CLEANUP_ACCEPTED')
# The deletion sequence can be interrupted after index/phase have gone.
Write-Metadata $retired @('owner.txt','phase.txt','index.txt')
[IO.File]::Delete((Join-Path $retired 'index.txt'))
[IO.File]::Delete((Join-Path $retired 'phase.txt'))
Invoke-Recover $method
if(Test-Path -LiteralPath $retired){throw 'R300_OWNER_ONLY_POST_DELETE_RECOVERY_FAILED'}
$checks.Add('PARTIALLY_DELETED_METADATA_RECOVERED')
[void][IO.Directory]::CreateDirectory($retired)
Invoke-Recover $method
if(Test-Path -LiteralPath $retired){throw 'R300_EMPTY_RETIRED_DIR_NOT_RECOVERED'}
$checks.Add('EMPTY_FINAL_DIRECTORY_RECOVERED')
# An unexpected file must stop cleanup with both file and owner intact.
Write-Metadata $retired @('owner.txt','index.txt')
$unknown=Join-Path $retired 'unknown-owner-file.txt'
[IO.File]::WriteAllText($unknown,'R300_UNKNOWN_PRESERVE',[Text.Encoding]::ASCII)
$ownerSHA=Hash (Join-Path $retired 'owner.txt')
Expect-Refused 'UNKNOWN_RETIRED_MEMBER_REFUSED' $method 'Unknown retired upgrade member'
if((Hash $unknown) -eq 'MISSING' -or (Hash (Join-Path $retired 'owner.txt')) -cne $ownerSHA){
 throw 'R300_UNKNOWN_RETIREMENT_DATA_MUTATED'
}
[IO.File]::Delete($unknown)
# Detect actual junctions, including a correctly named intermediate subtree.
$link=Join-Path $retired 'phase.tmp'
New-Item -ItemType Junction -Path $link -Target $outside -ErrorAction Stop|Out-Null
if(-not ((Get-Item -LiteralPath $link -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){
 throw 'R300_REAL_WINDOWS_REPARSE_NOT_CREATED'
}
Expect-Refused 'RETIRED_JUNCTION_REFUSED' $method 'reparse|ordinary file'
if((Hash $canary) -cne $canarySHA){throw 'R300_EXTERNAL_CANARY_CHANGED_BY_JUNCTION'}
[IO.Directory]::Delete($link)
$checks.Add('EXTERNAL_CANARY_PROTECTED')
# Invalid ownership and missing ownership with nonempty metadata fail closed.
[IO.File]::WriteAllText((Join-Path $retired 'owner.txt'),'WRONG_OWNER',[Text.Encoding]::ASCII)
Expect-Refused 'INVALID_OWNER_MARKER_REFUSED' $method 'ownership marker mismatch'
[IO.File]::Delete((Join-Path $retired 'owner.txt'))
Expect-Refused 'MISSING_OWNER_WITH_METADATA_REFUSED' $method 'lost its ownership marker'
[IO.File]::WriteAllText((Join-Path $retired 'owner.txt'),$marker,[Text.Encoding]::ASCII)
Invoke-Recover $method
if(Test-Path -LiteralPath $retired){throw 'R300_SAFE_METADATA_REPAIR_DID_NOT_FINISH'}
$checks.Add('KNOWN_RETIRED_STAGE_RECOVERED_AFTER_HOSTILE_TESTS')
if((Hash $main) -cne $before.Main -or
   (Hash $config) -cne $before.Config -or
   (Hash $state) -cne $before.State -or
   (Hash $canary) -cne $canarySHA -or
   (Test-Path -LiteralPath $stage)){
 throw 'R300_GUEST_OR_EXTERNAL_USER_CONTENT_CHANGED'
}
$checks.Add('EXACT_INSTALLED_FILES_AND_CANARY_UNCHANGED')
$data=[ordered]@{
 Schema=1;Revision='R300';Status='PASS_RETIRED_STAGE_RESTART_AND_HOSTILE_REFUSAL'
 Host=$HostLabel;SourceCommit=$env:GITHUB_SHA;OwnerComputerTouched=$false
 RealProcessKilled=$false;SimulatedPostMoveStop=$true
 SameParentDirectoryRename=$true;PostMoveCleanupRetried=$true
 InterruptedMetadataCleanupRetried=$true;UnknownFileRefused=$true
 ReparseRefused=$true;UnknownOwnerRefused=$true
 InstalledMainConfigStateUnchanged=$true;NoRetiredOrActiveStageResidue=$true
 Checks=@($checks);RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receipt,($data|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
'R300_NATIVE_'+$HostLabel+'_RETIRED_STAGE_RECOVERY_PASS'
