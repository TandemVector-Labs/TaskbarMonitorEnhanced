[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$CandidateDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'R296_ONLY_GITHUB_DISPOSABLE_WINDOWS'
}
function Hash([string]$Path){
 if(!(Test-Path -LiteralPath $Path -PathType Leaf)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}
function ExpectRefusal([string]$Name,[scriptblock]$Body,[string]$Match){
 $refused=$false
 try{& $Body}
 catch{
  if($_.Exception.Message -match $Match){$refused=$true}else{throw ('R296_UNEXPECTED_'+$Name+': '+$_.Exception.Message)}
 }
 if(!$refused){throw ('R296_FAIL_OPEN_'+$Name)}
 $script:checks.Add($Name)
}
$root=Join-Path $env:RUNNER_TEMP ('R296_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $root 'R296_MEMORY_ROLLBACK_RECEIPT.json'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$liveMain=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R295_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R295_ZIP_PROVENANCE_RECEIPT.json')
$checks=[Collections.Generic.List[string]]::new()
$accepted=$false
if(Test-Path $root){throw 'R296_PREEXISTING_TEST_ROOT'}
[void][IO.Directory]::CreateDirectory($root)
$mainBefore=Hash $liveMain
try{
 $identity=Get-Content $manifest -Raw|ConvertFrom-Json
 $previous=Get-Content $prior -Raw|ConvertFrom-Json
 if($identity.Commit -cne $env:GITHUB_SHA -or
    (Hash $setup) -cne $identity.SetupSHA256 -or
    (Hash $liveMain) -cne $identity.MainSHA256 -or
    $previous.SourceCommit -cne $env:GITHUB_SHA -or
    $previous.Host -cne $HostLabel -or
    $previous.Status -cne 'PASS_PE_PINNED_ZIP_BYTE_ONLY_BACKEND_PROVENANCE'){
  throw 'R296_EXACT_HOST_SOURCE_OR_R295_NOT_VERIFIED'
 }
 $helper=(Resolve-Path (Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1')).Path
 $raw=Get-Content $helper -Raw
 if($raw.Contains('$RollbackRoot=Join-Path $PayloadDir') -or
    $raw.Contains('Copy-Item -LiteralPath $RollbackBrokerRoot') -or
    -not $raw.Contains('$script:RollbackFiles=Get-SensorRollbackFiles $BrokerRoot') -or
    -not $raw.Contains('Restore-SensorRollbackFiles $BrokerRoot $RollbackFiles') -or
    -not $raw.Contains('$script:RollbackTaskXmlText=[string](Export-ScheduledTask')){
  throw 'R296_USER_WRITABLE_ROLLBACK_STILL_ACTIVE'
 }
 $checks.Add('NO_TEMP_SNAPSHOT_OR_TASK_XML_PATH_IN_PRODUCTION_HELPER')
 $t=$null;$e=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile($helper,[ref]$t,[ref]$e)
 if(@($e).Count){throw 'R296_WINDOWS_POWER_SHELL_51_PARSE_FAILED'}
 $defs=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
      $node.Name -in @('Assert-SensorBoundaryNoReparse','Get-SensorRollbackFiles','Restore-SensorRollbackFiles','Clear-SensorRollbackBuffer')},$true))
 if($defs.Count -ne 4){throw 'R296_EXPECTED_FOUR_PURE_SECURITY_FUNCTIONS'}
 . ([scriptblock]::Create(($defs|ForEach-Object {$_.Extent.Text}) -join [Environment]::NewLine))
 $old=Join-Path $root 'old-broker'
 $target=Join-Path $root 'restored-broker'
 $fakeTemp=Join-Path $root 'attacker-TEMP-snapshot'
 $external=Join-Path $root 'external-canary'
 foreach($p in @($old,$fakeTemp,$external)){[void][IO.Directory]::CreateDirectory($p)}
 $broker=Join-Path $old 'TaskbarMonitorSensorBroker.exe'
 $library=Join-Path $old 'LibreHardwareMonitorLib.dll'
 $nested=Join-Path $old 'lang'
 [void][IO.Directory]::CreateDirectory($nested)
 $subfile=Join-Path $nested 'safe.dll'
 [IO.File]::WriteAllBytes($broker,[byte[]](1,2,3,4,5,6,7,8,9))
 [IO.File]::WriteAllBytes($library,[byte[]](10,9,8,7,6,5,4,3,2,1))
 [IO.File]::WriteAllBytes($subfile,[byte[]](42,77,83))
 $beforeBroker=Hash $broker
 $beforeLibrary=Hash $library
 $beforeSub=Hash $subfile
 $snapshot=Get-SensorRollbackFiles $old
 if(@($snapshot).Count -ne 3){throw 'R296_MISSING_CAPTURED_SNAPSHOT_FILES'}
 $checks.Add('THREE_PROGRAMFILES_LIKE_FILES_CAPTURED_ONLY_IN_MEMORY')
 [IO.File]::WriteAllBytes($broker,[byte[]](200,201,202))
 [IO.File]::WriteAllBytes((Join-Path $fakeTemp 'TaskbarMonitorSensorBroker.exe'),[byte[]](255,255))
 Restore-SensorRollbackFiles $target $snapshot
 if((Hash (Join-Path $target 'TaskbarMonitorSensorBroker.exe')) -cne $beforeBroker -or
    (Hash (Join-Path $target 'LibreHardwareMonitorLib.dll')) -cne $beforeLibrary -or
    (Hash (Join-Path $target 'lang\safe.dll')) -cne $beforeSub){
  throw 'R296_REPLAY_BYTES_DIFFER_FROM_PRIVATE_SNAPSHOT'
 }
 $checks.Add('RESTORE_EXACT_PRIOR_CONTENT_FROM_PRIVATE_MEMORY')
 $checks.Add('MUTABLE_TEMP_FORGED_SNAPSHOT_IGNORED')
 $script:RollbackFiles=$snapshot
 $script:RollbackCaptured=$true
 $script:RollbackTaskXmlText='<Task>R296_IN_MEMORY_ONLY</Task>'
 Clear-SensorRollbackBuffer
 if(@($script:RollbackFiles).Count -ne 0 -or $script:RollbackCaptured -or $null -ne $script:RollbackTaskXmlText){
  throw 'R296_SNAPSHOT_MEMORY_NOT_WIPED'
 }
 $checks.Add('ROLLBACK_DATA_AND_XML_MEMORY_CLEARED')
 ExpectRefusal 'PARENT_TRAVERSAL_REJECTED' {Restore-SensorRollbackFiles $target @([pscustomobject]@{Rel='..\outside.dll';Data=[byte[]](77)})} 'ROLLBACK_RESTORE_BAD_NAME'
 $canary=Join-Path $external 'outside.txt'
 [IO.File]::WriteAllText($canary,'R296_UNMODIFIED')
 $canarySHA=Hash $canary
 $link=Join-Path $old 'junction'
 New-Item -ItemType Junction -Path $link -Target $external -ErrorAction Stop|Out-Null
 try{
  ExpectRefusal 'JUNCTIONED_SNAPSHOT_INPUT_REJECTED' {Get-SensorRollbackFiles $old|Out-Null} 'SENSOR_BOUNDARY_REPARSE_REFUSED'
 }finally{[IO.Directory]::Delete($link)}
 $escape=Join-Path $target 'escape'
 New-Item -ItemType Junction -Path $escape -Target $external -ErrorAction Stop|Out-Null
 try{
  ExpectRefusal 'JUNCTIONED_RESTORE_DESTINATION_REJECTED' {Restore-SensorRollbackFiles $target @([pscustomobject]@{Rel='escape\outside.txt';Data=[byte[]](1,2,3)})} 'SENSOR_BOUNDARY_REPARSE_REFUSED'
 }finally{[IO.Directory]::Delete($escape)}
 if((Hash $canary) -cne $canarySHA){throw 'R296_EXTERNAL_CANARY_MUTATED'}
 $checks.Add('EXTERNAL_CANARY_PRESERVED')
 $lock=[IO.FileStream]::new($library,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
 try{ExpectRefusal 'CONCURRENT_SOURCE_READER_REFUSED' {Get-SensorRollbackFiles $old|Out-Null} 'sharing violation|being used|used by another process'}finally{$lock.Dispose()}
 if((Hash $liveMain) -cne $mainBefore){throw 'R296_INSTALLED_GUEST_MAIN_CHANGED'}
 $checks.Add('INSTALLED_MAIN_UNCHANGED')
 if(Test-Path (Join-Path $root '_sensor_rollback')){throw 'R296_SNAPSHOT_DID_WRITE_DISK'}
 $checks.Add('NO_DISK_ROLLBACK_CREATED')
 $rec=[ordered]@{
  Schema=1;Revision='R296';Status='PASS_MEMORY_ONLY_ROLLBACK_NO_USER_TEMP_TRUST'
  Host=$HostLabel;SourceCommit=$env:GITHUB_SHA;OriginalOwnerComputerTouched=$false
  UACOrProtectedServiceCalled=$false;PrivateSnapshotFiles=3
  ForgedUserTempIgnored=$true;TwoJunctionDirectionsRejected=$true
  CorruptedOriginalRestoredFromMemory=$true;NoRollbackDiskFiles=$true
  InstalledMainUnchanged=$true;Checks=@($checks);RecordedUtc=[DateTime]::UtcNow.ToString('o')
 }
 [IO.File]::WriteAllText($receipt,($rec|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
 $accepted=$true
 'R296_GUEST_'+$HostLabel+'_IN_MEMORY_ROLLBACK=PASS'
}finally{
 if(!$accepted){
  $fail=[ordered]@{Schema=1;Revision='R296';Status='FAILED_NOT_ACCEPTED';Host=$HostLabel;SourceCommit=$env:GITHUB_SHA;OriginalOwnerHostUntouched=$true}
  [IO.File]::WriteAllText($receipt,($fail|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
 }
}
