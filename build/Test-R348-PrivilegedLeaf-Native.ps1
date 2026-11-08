[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$SourceRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'GOD13emad/TaskbarMonitorEnhanced' -or
   $env:GITHUB_REF -cne 'refs/heads/audit/r348-privileged-leaf-race-negative' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC|ALIEMAD|SAEID|LAPTOP' -or
   $env:GITHUB_SHA -cnotmatch '^[0-9a-f]{40}$' -or
   $env:GITHUB_RUN_ID -cnotmatch '^[0-9]{5,20}$' -or
   (git -C $SourceRoot rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){
 throw 'R348_GUEST_ONLY_HOSTED_EXACT_REVISION'
}
$who=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(!$who.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 throw 'R348_REQUIRE_EXISTING_ADMIN_NO_UAC_BYPASS'
}
$pf=[Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
$product=Join-Path $pf 'TaskbarMonitorEnhanced'
$broker=Join-Path $product 'SensorBroker'
$leaf=Join-Path $broker 'R348_KNOWN_LEAF.txt'
$runRoot=Join-Path $env:RUNNER_TEMP ('R348_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$authority=Join-Path $runRoot 'R348_AUTHORITY.json'
$actorReceipt=Join-Path $runRoot 'R348_ACTOR_RECEIPT.json'
$receipt=Join-Path $runRoot 'R348_PRIVILEGED_LEAF_NEGATIVE.json'
$outside=Join-Path $runRoot 'OUTSIDE_CANARY.txt'
$source=Join-Path $SourceRoot 'installer\TBME_Setup_Elevated_Helper.ps1'
$setup=Join-Path $SourceRoot 'build\_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$actorFile=Join-Path $SourceRoot 'build\Test-R348-PrivilegedLeaf-Actor.ps1'
$native=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
$oldText='R348_BASELINE_'+$env:GITHUB_RUN_ID+'_'+$HostLabel
$newText='R348_ACTOR_WRITE_'+$env:GITHUB_RUN_ID+'_'+$HostLabel
$lease=$null;$child=$null;$protectedOwned=$false
$checks=[Collections.Generic.List[string]]::new()
$failure='';$observedGap=$false;$clean=$false;$childPid=0;$oldSha='';$newSha='';$actorSha='';$canarySha=''
function Hash([string]$f){return (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash}
function Pass([string]$msg){$script:checks.Add($msg);Write-Output ('PASS '+$msg)}
try{
 if([IO.Directory]::Exists($product) -or [IO.Directory]::Exists($runRoot) -or
    @(Get-Process TaskbarMonitorEnhanced,TaskbarMonitorSensorBroker,TaskbarMonitorSensorSupervisor -ErrorAction SilentlyContinue).Count){
  throw 'R348_EXISTING_PRODUCT_OR_GUEST_TEST_ROOT'
 }
 foreach($f in @($source,$setup,$actorFile,$native)){
  if(-not [IO.File]::Exists($f)){throw 'R348_REVIEW_SOURCE_FILE_MISSING'}
 }
 $assembly=[Reflection.Assembly]::LoadFrom((Resolve-Path $setup).Path)
 $stream=$assembly.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
 if(!$stream){throw 'R348_COMPILED_ORIGINAL_HELPER_NOT_PRESENT'}
 $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
 try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
 $norm={param($v) $v.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
 if((& $norm $embedded) -cne (& $norm ([IO.File]::ReadAllText($source)))){
  throw 'R348_COMPILED_PRODUCT_NOT_IDENTICAL_TO_HELPER_SOURCE'
 }
 $loc=$embedded.IndexOf('public sealed class TBMEProtectedBrokerLease',[StringComparison]::Ordinal)
 $start=$embedded.LastIndexOf("Add-Type -TypeDefinition @'",$loc,[StringComparison]::Ordinal)
 $first=$embedded.IndexOf([string][char]10,$start,[StringComparison]::Ordinal)
 $last=$embedded.IndexOf(([string][char]10+"'@"),$loc,[StringComparison]::Ordinal)
 if($loc -lt 0 -or $start -lt 0 -or $first -lt 0 -or $last -le $loc -or $last-$first -gt 14000){
  throw 'R348_COMPILED_LEASE_EXTRACTION_BOUNDS'
 }
 Add-Type -TypeDefinition $embedded.Substring($first+1,$last-$first-1) -ErrorAction Stop
 if($null -eq ('TBMEProtectedBrokerLease' -as [type])){throw 'R348_COMPILED_LEASE_TYPE_NOT_AVAILABLE'}
 Pass 'REAL_ORIGINAL_SETUP_PE_EMBEDDED_DIRECTORY_LEASE_CLASS'
 [void][IO.Directory]::CreateDirectory($runRoot)
 [IO.File]::WriteAllText($outside,'R348_OUTSIDE_CANARY',[Text.UTF8Encoding]::new($false))
 $canarySha=Hash $outside
 $admins=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
 $system=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
 $users=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
 $acl=[Security.AccessControl.DirectorySecurity]::new()
 $acl.SetOwner($admins);$acl.SetAccessRuleProtection($true,$false)
 foreach($sid in @($admins,$system,$users)){
  $rights=if($sid -eq $users){[Security.AccessControl.FileSystemRights]::ReadAndExecute}else{[Security.AccessControl.FileSystemRights]::FullControl}
  [void]$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
   $sid,$rights,[Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
   [Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
 }
 [void][IO.Directory]::CreateDirectory($product,$acl)
 $protectedOwned=$true
 [void][IO.Directory]::CreateDirectory($broker)
 [IO.File]::WriteAllText($leaf,$oldText,[Text.UTF8Encoding]::new($false))
 $oldSha=Hash $leaf
 Pass 'TEST_ONLY_ADMIN_OWNED_PROTECTED_ROOT_EXACT_LEAF_CREATED'
 $lease=[TBMEProtectedBrokerLease]::new($broker)
 if(-not $lease.IsPinned){throw 'R348_EXPECT_THREE_OPEN_PROGRAMFILES_DIRECTORY_HANDLES'}
 Pass 'REAL_R347_DIRECTORY_LEASE_HELD_ACROSS_OTHER_ADMIN_WRITE'
 $auth=[ordered]@{
  Schema=1;Revision='R348';SourceCommit=$env:GITHUB_SHA;Guest=$env:COMPUTERNAME
  ExpectedLeafPath=$leaf;OriginalSHA256=$oldSha;Payload=$newText
 }
 [IO.File]::WriteAllText($authority,($auth|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
 $psi=[Diagnostics.ProcessStartInfo]::new()
 $psi.FileName=$native
 $psi.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$actorFile+'" -AuthorityPath "'+$authority+'" -ReceiptPath "'+$actorReceipt+'"'
 $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
 $child=[Diagnostics.Process]::Start($psi)
 if(!$child){throw 'R348_DIFFERENT_ADMIN_CHILD_NOT_STARTED'}
 $childPid=$child.Id
 if(-not $child.WaitForExit(18000)){throw 'R348_DIFFERENT_ADMIN_CHILD_TIMEOUT'}
 if($child.ExitCode -ne 0){throw ('R348_DIFFERENT_ADMIN_CHILD_FAILED_EXIT_'+$child.ExitCode)}
 if(-not [IO.File]::Exists($actorReceipt)){throw 'R348_CHILD_PROOF_NOT_FOUND'}
 $typed=Get-Content $actorReceipt -Raw|ConvertFrom-Json
 $actorSha=Hash $actorReceipt
 $newSha=Hash $leaf
 if($typed.SourceCommit -cne $env:GITHUB_SHA -or
    $typed.Revision -cne 'R348' -or
    $typed.ActorPid -ne $childPid -or
    $typed.Status -cne 'OBSERVED_PRIVILEGED_LEAF_WRITE_WHILE_DIRECTORY_LEASE_HELD' -or
    $typed.LeafWriteSucceeded -ne $true -or
    $typed.OriginalSHA256 -cne $oldSha -or
    $typed.AfterSHA256 -cne $newSha -or
    [IO.File]::ReadAllText($leaf) -cne $newText -or
    -not $lease.IsPinned -or
    $newSha -ceq $oldSha){
  throw 'R348_REAL_PRIVILEGED_LEAF_WRITE_GAP_NOT_WITNESSED'
 }
 $observedGap=$true
 Pass 'DIFFERENT_ADMIN_PID_CHANGED_LEAF_WHILE_DIRECTORY_HANDLE_STILL_PINNED'
 if(-not [IO.Directory]::Exists($broker) -or
    -not [IO.Directory]::Exists($product) -or
    ([IO.File]::GetAttributes($broker) -band [IO.FileAttributes]::ReparsePoint) -ne 0){
  throw 'R348_DIRECTORY_IDENTITY_NO_LONGER_STABLE'
 }
 Pass 'DIRECTORY_ANCESTRY_STABLE_WHILE_LEAF_BYTES_CHANGED'
 if((Hash $outside) -cne $canarySha){throw 'R348_OUTSIDE_CANARY_MODIFIED'}
 Pass 'OUTSIDE_CANARY_UNCHANGED_BY_LEAF_WRITE'
}catch{$failure=$_.Exception.ToString()}
finally{
 if($child){
  try{if(-not $child.HasExited){$child.Kill();[void]$child.WaitForExit(5000)}}catch{}
  $child.Dispose()
 }
 if($lease){$lease.Dispose()}
 if($protectedOwned -and [IO.Directory]::Exists($product)){
  try{
   if(([IO.File]::GetAttributes($product) -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
      -not [IO.Directory]::Exists($broker) -or
      ([IO.File]::GetAttributes($broker) -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
      @([IO.Directory]::GetFileSystemEntries($product)).Count -ne 1 -or
      @([IO.Directory]::GetFileSystemEntries($broker)).Count -ne 1 -or
      -not [IO.File]::Exists($leaf)){
    throw 'R348_UNEXPECTED_PROTECTED_ROOT_MEMBER'
   }
   $actual=[IO.File]::ReadAllText($leaf)
   if($actual -cne $newText -and $actual -cne $oldText){
    throw 'R348_PROTECTED_TEST_LEAF_UNKNOWN_BYTES_PRESERVED'
   }
   [IO.File]::Delete($leaf)
   [IO.Directory]::Delete($broker,$false)
   [IO.Directory]::Delete($product,$false)
   $clean=(-not [IO.Directory]::Exists($product))
  }catch{$failure+=' TEST_ONLY_CLEANUP_REFUSED_'+$_.Exception.Message}
 }
 $status=if(-not $failure -and $checks.Count -eq 6 -and $observedGap -and $clean){
  'NEGATIVE_CONFIRMED_DIRECTORY_LEASE_DOES_NOT_PROTECT_PRIVILEGED_LEAF_OVERWRITE'
 }else{'FAIL_R348_DIAGNOSTIC_INCONCLUSIVE'}
 if([IO.Directory]::Exists($runRoot)){
  [IO.File]::WriteAllText($receipt,([ordered]@{
   Schema=1;Revision='R348';Status=$status;SourceCommit=$env:GITHUB_SHA;Host=$HostLabel
   RealExactPEEmbeddedLeaseLoaded=$true;AdminActorPid=$childPid;ActorReceiptSHA256=$actorSha
   DirectoryHandlesStayedPinned=$observedGap;PrivilegedLeafWriteWasAllowed=$observedGap
   LeafSHA256Before=$oldSha;LeafSHA256After=$newSha
   OutsideCanarySHA256=$canarySha;TemporaryProtectedFixtureRemoved=$clean
   UserInstallationOrGlassTouched=$false;RealUACPromptTested=$false
   SecurityGatePassed=$false;OriginalHelperExecuted=$false
   Checks=@($checks);Failure=$failure
  }|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  Write-Output ('R348_RAW_NEGATIVE_PROOF='+$receipt)
 }
 Write-Output ('R348_DIAGNOSTIC_STATUS='+$status+' CHECKS='+$checks.Count)
}
if($failure){throw ('R348_NEGATIVE_LEAF_GAP_TEST_FAILED_'+$failure)}
