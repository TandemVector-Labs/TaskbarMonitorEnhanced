[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$CandidateDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Read-only identity probes; no UAC or shared service/driver mutation.
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'R305_DISPOSABLE_GITHUB_WINDOWS_ONLY'
}
function SHA([string]$f){
 if(!(Test-Path -LiteralPath $f -PathType Leaf)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash
}
function Reject([string]$label,[string]$mode,[string]$payload,[string]$app,[string]$identity,[string]$expected){
 $observed=''
 try{[void](Assert-SensorPrivilegedBoundary $mode $payload $app $identity)}
 catch{$observed=$_.Exception.ToString()}
 if($observed -notmatch $expected){
  if($observed.Length -gt 500){$observed=$observed.Substring(0,500)}
  throw ('R305_UNEXPECTED_REFUSAL_'+$label+' ACTUAL='+$observed)
 }
 $script:checks.Add($label)
}
$root=Join-Path $env:RUNNER_TEMP ('R305_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $root 'R305_ELEVATED_TOKEN_SID_RECEIPT.json'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R304_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R304_LONG_POWERSHELL_TRANSPORT_RECEIPT.json')
$main=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced\TaskbarMonitorEnhanced.exe'
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$config=Join-Path $app 'config.json'
$state=Join-Path $app 'install_state.json'
$marker=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)) 'TaskbarMonitorEnhanced\SensorBroker\.tbme-owner.sid'
$checks=[Collections.Generic.List[string]]::new()
if(Test-Path -LiteralPath $root){throw 'R305_EXACT_RUN_FIXTURE_ROOT_EXISTS'}
$candidate=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
$previous=Get-Content -LiteralPath $prior -Raw|ConvertFrom-Json
if($candidate.Commit -cne $env:GITHUB_SHA -or
   $candidate.SetupSHA256 -cne (SHA $setup) -or
   $candidate.MainSHA256 -cne (SHA $main) -or
   $previous.SourceCommit -cne $env:GITHUB_SHA -or
   $previous.Host -cne $HostLabel -or
   $previous.Status -cne 'PASS_LONG_PROFILE_INMEMORY_POWERSHELL_FALLBACK'){
 throw 'R305_EXACT_CANDIDATE_OR_R304_NATIVE_PROOF_NOT_PINNED'
}
[void][IO.Directory]::CreateDirectory($root)
$original=@{ Main=(SHA $main);Config=(SHA $config);State=(SHA $state);Marker=(SHA $marker) }
$source=(Resolve-Path (Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1')).Path
$raw=[IO.File]::ReadAllText($source)
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw 'R305_WINPS51_HELPER_SYNTAX_INVALID'}
$defs=@($ast.FindAll({param($n)
 $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
 $n.Name -in @('Assert-SensorPrivilegedBoundary','Assert-SensorBoundaryNoReparse')
},$true))
if($defs.Count -ne 2){throw 'R305_EXPECTED_TWO_GUARD_AST_NODES'}
$checkAt=$raw.IndexOf("SENSOR_BOUNDARY_ELEVATED_TOKEN_ACCOUNT_MISMATCH",[StringComparison]::Ordinal)
$profileAt=$raw.IndexOf('$profileKey=',[StringComparison]::Ordinal)
$validatedAt=$raw.IndexOf('$validatedSensorSid=Assert-SensorPrivilegedBoundary',[StringComparison]::Ordinal)
$pipeAt=$raw.IndexOf('SENSOR_STATUS_CHANNEL_REQUIRED',[StringComparison]::Ordinal)
if($checkAt -lt 0 -or $profileAt -le $checkAt -or
   $validatedAt -le $profileAt -or $pipeAt -le $validatedAt -or
   $raw.Contains('New-Item -ItemType Directory -Force -Path $LogsRoot') -or
   $raw.Contains('Add-Content -LiteralPath $LogPath') -or
   $raw.Contains('Set-Content -LiteralPath $ResultPath')){
 throw 'R305_ELEVATED_TOKEN_CHECK_NOT_BEFORE_SECURE_IPC_OR_PRIVILEGED_PROFILE_WRITES'
}
$checks.Add('EFFECTIVE_TOKEN_SID_CHECK_BEFORE_SESSION_IPC_NO_PRIVILEGED_USER_LOG_WRITES')
$assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
$resource=$assembly.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
if(!$resource){throw 'R305_PRIVATE_SETUP_EMBEDDED_RESOURCE_MISSING'}
$reader=[IO.StreamReader]::new($resource)
try{$embedded=[string]$reader.ReadToEnd()}finally{$reader.Dispose()}
$normalize={param([string]$s) $s.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $normalize $raw) -cne (& $normalize $embedded)){
 throw 'R305_HELPER_SOURCE_NOT_EXACT_SETUP_PE'
}
$checks.Add('EXACT_PE_EMBEDDED_HELPER_CONTAINS_SID_CHECK')
# Evaluate only the two pure security functions from the compiled-source AST.
# Never dot-source or invoke the side-effecting privileged installer.
. ([scriptblock]::Create(($defs|ForEach-Object {$_.Extent.Text}) -join [Environment]::NewLine))
$token=[Security.Principal.WindowsIdentity]::GetCurrent()
$actualSid=[string]$token.User.Value
$actualName=[string]$token.Name
if($actualSid -cnotmatch '^S-1-5-21-(?:\d+-){3}\d+$'){
 throw 'R305_GUEST_NOT_INTERACTIVE_SID'
}
$temp=Join-Path ([Environment]::GetFolderPath('UserProfile')) 'AppData\Local\Temp'
$payloadInstall=Join-Path $temp ('tbme_setup_'+('a'*32))
$payloadUninstall=Join-Path $temp ('tbme_uninstall_'+('b'*32))
if((Assert-SensorPrivilegedBoundary Install $payloadInstall $app $actualSid) -cne $actualSid){
 throw 'R305_SAME_SID_INSTALL_NOT_ACCEPTED'
}
$checks.Add('EXACT_TOKEN_SID_INSTALL_ACCEPTED')
if((Assert-SensorPrivilegedBoundary Uninstall $payloadUninstall $app $actualSid) -cne $actualSid){
 throw 'R305_SAME_SID_UNINSTALL_NOT_ACCEPTED'
}
$checks.Add('EXACT_TOKEN_SID_UNINSTALL_ACCEPTED')
if((Assert-SensorPrivilegedBoundary Install $payloadInstall $app $actualName) -cne $actualSid){
 throw 'R305_CURRENT_ACCOUNT_NTNAME_NOT_RESOLVED_TO_TOKEN_SID'
}
$checks.Add('CURRENT_WINDOWS_ACCOUNT_NAME_RESOLVES_TO_TOKEN_SID')
$foreign='S-1-5-21-12345-23456-34567-45678'
if($foreign -ceq $actualSid){$foreign='S-1-5-21-12345-23456-34567-45679'}
Reject 'SYNTHETIC_FOREIGN_ACCOUNT_INSTALL_PREWRITE_REJECTED' Install $payloadInstall $app $foreign 'SENSOR_BOUNDARY_ELEVATED_TOKEN_ACCOUNT_MISMATCH'
Reject 'SYNTHETIC_FOREIGN_ACCOUNT_UNINSTALL_PREWRITE_REJECTED' Uninstall $payloadUninstall $app $foreign 'SENSOR_BOUNDARY_ELEVATED_TOKEN_ACCOUNT_MISMATCH'
Reject 'SYSTEM_SERVICE_SID_UNRESOLVABLE' Install $payloadInstall $app 'S-1-5-18' 'SENSOR_BOUNDARY_USER_ID_UNRESOLVABLE'
Reject 'UNRESOLVABLE_OTHER_ACCOUNT_REFUSED' Install $payloadInstall $app 'THIS_USER_MUST_NOT_EXIST_R305' 'SENSOR_BOUNDARY_USER_ID_UNRESOLVABLE'
Reject 'REQUESTED_WRONG_APP_ROOT_REFUSED' Install $payloadInstall (Join-Path $env:WINDIR 'R305_REJECT_ROOT') $actualSid 'SENSOR_BOUNDARY_APP_ROOT_OUTSIDE_USER_PROFILE'
if((SHA $main) -cne $original.Main -or (SHA $config) -cne $original.Config -or
   (SHA $state) -cne $original.State -or (SHA $marker) -cne $original.Marker){
 throw 'R305_READONLY_NATIVE_TOKEN_TEST_CHANGED_USER_OR_PROTECTED_BYTES'
}
$checks.Add('MAIN_CONFIG_STATE_AND_PROTECTED_OWNER_MARKER_UNTOUCHED')
$receiptValue=[ordered]@{
 Schema=1;Revision='R305'
 Status='PASS_EFFECTIVE_PROCESS_TOKEN_SID_BOUND_TO_REQUESTED_USER'
 Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
 OriginalOwnerComputerTouched=$false
 ActualUACOrProtectedServicesInvoked=$false
 PrivateEmbeddedPEHelperExact=$true
 SameUserIdentityAccepted=$true
 CrossAccountSyntheticSidsRejected=$true
 RejectedBeforeAnyLogOrServiceWrite=$true
 MainConfigStateAndMarkerUnchanged=$true
 Checks=@($checks)
 RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receipt,($receiptValue|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
'R305_GUEST_'+$HostLabel+'_EFFECTIVE_TOKEN_SID_POLICY=PASS'
