[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][ValidateSet('LiveRace')][string]$Mode,
 [Parameter(Mandatory=$true)][string]$SourceRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# R354: compile/build the original Setup, launch ONLY its own generated
# unelevated deferred-cleanup command on an already clean, disposable
# GitHub-hosted Windows user profile. Never invoke this on the owner PC.
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'GOD13emad/TaskbarMonitorEnhanced' -or
   $env:GITHUB_REF -cne 'refs/heads/audit/r355-deferred-cleanup-directory-pins' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC|ALIEMAD|SAEID|LAPTOP' -or
   $env:GITHUB_RUN_ID -cnotmatch '^[0-9]{5,20}$' -or
   $env:GITHUB_SHA -cnotmatch '^[a-f0-9]{40}$' -or
   (git -C $SourceRoot rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){
 throw 'R354_REFUSE_NONDISPOSABLE_OR_UNPINNED_HOST'
}
$who=[Security.Principal.WindowsIdentity]::GetCurrent()
$admin=[Security.Principal.WindowsPrincipal]::new($who)
if(!$admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 throw 'R354_GITHUB_RUNNER_ALREADY_ADMIN_REQUIRED'
}
if($HostLabel -cne 'A' -and $HostLabel -cne 'B'){throw 'R354_INVALID_MATRIX_HOST'}
$profile=[Environment]::GetFolderPath('UserProfile')
$local=[Environment]::GetFolderPath('LocalApplicationData')
$program=[Environment]::GetFolderPath('ProgramFiles')
$app=Join-Path $local 'TaskbarMonitorEnhanced'
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$protected=Join-Path $program 'TaskbarMonitorEnhanced'
$taskName='TaskbarMonitorEnhanced Sensor Broker'
$receiptRoot=Join-Path $env:RUNNER_TEMP ('R354_'+$Mode+'_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $receiptRoot 'R354_ORIGINAL_DEFERRED_CLEANUP.json'
$external=Join-Path $receiptRoot 'R354_OUTSIDE_CANARY_ROOT'
$canary=Join-Path $external 'NEVER_DELETE_OUTSIDE.txt'
$fixture=Join-Path $app 'synthetic-owner-file.txt'
$child=Join-Path $app 'malicious-child-junction'
$checks=[Collections.Generic.List[string]]::new()
$exitCode=-1;$stderr='';$failure='';$phase='PRECONDITION'
$setup='';$sourceExact=$false;$fixtureCreated=$false;$outsideSha=''
$canaryUnchanged=$false;$reparseRefused=$false;$nominalDeleted=$false
$testCleaned=$false;$parentPid=0;$parentTicks=0;$cleanupPid=0
$compiledEmbeddedSource=$false;$decodedTransport=$false;$nativeOriginalProcessLaunched=$false
$actorProcess=$null;$actorPid=0;$actorReceipt='';$actorReady='';$actorSignal='';$actorProofSha='';$actorDenied=$false;$actorAttempts=0;$actorObservedDeleted=-1;$actorExit=-1;$stageDir='';$raceMoved='';$filesCount=4000
$spillover='';$spilloverMoved=$false;$spilloverRestored=$false
$spillBefore='';$spillAfter='';$syntheticGone=$false
function FingerprintGuestApp([string]$base){
 if(![IO.Directory]::Exists($base)){throw 'R354_SPILL_NOT_DIRECTORY'}
 if(([IO.File]::GetAttributes($base) -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'R354_SPILL_ROOT_REPARSE'}
 $members=@(Get-ChildItem -LiteralPath $base -Recurse -Force -ErrorAction Stop)
 if($members.Count -gt 300){throw 'R354_SPILL_TOO_MANY_ENTRIES'}
 $lines=[Collections.Generic.List[string]]::new()
 [long]$total=0
 foreach($item in $members){
   if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'R354_SPILL_MEMBER_REPARSE'}
   $rel=$item.FullName.Substring($base.TrimEnd('\').Length+1)
   if($item.PSIsContainer){$lines.Add('D|'+$rel)}
   else{
     if($item.Length -gt 16777216){throw 'R354_SPILL_OVERSIZE_FILE'}
     $total+=$item.Length
     if($total -gt 67108864){throw 'R354_SPILL_TOO_MANY_BYTES'}
     $lines.Add('F|'+$rel+'|'+$item.Length+'|'+(Hash $item.FullName))
   }
 }
 $digest=[Security.Cryptography.SHA256]::Create()
 try{
   $joined=[string]::Join([string][char]10,[string[]]@($lines|Sort-Object -CaseSensitive))
   return ([BitConverter]::ToString($digest.ComputeHash([Text.Encoding]::UTF8.GetBytes($joined)))).Replace('-','')
 }finally{$digest.Dispose()}
}

function Check([string]$name){$script:checks.Add($name);Write-Output ('PASS '+$name)}
function Hash([string]$p){return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash}
function IsTaskPresent(){
 return @((Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue|Where-Object {$null -ne $_})).Count -ne 0
}
# This receipt path is RUNNER_TEMP on a verified hosted disposable Windows
# runner, not any owner installation; it must exist even when preflight fails.
if([IO.Directory]::Exists($receiptRoot)){throw 'R354_OWNED_RECEIPT_ROOT_PREEXISTS'}
[IO.Directory]::CreateDirectory($receiptRoot)|Out-Null
$fresh=[ordered]@{AppDir=$false;ProtectedDir=$false;MainFile=$false;SensorTask=$false;SensorProcessCount=0}
try{
 $phase='VERIFY_FRESH_GITHUB_HOSTED_CLEAN_PROFILE'
 $fresh.AppDir=[IO.Directory]::Exists($app)
 $fresh.ProtectedDir=[IO.Directory]::Exists($protected)
 $fresh.MainFile=[IO.File]::Exists($main)
 $fresh.SensorTask=[bool](IsTaskPresent)
 $fresh.SensorProcessCount=@(Get-Process TaskbarMonitorEnhanced,TaskbarMonitorSensorBroker,TaskbarMonitorSensorSupervisor -ErrorAction SilentlyContinue).Count
 Write-Output ('R354_NATIVE_GUEST_FRESHNESS='+($fresh|ConvertTo-Json -Compress))
 $marker=Join-Path $env:RUNNER_TEMP 'R354_PREBUILD_FRESH_GUEST.json'
 if(![IO.File]::Exists($marker)){throw 'R354_PREBUILD_FRESHNESS_PROOF_MISSING'}
 $pre=Get-Content -LiteralPath $marker -Raw|ConvertFrom-Json
 if($pre.Schema -ne 1 -or $pre.Revision -cne 'R354' -or
    $pre.SourceCommit -cne $env:GITHUB_SHA -or
    $pre.Host -cne $env:COMPUTERNAME -or
    $pre.AppRootAbsentBeforeBuild -ne $true -or
    $pre.ProtectedRootAbsentBeforeBuild -ne $true -or
    $pre.TaskAbsentBeforeBuild -ne $true){
   throw 'R354_BAD_PREBUILD_FRESHNESS_PROOF'
 }
 if($fresh.ProtectedDir -or $fresh.MainFile -or
    $fresh.SensorTask -or $fresh.SensorProcessCount -gt 0){
   throw 'R354_POSTBUILD_REAL_PRODUCT_OR_SENSOR_REFUSED'
 }
 if(-not [string]::Equals([IO.Path]::GetFullPath($local),
   [IO.Path]::GetFullPath((Join-Path $profile 'AppData\Local')),[StringComparison]::OrdinalIgnoreCase)){
   throw 'R354_NONCANONICAL_LOCALAPPDATA_REFUSED'
 }
 [IO.Directory]::CreateDirectory($external)|Out-Null
 [IO.File]::WriteAllText($canary,'R354_OUTSIDE_CANARY_DO_NOT_TOUCH',[Text.UTF8Encoding]::new($false))
 $outsideSha=Hash $canary
 Check 'REAL_GITHUB_HOSTED_WINDOWS_CLEAN_APP_TASK_AND_SENSORS_ABSENT'
 Check 'EXPECTED_OWNER_APP_ROOT_IS_CANONICAL_KNOWNFOLDER_NOT_ENV_OVERRIDE'
 $phase='ISOLATE_KNOWN_BUILD_ONLY_APPROOT'
 if($fresh.AppDir){
   $spillover=Join-Path $local ('TaskbarMonitorEnhanced_R354_BUILD_SNAPSHOT_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
   if(Test-Path -LiteralPath $spillover){throw 'R354_SPILL_PREEXISTS'}
   $spillBefore=FingerprintGuestApp $app
   [IO.Directory]::Move($app,$spillover)
   $spilloverMoved=$true
   if([IO.Directory]::Exists($app) -or
      (FingerprintGuestApp $spillover) -cne $spillBefore){
     throw 'R354_SPILL_MOVE_SHA_MISMATCH'
   }
 }
 Check 'PREBUILD_FRESH_GUEST_BUILD_ONLY_APPDATA_ATOMICALLY_ISOLATED'
 $phase='REFLECT_EXACT_COMPILED_PRODUCTION_SETUP_PRIVATE_FACTORY'
 $setup=Join-Path $SourceRoot 'build\_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
 $source=Join-Path $SourceRoot 'installer\TaskbarMonitorEnhanced_Setup.cs'
 $native=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
 foreach($p in @($setup,$source,$native)){
   if(![IO.File]::Exists($p)){throw 'R354_BUILD_OR_TRUSTED_WINDOWS_HOST_MISSING'}
 }
 $assembly=[Reflection.Assembly]::LoadFrom((Resolve-Path $setup).Path)
 $reader=[IO.StreamReader]::new($assembly.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced_Setup.cs'))
 try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
 $expectedSource=[IO.File]::ReadAllText($source)
 $normalize={param([string]$s) $s.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
 if((& $normalize $embedded) -cne (& $normalize $expectedSource)){
   throw 'R354_ORIGINAL_PE_SETUP_SOURCE_HASH_MISMATCH'
 }
 $sourceExact=$true;$compiledEmbeddedSource=$true
 Check 'REAL_ORIGINAL_SETUP_PE_EMBEDS_EXACT_REVIEWED_SETUP_SOURCE'
 $type=$assembly.GetType('SetupProgram',$true)
 $flags=[Reflection.BindingFlags]'Static,NonPublic'
 $builder=$type.GetMethod('BuildDeferredUninstallCleanupProcessInfo',$flags)
 $appProp=$type.GetProperty('AppRoot',$flags)
 if(!$builder -or !$appProp){throw 'R354_EXACT_PE_CLEANUP_FACTORY_MISSING'}
 $known=[string]$appProp.GetValue($null,$null)
 if(-not [string]::Equals($known,$app,[StringComparison]::OrdinalIgnoreCase)){
   throw 'R354_SETUP_KNOWN_APP_ROOT_CHANGED'
 }
 Check 'PRODUCTION_SETUP_KNOWN_ROOT_AND_REAL_FACTORY_VERIFIED'
 $phase='USE_REAL_EXITED_PARENT_IDENTITY_FOR_DEFERRED_CLEANUP'
 $sacStart=[Diagnostics.ProcessStartInfo]::new()
 $sacStart.FileName=$native
 $sacStart.Arguments='-NoProfile -NonInteractive -Command "Start-Sleep -Milliseconds 800"'
 $sacStart.UseShellExecute=$false;$sacStart.CreateNoWindow=$true
 $parent=[Diagnostics.Process]::Start($sacStart)
 if(!$parent){throw 'R354_TEST_PARENT_PROCESS_MISSING'}
 try{
  $parentPid=$parent.Id
  $parentTicks=$parent.StartTime.ToUniversalTime().Ticks
  if(!$parent.WaitForExit(10000)){throw 'R354_REAL_PARENT_DID_NOT_EXIT'}
 }finally{$parent.Dispose()}
 if($parentPid -le 0 -or $parentTicks -le 0){
  throw 'R354_INVALID_REAL_EXITED_PARENT_IDENTITY'
 }
 $args=[object[]]::new(3)
 $args[0]=([string]$known).PSObject.BaseObject
 $args[1]=([int]$parentPid).PSObject.BaseObject
 $args[2]=([long]$parentTicks).PSObject.BaseObject
 $psi=[Diagnostics.ProcessStartInfo]$builder.Invoke($null,$args)
 if(-not [string]::Equals($psi.FileName,$native,[StringComparison]::OrdinalIgnoreCase) -or
    $psi.UseShellExecute -ne $false -or
    !$psi.Arguments.StartsWith('-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand ',[StringComparison]::Ordinal) -or
    $psi.Arguments.Contains($app) -or
    $psi.Arguments.Contains(' -File ') -or
    $psi.Arguments.Contains(' -Command ')){
   throw 'R354_REAL_SETUP_PROCESS_FACTORY_NOT_BOUND_TO_TRUSTED_HOST'
 }
 $decoded=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(
   $psi.Arguments.Substring('-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand '.Length)))
 $tokens=$null;$parseErrors=$null
 [Management.Automation.Language.Parser]::ParseInput($decoded,[ref]$tokens,[ref]$parseErrors)|Out-Null
 if(@($parseErrors).Count -ne 0 -or
    !$decoded.Contains('TBME_CLEANUP_ANCESTOR_REPARSE') -or
    !$decoded.Contains('TBME_CLEANUP_CHILD_REPARSE') -or
    !$decoded.Contains('[IO.Directory]::Delete($dir,$false)')){
   throw 'R354_ORIGINAL_PE_CLEANUP_COMMAND_INCORRECT'
 }
 $decodedTransport=$true
 Check 'REAL_EXITED_PARENT_ID_AND_UTF16_ONLY_ORIGINAL_SETUP_COMMAND_TRANSPORT'
 $phase='CREATE_DISPOSABLE_CANARY_AND_OPTIONAL_JUNCTION'
 if($Mode -ceq 'RootJunction'){
   if(Test-Path -LiteralPath $app){throw 'R354_FRESH_ROOT_ALREADY_OCCUPIED'}
   New-Item -ItemType Junction -Path $app -Target $external -ErrorAction Stop|Out-Null
   if(([IO.File]::GetAttributes($app) -band [IO.FileAttributes]::ReparsePoint) -eq 0){
     throw 'R354_ROOT_JUNCTION_NOT_ACTUALLY_REPARSE'
   }
   $fixtureCreated=$true
 }else{
   [IO.Directory]::CreateDirectory($app)|Out-Null
   [IO.File]::WriteAllText($fixture,'R354_TEST_USER_DATA_ONLY',[Text.UTF8Encoding]::new($false))
    $fixtureCreated=$true
    if($Mode -ceq 'LiveRace'){
       $phase='R355_CREATE_BOUNDED_ONLY_HOSTED_TEST_FILES_FOR_REAL_DELETION'
       $stageDir=Join-Path $app 'delete_stage'
       [IO.Directory]::CreateDirectory($stageDir)|Out-Null
       for($i=0;$i -lt $filesCount;$i++){
         [IO.File]::WriteAllText((Join-Path $stageDir ('{0:d5}.bin' -f $i)),
             'R355_ONLY_TEST_DATA',[Text.UTF8Encoding]::new($false))
       }
       $check=@([IO.Directory]::GetFiles($stageDir,'*.bin'))
       if($check.Count -ne $filesCount -or
          ![IO.File]::Exists((Join-Path $stageDir '00000.bin'))){
         throw 'R355_REAL_CLEANUP_FIXTURE_FILES_INCOMPLETE'
       }
       Check 'BOUNDED_FOUR_THOUSAND_SYNTHETIC_TEST_FILES_ONLY_IN_HOSTED_APPROOT'
    }
    if($Mode -ceq 'ChildJunction'){
      New-Item -ItemType Junction -Path $child -Target $external -ErrorAction Stop|Out-Null
      if(([IO.File]::GetAttributes($child) -band [IO.FileAttributes]::ReparsePoint) -eq 0){
        throw 'R354_CHILD_JUNCTION_NOT_ACTUALLY_REPARSE'
      }
   }
 }
 Check 'ONLY_FRESH_GUEST_OWNED_SYNTHETIC_ROOT_WITH_EXTERNAL_CANARY_PREPARED'
  if($Mode -ceq 'LiveRace'){
    $phase='R355_PRESTART_INDEPENDENT_NATIVE_RENAME_ACTOR'
    $actorFile=Join-Path $SourceRoot 'build\Test-R355-RealCleanupRenameActor-Native.ps1'
    if(![IO.File]::Exists($actorFile)){throw 'R355_RACE_ACTOR_FILE_MISSING'}
    $actorReceipt=Join-Path $receiptRoot 'R355_LIVE_RENAME_ACTOR.json'
    $actorReady=Join-Path $receiptRoot 'R355_LIVE_RENAME_READY.txt'
    $actorSignal=Join-Path $receiptRoot 'R355_LIVE_RENAME_SIGNAL.json'
    $raceMoved=$app+'_R355_RACE_'+$HostLabel+'_'+$env:GITHUB_RUN_ID
    foreach($path in @($actorReceipt,$actorReady,$actorSignal,$raceMoved)){
       if(Test-Path -LiteralPath $path){throw 'R355_PREEXISTING_RACE_CONTROL_OR_MOVED_TARGET'}
    }
    foreach($path in @($actorFile,$app,$raceMoved,$actorReceipt,$actorReady,$actorSignal)){
       if($path.Contains('"')){throw 'R355_DISALLOWED_QUOTE_IN_TRUSTED_NATIVE_PATH'}
    }
    $actorPsi=[Diagnostics.ProcessStartInfo]::new()
    $actorPsi.FileName=$native
    $actorPsi.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$actorFile+'" -HostLabel "'+$HostLabel+'" -AppRoot "'+$app+'" -MovedRoot "'+$raceMoved+'" -ReadyPath "'+$actorReady+'" -SignalPath "'+$actorSignal+'" -ReceiptPath "'+$actorReceipt+'"'
    $actorPsi.CreateNoWindow=$true;$actorPsi.UseShellExecute=$false
    $actorProcess=[Diagnostics.Process]::Start($actorPsi)
    if(!$actorProcess){throw 'R355_ACTOR_PROCESS_FAILED_TO_START'}
    $actorPid=$actorProcess.Id
    if($actorPid -le 0 -or $actorPid -eq $PID){throw 'R355_ACTOR_NOT_INDEPENDENT_PID'}
    $wait=[Diagnostics.Stopwatch]::StartNew()
    while(![IO.File]::Exists($actorReady) -and !$actorProcess.HasExited -and $wait.ElapsedMilliseconds -lt 25000){
       Start-Sleep -Milliseconds 5
    }
    if(![IO.File]::Exists($actorReady) -or
       [IO.File]::ReadAllText($actorReady) -cne ('R355_REAL_NATIVE_ACTOR_READY_'+$env:GITHUB_SHA)){
       throw 'R355_ACTOR_PREHELPER_RENAME_PREFLIGHT_NOT_PROVEN'
    }
    Check 'SEPARATE_WINDOWS_RENAME_ACTOR_PREHELPER_ORIGINAL_ROOT_MOVE_AND_RESTORE_READY'
  }
  $phase='START_REAL_UNMODIFIED_COMPILED_SETUP_CLEANUP_PROCESS'
 $psi.RedirectStandardError=$true
 $psi.RedirectStandardOutput=$true
 $psi.CreateNoWindow=$true
 $cleanup=[Diagnostics.Process]::Start($psi)
 if(!$cleanup){throw 'R354_REAL_CLEANUP_PROCESS_NOT_STARTED'}
 try{
   $cleanupPid=$cleanup.Id
   if($Mode -ceq 'LiveRace'){
     $signalInfo=[ordered]@{SourceCommit=$env:GITHUB_SHA;Host=$HostLabel;CleanupPid=$cleanupPid}
     [IO.File]::WriteAllText($actorSignal,($signalInfo|ConvertTo-Json -Depth 5),
                            [Text.UTF8Encoding]::new($false))
   }
   if(!$cleanup.WaitForExit(70000)){
    if(!$cleanup.HasExited){$cleanup.Kill();[void]$cleanup.WaitForExit(8000)}
    throw 'R354_REAL_CLEANUP_PROCESS_TIMEOUT'
  }
  $exitCode=[int]$cleanup.ExitCode
  $stderr=[string]$cleanup.StandardError.ReadToEnd()
  $stdout=[string]$cleanup.StandardOutput.ReadToEnd()
 }finally{$cleanup.Dispose()}
 $nativeOriginalProcessLaunched=$true
 Check 'REAL_COMPILED_SETUP_GENERATED_CLEANUP_EXECUTED_AS_SEPARATE_NATIVE_PROCESS'
  if($Mode -ceq 'LiveRace'){
    $phase='R355_VERIFY_REAL_COMPETITOR_OVERLAPPED_ORIGINAL_CLEANUP_DELETION'
    if($null -eq $actorProcess){throw 'R355_ACTOR_LOST_BEFORE_WITNESS'}
    if(!$actorProcess.WaitForExit(15000)){
      if(!$actorProcess.HasExited){$actorProcess.Kill();[void]$actorProcess.WaitForExit(5000)}
      throw 'R355_ACTOR_COMPLETION_TIMED_OUT'
    }
    $actorExit=$actorProcess.ExitCode
    if($actorExit -ne 0 -or -not [IO.File]::Exists($actorReceipt)){
      throw ('R355_ACTOR_EXIT_NONZERO_OR_RECEIPT_MISSING_'+$actorExit)
    }
    $actorEvidence=Get-Content -LiteralPath $actorReceipt -Raw|ConvertFrom-Json
    $actorProofSha=Hash $actorReceipt
    if($actorEvidence.Status -cne 'PASS_REAL_NATIVE_ORIGINAL_CLEANUP_DIRECTORY_RENAME_DENIED_ON_LIVE_DELETION' -or
       $actorEvidence.SourceCommit -cne $env:GITHUB_SHA -or
       $actorEvidence.Host -cne $HostLabel -or
       $actorEvidence.ActorPid -ne $actorPid -or
       $actorEvidence.OriginalCleanupPid -ne $cleanupPid -or
       $actorEvidence.NativeSharingViolationWin32 -ne 32 -or
       $actorEvidence.RealRenameDeniedWhileCleanupAlive -ne $true -or
       $actorEvidence.FirstSyntheticFileAlreadyDeletedBeforeProbe -lt 0 -or
       $actorEvidence.PreHelperRenameSucceededAndRestored -ne $true -or
       $actorEvidence.RealRenameAllowedDuringCleanup -ne $false -or
       ![string]::IsNullOrEmpty([string]$actorEvidence.Failure)){
       throw 'R355_UNTRUSTED_ACTOR_REPORT_OR_UNPROVEN_LIVE_OVERLAP'
    }
    $actorDenied=$true
    $actorAttempts=[int]$actorEvidence.RenameAttempts
    $actorObservedDeleted=[int]$actorEvidence.FirstSyntheticFileAlreadyDeletedBeforeProbe
    Check 'ACTUAL_ORIGINAL_COMPILED_CLEANUP_DENIED_CONCURRENT_ROOT_RENAME_AFTER_FIRST_DELETION'
  }
  $phase='VERIFY_OUTCOME_EXACT_NATIVE_PROCESS_NONFOLLOWING'
  if($Mode -ceq 'Nominal' -or $Mode -ceq 'LiveRace'){
   if($exitCode -ne 0 -or [IO.Directory]::Exists($app) -or
      $stderr.Contains('TBME_CLEANUP_')){
     throw 'R354_NOMINAL_NATIVE_CLEANUP_NOT_SUCCESSFUL'
   }
   $nominalDeleted=$true
   Check 'ORIGINAL_CLEANUP_NOMINAL_REMOVES_OWNED_TEST_ROOT_AND_NOTHING_ELSE'
 }else{
   $expected=if($Mode -ceq 'RootJunction'){'TBME_CLEANUP_ANCESTOR_REPARSE'}else{'TBME_CLEANUP_CHILD_REPARSE'}
   if($exitCode -eq 0 -or !$stderr.Contains($expected)){
     throw ('R354_ORIGINAL_NATIVE_CLEANUP_JUNCTION_WAS_NOT_REFUSED_'+$Mode+'_exit_'+$exitCode+'_stderr_'+$stderr.Substring(0,[Math]::Min(320,$stderr.Length)))
   }
   if($Mode -ceq 'ChildJunction' -and ![IO.File]::Exists($fixture)){
     throw 'R354_OWNER_TEST_PAYLOAD_DELETED_BEFORE_REFUSAL'
   }
   $junction=if($Mode -ceq 'RootJunction'){$app}else{$child}
   if(([IO.File]::GetAttributes($junction) -band [IO.FileAttributes]::ReparsePoint) -eq 0){
      throw 'R354_JUNCTION_NOT_PRESERVED_ON_REFUSAL'
   }
   $reparseRefused=$true
   Check ('ORIGINAL_CLEANUP_NATIVE_'+$Mode.ToUpperInvariant()+'_JUNCTION_REFUSED_PRE_DELETE')
 }
 if((Hash $canary) -cne $outsideSha){throw 'R354_OUTSIDE_CANARY_WAS_MODIFIED'}
 $canaryUnchanged=$true
 Check 'EXTERNAL_CANARY_SHA_UNCHANGED_AFTER_ORIGINAL_CLEANUP_PROCESS'
 if([IO.Directory]::Exists($protected) -or (IsTaskPresent)){
   throw 'R354_REAL_SENSOR_INSTALLATION_OR_SCHEDULED_TASK_TRIGGERED'
 }
 Check 'NO_PROTECTED_SENSOR_OR_DRIVER_SETUP_EVER_INVOKED'
}catch{
 $failure=$_.Exception.GetType().Name+': '+$_.Exception.Message+' PHASE='+$phase
}finally{
  if($null -ne $actorProcess){
    try{
      if(!$actorProcess.HasExited){$actorProcess.Kill();[void]$actorProcess.WaitForExit(5000)}
    }catch{$failure+=' R355_ACTOR_CHILD_TERMINATION_FAILED'}
    try{$actorProcess.Dispose()}catch{$failure+=' R355_ACTOR_DISPOSE_FAILED'}
    $actorProcess=$null
  }
  if($Mode -ceq 'LiveRace' -and $fixtureCreated){
    # No recursive delete; only files with this exact disposable test name and bytes.
    try{
      if([IO.Directory]::Exists($raceMoved) -and -not [IO.Directory]::Exists($app) -and
         ([IO.File]::GetAttributes($raceMoved) -band [IO.FileAttributes]::ReparsePoint) -eq 0){
         [IO.Directory]::Move($raceMoved,$app)
      }
      if([IO.Directory]::Exists($app) -and
         ([IO.File]::GetAttributes($app) -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
         [IO.Directory]::Exists($stageDir) -and
         ([IO.File]::GetAttributes($stageDir) -band [IO.FileAttributes]::ReparsePoint) -eq 0){
         $members=@([IO.Directory]::GetFileSystemEntries($stageDir))
         if($members.Count -le $filesCount){
           foreach($member in $members){
             $name=[IO.Path]::GetFileName($member)
             if($name -cnotmatch '^[0-9]{5}\.bin$' -or
                ([IO.File]::GetAttributes($member) -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
                [IO.File]::ReadAllText($member) -cne 'R355_ONLY_TEST_DATA'){
                throw 'R355_UNKNOWN_FIXTURE_MEMBER_CLEANUP_REFUSED'
             }
             [IO.File]::Delete($member)
           }
           if(@([IO.Directory]::GetFileSystemEntries($stageDir)).Count -eq 0){
             [IO.Directory]::Delete($stageDir,$false)
           }
         }else{throw 'R355_TOO_MANY_FIXTURE_MEMBERS_NO_CLEANUP'}
      }
    }catch{$failure+=' R355_BOUNDED_STAGE_FIXTURE_RECOVERY_FAILED='+$_.Exception.Message}
  }
  # Remove ONLY exact owned synthetic test fixture created on this hosted runner,
 # and only after confirming the external canary has not changed.
 try{
  if($fixtureCreated -and (Hash $canary) -ceq $outsideSha){
   if($Mode -ceq 'RootJunction' -and [IO.Directory]::Exists($app) -and
      ([IO.File]::GetAttributes($app) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
       [IO.Directory]::Delete($app,$false)
   }
   if($Mode -ceq 'ChildJunction' -and [IO.Directory]::Exists($child) -and
      ([IO.File]::GetAttributes($child) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
       [IO.Directory]::Delete($child,$false)
   }
   if($Mode -cne 'RootJunction' -and [IO.Directory]::Exists($app)){
      if([IO.File]::Exists($fixture) -and (Hash $fixture) -ceq ((
        [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash(
            [Text.Encoding]::UTF8.GetBytes('R354_TEST_USER_DATA_ONLY')))).Replace('-',''))){
          [IO.File]::Delete($fixture)
      }
      if(@([IO.Directory]::GetFileSystemEntries($app)).Count -eq 0){
          [IO.Directory]::Delete($app,$false)
      }
   }
  }
  if([IO.File]::Exists($canary) -and (Hash $canary) -ceq $outsideSha -and
    @([IO.Directory]::GetFileSystemEntries($external)).Count -eq 1){
    [IO.File]::Delete($canary)
    [IO.Directory]::Delete($external,$false)
  }
  $syntheticGone=(![IO.Directory]::Exists($app))
  if($spilloverMoved -and $syntheticGone){
    if(![IO.Directory]::Exists($spillover) -or
       (FingerprintGuestApp $spillover) -cne $spillBefore){
      throw 'R354_SPILL_CHANGED_BEFORE_RESTORE'
    }
    [IO.Directory]::Move($spillover,$app)
    $spillAfter=FingerprintGuestApp $app
    $spilloverRestored=($spillAfter -ceq $spillBefore -and ![IO.Directory]::Exists($spillover))
    if(!$spilloverRestored){throw 'R354_BUILD_APPDATA_NOT_EXACTLY_RESTORED'}
  }
  $testCleaned=($syntheticGone -and
    (!$spilloverMoved -or $spilloverRestored) -and
    ![IO.Directory]::Exists($external) -and ![IO.Directory]::Exists($protected) -and !(IsTaskPresent))
 }catch{$failure+=' R354_TEST_FIXTURE_CLEANUP_FAILED='+$_.Exception.Message}
  $accepted=(!$failure -and $checks.Count -eq 14 -and $testCleaned -and
    $actorDenied -and $actorProofSha -cne '' -and
   $nativeOriginalProcessLaunched -and $canaryUnchanged -and
   ($nominalDeleted -or $reparseRefused))
  $status=if($accepted){'PASS_R355_ORIGINAL_PE_REAL_CLEANUP_CONCURRENT_ROOT_RENAME_DENIED'}else{'FAIL_R355_LIVE_REAL_CLEANUP_UNPROVEN'}
 $receiptData=[ordered]@{
    Schema=1;Revision='R355';Status=$status
   SourceCommit=$env:GITHUB_SHA;Host=$HostLabel;Mode=$Mode
   SetupSHA256=$(if($setup -and [IO.File]::Exists($setup)){Hash $setup}else{'MISSING'})
   RealSetupSourceEmbeddedExact=$sourceExact;SourceUnchanged=$compiledEmbeddedSource
   TrustedProcessInfoTransport=$decodedTransport
   RealExitedParentPid=$parentPid;OriginalNativeCleanupPid=$cleanupPid
   ActualOriginalSetupGeneratedCleanupExecuted=$nativeOriginalProcessLaunched
   CleanupNativeExitCode=$exitCode
   ExpectedJunctionRefusalObserved=$reparseRefused;NormalSyntheticUninstallRemoved=$nominalDeleted
   ExternalCanarySHA256=$outsideSha;CanaryUnchanged=$canaryUnchanged
    ScopedTestCleanupComplete=$testCleaned
    R355OnlySyntheticOwnedFilesCreated=$filesCount
   PreBuildGuestAppAbsent=$true
   BuildGeneratedAppRootSeen=$fresh.AppDir
   BuildGeneratedRootBackupRestored=$spilloverRestored
   BuildGeneratedRootShaBefore=$spillBefore
   BuildGeneratedRootShaAfter=$spillAfter
   SyntheticFixtureRootFullyRemoved=$syntheticGone
   GuestFreshness=$fresh
   UserOwnerComputerTouched=$false;DriverOrBrokerSetupExecuted=$false
    InteractiveUacTested=$false;ConcurrentPathSwapTested=$true
    SeparateWindowsActorPid=$actorPid;SeparateActorReceiptSHA256=$actorProofSha
    RealConcurrentRenameRefusedDuringOriginalCleanup=$actorDenied
    RealConcurrentRenameAttempts=$actorAttempts
    FirstDeletedOwnedFileWitnessIndex=$actorObservedDeleted
    ActorExitCode=$actorExit
    NoForeignOrOwnerFilesAltered=$canaryUnchanged
   Checks=@($checks);Failure=$failure
 }
 try{[IO.File]::WriteAllText($receipt,($receiptData|ConvertTo-Json -Depth 8),
   [Text.UTF8Encoding]::new($false))}catch{$failure+=' RECEIPT_WRITE_FAILED'}
 Write-Output ('R354_NATIVE_STATUS='+$status+' CHECKS='+$checks.Count+' EXIT='+$exitCode)
 if($failure){Write-Output ('R354_FAILURE='+$failure)}
}
if($failure){throw ('R354_REAL_DEFERRED_CLEANUP_FAILED '+$failure)}
