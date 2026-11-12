[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$CandidateDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Never run on the owner's live Windows host.
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'R301_ONLY_DISPOSABLE_GITHUB_WINDOWS'
}
function Hash([string]$path){
 if(!(Test-Path -LiteralPath $path -PathType Leaf)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
function Expect-Fail([string]$gate,[Reflection.MethodInfo]$method,[string]$pattern){
 $refused=$false
 try{[void]$method.Invoke($null,[object[]]::new(0))}
 catch{if($_.Exception.ToString() -match $pattern){$refused=$true}else{throw}}
 if(!$refused){throw ('R301_FAIL_OPEN_'+$gate)}
 $script:checks.Add($gate)
}
function Start-ProofChild([string]$code){
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
 $system=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
 if(-not [IO.File]::Exists($system)){throw 'R301_NATIVE_WINDOWS_POWERSHELL_MISSING'}
 $psi=[Diagnostics.ProcessStartInfo]::new()
 $psi.FileName=$system
 $psi.Arguments='-NoProfile -NonInteractive -EncodedCommand '+$encoded
 $psi.UseShellExecute=$false
 $psi.CreateNoWindow=$true
 $psi.RedirectStandardOutput=$true
 $psi.RedirectStandardError=$true
 return [Diagnostics.Process]::Start($psi)
}
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$stage=Join-Path $app '.tbme-upgrade'
$retired=Join-Path $app '.tbme-upgrade-retired'
$testRoot=Join-Path $env:RUNNER_TEMP ('R301_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $testRoot 'R301_ROLLBACK_RETRY_RECEIPT.json'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R300_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R300_RETIRED_JOURNAL_RECEIPT.json')
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$config=Join-Path $app 'config.json'
$state=Join-Path $app 'install_state.json'
$checks=[Collections.Generic.List[string]]::new()
if((Test-Path -LiteralPath $testRoot) -or (Test-Path -LiteralPath $stage) -or
   (Test-Path -LiteralPath $retired) -or
   @((Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue)).Count -ne 0){
 throw 'R301_EXISTING_OR_RUNNING_OWNER_STATE'
}
$m=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
$p=Get-Content -LiteralPath $prior -Raw|ConvertFrom-Json
if($m.Commit -cne $env:GITHUB_SHA -or $m.SetupSHA256 -cne (Hash $setup) -or
   $m.MainSHA256 -cne (Hash $main) -or $p.SourceCommit -cne $env:GITHUB_SHA -or
   $p.Host -cne $HostLabel -or
   $p.Status -cne 'PASS_RETIRED_STAGE_RESTART_AND_HOSTILE_REFUSAL'){
 throw 'R301_UNTRUSTED_EXACT_SOURCE_OR_PRIOR_PROOF'
}
[void][IO.Directory]::CreateDirectory($testRoot)
$before=@{Main=(Hash $main);Config=(Hash $config);State=(Hash $state)}
$marker='TBME_UPGRADE_R92_OWNED_STAGE_V1'
$assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
$type=$assembly.GetType('SetupProgram',$true)
$static=[Reflection.BindingFlags]'Static,NonPublic'
$instance=[Reflection.BindingFlags]'Instance,NonPublic,Public'
$targetField=$type.GetField('UpgradeTargets',$static)
$recover=$type.GetMethod('RecoverUpgradeStageIfAny',$static)
$verify=$type.GetMethod('VerifyRolledBackUpgrade',$static)
$phaseWriter=$type.GetMethod('WritePhase',$static)
if(!$targetField -or !$recover -or !$verify -or !$phaseWriter){
 throw 'R301_EXPECTED_PRODUCTION_ENTRYPOINTS_MISSING'
}
$targets=[array]$targetField.GetValue($null)
if($targets.Count -lt 25 -or $targets.Count -gt 40){throw 'R301_UNEXPECTED_MANAGED_INVENTORY'}
$rows=[Collections.Generic.List[string]]::new()
foreach($item in $targets){
 $field=$item.GetType().GetField('Rel',$instance)
 if(!$field){throw 'R301_TYPED_ROW_REL_MISSING'}
 $rel=[string]$field.GetValue($item)
 $full=Join-Path $app ($rel.Replace('/',[IO.Path]::DirectorySeparatorChar))
 $previous=Hash $full
 if($previous -ceq 'MISSING'){$previous='-'}
 elseif($previous -cnotmatch '^[0-9A-F]{64}$'){throw 'R301_BAD_HASH_GENERATED'}
 # Existing source hashes are real, new-only files are represented by '-'.
 $rows.Add($rel+'|'+$previous+'|-')
}
if(-not $rows[0].StartsWith('TaskbarMonitorEnhanced.exe|',[StringComparison]::Ordinal)){
 throw 'R301_PINNED_MAIN_ROW_NOT_FIRST'
}
$checks.Add('COMPILED_ROW_INVENTORY_EXACT_LIVE_HASHES')
$indexText=$rows.ToArray() -join ([string][char]10)
$registration='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TaskbarMonitorEnhanced'
$display=[string](Get-ItemProperty -LiteralPath $registration -ErrorAction Stop).DisplayVersion
$oldVersion='1.7.8'
if($display -cne $oldVersion){throw 'R301_GUEST_INSTALLED_VERSION_UNEXPECTED'}
function Prepare-Journal([string]$version){
 if(Test-Path -LiteralPath $stage){throw 'R301_STAGE_COLLISION'}
 [void][IO.Directory]::CreateDirectory($stage)
 [IO.File]::WriteAllText((Join-Path $stage 'owner.txt'),$marker,[Text.Encoding]::ASCII)
 [IO.File]::WriteAllText((Join-Path $stage 'previous_version.txt'),$version,[Text.Encoding]::ASCII)
 [IO.File]::WriteAllText((Join-Path $stage 'index.txt'),$indexText,[Text.Encoding]::ASCII)
 [IO.File]::WriteAllText((Join-Path $stage 'phase.txt'),($marker+'|COMMITTING'),[Text.Encoding]::ASCII)
}
function Restore-SafeStage(){
 if(Test-Path -LiteralPath $stage){
  foreach($name in @('phase.tmp','phase.txt','index.txt','previous_version.txt','owner.txt')){
   $path=Join-Path $stage $name
   if(Test-Path -LiteralPath $path -PathType Leaf){[IO.File]::Delete($path)}
  }
  [IO.Directory]::Delete($stage,$false)
 }
}
Prepare-Journal $oldVersion
# Mimic a completed rollback where previously copied 'old' backup snapshots
# have already been unlinked. A COMMITTING replay must not consume them again.
if((Test-Path -LiteralPath (Join-Path $stage 'old')) -or
   (Test-Path -LiteralPath (Join-Path $stage 'new'))){
 throw 'R301_SHOULD_NOT_HAVE_STAGED_OLD_SNAPSHOTS'
}
$checks.Add('COMPLETE_OLD_LIVE_STATE_WITH_ABSENT_BACKUP_SNAPSHOTS')
# The separate real PowerShell worker executes the production WritePhase
# and is then forcibly terminated by this parent after a checkpoint. This
# is NOT a kill of the production Setup process inside filesystem cleanup.
$checkpoint=Join-Path $testRoot 'worker-durable-phase-ready.txt'
$setupQuoted=$setup.Replace("'","''")
$checkQuoted=$checkpoint.Replace("'","''")
$writerCode=@"
`$ErrorActionPreference='Stop'
`$assembly=[Reflection.Assembly]::LoadFile('$setupQuoted')
`$type=`$assembly.GetType('SetupProgram',`$true)
`$method=`$type.GetMethod('WritePhase',[Reflection.BindingFlags]'Static,NonPublic')
if(!`$method){throw 'R301_CHILD_PRODUCTION_PHASE_METHOD_MISSING'}
[void]`$method.Invoke(`$null,[object[]]@('ROLLED_BACK'))
[IO.File]::WriteAllText('$checkQuoted','DURABLE_ROLLBACK_PHASE_READY')
Start-Sleep -Seconds 30
"@
$worker=Start-ProofChild $writerCode
if(!$worker){throw 'R301_WORKER_PROCESS_DID_NOT_START'}
$watch=[Diagnostics.Stopwatch]::StartNew()
try{
 while(!(Test-Path -LiteralPath $checkpoint) -and !$worker.HasExited -and $watch.ElapsedMilliseconds -lt 14000){
  Start-Sleep -Milliseconds 100
 }
 if(!(Test-Path -LiteralPath $checkpoint) -or $worker.HasExited){
  throw 'R301_CHILD_DURABLE_PHASE_CHECKPOINT_NOT_REACHED'
 }
 $phaseContent=[IO.File]::ReadAllText((Join-Path $stage 'phase.txt'),[Text.Encoding]::ASCII)
 if($phaseContent -cne ($marker+'|ROLLED_BACK')){
  throw 'R301_PHASE_NOT_DURABLY_REPLACED'
 }
 $worker.Kill()
 if(!$worker.WaitForExit(10000) -or !$worker.HasExited -or $worker.ExitCode -eq 0){
  throw 'R301_WORKER_TERMINATION_NOT_OBSERVED'
 }
 $checks.Add('REAL_DISPOSABLE_WORKER_KILLED_AFTER_PRODUCTION_ROLLBACK_MARKER')
}finally{
 if(!$worker.HasExited){$worker.Kill();[void]$worker.WaitForExit(10000)}
 $worker.Dispose()
}
# New process loads the SAME compiled installer and runs its normal recovery.
$retryCode=@"
`$ErrorActionPreference='Stop'
`$assembly=[Reflection.Assembly]::LoadFile('$setupQuoted')
`$type=`$assembly.GetType('SetupProgram',`$true)
`$method=`$type.GetMethod('RecoverUpgradeStageIfAny',[Reflection.BindingFlags]'Static,NonPublic')
if(!`$method){throw 'R301_RESTART_RECOVERY_METHOD_MISSING'}
[void]`$method.Invoke(`$null,[object[]]::new(0))
"@
$retry=Start-ProofChild $retryCode
if(!$retry){throw 'R301_RESTART_WORKER_NOT_STARTED'}
try{
 if(!$retry.WaitForExit(18000) -or !$retry.HasExited -or $retry.ExitCode -ne 0){
   $errorText=if($retry.HasExited){$retry.StandardError.ReadToEnd()}else{'CHILD_TIMEOUT'}
   if($errorText.Length -gt 2500){$errorText=$errorText.Substring(0,2500)}
   throw ('R301_RECOVERY_WORKER_FAILED exit='+$(if($retry.HasExited){$retry.ExitCode}else{'RUNNING'})+' stderr='+$errorText)
 }
}finally{
 if(!$retry.HasExited){$retry.Kill();[void]$retry.WaitForExit(10000)}
 $retry.Dispose()
}
if((Test-Path -LiteralPath $stage) -or (Test-Path -LiteralPath $retired)){
 throw 'R301_POST_RESTART_JOURNAL_RESIDUE'
}
$checks.Add('FRESH_PROCESS_RESTART_RECOVERS_WITHOUT_OLD_SNAPSHOTS')
# Negative test: wrong installed digest must fail closed, preserving the stage.
Prepare-Journal $oldVersion
$first=$rows[0].Split('|')
if($first.Length -ne 3 -or $first[1] -ceq '-'){throw 'R301_EXPECTED_REAL_MAIN_PREVIOUS_HASH_MISSING'}
$changed=$first[0]+'|'+('0'*64)+'|'+$first[2]
$lines=[string[]]$rows.ToArray()
$lines[0]=$changed
[IO.File]::WriteAllText((Join-Path $stage 'index.txt'),($lines -join ([string][char]10)),[Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $stage 'phase.txt'),($marker+'|ROLLED_BACK'),[Text.Encoding]::ASCII)
Expect-Fail 'FORGED_PREVIOUS_DIGEST_REJECTED' $recover 'Rolled-back previous SHA mismatch'
if(-not (Test-Path -LiteralPath $stage) -or
   (Hash $main) -cne $before.Main){throw 'R301_FAILED_VERIFICATION_CHANGED_APP'}
