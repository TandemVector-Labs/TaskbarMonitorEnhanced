[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateSet('baseline','candidate')][string]$Variant,
  [Parameter(Mandatory=$true)][string]$SupervisorPath,
  [Parameter(Mandatory=$true)][string]$SourceRoot,
  [ValidateSet('LOCAL','A','B')][string]$HostLabel='LOCAL',
  [switch]$HostedGuest
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop'){throw 'R338_WINDOWS_POWERSHELL_51_REQUIRED'}
if($HostedGuest -and ($env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or $HostLabel -eq 'LOCAL' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC|ALIEMAD|SAEID')){
  throw 'R338_GUEST_RUNNER_IDENTITY_FAIL_CLOSED'
}
function FileHash([string]$file) {
  return (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
}
$expectedCommit=if($Variant -ceq 'baseline'){
  '997c6f349fa64cfe6385113a9ede46d35479cc7a'
}else{
  # Candidate must match a pinned workflow checkout; caller validates its SHA.
  (git -C $SourceRoot rev-parse HEAD).Trim()
}
if((git -C $SourceRoot rev-parse HEAD).Trim() -cne $expectedCommit){
  throw 'R338_EXACT_SOURCE_HEAD_MISMATCH'
}
if(!(Test-Path -LiteralPath $SupervisorPath -PathType Leaf)){
  throw 'R338_COMPILED_SUPERVISOR_MISSING'
}
$assembly=[Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $SupervisorPath).Path)
$type=$assembly.GetType('TaskbarMonitorSensorSupervisor',$true)
$flags=[Reflection.BindingFlags]'Static,NonPublic'
$parse=$type.GetMethod('ParseArgs',$flags)
$trusted=$type.GetMethod('TrustedWorkerPaths',$flags)
$brokerField=$type.GetField('BrokerPath',$flags)
if(!$parse -or !$brokerField){throw 'R338_REAL_COMPILED_ENTRYPOINT_MISSING'}
$checks=[Collections.Generic.List[string]]::new()
function Pass([string]$label) {
  $script:checks.Add($label)
  Write-Output ('PASS '+$label)
}
function Invoke-Parse([string[]]$items){
  $values=New-Object 'object[]' 1
  $values[0]=$items
  return [bool]$parse.Invoke($null,$values)
}
function Invoke-Trusted([string[]]$parts){
  $values=New-Object 'object[]' 6
  for($i=0;$i -lt $values.Length;$i++){$values[$i]=$parts[$i]}
  return [bool]$trusted.Invoke($null,$values)
}
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('tbme_r338_'+$HostLabel+'_'+[Guid]::NewGuid().ToString('N'))
$reportRoot=if($HostedGuest){Join-Path $env:RUNNER_TEMP ('R338_'+$HostLabel+'_'+$Variant+'_'+$env:GITHUB_RUN_ID)}else{''}
if($HostedGuest){
  if([IO.Directory]::Exists($reportRoot)){throw 'R338_DUPLICATE_HOSTED_RECEIPT_ROOT'}
  [void][IO.Directory]::CreateDirectory($reportRoot)
}
$receipt=if($HostedGuest){Join-Path $reportRoot 'R338_SUPERVISOR_ARG_TRUST.json'}else{''}
$failure=''
$canaryHash=''
$junctionCreated=$false
$brokerDir=''
$canary=''
try {
  [void][IO.Directory]::CreateDirectory($testRoot)
  $program=Join-Path $testRoot 'Program Files'
  $brokerDir=Join-Path $program 'TaskbarMonitorEnhanced\SensorBroker'
  $profile=Join-Path $testRoot 'Profile'
  $local=Join-Path $profile 'AppData\Local'
  $app=Join-Path $local 'TaskbarMonitorEnhanced'
  $foreign=Join-Path $testRoot 'foreign-untrusted'
  [void][IO.Directory]::CreateDirectory($brokerDir)
  [void][IO.Directory]::CreateDirectory($app)
  [void][IO.Directory]::CreateDirectory($foreign)
  $broker=Join-Path $brokerDir 'TaskbarMonitorSensorBroker.exe'
  $output=Join-Path $app 'cpu_temp_broker.json'
  $canary=Join-Path $foreign 'CANARY_NEVER_EXECUTED.txt'
  [IO.File]::WriteAllText($broker,'R338_MOCK_EXE_NEVER_EXECUTED',[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($canary,'R338_UNRELATED_FOREIGN_CANARY',[Text.UTF8Encoding]::new($false))
  $canaryHash=FileHash $canary
  $evil=Join-Path $foreign 'foreign.exe'
  $evilOutput=Join-Path $foreign 'rogue.json'
  if($Variant -ceq 'baseline'){
    if($trusted){throw 'R338_BASELINE_UNEXPECTED_TRUSTED_FUNCTION'}
    if(!(Invoke-Parse ([string[]]@('--broker',$evil,'--output',$evilOutput)))){
      throw 'R338_OLD_PARSER_DID_NOT_ACCEPT_ARBITRARY_PATHS'
    }
    Pass 'BASELINE_COMPILED_SUPERVISOR_ACCEPTS_FOREIGN_EXE_AND_OUTPUT_WITHOUT_EXECUTING'
    if(!(Invoke-Parse ([string[]]@('--broker',$evil,'--output',$evilOutput,'--ignored','x')))){
      throw 'R338_OLD_PARSER_DID_NOT_IGNORE_EXTRA_FLAGS'
    }
    Pass 'BASELINE_ACCEPTS_UNEXPECTED_EXTRA_FLAGS'
  }else{
    if(!$trusted){throw 'R338_TRUSTED_FUNCTION_NOT_COMPILED'}
    Pass 'CANDIDATE_COMPILED_SUPERVISOR_EXPOSES_TRUST_CHECK'
    $argsGood=[string[]]@($broker,$output,$brokerDir,$program,$profile,$local)
    if(!(Invoke-Trusted $argsGood)){throw 'R338_CANONICAL_SANDBOX_POSITIVE_REFUSED'}
    Pass 'SANDBOX_REAL_PATHS_CANONICAL_KNOWNFOLDERS_ACCEPTED'
    $beforeField=[string]$brokerField.GetValue($null)
    $badArgs=[string[]]@('--broker',$evil,'--output',$evilOutput)
    if(Invoke-Parse $badArgs){throw 'R338_FOREIGN_PROCESS_START_PATH_ACCEPTED'}
    if([string]$brokerField.GetValue($null) -cne $beforeField){
      throw 'R338_INVALID_PROCESS_ARGUMENT_PARTIALLY_MUTATED_GLOBAL_PATH'
    }
    Pass 'COMPILLED_PRODUCTION_PARSE_REFUSES_FOREIGN_EXECUTABLE_PRELAUNCH'
    $malformed=@(
      [pscustomobject]@{Argv=[string[]]@('--broker',$evil,'--output',$output)},
      [pscustomobject]@{Argv=[string[]]@('--broker',$broker,'--output',$evilOutput)},
      [pscustomobject]@{Argv=[string[]]@('--broker',$broker,'--broker',$evil)},
      [pscustomobject]@{Argv=[string[]]@('--broker',$broker,'--output',$output,'--ignored','x')},
      [pscustomobject]@{Argv=[string[]]@('--broker',$broker,'--output')},
      [pscustomobject]@{Argv=[string[]]@('--broker',$broker,'--output',($output+'";Write-Host INJECTED'))},
      [pscustomobject]@{Argv=[string[]]@('--broker',$broker,'--output',('X'*4097))}
    )
    foreach($case in $malformed){
      if(Invoke-Parse $case.Argv){throw 'R338_BAD_REAL_PROCESS_ARG_ACCEPTED'}
    }
    Pass 'REAL_PARSER_NEGATIVES_FOREIGN_DUPLICATE_UNKNOWN_TRUNCATED_HOSTILE_OVERLONG'
    if(Invoke-Trusted ([string[]]@($evil,$output,$brokerDir,$program,$profile,$local))){
      throw 'R338_TRUST_ALLOW_FOREIGN_BROKER'
    }
    Pass 'TRUST_CHECK_REFUSES_FOREIGN_BROKER_PATH'
    if(Invoke-Trusted ([string[]]@($broker,$evilOutput,$brokerDir,$program,$profile,$local))){
      throw 'R338_TRUST_ALLOW_FOREIGN_OUTPUT'
    }
    Pass 'TRUST_CHECK_REFUSES_FOREIGN_TELEMETRY_OUTPUT'
    if(Invoke-Trusted ([string[]]@($broker,$output,$foreign,$program,$profile,$local))){
      throw 'R338_TRUST_ALLOW_FOREIGN_IMAGE_DIRECTORY'
    }
    Pass 'TRUST_CHECK_REFUSES_IMAGE_OUTSIDE_PROGRAMFILES_SENSOR_ROOT'
    if(Invoke-Trusted ([string[]]@($broker,$output,$brokerDir,$program,$profile,$foreign))){
      throw 'R338_TRUST_ALLOW_NONLOCAL_PROFILE_DIRECTORY'
    }
    Pass 'TRUST_CHECK_REFUSES_NONCANONICAL_PROFILE_LOCALAPPDATA'
    $escapedOutput=Join-Path $foreign 'escape\cpu_temp_broker.json'
    if(Invoke-Trusted ([string[]]@($broker,$escapedOutput,$brokerDir,$program,$profile,$local))){
      throw 'R338_TRUST_ALLOW_PARENT_ESCAPE'
    }
    Pass 'TRUST_CHECK_REFUSES_OUTPUT_PARENT_ESCAPE'
    $brokerBackup=$brokerDir+'_original'
    [IO.Directory]::Move($brokerDir,$brokerBackup)
    $outsideBroker=Join-Path $foreign 'TaskbarMonitorSensorBroker.exe'
    [IO.File]::WriteAllText($outsideBroker,'R338_FOREIGN_EXE_MARKER',[Text.UTF8Encoding]::new($false))
    try {
      New-Item -ItemType Junction -Path $brokerDir -Target $foreign -ErrorAction Stop|Out-Null
      $junctionCreated=$true
      if(Invoke-Trusted ([string[]]@($broker,$output,$brokerDir,$program,$profile,$local))){
        throw 'R338_PROTECTED_BROKER_REPARSE_NOT_REJECTED'
      }
      Pass 'TRUST_CHECK_REJECTS_REAL_WINDOWS_BROKER_JUNCTION'
    } finally {
      if($junctionCreated -and [IO.Directory]::Exists($brokerDir)){
        $att=[IO.File]::GetAttributes($brokerDir)
        if(($att -band [IO.FileAttributes]::ReparsePoint) -eq 0){
          throw 'R338_BROKER_LINK_CHANGED_BEFORE_CLEANUP'
        }
        [IO.Directory]::Delete($brokerDir,$false)
        $junctionCreated=$false
      }
      [IO.Directory]::Move($brokerBackup,$brokerDir)
    }
    if(!(Invoke-Trusted $argsGood)){throw 'R338_POSITIVE_NOT_RECOVERED_AFTER_JUNCTION'}
    Pass 'VALID_PATHS_REACCEPTED_AFTER_REAL_JUNCTION_REMOVAL'
  }
  if((FileHash $canary) -cne $canaryHash){throw 'R338_FOREIGN_CANARY_MODIFIED'}
  Pass 'FOREIGN_CANARY_BYTE_IDENTICAL_NO_PROCESS_STARTED'
} catch {
  $failure=$_.Exception.ToString()
} finally {
  $status=if(!$failure){if($Variant -ceq 'baseline'){
    'PASS_REPRODUCED_OLD_SUPERVISOR_ARG_ACCEPTANCE'
  }else{
    'PASS_CANDIDATE_SUPERVISOR_TRUST_BOUNDARY'
  }}else{'FAIL'}
  if($HostedGuest){
    $result=[ordered]@{
      Schema=1;Revision='R338';Host=$HostLabel;Variant=$Variant;
      SourceCommit=(git -C $SourceRoot rev-parse HEAD).Trim()
      SupervisorSHA256=FileHash $SupervisorPath
      Status=$status
      ActualOriginalElevatedSupervisorStarted=$false
      ActualUacConsentPromptTested=$false
      ProtectedProgramFilesModified=$false
      OriginalOwnerHostTouched=$false
      AnyBrokerExeStarted=$false
      Checks=@($checks)
      Failure=$failure
    }
    [IO.File]::WriteAllText($receipt,($result|ConvertTo-Json -Depth 7),
       [Text.UTF8Encoding]::new($false))
    Write-Output ('R338_RECEIPT='+$receipt)
  }
  if($junctionCreated -and [IO.Directory]::Exists($brokerDir)){
    if(([IO.File]::GetAttributes($brokerDir) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
      [IO.Directory]::Delete($brokerDir,$false)
      $junctionCreated=$false
    }
  }
  # No actual system files, protected tasks, drivers or service are modified.
  if([IO.Directory]::Exists($testRoot) -and !$junctionCreated){
    [IO.Directory]::Delete($testRoot,$true)
  }
  Write-Output ('R338_STATUS='+$status+' CHECKS='+$checks.Count)
}
if($failure){throw ('R338_SUPERVISOR_TRUST_NEGATIVE_FAILED '+$failure)}
