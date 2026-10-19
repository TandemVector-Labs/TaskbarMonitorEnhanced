[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$AuthorityPath,
  [Parameter(Mandatory=$true)][string]$ReceiptPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# R339 only runs as the actual newly-created *nonadmin* SID on an isolated
# GitHub-hosted Windows runner. It never executes a SensorBroker or installer.
if($env:COMPUTERNAME -match '(?i)EMAD-PC|ALIEMAD|SAEID|LAPTOP'){
  throw 'R339_SECOND_ACCOUNT_REFUSE_KNOWN_OWNER_MACHINE'
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
  throw 'R339_SECOND_ACCOUNT_MUST_NOT_BE_ADMIN'
}
$sid=[string]$identity.User.Value
if($sid -cnotmatch '^S-1-5-21-(?:\d+-){3}\d+$'){
  throw 'R339_NONADMIN_SID_EXPECTED'
}
$program=[IO.Path]::GetFullPath([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles))
$expectedProgram=Join-Path $program 'TaskbarMonitorEnhanced'
$expectedBrokerDir=Join-Path $expectedProgram 'SensorBroker'
$expectedExe=Join-Path $expectedBrokerDir 'TaskbarMonitorSensorBroker.exe'
$expectedSupervisor=Join-Path $expectedBrokerDir 'TaskbarMonitorSensorSupervisor.exe'
$allowedSharedRoot=[IO.Path]::GetFullPath((Join-Path $env:ProgramData 'R339_' ))
$authority=[IO.Path]::GetFullPath($AuthorityPath)
$parentDir=[IO.Path]::GetDirectoryName($authority)
$resultsDir=Join-Path $parentDir 'Results'
$expectedReceipt=Join-Path $resultsDir 'R339_B_RECEIPT.json'
if($parentDir -cnotmatch '[/\\]TBME_R339_[AB]_\d{5,20}$' -or
   ![string]::Equals($authority,(Join-Path $parentDir 'R339_AUTHORITY.json'),[StringComparison]::OrdinalIgnoreCase) -or
   ![string]::Equals([IO.Path]::GetFullPath($ReceiptPath),$expectedReceipt,[StringComparison]::OrdinalIgnoreCase) -or
   -not $parentDir.StartsWith(($env:ProgramData.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){
  throw 'R339_SECOND_ACCOUNT_AUTHORITY_OUTSIDE_OWNED_PROGRAMDATA'
}
if(!(Test-Path -LiteralPath $authority -PathType Leaf) -or
   !(Test-Path -LiteralPath $expectedExe -PathType Leaf) -or
   !(Test-Path -LiteralPath $expectedSupervisor -PathType Leaf)){
  throw 'R339_SECOND_ACCOUNT_AUTHORITY_OR_PROTECTED_FILES_ABSENT'
}
$j=Get-Content -LiteralPath $authority -Raw|ConvertFrom-Json
if($j.Revision -cne 'R339' -or $j.ExpectedActorSid -cne $sid -or
   $j.HostComputerName -cne $env:COMPUTERNAME -or
   $j.ProtectedBrokerPath -cne $expectedExe -or
   $j.SourceCommit -cnotmatch '^[0-9a-f]{40}$'){
  throw 'R339_SECOND_ACCOUNT_AUTHORITY_NOT_BOUND_TO_TOKEN_AND_ROOT'
}
if(Test-Path -LiteralPath $expectedReceipt){throw 'R339_ACTOR_RECEIPT_PREEXISTS'}
$denials=[ordered]@{
  ProtectedRootRename=0;BrokerFolderRename=0;
  BrokerExecutableOverwrite=0;BrokerExecutableDelete=0;
  UnexpectedChildDirectory=0;UnexpectedJunction=0;
  SupervisorExecutableOverwrite=0
}
$failure=''
$canReadProtected=$false
$checks=[Collections.Generic.List[string]]::new()
$beforeExe=''
function Hash([string]$p){return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash}
function RefuseMutation([string]$label,[scriptblock]$action){
  try{
    & $action | Out-Null
    throw ('R339_ACTOR_WRITE_SUCCEEDED_'+$label)
  }catch{
    if($_.Exception.Message.StartsWith('R339_ACTOR_WRITE_SUCCEEDED_',[StringComparison]::Ordinal)){
      throw
    }
    $reason=$_.Exception
    $allowed=$false
    while($reason){
      if($reason -is [UnauthorizedAccessException] -or
         $reason -is [Security.SecurityException] -or
         $reason.HResult -eq -2147024891 -or
         ($reason -is [IO.IOException] -and $reason.Message -match '(?i)denied|permission|access|privilege')){
        $allowed=$true;break
      }
      $reason=$reason.InnerException
    }
    if(!$allowed){
      throw ('R339_UNEXPECTED_MUTATION_FAILURE_TYPE_'+$label+' '+$_.Exception.Message)
    }
    $script:denials[$label]=[int]$script:denials[$label]+1
  }
}
try{
  if((Hash $expectedExe) -cne [string]$j.ExpectedBrokerSHA256 -or
     (Hash $expectedSupervisor) -cne [string]$j.ExpectedSupervisorSHA256){
    throw 'R339_ACTOR_CANNOT_READ_EXACT_PROTECTED_FILES'
  }
  $canReadProtected=$true
  $beforeExe=Hash $expectedExe
  $checks.Add('ACTUAL_OTHER_LOCAL_WINDOWS_SID_NONADMIN_READS_PROTECTED_BINARY')
  # This checkpoint lets the owning high-integrity test actor begin its
  # in-memory production guard reads before the attempts start.
  [IO.File]::WriteAllText((Join-Path $resultsDir 'R339_ACTOR_READY'),'SECOND_USER_BOUND',[Text.UTF8Encoding]::new($false))
  Start-Sleep -Milliseconds 450
  for($i=0;$i -lt 60;$i++){
    RefuseMutation 'ProtectedRootRename' {
      [IO.Directory]::Move($expectedProgram,($expectedProgram+'_foreign'))
    }
    RefuseMutation 'BrokerFolderRename' {
      [IO.Directory]::Move($expectedBrokerDir,($expectedBrokerDir+'_foreign'))
    }
    RefuseMutation 'BrokerExecutableOverwrite' {
      [IO.File]::WriteAllText($expectedExe,'UNAUTHORIZED_R339_WRITE')
    }
    RefuseMutation 'BrokerExecutableDelete' {
      [IO.File]::Delete($expectedExe)
    }
    RefuseMutation 'UnexpectedChildDirectory' {
      [void][IO.Directory]::CreateDirectory((Join-Path $expectedBrokerDir 'R339_UNAUTHORISED_SUBDIR'))
    }
    RefuseMutation 'UnexpectedJunction' {
      New-Item -ItemType Junction -Path (Join-Path $expectedBrokerDir 'R339_UNAUTHORISED_LINK') -Target $resultsDir -ErrorAction Stop | Out-Null
    }
    RefuseMutation 'SupervisorExecutableOverwrite' {
      [IO.File]::WriteAllText($expectedSupervisor,'UNAUTHORIZED_R339_SUPERVISOR_WRITE')
    }
    if($i%10 -eq 0){Start-Sleep -Milliseconds 15}
  }
  if(@($denials.Values |Where-Object{$_ -ne 60}).Count){
    throw 'R339_B_ACTOR_NOT_ALL_MUTATIONS_ACCESS_DENIED'
  }
  $checks.Add('420_ACTUAL_NONADMIN_MUTATIONS_ALL_ACCESS_DENIED')
  if((Hash $expectedExe) -cne $beforeExe -or
     (Hash $expectedSupervisor) -cne [string]$j.ExpectedSupervisorSHA256){
    throw 'R339_ACTOR_PROTECTED_BYTES_CHANGED'
  }
  $checks.Add('OTHER_ACCOUNT_PROTECTED_EXE_BYTES_STILL_PINNED')
}catch{
  $failure=$_.Exception.GetType().Name+': '+$_.Exception.Message
}finally{
  $status=if(!$failure -and $checks.Count -eq 3){'PASS_SECOND_REAL_LOCAL_SID_DENIED_420_PROTECTED_MUTATIONS'}else{'FAIL_SECOND_ACCOUNT'}
  $out=[ordered]@{
    Schema=1;Revision='R339';Status=$status
    SourceCommit=$j.SourceCommit;Host=$j.HostLabel
    ActorSid=$sid;ActorIsAdmin=$false;ParentSid=$j.ParentSid
    ActualDifferentLocalAccount=($sid -cne $j.ParentSid)
    CanReadProtectedBroker=$canReadProtected;DeniedByOperation=$denials
    ProtectedBrokerHashBefore=$beforeExe;ExpectedBrokerSHA256=$j.ExpectedBrokerSHA256
    Iterations=60;Checks=@($checks);Failure=$failure
    ActualUacPromptTested=$false;ActualOriginalHelperStarted=$false
    OwnerMachineTouched=$false
  }
  [IO.File]::WriteAllText($expectedReceipt,($out|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
  Write-Output ('R339_OTHER_USER_STATUS='+$status)
}
if($failure){throw ('R339_ACTOR_MUTATION_REFUSAL_FAILED '+$failure)}