Restore-SafeStage
# A supported but wrong prior version and HKCU version mismatch must fail closed.
Prepare-Journal '1.7.7'
[IO.File]::WriteAllText((Join-Path $stage 'phase.txt'),($marker+'|ROLLED_BACK'),[Text.Encoding]::ASCII)
Expect-Fail 'VERSION_REGISTRY_MISMATCH_REFUSED' $recover 'Rolled-back uninstall registration mismatch'
Restore-SafeStage
# Unrecognized version should be rejected before any delete.
Prepare-Journal '99.99'
[IO.File]::WriteAllText((Join-Path $stage 'phase.txt'),($marker+'|ROLLED_BACK'),[Text.Encoding]::ASCII)
Expect-Fail 'UNKNOWN_OLD_VERSION_REFUSED' $recover 'not pinned'
Restore-SafeStage
if((Hash $main) -cne $before.Main -or (Hash $config) -cne $before.Config -or
   (Hash $state) -cne $before.State -or
   [string](Get-ItemProperty -LiteralPath $registration).DisplayVersion -cne $oldVersion -or
   (Test-Path -LiteralPath $stage) -or (Test-Path -LiteralPath $retired)){
 throw 'R301_INSTALLED_ASSETS_OR_REGISTRY_CHANGED'
}
$checks.Add('GUEST_MAIN_CONFIG_STATE_AND_REGISTRATION_IMMUTABLE')
$data=[ordered]@{
 Schema=1;Revision='R301';Status='PASS_ROLLED_BACK_JOURNAL_RETRY_REAL_WORKER_TERMINATION'
 Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
 OwnerComputerTouched=$false;OriginalMainAndSettingsUnchanged=$true
 ActualOriginalSetupProcessKilled=$false
 ActualDisposableProofWorkerKilled=$true
 ProductionWritePhaseExecutedInChild=$true
 FreshRecoveryProcessSucceeded=$true
 MissingOldSnapshotsAcceptedAfterVerifiedRollback=$true
 TamperedPriorFileDigestRejected=$true
 RegistryVersionMismatchRejected=$true
 UnsupportedVersionRejected=$true
 NoJournalResidue=$true;Checks=@($checks)
 RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receipt,($data|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
'R301_NATIVE_'+$HostLabel+'_RECOVERY_AFTER_REAL_WORKER_KILL_PASS'
