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
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'R297_ONLY_DISPOSABLE_GITHUB_WINDOWS'
}
function Hash([string]$Path){
 if(!(Test-Path -LiteralPath $Path -PathType Leaf)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
function RunGuard([string]$Guard,[string]$Version,[string]$Fake){
 $base64Fake=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Fake))
 $script=@(
  '$ErrorActionPreference="Stop"',
  'function Get-PawnIOVersion { return "'+$Version+'" }',
  'function Write-Log {param([string]$Text)}',
  'function Write-Result { Write-Output ("R297_RESULT_"+[string]$args[0]) }',
  '$ActiveArchitecture=""',
  '$PawnPayload=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("'+$base64Fake+'"))',
  $Guard,
  'Write-Output "R297_SAFE_COMPATIBLE_REACHED"'
 ) -join [string][char]10
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
 $psi=[Diagnostics.ProcessStartInfo]::new()
 $psi.FileName='powershell.exe'
 $psi.Arguments='-NoProfile -NonInteractive -EncodedCommand '+$encoded
 $psi.UseShellExecute=$false
 $psi.CreateNoWindow=$true
 $psi.RedirectStandardOutput=$true
 $psi.RedirectStandardError=$true
 $proc=[Diagnostics.Process]::Start($psi)
 if(!$proc){throw 'R297_NEGATIVE_GUARD_PROCESS_NOT_STARTED'}
 try{
  $outTask=$proc.StandardOutput.ReadToEndAsync()
  $errTask=$proc.StandardError.ReadToEndAsync()
  if(!$proc.WaitForExit(15000)){
   try{$proc.Kill()}catch{}
   throw 'R297_NATIVE_GUARD_PROCESS_TIMEOUT'
  }
  return [pscustomobject]@{
   Exit=$proc.ExitCode
   Out=$outTask.GetAwaiter().GetResult()
   Err=$errTask.GetAwaiter().GetResult()
  }
 }finally{$proc.Dispose()}
}
$root=Join-Path $env:RUNNER_TEMP ('R297_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $root 'R297_PAWN_REFUSAL_RECEIPT.json'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$live=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R296_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R296_MEMORY_ROLLBACK_RECEIPT.json')
$checks=[Collections.Generic.List[string]]::new()
$accepted=$false
if(Test-Path $root){throw 'R297_PREEXISTING_GUEST_FIXTURE_REFUSED'}
[void][IO.Directory]::CreateDirectory($root)
$mainBefore=Hash $live
try{
 $id=Get-Content $manifest -Raw|ConvertFrom-Json
 $old=Get-Content $prior -Raw|ConvertFrom-Json
 if($id.Commit -cne $env:GITHUB_SHA -or (Hash $setup) -cne $id.SetupSHA256 -or
   (Hash $live) -cne $id.MainSHA256 -or
   $old.SourceCommit -cne $env:GITHUB_SHA -or $old.Host -cne $HostLabel -or
   $old.Status -cne 'PASS_MEMORY_ONLY_ROLLBACK_NO_USER_TEMP_TRUST'){
  throw 'R297_EXACT_CANDIDATE_OR_PRIOR_RECEIPT_NOT_PINNED'
 }
 $assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
 $stream=$assembly.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
 if(!$stream){throw 'R297_EMBEDDED_HELPER_MISSING'}
 $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
 try{$helper=$reader.ReadToEnd()}finally{$reader.Dispose()}
 $sourcePath=(Resolve-Path (Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1')).Path
 $source=Get-Content -LiteralPath $sourcePath -Raw
 $crlf=[string][char]13+[char]10
 $lf=[string][char]10
 if($helper.Replace($crlf,$lf).TrimEnd() -cne $source.Replace($crlf,$lf).TrimEnd()){
  throw 'R297_PACKAGED_HELPER_DIFFERS_FROM_SOURCE'
 }
 $checks.Add('EMBEDDED_HELPER_SOURCE_EXACT')
 if($helper.Contains('Start-Process -FilePath $PawnPayload') -or
    $helper.Contains('if(-not $pawnAlreadyCompatible -and !(Test-Path') -or
    $helper.Contains('$PawnPayload=Join-Path $PayloadDir')){
  throw 'R297_UNTRUSTED_PAWN_AUTORUN_STILL_PRESENT'
 }
 $checks.Add('NO_AUTO_ELEVATED_PAWNIO_TEMP_LAUNCH')
 $setupCode=Get-Content (Join-Path $PSScriptRoot '..\installer\TaskbarMonitorEnhanced_Setup.cs') -Raw
 if($setupCode.Contains('Extract("Payload.PawnIO_setup.exe"')){
  throw 'R297_SETUP_STILL_EXTRACTS_WRITABLE_PAWN_BINARY'
 }
 $checks.Add('SETUP_NEVER_STAGES_PAWN_INSTALLER_IN_TEMP')
 $guardStart=$helper.IndexOf('$existingPawn=Get-PawnIOVersion',[StringComparison]::Ordinal)
 $guardEnd=$helper.IndexOf('# R294: Verify pinned embedded identity',[StringComparison]::Ordinal)
 if($guardStart -lt 0 -or $guardEnd -le $guardStart -or
    $helper.IndexOf('$existingPawn=Get-PawnIOVersion',$guardStart+1) -ge 0){
  throw 'R297_PAWN_PREFLIGHT_BLOCK_NOT_UNIQUE'
 }
 $guard=$helper.Substring($guardStart,$guardEnd-$guardStart)
 if(-not $guard.Contains('if(-not $pawnAlreadyCompatible){') -or
    -not $guard.Contains("'EXTERNAL_INSTALL_REQUIRED'")){
  throw 'R297_PAWN_PREFLIGHT_NOT_STRICT'
 }
 $checks.Add('PRODUCTION_GUARD_IN_SOURCE_PRE_MUTATION')
 $fake=Join-Path $root 'PawnIO_setup.exe'
 [IO.File]::WriteAllBytes($fake,[byte[]](77,90,1,2,3,4,5,6))
 $originalFakeHash=Hash $fake
 $absent=RunGuard $guard '' $fake
 if($absent.Exit -ne 0 -or
    $absent.Out -notmatch 'R297_RESULT_DEGRADED' -or
    $absent.Out -match 'R297_SAFE_COMPATIBLE_REACHED' -or
    $absent.Err -match 'Start-Process|cannot be started'){
  throw ('R297_FORGED_PAWN_FILE_WAS_NOT_IGNORED exit='+$absent.Exit+' stdout='+$absent.Out+' stderr='+$absent.Err)
 }
 $checks.Add('FORGED_TEMP_EXE_DOES_NOT_BYPASS_MISSING_DRIVER_REFUSAL')
 $checks.Add('MISSING_DRIVER_RETURNS_EXTERNAL_CONSENT_REQUIRED')
 $compatible=RunGuard $guard '2.2.0' $fake
 if($compatible.Exit -ne 0 -or
    $compatible.Out -notmatch 'R297_SAFE_COMPATIBLE_REACHED' -or
    $compatible.Out -match 'R297_RESULT_DEGRADED'){
  throw ('R297_COMPATIBLE_EXISTING_DRIVER_REJECTED '+$compatible.Err)
 }
 $checks.Add('EXISTING_COMPATIBLE_DRIVER_REUSED')
 if((Hash $fake) -cne $originalFakeHash){throw 'R297_FAKE_TEMP_INSTALLER_CHANGED_OR_RUN'}
 $checks.Add('FORGED_TEMP_BINARY_UNMODIFIED')
 if((Hash $live) -cne $mainBefore){throw 'R297_GUEST_MAIN_CHANGED'}
 $checks.Add('GUEST_MAIN_UNCHANGED')
 $checks.Add('NO_UAC_DRIVER_INSTALL_TASK_OR_PROTECTED_SERVICE_MUTATION')
 $record=[ordered]@{
  Schema=1;Revision='R297';Status='PASS_NO_UNTRUSTED_PAWNIO_AUTORUN'
  Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
  OriginalOwnerComputerTouched=$false;UACOrDriverServiceMutation=$false
  FakeTempPawnInstallerIgnored=$true;MissingDriverRequiresOfficialExternalConsent=$true
  ExistingCompatiblePawnIORetained=$true;MainUnchanged=$true
  Checks=@($checks);RecordedUtc=[DateTime]::UtcNow.ToString('o')
 }
 [IO.File]::WriteAllText($receipt,($record|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
 $accepted=$true
 'R297_GUEST_'+$HostLabel+'_NO_PAWNIO_TEMP_ELEVATION_PASS'
}finally{
 if(!$accepted){
  $fail=[ordered]@{Schema=1;Revision='R297';Status='FAIL_NOT_ACCEPTED';Host=$HostLabel
   SourceCommit=$env:GITHUB_SHA;OriginalOwnerComputerTouched=$false}
  [IO.File]::WriteAllText($receipt,($fail|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
 }
}
