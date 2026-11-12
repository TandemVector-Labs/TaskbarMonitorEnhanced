[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OfficialSetup)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# HARD HOST GATE: NEVER run an in-place update on a real owner/user device.
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'GOD13emad/TaskbarMonitorEnhanced' -or
   $env:GITHUB_RUN_ID -cnotmatch '^[0-9]{5,20}$' -or
   $env:GITHUB_SHA -cnotmatch '^[a-f0-9]{40}$' -or
   $env:COMPUTERNAME -match '(?i)EMAD|ALIEMAD|SAEID|LAPTOP'){
 throw 'R299_REFUSE_NONDISPOSABLE_OR_UNPINNED_WINDOWS_RUNNER'
}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if((git -C $root rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){throw 'R299_REFUSE_NONEXACT_COMMIT'}
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$expectedLocal=Join-Path ([Environment]::GetFolderPath('UserProfile')) 'AppData/Local'
if(-not [string]::Equals([IO.Path]::GetFullPath((Split-Path $app)),
 [IO.Path]::GetFullPath($expectedLocal),[StringComparison]::OrdinalIgnoreCase)){
 throw 'R299_NONCANONICAL_OWNER_LOCALAPPDATA'
}
$uninstallKey='Software\Microsoft\Windows\CurrentVersion\Uninstall\TaskbarMonitorEnhanced'
$runKey='Software\Microsoft\Windows\CurrentVersion\Run'
$startupName='TaskbarMonitorEnhanced'
if([IO.Directory]::Exists($app) -or
   [IO.Directory]::Exists((Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'TaskbarMonitorEnhanced')) -or
   @(Get-Process TaskbarMonitorEnhanced,TaskbarMonitorSensorBroker,TaskbarMonitorSensorSupervisor -ErrorAction SilentlyContinue).Count -gt 0 -or
   (Get-ScheduledTask -TaskName 'TaskbarMonitorEnhanced Sensor Broker' -ErrorAction SilentlyContinue) -or
   [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($uninstallKey,$false)){
 throw 'R299_REFUSE_PREEXISTING_PRODUCT_OR_SENSOR'
}
$run=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($runKey,$false)
try{
 if($run -and $null -ne $run.GetValue($startupName,$null)){throw 'R299_REFUSE_PREEXISTING_AUTORUN'}
}finally{if($run){$run.Dispose()}}
$official=[IO.Path]::GetFullPath($OfficialSetup)
$publicSha='3AE5E2AC7428C3443FF7768C543117AF864E7C73F68D32EFAD4AB40B30FB5B0E'
if(!(Test-Path $official -PathType Leaf) -or
   (Get-Item $official).Length -ne 8577536 -or
   (Get-FileHash $official -Algorithm SHA256).Hash -cne $publicSha){
 throw 'R299_REJECT_UNVERIFIED_PUBLIC_179_SETUP'
}
$newSetup=Join-Path $root 'build/_out/Setup/TaskbarMonitorEnhanced_Setup_1.7.10.exe'
$buildManifest=Get-Content (Join-Path $root 'artifacts/BUILD_MANIFEST.json') -Raw | ConvertFrom-Json
if($buildManifest.Version -cne '1.7.10'){throw 'R299_WRONG_BUILD_VERSION'}
$expectedNew=@($buildManifest.Outputs|Where-Object Name -eq 'TaskbarMonitorEnhanced_Setup_1.7.10.exe')
$expectedMain=@($buildManifest.Outputs|Where-Object Name -eq 'TaskbarMonitorEnhanced.exe')
if($expectedNew.Count -ne 1 -or $expectedMain.Count -ne 1 -or
   (Get-FileHash $newSetup -Algorithm SHA256).Hash -cne $expectedNew[0].SHA256 -or
   (Get-Item $newSetup).Length -ne $expectedNew[0].Bytes){
 throw 'R299_CANDIDATE_SETUP_NOT_SAME_BUILT_ARTIFACT'
}
# Build all prior managed files from SHA-verified public PE resources, not
# from the runner's mutable workspace or a user's installation.
$old=[Reflection.Assembly]::LoadFrom($official)
$maps=@(
 @('TaskbarMonitorEnhanced.exe','Payload.TaskbarMonitorEnhanced.exe'),
 @('TaskbarMonitorEnhanced.exe.config','Payload.TaskbarMonitorEnhanced.exe.config'),
 @('TaskbarMonitorEnhanced.ico','Payload.TaskbarMonitorEnhanced.ico'),
 @('Source/TaskbarMonitorEnhanced.cs','Payload.TaskbarMonitorEnhanced.cs'),
 @('Source/StudioThemes.cs','Payload.StudioThemes.cs'),
 @('Source/WallpaperStudio.cs','Payload.WallpaperStudio.cs'),
 @('Source/TaskbarGlass.cs','Payload.TaskbarGlass.cs'),
 @('Source/WorkspaceModels.cs','Payload.WorkspaceModels.cs'),
 @('Source/MonitorWorkspace.cs','Payload.MonitorWorkspace.cs'),
 @('Source/WorkspaceSelfTest.cs','Payload.WorkspaceSelfTest.cs'),
 @('Source/TaskbarMonitorSensorBroker.cs','Payload.TaskbarMonitorSensorBroker.cs'),
 @('Source/TaskbarMonitorSensorSupervisor.cs','Payload.TaskbarMonitorSensorSupervisor.cs'),
 @('Source/TaskbarMonitorEnhanced_Setup.cs','Payload.TaskbarMonitorEnhanced_Setup.cs'),
 @('Docs/LICENSE','Payload.LICENSE'),
 @('Docs/README.md','Payload.README.md'),
 @('Docs/AUTHORS.md','Payload.AUTHORS.md'),
 @('Docs/COPYRIGHT_AND_ATTRIBUTION.md','Payload.COPYRIGHT_AND_ATTRIBUTION.md'),
 @('Docs/AI_ASSISTED_DEVELOPMENT.md','Payload.AI_ASSISTED_DEVELOPMENT.md'),
 @('Docs/THIRD_PARTY_NOTICES.md','Payload.THIRD_PARTY_NOTICES.md'),
 @('Docs/RELEASE_NOTES_v1.7.9.md','Payload.RELEASE_NOTES_v1.7.9.md'),
 @('Docs/UPSTREAM_REFERENCE_GPL_NOTICE.md','Payload.UPSTREAM_REFERENCE_GPL_NOTICE.md')
)
if($maps.Count -ne 21){throw 'R299_UNEXPECTED_PREDECESSOR_MAP_COUNT'}
$assembly=[Reflection.Assembly]::LoadFrom($newSetup)
$typ=$assembly.GetType('SetupProgram',$true)
$private=$typ.GetMethod('LegacyExpected',[Reflection.BindingFlags]'NonPublic,Static')
$args=[object[]]::new(2);$args[0]=[string]'1.7.9';$args[1]=[string]'OFFICIAL_STABLE_V179'
$pins=$private.Invoke($null,$args)
if($pins.Count -ne 22 -or $pins['Uninstall.exe'] -cne $publicSha){
 throw 'R299_PUBLIC_PREDECESSOR_PINS_MISMATCH'
}
$canaryRoot=Join-Path $env:RUNNER_TEMP ('R299_OUTSIDE_CANARY_'+$env:GITHUB_RUN_ID)
if(Test-Path $canaryRoot){throw 'R299_CANARY_ALREADY_EXISTS'}
[IO.Directory]::CreateDirectory($canaryRoot)|Out-Null
$canaryFile=Join-Path $canaryRoot 'never-delete-user-data.txt'
[IO.File]::WriteAllText($canaryFile,'R299 external immutable canary')
$canarySHA=(Get-FileHash $canaryFile -Algorithm SHA256).Hash
[IO.Directory]::CreateDirectory($app)|Out-Null
foreach($map in $maps){
 $rel=[string]$map[0];$payload=[string]$map[1]
 $path=Join-Path $app $rel
 $stream=$old.GetManifestResourceStream($payload)
 if(!$stream){throw ('R299_OFFICIAL_EMBEDDED_RESOURCE_ABSENT_'+$payload)}
 try{
  $memory=New-Object IO.MemoryStream
  try{$stream.CopyTo($memory);$bytes=$memory.ToArray()}finally{$memory.Dispose()}
 }finally{$stream.Dispose()}
 [IO.Directory]::CreateDirectory((Split-Path $path))|Out-Null
 [IO.File]::WriteAllBytes($path,$bytes)
 if((Get-FileHash $path -Algorithm SHA256).Hash -cne [string]$pins[$rel]){throw ('R299_OLD_SOURCE_RESOURCE_HASH_MISMATCH_'+$rel)}
}
[IO.File]::Copy($official,(Join-Path $app 'Uninstall.exe'),$false)
if((Get-FileHash (Join-Path $app 'Uninstall.exe')).Hash -cne $publicSha){throw 'R299_BAD_FIXTURE_UNINSTALL_SETUP'}
$state=Join-Path $app 'install_state.json'
$previousState='{"Version":"1.7.9","PublicVersion":"1.7.9","ProductIdentity":"LOCKED","SensorLayerStatus":"READY","SensorLayerMode":"CURRENT_EXACT_R33","UserCanary":"preserve"}'
[IO.File]::WriteAllText($state,$previousState,[Text.UTF8Encoding]::new($false))
$config=Join-Path $app 'config.json'
$configBak=Join-Path $app 'config.json.bak'
$sensorState=Join-Path $app 'sensor_backend_state.json'
foreach($item in @(
 @{path=$config;text='{"userPreference":"R299-preserve","customWidth":1041}'},
 @{path=$configBak;text='{"backupPreference":"R299-preserve"}'},
 @{path=$sensorState;text='{"status":"R299-guest-fixture"}'}
 )){
 [IO.File]::WriteAllText($item.path,$item.text,[Text.UTF8Encoding]::new($false))
}
$backend=Join-Path $app 'SensorBackend/LibreHardwareMonitor-0.9.6/LibreHardwareMonitorLib.dll'
[IO.Directory]::CreateDirectory((Split-Path $backend))|Out-Null
[IO.File]::WriteAllBytes($backend,[Text.Encoding]::UTF8.GetBytes('R299_SYNTHETIC_BACKEND_PRESERVATION_PROBE'))
$keep=@{}
foreach($x in @($config,$configBak,$sensorState,$backend,$canaryFile)){$keep[$x]=(Get-FileHash $x -Algorithm SHA256).Hash}
$uninstall=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($uninstallKey)
try{
 $uninstall.SetValue('DisplayName','Taskbar Monitor Enhanced')
 $uninstall.SetValue('DisplayVersion','1.7.9')
 $uninstall.SetValue('InstallLocation',$app)
}finally{$uninstall.Dispose()}
$run=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($runKey)
try{$startup='"'+(Join-Path $app 'TaskbarMonitorEnhanced.exe')+'" --startup';$run.SetValue($startupName,$startup)}
finally{$run.Dispose()}
function AssertUnaffected {
 foreach($x in $keep.Keys){
  if(!(Test-Path $x) -or (Get-FileHash $x -Algorithm SHA256).Hash -cne $keep[$x]){
   throw ('R299_OWNER_OR_EXTERNAL_CANARY_CHANGED_'+$x)
  }
 }
 $run=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($runKey,$false)
 try{if($run.GetValue($startupName) -cne $startup){throw 'R299_STARTUP_PREFERENCE_CHANGED'}}finally{$run.Dispose()}
}
function InvokeCandidateUpdate {
 $p=[Diagnostics.ProcessStartInfo]::new()
 $p.FileName=$newSetup
 $p.Arguments='/update /quiet'
 $p.WorkingDirectory=$env:RUNNER_TEMP
 $p.UseShellExecute=$false
 $p.CreateNoWindow=$true
 $child=[Diagnostics.Process]::Start($p)
 if(!$child){throw 'R299_UPDATE_PROCESS_NOT_CREATED'}
 try{
  if(!$child.WaitForExit(150000)){
   try{$child.Kill();$child.WaitForExit(8000)|Out-Null}catch{}
   throw 'R299_UPDATE_PROCESS_TIMEOUT'
  }
  return [int]$child.ExitCode
 }finally{$child.Dispose()}
}
# Negative preflight: one deliberately tampered managed file must abort
# before a single managed byte, registry value or user preference changes.
$tamper=Join-Path $app 'Source/StudioThemes.cs'
[IO.File]::AppendAllText($tamper,'R299_TAMPER_PROBE')
$stateBefore=(Get-FileHash $state).Hash
$mainBefore=(Get-FileHash (Join-Path $app 'TaskbarMonitorEnhanced.exe')).Hash
$code=InvokeCandidateUpdate
if($code -ne 34){throw ('R299_TAMPERED_PREDECESSOR_NOT_REFUSED_EXIT_'+$code)}
if((Get-FileHash $state).Hash -cne $stateBefore -or
   (Get-FileHash (Join-Path $app 'TaskbarMonitorEnhanced.exe')).Hash -cne $mainBefore){
 throw 'R299_TAMPER_REFUSAL_MODIFIED_MANAGED_PRODUCT'
}
$reg=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($uninstallKey,$false)
try{if($reg.GetValue('DisplayVersion') -cne '1.7.9'){throw 'R299_TAMPER_CHANGED_VERSION_REGISTRY'}}
finally{$reg.Dispose()}
AssertUnaffected
if(@(Get-ChildItem $app -Directory -Force|Where-Object {$_.Name -match '(?i)upgrade|\\.tbme'}).Count){
 throw 'R299_TAMPER_LEFT_TRANSACTION_STAGE'
}
'R299_HOSTED_TAMPERED_OFFICIAL_PREDECESSOR_REFUSED_BEFORE_MUTATION=PASS'
# Restore only this test's exact tampered file with its SHA-pinned PE
# resource, then run the actual original compiled product /update path.
$stream=$old.GetManifestResourceStream('Payload.StudioThemes.cs')
if(!$stream){throw 'R299_CANNOT_RESTORE_SYNTHETIC_TAMPER'}
try{
 $memory=New-Object IO.MemoryStream
 try{$stream.CopyTo($memory);[IO.File]::WriteAllBytes($tamper,$memory.ToArray())}finally{$memory.Dispose()}
}finally{$stream.Dispose()}
if((Get-FileHash $tamper).Hash -cne [string]$pins['Source/StudioThemes.cs']){throw 'R299_TAMPER_RESTORE_NOT_EXACT'}
# R299 independent abrupt mid-commit simulation: trusted child stages the
# exact candidate resources, physically replaces two synthetic managed
# files and writes an owned COMMITTING marker. The parent terminates ONLY
# that exact test-owned child, and the REAL candidate Setup must recover.
$childScript=Join-Path $PSScriptRoot 'Test-R299-HostedCrashChild.ps1'
$signal=Join-Path $env:RUNNER_TEMP ('R299_ABRUPT_COMMITTING_ARMED_'+$env:GITHUB_RUN_ID+'.json')
if(!(Test-Path $childScript) -or (Test-Path $signal) -or (Test-Path ($signal+'.error.txt'))){
 throw 'R299_CRASH_FIXTURE_SOURCE_OR_SIGNAL_NOT_FRESH'
}
$trustedPowerShell=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell/v1.0/powershell.exe'
if(!(Test-Path $trustedPowerShell)){throw 'R299_CRASH_CHILD_HOST_UNAVAILABLE'}
$psi=[Diagnostics.ProcessStartInfo]::new()
$psi.FileName=$trustedPowerShell
$psi.WorkingDirectory=$env:RUNNER_TEMP
$psi.UseShellExecute=$false
$psi.CreateNoWindow=$true
$psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$childScript+
  '" -CandidateSetup "'+$newSetup+'" -App "'+$app+'" -Signal "'+$signal+
  '" -ExpectedSetupSha '+[string]$expectedNew[0].SHA256+
  ' -ExpectedPriorSetupSha '+$publicSha+
  ' -ExpectedPriorMainSha 04776E870A492733BBA33A550F732F5DB688A6585FC6533224A56687F1A6D88E'+
  ' -ExpectedNewMainSha '+[string]$expectedMain[0].SHA256
$crashChild=[Diagnostics.Process]::Start($psi)
if(!$crashChild){throw 'R299_OWNED_CRASH_CHILD_NOT_STARTED'}
try{
 $armed=$false
 for($probe=0;$probe -lt 130;$probe++){
  if(Test-Path $signal){$armed=$true;break}
  if($crashChild.HasExited){break}
  Start-Sleep -Milliseconds 150
 }
 if(!$armed){
  $childError=if(Test-Path ($signal+'.error.txt')){Get-Content ($signal+'.error.txt') -Raw}else{'child did not produce arm signal'}
  throw ('R299_CRASH_CHILD_DID_NOT_ARM_'+$childError.Substring(0,[Math]::Min(680,$childError.Length)))
 }
 $record=Get-Content $signal -Raw|ConvertFrom-Json
 if($record.Pid -ne $crashChild.Id -or
    $record.Phase -cne 'COMMITTING' -or
    $record.ChangedFiles -ne 2 -or
    $record.GitSha -cne $env:GITHUB_SHA){
  throw 'R299_CRASH_ARMED_PROCESS_OR_SOURCE_IDENTITY_WRONG'
 }
 $stageRoot=Join-Path $app '.tbme-upgrade'
 $phasePath=Join-Path $stageRoot 'phase.txt'
 if(!(Test-Path $phasePath) -or
    (Get-Content $phasePath -Raw) -cnotmatch 'TBME_UPGRADE_R92_OWNED_STAGE_V1\|COMMITTING$' -or
    (Get-FileHash (Join-Path $app 'TaskbarMonitorEnhanced.exe')).Hash -cne [string]$expectedMain[0].SHA256 -or
    (Get-FileHash (Join-Path $app 'Uninstall.exe')).Hash -cne $publicSha -or
    (Get-FileHash $state).Hash -cne $stateBefore){
  throw 'R299_CRASH_PARTIAL_COMMIT_NOT_PHYSICALLY_PROVEN'
 }
 AssertUnaffected
 $crashChild.Kill()
 if(!$crashChild.WaitForExit(12000)){throw 'R299_OWNED_CRASH_CHILD_REFUSES_TERMINATION'}
 if(!(Test-Path $stageRoot)){throw 'R299_JOURNAL_DISAPPEARED_BEFORE_NATIVE_RECOVERY'}
}finally{
 try{if(!$crashChild.HasExited){$crashChild.Kill();$crashChild.WaitForExit(12000)|Out-Null}}catch{}
 $crashChild.Dispose()
}
# The first genuine binary update below must replay the interrupted
# COMMITTING stage to the official predecessor, then perform the upgrade.
$code=InvokeCandidateUpdate
if($code -ne 0){throw ('R299_OFFICIAL_179_TO_1710_REAL_SETUP_UPDATE_FAILED_EXIT_'+$code)}
if(!(Test-Path (Join-Path $app 'TaskbarMonitorEnhanced.exe')) -or
   (Get-FileHash (Join-Path $app 'TaskbarMonitorEnhanced.exe')).Hash -cne $expectedMain[0].SHA256 -or
   (Get-FileHash (Join-Path $app 'Uninstall.exe')).Hash -cne $expectedNew[0].SHA256){
 throw 'R299_POSTUPDATE_PROGRAM_BINARY_NOT_EXACT_BUILD'
}
$stateAfter=Get-Content $state -Raw|ConvertFrom-Json
if($stateAfter.Version -cne '1.7.10' -or
   $stateAfter.PublicVersion -cne '1.7.10' -or
   $stateAfter.UserCanary -cne 'preserve'){
 throw 'R299_ACTUAL_UPDATED_INSTALL_STATE_UNACCEPTED'
}
if(!(Test-Path (Join-Path $app 'Docs/RELEASE_NOTES_v1.7.10.md')) -or
   (Test-Path (Join-Path $app 'Docs/RELEASE_NOTES_v1.7.9.md'))){
 throw 'R299_RELEASE_NOTES_UPGRADE_TRANSACTION_WRONG'
}
$reg=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($uninstallKey,$false)
try{if($reg.GetValue('DisplayVersion') -cne '1.7.10'){throw 'R299_INSTALLATION_REGISTRY_NOT_UPDATED'}}
finally{$reg.Dispose()}
AssertUnaffected
if(Test-Path (Join-Path $app '.tbme-upgrade')){throw 'R299_CRASH_RECOVERY_LEFT_TRANSACTION_STAGE'}
'R299_HOSTED_ABRUPT_TWO_FILE_COMMITTING_RECOVERED_BY_REAL_SETUP=PASS'
'R299_HOSTED_ORIGINAL_SETUP_OFFICIAL_179_TO_1710_INPLACE_UPGRADE=PASS'
'R299_HOSTED_CONFIG_SENSOR_REGISTRY_AND_OUTSIDE_CANARIES_PRESERVED=PASS'
# Exact v1.7.10 re-invocation must be byte-idempotent (no second root).
$mainAfter=(Get-FileHash (Join-Path $app 'TaskbarMonitorEnhanced.exe')).Hash
$setupAfter=(Get-FileHash (Join-Path $app 'Uninstall.exe')).Hash
$stateHashAfter=(Get-FileHash $state).Hash
$code=InvokeCandidateUpdate
if($code -ne 0 -or
   (Get-FileHash (Join-Path $app 'TaskbarMonitorEnhanced.exe')).Hash -cne $mainAfter -or
   (Get-FileHash (Join-Path $app 'Uninstall.exe')).Hash -cne $setupAfter -or
   (Get-FileHash $state).Hash -cne $stateHashAfter){
 throw 'R299_SECOND_UPDATE_NOT_EXACT_IDEMPOTENT'
}
AssertUnaffected
'R299_HOSTED_EXACT_SECOND_UPDATE_IDEMPOTENT=PASS'
# Preserve a deterministic compact receipt, never emit user data.
$receipt=[ordered]@{
 Status='PASS_ORIGINAL_PUBLIC_V179_TO_V1710_REAL_SETUP_UPDATE'
 GitSha=$env:GITHUB_SHA
 PublishedSetupSHA256=$publicSha
 CandidateSetupSHA256=[string]$expectedNew[0].SHA256
 CandidateMainSHA256=[string]$expectedMain[0].SHA256
 ImmutableManagedPredecessorFiles=22
 TamperedPredecessorRejected=$true
 InPlaceUpgradePassed=$true
 InterruptedCommitRecovered=$true
 UpgradePreservedUserCanaries=$true
 ExactSecondUpdateIdempotent=$true
 PersonalDeviceWasNotUsed=$true
 Utc=[DateTime]::UtcNow.ToString('o')
}
$receiptPath=Join-Path $env:RUNNER_TEMP 'R299_PUBLIC179_HOSTED_UPGRADE_RECEIPT.json'
if(Test-Path $receiptPath){throw 'R299_RECEIPT_EXISTS'}
[IO.File]::WriteAllText($receiptPath,($receipt|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
'R299_HOSTED_PUBLIC_V179_UPGRADE_RECEIPT=PASS'
