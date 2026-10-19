[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$CandidateDir,[Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Genuine product install/update is permitted ONLY on a fresh disposable hosted VM.
if($PSVersionTable.PSEdition -eq 'Core' -or $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or $env:RUNNER_OS -cne 'Windows' -or $env:COMPUTERNAME -match 'EMAD-PC' -or ![Environment]::UserInteractive){throw 'R265_REFUSE_PERSONAL_OR_NONINTERACTIVE_HOST'}
Add-Type -AssemblyName System.Windows.Forms
# R156: keep genuine CLR null; PS5.1 string binder converts $null to empty string.
Add-Type -TypeDefinition 'using System.IO; public static class R156FileBridge { public static void ReplaceWithoutBackup(string source,string destination){File.Replace(source,destination,null);} }'
$repo='GOD13emad/TaskbarMonitorEnhanced'
$app=Join-Path $env:LOCALAPPDATA 'TaskbarMonitorEnhanced'
$reg='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TaskbarMonitorEnhanced'
$out=Join-Path $env:RUNNER_TEMP ('TBME_R265_UPGRADE_'+$HostLabel)
if((Test-Path $out) -or (Test-Path $app) -or (Test-Path $reg) -or @(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count){throw 'R265_NOT_FRESH_DISPOSABLE_HOST'}
$manifest=Get-Content (Join-Path $CandidateDir 'CANDIDATE.json') -Raw|ConvertFrom-Json
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.5.exe'
if($manifest.Commit -cne $env:GITHUB_SHA -or $manifest.Version -cne '1.7.5' -or $manifest.Private -ne $true -or (Get-FileHash $setup -Algorithm SHA256).Hash -cne $manifest.SetupSHA256){throw 'R265_NOT_EXACT_VERSIONED_CANDIDATE'}
New-Item -ItemType Directory -Path $out|Out-Null
$phase='SOURCE_DOWNLOAD';$status='FAIL';$errorText='';$negative=0;$rollback=$false;$preserved=$false;$idempotent=$false;$downgrade=$false;$chain=@();$beforeProtected=@{};$evidence=@();$oldCpuR170=$null;$newCpuR170=$null
function Hash([string]$p){if(Test-Path -LiteralPath $p -PathType Leaf){return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash};return 'MISSING'}
function Run-Exact([string]$path,[string]$Arguments,[int]$timeout=190000){
 $si=New-Object Diagnostics.ProcessStartInfo
 $si.FileName=$path;$si.Arguments=$Arguments;$si.UseShellExecute=$false;$si.WorkingDirectory=(Split-Path $path -Parent)
 $p=[Diagnostics.Process]::Start($si)
 if($null -eq $p){throw 'R265_SETUP_PROCESS_NOT_CREATED'}
 try{if(!$p.WaitForExit($timeout)){throw ('R265_SETUP_PROCESS_TIMEOUT PID='+$p.Id)};return [int]$p.ExitCode}finally{$p.Dispose()}
}
function StartupValue(){
 $k=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
 if($null -eq $k){return 'MISSING'};$p=$k.PSObject.Properties['TaskbarMonitorEnhanced'];if($null -eq $p){return 'MISSING'};return [string]$p.Value
}
function Snapshot(){
 $map=@{}
 $inventory=Get-Content (Join-Path $PSScriptRoot 'official-v174-managed.json') -Raw|ConvertFrom-Json
 $paths=@($inventory.Rows|ForEach-Object Path)+@('Docs/RELEASE_NOTES_v1.7.5.md','install_state.json','config.json','config.json.bak','R265_USER_OWNED.txt','SensorBackend/LibreHardwareMonitor-0.9.6/LibreHardwareMonitorLib.dll')
 # Exclude volatile sensor telemetry/log files, not owned by installer and free to change independently.
 foreach($rel in @($paths|Select-Object -Unique)){$map[$rel]=Hash (Join-Path $app $rel)}
 $map['@RegistryVersion']=[string](Get-ItemProperty $reg).DisplayVersion
 $map['@Startup']=StartupValue
 return $map
}
function Equal-Snapshot($a,$b,[string]$reason){
 if($a.Count -ne $b.Count){throw ('R265_SNAPSHOT_COUNT_CHANGED '+$reason)}
 foreach($k in $a.Keys){if(!$b.ContainsKey($k) -or $a[$k] -cne $b[$k]){throw ('R265_SNAPSHOT_CHANGED '+$reason+' '+$k)}}
}
# R170: identical owner-independent CPU sampling on BOTH versions on the SAME disposable
# GitHub-hosted Windows worker. Never invoked on personal/unknown hosts.
function Measure-InstalledCpuR170([string]$version,[string]$expectedSha){
 if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
    $env:RUNNER_OS -cne 'Windows' -or ![Environment]::UserInteractive){
    throw 'R170_CPU_PROBE_REFUSES_NON_DISPOSABLE_MACHINE'
 }
 $bin=Join-Path $app 'TaskbarMonitorEnhanced.exe'
 $configFile=Join-Path $app 'config.json'
 $backupFile=Join-Path $app 'config.json.bak'
 if((Hash $bin) -cne $expectedSha){throw 'R170_CANDIDATE_EXE_SHA_MISMATCH'}
 if(@(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count){
    throw 'R170_BEFORE_SAMPLE_PRODUCT_PROCESS_ALREADY_RUNNING'
 }
 $cfgBytes=[IO.File]::ReadAllBytes($configFile)
 $bakBytes=[IO.File]::ReadAllBytes($backupFile)
 $cfgSha=Hash $configFile;$bakSha=Hash $backupFile
 $probe=$null;$sample=$null;$forcedStop=$false
 try{
   $probe=Start-Process -FilePath $bin -WorkingDirectory $app -PassThru -ErrorAction Stop
   Start-Sleep -Seconds 8
   $probe.Refresh()
   if($probe.HasExited){throw ('R170_PROCESS_EXITED_DURING_WARMUP_'+$version)}
   $cpu0=$probe.TotalProcessorTime.TotalSeconds
   $timer=[Diagnostics.Stopwatch]::StartNew()
   Start-Sleep -Seconds 8
   $timer.Stop()
   $probe.Refresh()
   if($probe.HasExited){throw ('R170_PROCESS_EXITED_DURING_SAMPLE_'+$version)}
   $cpuSeconds=$probe.TotalProcessorTime.TotalSeconds-$cpu0
   $elapsed=$timer.Elapsed.TotalSeconds
   $pct=100.0*$cpuSeconds/$elapsed
   if($elapsed -lt 7.5 -or $elapsed -gt 12.5 -or $cpuSeconds -lt 0 -or
      $pct -gt 500 -or [Double]::IsNaN($pct)){
     throw ('R170_INVALID_CPU_SAMPLE_'+$version)
   }
   $sample=[ordered]@{Version=$version;Host=$HostLabel;MainSHA256=$expectedSha;
     CpuSeconds=$cpuSeconds;ElapsedSeconds=$elapsed;PercentOfOneCore=$pct;
     ProcessId=$probe.Id;WarmupSeconds=8;Source='HOSTED_PROCESS_CPU_NOT_PERSONAL';
     ConfigurationBeforeSHA=$cfgSha;BackupBeforeSHA=$bakSha}
 }
 finally{
   if($null -ne $probe){
     try{
       $probe.Refresh()
       if(!$probe.HasExited){
         try{[void]$probe.CloseMainWindow()}catch{}
         if(!$probe.WaitForExit(3500)){
            $forcedStop=$true # CI-only process launched above, on disposable runner.
            $probe.Kill()
            if(!$probe.WaitForExit(12000)){throw 'R170_DISPOSABLE_PROCESS_NOT_STOPPED'}
         }
       }
     }finally{$probe.Dispose()}
   }
   # Restore the exact isolated test fixture if application startup normalizes it.
   if((Hash $configFile) -cne $cfgSha){
      [IO.File]::WriteAllBytes($configFile,$cfgBytes)
      if((Hash $configFile) -cne $cfgSha){throw 'R170_TEST_CONFIG_RESTORE_FAILED'}
   }
   if((Hash $backupFile) -cne $bakSha){
      [IO.File]::WriteAllBytes($backupFile,$bakBytes)
      if((Hash $backupFile) -cne $bakSha){throw 'R170_TEST_BACKUP_RESTORE_FAILED'}
   }
 }
 if($null -eq $sample){throw 'R170_NO_HOSTED_CPU_SAMPLE'}
 if(@(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count){
    throw 'R170_LEFT_TEST_PROCESS_RUNNING'
 }
 $sample['DisposableOnlyForcedStop']=$forcedStop
 $sample['ConfigRestoredToOriginalSHA']=((Hash $configFile) -ceq $cfgSha)
 $sample['BackupRestoredToOriginalSHA']=((Hash $backupFile) -ceq $bakSha)
 return $sample
}
try{
 & gh release download v1.7.4 --repo $repo --pattern TaskbarMonitorEnhanced_Setup_1.7.4.exe --dir $out
 if($LASTEXITCODE -ne 0){throw 'R265_OFFICIAL172_DOWNLOAD_FAILED'}
 $priorSetup=Join-Path $out 'TaskbarMonitorEnhanced_Setup_1.7.4.exe'
 if((Hash $priorSetup) -cne 'C00F0C944E4BFBEE93989E4B5A29931D460CC0011ABDC8FDE6A498E467BCC1A1'){throw 'R265_PREVIOUS_SETUP_NOT_IMMUTABLE_OFFICIAL'}
 $phase='CREATE_GENUINE_V172_PREDECESSOR'
 if($HostLabel -ceq 'B'){
  & gh release download v1.7.3 --repo $repo --pattern TaskbarMonitorEnhanced_Setup_1.7.3.exe --dir $out
  if($LASTEXITCODE -ne 0){throw 'R265_OFFICIAL171_DOWNLOAD_FAILED'}
  $older=Join-Path $out 'TaskbarMonitorEnhanced_Setup_1.7.3.exe'
  if((Hash $older) -cne '9EB5C54B4AE4C36F4035F115AC87403D9238AC66AA9AFE58DC5B211311D9774B'){throw 'R265_PREVIOUS_V171_SETUP_CHANGED'}
  if((Run-Exact $older '/install /quiet /desktop=0 /startup=0') -ne 0){throw 'R265_GENUINE_V171_INSTALL_FAILED'}
  if((Run-Exact $priorSetup '/update /quiet') -ne 0){throw 'R265_GENUINE_V171_TO_V173_FAILED'}
  $chain=@('1.7.3','1.7.4')
 }else{
  if((Run-Exact $priorSetup '/install /quiet /desktop=0 /startup=0') -ne 0){throw 'R265_GENUINE_V173_INSTALL_FAILED'}
  $chain=@('1.7.4')
 }
 if((Hash (Join-Path $app 'TaskbarMonitorEnhanced.exe')) -cne '279DF6276973D45A1F979792718E7BA1A9DB31A44C3C34E7335C7BE1503A3E3C' -or (Get-ItemProperty $reg).DisplayVersion -cne '1.7.4'){throw 'R265_OFFICIAL_V173_INSTALLED_IDENTITY_NOT_PROVEN'}
  # Neither fresh official v1.7.4 nor the v1.7.3→v1.7.4 upgrade includes
  # a redundant root C# source; original R254 defect was already fixed.
  $extra=Join-Path $app 'TaskbarMonitorEnhanced.cs'
  $source=Join-Path $app 'Source/TaskbarMonitorEnhanced.cs'
  if((Test-Path $extra) -or (Hash $source) -ceq 'MISSING'){
   throw 'R265_PUBLIC_V174_SOURCE_LAYOUT_NOT_CANONICAL'
  }
  $config=Join-Path $app 'config.json';$backup=Join-Path $app 'config.json.bak';$state=Join-Path $app 'install_state.json'
 $fixture='{"Theme":"Retro Terminal","Opacity":0.00,"GlassMode":true,"OpacityWhenGlassOff":0.10,"ConfigSchemaVersion":8,"StartWithWindows":false,"UpdateIntervalMs":1000,"ShowSparklines":true,"AutoCheckUpdates":false,"R265OwnerSentinel":"preserve user literal 1.7.4"}'
 [IO.File]::WriteAllText($config,$fixture,[Text.UTF8Encoding]::new($false))
 [IO.File]::WriteAllText($backup,'{"independent":"prior backup must not be overwritten"}',[Text.UTF8Encoding]::new($false))
 $userFile=Join-Path $app 'R265_USER_OWNED.txt';[IO.File]::WriteAllText($userFile,'User data, not installer-managed.',[Text.UTF8Encoding]::new($false))
 $sourceText=[IO.File]::ReadAllText($state)
 $expectedState=$sourceText.Replace('"Version": "1.7.4"','"Version": "1.7.5"').Replace('"PublicVersion": "1.7.4"','"PublicVersion": "1.7.5"')
 if($expectedState -ceq $sourceText){throw 'R265_ACTUAL_STATE_FORMAT_NOT_RECOGNIZED'}
 foreach($path in @($config,$backup,$userFile,(Join-Path $app 'SensorBackend\LibreHardwareMonitor-0.9.6\LibreHardwareMonitorLib.dll'))){if((Hash $path) -ceq 'MISSING'){throw ('R265_PROTECTED_INPUT_MISSING '+$path)};$beforeProtected[$path]=Hash $path}
 $startupBefore=StartupValue
 $phase='SAME_HOST_171_CPU_BASELINE'
 $oldCpuR170=Measure-InstalledCpuR170 '1.7.4' '279DF6276973D45A1F979792718E7BA1A9DB31A44C3C34E7335C7BE1503A3E3C'
 if($null -eq $oldCpuR170){throw 'R170_MISSING_OLD_BASELINE'}
 $phase='REJECT_EDITED_MANAGED_SOURCE'
 $managed=Join-Path $app 'Source\TaskbarGlass.cs';$original=[IO.File]::ReadAllBytes($managed)
 $changed=[byte[]]($original+[Text.Encoding]::UTF8.GetBytes("`n// deliberate owner edit: updater must refuse`n"))
 [IO.File]::WriteAllBytes($managed,$changed);$editedHash=Hash $managed
 $snap=Snapshot
 $code=Run-Exact $setup '/update /quiet'
 if($code -eq 0){throw 'R265_EDITED_SOURCE_ACCEPTED'}
 Equal-Snapshot $snap (Snapshot) 'EDITED_SOURCE_REFUSAL'
 if(Test-Path (Join-Path $app '.tbme-upgrade')){throw 'R265_REFUSAL_LEFT_STAGE'}
 if((Hash $managed) -cne $editedHash){throw 'R265_CONCURRENT_EDIT_CANNOT_RESTORE_FIXTURE'}
 [IO.File]::WriteAllBytes($managed,$original);$negative++
 $phase='REJECT_UNKNOWN_INSTALLED_VERSION'
 [IO.File]::WriteAllText($state,$sourceText.Replace('1.7.4','9.9.9'),[Text.UTF8Encoding]::new($false))
 $snap=Snapshot;$code=Run-Exact $setup '/update /quiet'
 if($code -eq 0){throw 'R265_UNKNOWN_VERSION_ACCEPTED'}
 Equal-Snapshot $snap (Snapshot) 'UNKNOWN_VERSION_REFUSAL'
 [IO.File]::WriteAllText($state,$sourceText,[Text.UTF8Encoding]::new($false));$negative++
 $phase='REAL_ROLLBACK_ENGINE_AFTER_SIMULATED_PARTIAL_COMMIT'
 # Exercise production journal and rollback code, without adding failure hooks to shipped binaries.
 # This is explicit simulated interruption, not a physical outage or real process-kill witness.
 $a=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup));$t=$a.GetType('SetupProgram',$true);$f=[Reflection.BindingFlags]'Static,NonPublic,Public'
 $legacy=$t.GetMethod('LegacyExpected',$f).Invoke($null,[object[]]@('1.7.4','OFFICIAL_STABLE_V174'))
 $fresh=$t.GetMethod('PrepareNewBytes',$f).Invoke($null,[object[]]@($sourceText))
 # Reflection host is PowerShell, so explicitly substitute EXACT verified Setup bytes for @SELF.
 $fresh['Uninstall.exe']=[IO.File]::ReadAllBytes($setup)
 $beforeRollback=Snapshot
 [void]$t.GetMethod('StageNewManaged',$f).Invoke($null,[object[]]@($fresh,$legacy,$sourceText,'1.7.4','OFFICIAL_STABLE_V174'))
 $stage=Join-Path $app '.tbme-upgrade'
 [void]$t.GetMethod('WritePhase',$f).Invoke($null,[object[]]@('COMMITTING'))
 foreach($rel in @('TaskbarMonitorEnhanced.exe','Source/TaskbarGlass.cs')){
  $staged=Join-Path (Join-Path $stage 'new') $rel;$live=Join-Path $app $rel
  [R156FileBridge]::ReplaceWithoutBackup($staged,$live)
 }
 if((Hash (Join-Path $app 'TaskbarMonitorEnhanced.exe')) -cne $manifest.MainSHA256){throw 'R265_PARTIAL_COMMIT_NOT_REAL'}
 [void]$t.GetMethod('RecoverUpgradeStageIfAny',$f).Invoke($null,[object[]]@())
 if(Test-Path $stage){throw 'R265_ROLLBACK_STAGE_NOT_CLEARED'}
 Equal-Snapshot $beforeRollback (Snapshot) 'REAL_ROLLBACK_RESTORATION';$rollback=$true
 $phase='REAL_CLI_171_TO_172'
 $code=Run-Exact $setup '/update /quiet'
 if($code -ne 0){throw ('R265_REAL_UPGRADE_FAILED EXIT='+$code)}
 if((Hash (Join-Path $app 'TaskbarMonitorEnhanced.exe')) -cne $manifest.MainSHA256 -or (Hash (Join-Path $app 'Uninstall.exe')) -cne $manifest.SetupSHA256){throw 'R265_FINAL_BINARY_HASH_MISMATCH'}
 if((Get-ItemProperty $reg).DisplayVersion -cne '1.7.5' -or [IO.File]::ReadAllText($state) -cne $expectedState){throw 'R265_STATE_OR_REGISTRY_NOT_EXACT_174'}
 foreach($path in $beforeProtected.Keys){if((Hash $path) -cne $beforeProtected[$path]){throw ('R265_USER_DATA_CHANGED '+$path)}}
 if((StartupValue) -cne $startupBefore){throw 'R265_STARTUP_PREFERENCE_CHANGED'}
 if(Test-Path $stage){throw 'R265_STAGE_LEFT_AFTER_SUCCESS'}
 if(!(Test-Path (Join-Path $app 'Docs\RELEASE_NOTES_v1.7.5.md')) -or (Test-Path (Join-Path $app 'Docs\RELEASE_NOTES_v1.7.4.md'))){throw 'R265_RELEASE_NOTES_NOT_MIGRATED'}
 $registrations=@(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'|Where-Object PSChildName -ceq 'TaskbarMonitorEnhanced')
 if($registrations.Count -ne 1 -or (Get-ItemProperty $reg).InstallLocation -cne $app){throw 'R265_DUPLICATE_OR_WRONG_ROOT'}
 $preserved=$true;$chain+=@('1.7.5')
 $phase='SAME_HOST_172_CPU_COMPARATOR'
 $newCpuR170=Measure-InstalledCpuR170 '1.7.5' $manifest.MainSHA256
 if($null -eq $newCpuR170 -or $oldCpuR170.Host -cne $newCpuR170.Host){throw 'R170_SAME_HOST_CPU_NOT_VERIFIED'}
 $phase='IDEMPOTENCE_AND_DOWNGRADE_REFUSAL'
 $after=Snapshot
 if((Run-Exact $setup '/update /quiet') -ne 0){throw 'R265_REPEATED_IDENTICAL_UPGRADE_FAILED'}
 Equal-Snapshot $after (Snapshot) 'IDENTICAL_REINSTALL';$idempotent=$true
 if((Run-Exact $priorSetup '/update /quiet') -eq 0){throw 'R265_OLD_INSTALLER_DOWNGRADE_ACCEPTED'}
 Equal-Snapshot $after (Snapshot) 'DOWNGRADE_REFUSAL';$downgrade=$true
 $status='PASS_GENUINE_174_TO_175_SINGLE_ROOT_PRESERVATION_ROLLBACK_IDEMPOTENCE'
}catch{$errorText=$_.Exception.ToString()}
finally{
 $r=[ordered]@{Revision='R265';Status=$status;Phase=$phase;Failure=$errorText;Host=$HostLabel;Commit=$env:GITHUB_SHA;SourceChain=$chain;MainSHA256=$manifest.MainSHA256;SetupSHA256=$manifest.SetupSHA256;RejectedUnsafeUpdates=$negative;RealProductionRollbackAfterSimulatedPartialCommit=$rollback;PhysicalPowerCutClaimed=$false;RealProcessKillClaimed=$false;ProtectedUserFilesPreserved=$preserved;IdenticalSetupIdempotent=$idempotent;DowngradeRefused=$downgrade;PersonalComputerTouched=$false;ProtectedSHA256=$beforeProtected;R170SameHostedWindowsOldCpu=$oldCpuR170;R170SameHostedWindowsNewCpu=$newCpuR170;R170SameHostCpuMeasured=($null -ne $oldCpuR170 -and $null -ne $newCpuR170);R170PersonalCpuAcceptance=$false}
 [IO.File]::WriteAllText((Join-Path $out 'R265_UPGRADE.json'),($r|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 Write-Output ($r|ConvertTo-Json -Depth 8 -Compress)
}
if($status -notlike 'PASS_*'){throw ('R265_UPGRADE_ACCEPTANCE_FAILED '+$phase+' '+$errorText)}
