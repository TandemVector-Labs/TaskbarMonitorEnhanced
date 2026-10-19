[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][ValidateSet('PREPARED','COMMITTING')][string]$Phase
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
# Irreversible termination is ONLY allowed for the exact child we launch
# on an authenticated disposable GitHub-hosted Windows VM.
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   ![Environment]::UserInteractive){throw 'R282_REFUSE_NON_DISPOSABLE_OR_OWNER_HOST'}
$repo='GOD13emad/TaskbarMonitorEnhanced'
$releaseHead='2348791fbde3aff5a18b7df536dba8a66a65d191'
$sha175='8E37397F02273952B5866003FC156E152B13FC90D95D80B5DB4208046DD588EC'
$sha176='D1FE446CC2D8274A5B63E8080FAB15767A6799B5A377584B0F7B923056E2CEE0'
$main175='25E0565301963467BF290908BE965F73EDDE6BF41EC693A4FE45ED19653FBDB6'
$main176='0FA50938D330DB02D7D66593740F51FEE5D3036C59484E5697C34DCBC55A2DF8'
$app=Join-Path $env:LOCALAPPDATA 'TaskbarMonitorEnhanced'
$uninstall='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TaskbarMonitorEnhanced'
$stage=Join-Path $app '.tbme-upgrade'
$out=Join-Path $env:RUNNER_TEMP ('TBME_R282_'+$HostLabel+'_'+$Phase)
$armed=Join-Path $out 'ARMED.json'
$receipt=Join-Path $out 'R282_ABRUPT_RECOVERY.json'
$childScript=Join-Path $out 'StageChild.ps1'
if((Test-Path $out) -or (Test-Path $app) -or (Test-Path $uninstall) -or
   @(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count -gt 0){
 throw 'R282_REFUSE_NON_FRESH_HOST_OR_PREEXISTING_PRODUCT'
}
$previousExe=$null;$currentExe=$null;$stageProcess=$null
$phaseNow='START'
$reason='';$passes=@();$terminated=$false;$partialReplacement=$false
function Hash([string]$p){
 if(Test-Path $p -PathType Leaf){return (Get-FileHash $p -Algorithm SHA256).Hash}
 return 'MISSING'
}
function Run-Exact([string]$exe,[string]$arguments){
 # Do not use '$args' as a parameter: PowerShell automatically replaces it with
 # unbound positional arguments, silently dropping /update /quiet and hanging GUI.
 if($arguments -cne '/update /quiet'){throw ('R282_UNEXPECTED_SETUP_ARGUMENT_STRING_'+$arguments)}
 # Exact process launch from successful R273 hosted installer acceptance.
 $si=New-Object Diagnostics.ProcessStartInfo
 $si.FileName=$exe;$si.Arguments=$arguments;$si.UseShellExecute=$false
 $si.WorkingDirectory=(Split-Path $exe -Parent)
 $p=[Diagnostics.Process]::Start($si)
 if(!$p){throw 'R282_SETUP_NOT_STARTED'}
 try{
  if(!$p.WaitForExit(190000)){
   $children=@(Get-CimInstance Win32_Process | Where-Object {$_.ParentProcessId -eq $p.Id} | Select-Object -ExpandProperty Name)
   $driver=Get-Service PawnIO -ErrorAction SilentlyContinue
   $snapshot=[ordered]@{
    FailedPhase=$phaseNow;InstallerPid=$p.Id
    InstallerStillRunning=(-not $p.HasExited)
    ChildProcessNames=$children
    InstalledRootExists=[bool](Test-Path $app)
    InstalledMainPresent=[bool](Test-Path (Join-Path $app 'TaskbarMonitorEnhanced.exe'))
    InstalledStatePresent=[bool](Test-Path (Join-Path $app 'install_state.json'))
    PawnIOServiceState=$(if($driver){[string]$driver.Status}else{'NOT_PRESENT'})
    CanReadInstallLogs=[bool](Test-Path (Join-Path $app 'Logs'))
    RecordedUtc=[DateTime]::UtcNow.ToString('o')
   }
   [IO.File]::WriteAllText((Join-Path $out 'R282_INSTALL_DIAGNOSTIC.json'),($snapshot|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
   throw ('R282_SETUP_TIMEOUT_PID_'+$p.Id+'_CHILDREN_'+($children -join ','))
  }
  return [int]$p.ExitCode
 }finally{$p.Dispose()}
}
function Startup(){
 $p=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
 if(!$p){return 'ABSENT'}
 $v=$p.PSObject.Properties['TaskbarMonitorEnhanced']
 return $(if(!$v){'ABSENT'}else{[string]$v.Value})
}
# Minimal child script: all source / installer functions are the unchanged,
# SHA-pinned public 1.7.6 code. The child itself is the sole forced termination target.
$childText=@'
param(
 [Parameter(Mandatory=$true)][string]$Setup,
 [Parameter(Mandatory=$true)][string]$App,
 [Parameter(Mandatory=$true)][string]$Signal,
 [Parameter(Mandatory=$true)][string]$Phase
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
try{
 if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
    $env:RUNNER_OS -cne 'Windows' -or $env:COMPUTERNAME -match '(?i)EMAD-PC'){throw 'CHILD_REFUSES_PERSONAL_HOST'}
 if((Get-FileHash $Setup).Hash -ne 'D1FE446CC2D8274A5B63E8080FAB15767A6799B5A377584B0F7B923056E2CEE0'){throw 'WRONG_PUBLIC_SETUP'}
 if((Get-FileHash (Join-Path $App 'TaskbarMonitorEnhanced.exe')).Hash -ne '25E0565301963467BF290908BE965F73EDDE6BF41EC693A4FE45ED19653FBDB6'){throw 'WRONG_INSTALLED_PREDECESSOR'}
 if(Test-Path (Join-Path $App '.tbme-upgrade')){throw 'JOURNAL_ALREADY_PRESENT'}
 if(@(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count){throw 'APP_RUNNING_DURING_DISPOSABLE_TEST'}
 Add-Type -TypeDefinition 'using System.IO; public static class R282FileBridge { public static void ReplaceNoBackup(string a,string b){File.Replace(a,b,null);} }'
 $asm=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($Setup))
 $t=$asm.GetType('SetupProgram',$true)
 $f=[Reflection.BindingFlags]'Static,NonPublic,Public'
 $version='1.7.5';$channel='OFFICIAL_STABLE_V175'
 $state=([IO.File]::ReadAllText((Join-Path $App 'install_state.json')))
 $legacy=$t.GetMethod('LegacyExpected',$f).Invoke($null,[object[]]@($version,$channel))
 $fresh=$t.GetMethod('PrepareNewBytes',$f).Invoke($null,[object[]]@($state))
 $fresh['Uninstall.exe']=[IO.File]::ReadAllBytes($Setup)
 [void]$t.GetMethod('StageNewManaged',$f).Invoke($null,[object[]]@($fresh,$legacy,$state,$version,$channel))
 if($Phase -ceq 'COMMITTING'){
  [void]$t.GetMethod('WritePhase',$f).Invoke($null,[object[]]@('COMMITTING'))
  foreach($rel in @('TaskbarMonitorEnhanced.exe','Source/TaskbarGlass.cs')){
   $staged=Join-Path (Join-Path $App '.tbme-upgrade\new') $rel
   $live=Join-Path $App $rel
   [R282FileBridge]::ReplaceNoBackup($staged,$live)
  }
  if((Get-FileHash (Join-Path $App 'TaskbarMonitorEnhanced.exe')).Hash -ne '0FA50938D330DB02D7D66593740F51FEE5D3036C59484E5697C34DCBC55A2DF8'){throw 'PHYSICAL_PARTIAL_COMMIT_UNVERIFIED'}
 }
 $report=[ordered]@{Phase=$Phase;ChildProcessId=$PID;CommittedManagedCount=$(if($Phase -eq 'COMMITTING'){2}else{0});ArmUtc=[DateTime]::UtcNow.ToString('o')}
 [IO.File]::WriteAllText($Signal,($report|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
 while($true){Start-Sleep -Seconds 3}
}catch{
 $errorPath=[IO.Path]::ChangeExtension($Signal,'.error.txt')
 [IO.File]::WriteAllText($errorPath,$_.Exception.ToString(),[Text.UTF8Encoding]::new($false))
 throw
}
'@
$receiptWritten=$false
[IO.Directory]::CreateDirectory($out)|Out-Null
try{
 $phaseNow='DOWNLOAD_OFFICIAL_RELEASES'
 $env:GH_PROMPT_DISABLED='1'
 & gh release download v1.7.5 -R $repo -p TaskbarMonitorEnhanced_Setup_1.7.5.exe -D $out
 if($LASTEXITCODE -ne 0){throw 'PRIOR_175_RELEASE_DOWNLOAD_FAILED'}
 & gh release download v1.7.6 -R $repo -p TaskbarMonitorEnhanced_Setup_1.7.6.exe -D $out
 if($LASTEXITCODE -ne 0){throw 'CURRENT_176_RELEASE_DOWNLOAD_FAILED'}
 $previousExe=Join-Path $out 'TaskbarMonitorEnhanced_Setup_1.7.5.exe'
 $currentExe=Join-Path $out 'TaskbarMonitorEnhanced_Setup_1.7.6.exe'
 if((Hash $previousExe) -cne $sha175 -or (Hash $currentExe) -cne $sha176){throw 'SIGNED_OFF_PUBLIC_ASSET_SHA_CHANGED'}
 $passes+=@('PUBLIC_175_176_ASSETS_PINNED')
 $phaseNow='STAGE_EXACT_22_SHA_PINNED_OFFICIAL_V175_RESOURCES_ONLY'
 # Previous authentic R273 hosted CI covered genuine fresh 1.7.5 install;
 # this R282 isolated crash test needs a byte-exact prior product root WITHOUT
 # installing privileged machine drivers or invoking fresh Setup/UAC.
 $inventory=Get-Content (Join-Path $PSScriptRoot 'official-v175-managed.json') -Raw|ConvertFrom-Json
 if($inventory.Version -ne '1.7.5' -or $inventory.ManagedCount -ne 22 -or
    $inventory.PublishedSetupSHA256 -cne $sha175 -or $inventory.PublishedMainSHA256 -cne $main175 -or
    @($inventory.Rows).Count -ne 22){throw 'R282_PREDECESSOR_22_FILE_PINNING_CHANGED'}
 $assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($previousExe))
 [IO.Directory]::CreateDirectory($app)|Out-Null
 foreach($row in $inventory.Rows){
  $rel=[string]$row.Path
  if([string]::IsNullOrWhiteSpace($rel) -or [IO.Path]::IsPathRooted($rel) -or
     $rel -match '(^|[/\\])\.\.([/\\]|$)' -or $rel -match '[:*?"<>|]'){throw 'R282_UNSAFE_PREDECESSOR_MEMBER'}
  $dest=Join-Path $app $rel
  $normalized=[IO.Path]::GetFullPath($dest)
  if(!$normalized.StartsWith(([IO.Path]::GetFullPath($app).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'R282_RESOURCE_OUTPUT_OUTSIDE_DISPOSABLE_ROOT'}
  [IO.Directory]::CreateDirectory((Split-Path $normalized -Parent))|Out-Null
  if(Test-Path $normalized){throw ('R282_DUPLICATE_RESOURCE_'+$rel)}
  if($rel -ceq 'Uninstall.exe'){
   [IO.File]::Copy($previousExe,$normalized)
  }else{
   $resourceName='Payload.'+[IO.Path]::GetFileName($rel)
   $stream=$assembly.GetManifestResourceStream($resourceName)
   if(!$stream){throw ('R282_PREDECESSOR_EMBEDDED_RESOURCE_MISSING_'+$resourceName)}
   try{
    $target=[IO.File]::Open($normalized,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$stream.CopyTo($target)}finally{$target.Dispose()}
   }finally{$stream.Dispose()}
  }
  if((Hash $normalized) -cne $row.SHA256 -or (Get-Item $normalized).Length -ne $row.Bytes){throw ('R282_OFFICIAL_PREDECESSOR_ROW_IDENTITY_DRIFT_'+$rel)}
 }
 $backendRoot=Join-Path $app 'SensorBackend\LibreHardwareMonitor-0.9.6'
 $archive=Join-Path $out 'LHM_096_REPLAY_FROM_OFFICIAL_175_SETUP.zip'
 $stream=$assembly.GetManifestResourceStream('Payload.LibreHardwareMonitor.zip')
 if(!$stream){throw 'R282_OFFICIAL_SENSOR_LIBRARY_RESOURCE_MISSING'}
 try{
  $target=[IO.File]::Open($archive,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$stream.CopyTo($target)}finally{$target.Dispose()}
 }finally{$stream.Dispose()}
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 [IO.Directory]::CreateDirectory($backendRoot)|Out-Null
 [IO.Compression.ZipFile]::ExtractToDirectory($archive,$backendRoot)
 if((Hash (Join-Path $backendRoot 'LibreHardwareMonitorLib.dll')) -cne '6EBC194316536BA61AF5BE24508AD9FCBB2ECC685E716C12E787C79530F66BF0'){throw 'R282_PINNED_BACKEND_LIBRARY_WRONG'}
 $synthetic=[ordered]@{App='Taskbar Monitor Enhanced';Version='1.7.5';PublicVersion='1.7.5'
  ProductIdentity='LOCKED';SensorLayerStatus='READY';SensorLayerMode='R282_DISPOSABLE_PRESEEDED_NO_DRIVER'
  SensorLayerVersion='0.9.6';MainLaunchMode='NOT_STARTED_DISPOSABLE';R282Fixture=$true}
 [IO.File]::WriteAllText((Join-Path $app 'install_state.json'),($synthetic|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
 $key=New-Item -Path $uninstall -Force -ErrorAction Stop
 Set-ItemProperty -Path $uninstall -Name 'DisplayName' -Value 'Taskbar Monitor Enhanced'
 Set-ItemProperty -Path $uninstall -Name 'DisplayVersion' -Value '1.7.5'
 Set-ItemProperty -Path $uninstall -Name 'InstallLocation' -Value $app
 $key.Dispose()
 if((Hash (Join-Path $app 'TaskbarMonitorEnhanced.exe')) -cne $main175 -or
    (Hash (Join-Path $app 'Uninstall.exe')) -cne $sha175 -or
    (Get-ItemProperty $uninstall).DisplayVersion -cne '1.7.5'){throw 'R282_PINNED_PREDECESSOR_FIXTURE_INCOMPLETE'}
 if(@(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count){throw 'DISPOSABLE_FIXTURE_STARTED_REAL_PRODUCT'}
 $passes+=@('22_OFFICIAL_V175_MANAGED_ROWS_VERIFIED_SHA_FROM_EMBEDDED_RESOURCES','NO_PRIVILEGED_SENSOR_DRIVER_INSTALLED')
 $config=Join-Path $app 'config.json'
 $backup=Join-Path $app 'config.json.bak'
 $userOwned=Join-Path $app 'R282_USER_OWNED_CANARY.txt'
 $backend=Join-Path $app 'SensorBackend\LibreHardwareMonitor-0.9.6\LibreHardwareMonitorLib.dll'
 $fixture='{"Theme":"Retro Terminal","GlassMode":true,"Opacity":0.0,"EnableTemperatureAlerts":true,"EnableTemperatureNotifications":true,"R282Canary":"MUST_PRESERVE_ABRUPT_STAGE"}'
 [IO.File]::WriteAllText($config,$fixture,[Text.UTF8Encoding]::new($false))
 [IO.File]::WriteAllText($backup,'{"R282Backup":"INDEPENDENT"}',[Text.UTF8Encoding]::new($false))
 [IO.File]::WriteAllText($userOwned,'R282 disposable user file remains unchanged',[Text.UTF8Encoding]::new($false))
 $protected=@{}
 foreach($path in @($config,$backup,$userOwned,$backend)){
  if(!(Test-Path $path)){throw ('PROTECTED_FILE_MISSING_'+$path)}
  $protected[$path]=Hash $path
 }
 $startupBefore=Startup
 $stateBefore=Hash (Join-Path $app 'install_state.json')
 $sourceBefore=Hash (Join-Path $app 'Source\TaskbarGlass.cs')
 $passes+=@('PREEXISTING_OWNERLIKE_DATA_PINNED')
 $phaseNow='STAGE_IN_SEPARATE_CHILD_PROCESS'
 [IO.File]::WriteAllText($childScript,$childText,[Text.UTF8Encoding]::new($false))
 $si=[Diagnostics.ProcessStartInfo]::new()
 $si.FileName=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $si.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$childScript+'" -Setup "'+$currentExe+'" -App "'+$app+'" -Signal "'+$armed+'" -Phase '+$Phase
 $si.UseShellExecute=$false;$si.CreateNoWindow=$true
 $stageProcess=[Diagnostics.Process]::Start($si)
 if(!$stageProcess){throw 'DISPOSABLE_CHILD_NOT_STARTED'}
 $sw=[Diagnostics.Stopwatch]::StartNew()
 while(!(Test-Path $armed) -and $sw.Elapsed.TotalSeconds -lt 60){
  $stageProcess.Refresh()
  if($stageProcess.HasExited){throw ('STAGING_CHILD_FAILED_EARLY_'+$stageProcess.ExitCode)}
  Start-Sleep -Milliseconds 150
 }
 if(!(Test-Path $armed)){throw 'DISPOSABLE_STAGING_CHILD_TIMEOUT'}
 $signal=Get-Content $armed -Raw|ConvertFrom-Json
 if($signal.ChildProcessId -ne $stageProcess.Id -or $signal.Phase -cne $Phase -or $signal.CommittedManagedCount -ne $(if($Phase -eq 'COMMITTING'){2}else{0})){throw 'PARENT_CHILD_SIGNAL_OR_PHASE_MISMATCH'}
 $phaseFile=Join-Path $stage 'phase.txt'
 if(!(Test-Path $phaseFile) -or ((Get-Content $phaseFile -Raw) -cne ('TBME_UPGRADE_R92_OWNED_STAGE_V1|'+$Phase))){throw 'DISPOSABLE_OWNED_JOURNAL_PHASE_WRONG'}
 $partialReplacement=($Phase -eq 'COMMITTING')
 if($partialReplacement -and (Hash (Join-Path $app 'TaskbarMonitorEnhanced.exe')) -cne $main176){throw 'COMMITTING_PREKILL_NOT_NEW_MAIN'}
 if(!$partialReplacement -and (Hash (Join-Path $app 'TaskbarMonitorEnhanced.exe')) -cne $main175){throw 'PREPARED_SHOULD_NOT_TOUCH_MAIN'}
 if((Hash (Join-Path $app 'install_state.json')) -cne $stateBefore){throw 'PARTIAL_STAGE_ALREADY_CHANGED_INSTALLED_VERSION'}
 $passes+=@('STAGED_DURABLE_JOURNAL_EXACT_PHASE')
 $phaseNow='FORCE_TERMINATE_ONLY_NEW_TEST_CHILD_ON_DISPOSABLE'
 $stageProcess.Refresh()
 if($stageProcess.HasExited){throw 'CHILD_ENDED_WITHOUT_EXTERNAL_TERMINATION'}
 $stageProcess.Kill()
 if(!$stageProcess.WaitForExit(15000)){throw 'OWNED_TEST_CHILD_WILL_NOT_TERMINATE'}
 $terminated=$true
 if(!(Test-Path $stage)){throw 'KILL_DESTROYED_EXPECTED_STAGE'}
 $passes+=@('ACTUAL_STAGING_HELPER_PROCESS_ABRUPTLY_KILLED')
 $phaseNow='COLD_NATIVE_SETUP_PROCESS_RECOVERS_JOURNAL_THEN_UPGRADES'
 $result=Run-Exact $currentExe '/update /quiet'
 if($result -ne 0){throw ('NATIVE_UPDATE_DID_NOT_RECOVER_AND_UPGRADE_'+$result)}
 if(Test-Path $stage){throw 'RECOVERY_JOURNAL_NOT_CLEANED'}
 if((Hash (Join-Path $app 'TaskbarMonitorEnhanced.exe')) -cne $main176 -or
    (Hash (Join-Path $app 'Uninstall.exe')) -cne $sha176 -or
    (Get-ItemProperty $uninstall).DisplayVersion -cne '1.7.6'){throw 'FINAL_INSTALLED_RELEASE_IDENTITY_MISMATCH'}
 if((Get-Content (Join-Path $app 'install_state.json') -Raw|ConvertFrom-Json).Version -cne '1.7.6'){throw 'FINAL_STATE_VERSION_NOT_UPDATED'}
 foreach($p in $protected.Keys){if((Hash $p) -cne $protected[$p]){throw ('PROTECTED_USER_DATA_CHANGED_'+[IO.Path]::GetFileName($p))}}
 if((Startup) -cne $startupBefore){throw 'USER_STARTUP_PREFERENCE_CHANGED'}
 if((Test-Path (Join-Path $app 'Docs\RELEASE_NOTES_v1.7.5.md')) -or !(Test-Path (Join-Path $app 'Docs\RELEASE_NOTES_v1.7.6.md'))){throw 'OLD_NOTES_SURVIVED_NEW_NOTES_MISSING'}
 if(@(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count){throw 'PRODUCT_PROCESS_LEFT_RUNNING'}
 $duplicates=@(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'|Where-Object PSChildName -ceq 'TaskbarMonitorEnhanced')
 if($duplicates.Count -ne 1 -or (Get-ItemProperty $uninstall).InstallLocation -cne $app){throw 'DUPLICATE_INSTALL_ROOT_OR_REGISTRATION'}
 $passes+=@('REAL_NATIVE_176_SETUP_AUTOMATICALLY_RECOVERED_KILLED_HELPER_JOURNAL','PRIVATE_DATA_AND_SINGLE_ROOT_PRESERVED')
 $phaseNow='FINAL_ACCEPTANCE'
 $accepted=[ordered]@{
  Schema=1;Revision='R282';Status='PASS_DISPOSABLE_CHILD_KILLED_THEN_OFFICIAL_INSTALLER_AUTO_RECOVERED'
  SourceBranchCommit=$env:GITHUB_SHA;ExactOriginalReleaseSource=$releaseHead
  Official175SetupSHA256=$sha175;Official176SetupSHA256=$sha176
  Official175MainSHA256=$main175;Official176MainSHA256=$main176
  Official175ManagedFixtureRowsExact=22;OriginalOfficial175InstallerFreshInstallPerformed=$false
  HistoricalV175FilesExtractedFromPinnedPublishedInstallerResources=$true
  PrivilegedSensorDriverInstallPerformedForTest=$false
  HostLabel=$HostLabel;Scenario=$Phase;WindowStagedAndOwned=$true
  StagingHelperExternalProcessKilled=$terminated
  ActualSetupExecutableProcessKilled=$false;RealPhysicalMainsCut=$false
  PhaseAtTermination=$Phase;ManagedComponentsPartiallyReplacedBeforeKill=$(if($partialReplacement){2}else{0})
  ProductionVersionedSetupReinvokedInFreshProcess=$true
  NativeSetupAutomaticJournalRecoveryAndInPlaceUpgrade=$true
  ExactProtectedUserDataSHA256Preserved=$true;SingleCanonicalUserRoot=$true
  NoOriginalOwnerPcTouched=$true;NoNonTestProcessTerminated=$true
  RecoveryJournalRemoved=$true;OriginalProcessWasIsolatedTestHelper=$true
  ReceiptEvidenceGate=$passes;RecordedUtc=[DateTime]::UtcNow.ToString('o')
 }
 [IO.File]::WriteAllText($receipt,($accepted|ConvertTo-Json -Depth 9),[Text.UTF8Encoding]::new($false))
 $receiptWritten=$true
 Write-Output ('TBME_R282_ABRUPT_PROCESS_RECOVERY=PASS HOST='+$HostLabel+' PHASE='+$Phase)
}catch{
 $reason=$_.Exception.ToString()
 Write-Output ('TBME_R282_PHASE_FAILED='+$phaseNow+' ERROR='+$reason)
 throw
}finally{
 if($stageProcess){
  try{
   $stageProcess.Refresh()
   if(!$stageProcess.HasExited -and $env:GITHUB_ACTIONS -ceq 'true' -and $env:RUNNER_ENVIRONMENT -ceq 'github-hosted'){
    # This is ONLY the known disposable helper created by this script.
    $stageProcess.Kill()
    [void]$stageProcess.WaitForExit(10000)
   }
  }finally{$stageProcess.Dispose()}
 }
 if(-not $receiptWritten){
  $failed=[ordered]@{Schema=1;Revision='R282';Status='FAIL';Host=$HostLabel;Scenario=$Phase
   Phase=$phaseNow;Reason=$reason;TestHelperKilled=$terminated;OriginalOwnerPcTouched=$false;
   CurrentUtc=[DateTime]::UtcNow.ToString('o')}
  [IO.File]::WriteAllText($receipt,($failed|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
 }
}
if($LASTEXITCODE -ne 0){throw 'R282_RECEIPT_HAS_FAILURE'}
