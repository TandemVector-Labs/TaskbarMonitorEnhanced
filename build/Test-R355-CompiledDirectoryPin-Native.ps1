[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$SourceRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
 $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
 $env:RUNNER_OS -cne 'Windows' -or
 $env:GITHUB_REPOSITORY -cne 'GOD13emad/TaskbarMonitorEnhanced' -or
 $env:GITHUB_REF -cne 'refs/heads/audit/r355-deferred-cleanup-directory-pins' -or
 $env:COMPUTERNAME -match '(?i)EMAD-PC|ALIEMAD|SAEID|LAPTOP' -or
 $env:GITHUB_SHA -cnotmatch '^[a-f0-9]{40}$' -or
 (git -C $SourceRoot rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){
 throw 'R355_ONLY_FRESH_DISPOSABLE_GITHUB_WINDOWS'
}
$root=Join-Path $env:RUNNER_TEMP ('R355_DIRECTORY_PIN_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$testDir=Join-Path $root 'owner-test-only'
$moved=Join-Path $root 'owner-moved'
$link=Join-Path $root 'owner-junction'
$receipt=Join-Path $root 'R355_PRODUCTION_PIN_RECEIPT.json'
$setup=Join-Path $SourceRoot 'build\_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$checks=[Collections.Generic.List[string]]::new()
$lease=$null;$started=$false;$canary='';$sha='';$deniedCode=-1;$releasedCode=-1
function Pass([string]$x){$script:checks.Add($x);Write-Output ('PASS '+$x)}
function Hash([string]$f){return (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash}
if([IO.Directory]::Exists($root) -or ![IO.File]::Exists($setup) -or
 [IO.Directory]::Exists((Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'TaskbarMonitorEnhanced'))){
 throw 'R355_GUEST_SCOPE_NOT_FRESH_OR_SETUP_MISSING'
}
[IO.Directory]::CreateDirectory($root)|Out-Null
try{
 $assembly=[Reflection.Assembly]::LoadFrom($setup)
 $sourceReader=[IO.StreamReader]::new($assembly.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced_Setup.cs'))
 try{$embedded=$sourceReader.ReadToEnd()}finally{$sourceReader.Dispose()}
 $text=[IO.File]::ReadAllText((Join-Path $SourceRoot 'installer\TaskbarMonitorEnhanced_Setup.cs'))
 $norm={param([string]$s) $s.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
 if((& $norm $embedded) -cne (& $norm $text)){throw 'R355_ORIGINAL_PE_EMBEDDED_SOURCE_NOT_EXACT'}
 Pass 'COMPILED_PRODUCTION_SETUP_PE_EMBEDS_EXACT_NEW_DEFENSIVE_SOURCE'
 $type=$assembly.GetType('SetupProgram',$true)
 $flags=[Reflection.BindingFlags]'Static,NonPublic'
 $build=$type.GetMethod('BuildDeferredUninstallCleanupProcessInfo',$flags)
 $app=$type.GetProperty('AppRoot',$flags)
 if(!$build -or !$app){throw 'R355_ORIGINAL_FACTORY_ABSENT'}
 $known=[string]$app.GetValue($null,$null)
 $proc=[Diagnostics.Process]::GetCurrentProcess()
 try{$pidSelf=$proc.Id;$ticks=$proc.StartTime.ToUniversalTime().Ticks}finally{$proc.Dispose()}
 $nativeArgs=[object[]]::new(3)
 $nativeArgs[0]=([string]$known).PSObject.BaseObject
 $nativeArgs[1]=([int]$pidSelf).PSObject.BaseObject
 $nativeArgs[2]=([long]$ticks).PSObject.BaseObject
 $psi=[Diagnostics.ProcessStartInfo]$build.Invoke($null,$nativeArgs)
 $prefix='-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand '
 if(!$psi.Arguments.StartsWith($prefix,[StringComparison]::Ordinal) -or
    $psi.Arguments.Length -gt 22080 -or
    $psi.UseShellExecute -ne $false -or
    ![string]::Equals($psi.FileName,
      (Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'),
      [StringComparison]::OrdinalIgnoreCase)){
   throw 'R355_PRODUCTION_CLEANUP_COMMAND_CHANGED_INSECURELY'
 }
 Pass 'REAL_PRODUCTION_DEFERRED_PROCESSINFO_HOST_AND_ENCODEDCOMMAND_BOUNDS'
 $code=[Text.Encoding]::Unicode.GetString(
   [Convert]::FromBase64String($psi.Arguments.Substring($prefix.Length)))
 $tokens=$null;$parseErr=$null
 [Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$parseErr)|Out-Null
 if(@($parseErr).Count){throw 'R355_REAL_ENCODEDCOMMAND_POWERSHELL51_PARSE_FAILED'}
 $m=[regex]::Matches($code,"(?ms)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@")
 if($m.Count -ne 1){throw 'R355_REAL_NATIVE_CLASS_NOT_UNIQUE_IN_PE'}
 Add-Type -TypeDefinition $m[0].Groups[1].Value -ErrorAction Stop
 Pass 'ACTUAL_COMPILED_DEFERRED_SCRIPT_PS51_AND_NATIVE_CSHARP_COMPILE_PASS'
 [IO.Directory]::CreateDirectory($testDir)|Out-Null
 $canary=Join-Path $testDir 'R355_TEST_ONLY_CANARY.txt'
 [IO.File]::WriteAllText($canary,'R355_TEST_PRIVATE_ONLY',[Text.UTF8Encoding]::new($false))
 $sha=Hash $canary
 $lease=[TBMEDeferredDirectoryLeaseSet]::new()
 $lease.Pin($testDir)
 $lease.Pin($testDir)
 $pathBlob=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($testDir))
 $moveBlob=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($moved))
 $actorCode='$a=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+$pathBlob+'''));'+
 '$b=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('''+$moveBlob+'''));'+
 'try{[IO.Directory]::Move($a,$b);[IO.Directory]::Move($b,$a);exit 61}'+
 'catch [IO.IOException]{exit 32}catch [UnauthorizedAccessException]{exit 5}'
 $actorTokens=$null;$actorErrors=$null
 [Management.Automation.Language.Parser]::ParseInput($actorCode,[ref]$actorTokens,[ref]$actorErrors)|Out-Null
 if(@($actorErrors).Count){throw 'R355_ACTOR_CODE_GENERATION_PARSE_FAILED'}
 $enc=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($actorCode))
 $native=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
 $actor1=[Diagnostics.Process]::Start($native,('-NoProfile -NonInteractive -EncodedCommand '+$enc))
 if(!$actor1){throw 'R355_SEPARATE_PROCESS_NOT_STARTED'}
 try{
  if(!$actor1.WaitForExit(16000)){throw 'R355_SEPARATE_ACTOR_TIMEOUT'}
  $deniedCode=$actor1.ExitCode
 }finally{$actor1.Dispose()}
 if($deniedCode -ne 32 -and $deniedCode -ne 5){throw ('R355_RENAME_NOT_DENIED_WHILE_PINN_'+$deniedCode)}
 if([IO.Directory]::Exists($moved) -or (Hash $canary) -cne $sha){
  throw 'R355_ACTOR_CHANGED_PINNED_ROOT_OR_CANARY'
 }
 Pass 'SEPARATE_NATIVE_WINDOWS_PROCESS_RENAME_REFUSED_DURING_DIRECTORY_LEASE'
 $lease.Release($testDir)
 $actor2=[Diagnostics.Process]::Start($native,('-NoProfile -NonInteractive -EncodedCommand '+$enc))
 if(!$actor2){throw 'R355_SECOND_ACTOR_NOT_STARTED'}
 try{
  if(!$actor2.WaitForExit(16000)){throw 'R355_SECOND_ACTOR_TIMEOUT'}
  $releasedCode=$actor2.ExitCode
 }finally{$actor2.Dispose()}
 if($releasedCode -ne 61 -or ![IO.Directory]::Exists($testDir) -or (Hash $canary) -cne $sha){
  throw ('R355_DIRECTORY_RENAME_NOT_ALLOWED_AFTER_LEASE_RELEASE_'+$releasedCode)
 }
 Pass 'SAME_ACTOR_RENAME_ALLOWED_AND_RESTORED_AFTER_LEASE_RELEASE'
 New-Item -ItemType Junction -Path $link -Target $testDir -ErrorAction Stop|Out-Null
 if(([IO.File]::GetAttributes($link) -band [IO.FileAttributes]::ReparsePoint) -eq 0){
  throw 'R355_TEST_JUNCTION_CREATION_NOT_GENUINE'
 }
 $denied=$false
 try{$lease.Pin($link)}catch [IO.IOException]{$denied=$true}
 if(!$denied -or (Hash $canary) -cne $sha){throw 'R355_LEASE_FAILOPEN_ON_JUNCTION'}
 Pass 'SAME_PRODUCTION_LEASE_CLASS_REFUSED_REAL_TEST_JUNCTION'
 $started=$true
}finally{
 if($lease){$lease.Dispose()}
 if([IO.Directory]::Exists($link) -and
    ([IO.File]::GetAttributes($link) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
  [IO.Directory]::Delete($link,$false)
 }
 if([IO.File]::Exists($canary) -and [IO.File]::ReadAllText($canary) -ceq 'R355_TEST_PRIVATE_ONLY'){
  [IO.File]::Delete($canary)
 }
 if([IO.Directory]::Exists($testDir) -and
    @([IO.Directory]::GetFileSystemEntries($testDir)).Count -eq 0){
  [IO.Directory]::Delete($testDir,$false)
 }
}
if(!$started -or $checks.Count -ne 6 -or [IO.Directory]::Exists($testDir) -or
   [IO.Directory]::Exists($moved) -or [IO.Directory]::Exists($link)){
 throw 'R355_BOUNDED_COMPILED_NATIVE_PROOF_NOT_ACCEPTED'
}
$record=[ordered]@{
 Schema=1;Revision='R355';Status='PASS_SCOPED_ORIGINAL_COMPILED_PE_DIRECTORY_PIN_NATIVE'
 SourceCommit=$env:GITHUB_SHA;Host=$HostLabel
 SetupSHA256=Hash $setup;Tests=@($checks)
 ParentPid=$PID;SeparateNativeActorDeniedCode=$deniedCode
 SeparateNativeActorAllowedCode=$releasedCode
 ExactCompiledProductionNativeClassUsed=$true
 ExternalTestCanaryUntouched=$true
 OwnerAppOrSensorModified=$false
 ActualConcurrentUninstallRaceTested=$false
 InteractiveUacTested=$false
 WholeSecurityAccepted=$false
}
[IO.File]::WriteAllText($receipt,($record|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
'R355_COMPILED_NATIVE_LEASE_PASS_HOST='+$HostLabel+' CHECKS='+$checks.Count
