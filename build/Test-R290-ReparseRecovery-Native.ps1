[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$CandidateDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# Only ephemeral GitHub Windows runners, never the owner's installation.
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'R290_ONLY_GITHUB_DISPOSABLE_WINDOWS'
}
$dir=Join-Path $env:RUNNER_TEMP ('R290_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$app=Join-Path $env:LOCALAPPDATA 'TaskbarMonitorEnhanced'
$stage=Join-Path $app '.tbme-upgrade'
$alias=Join-Path $app 'R290-Junction-Only-Temporary'
$oldLink=Join-Path $stage 'old'
$outside=Join-Path $dir 'external-canary'
$canary=Join-Path $outside 'do-not-change.txt'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$prior=Join-Path $env:RUNNER_TEMP ('R286_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R286_RECOVERY_RECEIPT.json')
$gates=[Collections.Generic.List[string]]::new()
$accepted=$false
$phase='INITIAL'
function Hash([string]$path){
 if(!(Test-Path -LiteralPath $path -PathType Leaf)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
function Expect-ReparseRefusal([string]$gate,[Reflection.MethodInfo]$method,[object[]]$arguments){
 $refused=$false
 try{[void]$method.Invoke($null,$arguments)}
 catch{
  $message=$_.Exception.ToString()
  if($message -match '(?i)symlink/junction|reparse'){$refused=$true}
  else{throw ('R290_UNEXPECTED_EXCEPTION_'+$gate+': '+$message)}
 }
 if(!$refused){throw ('R290_FAIL_OPEN_'+$gate)}
 $script:gates.Add($gate)
}
if(!(Test-Path $app) -or (Test-Path $dir) -or
   (Test-Path $alias) -or (Test-Path $stage) -or
   @(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count -ne 0){
 throw 'R290_PREVIOUS_TEST_DID_NOT_LEAVE_CLEAN_GUEST'
}
$previous=Get-Content $prior -Raw|ConvertFrom-Json
$candidate=Get-Content $manifest -Raw|ConvertFrom-Json
if($previous.Status -cne 'PASS_EXACT_V178_SETUP_RETRY_AFTER_STRANDED_RESTORE' -or
   $previous.SourceCommit -cne $env:GITHUB_SHA -or
   $candidate.Commit -cne $env:GITHUB_SHA -or
   (Hash $setup) -cne $candidate.SetupSHA256 -or
   (Hash (Join-Path $app 'TaskbarMonitorEnhanced.exe')) -cne $candidate.MainSHA256){
 throw 'R290_UNPINNED_CANDIDATE_OR_PRIOR_ACCEPTANCE'
}
$mainBefore=Hash (Join-Path $app 'TaskbarMonitorEnhanced.exe')
$configBefore=Hash (Join-Path $app 'config.json')
$stateBefore=Hash (Join-Path $app 'install_state.json')
[IO.Directory]::CreateDirectory($outside)|Out-Null
[IO.File]::WriteAllText($canary,'R290_EXTERNAL_CANARY_MUST_NOT_CHANGE',[Text.UTF8Encoding]::new($false))
$canaryBefore=Hash $canary
try{
 $phase='REFLECTION_PREPARE'
 $assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
 $type=$assembly.GetType('SetupProgram',$true)
 $flags=[Reflection.BindingFlags]'NonPublic,Static'
 $liveMethod=$type.GetMethod('UPath',$flags)
 $stageMethod=$type.GetMethod('Stage',$flags)
 $recoverMethod=$type.GetMethod('RecoverUpgradeStageIfAny',$flags)
 if(!$liveMethod -or !$stageMethod -or !$recoverMethod){throw 'R290_EXPECTED_CANDIDATE_METHODS_MISSING'}
 $normal=[string]$liveMethod.Invoke($null,[object[]]@('TaskbarMonitorEnhanced.exe'))
 if($normal -cne (Join-Path $app 'TaskbarMonitorEnhanced.exe')){throw 'R290_NORMAL_MANAGED_PATH_CHANGED'}
 [void]$stageMethod.Invoke($null,[object[]]@('old','TaskbarMonitorEnhanced.exe'))
 $gates.Add('NORMAL_FIXED_APP_AND_STAGE_PATHS_ACCEPTED')
 $phase='VALIDATE_TRAVERSAL_REJECTION'
 $invalidRejected=$false
 try{[void]$stageMethod.Invoke($null,[object[]]@('old','..\..\outside.txt'))}
 catch{if($_.Exception.ToString() -match 'unsafe staged resource path|stage escape'){$invalidRejected=$true}else{throw}}
 if(!$invalidRejected){throw 'R290_TRAVERSAL_NOT_REJECTED'}
 $gates.Add('RELATIVE_TRAVERSAL_REJECTED')
 $phase='LIVE_CHILD_JUNCTION'
 New-Item -ItemType Junction -Path $alias -Target $outside -ErrorAction Stop|Out-Null
 if(-not ((Get-Item -LiteralPath $alias -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){
  throw 'R290_REAL_WINDOWS_JUNCTION_NOT_CREATED'
 }
 Expect-ReparseRefusal 'LIVE_CHILD_JUNCTION_REFUSED' $liveMethod ([object[]]@('R290-Junction-Only-Temporary/do-not-change.txt'))
 [IO.Directory]::Delete($alias)
 if(Test-Path $alias){throw 'R290_CANNOT_REMOVE_ONLY_LINK'}
 $phase='INTERRUPTED_STAGE_CHILD_JUNCTION'
 [IO.Directory]::CreateDirectory($stage)|Out-Null
 New-Item -ItemType Junction -Path $oldLink -Target $outside -ErrorAction Stop|Out-Null
 if(-not ((Get-Item -LiteralPath $oldLink -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){
  throw 'R290_REAL_STAGE_JUNCTION_NOT_CREATED'
 }
 Expect-ReparseRefusal 'STAGED_OLD_JUNCTION_REFUSED' $stageMethod ([object[]]@('old','TaskbarMonitorEnhanced.exe'))
 # Reparse refusal must occur before reading any bogus stage metadata.
 Expect-ReparseRefusal 'RECOVERY_REJECTS_BEFORE_ANY_FILE_MUTATION' $recoverMethod ([object[]]@())
 [IO.Directory]::Delete($oldLink)
 if(Test-Path $oldLink){throw 'R290_STAGE_LINK_CLEANUP_FAILED'}
 [IO.Directory]::Delete($stage)
 if(Test-Path $stage){throw 'R290_STAGE_CLEANUP_FAILED'}
 $phase='CANARY_AND_PROTECTED_ASSET_READBACK'
 if((Hash $canary) -cne $canaryBefore -or
    (Hash (Join-Path $app 'TaskbarMonitorEnhanced.exe')) -cne $mainBefore -or
    (Hash (Join-Path $app 'config.json')) -cne $configBefore -or
    (Hash (Join-Path $app 'install_state.json')) -cne $stateBefore){
  throw 'R290_EXTERNAL_OR_PROTECTED_USER_BYTES_ALTERED'
 }
 $gates.Add('EXTERNAL_AND_INSTALLED_DATA_UNCHANGED')
 $gates.Add('NO_ROOT_STAGE_OR_JUNCTION_RESIDUE')
 $receipt=[ordered]@{
  Schema=1;Revision='R290';Status='PASS_NATIVE_UPGRADE_CHILD_REPARSE_FAIL_CLOSED'
  Host=$HostLabel;SourceCommit=$env:GITHUB_SHA;OriginalOwnerComputerTouched=$false
  NativeWindowsJunctionCreated=$true; NormalPathAcceptance=$true
  ParentTraversalRejected=$true; LiveChildJunctionRejected=$true
  StageOldJunctionRejected=$true; RecoverPreMutationRejected=$true
  NoExternalCanaryMutation=$true; InstalledMainAndConfigUnchanged=$true
  NoStageOrLinkResidue=$true; Tests=@($gates)
  RecordedUtc=[DateTime]::UtcNow.ToString('o')
 }
 [IO.File]::WriteAllText((Join-Path $dir 'R290_REPARSE_RECEIPT.json'),
  ($receipt|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
 $accepted=$true
 'R290_DISPOSABLE_GUEST_'+$HostLabel+'_CHILD_REPARSE_GUARDS_PASS'
}finally{
 if(Test-Path $alias){try{[IO.Directory]::Delete($alias)}catch{}}
 if(Test-Path $oldLink){try{[IO.Directory]::Delete($oldLink)}catch{}}
 if(Test-Path $stage){try{[IO.Directory]::Delete($stage)}catch{}}
 if(!$accepted){
  $fail=[ordered]@{Schema=1;Revision='R290';Status='FAIL';Phase=$phase
   SourceCommit=$env:GITHUB_SHA;OriginalOwnerComputerTouched=$false
   RecordedUtc=[DateTime]::UtcNow.ToString('o')}
  [IO.File]::WriteAllText((Join-Path $dir 'R290_REPARSE_RECEIPT.json'),
   ($fail|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
 }
}
