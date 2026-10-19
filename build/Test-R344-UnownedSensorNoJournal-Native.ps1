[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$SourceRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Native security-negative witness; tests exact PE embedded production Helper
# only on fresh temporary hosted Windows. Never run on owner's installed PC.
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'GOD13emad/TaskbarMonitorEnhanced' -or
   $env:GITHUB_REF -cne 'refs/heads/audit/r349-pinned-leaf-replay-handles' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC|ALIEMAD|SAEID|LAPTOP' -or
   $env:GITHUB_RUN_ID -cnotmatch '^\d{5,20}$' -or
   $env:GITHUB_SHA -cnotmatch '^[0-9a-f]{40}$' -or
   (git -C $SourceRoot rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){
 throw 'R344_NEGATIVE_REQUIRES_PINNED_DISPOSABLE_GUEST'
}
$token=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($token)
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 throw 'R344_NEGATIVE_REQUIRES_EXISTING_ADMIN_TOKEN'
}
$sid=[string]$token.User.Value
if($sid -cnotmatch '^S-1-5-21-(?:\d+-){3}\d+$'){throw 'R344_NEGATIVE_INTERACTIVE_TOKEN_SID_MISSING'}
$pf=[Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
$root=Join-Path $pf 'TaskbarMonitorEnhanced'
$broker=Join-Path $root 'SensorBroker'
$brokerExe=Join-Path $broker 'TaskbarMonitorSensorBroker.exe'
$supervisorExe=Join-Path $broker 'TaskbarMonitorSensorSupervisor.exe'
$ownerMarker=Join-Path $broker '.tbme-owner.sid'
$journal=Join-Path $root '.tbme-sensor-rollback'
$task='TaskbarMonitorEnhanced Sensor Broker'
$app=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'TaskbarMonitorEnhanced'
$logs=Join-Path $app 'Logs'
$log=Join-Path $logs 'sensor_install.log'
$result=Join-Path $logs 'sensor_install_result.json'
$temp=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) 'AppData\Local\Temp'
$payload=Join-Path $temp ('tbme_uninstall_'+[guid]::NewGuid().ToString('N'))
$receiptRoot=Join-Path $env:RUNNER_TEMP ('R344Neg_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $receiptRoot 'R344_UNOWNED_FOREIGN_WITHOUT_JOURNAL.json'
$setup=Join-Path $SourceRoot 'build\_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$privateBroker=Join-Path $SourceRoot 'build\_out\Broker\TaskbarMonitorSensorBroker.exe'
$privateSupervisor=Join-Path $SourceRoot 'build\_out\Supervisor\TaskbarMonitorSensorSupervisor.exe'
$helperSource=Join-Path $SourceRoot 'installer\TBME_Setup_Elevated_Helper.ps1'
$native=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
$checks=[Collections.Generic.List[string]]::new()
$failure='';$phase='PRECONDITION'
$rootCreated=$false;$payloadCreated=$false;$appCreated=$false;$logsCreated=$false
$rootRemoved=$false;$payloadRemoved=$false;$logsRemoved=$false;$appRemoved=$false
$originalBrokerHash='';$originalSupervisorHash='';$script:startupCount=0
$realPE=$false;$canary='';$canaryHash=''
function SHA([string]$f){return (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash}
function Note([string]$name){$script:checks.Add($name);Write-Output ('PASS '+$name)}
function TaskExists(){
 return @((Get-ScheduledTask -TaskPath '\' -TaskName $task -ErrorAction SilentlyContinue |Where-Object {$null -ne $_})).Count -gt 0
}
function RefuseReparse([string]$path){
 if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
  throw 'R344_NEGATIVE_FIXTURE_REPARSE_NOT_OWNED'
 }
}
function RunOriginalHelper([Diagnostics.ProcessStartInfo]$psi,[string]$reason){
 $child=[Diagnostics.Process]::Start($psi)
 if(!$child){throw 'R344_NEGATIVE_ORIGINAL_HELPER_NOT_STARTED'}
 try{
  if(!$child.WaitForExit(45000)){
   if(!$child.HasExited){$child.Kill();[void]$child.WaitForExit(5000)}
   throw 'R344_NEGATIVE_ORIGINAL_HELPER_TIMEOUT'
  }
  if($child.ExitCode -ne 0){throw ('R344_NEGATIVE_HELPER_EXIT_NONZERO_'+$child.ExitCode)}
 }finally{$child.Dispose()}
 $script:startupCount++
 if(![IO.File]::Exists($result) -or ![IO.File]::Exists($log)){
  throw 'R344_NEGATIVE_MISSING_REAL_HELPER_STATUS_OR_LOG'
 }
 $status=Get-Content -LiteralPath $result -Raw|ConvertFrom-Json
 if($status.Status -cne 'DEGRADED_OTHER_USER_SENSOR_LAYER_PRESERVED' -or
    $status.Message -cnotmatch [Regex]::Escape($reason)){
  throw ('R344_NEGATIVE_FOERGIGN_OWNER_GUARD_FAIL_'+$status.Status+'_'+$status.Message)
 }
 if(!(Select-String -LiteralPath $log -SimpleMatch ('CROSS_USER_SENSOR_SAFETY_REFUSAL reason='+$reason) -Quiet)){
  throw 'R344_NEGATIVE_REAL_HELPER_NOT_LOGGING_EXPECTED_REFUSAL'
 }
 if([IO.Directory]::Exists($journal) -or [IO.Directory]::Exists($journal+'-retired') -or
    (TaskExists) -or (SHA $brokerExe) -cne $originalBrokerHash -or
    (SHA $supervisorExe) -cne $originalSupervisorHash -or (SHA $canary) -cne $canaryHash){
  throw 'R344_NEGATIVE_PROTECTED_EXECUTABLE_OR_CANARY_MUTATED'
 }
 Note ('EXACT_PRODUCTION_HELPER_REFUSES_'+$reason)
}
try{
 foreach($f in @($setup,$privateBroker,$privateSupervisor,$helperSource,$native)){
  if(![IO.File]::Exists($f)){throw 'R344_NEGATIVE_EXACT_PRIVATE_BUILD_FILE_MISSING'}
 }
 if([IO.Directory]::Exists($root) -or [IO.Directory]::Exists($receiptRoot) -or
    [IO.Directory]::Exists($payload) -or [IO.File]::Exists($log) -or
    [IO.File]::Exists($result) -or [IO.File]::Exists((Join-Path $app 'TaskbarMonitorEnhanced.exe')) -or
    (TaskExists) -or @(Get-Process TaskbarMonitorSensorBroker,TaskbarMonitorSensorSupervisor -ErrorAction SilentlyContinue).Count){
  throw 'R344_NEGATIVE_PREEXISTING_INSTALL_OR_FIXTURE_COLLISION'
 }
 [void][IO.Directory]::CreateDirectory($receiptRoot)
 $canary=Join-Path $receiptRoot 'CANARY.txt'
 [IO.File]::WriteAllText($canary,'R344_OUTSIDE_CANARY',[Text.UTF8Encoding]::new($false))
 $canaryHash=SHA $canary
 $asm=[Reflection.Assembly]::LoadFrom([IO.Path]::GetFullPath($setup))
 $resource=$asm.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
 if(!$resource){throw 'R344_NEGATIVE_PE_NO_EMBEDDED_PRODUCTION_HELPER'}
 $reader=[IO.StreamReader]::new($resource,[Text.Encoding]::UTF8)
 try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
 $norm={param($text) $text.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
 if((& $norm $embedded) -cne (& $norm ([IO.File]::ReadAllText($helperSource)))){
  throw 'R344_NEGATIVE_PRIVATE_SETUP_EMBEDDED_SOURCE_NOT_EXACT'
 }
 $realPE=$true
 Note 'ORIGINAL_PE_EMBEDDED_HELPER_SHA_BOUND_WITH_DISPOSABLE_TOKEN'
 $admins=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
 $system=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
 $users=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
 $acl=[Security.AccessControl.DirectorySecurity]::new()
 $acl.SetOwner($admins);$acl.SetAccessRuleProtection($true,$false)
 foreach($party in @($admins,$system,$users)){
  $rights=if($party -eq $users){[Security.AccessControl.FileSystemRights]::ReadAndExecute}else{[Security.AccessControl.FileSystemRights]::FullControl}
  [void]$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
   $party,$rights,[Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
   [Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
 }
 [void][IO.Directory]::CreateDirectory($root,$acl)
 $rootCreated=$true
 [void][IO.Directory]::CreateDirectory($broker)
 [IO.File]::Copy($privateBroker,$brokerExe)
 [IO.File]::Copy($privateSupervisor,$supervisorExe)
 $originalBrokerHash=SHA $brokerExe
 $originalSupervisorHash=SHA $supervisorExe
 if($originalBrokerHash -cne (SHA $privateBroker) -or
    $originalSupervisorHash -cne (SHA $privateSupervisor)){throw 'R344_NEGATIVE_PRIVATE_EXECUTABLE_COPY_NOT_EXACT'}
 if(![IO.Directory]::Exists($app)){
  [void][IO.Directory]::CreateDirectory($app);$appCreated=$true
 }
 if(![IO.Directory]::Exists($logs)){
  [void][IO.Directory]::CreateDirectory($logs);$logsCreated=$true
 }
 [void][IO.Directory]::CreateDirectory($payload);$payloadCreated=$true
 $type=$asm.GetType('SetupProgram',$true)
 $factory=$type.GetMethod('BuildElevatedSensorProcessInfo',[Reflection.BindingFlags]'NonPublic,Static')
 if(!$factory){throw 'R344_NEGATIVE_PRODUCTION_RUNAS_FACTORY_MISSING'}
 $actual=[string[]]@('Uninstall',$payload,$app,$sid)
 $values=New-Object 'object[]' 4
 for($i=0;$i -lt 4;$i++){$values[$i]=$actual[$i].PSObject.BaseObject}
 $psi=[Diagnostics.ProcessStartInfo]$factory.Invoke($null,$values)
 if(!$psi.UseShellExecute -or $psi.Verb -cne 'runas' -or
    -not [string]::Equals($psi.FileName,$native,[StringComparison]::OrdinalIgnoreCase)){
  throw 'R344_NEGATIVE_NOT_ORIGINAL_SYSTEM32_RUNAS_PE_HELPER'
 }
 Note 'BOUNDED_ADMIN_OWNED_MARKERLESS_PROGRAMFILES_BROKER_CREATED_WITHOUT_JOURNAL_OR_TASK'
 $phase='ORIGINAL_HELPER_REFUSES_MISSING_OWNER_WITHOUT_DURABLE_JOURNAL'
 RunOriginalHelper $psi 'UNOWNED_SHARED_PROGRAMFILES_BROKER_WITHOUT_TASK'
 if([IO.File]::Exists($ownerMarker)){throw 'R344_NEGATIVE_HELPER_CREATED_MISSING_OWNER_MARKER'}
 Note 'ABSENT_JOURNAL_DID_NOT_FABRICATE_SENSOR_OWNER_MARKER'
 $phase='ORIGINAL_HELPER_REFUSES_FOREIGN_MARKER_WITHOUT_DURABLE_JOURNAL'
 [IO.File]::WriteAllText($ownerMarker,'S-1-5-21-0-0-0-1',[Text.Encoding]::ASCII)
 $markerHash=SHA $ownerMarker
 RunOriginalHelper $psi 'PROTECTED_SENSOR_OWNER_MARKER_MISMATCH'
 if((SHA $ownerMarker) -cne $markerHash){throw 'R344_NEGATIVE_FOREIGN_SID_MARKER_CHANGED'}
 Note 'OTHER_ACCOUNT_MARKER_BYTE_EXACT_AND_NO_UNTRUSTED_SENSOR_CLEANUP'
}catch{
 $failure=$_.Exception.GetType().Name+': '+$_.Exception.Message+' PHASE='+$phase
}finally{
 if($rootCreated -and [IO.Directory]::Exists($root)){
  try{
   RefuseReparse $root;RefuseReparse $broker
   $parentMembers=@([IO.Directory]::GetFileSystemEntries($root))
   $expectedBroker=$broker
   if($parentMembers.Count -ne 1 -or $parentMembers[0] -cne $expectedBroker){
    throw 'R344_NEGATIVE_UNEXPECTED_PROTECTED_ROOT_CHILD_REFUSE_CLEANUP'
   }
   $children=@([IO.Directory]::GetFileSystemEntries($broker))
   $allowed=@($brokerExe,$supervisorExe,$ownerMarker)
   if(@($children|Where-Object{$_ -notin $allowed}).Count){
    throw 'R344_NEGATIVE_UNEXPECTED_PROTECTED_FILE_REFUSE_CLEANUP'
   }
   foreach($f in $children){RefuseReparse $f}
   if((SHA $brokerExe) -cne $originalBrokerHash -or
      (SHA $supervisorExe) -cne $originalSupervisorHash){
    throw 'R344_NEGATIVE_EXACT_PROTECTED_EXECUTABLE_HASH_CHANGED_REFUSE_CLEANUP'
   }
   foreach($f in $children){[IO.File]::Delete($f)}
   [IO.Directory]::Delete($broker,$false)
   [IO.Directory]::Delete($root,$false)
  }catch{$failure+=' PROTECTED_CLEANUP_REFUSED='+$_.Exception.Message}
 }
 $rootRemoved=(![IO.Directory]::Exists($root))
 if($payloadCreated){
  try{
   if([IO.Directory]::Exists($payload) -and @([IO.Directory]::GetFileSystemEntries($payload)).Count -eq 0){
    [IO.Directory]::Delete($payload,$false)
   }
  }catch{$failure+=' PAYLOAD_CLEANUP_REFUSED='+$_.Exception.Message}
 }
 $payloadRemoved=(![IO.Directory]::Exists($payload))
 if([IO.Directory]::Exists($logs)){
  try{
   foreach($f in @($log,$result)){if([IO.File]::Exists($f)){RefuseReparse $f;[IO.File]::Delete($f)}}
   if($logsCreated -and @([IO.Directory]::GetFileSystemEntries($logs)).Count -eq 0){
    [IO.Directory]::Delete($logs,$false)
   }
  }catch{$failure+=' LOG_CLEANUP_REFUSED='+$_.Exception.Message}
 }
 $logsRemoved=(!$logsCreated -or ![IO.Directory]::Exists($logs))
 if($appCreated -and [IO.Directory]::Exists($app)){
  try{
   if(@([IO.Directory]::GetFileSystemEntries($app)).Count -eq 0){[IO.Directory]::Delete($app,$false)}
  }catch{$failure+=' APP_CLEANUP_REFUSED='+$_.Exception.Message}
 }
 $appRemoved=(!$appCreated -or ![IO.Directory]::Exists($app))
 if($rootCreated -and !$rootRemoved){$failure+=' OWN_PROTECTED_ROOT_NOT_REMOVED'}
 if($payloadCreated -and !$payloadRemoved){$failure+=' OWN_TEMP_PAYLOAD_NOT_REMOVED'}
 if(!$logsRemoved -or !$appRemoved){$failure+=' OWN_TEST_PROFILE_LOG_REMAINS'}
 $status=if(!$failure -and $checks.Count -eq 6 -and $startupCount -eq 2 -and $rootRemoved){
  'PASS_REAL_HELPER_REFUSES_UNOWNED_AND_FOREIGN_BROKER_WITHOUT_JOURNAL'
 }else{'FAIL_R344_REAL_SECURITY_NEGATIVE'}
 $out=[ordered]@{
  Schema=1;Revision='R344';Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
  Status=$status;SetupSHA256=if([IO.File]::Exists($setup)){SHA $setup}else{'MISSING'}
  ActualFullPEEmbeddedOriginalHelper=$realPE;RealOriginalHelperInvocations=$startupCount
  NoTrustedPreparedJournalPresent=$true;NoScheduledTaskEverRegistered=$true
  ForeignAndAbsentOwnerMarkerRefused=($checks.Count -eq 6)
  ProtectedOriginalBrokerSHA256=$originalBrokerHash
  ProtectedOriginalSupervisorSHA256=$originalSupervisorHash
  ExactOwnedProtectedRootRemoved=$rootRemoved
  OriginalOwnerComputerTouched=$false
  ActualInteractiveUACPromptObserved=$false
  ActualProtectedDriverInstalled=$false
  Checks=@($checks);Failure=$failure
 }
 if([IO.Directory]::Exists($receiptRoot)){
  [IO.File]::WriteAllText($receipt,($out|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
  Write-Output ('R344_NEGATIVE_RECEIPT='+$receipt)
 }
 Write-Output ('R344_NEGATIVE_STATUS='+$status)
}
if($failure){throw ('R344_SECURITY_NEGATIVE_NOT_ACCEPTED '+$failure)}
