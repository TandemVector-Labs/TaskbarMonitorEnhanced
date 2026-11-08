[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$CandidateDir,
 [Parameter(Mandatory=$true)][ValidateSet("A","B")][string]$HostLabel
)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

# Test-only, exact source, genuine compiled .NET 4.x Windows setup.
# No run on owner's PC, no driver install direct from this harness.
if($env:GITHUB_ACTIONS -cne "true" -or
   $env:RUNNER_ENVIRONMENT -cne "github-hosted" -or
   $env:RUNNER_OS -cne "Windows" -or
   $env:GITHUB_REPOSITORY -cne "GOD13emad/TaskbarMonitorEnhanced" -or
   ($env:GITHUB_REF -cne "refs/heads/release/r265-v175-sensor-crossuser-safety" -and
    $env:GITHUB_REF -cne "refs/heads/main") -or
   $env:COMPUTERNAME -match "(?i)EMAD|ALI|LAPTOP" -or
   -not [Environment]::UserInteractive) {
 throw "R265_REFUSE_NON_DISPOSABLE_GITHUB_HOST"
}
$repo="GOD13emad/TaskbarMonitorEnhanced"
$app=Join-Path $env:LOCALAPPDATA "TaskbarMonitorEnhanced"
$reg="HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TaskbarMonitorEnhanced"
$build=Get-Content -LiteralPath (Join-Path $CandidateDir "CANDIDATE.json") -Raw|ConvertFrom-Json -ErrorAction Stop
$setup=[IO.Path]::GetFullPath((Join-Path $CandidateDir "Setup/TaskbarMonitorEnhanced_Setup_1.7.5.exe"))
$out=Join-Path $env:RUNNER_TEMP ("TBME_R265_"+$HostLabel)
$receipt=Join-Path $out "R265_FRESH.json"
$folder=if($HostLabel -ceq "A"){[Environment]::GetFolderPath("ProgramFiles")}else{[Environment]::GetFolderPath("ProgramFilesX86")}
$legacy=Join-Path $folder "TaskbarMonitorEnhanced"
$marker=Join-Path $legacy "TaskbarMonitorEnhanced.exe"
$owned=$false;$expectedMarker=""
$status="FAIL";$phase="PREFLIGHT";$error=""
$installedExit=$null;$sameVersionExit=$null;$negativeExit=$null;$afterCollisionExit=$null
$original=@{};$originalRun="";$removed=false
function StopNow([string]$msg){throw ("R265_"+$msg)}
function Hash([string]$path){
 if(!(Test-Path -LiteralPath $path -PathType Leaf)){return "MISSING"}
 return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
function RunCandidate([string]$arguments){
 $psi=[Diagnostics.ProcessStartInfo]::new()
 $psi.FileName=$setup;$psi.Arguments=$arguments
 $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
 $psi.WorkingDirectory=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($setup))
 $p=[Diagnostics.Process]::Start($psi)
 if($null -eq $p){StopNow "CANDIDATE_SETUP_NOT_STARTED"}
 try{
  if(!$p.WaitForExit(180000)){StopNow ("CANDIDATE_TIMEOUT_"+$p.Id)}
  return [int]$p.ExitCode
 } finally {$p.Dispose()}
}
function StartupValue{
 $key=Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
 if($null -eq $key){return "ABSENT"}
 $v=$key.PSObject.Properties["TaskbarMonitorEnhanced"]
 if($null -eq $v){return "ABSENT"}
 return [string]$v.Value
}
function Snapshot{
 $paths=@("TaskbarMonitorEnhanced.exe","Uninstall.exe","config.json",
   "config.json.bak","install_state.json","Source/TaskbarMonitorEnhanced.cs",
   "Source/TaskbarGlass.cs","R265_PRESERVE_USER_CANARY.txt")
 $m=@{}
 foreach($path in $paths){$m[$path]=Hash (Join-Path $app $path)}
 return $m
}
function AssertUnchanged($before,[string]$case){
 $now=Snapshot
 if($now.Count -ne $before.Count){StopNow ("MAP_COUNT_"+$case)}
 foreach($item in $before.Keys){
  if($before[$item] -cne $now[$item]){StopNow ("USER_OR_MANAGED_DRIFT_"+$case+"_"+$item)}
 }
 if((Get-ItemProperty $reg -ErrorAction Stop).DisplayVersion -cne "1.7.5"){
  StopNow ("REGISTERED_VERSION_DRIFT_"+$case)
 }
 if((StartupValue) -cne $originalRun){StopNow ("STARTUP_DRIFT_"+$case)}
 if(Test-Path (Join-Path $app ".tbme-upgrade")){StopNow ("TRANSACTION_STAGE_LEFT_"+$case)}
 if(@(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count){StopNow ("MAIN_PROCESS_RUNNING_"+$case)}
}
if($build.Commit -cne $env:GITHUB_SHA -or $build.Version -cne "1.7.5" -or
   $build.Private -ne $true -or $build.NotForPublicInstallation -ne $true){
  StopNow "WRONG_PRIVATE_CANDIDATE_MANIFEST"
}
if((Hash $setup) -cne $build.SetupSHA256){StopNow "PRIVATE_COMPILED_SETUP_SHA_DRIFT"}
if((Test-Path $app) -or (Test-Path $reg) -or (Test-Path $legacy) -or
   (Test-Path $out) -or @(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count){
 StopNow "GUEST_NOT_CLEAN"
}
[void](New-Item -Path $out -ItemType Directory -ErrorAction Stop)
try{
 $phase="FRESH_TEST_ONLY_SETUP"
 $installedExit=RunCandidate "/install /quiet /desktop=0 /startup=0"
 if($installedExit -ne 0){StopNow ("FRESH_INSTALL_EXIT_"+$installedExit)}
 if((Hash (Join-Path $app "TaskbarMonitorEnhanced.exe")) -cne $build.MainSHA256 -or
    (Hash (Join-Path $app "Uninstall.exe")) -cne $build.SetupSHA256){
  StopNow "FRESH_INSTALL_PRODUCT_SHA_CHANGED"
 }
 $source=Join-Path $app "Source/TaskbarMonitorEnhanced.cs"
 $redundant=Join-Path $app "TaskbarMonitorEnhanced.cs"
 if((Hash $source) -ceq "MISSING"){StopNow "SINGLE_MANAGED_SOURCE_NOT_INSTALLED"}
 if(Test-Path $redundant){StopNow "REDUNDANT_ROOT_SOURCE_STILL_INSTALLED"}
 if(@(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count){StopNow "FRESH_MAIN_ALREADY_RUNNING"}
 $phase="CREATE_USER_OWNED_TEST_FIXTURE"
 $config=Join-Path $app "config.json"
 $backup=Join-Path $app "config.json.bak"
 $canary=Join-Path $app "R265_PRESERVE_USER_CANARY.txt"
 if(!(Test-Path $config)){
  [IO.File]::WriteAllText($config,'{"GlassMode":true,"Opacity":0,"OpacityWhenGlassOff":0.1,"R265UserFixture":"retain all bytes"}',[Text.UTF8Encoding]::new($false))
 }
 if(!(Test-Path $backup)){
  [IO.File]::WriteAllText($backup,'{"R265Backup":"independent prior user config must remain SHA-exact"}',[Text.UTF8Encoding]::new($false))
 }
 [IO.File]::WriteAllText($canary,"R265 synthetic guest user canary, no personal content",[Text.UTF8Encoding]::new($false))
 $originalRun=StartupValue
 $original=Snapshot
 if(@($original.Values|Where-Object {$_ -ceq "MISSING"}).Count){StopNow "EXPECTED_FRESH_FIXTURE_MISSING"}

 $phase="FIRST_SAME_VERSION_MAINTENANCE_IDEMPOTENCE"
 $sameVersionExit=RunCandidate "/update /quiet"
 if($sameVersionExit -ne 0){StopNow ("SAME_VERSION_MAINTENANCE_FAILED_"+$sameVersionExit)}
 AssertUnchanged $original "FIRST_IDEMPOTENCE"
 if(Test-Path $redundant){StopNow "MAINTENANCE_RECREATED_REDUNDANT_SOURCE"}

 $phase="REJECT_DISPOSABLE_PROGRAMFILES_DUPLICATE"
 if(Test-Path $legacy){StopNow "LEGACY_PATH_PREEXISTS"}
 [void](New-Item $legacy -ItemType Directory -ErrorAction Stop)
 $owned=$true
 [IO.File]::WriteAllText($marker,("R265 inert duplicate executable marker "+$HostLabel),[Text.UTF8Encoding]::new($false))
 $expectedMarker=Hash $marker
 if($expectedMarker -ceq "MISSING"){StopNow "LEGACY_INERT_MARKER_MISSING"}
 $negativeExit=RunCandidate "/update /quiet"
 if($negativeExit -ne 34){StopNow ("PROGRAMFILES_DUPLICATE_NOT_EXACTLY_REFUSED_"+$negativeExit)}
 if((Hash $marker) -cne $expectedMarker){StopNow "INERT_MARKER_MODIFIED"}
 AssertUnchanged $original "PROGRAMFILES_CONFLICT_REFUSAL"
 if((Hash $marker) -cne $expectedMarker){StopNow "MARKER_CHANGED_BEFORE_REMOVAL"}
 Remove-Item -LiteralPath $marker -Force -ErrorAction Stop
 if(@(Get-ChildItem -LiteralPath $legacy -Force).Count){StopNow "LEGACY_DIR_CONTENT_NOT_OWNED"}
 Remove-Item -LiteralPath $legacy -Force -ErrorAction Stop
 $owned=$false
 if(Test-Path $legacy){StopNow "LEGACY_DIR_NOT_REMOVED"}
 $removed=$true

 $phase="SECOND_IDEMPOTENT_UPDATE_AFTER_CONFLICT_REMOVAL"
 $afterCollisionExit=RunCandidate "/update /quiet"
 if($afterCollisionExit -ne 0){StopNow ("AFTER_COLLISION_MAINTENANCE_FAILED_"+$afterCollisionExit)}
 AssertUnchanged $original "SECOND_IDEMPOTENCE"
 if(Test-Path $redundant){StopNow "ROOT_REDUNDANCY_RETURNED"}
 $status="PASS_REAL_GUEST_FRESH_R265_NO_REDUNDANT_SOURCE_AND_TWICE_IDEMPOTENT"
}catch{
 $error=$_.Exception.GetType().Name+": "+$_.Exception.Message
}finally{
 if($owned -and (Test-Path $marker) -and (Hash $marker) -ceq $expectedMarker){
  Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
 }
 if($owned -and (Test-Path $legacy) -and @((Get-ChildItem -LiteralPath $legacy -Force -ErrorAction SilentlyContinue)).Count -eq 0){
  Remove-Item -LiteralPath $legacy -Force -ErrorAction SilentlyContinue
 }
 $e=[ordered]@{
  Revision="R265";Status=$status;Phase=$phase;Failure=$error;Host=$HostLabel
  SourceCommit=$env:GITHUB_SHA;TestOnlyCandidate=$true;PublicSetupChanged=$false
  PersonalComputerTouched=$false;ReleasedV173Untouched=$true
  CandidateMainSHA256=$build.MainSHA256;CandidateSetupSHA256=$build.SetupSHA256
  FreshInstallExit=$installedExit
  SingleManagedSourceWithoutRootDuplicate=(!(Test-Path (Join-Path $app "TaskbarMonitorEnhanced.cs")))
  FirstSameVersionMaintenanceExit=$sameVersionExit
  NegativeProgramFilesCollisionExit=$negativeExit
  SecondSameVersionMaintenanceExit=$afterCollisionExit
  GuestOwnedLegacyFixtureRemoved=(!(Test-Path $legacy))
  ProtectedCanaryAndConfigPreserved=($status -like "PASS_*")
  RealHKLMRegistryOrCrossUserAcceptance=$false
  NoPhysicalPowerCutOrExternalSecurityClaim=$true
  UTC=[DateTime]::UtcNow.ToString("o")
 }
 [IO.File]::WriteAllText($receipt,($e|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 Write-Output ($e|ConvertTo-Json -Compress -Depth 8)
}
if($status -notlike "PASS_*"){throw ("R265_REAL_GUEST_NOT_ACCEPTED "+$phase+" "+$error)}
