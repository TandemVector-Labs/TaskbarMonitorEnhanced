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
   $env:GITHUB_SHA -cnotmatch '^[0-9a-f]{40}$' -or
   $env:GITHUB_RUN_ID -cnotmatch '^[0-9]{5,20}$'){
 throw 'R344_ACL_TEST_REFUSES_NON_DISPOSABLE_WINDOWS'
}
if((git -C $SourceRoot rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){
 throw 'R344_ACL_GUEST_EXACT_COMMIT_MISMATCH'
}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 throw 'R344_ACL_TEST_REQUIRES_EXISTING_ADMIN_TOKEN_NO_UAC'
}
$realScript=(Resolve-Path -LiteralPath (Join-Path $SourceRoot 'installer\TBME_Setup_Elevated_Helper.ps1')).Path
$setup=(Resolve-Path -LiteralPath (Join-Path $SourceRoot 'build\_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe')).Path
$raw=[IO.File]::ReadAllText($realScript)
$asm=[Reflection.Assembly]::LoadFrom($setup)
$stream=$asm.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
if(!$stream){throw 'R344_ACL_COMPILED_REAL_PE_HELPER_ABSENT'}
$reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
try{$fromSetup=$reader.ReadToEnd()}finally{$reader.Dispose()}
$norm={param($text) $text.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $norm $raw) -cne (& $norm $fromSetup)){
 throw 'R344_ACL_SOURCE_NOT_EXACT_COMPILED_PE_HELPER'
}
$tok=$null;$err=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($realScript,[ref]$tok,[ref]$err)
if(@($err).Count){throw 'R344_ACL_EMBEDDED_HELPER_PS51_AST_INVALID'}
$names=@('Assert-SensorBoundaryNoReparse','Assert-SensorJournalTrustedAcl')
$defs=@($ast.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
 $node.Name -in @('Assert-SensorBoundaryNoReparse','Assert-SensorJournalTrustedAcl')
},$true))
if($defs.Count -ne 2){throw 'R344_ACL_REAL_PRODUCTION_FUNCTION_MISSING'}
. ([scriptblock]::Create(($defs|ForEach-Object{$_.Extent.Text}) -join [Environment]::NewLine))
$container=Join-Path $env:RUNNER_TEMP ('R344Acl_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$target=Join-Path $container 'test-root'
$receipt=Join-Path $container 'R344_JOURNAL_ACL_MASK.json'
if(Test-Path -LiteralPath $container){throw 'R344_ACL_UNIQUE_TEST_ROOT_COLLISION'}
$checks=[Collections.Generic.List[string]]::new()
$failure=''
$clean=$false
$realAcl=$null
function Pass([string]$label){$script:checks.Add($label);Write-Output ('PASS '+$label)}
function GuardedExpectReject([string]$expected){
 $message=''
 try{
  Assert-SensorJournalTrustedAcl $target $true
  throw 'R344_ACL_DANGEROUS_ALLOW_WRITE_ACCEPTED'
 }catch{
  $message=$_.Exception.Message
 }
 if($message -cne $expected){throw ('R344_ACL_WRONG_REJECTION_'+$message)}
}
try{
 [void][IO.Directory]::CreateDirectory($container)
 $admins=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
 $system=[Security.Principal.SecurityIdentifier]::new('S-1-5-18')
 $users=[Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
 $base=[Security.AccessControl.DirectorySecurity]::new()
 $base.SetOwner($admins);$base.SetAccessRuleProtection($true,$false)
 foreach($sid in @($admins,$system,$users)){
  $rights=if($sid -eq $users){[Security.AccessControl.FileSystemRights]::ReadAndExecute}else{[Security.AccessControl.FileSystemRights]::FullControl}
  $rule=[Security.AccessControl.FileSystemAccessRule]::new(
   $sid,$rights,[Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
   [Security.AccessControl.PropagationFlags]::None,
   [Security.AccessControl.AccessControlType]::Allow)
  [void]$base.AddAccessRule($rule)
 }
 [void][IO.Directory]::CreateDirectory($target,$base)
 $realAcl=Get-Acl -LiteralPath $target
 if($realAcl.Owner -notmatch '(?i)Administrators' -or !$realAcl.AreAccessRulesProtected){
  throw 'R344_ACL_GUEST_DOES_NOT_HAVE_EXPECTED_ADMIN_OWNER'
 }
 Pass 'REAL_PE_EMBEDDED_HELPER_AND_PROTECTED_ADMIN_DACL_EXACT'
 Assert-SensorJournalTrustedAcl $target $true
 Pass 'BUILTIN_USERS_READ_EXECUTE_ALLOWED_NOT_MISCLASSIFIED_AS_WRITE'
 $rights=@([Security.AccessControl.FileSystemRights]::Modify,
  [Security.AccessControl.FileSystemRights]::WriteData,
  [Security.AccessControl.FileSystemRights]::Delete,
  [Security.AccessControl.FileSystemRights]::ChangePermissions)
 $labels=@('MODIFY','WRITE_DATA','DELETE','CHANGE_PERMISSIONS')
 for($i=0;$i -lt $rights.Count;$i++){
  $candidate=Get-Acl -LiteralPath $target
  $rule=[Security.AccessControl.FileSystemAccessRule]::new(
   $users,$rights[$i],[Security.AccessControl.AccessControlType]::Allow)
  [void]$candidate.AddAccessRule($rule)
  Set-Acl -LiteralPath $target -AclObject $candidate -ErrorAction Stop
  try{GuardedExpectReject 'SENSOR_JOURNAL_UNTRUSTED_WRITE_ACE'}
  finally{Set-Acl -LiteralPath $target -AclObject $realAcl -ErrorAction Stop}
  Assert-SensorJournalTrustedAcl $target $true
  Pass ('BUILTIN_USERS_'+$labels[$i]+'_REJECTED_WITH_SAME_DACL_RESTORED')
 }
}catch{$failure=$_.Exception.ToString()}
finally{
 try{
  if([IO.Directory]::Exists($target)){
   Assert-SensorBoundaryNoReparse $target
   if(@([IO.Directory]::GetFileSystemEntries($target)).Count -ne 0){
    throw 'R344_ACL_TEST_ROOT_HAS_UNEXPECTED_MEMBERS'
   }
   if($realAcl){Set-Acl -LiteralPath $target -AclObject $realAcl -ErrorAction Stop}
   [IO.Directory]::Delete($target,$false)
  }
  $clean=(![IO.Directory]::Exists($target))
 }catch{$failure+=' CLEANUP_FAIL '+$_.Exception.ToString()}
 $expected=6
 $status=if(!$failure -and $checks.Count -eq $expected -and $clean){'PASS_REAL_COMPILED_JOURNAL_ACL_MASK_NTFS'}else{'FAIL_R344_JOURNAL_ACL_GUEST'}
 $data=[ordered]@{
  Schema=1;Revision='R344';Status=$status
  SourceCommit=$env:GITHUB_SHA;Host=$HostLabel
  ExactPEEmbeddedRealProductionFunction=$true
  UsersReadAndExecuteAllowed=($checks.Contains('BUILTIN_USERS_READ_EXECUTE_ALLOWED_NOT_MISCLASSIFIED_AS_WRITE'))
  FourUntrustedMutationACEsRejected=($checks.Count -eq $expected)
  OriginalAdminOwnedFixtureRemoved=$clean
  RealOwnerComputerTouched=$false;UacPromptTested=$false
  Checks=@($checks);Failure=$failure
 }
 if([IO.Directory]::Exists($container)){
  [IO.File]::WriteAllText($receipt,($data|ConvertTo-Json -Depth 6),
     [Text.UTF8Encoding]::new($false))
  Write-Output ('R344_JOURNAL_ACL_RECEIPT='+$receipt)
 }
 Write-Output ('R344_JOURNAL_ACL_STATUS='+$status)
}
if($failure){throw ('R344_NATIVE_COMPILED_ACL_NEGATIVE_FAILED '+$failure)}
