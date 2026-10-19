[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AuthorityPath,
      [Parameter(Mandatory=$true)][string]$ReceiptPath)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
 $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
 $env:RUNNER_OS -cne 'Windows' -or $env:GITHUB_REPOSITORY -cne 'GOD13emad/TaskbarMonitorEnhanced' -or
 $env:GITHUB_REF -cne 'refs/heads/audit/r349-pinned-leaf-replay-handles' -or
 $env:COMPUTERNAME -match '(?i)EMAD-PC|ALIEMAD|SAEID|LAPTOP'){
 throw 'R349_REFUSE_NONDISPOSABLE_WINDOWS'
}
$who=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(!$who.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'R349_CHILD_ALREADY_ADMIN_REQUIRED'}
$temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')+'\'
$auth=[IO.Path]::GetFullPath($AuthorityPath)
$receipt=[IO.Path]::GetFullPath($ReceiptPath)
if(-not $auth.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
   -not $receipt.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
   [IO.File]::Exists($receipt)){
 throw 'R349_ACTOR_AUTHORITY_OUTSIDE_TEMP_OR_RECEIPT_EXISTS'
}
$a=Get-Content -LiteralPath $auth -Raw|ConvertFrom-Json
$leaf=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)) 'TaskbarMonitorEnhanced\SensorBroker\R349_KNOWN_LEAF.txt'
if($a.Schema -ne 1 -or $a.Revision -cne 'R349' -or $a.SourceCommit -cne $env:GITHUB_SHA -or
 $a.Guest -cne $env:COMPUTERNAME -or $a.ExpectedLeafPath -cne $leaf -or
 $a.Payload -cnotmatch '^R349_PRIVILEGED_WRITE_[0-9]+_[AB]$' -or
 $a.OriginalSha256 -cnotmatch '^[0-9A-F]{64}$'){
 throw 'R349_ACTOR_AUTHORITY_NOT_EXACT'
}
# The parent owns a READ/WRITE file handle with only FILE_SHARE_READ;
# a separate path-based Get-FileHash may itself be refused because its
# FileShare mode does not permit the parent's WRITE access. The original SHA
# was already established before pinning and passed in typed guest authority.
if(-not [IO.File]::Exists($leaf)){
 throw 'R349_EXPECTED_EXACT_TEST_LEAF_ABSENT'
}
$writeDenied=$false;$why='';$unexpected=''
try{
 [IO.File]::WriteAllText($leaf,[string]$a.Payload,[Text.UTF8Encoding]::new($false))
 $unexpected='R349_PRIVILEGED_LEAF_OVERWRITE_SUCCEEDED_WHILE_PINNED'
}catch{
 $e=$_.Exception
 while($e.InnerException -and
   ($e -is [Management.Automation.MethodInvocationException] -or
    $e -is [Reflection.TargetInvocationException])){$e=$e.InnerException}
 $why=$e.GetType().Name+' HRESULT='+$e.HResult
 $sharing=$e.HResult -in @(-2147024864,-2147024891)
 if(($e -is [IO.IOException] -or $e -is [UnauthorizedAccessException]) -and $sharing){
  $writeDenied=$true
 }else{$unexpected='R349_WRONG_FAILURE_CAUSE_'+$why}
}
$status=if($writeDenied -and !$unexpected){
 'PASS_PRIVILEGED_WRITE_OPEN_REFUSED_BY_PINNED_LEAF'
}else{'FAIL_R349_LEAF_WRITE_NOT_EXCLUSIVELY_PINNED'}
$out=[ordered]@{
 Schema=1;Revision='R349';Status=$status;SourceCommit=$env:GITHUB_SHA
 ActorPid=$PID;Guest=$env:COMPUTERNAME;AlreadyAdmin=$true
 WriteDeniedByRealWindowsSharing=$writeDenied;NativeError=$why
 OriginalSHA256=$a.OriginalSha256
 # Cannot reopen the leaf for reading while it is pinned. Parent checks
 # SHA from its already-open handle, then releases the lease.
 OwnerComputerTouched=$false;Failure=$unexpected
}
[IO.File]::WriteAllText($receipt,($out|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
'R349_CHILD_RESULT='+$status
if($unexpected){throw $unexpected}
