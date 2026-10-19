[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
      [Parameter(Mandatory=$true)][string]$SourceRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:GITHUB_EVENT_NAME -cne 'pull_request' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'Usefull-Skills/TaskbarMonitorEnhanced' -or
   $env:GITHUB_REF -cne 'refs/pull/10/merge' -or
   $env:GITHUB_HEAD_REF -cne 'qa/r349-r093-r091-integration-20261019' -or
   $env:GITHUB_BASE_REF -cne 'sync/personal-main-9960a06d-review' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC|ALIEMAD|SAEID|LAPTOP' -or
   $env:GITHUB_RUN_ID -cnotmatch '^\d{5,20}$' -or
   $env:QA_SOURCE_SHA -cnotmatch '^[0-9a-f]{40}$' -or
   (git -C $SourceRoot rev-parse HEAD).Trim() -cne $env:QA_SOURCE_SHA){
 throw 'R350_REFUSE_NONDISPOSABLE_OR_UNBOUND_QA_SOURCE'
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 throw 'R350_ALREADY_ADMIN_TOKEN_REQUIRED_NO_BYPASS'
}
$sid=[string]$identity.User.Value
if($sid -cnotmatch '^S-1-5-21-(?:\d+-){3}\d+$'){throw 'R350_UNEXPECTED_TEST_SID'}
$program=[Environment]::GetFolderPath('ProgramFiles')
$local=[Environment]::GetFolderPath('LocalApplicationData')
$profile=[Environment]::GetFolderPath('UserProfile')
$protected=Join-Path $program 'TaskbarMonitorEnhanced'
$broker=Join-Path $protected 'SensorBroker'
$journal=Join-Path $protected '.tbme-sensor-rollback'
$task='TaskbarMonitorEnhanced Sensor Broker'
$owner=Join-Path $broker '.tbme-owner.sid'
$brokerExe=Join-Path $broker 'TaskbarMonitorSensorBroker.exe'
$supervisorExe=Join-Path $broker 'TaskbarMonitorSensorSupervisor.exe'
$app=Join-Path $local 'TaskbarMonitorEnhanced'
$result=Join-Path $app 'Logs\sensor_install_result.json'
$log=Join-Path $app 'Logs\sensor_install.log'
$temp=Join-Path $profile 'AppData\Local\Temp'
$payload=Join-Path $temp ('tbme_uninstall_'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $SourceRoot 'installer\TBME_Setup_Elevated_Helper.ps1'
$setup=Join-Path $SourceRoot 'build\_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$binary=Join-Path $SourceRoot 'build\_out\Broker\TaskbarMonitorSensorBroker.exe'
$supervisor=Join-Path $SourceRoot 'build\_out\Supervisor\TaskbarMonitorSensorSupervisor.exe'
$actorScript=Join-Path $SourceRoot 'build\qa\Test-R350-PreopenedDelete-Actor-PR10.ps1'
$native=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
$root=Join-Path $env:RUNNER_TEMP ('R350_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $root 'R350_FULL_HELPER_PREOPEN_DELETE.json'
$authority=Join-Path $root 'ACTOR_AUTHORITY.json'
$actorReceipt=Join-Path $root 'ACTOR_READY.json'
$stop=Join-Path $root 'ACTOR_STOP.flag'
$canary=Join-Path $root 'OUTSIDE_CANARY'
$checks=[Collections.Generic.List[string]]::new()
$createdRoot=$false;$createdTask=$false;$createdApp=$false;$createdPayload=$false
$actor=$null;$failure='';$phase='PREFLIGHT'
$actorPid=0;$actorReceiptSha='';$originalHash='';$restoredHash='';$xml=''
$negativeStatus='';$positiveStatus='';$finalStatus=''
function Hash([string]$file){(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}
function Check([string]$name){$script:checks.Add($name);Write-Output ('PASS '+$name)}
function TaskExists(){
 return @((Get-ScheduledTask -TaskName $task -TaskPath '\' -ErrorAction SilentlyContinue|
    Where-Object {$null -ne $_})).Count -ne 0
}
function Fail-Unknown([string]$path){
 if(Test-Path -LiteralPath $path -PathType Any){
   if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
     throw 'R350_UNEXPECTED_REPARSE_BOUNDARY'
   }
 }
}
function Call-RealElevatedHelper([string]$label){
 $args=[object[]]@('Uninstall',[string]$payload,[string]$app,[string]$sid,[int]55000)
 $value=$null
 try{$value=$script:realFactory.Invoke($null,$args)}
 catch{
  $err=$_.Exception
  while($err.InnerException){$err=$err.InnerException}
  throw ('R350_REAL_PE_ELEVATED_HELPER_EXCEPTION_'+$label+'_'+$err.GetType().Name+'_'+$err.Message)
 }
 if([int]$value -ne 0){throw ('R350_REAL_PE_HELPER_NONZERO_'+$label+'_'+$value)}
 if(-not [IO.File]::Exists($result)){throw ('R350_NO_AUTHENTICATED_ASINVOKER_STATUS_'+$label)}
 $data=Get-Content -LiteralPath $result -Raw | ConvertFrom-Json
 if([string]::IsNullOrWhiteSpace([string]$data.Status) -or
    [string]$data.LogPath -cne (Join-Path $app 'Logs\sensor_install.log')){
    throw ('R350_INVALID_PERSISTED_TYPED_STATUS_'+$label)
 }
 return [string]$data.Status
}
try {
 $phase='PRECONDITION'
 foreach($path in @($source,$setup,$binary,$supervisor,$actorScript,$native)){
  if(-not [IO.File]::Exists($path)){throw 'R350_MISSING_PINNED_INPUT'}
 }
 if([IO.Directory]::Exists($protected) -or [IO.Directory]::Exists($root) -or
    [IO.Directory]::Exists($app) -or [IO.Directory]::Exists($payload) -or (TaskExists) -or
    @(Get-Process TaskbarMonitorEnhanced,TaskbarMonitorSensorBroker,TaskbarMonitorSensorSupervisor -ErrorAction SilentlyContinue).Count){
  throw 'R350_EXISTING_PRODUCT_OR_FIXTURE_REFUSED'
 }
 [void][IO.Directory]::CreateDirectory($root)
 [IO.File]::WriteAllText($canary,'R350_CANARY_UNMODIFIED',[Text.UTF8Encoding]::new($false))
 $canaryHash=Hash $canary
 $asm=[Reflection.Assembly]::LoadFrom([IO.Path]::GetFullPath($setup))
 $res=$asm.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
 if(!$res){throw 'R350_HELPER_NOT_EMBEDDED_IN_REAL_PE'}
 $reader=[IO.StreamReader]::new($res,[Text.Encoding]::UTF8)
 try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
 $sourceText=[IO.File]::ReadAllText($source)
 $norm={param($x) $x.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
 if((& $norm $embedded) -cne (& $norm $sourceText)){
  throw 'R350_ORIGINAL_EMBEDDED_HELPER_SOURCE_NOT_EXACT'
 }
 $t=$asm.GetType('SetupProgram',$true)
 $script:realFactory=$t.GetMethod('ElevatedHelper',[Reflection.BindingFlags]'NonPublic,Static')
 if(!$script:realFactory){throw 'R350_REAL_PE_IPC_RUNAS_FACTORY_MISSING'}
 Check 'EXACT_PE_HELPER_AND_IPC_RUNAS_FACTORY_CONFIRMED'

 $phase='CREATE_EXACT_OWNED_GLOBAL_FIXTURE'
 $admins=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
 $system=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
 $users=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
 $acl=[Security.AccessControl.DirectorySecurity]::new()
 $acl.SetOwner($admins);$acl.SetAccessRuleProtection($true,$false)
 foreach($p in @($admins,$system,$users)){
  $right=if($p -eq $users){[Security.AccessControl.FileSystemRights]::ReadAndExecute}else{[Security.AccessControl.FileSystemRights]::FullControl}
  [void]$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
    $p,$right,
    [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
    [Security.AccessControl.PropagationFlags]::None,
    [Security.AccessControl.AccessControlType]::Allow))
 }
 [void][IO.Directory]::CreateDirectory($protected,$acl);$createdRoot=$true
 [void][IO.Directory]::CreateDirectory($broker)
 [IO.File]::Copy($binary,$brokerExe)
 [IO.File]::Copy($supervisor,$supervisorExe)
 [IO.File]::WriteAllText($owner,$sid,[Text.Encoding]::ASCII)
 $originalHash=Hash $brokerExe
 $beforeS=Hash $supervisorExe;$beforeMarker=Hash $owner
 if((Hash $binary) -cne $originalHash -or (Hash $supervisor) -cne $beforeS){
  throw 'R350_PROTECTED_BINARY_PROVENANCE_MISMATCH'
 }
 $argsText='--broker "'+$brokerExe+'" --output "'+(Join-Path $app 'cpu_temp_broker.json')+'"'
 $taskXml=@"
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
<Triggers><LogonTrigger><Enabled>false</Enabled><UserId>$sid</UserId></LogonTrigger></Triggers>
<Principals><Principal id="Author"><UserId>$sid</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
<Settings><Enabled>false</Enabled><AllowStartOnDemand>false</AllowStartOnDemand></Settings>
<Actions Context="Author"><Exec><Command>$supervisorExe</Command><Arguments>$argsText</Arguments></Exec></Actions>
</Task>
"@
 Register-ScheduledTask -TaskPath '\' -TaskName $task -Xml $taskXml -ErrorAction Stop|Out-Null
 $createdTask=$true
 if(-not (TaskExists) -or (Get-ScheduledTask -TaskName $task).Settings.Enabled -ne $false){
  throw 'R350_TEST_TASK_UNEXPECTED_OR_ENABLED'
 }
 $xml=[string](Export-ScheduledTask -TaskName $task -TaskPath '\')
 [void][IO.Directory]::CreateDirectory($app);$createdApp=$true
 [void][IO.Directory]::CreateDirectory($payload);$createdPayload=$true
 Check 'FRESH_PROTECTED_BINARIES_OWNER_MARKER_DISABLED_TASK_AND_USER_PAYLOAD'

 $phase='MAKE_TRUE_PRODUCTION_PREPARED_JOURNAL'
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
 if(@($errors).Count){throw 'R350_ORIGINAL_HELPER_AST_NOT_VALID'}
 $defs=@($ast.EndBlock.Statements | Where-Object {
     $_ -is [Management.Automation.Language.FunctionDefinitionAst]})
 if(@($defs|Where-Object Name -eq 'New-SensorDurableJournal').Count -ne 1){
  throw 'R350_PRODUCTION_JOURNAL_FUNCTION_MISSING'
 }
 foreach($def in $defs){ . ([scriptblock]::Create($def.Extent.Text)) }
 $rows=@(
  [pscustomobject]@{Rel='.tbme-owner.sid';Data=[IO.File]::ReadAllBytes($owner)},
  [pscustomobject]@{Rel='TaskbarMonitorSensorBroker.exe';Data=[IO.File]::ReadAllBytes($brokerExe)},
  [pscustomobject]@{Rel='TaskbarMonitorSensorSupervisor.exe';Data=[IO.File]::ReadAllBytes($supervisorExe)}
 )
 New-SensorDurableJournal $journal $sid $rows $xml ([string[]]@()) $true
 if((Get-SensorJournalTerminal $journal $sid) -cne 'PREPARED'){
   throw 'R350_PRODUCTION_PREPARED_JOURNAL_VERIFICATION_FAILED'
 }
 Unregister-ScheduledTask -TaskPath '\' -TaskName $task -Confirm:$false -ErrorAction Stop
 if(TaskExists){throw 'R350_DISPOSABLE_INTERRUPTED_TASK_STILL_PRESENT'}
 Check 'REAL_PRODUCTION_HASHED_PREPARED_AND_TORN_TASK_STATE'

 $phase='HOLD_DISTINCT_ADMINISTRATOR_DELETE_HANDLE'
 $auth=[ordered]@{Schema=1;Revision='R350';SourceCommit=$env:QA_SOURCE_SHA
                   Sid=$sid;Guest=$env:COMPUTERNAME;Target=$brokerExe}
 [IO.File]::WriteAllText($authority,($auth|ConvertTo-Json -Compress -Depth 4),[Text.UTF8Encoding]::new($false))
 $psi=[Diagnostics.ProcessStartInfo]::new()
 $psi.FileName=$native
 $psi.Arguments='-NoLogo -NoProfile -NonInteractive -File "'+$actorScript+
   '" -AuthorityPath "'+$authority+'" -ReceiptPath "'+$actorReceipt+'" -StopPath "'+$stop+'"'
 $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
 $actor=[Diagnostics.Process]::Start($psi)
 if($null -eq $actor){throw 'R350_DISTINCT_ADMIN_ACTOR_NOT_STARTED'}
 $actorPid=$actor.Id
 $until=[DateTime]::UtcNow.AddSeconds(18)
 while(-not [IO.File]::Exists($actorReceipt) -and [DateTime]::UtcNow -lt $until){
  if($actor.HasExited){throw ('R350_ACTOR_EXITED_BEFORE_PROOF_'+$actor.ExitCode)}
  Start-Sleep -Milliseconds 30
 }
 if(-not [IO.File]::Exists($actorReceipt)){throw 'R350_ACTOR_READY_TIMEOUT'}
 $actorReady=Get-Content -LiteralPath $actorReceipt -Raw|ConvertFrom-Json
 if($actorReady.Status -cne 'PREOPENED_DELETE_HANDLE_HELD' -or
    $actorReady.ActorPid -ne $actorPid -or $actorReady.AlreadyAdmin -ne $true -or
    $actorReady.SourceCommit -cne $env:QA_SOURCE_SHA){
  throw 'R350_ACTOR_NOT_AN_INDEPENDENT_ADMIN_WITH_OPEN_DELETE_HANDLE'
 }
 $actorReceiptSha=Hash $actorReceipt
 Check 'DISTINCT_ALREADY_ADMIN_PROCESS_HOLDS_REAL_DELETE_HANDLE'

 $phase='REAL_HELPER_COLD_REPLAY_MUST_FAIL_CLOSED_UNDER_OPEN_DELETE'
 $negativeStatus=Call-RealElevatedHelper 'WITH_PREOPENED_DELETE'
 if($negativeStatus -cne 'DEGRADED_ROLLBACK_RECOVERY_REQUIRED' -or
    (Get-SensorJournalTerminal $journal $sid) -cne 'PREPARED' -or
    (TaskExists) -or (Hash $brokerExe) -cne $originalHash){
  throw ('R350_HELPER_FAILED_TO_RETAIN_PREPARED_ON_PREOPENED_DELETE_'+$negativeStatus)
 }
 Check 'REAL_PE_HELPER_COLD_REPLAY_REFUSED_PRIOR_DELETE_WITH_PREPARED_PRESERVED'

 $phase='RELEASE_ACTOR_AND_ALLOW_AUTHENTIC_RECOVERY'
 [IO.File]::WriteAllText($stop,'STOP',[Text.UTF8Encoding]::new($false))
 if(-not $actor.WaitForExit(10000) -or $actor.ExitCode -ne 0){
  throw 'R350_ACTOR_DID_NOT_RELEASE_DELETE_RIGHT'
 }
 $actor.Dispose();$actor=$null
 Check 'INDEPENDENT_ADMIN_FILE_HANDLE_RELEASED'

 if((Hash $brokerExe) -cne $originalHash){throw 'R350_OLD_BROKER_CHANGED_BEFORE_RESTORE'}
 [IO.File]::Delete($brokerExe)
 if([IO.File]::Exists($brokerExe)){throw 'R350_OWNED_TEST_LEAF_NOT_REMOVED'}
 $phase='REAL_HELPER_COMPLETE_COLD_REPLAY'
 $positiveStatus=Call-RealElevatedHelper 'AFTER_DELETE_RELEASE'
 $restoredHash=Hash $brokerExe
 if($positiveStatus -cne 'DEGRADED_PREVIOUS_LAYER_RESTORED' -or
    $restoredHash -cne $originalHash -or
    (Hash $supervisorExe) -cne $beforeS -or
    (Hash $owner) -cne $beforeMarker -or
    -not (TaskExists) -or [IO.Directory]::Exists($journal) -or
    [IO.Directory]::Exists($journal+'-retired')){
  throw ('R350_REAL_HELPER_COLD_RESTORE_INCOMPLETE_'+$positiveStatus)
 }
 $newTaskXml=[string](Export-ScheduledTask -TaskPath '\' -TaskName $task)
 if($newTaskXml -cne $xml){throw 'R350_SAVED_DISABLED_TASK_XML_NOT_BYTE_EXACT'}
 Check 'REAL_HELPER_REPLAY_RESTORES_PRIOR_LEAF_TASK_XML_AND_RETIRES_JOURNAL'

 $phase='FINAL_REAL_HELPER_UNINSTALL_CLEAN_FINISH'
 $finalStatus=Call-RealElevatedHelper 'FINAL_UNINSTALL'
 if($finalStatus -cne 'UNINSTALLED' -or (TaskExists) -or
    [IO.Directory]::Exists($broker) -or [IO.Directory]::Exists($journal)){
  throw ('R350_REAL_HELPER_FINAL_UNINSTALL_NOT_CLEAN_'+$finalStatus)
 }
 Check 'REAL_HELPER_THIRD_INVOCATION_UNINSTALLS_KNOWN_DISPOSABLE_LAYER'
 if((Hash $canary) -cne $canaryHash){throw 'R350_OUTSIDE_CANARY_MUTATED'}
 Check 'TEST_FOREIGN_CANARY_EXACT_BYTES_PRESERVED'
}catch{
 $failure=$_.Exception.GetType().Name+': '+$_.Exception.Message+' PHASE='+$phase
}finally{
 if($actor){
  try{[IO.File]::WriteAllText($stop,'STOP',[Text.UTF8Encoding]::new($false))}catch{}
  try{if(-not $actor.WaitForExit(2500)){$actor.Kill();[void]$actor.WaitForExit(3000)}}catch{}
  $actor.Dispose()
 }
 # Fail closed on unexpected Program Files/journal members: keep them for the
 # ephemeral runner diagnosis, never recursively delete unknown content.
 if($createdTask -and (TaskExists)){
  try{
   $current=Get-ScheduledTask -TaskName $task -TaskPath '\' -ErrorAction Stop
   if($current.Settings.Enabled -eq $false -and
      [string]$current.Principal.UserId -in @($sid,[string]$identity.Name)){
     Unregister-ScheduledTask -TaskName $task -TaskPath '\' -Confirm:$false
   }
  }catch{$failure+=' TASK_CLEANUP_REFUSED'}
 }
 if($createdRoot -and [IO.Directory]::Exists($protected)){
  try{
   $members=@([IO.Directory]::GetFileSystemEntries($protected))
   if($members.Count -eq 0){[IO.Directory]::Delete($protected,$false)}
   else{
    $failure+=' PROTECTED_FIXTURE_LEFT_FOR_DIAGNOSIS'
   }
  }catch{$failure+=' PROTECTED_CLEANUP_NOT_EMPTY'}
 }
 if($createdPayload -and [IO.Directory]::Exists($payload)){
  try{if(@([IO.Directory]::GetFileSystemEntries($payload)).Count -eq 0){
    [IO.Directory]::Delete($payload,$false)
  }}catch{$failure+=' TEMP_FIXTURE_CLEANUP_FAILED'}
 }
 if($createdApp -and [IO.Directory]::Exists($app)){
  try{
   $logs=Join-Path $app 'Logs'
   if([IO.Directory]::Exists($logs)){
    $files=@([IO.Directory]::GetFileSystemEntries($logs))
    $allow=@($result,$log)
    if(@($files|Where-Object {$_ -notin $allow}).Count -eq 0){
      foreach($f in $files){Fail-Unknown $f;[IO.File]::Delete($f)}
      [IO.Directory]::Delete($logs,$false)
    }else{$failure+=' UNKNOWN_LOGS_CONTENT'}
   }
   if(@([IO.Directory]::GetFileSystemEntries($app)).Count -eq 0){
    [IO.Directory]::Delete($app,$false)
   }
  }catch{$failure+=' APP_CLEANUP_FAILED'}
 }
 if([IO.Directory]::Exists($root)){
  $status=if(!$failure -and $checks.Count -eq 9 -and
      -not [IO.Directory]::Exists($protected) -and -not (TaskExists)){
    'PASS_FULL_PE_HELPER_PREOPENED_DELETE_FAIL_CLOSED_THEN_COLD_RESTORE_AND_UNINSTALL'
  }else{'FAIL_OR_INCOMPLETE_FULL_HELPER_COLD_REPLAY'}
  $out=[ordered]@{
    Schema=1;Revision='R350';Host=$HostLabel;SourceCommit=$env:QA_SOURCE_SHA
    Status=$status;Checks=@($checks);AlreadyAdminGuest=$true
    FullOriginalPEHelperAndAuthenticatedIPCExecuted=($negativeStatus -ne '')
    DistinctAlreadyAdminActorPid=$actorPid;ActorReceiptSHA256=$actorReceiptSha
    RefusalStatus=$negativeStatus;RecoveryStatus=$positiveStatus;FinalStatus=$finalStatus
    OriginalBrokerSHA256=$originalHash;RestoredBrokerSHA256=$restoredHash
    PREPAREDRetainedUnderPreopenedDelete=($negativeStatus -ceq 'DEGRADED_ROLLBACK_RECOVERY_REQUIRED')
    RecoveryAfterLeaseRelease=($positiveStatus -ceq 'DEGRADED_PREVIOUS_LAYER_RESTORED')
    RealInteractiveUacConsentTested=$false
    ConcurrentWriterDuringActualSuccessfulLeafCopyTested=$false
    NativeUserDeviceTouched=$false;FinalSecurityAcceptance=$false
    Failure=$failure
  }
  [IO.File]::WriteAllText($receipt,($out|ConvertTo-Json -Depth 6),
      [Text.UTF8Encoding]::new($false))
  'R350_FULL_HELPER_RECEIPT='+$receipt
  'R350_FULL_HELPER_STATUS='+$status+' CHECKS='+$checks.Count
 }
}
if($failure){throw ('R350_FULL_HELPER_NOT_ACCEPTED '+$failure)}
