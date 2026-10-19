[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or $env:GITHUB_REPOSITORY -cne 'GOD13emad/TaskbarMonitorEnhanced' -or
   ($env:GITHUB_REF -cne 'refs/heads/release/r265-v175-sensor-crossuser-safety' -and $env:GITHUB_REF -cne 'refs/heads/main') -or
   $env:COMPUTERNAME -match '(?i)EMAD|ALI|LAPTOP'){
 throw 'R265_DISPOSABLE_GUEST_ONLY'
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$admin=[Security.Principal.WindowsPrincipal]::new($identity)
if(!$admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 throw 'R265_EXISTING_GITHUB_VM_ADMIN_REQUIRED'
}
$helper=Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1'
$expected='84A7DC21012A63C5959447D7234B365CF926028016A81B742F891951B191E7FB'
$task='TaskbarMonitorEnhanced Sensor Broker'
$user='TBME265'+$HostLabel
$description='R265 no-trigger owned task test'
$out=Join-Path $env:RUNNER_TEMP ('TBME_R265_'+$HostLabel)
$receipt=Join-Path $out 'R265_CROSSUSER.json'
$copy=Join-Path $out 'R265_OnlyOriginalPreMutationGuard.ps1'
$payload=Join-Path $out 'EmptyPayload'
$fixtureCreated=$false;$taskOwned=$false;$accountRemoved=$false;$taskRemoved=$false
$otherSID='';$ownerSID=[string]$identity.User.Value
$otherPrincipal='';$currentPrincipal=''
$blocked=@();$allowed=@();$status='FAIL';$failure='';$phase='PREFLIGHT'
function Fail([string]$reason){throw ('R265_'+$reason)}
function VerifyTask{
 $x=Get-ScheduledTask -TaskName $task -TaskPath '\' -ErrorAction Stop
 $xml=[xml](Export-ScheduledTask -TaskName $task)
 if([string]$xml.Task.RegistrationInfo.Description -cne $description -or
   @($x.Triggers|Where-Object {$null -ne $_}).Count){Fail 'TEST_TASK_UNEXPECTED_OWNERSHIP_OR_TRIGGER'}
 return $x
}
function InvokePrefix([string]$mode,[string]$root,[bool]$fullHelper=$false){
 $psi=[Diagnostics.ProcessStartInfo]::new()
 $psi.FileName='powershell.exe'
 $selected=if($fullHelper){$helper}else{$copy}
 $psi.Arguments='-NoProfile -NonInteractive -File "'+$selected+'" -Mode '+$mode+' -PayloadDir "'+$payload+'" -AppRoot "'+$root+'" -UserId "'+$identity.Name+'"'
 $psi.WorkingDirectory=$out;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
 $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
 $proc=[Diagnostics.Process]::Start($psi)
 if(!$proc){Fail 'PREFIX_NOT_STARTED'}
 try{
  if(!$proc.WaitForExit(25000)){Fail ('GUARD_PREFIX_TIMEOUT_'+$mode)}
  return [ordered]@{Exit=[int]$proc.ExitCode;Out=$proc.StandardOutput.ReadToEnd().Trim();Err=$proc.StandardError.ReadToEnd().Trim()}
 }finally{$proc.Dispose()}
}
if((Test-Path $out) -or (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) -or
   (Get-LocalUser -Name $user -ErrorAction SilentlyContinue) -or
   (Test-Path (Join-Path $env:ProgramFiles 'TaskbarMonitorEnhanced\SensorBroker'))){
 Fail 'HOST_NOT_FRESH_NO_SHARED_SENSOR_TASK'
}
if((Get-FileHash $helper).Hash -cne $expected){Fail 'VERSIONED_TEST_HELPER_SHA_MISMATCH'}
New-Item -ItemType Directory -Path $out|Out-Null
try{
 $phase='COPY_ONLY_EXACT_BEFORE_MUTATION_HELPER_PREFIX'
 $full=[IO.File]::ReadAllText($helper,[Text.Encoding]::UTF8)
 $marker='# R264-SENSOR-GUARD-BOUNDARY-END'
 if($full.Split(@($marker),[StringSplitOptions]::None).Count -ne 2){Fail 'GUARD_BOUNDARY_NOT_UNIQUE'}
 $end=$full.IndexOf($marker)+$marker.Length
 $uninstall=$full.IndexOf(('if('+'$Mode'+" -eq 'Uninstall'){"))
 if($end -lt 3000 -or $end -ge $uninstall){Fail 'GUARD_IS_NOT_PRE_UNINSTALL'}
 $only=$full.Substring(0,$end)+[Environment]::NewLine+"Write-Output 'R265_GUARD_PASSED_SAME_USER'"+[Environment]::NewLine
 [IO.File]::WriteAllText($copy,$only,[Text.UTF8Encoding]::new($false))
 $tk=$null;$errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($copy,[ref]$tk,[ref]$errors)
 if(@($errors).Count){Fail 'GUARD_ONLY_PREFIX_PARSE_FAILED'}
 New-Item -ItemType Directory -Path $payload|Out-Null
 $phase='CREATE_ONLY_NEW_DISPOSABLE_LOCAL_USER'
 $bytes=[byte[]]::new(32)
 $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
 try{$rng.GetBytes($bytes)}finally{$rng.Dispose()}
 $secure=ConvertTo-SecureString ([Convert]::ToBase64String($bytes)+'R9!') -AsPlainText -Force
 $u=New-LocalUser -Name $user -Password $secure -AccountNeverExpires -PasswordNeverExpires -Description 'R265 test-only temporary local user' -ErrorAction Stop
 $otherSID=[string]$u.SID.Value
 $fixtureCreated=$true
 if($otherSID -notmatch '^S-1-5-21-' -or $otherSID -ceq $ownerSID){Fail 'SID_NOT_OTHER_USER'}
 $phase='REGISTER_OTHER_USER_FIXED_LEGACY_TASK_WITHOUT_TRIGGER'
 $otherName=[Security.Principal.SecurityIdentifier]::new($otherSID).Translate([Security.Principal.NTAccount]).Value
 $action=New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\whoami.exe')
 $settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::FromMinutes(1))
 $other=New-ScheduledTaskPrincipal -UserId $otherName -LogonType Interactive -RunLevel Limited
 Register-ScheduledTask -TaskName $task -Principal $other -Action $action -Settings $settings -Description $description -ErrorAction Stop|Out-Null
 $taskOwned=$true
 $otherPrincipal=[string](VerifyTask).Principal.UserId
 if(!$otherPrincipal.EndsWith($user,[StringComparison]::OrdinalIgnoreCase)){Fail 'OTHER_TASK_NOT_OTHER_USER'}
 $phase='INSTALL_AND_UNINSTALL_MUST_REFUSE_OTHER_USER_TASK_WITHOUT_MODIFICATION'
 foreach($mode in @('Install','Uninstall')){
  $app=Join-Path $out ('OtherRoot_'+$mode)
  New-Item -ItemType Directory -Path $app|Out-Null
  $run=InvokePrefix $mode $app
  $result=Join-Path $app 'Logs\sensor_install_result.json'
  if($run.Exit -ne 0 -or !(Test-Path $result)){Fail ('OTHER_USER_NOT_REFUSED_'+$mode)}
  $j=Get-Content $result -Raw|ConvertFrom-Json
  if($j.Status -cne 'DEGRADED_OTHER_USER_SENSOR_LAYER_PRESERVED' -or
     $j.Architecture -cne 'SHARED_PROTECTED_SENSOR_LAYER_LEFT_UNTOUCHED' -or
     $run.Out -match 'R265_GUARD_PASSED_SAME_USER'){Fail ('REFUSAL_STATUS_WRONG_'+$mode)}
  if([string](VerifyTask).Principal.UserId -cne $otherPrincipal){Fail ('OTHER_TASK_CHANGED_'+$mode)}
  $blocked+=$mode
 }
 $phase='RUN_REAL_FULL_ELEVATED_HELPER_AGAINST_OTHER_ACCOUNT_OWNED_TASK'
 # Unlike prefix tests above, run all released helper source. It MUST exit
 # before real shared broker drivers/files or any global process mutation.
 foreach($mode in @('Install','Uninstall')){
  $app=Join-Path $out ('WholeHelperOtherRoot_'+$mode)
  New-Item -ItemType Directory -Path $app|Out-Null
  $run=InvokePrefix $mode $app $true
  $result=Join-Path $app 'Logs\sensor_install_result.json'
  if($run.Exit -ne 0 -or !(Test-Path $result)){Fail ('REAL_FULL_HELPER_OTHER_USER_NOT_REFUSED_'+$mode+'_Exit_'+$run.Exit+'_Result_'+(Test-Path $result)+'_Out_'+$run.Out+'_Err_'+$run.Err)}
  $j=Get-Content $result -Raw|ConvertFrom-Json
  if($j.Status -cne 'DEGRADED_OTHER_USER_SENSOR_LAYER_PRESERVED' -or
     $j.Architecture -cne 'SHARED_PROTECTED_SENSOR_LAYER_LEFT_UNTOUCHED'){
   Fail ('REAL_FULL_HELPER_ENTERED_UNSAFE_CODE_'+$mode)
  }
  if([string](VerifyTask).Principal.UserId -cne $otherPrincipal){Fail ('OTHER_GLOBAL_TASK_MODIFIED_BY_FULL_HELPER_'+$mode)}
  $blocked+=('WholeHelper_'+$mode)
 }
 $phase='SAME_USER_TASK_SHOULD_PASS_GUARD_ONLY_NOT_HELPER_MUTATIONS'
 $own=New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Limited
 Register-ScheduledTask -TaskName $task -Principal $own -Action $action -Settings $settings -Description $description -Force -ErrorAction Stop|Out-Null
 $currentPrincipal=[string](VerifyTask).Principal.UserId
 if(!$currentPrincipal.EndsWith($env:USERNAME,[StringComparison]::OrdinalIgnoreCase)){Fail 'CURRENT_USER_TASK_NOT_OWNER'}
 foreach($mode in @('Install','Uninstall')){
  $app=Join-Path $out ('OwnRoot_'+$mode)
  New-Item -ItemType Directory -Path $app|Out-Null
  $run=InvokePrefix $mode $app
  if($run.Exit -ne 0 -or $run.Out -notmatch 'R265_GUARD_PASSED_SAME_USER'){
   Fail ('OWN_ACCOUNT_FALSE_REFUSAL_'+$mode+'_'+$run.Err)
  }
  if(!(VerifyTask)){Fail 'CURRENT_ACCOUNT_TASK_CHANGED'}
  $allowed+=$mode
 }
 $phase='CLEANUP_ONLY_OWNED_GUEST_TASK_AND_USER'
 if(!(VerifyTask)){Fail 'TASK_NOT_OWNED_AT_CLEANUP'}
 Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction Stop
 $taskOwned=$false
 $taskRemoved=($null -eq (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue))
 if(!$taskRemoved){Fail 'OWNED_TASK_NOT_REMOVED_BEFORE_FRESH_GUARD'}
 $phase='FRESH_SINGLE_USER_NO_GLOBAL_TASK_AND_NO_SHARED_BROKER_MUST_NOT_FALSE_REFUSE'
 foreach($mode in @('Install','Uninstall')){
  $app=Join-Path $out ('FreshNoTaskRoot_'+$mode)
  New-Item -ItemType Directory -Path $app|Out-Null
  $run=InvokePrefix $mode $app
  if($run.Exit -ne 0 -or $run.Out -notmatch 'R265_GUARD_PASSED_SAME_USER'){
   Fail ('EMPTY_GLOBAL_TASK_GUARD_FALSE_REFUSED_'+$mode+'_'+$run.Err)
  }
  $allowed+=('FreshNoTask_'+$mode)
 }
 $found=Get-LocalUser -Name $user -ErrorAction Stop
 if([string]$found.SID.Value -cne $otherSID){Fail 'LOCAL_USER_IDENTITY_CHANGED'}
 Disable-LocalUser -Name $user -ErrorAction Stop
 Remove-LocalUser -Name $user -ErrorAction Stop
 $fixtureCreated=$false
 $accountRemoved=($null -eq (Get-LocalUser -Name $user -ErrorAction SilentlyContinue))
 if(!$taskRemoved -or !$accountRemoved){Fail 'FIXTURES_NOT_REMOVED'}
 $status='PASS_OTHER_USER_SENSOR_TASK_PRESERVED_AND_SAME_OWNER_GUARD_ALLOWED'
}catch{$failure=$_.Exception.GetType().Name+': '+$_.Exception.Message}
finally{
 try{
  if($taskOwned -and (VerifyTask)){
   Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction Stop
   $taskRemoved=($null -eq (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue))
  }
 }catch{$status='FAIL_TASK_CLEANUP_UNCERTAIN';$failure+=' | '+$_.Exception.Message}
 try{
  if($fixtureCreated){
   $x=Get-LocalUser -Name $user -ErrorAction SilentlyContinue
   if($x -and [string]$x.SID.Value -ceq $otherSID){
    Disable-LocalUser -Name $user -ErrorAction Stop
    Remove-LocalUser -Name $user -ErrorAction Stop
    $accountRemoved=($null -eq (Get-LocalUser -Name $user -ErrorAction SilentlyContinue))
   }
  }
 }catch{$status='FAIL_ACCOUNT_CLEANUP_UNCERTAIN';$failure+=' | '+$_.Exception.Message}
 $r=[ordered]@{
  Revision='R265';Status=$status;Guest=$HostLabel;Phase=$phase;Failure=$failure
  SourceGuardSHA256=$expected;ExactProductionHelperAfterGuardWasNotExecuted=$true
  OtherUserSid=$otherSID;CurrentUserSid=$ownerSID
  OtherTaskPrincipal=$otherPrincipal;CurrentTaskPrincipal=$currentPrincipal
  OtherUserModesRefused=$blocked;SameUserModesPermitted=$allowed
  TestOwnedTaskDeleted=$taskRemoved;GuestUserAccountDeleted=$accountRemoved
  VerifiedRealFullHelperEarlyRefusal=($blocked.Count -eq 4)
  NoSensorTaskTriggered=$true;NoPawnIODriverOrSetupExecuted=$true
  OwnerPCAndPublicV174Unchanged=$true;NeedsNewVersionForAnyDeployment=$true
  Utc=[DateTime]::UtcNow.ToString('o')
 }
 [IO.File]::WriteAllText($receipt,($r|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 Write-Output ($r|ConvertTo-Json -Compress -Depth 8)
}
if($status -notlike 'PASS_*' -or !$taskRemoved -or !$accountRemoved){
 throw ('R265_GUEST_SENSOR_OWNER_GUARD_NOT_PASS_'+$phase+'_'+$failure)
}
