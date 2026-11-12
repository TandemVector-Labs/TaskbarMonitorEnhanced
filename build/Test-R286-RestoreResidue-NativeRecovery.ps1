[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$CandidateDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Never execute an installer or kill a process on a personal/shared computer.
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or
   ![Environment]::UserInteractive){throw 'R286_ONLY_NEW_DISPOSABLE_GITHUB_WINDOWS_VM_ALLOWED'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -TypeDefinition 'using System.IO; public static class R286Bridge { public static void ReplaceNoBackup(string src,string dest) { File.Replace(src,dest,null); } }'
$repo='GOD13emad/TaskbarMonitorEnhanced'
$published177='395AEE56006F55FD5DCCFB52E1519088CE01A10386840D7008C6BA900136A06D'
$publishedMain177='A6D4BFD00C918C0601A12D185F414E92F2B6A85927042B811537B0BC37606253'
$libSha='6EBC194316536BA61AF5BE24508AD9FCBB2ECC685E716C12E787C79530F66BF0'
$app=Join-Path $env:LOCALAPPDATA 'TaskbarMonitorEnhanced'
$uninstall='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TaskbarMonitorEnhanced'
$stage=Join-Path $app '.tbme-upgrade'
$out=Join-Path $env:RUNNER_TEMP ('R286_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$report=Join-Path $out 'R286_RECOVERY_RECEIPT.json'
$arm=Join-Path $out 'ARMED.json'
$childFile=Join-Path $out 'StageChild.ps1'
$predecessor=Join-Path $out 'TaskbarMonitorEnhanced_Setup_1.7.7.exe'
$candidate=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$candidateMain=Join-Path $CandidateDir 'App\TaskbarMonitorEnhanced.exe'
$candidateManifest=Join-Path $CandidateDir 'CANDIDATE.json'
$prevFixture=Join-Path $PSScriptRoot 'official-v177-managed.json'
$native=$null;$child=$null;$watcher=$null
$nativeWasKilled=$false;$documentWitness=$false;$residueInjected=$false
$phaseNow='INITIAL';$reason='';$accepted=$false
$gates=[Collections.Generic.List[string]]::new()
function Hash([string]$path){
 if(Test-Path -LiteralPath $path -PathType Leaf){return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
 return 'MISSING'
}
function ProcessCount(){return @(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count}
function StartupValue(){
 $key=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
 if($null -eq $key){return 'MISSING'}
 $p=$key.PSObject.Properties['TaskbarMonitorEnhanced']
 return $(if($null -eq $p){'MISSING'}else{[string]$p.Value})
}
function Run-Official([string]$exe,[string]$arguments){
 if($arguments -cne '/update /quiet'){throw 'R286_TEST_REFUSES_WRONG_ARGUMENTS'}
 $si=[Diagnostics.ProcessStartInfo]::new()
 $si.FileName=$exe;$si.Arguments=$arguments;$si.UseShellExecute=$false
 $si.WorkingDirectory=(Split-Path $exe -Parent)
 $p=[Diagnostics.Process]::Start($si)
 if(!$p){throw 'R286_SETUP_NOT_LAUNCHED'}
 try{
  if(!$p.WaitForExit(150000)){
   $p.Refresh()
   if(!$p.HasExited){$p.Kill();[void]$p.WaitForExit(14000)}
   throw 'R286_NATIVE_SETUP_TIMEOUT_ONLY_TEST_PROCESS_STOPPED'
  }
  return [int]$p.ExitCode
 }finally{$p.Dispose()}
}
if((Test-Path $app) -or (Test-Path $uninstall) -or
   (Test-Path $out) -or (ProcessCount) -ne 0){throw 'R286_GUEST_NOT_CLEAN'}
[IO.Directory]::CreateDirectory($out)|Out-Null
try{
 $phaseNow='PIN_CANDIDATE_AND_IMMUTABLE_PREDECESSOR'
 $manifest=Get-Content $candidateManifest -Raw|ConvertFrom-Json
 if($manifest.Commit -cne $env:GITHUB_SHA -or $manifest.Version -cne '1.7.8' -or
    $manifest.Private -ne $true -or $manifest.NotForPublicInstallation -ne $true -or
    (Hash $candidate) -cne $manifest.SetupSHA256 -or
    (Hash $candidateMain) -cne $manifest.MainSHA256){throw 'R286_CANDIDATE_SOURCE_OR_SHA_MISMATCH'}
 $candidateSha=[string]$manifest.SetupSHA256
 $mainSha=[string]$manifest.MainSHA256
 if($candidateSha -cnotmatch '^[A-F0-9]{64}$' -or $mainSha -cnotmatch '^[A-F0-9]{64}$'){throw 'R286_CANDIDATE_BAD_DIGEST'}
 $env:GH_PROMPT_DISABLED='1'
 & gh release download v1.7.7 -R $repo -p TaskbarMonitorEnhanced_Setup_1.7.7.exe -D $out
 if($LASTEXITCODE -ne 0 -or (Hash $predecessor) -cne $published177){throw 'R286_PREVIOUS_OFFICIAL_RELEASE_DOWNLOAD_HASH_FAILED'}
 $pin=Get-Content $prevFixture -Raw|ConvertFrom-Json
 if($pin.Version -cne '1.7.7' -or $pin.ManagedCount -ne 22 -or
    @($pin.Rows).Count -ne 22 -or $pin.PublishedSetupSHA256 -cne $published177 -or
    $pin.PublishedMainSHA256 -cne $publishedMain177){throw 'R286_BAD_PRIOR_MANIFEST'}
 $gates.Add('BOTH_OFFICIAL_AND_PRIVATE_CANDIDATE_ASSET_SHA_VERIFIED')
 $phaseNow='RESTORE_PINNED_V176_GUEST_ROOT_WITHOUT_RUNNING_OLD_SETUP'
 $asm=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($predecessor))
 [IO.Directory]::CreateDirectory($app)|Out-Null
 foreach($row in $pin.Rows){
  $rel=[string]$row.Path
  if(!$rel -or [IO.Path]::IsPathRooted($rel) -or
      $rel -match '(^|[/\\])\.\.([/\\]|$)' -or $rel -match '[:*?"<>|]'){
    throw 'R286_UNSAFE_PRIOR_RESOURCE_PATH'
  }
  $dest=[IO.Path]::GetFullPath((Join-Path $app $rel))
  if(!$dest.StartsWith(([IO.Path]::GetFullPath($app).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){
    throw 'R286_PREDECESSOR_RESOURCE_TRAVERSAL'
  }
  [IO.Directory]::CreateDirectory((Split-Path $dest -Parent))|Out-Null
  if(Test-Path $dest){throw 'R286_DUPLICATE_PREVIOUS_MANAGED_RESOURCE'}
  if($rel -ceq 'Uninstall.exe'){
    [IO.File]::Copy($predecessor,$dest)
  }else{
    $embedded='Payload.'+[IO.Path]::GetFileName($rel)
    $source=$asm.GetManifestResourceStream($embedded)
    if(!$source){throw ('R286_PREVIOUS_EMBEDDED_RESOURCE_MISSING_'+$embedded)}
    try{
     $target=[IO.File]::Open($dest,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
     try{$source.CopyTo($target)}finally{$target.Dispose()}
    }finally{$source.Dispose()}
  }
  if((Hash $dest) -cne $row.SHA256 -or (Get-Item $dest).Length -ne $row.Bytes){
    throw ('R286_PREVIOUS_MANAGED_SHA_OR_LENGTH_WRONG_'+$rel)
  }
 }
 $backendRoot=Join-Path $app 'SensorBackend\LibreHardwareMonitor-0.9.6'
 $lhmArchive=Join-Path $out 'LibreHardwareMonitor-from-official-Setup.zip'
 $stream=$asm.GetManifestResourceStream('Payload.LibreHardwareMonitor.zip')
 if(!$stream){throw 'R286_PRIOR_OFFICIAL_LHM_MISSING'}
 try{
  $dst=[IO.File]::Open($lhmArchive,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$stream.CopyTo($dst)}finally{$dst.Dispose()}
 }finally{$stream.Dispose()}
 [IO.Directory]::CreateDirectory($backendRoot)|Out-Null
 [IO.Compression.ZipFile]::ExtractToDirectory($lhmArchive,$backendRoot)
 if((Hash (Join-Path $backendRoot 'LibreHardwareMonitorLib.dll')) -cne $libSha){throw 'R286_LIBRARY_SHA_MISMATCH'}
 $stateJson='{"App":"Taskbar Monitor Enhanced","Version":"1.7.7","PublicVersion":"1.7.7","ProductIdentity":"LOCKED","SensorLayerStatus":"READY","SensorLayerMode":"R286_PRIVATE_PINNED_FIXTURE","SensorLayerVersion":"0.9.6","R286Fixture":true}'
 [IO.File]::WriteAllText((Join-Path $app 'install_state.json'),$stateJson,[Text.UTF8Encoding]::new($false))
 $reg=New-Item -Path $uninstall -Force -ErrorAction Stop
 Set-ItemProperty -Path $uninstall -Name DisplayName -Value 'Taskbar Monitor Enhanced'
 Set-ItemProperty -Path $uninstall -Name DisplayVersion -Value '1.7.7'
 Set-ItemProperty -Path $uninstall -Name InstallLocation -Value $app
 $reg.Dispose()
 if((Hash (Join-Path $app 'TaskbarMonitorEnhanced.exe')) -cne $publishedMain177 -or
    (Hash (Join-Path $app 'Uninstall.exe')) -cne $published177 -or
    (ProcessCount) -ne 0){throw 'R286_PINNED_PREDECESSOR_NOT_VALID'}
 $protected=@{}
 $config=Join-Path $app 'config.json'
 $backup=Join-Path $app 'config.json.bak'
 $canary=Join-Path $app 'R286_PRIVATE_USER_CANARY.txt'
 [IO.File]::WriteAllText($config,'{"Theme":"Retro Terminal","GlassMode":true,"Opacity":0,"EnableTemperatureAlerts":true,"EnableTemperatureNotifications":true,"R286":"PRESERVE"}',[Text.UTF8Encoding]::new($false))
 [IO.File]::WriteAllText($backup,'{"BackupCanary":"R286_PROTECTED"}',[Text.UTF8Encoding]::new($false))
 [IO.File]::WriteAllText($canary,'Only disposable R286 user content',[Text.UTF8Encoding]::new($false))
 foreach($p in @($config,$backup,$canary,(Join-Path $backendRoot 'LibreHardwareMonitorLib.dll'))){$protected[$p]=Hash $p}
 $startup=StartupValue
 $gates.Add('22_SHA_PINNED_PREDECESSOR_ROWS_AND_PROTECTED_SETTINGS')
 $phaseNow='EXACT_CANDIDATE_STAGE_HELPER'
 $childText=@'
param([string]$Setup,[string]$App,[string]$Signal)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or $env:RUNNER_OS -cne 'Windows'){throw 'R286_CHILD_REFUSES_NONHOSTED'}
if((Get-FileHash $Setup).Hash -cne $env:R286_CANDIDATE_SETUP_SHA){throw 'R286_CHILD_CANDIDATE_SHA_DRIFT'}
if((Get-FileHash (Join-Path $App 'TaskbarMonitorEnhanced.exe')).Hash -cne 'A6D4BFD00C918C0601A12D185F414E92F2B6A85927042B811537B0BC37606253'){throw 'R286_CHILD_PREVIOUS_SHA_DRIFT'}
if(Test-Path (Join-Path $App '.tbme-upgrade')){throw 'R286_CHILD_STAGE_ALREADY_EXISTS'}
Add-Type -TypeDefinition 'using System.IO; public static class R286FileSwap { public static void ReplaceOne(string a,string b){File.Replace(a,b,null);} }'
$assembly=[Reflection.Assembly]::LoadFrom($Setup)
$type=$assembly.GetType('SetupProgram',$true)
$f=[Reflection.BindingFlags]'Static,NonPublic,Public'
$old='1.7.7';$channel='OFFICIAL_STABLE_V177'
$prior=[IO.File]::ReadAllText((Join-Path $App 'install_state.json'))
$legacy=$type.GetMethod('LegacyExpected',$f).Invoke($null,[object[]]@($old,$channel))
$fresh=$type.GetMethod('PrepareNewBytes',$f).Invoke($null,[object[]]@($prior))
$fresh['Uninstall.exe']=[IO.File]::ReadAllBytes($Setup)
[void]$type.GetMethod('StageNewManaged',$f).Invoke($null,[object[]]@($fresh,$legacy,$prior,$old,$channel))
[void]$type.GetMethod('WritePhase',$f).Invoke($null,[object[]]@('COMMITTING'))
$stage=Join-Path $App '.tbme-upgrade\new'
$mainLive=Join-Path $App 'TaskbarMonitorEnhanced.exe'
[R286FileSwap]::ReplaceOne((Join-Path $stage 'TaskbarMonitorEnhanced.exe'),$mainLive)
$note='Docs/RELEASE_NOTES_v1.7.8.md'
$live=Join-Path $App $note
if(Test-Path $live){throw 'NEW_NOTE_ALREADY_EXISTS'}
[IO.File]::Move((Join-Path $stage $note),$live)
if((Get-FileHash $mainLive).Hash -cne $env:R286_CANDIDATE_MAIN_SHA){throw 'R286_PARTIAL_CANDIDATE_MAIN_NOT_PRESENT'}
[IO.File]::WriteAllText($Signal,([ordered]@{ChildPid=$PID;Phase='COMMITTING';ReplacedManagedCount=2;Utc=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
while($true){Start-Sleep -Seconds 2}
'@
 [IO.File]::WriteAllText($childFile,$childText,[Text.UTF8Encoding]::new($false))
 $env:R286_CANDIDATE_SETUP_SHA=$candidateSha
 $env:R286_CANDIDATE_MAIN_SHA=$mainSha
 $si=[Diagnostics.ProcessStartInfo]::new()
 $si.FileName=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $si.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$childFile+'" -Setup "'+$candidate+'" -App "'+$app+'" -Signal "'+$arm+'"'
 $si.UseShellExecute=$false;$si.CreateNoWindow=$true
 $child=[Diagnostics.Process]::Start($si)
 if(!$child){throw 'R286_CHILD_NOT_STARTED'}
 $clock=[Diagnostics.Stopwatch]::StartNew()
 while(!(Test-Path $arm) -and $clock.Elapsed.TotalSeconds -lt 55){
  $child.Refresh()
  if($child.HasExited){throw ('R286_CHILD_FAIL_EXIT_'+$child.ExitCode)}
  Start-Sleep -Milliseconds 75
 }
 if(!(Test-Path $arm)){throw 'R286_CHILD_DID_NOT_ARM'}
 $message=Get-Content $arm -Raw|ConvertFrom-Json
 if($message.ChildPid -ne $child.Id -or $message.Phase -cne 'COMMITTING' -or $message.ReplacedManagedCount -ne 2){throw 'R286_ARMED_INVALID'}
 $phase=Join-Path $stage 'phase.txt'
 $currentNote=Join-Path $app 'Docs\RELEASE_NOTES_v1.7.8.md'
 if((Get-Content $phase -Raw) -cne 'TBME_UPGRADE_R92_OWNED_STAGE_V1|COMMITTING' -or
    (Hash (Join-Path $app 'TaskbarMonitorEnhanced.exe')) -cne $mainSha -or !(Test-Path $currentNote)){
  throw 'R286_STAGE_NOT_PHYSICALLY_PARTIAL'
 }
 $child.Refresh();if($child.HasExited){throw 'R286_CHILD_EXITED_ALREADY'}
 $child.Kill();if(!$child.WaitForExit(13000)){throw 'R286_CHILD_KILL_NOT_COMPLETE'}
 $child.Dispose();$child=$null
 $gates.Add('ACTUAL_ISOLATED_STAGING_HELPER_KILLED_WITH_TWO_MANAGED_REPLACEMENTS')
 $residue=Join-Path $stage 'old\TaskbarMonitorEnhanced.exe.restore'
 if(Test-Path $residue){throw 'R286_STRANDED_RESIDUE_ALREADY_EXISTS'}
 if($HostLabel -ceq 'B'){
  $phaseNow='KILL_ACTUAL_OFFICIAL_CANDIDATE_SETUP_PROCESS_DURING_ROLLBACK'
  $watcher=[IO.FileSystemWatcher]::new((Join-Path $app 'Docs'),'RELEASE_NOTES_v1.7.8.md')
  $watcher.NotifyFilter=[IO.NotifyFilters]'FileName,LastWrite,Size,CreationTime'
  $watcher.EnableRaisingEvents=$true
  $si=[Diagnostics.ProcessStartInfo]::new()
  $si.FileName=$candidate;$si.Arguments='/update /quiet';$si.UseShellExecute=$false;$si.WorkingDirectory=$out
  $native=[Diagnostics.Process]::Start($si)
  if(!$native){throw 'R286_REAL_SETUP_NOT_STARTED'}
  $watchTime=[Diagnostics.Stopwatch]::StartNew()
  while($watchTime.Elapsed.TotalSeconds -lt 40){
   $native.Refresh()
   if($native.HasExited){throw ('R286_SETUP_FINISHED_BEFORE_KILLABLE_ROLLBACK_'+$native.ExitCode)}
   $signal=$watcher.WaitForChanged([IO.WatcherChangeTypes]::All,45)
   if($signal.TimedOut -or (Test-Path $currentNote)){continue}
   if((Hash (Join-Path $app 'TaskbarMonitorEnhanced.exe')) -cne $mainSha -or
      !(Test-Path $phase) -or (Get-Content $phase -Raw) -cne 'TBME_UPGRADE_R92_OWNED_STAGE_V1|COMMITTING'){
     throw 'R286_REAL_ROLLBACK_KILL_WINDOW_WAS_MISSED'
   }
   $native.Refresh();if($native.HasExited){throw 'R286_REAL_SETUP_EXITED_BEFORE_FORCE_TERMINATION'}
   $native.Kill()
   if(!$native.WaitForExit(18000)){throw 'R286_REAL_NATIVE_SETUP_DID_NOT_TERMINATE'}
   $nativeWasKilled=$true;$documentWitness=$true
   break
  }
  if(!$nativeWasKilled){throw 'R286_NO_VALID_REAL_SETUP_PROCESS_KILL_WITNESS'}
  $watcher.EnableRaisingEvents=$false;$watcher.Dispose();$watcher=$null
  $native.Dispose();$native=$null
  if(!(Test-Path $stage) -or (Hash (Join-Path $app 'TaskbarMonitorEnhanced.exe')) -cne $mainSha){throw 'R286_KILL_NOT_LEFT_PARTIAL_STAGE'}
  $gates.Add('REAL_UNMODIFIED_CANDIDATE_SETUP_PROCESS_KILLED_AFTER_DOCUMENT_DELETION')
 }
 $phaseNow='EXACT_KNOWN_OWNER_STAGE_STRANDED_TEMP_RESIDUE'
 if(!(Test-Path $residue)){
  $copy=[IO.File]::Open($residue,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  $copy.Dispose()
  $residueInjected=$true
 }
 if((Get-Item $residue).Length -ne 0 -or
    (Hash (Join-Path $app 'TaskbarMonitorEnhanced.exe')) -cne $mainSha -or
    (Get-Content $phase -Raw) -cne 'TBME_UPGRADE_R92_OWNED_STAGE_V1|COMMITTING'){
   throw 'R286_NOT_A_REPRODUCIBLE_STRANDED_ZERO_BYTE_OLD_MAIN_SCRATCH'
 }
 $gates.Add('ZERO_LENGTH_STRANDED_UPDATER_OWNED_RESTORE_FILE_CONFIRMED')
 $phaseNow='NEW_VERSIONED_OFFICIAL_SETUP_COLD_RECOVERS'
 $result=Run-Official $candidate '/update /quiet'
 if($result -ne 0){throw ('R286_CANDIDATE_FAILED_TO_COLD_RECOVER_'+$result)}
 if(Test-Path $stage){throw 'R286_JOURNAL_NOT_REMOVED'}
 if((Hash (Join-Path $app 'TaskbarMonitorEnhanced.exe')) -cne $mainSha -or
    (Hash (Join-Path $app 'Uninstall.exe')) -cne $candidateSha -or
    (Get-ItemProperty $uninstall).DisplayVersion -cne '1.7.8'){throw 'R286_NEW_INSTALLED_APP_OR_SETUP_HASH_INVALID'}
 $newState=Get-Content (Join-Path $app 'install_state.json') -Raw|ConvertFrom-Json
 if($newState.Version -cne '1.7.8' -or $newState.PublicVersion -cne '1.7.8'){throw 'R286_INSTALLED_PUBLIC_VERSION_INCORRECT'}
 if((Test-Path (Join-Path $app 'Docs\RELEASE_NOTES_v1.7.7.md')) -or !(Test-Path (Join-Path $app 'Docs\RELEASE_NOTES_v1.7.8.md'))){throw 'R286_VERSION_NOTES_UPGRADE_INVALID'}
 foreach($p in $protected.Keys){if((Hash $p) -cne $protected[$p]){throw ('R286_PROTECTED_USER_FILE_CHANGED_'+$p)}}
 if((StartupValue) -cne $startup){throw 'R286_USER_AUTOSTART_PREFERENCE_CHANGED'}
 if((ProcessCount) -ne 0){throw 'R286_MAIN_PROGRAM_UNEXPECTEDLY_LAUNCHED'}
 if(@(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'|Where-Object PSChildName -ceq 'TaskbarMonitorEnhanced').Count -ne 1){throw 'R286_MORE_THAN_ONE_PRODUCT_REGISTRATION'}
 $gates.Add('EXACT_RELEASE_177_MAIN_SETUP_USER_CONFIG_AUTOSTART_ONE_ROOT_JOURNAL_REMOVED')
 $result=[ordered]@{
  Schema=1;Revision='R286';Status='PASS_EXACT_V178_SETUP_RETRY_AFTER_STRANDED_RESTORE'
  Host=$HostLabel;SourceCommit=$env:GITHUB_SHA;PreviousOfficialVersion='1.7.7'
  PreviousOfficialSetupSHA256=$published177;PreviousOfficialMainSHA256=$publishedMain177
  PreviousManifestRowsSHAAndSizeChecked=22;PredecessorSetupProcessRun=$false;PrivilegedDriverInstalled=$false
  CandidateVersion='1.7.8';CandidateSetupSHA256=$candidateSha;CandidateMainSHA256=$mainSha
  StagedPhase='COMMITTING';ManagedFileReplacementsBeforeKill=2
  StagingHelperActuallyKilled=$true;NativeSetupProcessActuallyKilled=$nativeWasKilled
  NativeSetupManagedNoteDeletionWitnessed=$documentWitness
  StrandedUpdaterOwnedRestoreZeroByteProven=$true
  StrandedScratchInjectedOnlyIfAbsent=$residueInjected
  RecoveredAfterSecondNativeSetupRun=$true;ProtectedUserDataHashPreserved=$true
  SingleCanonicalUserRootPreserved=$true;JournalRemoved=$true
  PhysicalMainsLossTriggered=$false;OriginalOwnerComputerTouched=$false
  PassedGates=@($gates);RecordedUtc=[DateTime]::UtcNow.ToString('o')
 }
 [IO.File]::WriteAllText($report,($result|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 $accepted=$true
 'R286_DISPOSABLE_GUEST_'+$HostLabel+'_INTERRUPTED_SETUP_RECOVERY=PASS'
}catch{
 $reason=$_.Exception.ToString()
 Write-Output ('R286_GUEST_PHASE_FAILURE='+$phaseNow+' REASON='+$reason)
 throw
}finally{
 if($watcher){$watcher.EnableRaisingEvents=$false;$watcher.Dispose()}
 if($native){
  try{$native.Refresh();if(!$native.HasExited -and $env:RUNNER_ENVIRONMENT -cne 'owner'){$native.Kill();[void]$native.WaitForExit(12000)}}finally{$native.Dispose()}
 }
 if($child){
  try{$child.Refresh();if(!$child.HasExited -and $env:RUNNER_ENVIRONMENT -cne 'owner'){$child.Kill();[void]$child.WaitForExit(12000)}}finally{$child.Dispose()}
 }
 if(!$accepted){
  $bad=[ordered]@{Schema=1;Revision='R286';Status='FAIL';Host=$HostLabel;Phase=$phaseNow
   Failure=$reason;NativeSetupWasKilled=$nativeWasKilled;WitnessedNativeDeletion=$documentWitness
   StrandedResidueInjected=$residueInjected;UserHostTouched=$false;Utc=[DateTime]::UtcNow.ToString('o')}
  [IO.File]::WriteAllText($report,($bad|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
 }
}
