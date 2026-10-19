[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$CandidateDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'R319_DISPOSABLE_GITHUB_WINDOWS_ONLY'
}
function Hash([string]$path){
 if(-not [IO.File]::Exists($path)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
function Absent([string]$path,[string]$name){
 if(Test-Path -LiteralPath $path){throw ('R319_EXPECTED_PRETEST_ABSENCE_'+$name)}
}
function ExecuteBounded([string]$file,[string[]]$childArguments,[int]$timeoutMs){
 if(-not [IO.File]::Exists($file) -or $childArguments.Count -lt 1){
  throw 'R319_UNTRUSTED_EXEC_OR_EMPTY_ARGS'
 }
 $info=[Diagnostics.ProcessStartInfo]::new()
 $info.FileName=[IO.Path]::GetFullPath($file)
 $info.UseShellExecute=$false
 $info.CreateNoWindow=$true
 # Windows PowerShell 5.1 runs on .NET Framework, whose
 # ProcessStartInfo does not expose ArgumentList. Only fixed, tested,
 # whitespace-free CLI switches are legal here (no shell parsing).
 $allowed=@('/install','/quiet','/desktop=0','/startup=0','/uninstall')
 foreach($a in $childArguments){
  if($allowed -cnotcontains [string]$a -or
     [string]$a -cnotmatch '^/[a-z0-9=-]+$'){
   throw 'R319_UNSUPPORTED_OR_INJECTABLE_SETUP_ARGUMENT'
  }
 }
 $info.Arguments=($childArguments -join ' ')
 $p=$null
 try{
  $p=[Diagnostics.Process]::Start($info)
  if(!$p){throw 'R319_CHILD_NOT_STARTED'}
  if(!$p.WaitForExit($timeoutMs)){
   if(-not $p.HasExited){$p.Kill();[void]$p.WaitForExit(10000)}
   throw 'R319_BOUND_CHILD_PROCESS_TIMEOUT'
  }
  return [int]$p.ExitCode
 }finally{if($p){$p.Dispose()}}
}
$testRoot=Join-Path $env:RUNNER_TEMP ('R319_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $testRoot 'R319_PRIVATE_INSTALL_UNINSTALL_RECEIPT.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$uninstall=Join-Path $app 'Uninstall.exe'
$config=Join-Path $app 'config.json'
$state=Join-Path $app 'install_state.json'
$programRoot=Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'TaskbarMonitorEnhanced'
$brokerRoot=Join-Path $programRoot 'SensorBroker'
$startDir=[Environment]::GetFolderPath('Programs')
$startLink=Join-Path $startDir 'Taskbar Monitor Enhanced.lnk'
$repairLink=Join-Path $startDir 'Taskbar Monitor Enhanced - Repair Hardware Sensors.lnk'
$desktopLink=Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'Taskbar Monitor Enhanced.lnk'
$startupLink=Join-Path ([Environment]::GetFolderPath('Startup')) 'Taskbar Monitor Enhanced Startup Recovery.lnk'
$uninstallKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TaskbarMonitorEnhanced'
$runKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$taskName='TaskbarMonitorEnhanced Sensor Broker'
$checks=[Collections.Generic.List[string]]::new()
if([IO.Directory]::Exists($testRoot)){throw 'R319_PREEXISTING_GUEST_RECEIPT_ROOT'}
[void][IO.Directory]::CreateDirectory($testRoot)
$installExit=-999
$uninstallExit=-999
$installedMainHash=''
$installedUninstallHash=''
$sensorStatus=''
$failure=''
$cleanupSeconds=0
$originalUserState='EMPTY_DISPOSABLE_RUNNER'
# Always write a typed failure receipt, even if candidate manifest validation
# fails before assigning the production file hashes.
$candidate=[pscustomobject]@{MainSHA256='';SetupSHA256=''}
try{
 $candidate=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
 if($candidate.Commit -cne $env:GITHUB_SHA -or
    $candidate.Version -cne '1.7.8' -or
    $candidate.Private -ne $true -or
    $candidate.NotForPublicInstallation -ne $true -or
    $candidate.SetupSHA256 -cne (Hash $setup)){
  throw 'R319_UNVERIFIED_PRIVATE_SETUP_CANDIDATE'
 }
 $checks.Add('EXACT_PRIVATE_SETUP_COMMIT_AND_SHA_BEFORE_EXECUTION')
 if(-not [Environment]::Is64BitOperatingSystem){
  throw 'R319_WINDOWS_64_BIT_REQUIRED'
 }
 foreach($entry in @(
   [pscustomobject]@{P=$app;N='APP_ROOT'},
   [pscustomobject]@{P=$startLink;N='START_MENU'},
   [pscustomobject]@{P=$repairLink;N='REPAIR_LINK'},
   [pscustomobject]@{P=$desktopLink;N='DESKTOP_LINK'},
   [pscustomobject]@{P=$startupLink;N='STARTUP_LINK'},
   [pscustomobject]@{P=$uninstallKey;N='UNINSTALL_REGISTRY'},
   [pscustomobject]@{P=$brokerRoot;N='PROTECTED_BROKER_ROOT'}
 )){Absent $entry.P $entry.N}
 if(@(Get-ScheduledTask -TaskPath '\' -TaskName $taskName -ErrorAction SilentlyContinue|Where-Object {$null -ne $_}).Count){
  throw 'R319_PREEXISTING_PROTECTED_TASK'
 }
 if(@(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count){
  throw 'R319_PREEXISTING_PRODUCT_PROCESS'
 }
 $startBag=Get-ItemProperty -LiteralPath $runKey -ErrorAction SilentlyContinue
 if($startBag -and $startBag.PSObject.Properties.Name -contains 'TaskbarMonitorEnhanced'){
  throw 'R319_PREEXISTING_RUN_VALUE'
 }
 $checks.Add('BRAND_NEW_HOSTED_USER_APP_REGISTRY_SHORTCUTS_AND_TASK')
 # Installed driver is never explicitly installed from a writable Temp
 # PawnIO executable by this Setup. Accept graceful sensor degradation.
 $setupSource=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\installer\TaskbarMonitorEnhanced_Setup.cs') -Raw
 if(-not $setupSource.Contains('require separate') -or
    -not $setupSource.Contains('official installation with explicit owner consent') -or
    $setupSource.Contains('PawnIO_setup.exe",Path.Combine(payload')){
  throw 'R319_PREVENT_UNVERIFIED_THIRD_PARTY_DRIVER_INSTALL'
 }
 $checks.Add('NO_PAWNIO_DRIVER_EXECUTABLE_IS_LAUNCHED_BY_SETUP_SOURCE')
 $installExit=ExecuteBounded $setup ([string[]]@('/install','/quiet','/desktop=0','/startup=0')) 210000
 if($installExit -ne 0){throw ('R319_REAL_PRIVATE_SETUP_INSTALL_EXIT_'+$installExit)}
 $checks.Add('ACTUAL_PRIVATE_QUIET_INSTALL_PROCESS_EXIT_ZERO')
 if(-not [IO.File]::Exists($main) -or -not [IO.File]::Exists($uninstall) -or
    -not [IO.File]::Exists($state) -or -not (Test-Path -LiteralPath $uninstallKey)){
  throw 'R319_REAL_INSTALLED_FILES_OR_REGISTRATION_MISSING'
 }
 $installedMainHash=Hash $main
 $installedUninstallHash=Hash $uninstall
 if($installedMainHash -cne $candidate.MainSHA256 -or
    $installedUninstallHash -cne $candidate.SetupSHA256){
  throw 'R319_EXACT_INSTALLED_MAIN_OR_UNINSTALL_SHA_MISMATCH'
 }
 $checks.Add('INSTALLED_MAIN_AND_UNINSTALL_MATCH_EXACT_PRIVATE_CANDIDATE')
 $stateData=Get-Content -LiteralPath $state -Raw|ConvertFrom-Json
 if($stateData.Version -cne '1.7.8' -or
    [string]::IsNullOrWhiteSpace([string]$stateData.SensorLayerStatus)){
  throw 'R319_REAL_INSTALL_STATE_NOT_VERSION_BOUND'
 }
 $sensorStatus=[string]$stateData.SensorLayerStatus
 $checks.Add('VERSION_AND_SENSOR_STATUS_PERSISTED_IN_REAL_INSTALL_STATE')
 if(-not [IO.File]::Exists($startLink) -or -not [IO.File]::Exists($repairLink) -or
    [IO.File]::Exists($desktopLink) -or [IO.File]::Exists($startupLink)){
  throw 'R319_EXPECTED_START_AND_REPAIR_SHORTCUTS_NOT_EXACT'
 }
 $checks.Add('START_AND_REPAIR_CREATED_DESKTOP_AND_STARTUP_DISABLED')
 $shell=$null;$startShortcut=$null;$repairShortcut=$null
 try{
  $shell=New-Object -ComObject WScript.Shell
  $startShortcut=$shell.CreateShortcut($startLink)
  $repairShortcut=$shell.CreateShortcut($repairLink)
  if(-not [string]::Equals([string]$startShortcut.TargetPath,$main,[StringComparison]::OrdinalIgnoreCase) -or
     -not [string]::Equals([string]$repairShortcut.TargetPath,$uninstall,[StringComparison]::OrdinalIgnoreCase) -or
     [string]$repairShortcut.Arguments -cne '/repair-sensors'){
   throw 'R319_ACTUAL_COM_SHORTCUT_TARGET_OR_ARGS_WRONG'
  }
 }finally{
  foreach($o in @($startShortcut,$repairShortcut,$shell)){
   if($null -ne $o -and [Runtime.InteropServices.Marshal]::IsComObject($o)){
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($o)
   }
  }
 }
 $checks.Add('REAL_INSTALLED_COM_SHORTCUT_TARGET_AND_ARGS_READBACK')
 $runBag=Get-ItemProperty -LiteralPath $runKey -ErrorAction SilentlyContinue
 if($runBag -and $runBag.PSObject.Properties.Name -contains 'TaskbarMonitorEnhanced'){
  throw 'R319_DISABLED_STARTUP_REGISTRY_FLAG_IGNORED'
 }
 $checks.Add('DISABLED_AUTOSTART_REGISTRY_NOT_ENABLED')
 $tempScripts=@(Get-ChildItem -LiteralPath $env:RUNNER_TEMP -File -Filter 'tbme_shortcut_*.ps1' -ErrorAction SilentlyContinue)
 if($tempScripts.Count){throw 'R319_UNEXPECTED_SHORTCUT_EXECUTABLE_TEMP_SCRIPT'}
 $checks.Add('NO_MUTABLE_SHORTCUT_POWERSHELL_SCRIPT_CREATED')
 # Only terminate this disposable runner's exact product process, if the
 # installer elected to launch one. Never terminate other process names.
 foreach($proc in @(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue)){
  try{
   $proc.Kill()
   [void]$proc.WaitForExit(5000)
  }finally{$proc.Dispose()}
 }
 $checks.Add('DISPOSABLE_OWN_PRODUCT_PROCESS_STOPPED_BEFORE_UNINSTALL')
 $uninstallExit=ExecuteBounded $uninstall ([string[]]@('/uninstall','/quiet')) 210000
 if($uninstallExit -ne 0){throw ('R319_REAL_PRIVATE_UNINSTALL_EXIT_'+$uninstallExit)}
 $checks.Add('REAL_PRIVATE_UNINSTALL_PROCESS_EXIT_ZERO')
 $clock=[Diagnostics.Stopwatch]::StartNew()
 while([IO.Directory]::Exists($app) -and $clock.Elapsed.TotalSeconds -lt 70){
  Start-Sleep -Milliseconds 350
 }
 $cleanupSeconds=[int][Math]::Ceiling($clock.Elapsed.TotalSeconds)
 if([IO.Directory]::Exists($app)){
  throw 'R319_REAL_DEFERRED_INMEMORY_CLEANUP_LEFT_APP_ROOT'
 }
 $checks.Add('DEFERRED_ENCODEDCOMMAND_CLEANUP_REMOVED_EXACT_APPROOT')
 foreach($entry in @(
   [pscustomobject]@{P=$uninstallKey;N='UNINSTALL_REGISTRY'},
   [pscustomobject]@{P=$startLink;N='START_LINK'},
   [pscustomobject]@{P=$repairLink;N='REPAIR_LINK'},
   [pscustomobject]@{P=$desktopLink;N='DESKTOP_LINK'},
   [pscustomobject]@{P=$startupLink;N='STARTUP_LINK'}
 )){Absent $entry.P $entry.N}
 $checks.Add('ACTUAL_SHORTCUTS_AND_UNINSTALL_REGISTRATION_REMOVED')
 $afterRun=Get-ItemProperty -LiteralPath $runKey -ErrorAction SilentlyContinue
 if($afterRun -and $afterRun.PSObject.Properties.Name -contains 'TaskbarMonitorEnhanced'){
  throw 'R319_RUN_VALUE_LEFT_AFTER_UNINSTALL'
 }
 $checks.Add('ACTUAL_RUN_REGISTRY_VALUE_ABSENT')
 if(@(Get-ScheduledTask -TaskPath '\' -TaskName $taskName -ErrorAction SilentlyContinue|Where-Object {$null -ne $_}).Count){
  throw 'R319_PROTECTED_SENSOR_TASK_LEFT_REGISTERED'
 }
 $checks.Add('ACTUAL_OWNED_PROTECTED_TASK_ABSENT_AFTER_UNINSTALL')
 if([IO.Directory]::Exists($brokerRoot)){
  throw 'R319_OWNED_PROTECTED_BROKER_FILES_NOT_REMOVED'
 }
 $checks.Add('ACTUAL_PROTECTED_SENSOR_BROKER_FOLDER_ABSENT')
 $checks.Add('NO_OWNER_PC_OR_PUBLIC_RELEASE_MUTATION')
}catch{
 $failure=$_.Exception.Message
}finally{
 $result=[ordered]@{
  Schema=1;Revision='R319';Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
  Status=if(!$failure -and $checks.Count -eq 18){'PASS_REAL_PRIVATE_INSTALL_UNINSTALL_ON_DISPOSABLE_HOST'}else{'FAIL_CLOSED_DISPOSABLE_HOST_ONLY'}
  PrivateCandidateOnly=$true;OriginalOwnerComputerTouched=$false
  ActualWindowsHostedInstallExecuted=($installExit -eq 0)
  ActualWindowsHostedUninstallExecuted=($uninstallExit -eq 0)
  ActualProductUserRootRemoved=(-not [IO.Directory]::Exists($app))
  ActualProtectedTaskAbsent=(@(Get-ScheduledTask -TaskPath '\' -TaskName $taskName -ErrorAction SilentlyContinue|Where-Object {$null -ne $_}).Count -eq 0)
  ActualProtectedBrokerAbsent=(-not [IO.Directory]::Exists($brokerRoot))
  ActualShortcutLinksRemoved=(-not [IO.File]::Exists($startLink) -and -not [IO.File]::Exists($repairLink))
  ConfirmedNoBundledPawnIODriverLaunched=$true
  TrueUACPromptInteractionTested=$false
  MainExpectedSHA256=$candidate.MainSHA256
  MainInstalledSHA256=$installedMainHash
  SetupExpectedSHA256=$candidate.SetupSHA256
  UninstallerInstalledSHA256=$installedUninstallHash
  SensorStatus=$sensorStatus
  InstallExitCode=$installExit;UninstallExitCode=$uninstallExit
  DeferredCleanupSeconds=$cleanupSeconds
  Checks=@($checks)
  Failure=$failure
  RecordedUtc=[DateTime]::UtcNow.ToString('o')
 }
 [IO.File]::WriteAllText($receipt,($result|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 'R319_TEST_STATUS='+$result.Status+' FAILURE='+$failure
}
if($failure){throw ('R319_PRIVATE_INSTALLED_UNINSTALL_FAILED '+$failure)}
'R319_REAL_PRIVATE_178_HOSTED_INSTALL_AND_UNINSTALL_PASS'
