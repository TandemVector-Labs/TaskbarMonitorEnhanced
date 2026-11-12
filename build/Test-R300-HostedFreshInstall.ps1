# R300: actual compiled new-version fresh install on a wholly disposable, fresh
# GitHub-hosted Windows guest. This MUST NEVER run on the owner PC.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'GOD13emad/TaskbarMonitorEnhanced' -or
   $env:GITHUB_RUN_ID -cnotmatch '^[0-9]{5,20}$' -or
   $env:GITHUB_SHA -cnotmatch '^[0-9a-f]{40}$' -or
   $env:COMPUTERNAME -match '(?i)EMAD|ALIEMAD|LAPTOP|SAEID'){
 throw 'R300_NO_PERSONAL_OR_UNATTESTED_HOST_INSTALL'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if((git -C $repo rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){
 throw 'R300_CHECKOUT_COMMIT_NOT_EXACT'
}
$root=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$expectedRoot=Join-Path ([Environment]::GetFolderPath('UserProfile')) 'AppData/Local/TaskbarMonitorEnhanced'
if(-not [string]::Equals([IO.Path]::GetFullPath($root),[IO.Path]::GetFullPath($expectedRoot),[StringComparison]::OrdinalIgnoreCase)){
 throw 'R300_LOCALAPPDATA_NOT_CANONICAL'
}
$registry='Software\Microsoft\Windows\CurrentVersion\Uninstall\TaskbarMonitorEnhanced'
$autorun='Software\Microsoft\Windows\CurrentVersion\Run'
$start=Join-Path ([Environment]::GetFolderPath('Programs')) 'Taskbar Monitor Enhanced.lnk'
$repair=Join-Path ([Environment]::GetFolderPath('Programs')) 'Taskbar Monitor Enhanced - Repair Hardware Sensors.lnk'
$desktop=Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'Taskbar Monitor Enhanced.lnk'
$recovery=Join-Path ([Environment]::GetFolderPath('Startup')) 'Taskbar Monitor Enhanced Startup Recovery.lnk'
if((Test-Path $root) -or
   (Test-Path (Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'TaskbarMonitorEnhanced')) -or
   (Test-Path $start) -or (Test-Path $repair) -or (Test-Path $desktop) -or (Test-Path $recovery) -or
   @(Get-Process TaskbarMonitorEnhanced,TaskbarMonitorSensorBroker,TaskbarMonitorSensorSupervisor -ErrorAction SilentlyContinue).Count -gt 0 -or
   (Get-ScheduledTask -TaskName 'TaskbarMonitorEnhanced Sensor Broker' -ErrorAction SilentlyContinue) -or
   [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($registry,$false)){
 throw 'R300_REFUSE_NONFRESH_GUEST_OR_EXISTING_PRODUCT'
}
$run=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($autorun,$false)
try{
 if($run -and $null -ne $run.GetValue('TaskbarMonitorEnhanced',$null)){throw 'R300_AUTORUN_PREEXISTS'}
}finally{if($run){$run.Dispose()}}
$manifest=Get-Content (Join-Path $repo 'artifacts/BUILD_MANIFEST.json') -Raw|ConvertFrom-Json
if($manifest.Version -cne '1.7.10' -or
   $manifest.Build -cne 'V1_7_10_R299_PINNED_UNINSTALL_CANDIDATE'){
 throw 'R300_WRONG_VERSION_OR_BUILD_ORIGIN'
}
$setup=Join-Path $repo 'build/_out/Setup/TaskbarMonitorEnhanced_Setup_1.7.10.exe'
$rows=@($manifest.Outputs|Where-Object { $_.Name -ceq 'TaskbarMonitorEnhanced_Setup_1.7.10.exe' })
$mainRows=@($manifest.Outputs|Where-Object { $_.Name -ceq 'TaskbarMonitorEnhanced.exe' })
if($rows.Count -ne 1 -or $mainRows.Count -ne 1 -or
   !(Test-Path $setup -PathType Leaf) -or
   (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash -cne $rows[0].SHA256 -or
   (Get-Item $setup).Length -ne $rows[0].Bytes){
 throw 'R300_CANDIDATE_BINARY_NOT_BUILD_MANIFEST_PINNED'
}
$canary=Join-Path $env:RUNNER_TEMP ('R300_OUTSIDE_CANARY_'+$env:GITHUB_RUN_ID+'.txt')
if(Test-Path $canary){throw 'R300_CANARY_PREEXISTS'}
[IO.File]::WriteAllText($canary,'R300 synthetic external data canary',[Text.UTF8Encoding]::new($false))
$canaryHash=(Get-FileHash $canary).Hash
function Run-ExactSetup([string]$childArguments,[int]$timeoutMs){
 if($childArguments -cne '/install /quiet /desktop=0 /startup=0' -and
    $childArguments -cnotmatch '^/verify /verifyfile=[A-Z]:\\[^"]+\.json$'){
  throw 'R300_NOT_AN_APPROVED_INSTALLER_INVOCATION'
 }
 $info=New-Object Diagnostics.ProcessStartInfo
 $info.FileName=$setup
 $info.Arguments=$childArguments
 $info.WorkingDirectory=$env:RUNNER_TEMP
 $info.UseShellExecute=$false
 $info.CreateNoWindow=$true
 $proc=[Diagnostics.Process]::Start($info)
 if(!$proc){throw 'R300_SETUP_PROCESS_FAILED_TO_START'}
 try{
  if(!$proc.WaitForExit($timeoutMs)){
   try{$proc.Kill();[void]$proc.WaitForExit(10000)}catch{}
   throw 'R300_EXACT_SETUP_CHILD_TIMEOUT'
  }
  return [int]$proc.ExitCode
 }finally{$proc.Dispose()}
}
# Inspect original PE resource manifest without touching the user's machine.
$asm=[Reflection.Assembly]::LoadFrom([IO.Path]::GetFullPath($setup))
if($asm.GetName().Version.ToString() -cne '1.7.10.0'){throw 'R300_SETUP_ASSEMBLY_VERSION_BAD'}
$verify=Join-Path $env:RUNNER_TEMP ('R300_VERIFY_'+$env:GITHUB_RUN_ID+'.json')
if(Test-Path $verify){throw 'R300_VERIFY_RECEIPT_PREEXISTS'}
$code=Run-ExactSetup ('/verify /verifyfile='+$verify) 35000
if($code -ne 0 -or !(Test-Path $verify)){throw 'R300_SETUP_SELF_VERIFY_FAILED'}
$check=Get-Content $verify -Raw | ConvertFrom-Json
if($check.Status -cne 'PASS' -or $check.Resources -ne 25 -or
   $check.PawnIOBundled -ne $false -or $check.EmbeddedMainSHA256 -cne $mainRows[0].SHA256){
 throw 'R300_EXACT_COMPILED_SETUP_SELF_VERIFICATION_NOT_PASS'
}
'R300_HOSTED_SETUP_RESOURCE_VERIFY=PASS'
$code=Run-ExactSetup '/install /quiet /desktop=0 /startup=0' 170000
if($code -ne 0){throw ('R300_HOSTED_REAL_FRESH_INSTALL_RETURNED_'+$code)}
$main=Join-Path $root 'TaskbarMonitorEnhanced.exe'
$maint=Join-Path $root 'Uninstall.exe'
$state=Join-Path $root 'install_state.json'
$config=Join-Path $root 'TaskbarMonitorEnhanced.exe.config'
if(!(Test-Path $main) -or !(Test-Path $maint) -or
   !(Test-Path $state) -or !(Test-Path $config)){
 throw 'R300_INSTALLED_PROGRAM_CORE_FILES_MISSING'
}
if((Get-FileHash $main).Hash -cne $mainRows[0].SHA256 -or
   (Get-FileHash $maint).Hash -cne $rows[0].SHA256){
 throw 'R300_INSTALLED_EXACT_MAIN_OR_SETUP_DIGEST_MISMATCH'
}
$installedState=Get-Content $state -Raw|ConvertFrom-Json
if($installedState.Version -cne '1.7.10' -or
   $installedState.PublicVersion -cne '1.7.10' -or
   $installedState.ProductIdentity -cne 'LOCKED' -or
   [string]::IsNullOrWhiteSpace([string]$installedState.SensorLayerStatus)){
 throw 'R300_INSTALLED_VERSION_OR_SENSOR_STATE_INVALID'
}
$u=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($registry,$false)
if(!$u){throw 'R300_INSTALL_UNINSTALL_REGISTRY_ABSENT'}
try{
 if($u.GetValue('DisplayVersion') -cne '1.7.10' -or
    [string]$u.GetValue('InstallLocation') -cne $root){
  throw 'R300_WRONG_INSTALLED_REGISTRY_IDENTITY'
 }
}finally{$u.Dispose()}
if(!(Test-Path $start) -or !(Test-Path $repair) -or
   (Test-Path $desktop) -or (Test-Path $recovery)){
 throw 'R300_DESKTOP_STARTUP_CHOICE_OR_START_MENU_SHORTCUT_INVALID'
}
$run=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($autorun,$false)
try{if($run -and $null -ne $run.GetValue('TaskbarMonitorEnhanced',$null)){throw 'R300_STARTUP_FALSE_NOT_HONORED'}}
finally{if($run){$run.Dispose()}}
if((Get-FileHash $canary).Hash -cne $canaryHash){throw 'R300_EXTERNAL_CANARY_MUTATED'}
$release=Join-Path $root 'Docs/RELEASE_NOTES_v1.7.10.md'
if(!(Test-Path $release) -or (Test-Path (Join-Path $root 'Docs/RELEASE_NOTES_v1.7.9.md'))){
 throw 'R300_RELEASE_NOTE_NOT_CURRENT_SINGLE_VERSION'
}
if(Test-Path (Join-Path $root '.tbme-upgrade')){throw 'R300_FRESH_INSTALL_LEFT_UPGRADE_JOURNAL'}
# The app may auto-launch non-elevated. Never terminate any other processes.
$processes=@(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue)
foreach($p in $processes){
 if(-not [string]::Equals([IO.Path]::GetFullPath($p.Path),[IO.Path]::GetFullPath($main),[StringComparison]::OrdinalIgnoreCase)){
  throw 'R300_UNEXPECTED_PROGRAM_PROCESS_PATH'
 }
}
'R300_HOSTED_REAL_FRESH_INSTALL_AND_EXACT_BINARY_HASHES=PASS'
'R300_HOSTED_ONE_ROOT_START_MENU_REGISTRY_AND_STARTUP_FALSE=PASS'
'R300_HOSTED_REAL_INSTALL_SENSOR_STATE_AND_EXTERNAL_CANARY=PASS'
$receipt=[ordered]@{
 Schema=1
 Status='PASS_REAL_COMPILED_V1710_FRESH_INSTALL'
 GithubSha=$env:GITHUB_SHA
 SetupSHA256=[string]$rows[0].SHA256
 MainSHA256=[string]$mainRows[0].SHA256
 Version='1.7.10'
 OneCanonicalUserInstallRoot=$true
 DesktopDisabled=$true
 StartupDisabled=$true
 StartMenuShortcutsCreated=$true
 InstallStateVersionValid=$true
 OptionalSensorStateRecorded=$true
 ExternalCanaryPreserved=$true
 OwnerComputerUntouched=$true
 Utc=[DateTime]::UtcNow.ToString('o')
}
$receiptPath=Join-Path $env:RUNNER_TEMP 'R300_HOSTED_FRESH_INSTALL_RECEIPT.json'
if(Test-Path $receiptPath){throw 'R300_RECEIPT_ALREADY_EXISTS'}
[IO.File]::WriteAllText($receiptPath,($receipt|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
'R300_HOSTED_FRESH_INSTALL_RECEIPT=PASS'
