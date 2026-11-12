[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
      [Parameter(Mandatory=$true)][string]$SourceRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
 $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
 $env:RUNNER_OS -cne 'Windows' -or $env:GITHUB_REPOSITORY -cne 'GOD13emad/TaskbarMonitorEnhanced' -or
 $env:GITHUB_REF -cne 'refs/heads/audit/r347-protected-broker-handle-lease' -or
 $env:COMPUTERNAME -match '(?i)EMAD-PC|ALIEMAD|SAEID|LAPTOP' -or
 $env:GITHUB_RUN_ID -cnotmatch '^[0-9]{5,20}$' -or
 (git -C $SourceRoot rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){
 throw 'R347_DISPOSABLE_HOST_EXACT_SOURCE_REQUIRED'
}
$actor=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $actor.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 throw 'R347_ALREADY_ADMIN_WINDOWS_TOKEN_REQUIRED'
}
$pf=[Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
$root=Join-Path $pf 'TaskbarMonitorEnhanced'
$broker=Join-Path $root 'SensorBroker'
$private=Join-Path $env:RUNNER_TEMP ('R347_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $private 'R347_PINNED_DIRECTORY_LEASE.json'
$otherReceipt=Join-Path $private 'OTHER_ADMIN_RENAME_RECEIPT.json'
$outsideCanary=Join-Path $private 'OUTSIDE_CANARY.txt'
$sentinel=Join-Path $broker 'R347_KNOWN.txt'
$backup=Join-Path $root 'SensorBroker_R347_backup'
$setup=Join-Path $SourceRoot 'build\_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$src=Join-Path $SourceRoot 'installer\TBME_Setup_Elevated_Helper.ps1'
$other=Join-Path $SourceRoot 'build\Test-R347-OtherAdminRename-Actor.ps1'
$ps=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
$checks=[Collections.Generic.List[string]]::new()
$lease=$null;$child=$null;$created=$false;$linked=$false
$failure='';$denials=0;$concurrent=0;$actorPid=0;$released=$false;$rejectLink=$false;$clean=$false
$canarySha='';$actorSha=''
function Hash([string]$f){return (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash}
function Pass([string]$s){$script:checks.Add($s);Write-Output ('PASS '+$s)}
try{
 if([IO.Directory]::Exists($root) -or [IO.Directory]::Exists($private) -or
    @(Get-Process TaskbarMonitorEnhanced,TaskbarMonitorSensorBroker,TaskbarMonitorSensorSupervisor -ErrorAction SilentlyContinue).Count){
  throw 'R347_PREEXISTING_PRODUCT_OR_FIXTURE_REFUSE'
 }
 foreach($f in @($src,$setup,$other,$ps)){if(-not [IO.File]::Exists($f)){throw 'R347_SOURCE_FILE_NOT_FOUND'}}
 $asm=[Reflection.Assembly]::LoadFrom((Resolve-Path $setup).Path)
 $resource=$asm.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
 if(!$resource){throw 'R347_EMBEDDED_PRODUCTION_HELPER_ABSENT'}
 $reader=[IO.StreamReader]::new($resource,[Text.Encoding]::UTF8)
 try{$body=$reader.ReadToEnd()}finally{$reader.Dispose()}
 $normalize={param($v) $v.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
 if((& $normalize $body) -cne (& $normalize ([IO.File]::ReadAllText($src)))){
  throw 'R347_ORIGINAL_SETUP_EMBEDDED_HELPER_NOT_SOURCE_EXACT'
 }
 $at=$body.IndexOf('public sealed class TBMEProtectedBrokerLease',[StringComparison]::Ordinal)
 if($at -lt 0){throw 'R347_NATIVE_CLASS_NOT_EMBEDDED'}
 $st=$body.LastIndexOf("Add-Type -TypeDefinition @'",$at,[StringComparison]::Ordinal)
 $from=$body.IndexOf([string][char]10,$st,[StringComparison]::Ordinal)
 $end=$body.IndexOf(([string][char]10+"'@"),$at,[StringComparison]::Ordinal)
 if($st -lt 0 -or $from -lt 0 -or $end -le $at -or $end-$from -gt 13000){
  throw 'R347_EMBEDDED_CSHARP_BOUNDS_BAD'
 }
 Add-Type -TypeDefinition $body.Substring($from+1,$end-$from-1) -ErrorAction Stop
 Pass 'EXACT_REAL_PE_EMBEDDED_PROTECTED_LEASE_COMPILED'
 [void][IO.Directory]::CreateDirectory($private)
 [IO.File]::WriteAllText($outsideCanary,'R347_OUTSIDE_CANARY_UNTOUCHED',[Text.UTF8Encoding]::new($false))
 $canarySha=Hash $outsideCanary
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
 [void][IO.Directory]::CreateDirectory($root,$acl);$created=$true
 [void][IO.Directory]::CreateDirectory($broker)
 [IO.File]::WriteAllText($sentinel,'R347_KNOWN_MEMBER',[Text.UTF8Encoding]::new($false))
 if((Get-Acl $root).Owner -notmatch '(?i)Administrators'){throw 'R347_PROTECTED_OWNER_NOT_ADMIN'}
 Pass 'EXACT_ADMIN_OWNED_PROGRAMFILES_TEST_ROOT_CREATED'
 $lease=[TBMEProtectedBrokerLease]::new($broker)
 if(-not $lease.IsPinned){throw 'R347_THREE_DIRECTORY_HANDLES_NOT_OPEN'}
 Pass 'REAL_PROGRAMFILES_PRODUCT_AND_BROKER_DIR_HANDLE_LEASE_ACTIVE'
 $psi=[Diagnostics.ProcessStartInfo]::new()
 $psi.FileName=$ps
 $psi.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$other+'" -BrokerPath "'+$broker+'" -ReceiptPath "'+$otherReceipt+'"'
 $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
 $child=[Diagnostics.Process]::Start($psi)
 if(!$child){throw 'R347_DIFFERENT_ADMIN_PROCESS_START_FAILED'}
 $actorPid=$child.Id
 $watch=[Diagnostics.Stopwatch]::StartNew()
 while(-not $child.HasExited -and $watch.ElapsedMilliseconds -lt 25000){
  if(-not $lease.IsPinned -or -not [IO.File]::Exists($sentinel)){
   throw 'R347_PROTECTED_ROOT_CHANGED_WHILE_HANDLE_PINNED'
  }
  $concurrent++;Start-Sleep -Milliseconds 4
 }
 if(-not $child.WaitForExit(8000) -or $child.ExitCode -ne 0){throw 'R347_OTHER_ADMIN_PROCESS_NOT_SUCCESSFUL'}
 $a=Get-Content -LiteralPath $otherReceipt -Raw|ConvertFrom-Json
 if($a.Status -cne 'PASS_ADMIN_RENAME_DENIED_DURING_PINNED_ANCESTOR_HANDLES' -or
    $a.ActorPid -ne $actorPid -or $a.ActorAlreadyAdmin -ne $true -or
    $a.BrokerRenameDenied -ne 80 -or $a.ProductRenameDenied -ne 80 -or
    $a.SourceCommit -cne $env:GITHUB_SHA -or $concurrent -lt 5){
  throw 'R347_OTHER_ADMIN_TYPED_PROOF_INVALID'
 }
 $actorSha=Hash $otherReceipt;$denials=160
 Pass 'OTHER_ADMIN_PID_RENAME_160_OF_160_REFUSED_DURING_LEASE'
 Pass 'ORIGINAL_PINNED_BROKER_PATH_STABLE_WHILE_ATTACKER_ACTIVE'
 $lease.Dispose();$lease=$null
 [IO.Directory]::Move($broker,$backup)
 if(-not [IO.Directory]::Exists($backup) -or [IO.Directory]::Exists($broker)){throw 'R347_POST_LEASE_MOVE_NOT_SUCCESSFUL'}
 [IO.Directory]::Move($backup,$broker);$released=$true
 Pass 'SAME_ADMIN_RENAME_SUCCEEDS_AFTER_LEASE_RELEASE'
 [IO.Directory]::Move($broker,$backup)
 New-Item -ItemType Junction -Path $broker -Target $private -ErrorAction Stop|Out-Null
 $linked=$true
 $message=''
 try{$attempt=[TBMEProtectedBrokerLease]::new($broker);try{throw 'R347_UNSAFE_LINK_ACCEPTED'}finally{$attempt.Dispose()}}
 catch{
  $cause=$_.Exception
  while($cause.InnerException -and
     ($cause -is [Management.Automation.MethodInvocationException] -or
      $cause -is [Reflection.TargetInvocationException])){
    $cause=$cause.InnerException
  }
  $message=$cause.Message
 }
 if($message -cne 'SENSOR_BROKER_DIRECTORY_LEASE_REPARSE_REFUSED'){throw ('R347_JUNCTION_REJECTION_WRONG_'+$message)}
 $rejectLink=$true
 if((Hash $outsideCanary) -cne $canarySha){throw 'R347_OUTSIDE_CANARY_CHANGED'}
 Pass 'REAL_NTFS_JUNCTION_REJECTED_BY_HANDLE_REPARSE_TAG'
 if(([IO.File]::GetAttributes($broker) -band [IO.FileAttributes]::ReparsePoint) -eq 0){throw 'R347_JUNCTION_CHANGED_BEFORE_SAFE_DELETION'}
 [IO.Directory]::Delete($broker,$false);$linked=$false
 [IO.Directory]::Move($backup,$broker)
 if((Hash $outsideCanary) -cne $canarySha){throw 'R347_OUTSIDE_SHA_CHANGED'}
 Pass 'OUTSIDE_CANARY_SHA256_UNCHANGED'
}catch{$failure=$_.Exception.ToString()}
finally{
 if($child){try{if(-not $child.HasExited){$child.Kill();[void]$child.WaitForExit(3000)}}catch{};$child.Dispose()}
 if($lease){$lease.Dispose()}
 if($linked -and [IO.Directory]::Exists($broker)){
  try{if(([IO.File]::GetAttributes($broker) -band [IO.FileAttributes]::ReparsePoint) -ne 0){[IO.Directory]::Delete($broker,$false)}}catch{$failure+=' LINK_CLEANUP_FAILED'}
 }
 if([IO.Directory]::Exists($backup) -and -not [IO.Directory]::Exists($broker)){try{[IO.Directory]::Move($backup,$broker)}catch{$failure+=' RESTORE_BACKUP_FAILED'}}
 if($created -and [IO.Directory]::Exists($root)){
  try{
   if(([IO.File]::GetAttributes($root) -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
      -not [IO.Directory]::Exists($broker) -or
      ([IO.File]::GetAttributes($broker) -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
      @([IO.Directory]::GetFileSystemEntries($root)).Count -ne 1 -or
      @([IO.Directory]::GetFileSystemEntries($broker)).Count -ne 1 -or
      [IO.File]::ReadAllText($sentinel) -cne 'R347_KNOWN_MEMBER'){
    throw 'R347_UNKNOWN_FIXTURE_MEMBER_NO_CLEANUP'
   }
   [IO.File]::Delete($sentinel);[IO.Directory]::Delete($broker,$false);[IO.Directory]::Delete($root,$false)
   $clean=(![IO.Directory]::Exists($root))
  }catch{$failure+=' PROTECTED_FIXTURE_CLEANUP_FAILED '+$_.Exception.Message}
 }
 $status=if(-not $failure -and $checks.Count -eq 8 -and $denials -eq 160 -and
  $concurrent -ge 5 -and $released -and $rejectLink -and $clean){
   'PASS_CONCURRENT_ALREADY_ADMIN_DIRECTORY_RENAME_DENIED'
 }else{'FAIL_R347_DIRECTORY_LEASE'}
 if([IO.Directory]::Exists($private)){
  $obj=[ordered]@{
   Schema=1;Revision='R347';Status=$status;Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
   ExactOriginalSetupPEHelper=$true;RealOtherAdminPid=$actorPid
   DeniedAdminRenames=$denials;ConcurrentPinnedChecks=$concurrent
   RenameAfterDisposePass=$released;ReparseJunctionRefused=$rejectLink
   OutsideCanarySHA256=$canarySha;OtherAdminRawReceiptSHA256=$actorSha
   CreatedAdminProtectedRootRemoved=$clean;LeafFileConcurrentRaceProven=$false
   InteractiveUACNotTested=$true;ActualOriginalHelperWasNotLaunched=$true
   OwnerComputerTouched=$false;Checks=@($checks);Failure=$failure
  }
  [IO.File]::WriteAllText($receipt,($obj|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
  Write-Output ('R347_TYPED_RECEIPT='+$receipt)
 }
 Write-Output ('R347_STATUS='+$status+' CHECKS='+$checks.Count+' DENIED='+$denials)
}
if($failure){throw ('R347_NATIVE_PRIVILEGED_RENAME_GUARD_FAILED '+$failure)}
