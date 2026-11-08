[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'R307_ONLY_DISPOSABLE_NATIVE_WINDOWS'
}
$root=Join-Path $env:RUNNER_TEMP ('R307_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$protected=Join-Path $root 'owned-protected-journal'
$unsafe=Join-Path $root 'unsafe-user-journal'
$outside=Join-Path $root 'unrelated-user-canary'
$receipt=Join-Path $root 'R307_PROTECTED_JOURNAL_ACL_RECEIPT.json'
$checks=[Collections.Generic.List[string]]::new()
if(Test-Path -LiteralPath $root){throw 'R307_PREEXISTING_GUEST_JOURNAL_FIXTURE'}
[void][IO.Directory]::CreateDirectory($root)
[void][IO.Directory]::CreateDirectory($outside)
$canary=Join-Path $outside 'canary.txt'
[IO.File]::WriteAllText($canary,'R307_UNRELATED_CANARY',[Text.Encoding]::ASCII)
$canarySHA=(Get-FileHash -LiteralPath $canary -Algorithm SHA256).Hash
$admins=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
$system=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
$trusted=[Security.Principal.SecurityIdentifier]::new('S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
$allowed=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
[void]$allowed.Add($admins.Value)
[void]$allowed.Add($system.Value)
[void]$allowed.Add($trusted.Value)
$writable=(
 [Security.AccessControl.FileSystemRights]::Write -bor
 [Security.AccessControl.FileSystemRights]::Modify -bor
 [Security.AccessControl.FileSystemRights]::Delete -bor
 [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
 [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
 [Security.AccessControl.FileSystemRights]::TakeOwnership
)
function Assert-R307ProtectedAcl([string]$target){
 $info=Get-Item -LiteralPath $target -Force -ErrorAction Stop
 if(-not $info.PSIsContainer -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  throw 'R307_REPARSE_OR_NON_DIRECTORY_REFUSED'
 }
 $acl=Get-Acl -LiteralPath $target -ErrorAction Stop
 $owner=[Security.Principal.NTAccount]::new([string]$acl.Owner)
 $ownerSid=$owner.Translate([Security.Principal.SecurityIdentifier])
 if(-not $allowed.Contains($ownerSid.Value)){
  throw ('R307_JOURNAL_OWNER_NOT_TRUSTED '+$ownerSid.Value)
 }
 if(-not $acl.AreAccessRulesProtected){
  throw 'R307_JOURNAL_INHERITED_DACL_REFUSED'
 }
 $aces=$acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])
 foreach($rule in $aces){
  if($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
    -not $allowed.Contains([string]$rule.IdentityReference.Value) -and
    ($rule.FileSystemRights -band $writable)){
     throw 'R307_JOURNAL_BROAD_WRITE_ALLOW_REFUSED'
  }
 }
 return $acl
}
$security=[Security.AccessControl.DirectorySecurity]::new()
$security.SetOwner($admins)
$security.SetAccessRuleProtection($true,$false)
$inherit=[Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
$none=[Security.AccessControl.PropagationFlags]::None
$allow=[Security.AccessControl.AccessControlType]::Allow
foreach($principal in @($admins,$system)){
 $rule=[Security.AccessControl.FileSystemAccessRule]::new(
    $principal,[Security.AccessControl.FileSystemRights]::FullControl,
    $inherit,$none,$allow)
 $security.AddAccessRule($rule)
}
# .NET Framework Windows PowerShell 5.1 supports atomic directory creation
# with an explicit DACL. Never create first and tighten permissions later.
[void][IO.Directory]::CreateDirectory($protected,$security)
$effective=Assert-R307ProtectedAcl $protected
$checks.Add('CREATED_WITH_TRUSTED_OWNER_AND_PROTECTED_DACL')
$aclSids=@($effective.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])|
  ForEach-Object {$_.IdentityReference.Value})
if(-not ($aclSids -contains 'S-1-5-32-544') -or
   -not ($aclSids -contains 'S-1-5-18')){
 throw 'R307_SYSTEM_AND_ADMIN_FULL_CONTROL_MISSING'
}
$checks.Add('SYSTEM_AND_ADMINISTRATORS_PERSISTENT_ACCESS')
$file=Join-Path $protected 'manifest.json'
$bytes=[Text.Encoding]::UTF8.GetBytes('{"Schema":1,"Sid":"R307"}')
$stream=[IO.FileStream]::new($file,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
if((Get-FileHash $file -Algorithm SHA256).Hash -cne
 ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create().ComputeHash($bytes))).Replace('-',''))){
 throw 'R307_PROTECTED_MANIFEST_FLUSH_READBACK_MISMATCH'
}
$checks.Add('FLUSHED_MANIFEST_SHA_READBACK')
function Assert-R307ProtectedManifestFile([string]$path){
 $fileInfo=Get-Item -LiteralPath $path -Force -ErrorAction Stop
 if($fileInfo.PSIsContainer -or ($fileInfo.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  throw 'R307_MANIFEST_NOT_ORDINARY_FILE'
 }
 $acl=Get-Acl -LiteralPath $path -ErrorAction Stop
 $ownerSid=([Security.Principal.NTAccount]::new([string]$acl.Owner)).Translate(
    [Security.Principal.SecurityIdentifier])
 if(-not $allowed.Contains($ownerSid.Value)){throw 'R307_MANIFEST_OWNER_NOT_TRUSTED'}
 foreach($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])){
  if($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
     -not $allowed.Contains([string]$rule.IdentityReference.Value) -and
     ($rule.FileSystemRights -band $writable)){
   throw 'R307_MANIFEST_FILE_BROAD_WRITE_ALLOWED'
  }
 }
}
Assert-R307ProtectedManifestFile $file
$checks.Add('MANIFEST_FILE_OWNER_AND_ACL_TRUSTED')
# A preexisting user-writable directory must never be accepted as a journal.
[void][IO.Directory]::CreateDirectory($unsafe)
$denied=$false
try{$null=Assert-R307ProtectedAcl $unsafe}
catch{if($_.Exception.Message -match 'OWNER_NOT_TRUSTED|INHERITED_DACL_REFUSED|BROAD_WRITE_ALLOW_REFUSED'){$denied=$true}else{throw}}
if(!$denied){throw 'R307_EXISTING_USER_WRITABLE_FOLDER_ACCEPTED'}
$checks.Add('USER_WRITABLE_EXISTING_DIRECTORY_FAIL_CLOSED')
# A junction, even if placed under a legitimate parent, is never accepted.
$link=Join-Path $root 'test-junction'
New-Item -ItemType Junction -Path $link -Target $outside -ErrorAction Stop|Out-Null
if(-not ((Get-Item -LiteralPath $link -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){
 throw 'R307_NATIVE_JUNCTION_NOT_CREATED'
}
$denied=$false
try{$null=Assert-R307ProtectedAcl $link}catch{
 if($_.Exception.Message -match 'REPARSE_OR_NON_DIRECTORY_REFUSED'){$denied=$true}else{throw}
}
if(!$denied){throw 'R307_JUNCTION_TRAVERSED'}
if((Get-FileHash $canary -Algorithm SHA256).Hash -cne $canarySHA){
 throw 'R307_JUNCTION_DESTINATION_CHANGED'
}
$checks.Add('REAL_REPARSE_JUNCTION_REFUSED_AND_CANARY_IMMUTABLE')
# A read-only observation of real Program Files ancestors is informative,
# but never mutates live protected sensor files or ACLs.
$programFiles=[Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
$actualProgramFilesOwner=(Get-Acl -LiteralPath $programFiles).Owner
if([string]::IsNullOrWhiteSpace($actualProgramFilesOwner)){throw 'R307_REAL_PROGRAM_FILES_OWNER_UNREADABLE'}
$checks.Add('REAL_PROGRAM_FILES_ACL_READ_ONLY')
$data=[ordered]@{
 Schema=1;Revision='R307-PROTOTYPE'
 Status='PASS_PROTECTED_JOURNAL_ACL_TRUST_BOUNDARY_SYNTHETIC'
 Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
 OwnerComputerTouched=$false
 ActualProtectedSensorTaskTouched=$false
 RealProgramFilesWritten=$false
 ExplicitProtectedDaclCreated=$true
 OwnerTrustedAdministrators=$true
 SystemAdminAccessVerified=$true
 ManifestFileOwnerTrusted=$true
 UserWritableRootRejected=$true
 NativeJunctionRejected=$true
 FlushedManifestHashMatched=$true
 OutsideCanaryPreserved=$true
 Checks=@($checks)
 RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receipt,($data|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
'R307_'+$HostLabel+'_PROTECTED_ACL_MODEL_PASS'
