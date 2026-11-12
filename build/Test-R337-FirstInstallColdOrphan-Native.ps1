[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
  [Parameter(Mandatory=$true)][ValidateSet('baseline','candidate')][string]$Variant,
  [Parameter(Mandatory=$true)][string]$ProductRoot,
  [Parameter(Mandatory=$true)][string]$SetupPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
  throw 'R337_DISPOSABLE_GITHUB_WINDOWS_ONLY'
}
function Hash([string]$p){return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash}
$root=Join-Path $env:RUNNER_TEMP ('R337_'+$Variant+'_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
if(Test-Path -LiteralPath $root){throw 'R337_COLLIDING_TEST_ROOT'}
[void][IO.Directory]::CreateDirectory($root)
$receipt=Join-Path $root 'R337_FIRST_INSTALL_COLD_RECOVERY.json'
$checks=[Collections.Generic.List[string]]::new()
$failure=''
$remaining=$null
$outside=Join-Path $root 'OUTSIDE_CANARY.txt'
$canary='R337_OUTSIDE_CANARY_NOT_MODIFIED'
[IO.File]::WriteAllText($outside,$canary)
$source=(Resolve-Path (Join-Path $ProductRoot 'installer\TBME_Setup_Elevated_Helper.ps1')).Path
$process=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
try{
  if(-not [IO.File]::Exists($SetupPath) -or
     -not [string]::Equals([IO.Path]::GetFullPath($process),
       ([IO.Path]::GetFullPath((Get-Process -Id $PID).Path)),
       [StringComparison]::OrdinalIgnoreCase)){
    throw 'R337_EXACT_SYSTEM_POWERSHELL_51_OR_COMPILED_SETUP_MISSING'
  }
  $pe=[Reflection.Assembly]::LoadFrom([IO.Path]::GetFullPath($SetupPath))
  $rs=$pe.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
  if(!$rs){throw 'R337_COMPILED_PE_SENSOR_RESOURCE_MISSING'}
  $reader=[IO.StreamReader]::new($rs,[Text.Encoding]::UTF8)
  try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
  $normalize={param($x) $x.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
  $src=[IO.File]::ReadAllText($source)
  if((& $normalize $embedded) -cne (& $normalize $src)){
    throw 'R337_COMPILED_PE_SCRIPT_NOT_EXACT'
  }
  $checks.Add('COMPILED_SETUP_EMBEDS_EXACT_PRODUCTION_SENSOR_HELPER')
  $tok=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tok,[ref]$errors)
  if(@($errors).Count){throw 'R337_PRODUCTION_PS51_SYNTAX_INVALID'}
  $names=@(
    'Assert-SensorBoundaryNoReparse','Get-SensorJournalHash','Assert-SensorJournalRelative',
    'Assert-SensorJournalTrustedAcl','Write-SensorJournalUnique','Assert-SensorDurableJournal',
    'New-SensorDurableJournal','Get-SensorJournalTerminal','Write-SensorJournalTerminal',
    'Restore-SensorJournalOldFilesOnly','Assert-SensorRetiredJournalSafe',
    'Finish-SensorRetiredJournal','Finish-SensorTerminalJournal',
    'Resume-SensorCompletedJournal','Resolve-SensorPriorTaskPrincipalSid',
    'Assert-SensorTrustedOldTaskXml','Test-SensorOwnedTaskRegistration',
    'Restore-SensorJournalPriorLayerAndTask','Resume-SensorPendingJournal'
  )
  $defs=@($ast.FindAll({param($n)
    $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -in $names
  },$true))
  if($defs.Count -ne $names.Count){throw ('R337_PRODUCTION_FUNCTION_COUNT_'+$defs.Count)}
  . ([scriptblock]::Create(($defs|ForEach-Object {$_.Extent.Text}) -join [Environment]::NewLine))
  $checks.Add('EXECUTING_REAL_PS51_FUNCTIONS_EXTRACTED_FROM_COMPILED_HELPER')
  $sid=[string]([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
  if($sid -cnotmatch '^S-1-5-21-(?:\d+-){3}\d+$'){throw 'R337_HOSTED_INTERACTIVE_ACCOUNT_SID_INVALID'}
  $name='TBME-R314-Disposable-'+$env:GITHUB_RUN_ID+'-'+$HostLabel
  if(@(Get-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction SilentlyContinue |
      Where-Object {$null -ne $_}).Count){throw 'R337_TASK_COLLISION'}
  $checks.Add('NO_EXISTING_DISPOSABLE_TASK_OR_USER_SERVICE_CHANGE')
  $admins=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
  $system=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
  $acl=[Security.AccessControl.DirectorySecurity]::new()
  $acl.SetOwner($admins)
  $acl.SetAccessRuleProtection($true,$false)
  foreach($s in @($admins,$system)){
    $ace=[Security.AccessControl.FileSystemAccessRule]::new(
      $s,[Security.AccessControl.FileSystemRights]::FullControl,
      [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
      [Security.AccessControl.PropagationFlags]::None,
      [Security.AccessControl.AccessControlType]::Allow)
    [void]$acl.AddAccessRule($ace)
  }
  $trusted=Join-Path $root 'trusted'
  [void][IO.Directory]::CreateDirectory($trusted,$acl)
  Assert-SensorJournalTrustedAcl $trusted $true
  $journal=Join-Path $trusted 'snapshot'
  $live=Join-Path $root 'synthetic-broker'
  $userData=Join-Path $root 'synthetic-app'
  [void][IO.Directory]::CreateDirectory($userData)
  $new=[string[]]@('TaskbarMonitorSensorBroker.exe','.tbme-owner.sid','vendor\source\lib.dll')
  # Original protected tree DID NOT EXIST. A mid-install crash leaves an
  # ownership marker and nested new bytes which must be removed on recovery.
  New-SensorDurableJournal $journal $sid ([object[]]@()) '' $new $false
  $checks.Add('READY_FLUSHED_BEFORE_FIRST_INSTALL_MUTATION_AND_OLD_ROOT_ABSENT')
  [void][IO.Directory]::CreateDirectory($live,$acl)
  [void][IO.Directory]::CreateDirectory((Join-Path $live 'vendor\source'))
  [IO.File]::WriteAllText((Join-Path $live 'TaskbarMonitorSensorBroker.exe'),'NEW_TEST_ONLY')
  [IO.File]::WriteAllText((Join-Path $live '.tbme-owner.sid'),$sid)
  [IO.File]::WriteAllText((Join-Path $live 'vendor\source\lib.dll'),'NEW_TEST_ONLY')
  if((Get-SensorJournalTerminal $journal $sid) -cne 'PREPARED'){throw 'R337_MISSING_DURABLE_READY'}
  $checks.Add('SYNTHETIC_CRASH_STATE_HAS_PARTIAL_NEW_PROTECTED_FILES_AND_OWNER_MARKER')
  $result=Resume-SensorPendingJournal $journal $sid $live $userData $name
  if($result -cne 'PREVIOUS_LAYER_RESTORED'){throw ('R337_COLD_RECOVERY_NOT_ACCEPTED_'+$result)}
  if([IO.Directory]::Exists($journal) -or [IO.Directory]::Exists($journal+'-retired')){
    throw 'R337_TERMINAL_JOURNAL_NOT_FULLY_RETIRED'
  }
  $checks.Add('PRODUCTION_COLD_REPLAY_AND_DURABLE_RETIRE_SUCCEEDED')
  foreach($rel in $new){
    if([IO.File]::Exists((Join-Path $live $rel))){throw ('R337_EXPECTED_REMOVED_NEW_FILE_'+$rel)}
  }
  $checks.Add('ALL_KNOWN_NEW_FILES_REMOVED_AFTER_ROLLBACK')
  $remaining=[IO.Directory]::Exists($live)
  if($Variant -ceq 'baseline'){
    if(!$remaining){throw 'R337_BASELINE_EXPECTED_ORPHAN_NOT_REPRODUCED'}
    $checks.Add('BASELINE_BROKER_DIRECTORY_ORPHAN_REPRODUCED')
  }else{
    if($remaining){throw 'R337_REPAIRED_BROKER_DIRECTORY_STILL_ORPHANED'}
    $checks.Add('FIRST_INSTALL_RECOVERY_LEAVES_NO_UNOWNED_BROKER_ROOT')
  }
  if([IO.File]::ReadAllText($outside) -cne $canary){throw 'R337_OUTSIDE_CANARY_CHANGED'}
  $checks.Add('UNRELATED_CANARY_BYTE_EXACT_UNMODIFIED')
  if(@(Get-ScheduledTask -TaskPath '\' -TaskName $name -ErrorAction SilentlyContinue |
      Where-Object {$null -ne $_}).Count){throw 'R337_UNEXPECTED_REGISTERED_TASK'}
  $checks.Add('NEVER_REGISTERED_OR_MODIFIED_SCHEDULED_TASK')
}catch{
  $failure=$_.Exception.ToString()
}finally{
  $receiptData=[ordered]@{
    Schema=1;Revision='R337';Host=$HostLabel;Variant=$Variant
    SourceCommit=(git -C $ProductRoot rev-parse HEAD).Trim()
    SetupSHA256=if(Test-Path -LiteralPath $SetupPath){Hash $SetupPath}else{'MISSING'}
    Status=if(!$failure){if($Variant -ceq 'baseline'){'PASS_REPRODUCED_EMPTY_BROKER_ORPHAN'}else{'PASS_RECOVERY_LEAVES_NO_EMPTY_BROKER_ROOT'}}else{'FAIL'}
    ActualElevatedUacPerformed=$false
    RealProgramFilesWritten=$false
    ActualScheduledTaskChanged=$false
    ActualOwnerComputerTouched=$false
    OldRootPresent=$false
    EmptyBrokerRootRemained=$remaining
    Checks=@($checks)
    Failure=$failure
  }
  [IO.File]::WriteAllText($receipt,($receiptData|ConvertTo-Json -Depth 7),
    [Text.UTF8Encoding]::new($false))
  Write-Output ('R337_RECEIPT='+$receipt)
  Write-Output ('R337_STATUS='+$receiptData.Status)
}
if($failure){throw ('R337_FIRST_INSTALL_COLD_RECOVERY_FAILED '+$failure)}
