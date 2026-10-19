[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
  [Parameter(Mandatory=$true)][string]$CandidateRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# R339 native cross-account DACL/TOCTOU check is destructive ONLY to uniquely
# owned test fixtures on two short-lived github-hosted Windows VM runners.
# It does NOT test interactive UAC, the original Helper, or the owner's PC.
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'GOD13emad/TaskbarMonitorEnhanced' -or
   $env:GITHUB_REF -cne 'refs/heads/audit/r339-two-user-protected-broker' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC|ALIEMAD|SAEID|LAPTOP' -or
   $env:GITHUB_RUN_ID -cnotmatch '^\d{5,20}$' -or
   $env:GITHUB_SHA -cnotmatch '^[0-9a-f]{40}$'){
  throw 'R339_REFUSE_NON_DISPOSABLE_NATIVE_WINDOWS'
}
$root=(Resolve-Path -LiteralPath $CandidateRoot).Path
if((git -C $root rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){
  throw 'R339_PRODUCT_SOURCE_NOT_EXACT_RUNNING_SHA'
}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
  throw 'R339_ALREADY_ELEVATED_HOSTED_ADMIN_REQUIRED_NO_AUTO_UAC'
}
$parentSid=[string]([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
$program=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles))
$protectedRoot=Join-Path $program 'TaskbarMonitorEnhanced'
$brokerDir=Join-Path $protectedRoot 'SensorBroker'
$exe=Join-Path $brokerDir 'TaskbarMonitorSensorBroker.exe'
$supervisor=Join-Path $brokerDir 'TaskbarMonitorSensorSupervisor.exe'
$marker=Join-Path $brokerDir '.tbme-owner.sid'
$app=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'TaskbarMonitorEnhanced'
$cpu=Join-Path $app 'cpu_temp_broker.json'
$name='TBME339'+$HostLabel+$env:GITHUB_RUN_ID.Substring($env:GITHUB_RUN_ID.Length-7)
$shared=Join-Path $env:ProgramData ('TBME_R339_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$results=Join-Path $shared 'Results'
$authority=Join-Path $shared 'R339_AUTHORITY.json'
$workerPath=Join-Path $shared 'Test-R339-SecondAccount-Actor.ps1'
$childReceipt=Join-Path $results 'R339_B_RECEIPT.json'
$childReady=Join-Path $results 'R339_ACTOR_READY'
$out=Join-Path $env:RUNNER_TEMP ('R339_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $out 'R339_PROTECTED_PROGRAMFILES_TWO_USERS.json'
$inputBroker=Join-Path $root 'build\_out\Broker\TaskbarMonitorSensorBroker.exe'
$inputSupervisor=Join-Path $root 'build\_out\Supervisor\TaskbarMonitorSensorSupervisor.exe'
$native=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
$sourceActor=Join-Path $PSScriptRoot 'Test-R339-SecondAccount-Actor.ps1'
$ownerCreated=$false;$sharedCreated=$false;$appCreated=$false;$accountCreated=$false
$actorSid='';$child=$null;$childPid=0;$actorRead=$false;$rootRemoved=$false
$accountRemoved=$false;$sharedRemoved=$false;$appRemoved=$false
$denials=0;$concurrentChecks=0;$totalChecks=0;$failure='';$phase='PRECONDITION';$actorReceiptSha="NOT_ACCEPTED";$exitProvided=$false;$observedExit=$null
$checks=[Collections.Generic.List[string]]::new()
$initial=@{Broker="NOT_STARTED";Supervisor="NOT_STARTED";Owner="NOT_STARTED";Outside="NOT_STARTED"};$outsideCanary=''
function Hash([string]$path){return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
function Check([string]$name){$script:checks.Add($name);Write-Output ('PASS '+$name)}
function NewOwnedDirectory([string]$path,[bool]$writeForUsers){
  $admins=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
  $system=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
  $users=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
  $acl=[Security.AccessControl.DirectorySecurity]::new()
  $acl.SetOwner($admins);$acl.SetAccessRuleProtection($true,$false)
  foreach($sid in @($admins,$system,$users)){
    $rights=if($sid -eq $users){if($writeForUsers){[Security.AccessControl.FileSystemRights]::Modify}else{[Security.AccessControl.FileSystemRights]::ReadAndExecute}}else{[Security.AccessControl.FileSystemRights]::FullControl}
    $rule=[Security.AccessControl.FileSystemAccessRule]::new(
      $sid,$rights,[Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
      [Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
    [void]$acl.AddAccessRule($rule)
  }
  [void][IO.Directory]::CreateDirectory($path,$acl)
}
function AssertNoReparse([string]$path){
  if(([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw ('R339_DISPOSABLE_FIXTURE_BECAME_REPARSE '+[IO.Path]::GetFileName($path))
  }
}
function TryRemoveProtectedFixture(){
  if(!$script:ownerCreated -or ![IO.Directory]::Exists($protectedRoot)){return $false}
  AssertNoReparse $protectedRoot
  AssertNoReparse $brokerDir
  $entries=@([IO.Directory]::GetFileSystemEntries($protectedRoot))
  if($entries.Count -ne 1 -or $entries[0] -cne $brokerDir){throw 'R339_UNEXPECTED_PROTECTED_ROOT_MEMBER_KEEP_FOR_GUEST_DISPOSAL'}
  $files=@([IO.Directory]::GetFileSystemEntries($brokerDir))
  if($files.Count -ne 3 -or @($files|Where-Object {$_ -notin @($exe,$supervisor,$marker)}).Count){
    throw 'R339_UNEXPECTED_BROKER_FOLDER_MEMBER_KEEP_FOR_GUEST_DISPOSAL'
  }
  foreach($file in @($exe,$supervisor,$marker)){
    AssertNoReparse $file
    if($file -eq $exe -and (Hash $file) -cne $initial.Broker){throw 'R339_BROKER_MUTATED_KEEP_EVIDENCE'}
    if($file -eq $supervisor -and (Hash $file) -cne $initial.Supervisor){throw 'R339_SUPERVISOR_MUTATED_KEEP_EVIDENCE'}
  }
  foreach($file in @($exe,$supervisor,$marker)){[IO.File]::Delete($file)}
  [IO.Directory]::Delete($brokerDir,$false)
  [IO.Directory]::Delete($protectedRoot,$false)
  return !$([IO.Directory]::Exists($protectedRoot))
}
try{
  # The exact runner was verified empty immediately before Build.ps1. Its
  # selftests may create an innocuous LocalAppData scratch directory. Do not
  # treat that directory as an installation, nor delete preexisting bytes.
  foreach($entry in @($protectedRoot,$shared,$out)){
    if(Test-Path -LiteralPath $entry){throw ('R339_PROTECTED_OR_RECEIPT_FIXTURE_PREEXISTS '+$entry)}
  }
  if(Test-Path -LiteralPath $app){
    if(!(Test-Path -LiteralPath $app -PathType Container) -or
       @(Get-ChildItem -LiteralPath $app -Force -File -ErrorAction Stop |
         Where-Object {$_.Name -in @('TaskbarMonitorEnhanced.exe','Uninstall.exe','install_state.json','config.json')}).Count -gt 0 -or
       (Test-Path -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TaskbarMonitorEnhanced')){
      throw 'R339_BUILD_CREATED_OR_EXISTING_REAL_INSTALLATION_REFUSED'
    }
    $appRemoved=$true # No new app root was created, preserve all prior scratch.
    $checks.Add('PREEXISTING_BUILD_SELFTEST_LOCALAPPDATA_ROOT_PRESERVED')
  }
  if((Get-LocalUser -Name $name -ErrorAction SilentlyContinue) -or
     @(Get-Process TaskbarMonitorEnhanced,TaskbarMonitorSensorSupervisor,TaskbarMonitorSensorBroker -ErrorAction SilentlyContinue).Count){
    throw 'R339_PREEXISTING_ACCOUNT_OR_REAL_PRODUCT_PROCESS'
  }
  if(@(Get-ScheduledTask -TaskPath '\' -TaskName 'TaskbarMonitorEnhanced Sensor Broker' -ErrorAction SilentlyContinue |Where-Object {$null -ne $_}).Count){
    throw 'R339_PREEXISTING_PRODUCT_SCHEDULED_TASK'
  }
  foreach($file in @($inputBroker,$inputSupervisor,$sourceActor,$native)){
    if(![IO.File]::Exists($file)){throw 'R339_CANDIDATE_SOURCE_OR_SYSTEM_EXECUTABLE_MISSING'}
  }
  [void][IO.Directory]::CreateDirectory($out)
  Check 'DISPOSABLE_RUNNER_FRESH_PRODUCT_ACCOUNT_AND_SCHEDULER_PRECONDITIONS'
  $phase='CREATE_EXACT_NEW_PROTECTED_PROGRAMFILES_FIXTURE'
  NewOwnedDirectory $protectedRoot $false
  $ownerCreated=$true
  [void][IO.Directory]::CreateDirectory($brokerDir)
  [IO.File]::Copy($inputBroker,$exe)
  [IO.File]::Copy($inputSupervisor,$supervisor)
  [IO.File]::WriteAllText($marker,$parentSid,[Text.UTF8Encoding]::new($false))
  $initial=@{Broker=Hash $exe;Supervisor=Hash $supervisor;Owner=Hash $marker}
  if($initial.Broker -cne (Hash $inputBroker) -or $initial.Supervisor -cne (Hash $inputSupervisor)){
    throw 'R339_PRIVATE_COMPILED_SOURCE_BYTES_NOT_EXACT'
  }
  $dirAcl=Get-Acl -LiteralPath $brokerDir
  $exeAcl=Get-Acl -LiteralPath $exe
  if([string]$dirAcl.Owner -notmatch '(?i)Administrators' -or [string]$exeAcl.Owner -notmatch '(?i)Administrators'){
    throw 'R339_PROTECTED_FIXTURE_NOT_ADMINISTRATOR_OWNED'
  }
  foreach($acl in @($dirAcl,$exeAcl)){
    foreach($ace in @($acl.Access|Where-Object{$_.IdentityReference.Value -match '(?i)BUILTIN\\Users'})){
      if($ace.FileSystemRights.ToString() -match '(?i)Write|Modify|FullControl|Delete|ChangePermissions|TakeOwnership'){
        throw 'R339_USERS_HAVE_WRITE_ON_PROTECTED_FIXTURE'
      }
    }
  }
  Check 'REAL_PROGRAMFILES_PROTECTED_ACL_NO_OTHER_USERS_WRITE_AND_COMPILED_BINARY_BYTES_PINNED'
  $phase='PREPARE_SCOPED_OTHER_ACCOUNT_SCRATCH'
  NewOwnedDirectory $shared $false
  $sharedCreated=$true
  NewOwnedDirectory $results $true
  [IO.File]::Copy($sourceActor,$workerPath)
  if((Hash $workerPath) -cne (Hash $sourceActor)){throw 'R339_WORKER_COPY_CHANGED_BEFORE_CREDENTIAL_RUN'}
  if(-not [IO.Directory]::Exists($app)){
    [void][IO.Directory]::CreateDirectory($app)
    $appCreated=$true
  }
  $outsideCanary=Join-Path $out 'FOREIGN_CANARY.txt'
  [IO.File]::WriteAllText($outsideCanary,'R339_OUTSIDE_CANARY_UNCHANGED',[Text.UTF8Encoding]::new($false))
  $initial.Outside=Hash $outsideCanary
  Check 'ONLY_WHITELISTED_PROGRAMFILES_AND_PROGRAMDATA_FIXTURES_CREATED'
  $phase='CREATE_ACTUAL_OTHER_LOCAL_WINDOWS_SID'
  $bytes=[byte[]]::new(32)
  $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
  try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
  $secret=[Convert]::ToBase64String($bytes)+'A2!'
  $secure=ConvertTo-SecureString $secret -AsPlainText -Force
  $credential=[Management.Automation.PSCredential]::new(($env:COMPUTERNAME+'\'+$name),$secure)
  $secret=$null
  $account=New-LocalUser -Name $name -Password $secure -AccountNeverExpires -Description 'R339 disposable Windows ACL test'
  $accountCreated=$true
  $actorSid=[string]$account.SID.Value
  if($actorSid -cnotmatch '^S-1-5-21-' -or $actorSid -ceq $parentSid){throw 'R339_SECOND_WINDOWS_ACCOUNT_NOT_DISTINCT'}
  Check 'REAL_OTHER_LOCAL_NONADMIN_SID_CREATED_ON_DISPOSABLE_HOST'
  $authorityData=[ordered]@{
    Revision='R339';SourceCommit=$env:GITHUB_SHA;HostLabel=$HostLabel
    HostComputerName=$env:COMPUTERNAME;ParentSid=$parentSid
    ExpectedActorSid=$actorSid;ProtectedBrokerPath=$exe
    ExpectedBrokerSHA256=$initial.Broker;ExpectedSupervisorSHA256=$initial.Supervisor
  }
  [IO.File]::WriteAllText($authority,($authorityData|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
  $phase='COMPILLED_PRODUCTION_TRUST_PATH_BEFORE_ACTOR'
  $assembly=[Reflection.Assembly]::LoadFrom($inputSupervisor)
  $type=$assembly.GetType('TaskbarMonitorSensorSupervisor',$true)
  $method=$type.GetMethod('TrustedWorkerPaths',[Reflection.BindingFlags]'NonPublic,Static')
  if(!$method){throw 'R339_PRODUCTION_SOURCE_TRUST_METHOD_MISSING'}
  $args=New-Object 'object[]' 6
  $values=[string[]]@($exe,$cpu,$brokerDir,$program,[Environment]::GetFolderPath('UserProfile'),
                            [Environment]::GetFolderPath('LocalApplicationData'))
  for($i=0;$i -lt $values.Length;$i++){$args[$i]=$values[$i]}
  if(!([bool]$method.Invoke($null,$args))){throw 'R339_PRODUCTION_SUPERVISOR_PROTECTED_KNOWN_PATH_NOT_ACCEPTED'}
  Check 'EXACT_COMPILED_PRODUCTION_TRUST_GUARD_ACCEPTS_OWN_PROTECTED_FIXTURE'
  $phase='START_ACTUAL_OTHER_NONADMIN_ACCOUNT'
  $arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$workerPath+'" -AuthorityPath "'+$authority+'" -ReceiptPath "'+$childReceipt+'"'
  $child=Start-Process -FilePath $native -ArgumentList $arguments -Credential $credential -LoadUserProfile -PassThru -WindowStyle Hidden -WorkingDirectory $shared -ErrorAction Stop
  if(!$child){throw 'R339_DIFFERENT_USER_PROCESS_FAILED_TO_START'}
  $childPid=$child.Id
  $started=[Diagnostics.Stopwatch]::StartNew()
  while(![IO.File]::Exists($childReady) -and !$child.HasExited -and $started.Elapsed.TotalSeconds -lt 25){
    Start-Sleep -Milliseconds 100
  }
  if(![IO.File]::Exists($childReady)){throw 'R339_OTHER_LOCAL_ACTOR_DID_NOT_REACH_MUTATION_CHECKPOINT'}
  Check 'OTHER_SID_ACTOR_REACHED_CONCURRENT_MUTATION_CHECKPOINT'
  $phase='ADMIN_PRODUCTION_GUARD_WHILE_OTHER_SID_ATTEMPTS_MUTATION'
  while(!$child.HasExited -and $concurrentChecks -lt 100){
    if(!([bool]$method.Invoke($null,$args))){throw 'R339_TRUST_GUARD_LOST_VALID_PROTECTED_PATH_DURING_ATTACK'}
    if((Hash $exe) -cne $initial.Broker -or (Hash $supervisor) -cne $initial.Supervisor){
      throw 'R339_BINARY_DRIFT_DURING_OTHER_NONADMIN_SID_ATTACK'
    }
    $concurrentChecks++
    Start-Sleep -Milliseconds 30
  }
  if(!$child.WaitForExit(25000)){throw 'R339_SECOND_USER_ATTACK_PROCESS_TIMEOUT'}
  # Native Windows Start-Process -Credential/-LoadUserProfile can yield a
  # Process wrapper with a null ExitCode even after WaitForExit succeeds.
  # A nonzero provided ExitCode is fatal. Missing code requires successful
  # WaitForExit AND independently verified exact-SID typed guest receipt,
  # 420 actual operation refusals and unchanged protected binary hashes.
  $observedExit=$child.ExitCode
  $exitProvided=($null -ne $observedExit)
  if($exitProvided -and [int]$observedExit -ne 0){
    throw ('R339_SECOND_USER_RETURNED_NONZERO_'+$observedExit)
  }
  if($concurrentChecks -lt 1){throw 'R339_NO_CONCURRENT_OWNER_GUARD_WITNESS'}
  Check 'ADMIN_REAL_COMPILED_SUPERVISOR_TRUST_READS_DURING_ACTUAL_OTHER_USER_ATTACK'
  $phase='VERIFY_OTHER_USER_TYPED_RECEIPT_AND_BOUNDARIES'
  if(![IO.File]::Exists($childReceipt)){throw 'R339_OTHER_ACCOUNT_RECEIPT_NOT_RETURNED'}
  $guest=Get-Content -LiteralPath $childReceipt -Raw|ConvertFrom-Json
  if($guest.Status -cne 'PASS_SECOND_REAL_LOCAL_SID_DENIED_420_PROTECTED_MUTATIONS' -or
     $guest.ActorSid -cne $actorSid -or
     $guest.ParentSid -cne $parentSid -or
     $guest.ActualDifferentLocalAccount -ne $true -or
     $guest.ActorIsAdmin -ne $false -or
     $guest.CanReadProtectedBroker -ne $true -or
     $guest.SourceCommit -cne $env:GITHUB_SHA -or
     $guest.ActualUacPromptTested -ne $false -or
     @($guest.Checks).Count -ne 3 -or
     @($guest.DeniedByOperation.PSObject.Properties.Value |Where-Object{$_ -ne 60}).Count -gt 0){
    throw ('R339_DIFFERENT_TOKEN_RECEIPT_NEGATIVE_FAIL '+($guest|ConvertTo-Json -Depth 3 -Compress))
  }
  $actorRead=$true
  $actorReceiptSha=Hash $childReceipt
  $denials=420
  if((Hash $exe) -cne $initial.Broker -or (Hash $supervisor) -cne $initial.Supervisor -or
     (Hash $marker) -cne $initial.Owner -or
     (Hash $outsideCanary) -cne $initial.Outside){
    throw 'R339_PROTECTED_FILES_OR_EXTERNAL_CANARY_CHANGED_BY_OTHER_SID'
  }
  Check '420_OTHER_SID_PROTECTED_RENAME_OVERWRITE_DELETE_LINK_OPERATIONS_DENIED_AND_HASHES_STABLE'
}catch{
  $failure=$_.Exception.GetType().Name+': '+$_.Exception.Message+' PHASE='+$phase
}finally{
  if($child){
    try{if(!$child.HasExited){$child.Kill();[void]$child.WaitForExit(8000)}}catch{}
    $child.Dispose()
  }
  if($accountCreated){
    try{
      $accountNow=Get-LocalUser -Name $name -ErrorAction SilentlyContinue
      if($accountNow -and [string]$accountNow.SID.Value -ceq $actorSid){
        Disable-LocalUser -Name $name -ErrorAction Stop
        Remove-LocalUser -Name $name -ErrorAction Stop
        $accountRemoved=($null -eq (Get-LocalUser -Name $name -ErrorAction SilentlyContinue))
      }
    }catch{ $failure+= ' ACCOUNT_CLEANUP_FAILED='+$_.Exception.Message}
  }
  if($ownerCreated){
    try{$rootRemoved=TryRemoveProtectedFixture}
    catch{$failure+=' PROTECTED_FIXTURE_CLEANUP_REFUSED='+$_.Exception.Message}
  }
  if($appCreated){
    try{
      if([IO.Directory]::Exists($app) -and @([IO.Directory]::GetFileSystemEntries($app)).Count -eq 0){
        [IO.Directory]::Delete($app,$false)
      }
      $appRemoved=(![IO.Directory]::Exists($app))
    }catch{$failure+=' DISPOSABLE_LOCALAPP_CLEANUP_REFUSED='+$_.Exception.Message}
  }
  if($sharedCreated){
    try{
      foreach($f in @($childReady,$childReceipt,$authority,$workerPath)){
        if([IO.File]::Exists($f)){[IO.File]::Delete($f)}
      }
      if([IO.Directory]::Exists($results)){[IO.Directory]::Delete($results,$false)}
      if([IO.Directory]::Exists($shared)){[IO.Directory]::Delete($shared,$false)}
      $sharedRemoved=(![IO.Directory]::Exists($shared))
    }catch{$failure+=' DISPOSABLE_SHARE_CLEANUP_REFUSED='+$_.Exception.Message}
  }
  if($accountCreated -and !$accountRemoved){$failure+=' OTHER_SID_ACCOUNT_CLEANUP_INCOMPLETE'}
  if($ownerCreated -and !$rootRemoved){$failure+=' PROTECTED_TEST_ROOT_CLEANUP_INCOMPLETE'}
  if($sharedCreated -and !$sharedRemoved){$failure+=' PROGRAMDATA_FIXTURE_CLEANUP_INCOMPLETE'}
  if($appCreated -and !$appRemoved){$failure+=' CREATED_USER_APP_ROOT_CLEANUP_INCOMPLETE'}
  $status=if(!$failure -and $actorRead -and $denials -eq 420 -and $checks.Count -eq $(if($appCreated){8}else{9}) -and $concurrentChecks -ge 1){
    'PASS_REAL_NONADMIN_SECOND_SID_PROTECTED_PROGRAMFILES_CONCURRENT_REFUSAL'
  }else{'FAIL_CLOSED_DISPOSABLE_WINDOWS_ONLY'}
  $data=[ordered]@{
    Schema=1;Revision='R339';Status=$status;SourceCommit=$env:GITHUB_SHA;Host=$HostLabel
    HostType='github-hosted-disposable-Windows'
    ActorAAlreadyAdmin=$true;ActorBSID=$actorSid;ActorASID=$parentSid
    RealDistinctSecondNonAdminAccount=$actorRead;DeniedMutationCount=$denials;AttemptedOperationKinds=7
    ActualProductionTrustGuardConcurrentChecks=$concurrentChecks
    OtherAccountNativeProcessExitCodeProvided=$exitProvided
    OtherAccountNativeProcessExitCode=$observedExit
    OtherAccountReceiptSha256=$actorReceiptSha
    ProtectedBrokerSHA256=$initial.Broker;ProtectedSupervisorSHA256=$initial.Supervisor
    WindowsProtectedProgramFilesFixtureWasCreated=$ownerCreated
    PreExistingBuildOnlyLocalAppRootRetained=(!$appCreated -and [IO.Directory]::Exists($app))
    WindowsProtectedProgramFilesFixtureRemoved=$rootRemoved
    DisposableSecondAccountRemoved=$accountRemoved;DisposableProgramDataRemoved=$sharedRemoved
    DisposableProfileAppRootCreatedByTest=$appCreated
    DisposableProfileAppRootRemovedIfCreated=($appCreated -and $appRemoved)
    TrueInteractiveUacConsentTested=$false
    OriginalElevatedSensorHelperStartedOrKilled=$false
    OriginalOwnerComputerTouched=$false;OriginalReleaseOrDriversModified=$false
    Checks=@($checks);Failure=$failure
    RecordedUtc=[DateTime]::UtcNow.ToString('o')
  }
  if([IO.Directory]::Exists($out)){
    [IO.File]::WriteAllText($receipt,($data|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
    Write-Output ('R339_RECEIPT='+$receipt)
  }
  Write-Output ('R339_RESULT='+$status+' CHECKS='+$checks.Count+' DENIALS='+$denials+' CONCURRENT='+$concurrentChecks)
}
if($failure){throw ('R339_CROSS_ACCOUNT_NATIVE_REFUSAL_NOT_ACCEPTED '+$failure)}
