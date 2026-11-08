[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$AuthorityPath,
 [Parameter(Mandatory=$true)][string]$ReceiptPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'GOD13emad/TaskbarMonitorEnhanced' -or
   $env:GITHUB_REF -cne 'refs/heads/audit/r348-privileged-leaf-race-negative' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC|ALIEMAD|SAEID|LAPTOP'){
 throw 'R348_CHILD_ONLY_DISPOSABLE_HOSTED_WINDOWS'
}
$admin=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(!$admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 throw 'R348_CHILD_ALREADY_ADMIN_REQUIRED_NO_ELEVATION_ATTEMPT'
}
$temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')+'\'
$authority=[IO.Path]::GetFullPath($AuthorityPath)
$receipt=[IO.Path]::GetFullPath($ReceiptPath)
if(-not $authority.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
   -not $receipt.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)){
 throw 'R348_CHILD_OUTPUT_NOT_EXACT_DISPOSABLE_TEMP'
}
$pf=[Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
$leaf=Join-Path $pf 'TaskbarMonitorEnhanced\SensorBroker\R348_KNOWN_LEAF.txt'
$a=Get-Content -LiteralPath $authority -Raw|ConvertFrom-Json
if($a.Schema -ne 1 -or $a.Revision -cne 'R348' -or
   $a.SourceCommit -cne $env:GITHUB_SHA -or
   $a.Guest -cne $env:COMPUTERNAME -or
   $a.ExpectedLeafPath -cne $leaf -or
   $a.OriginalSha256 -cnotmatch '^[0-9A-F]{64}$' -or
   [string]::IsNullOrWhiteSpace([string]$a.Payload) -or
   $a.Payload.Length -gt 128 -or
   $a.Payload -cnotmatch '^R348_ACTOR_WRITE_[0-9]+_[AB]$'){
 throw 'R348_CHILD_AUTHORITY_NOT_BOUND_TO_GUEST_SOURCE_LEAF'
}
if(-not [IO.File]::Exists($leaf) -or
   (Get-FileHash -LiteralPath $leaf -Algorithm SHA256).Hash -cne $a.OriginalSha256){
 throw 'R348_CHILD_EXACT_OWNER_LEAF_OR_OLD_HASH_WRONG'
}
if([IO.File]::Exists($receipt)){throw 'R348_CHILD_RECEIPT_ALREADY_EXISTS'}
$failure='';$writeSucceeded=$false
try{
 [IO.File]::WriteAllText($leaf,[string]$a.Payload,[Text.UTF8Encoding]::new($false))
 $writeSucceeded=[IO.File]::ReadAllText($leaf) -ceq [string]$a.Payload
 if(-not $writeSucceeded){throw 'R348_CHILD_LEAF_WRITE_READBACK_UNEXPECTED'}
}catch{$failure=$_.Exception.GetType().Name+': '+$_.Exception.Message}
$status=if(!$failure -and $writeSucceeded){'OBSERVED_PRIVILEGED_LEAF_WRITE_WHILE_DIRECTORY_LEASE_HELD'}else{'NO_LEAF_WRITE_OBSERVED_OR_ACTOR_FAILED'}
$out=[ordered]@{
 Schema=1;Revision='R348';SourceCommit=$env:GITHUB_SHA;Status=$status
 Guest=$env:COMPUTERNAME;ActorPid=$PID;ActorAlreadyAdmin=$true
 OriginalSHA256=$a.OriginalSha256;LeafWriteSucceeded=$writeSucceeded
 AfterSHA256=$(if([IO.File]::Exists($leaf)){(Get-FileHash $leaf -Algorithm SHA256).Hash}else{'MISSING'})
 OwnerComputerTouched=$false;OriginalHelperStarted=$false
 Failure=$failure
}
[IO.File]::WriteAllText($receipt,($out|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
'R348_CHILD_STATUS='+$status
if($failure){throw ('R348_CHILD_TEST_OPERATION_FAILED_'+$failure)}
