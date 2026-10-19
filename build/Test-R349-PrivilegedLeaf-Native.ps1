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
 $env:GITHUB_REF -cne 'refs/heads/audit/r349-pinned-leaf-replay-handles' -or
 $env:COMPUTERNAME -match '(?i)EMAD-PC|ALIEMAD|SAEID|LAPTOP' -or
 $env:GITHUB_RUN_ID -cnotmatch '^[0-9]{5,20}$' -or
 $env:GITHUB_SHA -cnotmatch '^[0-9a-f]{40}$' -or
 (git -C $SourceRoot rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){
 throw 'R349_REFUSE_NONDISPOSABLE_OR_WRONG_GIT_SOURCE'
}
$admin=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(!$admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 throw 'R349_GUEST_ALREADY_ADMIN_REQUIRED_NO_ELEVATION'
}
$pf=[Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
$protected=Join-Path $pf 'TaskbarMonitorEnhanced'
$broker=Join-Path $protected 'SensorBroker'
$leafName='R349_KNOWN_LEAF.txt'
$leaf=Join-Path $broker $leafName
$root=Join-Path $env:RUNNER_TEMP ('R349_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $root 'R349_PINNED_LEAF_NATIVE.json'
$actorReceipt=Join-Path $root 'R349_ACTOR_RECEIPT.json'
$authority=Join-Path $root 'R349_AUTHORITY.json'
$canary=Join-Path $root 'OUTSIDE_CANARY.txt'
$source=Join-Path $SourceRoot 'installer\TBME_Setup_Elevated_Helper.ps1'
$setup=Join-Path $SourceRoot 'build\_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$actorFile=Join-Path $SourceRoot 'build\Test-R349-PrivilegedLeaf-Actor.ps1'
$native=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
$oldText='R349_ORIGINAL_BYTES_'+$env:GITHUB_RUN_ID+'_'+$HostLabel
$newText='R349_PRIVILEGED_WRITE_'+$env:GITHUB_RUN_ID+'_'+$HostLabel
$lease=$null;$child=$null;$priorDelete=$null;$secondLease=$null
$created=$false;$cleanupOk=$false;$failure='';$actorPid=0
$checks=[Collections.Generic.List[string]]::new()
$beforeHash='';$afterHash='';$actorHash='';$canaryHash=''
$denied=$false;$preopenDeleteRefused=$false;$postReleaseWriteAllowed=$false
function Hash([string]$file){(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}
function Check([string]$name){$script:checks.Add($name);Write-Output ('PASS '+$name)}
function Cause([Exception]$error){
 while($error.InnerException -and
   ($error -is [Management.Automation.MethodInvocationException] -or
    $error -is [Reflection.TargetInvocationException])){$error=$error.InnerException}
 return $error
}
function Sharing([Exception]$error){
 $e=Cause $error
 # The unchanged production native guard deliberately throws a fresh
 # IOException carrying GetLastError=32 in its exact message; its HResult
 # is the generic managed IOException code, not the source Win32 HResult.
 # Restrict acceptance to this precise native sharing violation only.
 return ($e -is [IO.IOException] -or $e -is [UnauthorizedAccessException]) -and
   (($e.HResult -in @(-2147024864,-2147024891)) -or
    $e.Message -ceq 'SENSOR_REPLAY_LEAF_EXCLUSIVE_OPEN_FAILED_WIN32_32')
}
try{
 if([IO.Directory]::Exists($protected) -or [IO.Directory]::Exists($root) -or
    @(Get-Process TaskbarMonitorEnhanced,TaskbarMonitorSensorBroker,TaskbarMonitorSensorSupervisor -ErrorAction SilentlyContinue).Count){
  throw 'R349_PREEXISTING_PROGRAMFILES_PRODUCT_OR_FIXTURE_COLLISION'
 }
 foreach($f in @($source,$setup,$actorFile,$native)){if(![IO.File]::Exists($f)){throw 'R349_SOURCE_PREREQUISITE_MISSING'}}
 $asm=[Reflection.Assembly]::LoadFrom((Resolve-Path $setup).Path)
 $stream=$asm.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
 if(!$stream){throw 'R349_REAL_SETUP_PE_EMBEDDED_HELPER_MISSING'}
 $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
 try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
 $normalize={param($x) $x.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
 if((& $normalize $embedded) -cne (& $normalize ([IO.File]::ReadAllText($source)))){
  throw 'R349_REAL_PE_EMBEDDED_HELPER_AND_SOURCE_DIFFER'
 }
 $at=$embedded.IndexOf('public sealed class TBMEProtectedBrokerLease',[StringComparison]::Ordinal)
 $header=$embedded.LastIndexOf("Add-Type -TypeDefinition @'",$at,[StringComparison]::Ordinal)
 $first=$embedded.IndexOf([string][char]10,$header,[StringComparison]::Ordinal)
 $last=$embedded.IndexOf(([string][char]10+"'@"),$at,[StringComparison]::Ordinal)
 if($at -lt 0 -or $header -lt 0 -or $first -lt 0 -or $last -le $at -or
    $last-$first -gt 22000){throw 'R349_BOUND_REAL_CSHARP_EXTRACTION_REFUSED'}
 Add-Type -TypeDefinition $embedded.Substring($first+1,$last-$first-1) -ErrorAction Stop
 if($null -eq ('TBMEProtectedBrokerLease' -as [type])){throw 'R349_REAL_PRODUCT_LEAF_LEASE_NOT_COMPILED'}
 Check 'EXACT_ORIGINAL_SETUP_EMBEDS_NEW_NATIVE_LEAF_LOCK_CLASS'
 [void][IO.Directory]::CreateDirectory($root)
 [IO.File]::WriteAllText($canary,'R349_OUTSIDE_CANARY',[Text.UTF8Encoding]::new($false))
 $canaryHash=Hash $canary
 $admins=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
 $system=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
 $users=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
 $acl=[Security.AccessControl.DirectorySecurity]::new()
 $acl.SetOwner($admins);$acl.SetAccessRuleProtection($true,$false)
 foreach($sid in @($admins,$system,$users)){
  $rights=if($sid -eq $users){[Security.AccessControl.FileSystemRights]::ReadAndExecute}else{[Security.AccessControl.FileSystemRights]::FullControl}
  [void]$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,$rights,
   [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
   [Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow))
 }
 [void][IO.Directory]::CreateDirectory($protected,$acl);$created=$true
 [void][IO.Directory]::CreateDirectory($broker)
 [IO.File]::WriteAllText($leaf,$oldText,[Text.UTF8Encoding]::new($false))
 $beforeHash=Hash $leaf
 if((Get-Acl $protected).Owner -notmatch '(?i)Administrators'){throw 'R349_PROTECTED_OWNER_NOT_ADMIN'}
 Check 'FRESH_ADMIN_OWNED_PROGRAMFILES_AND_KNOWN_LEAF_SHA_CREATED'
 $proof=[ordered]@{
  Schema=1;Revision='R349';SourceCommit=$env:GITHUB_SHA;Guest=$env:COMPUTERNAME
  ExpectedLeafPath=$leaf;OriginalSHA256=$beforeHash;Payload=$newText
 }
 [IO.File]::WriteAllText($authority,($proof|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
 $lease=[TBMEProtectedBrokerLease]::new($broker)
 $streamLeaf=$lease.OpenReplayLeaf($leafName)
 if(-not $lease.IsPinned -or $null -eq $streamLeaf){throw 'R349_LEAF_NOT_PINNED'}
 $bytes=[byte[]]$lease.ReadReplayLeaf($leafName)
 $actual=[Text.Encoding]::UTF8.GetString($bytes)
 if($actual -cne $oldText){throw 'R349_ORIGINAL_BYTES_CHANGED_BEFORE_CHILD'}
 Check 'EXACT_PROTECTED_LEAF_HANDLE_PINNED_AND_OLD_BYTES_STABLE'
 $psi=[Diagnostics.ProcessStartInfo]::new()
 $psi.FileName=$native
 $psi.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$actorFile+'" -AuthorityPath "'+$authority+'" -ReceiptPath "'+$actorReceipt+'"'
 $psi.CreateNoWindow=$true;$psi.UseShellExecute=$false
 $child=[Diagnostics.Process]::Start($psi)
 if(!$child){throw 'R349_ACTOR_PROCESS_NOT_CREATED'}
 $actorPid=$child.Id
 if(-not $child.WaitForExit(23000)){throw 'R349_ACTOR_PROCESS_TIMEOUT'}
 if($child.ExitCode -ne 0){throw ('R349_ACTOR_PROCESS_NONZERO_'+$child.ExitCode)}
 if(-not [IO.File]::Exists($actorReceipt)){throw 'R349_CHILD_TYPED_RECEIPT_NOT_WRITTEN'}
 $a=Get-Content -LiteralPath $actorReceipt -Raw|ConvertFrom-Json
 $actorHash=Hash $actorReceipt
 if($a.Status -cne 'PASS_PRIVILEGED_WRITE_OPEN_REFUSED_BY_PINNED_LEAF' -or
    $a.ActorPid -ne $actorPid -or $a.SourceCommit -cne $env:GITHUB_SHA -or
    $a.WriteDeniedByRealWindowsSharing -ne $true -or
    $a.AlreadyAdmin -ne $true -or
    ![string]::IsNullOrWhiteSpace([string]$a.Failure)){
  throw 'R349_SECOND_PRIVILEGED_PROCESS_DID_NOT_PROVE_SHARING_DENIAL'
 }
 $denied=$true
 Check 'DISTINCT_ALREADY_ADMIN_PID_WRITE_OPEN_REJECTED_BY_REAL_NTFS_SHARING'
 $bytes=[byte[]]$lease.ReadReplayLeaf($leafName)
 if([Text.Encoding]::UTF8.GetString($bytes) -cne $oldText -or
    !$lease.IsPinned -or [IO.Directory]::Exists($broker+'_renamed')){
   throw 'R349_PINNED_LEAF_OR_PARENT_CHANGED_DURING_OTHER_ADMIN_WRITE'
 }
 Check 'REAL_PRODUCTION_LEAF_HANDLE_READBACK_UNCHANGED_DURING_ATTACK'
 $lease.Dispose();$lease=$null
 # A preopened DELETE-capable handle with broad sharing must block a
 # later exclusive leaf lease, even if the directory is pinned. This is
 # a fail-closed precondition, not a successful recovery transaction.
 Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class R349PreopenedDelete {
 [DllImport("kernel32.dll",EntryPoint="CreateFileW",SetLastError=true,CharSet=CharSet.Unicode)]
 static extern SafeFileHandle Open(string p,uint a,uint s,IntPtr x,uint c,uint f,IntPtr t);
 public static SafeFileHandle Hold(string p) {
  SafeFileHandle h=Open(p,0x00010000,7,IntPtr.Zero,3,0x00200000,IntPtr.Zero);
  if(h.IsInvalid){int error=Marshal.GetLastWin32Error();h.Dispose();throw new IOException("R349_PREOPEN_DELETE_FAILED_WIN32_"+error);}
  return h;
 }
}
'@
 $priorDelete=[R349PreopenedDelete]::Hold($leaf)
 $secondLease=[TBMEProtectedBrokerLease]::new($broker)
 try{
  $null=$secondLease.OpenReplayLeaf($leafName)
  throw 'R349_LEAF_LEASE_UNSAFELY_OPENED_WITH_PREEXISTING_DELETE_HANDLE'
 }catch{
  if($_.Exception.Message -like 'R349_LEAF_LEASE_UNSAFELY*'){throw}
  if(-not (Sharing $_.Exception)){
   throw ('R349_EXPECTED_SHARING_FAIL_FOR_PREOPENED_DELETE_'+(Cause $_.Exception).Message)
  }
  $preopenDeleteRefused=$true
 }
 $secondLease.Dispose();$secondLease=$null
 $priorDelete.Dispose();$priorDelete=$null
 Check 'REAL_PREOPENED_DELETE_ACCESS_HANDLE_BLOCKED_NEW_EXCLUSIVE_LEAF_LOCK'
 [IO.File]::WriteAllText($leaf,$newText,[Text.UTF8Encoding]::new($false))
 $afterHash=Hash $leaf
 if($afterHash -ceq $beforeHash -or [IO.File]::ReadAllText($leaf) -cne $newText){
  throw 'R349_OWNER_WRITE_AFTER_LEASE_RELEASE_NOT_POSSIBLE'
 }
 $postReleaseWriteAllowed=$true
 Check 'WRITING_KNOWN_TEST_LEAF_ALLOWED_AFTER_EXCLUSIVE_HANDLE_RELEASE'
 if((Hash $canary) -cne $canaryHash){throw 'R349_OUTSIDE_CANARY_CHANGED'}
 Check 'OUTSIDE_CANARY_UNTOUCHED'
}catch{$failure=$_.Exception.ToString()}
finally{
 if($child){try{if(-not $child.HasExited){$child.Kill();[void]$child.WaitForExit(6000)}}catch{};$child.Dispose()}
 if($lease){$lease.Dispose()}
 if($secondLease){$secondLease.Dispose()}
 if($priorDelete){$priorDelete.Dispose()}
 if($created -and [IO.Directory]::Exists($protected)){
  try{
   if(([IO.File]::GetAttributes($protected) -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
      -not [IO.Directory]::Exists($broker) -or
      ([IO.File]::GetAttributes($broker) -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
      @([IO.Directory]::GetFileSystemEntries($protected)).Count -ne 1 -or
      @([IO.Directory]::GetFileSystemEntries($broker)).Count -ne 1 -or
      -not [IO.File]::Exists($leaf)){
    throw 'R349_UNEXPECTED_PROTECTED_ROOT_OR_MEMBER_KEEP_FOR_GUEST'
   }
   $current=[IO.File]::ReadAllText($leaf)
   if($current -cne $oldText -and $current -cne $newText){
    throw 'R349_UNEXPECTED_LEAF_BYTES_KEEP_FOR_GUEST'
   }
   [IO.File]::Delete($leaf)
   [IO.Directory]::Delete($broker,$false)
   [IO.Directory]::Delete($protected,$false)
   $cleanupOk=(![IO.Directory]::Exists($protected))
  }catch{$failure+=' R349_PROTECTED_CLEANUP_REFUSED_'+$_.Exception.Message}
 }
 $status=if(!$failure -and $checks.Count -eq 8 -and $denied -and
    $preopenDeleteRefused -and $postReleaseWriteAllowed -and $cleanupOk){
  'PASS_R349_PRIVILEGED_LEAF_WRITE_AND_PREOPEN_DELETE_DENIED_BY_NATIVE_HANDLES'
 }else{'FAIL_R349_NATIVE_LEAF_SHARING_ACCEPTANCE'}
 if([IO.Directory]::Exists($root)){
  [IO.File]::WriteAllText($receipt,([ordered]@{
   Schema=1;Revision='R349';Status=$status;Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
   RealUnmodifiedSetupEmbeddedCSharp=$true;AlreadyAdminRunner=$true;DistinctOtherAdminPid=$actorPid
   OriginalLeafSHA256=$beforeHash;AfterReleaseSHA256=$afterHash
   OtherAdminWriteRefused=$denied;PreopenedDeleteHandleRefused=$preopenDeleteRefused
   WriteAfterReleaseAllowed=$postReleaseWriteAllowed;ActualNativeLeaseHeld=$true
   ChildReceiptSHA256=$actorHash;OutsideCanarySHA256=$canaryHash
   CleanupOwnedProgramFilesFixture=$cleanupOk
   RealInteractiveUacConsentTested=$false;OriginalFullHelperExecuted=$false
   ActualFullJournalReplayWithConcurrentLeafWriterTested=$false
   SecurityEntireProductAccepted=$false;OwnerInstallationChanged=$false
   Checks=@($checks);Failure=$failure
  }|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
  Write-Output ('R349_PINNED_LEAF_RECEIPT='+$receipt)
 }
 Write-Output ('R349_NATIVE_STATUS='+$status+' CHECKS='+$checks.Count)
}
if($failure){throw ('R349_REPLAY_LEAF_GUARD_NOT_ACCEPTED '+$failure)}
