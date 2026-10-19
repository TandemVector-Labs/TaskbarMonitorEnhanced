[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$BrokerPath,
 [Parameter(Mandatory=$true)][string]$ReceiptPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'GOD13emad/TaskbarMonitorEnhanced' -or
   $env:GITHUB_REF -cne 'refs/heads/audit/r347-protected-broker-handle-lease' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC|ALIEMAD|SAEID|LAPTOP'){
 throw 'R347_ADMIN_ACTOR_REFUSES_NONHOSTED_WINDOWS'
}
$admin=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 throw 'R347_ADMIN_ACTOR_REQUIRES_ALREADY_ADMIN_TOKEN'
}
$pf=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles))
$root=Join-Path $pf 'TaskbarMonitorEnhanced'
$broker=Join-Path $root 'SensorBroker'
if(-not [string]::Equals([IO.Path]::GetFullPath($BrokerPath),$broker,[StringComparison]::OrdinalIgnoreCase)){
 throw 'R347_ACTOR_BROKER_NOT_EXACT_PROTECTED_PATH'
}
$receipt=[IO.Path]::GetFullPath($ReceiptPath)
if($receipt -notlike ([IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')+'\R347_*')){
 throw 'R347_ACTOR_RECEIPT_OUTSIDE_RUNNER_TEMP'
}
if([IO.File]::Exists($receipt)){throw 'R347_OTHER_ADMIN_RECEIPT_ALREADY_EXISTS'}
$attempts=80;$d1=0;$d2=0;$failure=''
function TryRename([string]$which,[string]$old,[string]$dest){
 try{
  [IO.Directory]::Move($old,$dest)
  throw ('R347_UNEXPECTED_PRIVILEGED_DIRECTORY_RENAME_SUCCEEDED_'+$which)
 }catch{
  if($_.Exception.Message.StartsWith('R347_UNEXPECTED_',[StringComparison]::Ordinal)){throw}
  # .NET static Directory.Move under Windows PowerShell 5.1 wraps the
  # underlying Win32 IOException in MethodInvocationException. Only unwrap
  # a proven sharing/access denial; reject all unrelated native failures.
  $e=$_.Exception
  while($e -is [Management.Automation.MethodInvocationException] -and $e.InnerException){
   $e=$e.InnerException
  }
  $allowedHResult=($e.HResult -in @(-2147024864,-2147024891,-2147024863))
  $allowedMessage=($e.Message -match '(?i)sharing violation|being used by another process|access (is )?denied')
  if(-not (($e -is [IO.IOException] -or $e -is [UnauthorizedAccessException]) -and
           ($allowedHResult -or $allowedMessage))){
   throw ('R347_UNEXPECTED_RENAME_FAILURE_CAUSE_'+$which+
     '_'+$e.GetType().Name+'_HRESULT_'+$e.HResult+'_MSG_'+$e.Message)
  }
  if([IO.Directory]::Exists($dest) -or -not [IO.Directory]::Exists($old)){
   throw ('R347_PROTECTED_PATH_CHANGED_DURING_DENIAL_'+$which)
  }
  if($which -eq 'Broker'){$script:d1++}else{$script:d2++}
 }
}
try{
 for($i=0;$i -lt $attempts;$i++){
  TryRename 'Broker' $broker ($broker+'_R347_unexpected')
  TryRename 'Product' $root ($root+'_R347_unexpected')
  Start-Sleep -Milliseconds 5
 }
}catch{$failure=$_.Exception.ToString()}
$status=if(-not $failure -and $d1 -eq $attempts -and $d2 -eq $attempts){
 'PASS_ADMIN_RENAME_DENIED_DURING_PINNED_ANCESTOR_HANDLES'
}else{'FAIL_R347_ADMIN_RENAME_ACTOR'}
[IO.File]::WriteAllText($receipt,([ordered]@{
 Schema=1;Revision='R347';Status=$status
 Host=$env:COMPUTERNAME;SourceCommit=$env:GITHUB_SHA
 ActorPid=$PID;ActorAlreadyAdmin=$true
 AttemptsPerPath=$attempts;BrokerRenameDenied=$d1;ProductRenameDenied=$d2
 ProgramFilesProtectedPath=$broker;Failure=$failure
}|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Write-Output ('R347_ACTOR_STATUS='+$status+' ATTEMPTS='+($d1+$d2))
if($failure){throw ('R347_ACTOR_FAILED '+$failure)}
