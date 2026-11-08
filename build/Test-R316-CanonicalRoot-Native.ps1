[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$CandidateDir
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
 throw 'R316_REQUIRES_DISPOSABLE_HOSTED_WINDOWS'
}
function Sha([string]$p){
 if(-not [IO.File]::Exists($p)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
}
$flags=[Reflection.BindingFlags]'Static,NonPublic'
$folder=Join-Path $env:RUNNER_TEMP ('R316_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $folder 'R316_TRUSTED_APPROOT_RECEIPT.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$prior=Join-Path $env:RUNNER_TEMP ('R315_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R315_TASK_COLD_RESTORE_RECEIPT.json')
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$config=Join-Path $app 'config.json'
$state=Join-Path $app 'install_state.json'
$checks=[Collections.Generic.List[string]]::new()
if([IO.Directory]::Exists($folder)){throw 'R316_EXISTING_FIXTURE_REFUSED'}
[void][IO.Directory]::CreateDirectory($folder)
$before=@{Main=(Sha $main);Config=(Sha $config);State=(Sha $state)}
$c=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
$p=Get-Content -LiteralPath $prior -Raw|ConvertFrom-Json
if($c.Commit -cne $env:GITHUB_SHA -or $c.SetupSHA256 -cne (Sha $setup) -or
   $c.MainSHA256 -cne $before.Main -or $p.SourceCommit -cne $env:GITHUB_SHA -or
   $p.Host -cne $HostLabel -or
   $p.Status -cne 'PASS_PREPARED_PRODUCTION_ENTRYPOINT_COLD_REPLAY_DISPOSABLE_TASK'){
 throw 'R316_EXACT_CANDIDATE_OR_PREVIOUS_ACCEPTANCE_MISMATCH'
}
$asm=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
$type=$asm.GetType('SetupProgram',$true)
$validator=$type.GetMethod('CanonicalAppRootFromKnownFolders',$flags)
$property=$type.GetProperty('AppRoot',$flags)
if(!$validator -or !$property){throw 'R316_TESTED_PE_HAS_NO_TRUSTED_ROOT_VALIDATOR'}
$resource=$asm.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced_Setup.cs')
if(!$resource){throw 'R316_PE_INSTALLER_SOURCE_NOT_EMBEDDED'}
$reader=[IO.StreamReader]::new($resource)
try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
$source=(Resolve-Path (Join-Path $PSScriptRoot '..\installer\TaskbarMonitorEnhanced_Setup.cs')).Path
$normalize={param([string]$text) $text.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $normalize $embedded) -cne (& $normalize ([IO.File]::ReadAllText($source)))){
 throw 'R316_COMPILED_SETUP_NOT_IDENTICAL_TO_REVIEWED_CSHARP'
}
$checks.Add('EXACT_PRIVATE_PE_CONTAINS_REVIEWED_CANONICAL_ROOT_CODE')
function Resolve([string]$local,[string]$profile){
 try{
  return [string]$validator.Invoke($null,([object[]]@($local,$profile)))
 }catch{
  $underlying=$_.Exception.GetBaseException()
  throw [InvalidOperationException]::new($underlying.Message,$underlying)
 }
}
function Refuse([string]$label,[string]$local,[string]$profile,[string]$pattern){
 $rejected=$false
 try{$null=Resolve $local $profile}catch{
  if($_.Exception.ToString() -match $pattern){$rejected=$true}else{throw}
 }
 if(-not $rejected){throw ('R316_EXPECTED_PATH_REJECTION_MISSING_'+$label)}
 $script:checks.Add($label)
}
$profile=[IO.Path]::GetFullPath([Environment]::GetFolderPath('UserProfile'))
$local=[IO.Path]::GetFullPath([Environment]::GetFolderPath('LocalApplicationData'))
$expected=[IO.Path]::GetFullPath((Join-Path $local 'TaskbarMonitorEnhanced'))
$actual=[string]$property.GetValue($null,$null)
if(-not [string]::Equals($actual,$expected,[StringComparison]::OrdinalIgnoreCase) -or
   -not [string]::Equals((Resolve $local $profile),$expected,[StringComparison]::OrdinalIgnoreCase)){
 throw 'R316_REAL_RUNNER_KNOWN_FOLDER_ROOT_CHANGED'
}
$checks.Add('HOSTED_RUNNER_OS_KNOWN_FOLDERS_MATCH_EXACT_APPROOT')
$fakeProfile=Join-Path $folder 'synthetic-profile'
$fakeLocal=Join-Path $fakeProfile 'AppData\Local'
[void][IO.Directory]::CreateDirectory($fakeLocal)
$syntheticExpected=[IO.Path]::GetFullPath((Join-Path $fakeLocal 'TaskbarMonitorEnhanced'))
if(-not [string]::Equals((Resolve $fakeLocal $fakeProfile),$syntheticExpected,[StringComparison]::OrdinalIgnoreCase)){
 throw 'R316_SYNTHETIC_NORMAL_PROFILE_NOT_ACCEPTED'
}
$checks.Add('SYNTHETIC_MATCHING_KNOWN_FOLDER_PROFILE_ACCEPTED')
Refuse 'RELATIVE_KNOWN_FOLDER_REFUSED' 'AppData\Local' $fakeProfile 'canonical|unavailable'
Refuse 'UNC_LOCAL_FOLDER_REFUSED' '\\server\share' $fakeProfile 'UNC|canonical'
Refuse 'ROOT_ONLY_PROFILE_REFUSED' $fakeLocal ([IO.Path]::GetPathRoot($fakeProfile)) 'root-only|LocalAppData'
Refuse 'REDIRECTED_KNOWN_FOLDER_REFUSED' $folder $fakeProfile 'canonical local folder'
Refuse 'PARENT_TRAVERSAL_OUT_OF_LOCAL_REFUSED' (Join-Path $fakeLocal '..\Other') $fakeProfile 'canonical local folder'
Refuse 'OTHER_USER_PROFILE_REFUSED' $fakeLocal (Join-Path $folder 'different-profile') 'canonical local folder'
$outside=Join-Path $folder 'unrelated'
[void][IO.Directory]::CreateDirectory($outside)
$canary=Join-Path $outside 'untouched.txt'
[IO.File]::WriteAllText($canary,'R316_EXTERNAL_CANARY',[Text.Encoding]::ASCII)
$canaryHash=Sha $canary
$target=Join-Path $fakeLocal 'TaskbarMonitorEnhanced'
New-Item -ItemType Junction -Path $target -Target $outside -ErrorAction Stop|Out-Null
try{
 Refuse 'APP_ROOT_JUNCTION_REFUSED' $fakeLocal $fakeProfile 'reparse point'
}finally{
 [IO.Directory]::Delete($target)
}
$alias=Join-Path $folder 'profile-junction'
New-Item -ItemType Junction -Path $alias -Target $fakeProfile -ErrorAction Stop|Out-Null
try{
 Refuse 'PROFILE_PARENT_JUNCTION_REFUSED' (Join-Path $alias 'AppData\Local') $alias 'reparse point'
}finally{[IO.Directory]::Delete($alias)}
$localAlias=Join-Path $fakeProfile 'AppData\linked-Local'
New-Item -ItemType Junction -Path $localAlias -Target $fakeLocal -ErrorAction Stop|Out-Null
try{
 Refuse 'REDIRECTED_LINKED_LOCAL_FOLDER_REFUSED' $localAlias $fakeProfile 'canonical local folder|reparse point'
}finally{[IO.Directory]::Delete($localAlias)}
if((Sha $main) -cne $before.Main -or (Sha $config) -cne $before.Config -or
   (Sha $state) -cne $before.State -or (Sha $canary) -cne $canaryHash){
 throw 'R316_GUEST_APP_DATA_OR_UNRELATED_CANARY_CHANGED'
}
$checks.Add('GUEST_INSTALLED_APP_AND_CANARY_BYTE_EXACT')
$receiptData=[ordered]@{
 Schema=1;Revision='R316';Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
 Status='PASS_OS_KNOWNFOLDER_CANONICAL_APPROOT_AND_REPARSE_REFUSAL'
 ExactCompiledInstallerSource=$true;CanonicalExistingAppRootAccepted=$true
 SyntheticSafeProfileAccepted=$true;RelativeUNCTraversalAndForeignProfileRejected=$true
 ExistingJunctionAndAliasRejected=$true;UserFilesAndExternalCanaryUnchanged=$true
 OriginalOwnerMachineTouched=$false;ActualProtectedTaskTouched=$false
 RealProgramFilesWritten=$false;ActualUACInvoked=$false
 CodeQLHighAlertsAccepted=$false
 Checks=@($checks);RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receipt,($receiptData|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
'R316_'+$HostLabel+'_TRUSTED_KNOWNFOLDER_ROOT_BOUNDS_PASS'
