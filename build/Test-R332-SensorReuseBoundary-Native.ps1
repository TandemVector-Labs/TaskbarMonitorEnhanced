[CmdletBinding()]
param(
 [string]$SetupPath='',
 [switch]$HostedGuest,
 [ValidateSet('LOCAL','A','B')][string]$HostLabel='LOCAL'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($SetupPath)) {
 $SetupPath=Join-Path $PSScriptRoot '_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
}
if($PSVersionTable.PSEdition -cne 'Desktop' -or !(Test-Path -LiteralPath $SetupPath -PathType Leaf)) {
 throw 'R332_EXACT_WINDOWS_NETFRAMEWORK_SETUP_REQUIRED'
}
$setupPath=(Resolve-Path -LiteralPath $SetupPath).Path
$assembly=[Reflection.Assembly]::LoadFrom($setupPath)
$type=$assembly.GetType('SetupProgram',$true)
$method=$type.GetMethod('ValidatedSensorReuseRoot',[Reflection.BindingFlags]'NonPublic,Static')
$reuse=$type.GetMethod('TryReuseCompatibleSensorLayer',[Reflection.BindingFlags]'NonPublic,Static')
if(!$method -or !$reuse){throw 'R332_REAL_COMPILED_PE_MISSING_BOTH_METHODS'}
$resource=$assembly.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced_Setup.cs')
if(!$resource){throw 'R332_PE_SOURCE_RESOURCE_MISSING'}
$reader=[IO.StreamReader]::new($resource)
try{$embeddedSource=$reader.ReadToEnd()}finally{$reader.Dispose()}
$source=[IO.File]::ReadAllText((Resolve-Path (Join-Path $PSScriptRoot '..\installer\TaskbarMonitorEnhanced_Setup.cs')).Path)
$normalize={param($x) $x.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $normalize $embeddedSource) -cne (& $normalize $source)){
 throw 'R332_COMPILED_SOURCE_NOT_EQUAL_CANONICAL_CODE'
}
$checks=[Collections.Generic.List[string]]::new()
function Pass([string]$name){
 $script:checks.Add($name)
 Write-Output ('PASS '+$name)
}
function Invoke-Validated([string]$pf,[string]$local,[string]$profile){
 $a=New-Object 'object[]' 3
 $a[0]=[string]$pf; $a[1]=[string]$local; $a[2]=[string]$profile
 return [string]$method.Invoke($null,$a)
}
function Expect-Fail([string]$label,[string]$pf,[string]$local,[string]$profile){
 $refused=$false
 try{
  $actual=Invoke-Validated $pf $local $profile
  throw ('R332_UNEXPECTED_ACCEPT_'+$label+'='+$actual)
 }catch {
  $e=$_.Exception
  while($null -ne $e.InnerException){$e=$e.InnerException}
  $message=$e.Message
  if($message -match '^R332_UNEXPECTED_ACCEPT_'){throw $message}
  if($message -notmatch '(?i)(root|UNC|profile|canonical|reparse|unavailable|ProgramFiles|escaped|not.*folder)'){
   throw ('R332_WRONG_FAILURE_REASON_'+$label+': '+$message)
  }
  $refused=$true
 }
 if(!$refused){throw ('R332_NEGATIVE_NOT_REFUSED_'+$label)}
 Pass $label
}
function MoveJunctionCheck([string]$label,[string]$victim,[string]$redirect,[string]$pf,[string]$local,[string]$profile){
 if(![IO.Directory]::Exists($victim) -or
    ([IO.File]::GetAttributes($victim) -band [IO.FileAttributes]::ReparsePoint)){
   throw ('R332_NOT_AN_OWNED_TEST_DIRECTORY_'+$label)
 }
 $retired=$victim+'_retired'
 if([IO.Directory]::Exists($retired)){throw ('R332_ALREADY_RETIRED_'+$label)}
 [IO.Directory]::Move($victim,$retired)
 $isLink=$false
 try{
  New-Item -ItemType Junction -Path $victim -Target $redirect -ErrorAction Stop|Out-Null
  $isLink=$true
  Expect-Fail $label $pf $local $profile
 }finally{
  if($isLink -and [IO.Directory]::Exists($victim)){[IO.Directory]::Delete($victim)}
  if([IO.Directory]::Exists($retired)){[IO.Directory]::Move($retired,$victim)}
 }
}
Pass 'REAL_SETUP_EMBEDDED_SOURCE_EXACT'
$call='string sensorRoot=ValidatedSensorReuseRoot('
if(([regex]::Matches($source,[regex]::Escape($call))).Count -ne 1 -or
   !$source.Contains('Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles)') -or
   !$source.Contains('CheckRootAncestorsNoReparse(Path.Combine(sensorRoot,"TaskbarMonitorSensorBroker.exe"))') -or
   !$source.Contains('CheckRootAncestorsNoReparse(Path.Combine(userRoot,"sensor_supervisor_state.json"))')){
 throw 'R332_REUSE_PRECHECK_NOT_BOUND_BEFORE_FILE_HASHES'
}
Pass 'REUSE_PRECHECK_BOUND_BEFORE_HASH_AND_STATE_READING'
$base=Join-Path ([IO.Path]::GetTempPath()) ('tbme_r332_sensor_reuse_'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($base)|Out-Null
$profile=Join-Path $base 'fake profile & literal $test'
$local=Join-Path $profile 'AppData\Local'
$userApp=Join-Path $local 'TaskbarMonitorEnhanced'
$pf=Join-Path $base 'Program Files & literal $test'
$pfProduct=Join-Path $pf 'TaskbarMonitorEnhanced'
$sensor=Join-Path $pfProduct 'SensorBroker'
$broker=Join-Path $sensor 'TaskbarMonitorSensorBroker.exe'
$supervisor=Join-Path $sensor 'TaskbarMonitorSensorSupervisor.exe'
$state=Join-Path $userApp 'sensor_supervisor_state.json'
$external=Join-Path $base 'foreign-canary'
[IO.Directory]::CreateDirectory($userApp)|Out-Null
[IO.Directory]::CreateDirectory($sensor)|Out-Null
[IO.Directory]::CreateDirectory($external)|Out-Null
$canary=Join-Path $external 'DO_NOT_MODIFY.txt'
[IO.File]::WriteAllText($canary,'R332_FOREIGN_PRESERVE')
[IO.File]::WriteAllText($broker,'R332_FAKE_BROKER_NOT_RUN')
[IO.File]::WriteAllText($supervisor,'R332_FAKE_SUPERVISOR_NOT_RUN')
[IO.File]::WriteAllText($state,'{"status":"FAKE_NOT_REUSED"}')
try{
 $got=Invoke-Validated $pf $local $profile
 if(-not [string]::Equals($got,[IO.Path]::GetFullPath($sensor),[StringComparison]::OrdinalIgnoreCase)){
  throw ('R332_POSITIVE_SYNTHETIC_EXACT_ROOT_MISMATCH_'+$got)
 }
 Pass 'CANONICAL_FAKE_SAME_USER_PROFILE_AND_PROGRAMFILES_ACCEPTED'
 $knownPF=[Environment]::GetFolderPath('ProgramFiles')
 $oldPF=$env:ProgramFiles
 try{
  $env:ProgramFiles=Join-Path $base 'attacker-supplied-env-ProgramFiles'
  if(-not [string]::Equals([Environment]::GetFolderPath('ProgramFiles'),$knownPF,
      [StringComparison]::OrdinalIgnoreCase)){
   throw 'R332_ENV_SPOOF_CHANGED_OS_KNOWN_PROGRAMFILES'
  }
  Pass 'OS_KNOWN_PROGRAMFILES_UNAFFECTED_BY_ENVIRONMENT_SPOOF'
 }finally{$env:ProgramFiles=$oldPF}
 Expect-Fail 'EMPTY_PROGRAMFILES_REFUSED' '' $local $profile
 Expect-Fail 'RELATIVE_PROGRAMFILES_REFUSED' 'Program Files' $local $profile
 Expect-Fail 'UNC_PROGRAMFILES_REFUSED' '\\foreign.invalid\programs' $local $profile
 Expect-Fail 'DRIVE_ROOT_PROGRAMFILES_REFUSED' ([IO.Path]::GetPathRoot($base)) $local $profile
 Expect-Fail 'MISMATCHED_USER_LOCAL_PROFILE_REFUSED' $pf (Join-Path $base 'different\AppData\Local') $profile
 Expect-Fail 'UNC_PROFILE_REFUSED' $pf '\\foreign.invalid\user\AppData\Local' '\\foreign.invalid\user'
 MoveJunctionCheck 'PROGRAMFILES_ROOT_JUNCTION_REFUSED' $pf $external $pf $local $profile
 MoveJunctionCheck 'PROGRAMFILES_PRODUCT_JUNCTION_REFUSED' $pfProduct $external $pf $local $profile
 MoveJunctionCheck 'SENSORBROKER_ROOT_JUNCTION_REFUSED' $sensor $external $pf $local $profile
 # A directory junction at the exact .exe leaf models an EXE-name reparse point;
 # no file symlink privileges or protected ProgramFiles modifications required.
 [IO.File]::Delete($broker)
 [IO.Directory]::CreateDirectory($external)|Out-Null
 $brokerLinked=$false
 try{
  New-Item -ItemType Junction -Path $broker -Target $external -ErrorAction Stop|Out-Null
  $brokerLinked=$true
  Expect-Fail 'BROKER_EXE_LEAF_REPARSE_REFUSED' $pf $local $profile
 }finally{
  if($brokerLinked -and [IO.Directory]::Exists($broker)){[IO.Directory]::Delete($broker)}
  [IO.File]::WriteAllText($broker,'R332_FAKE_BROKER_NOT_RUN')
 }
 [IO.File]::Delete($supervisor)
 $supervisorLinked=$false
 try{
  New-Item -ItemType Junction -Path $supervisor -Target $external -ErrorAction Stop|Out-Null
  $supervisorLinked=$true
  Expect-Fail 'SUPERVISOR_EXE_LEAF_REPARSE_REFUSED' $pf $local $profile
 }finally{
  if($supervisorLinked -and [IO.Directory]::Exists($supervisor)){[IO.Directory]::Delete($supervisor)}
  [IO.File]::WriteAllText($supervisor,'R332_FAKE_SUPERVISOR_NOT_RUN')
 }
 MoveJunctionCheck 'USER_APPROOT_JUNCTION_REFUSED' $userApp $external $pf $local $profile
 [IO.File]::Delete($state)
 $stateLinked=$false
 try{
  New-Item -ItemType Junction -Path $state -Target $external -ErrorAction Stop|Out-Null
  $stateLinked=$true
  Expect-Fail 'USER_HEALTH_STATE_LEAF_REPARSE_REFUSED' $pf $local $profile
 }finally{
  if($stateLinked -and [IO.Directory]::Exists($state)){[IO.Directory]::Delete($state)}
  [IO.File]::WriteAllText($state,'{"status":"FAKE_NOT_REUSED"}')
 }
 if([IO.File]::ReadAllText($canary) -cne 'R332_FOREIGN_PRESERVE' -or
    @([IO.Directory]::GetFileSystemEntries($external)).Count -ne 1){
  throw 'R332_FOREIGN_CANARY_OR_EXTERNAL_DIRECTORY_CHANGED'
 }
 Pass 'EXTERNAL_CANARY_PRESERVED_AFTER_ALL_NEGATIVES'
 if($checks.Count -ne 18){throw ('R332_NATIVE_EXPECTED_16_GOT_'+$checks.Count)}
 Write-Output ('R332_CANONICAL_SENSOR_REUSE_NET48_PASS='+$checks.Count+'/18')
 if(!$HostedGuest){return}
 if($HostLabel -cnotin @('A','B') -or $env:GITHUB_ACTIONS -cne 'true' -or
    $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or $env:RUNNER_OS -cne 'Windows' -or
    $env:GITHUB_SHA -cnotmatch '^[a-f0-9]{40}$' -or $env:GITHUB_RUN_ID -cnotmatch '^\d+$'){
  throw 'R332_HOSTED_GUEST_ENVIRONMENT_NOT_DISPOSABLE'
 }
 $receiptRoot=Join-Path $env:RUNNER_TEMP ('R332_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
 if([IO.Directory]::Exists($receiptRoot)){throw 'R332_GUEST_RECEIPT_ALREADY_EXISTS'}
 [IO.Directory]::CreateDirectory($receiptRoot)|Out-Null
 $evidence=[ordered]@{
  Schema=1
  Revision='R332'
  Status='PASS_CANONICAL_SENSOR_REUSE_JUNCTION_FAIL_CLOSED'
  Host=$HostLabel
  SourceCommit=$env:GITHUB_SHA
  SetupSHA256=(Get-FileHash $setupPath -Algorithm SHA256).Hash
  Checks=@($checks.ToArray())
  RealCompiledNetFrameworkSetupLoaded=$true
  ProgramFilesRealRootModified=$false
  ActualSensorHelperElevated=$false
  OwnerInstalledProgramChanged=$false
  ExternalCanaryPreserved=$true
  AtomicReparseRaceProven=$false
  SecurityFinalAccepted=$false
 }
 $p=Join-Path $receiptRoot 'R332_SENSOR_REUSE_BOUNDARY_RECEIPT.json'
 [IO.File]::WriteAllText($p,($evidence|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
 Write-Output ('R332_GUEST_TYPED_RECEIPT_SHA256='+(Get-FileHash $p -Algorithm SHA256).Hash)
}finally{
 if([IO.Directory]::Exists($base) -and
    [IO.Path]::GetFileName($base).StartsWith('tbme_r332_sensor_reuse_',[StringComparison]::Ordinal)){
  $links=@(Get-ChildItem $base -Recurse -Force -ErrorAction SilentlyContinue |
         Where-Object {($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0})
  if($links.Count -ne 0){throw 'R332_TEST_SANDBOX_HAS_REPARSE_POINTS_REFUSE_CLEANUP'}
  [IO.Directory]::Delete($base,$true)
 }
}
