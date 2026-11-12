[CmdletBinding()]
param(
 [string]$SetupPath='',
 [switch]$HostedFresh,
 [ValidateSet('LOCAL','A','B')][string]$HostLabel='LOCAL'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($SetupPath)){
 $SetupPath=Join-Path $PSScriptRoot '_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   !(Test-Path -LiteralPath $SetupPath -PathType Leaf)){
 throw 'R331_REQUIRES_COMPILED_DOTNET_FRAMEWORK_SETUP'
}
$path=(Resolve-Path -LiteralPath $SetupPath).Path
$codePath=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\installer\TaskbarMonitorEnhanced_Setup.cs')).Path
$assembly=[Reflection.Assembly]::LoadFrom($path)
$type=$assembly.GetType('SetupProgram',$true)
$resource=$assembly.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced_Setup.cs')
if(!$resource){throw 'R331_SHIPPED_PE_MISSING_CANONICAL_CSHARP_RESOURCE'}
$reader=[IO.StreamReader]::new($resource,[Text.Encoding]::UTF8)
try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
$source=[IO.File]::ReadAllText($codePath,[Text.Encoding]::UTF8)
$norm={param($t) $t.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $norm $embedded) -cne (& $norm $source)){throw 'R331_EMBEDDED_SOURCE_NOT_EXACT'}
$checks=[Collections.Generic.List[string]]::new()
function Pass([string]$name){
 $script:checks.Add($name)
 Write-Output ('PASS '+$name)
}
Pass 'COMPILED_SETUP_SOURCE_RESOURCE_EQUALS_REVIEW_SOURCE'

$method=$type.GetMethod('WriteHostedUpgradeFailure',[Reflection.BindingFlags]'Static,NonPublic')
if($null -ne $method){throw 'R331_SHIPPING_SETUP_HAS_HOSTED_FILE_WRITE_METHOD'}
Pass 'OLD_RUNNER_DIAGNOSTIC_METHOD_ABSENT_FROM_PE'
foreach($token in @(
 'R129_DIAG_','R129_FAIL_CLOSED_DIAGNOSTIC',
 'TBME_UPDATE_DIAGNOSTIC_PHASE',
 'WriteHostedUpgradeFailure')){
 if($source.Contains($token)){throw ('R331_UNTRUSTED_HOST_DIAGNOSTIC_TOKEN_PRESENT_'+$token)}
}
Pass 'NO_ENV_CONTROLLED_HOSTED_DIAGNOSTIC_DATAFLOW'
if($source -notmatch '(?s)if\(Has\(args,"/update"\)\)\s*\{.*?try\s*\{.*?UpgradeExisting\(\).*?\}\s*catch\(Exception ex\)\s*\{\s*if\(!quiet\)MessageBox\.Show\(ex\.Message,.*?return 34;'){
 throw 'R331_UPDATE_FAILURE_CONTRACT_RETURN_34_CHANGED'
}
Pass 'UPDATE_FAILURE_REMAINS_FAIL_CLOSED_EXIT_34'
if($source -notmatch '(?s)static SensorOutcome UpgradeExisting\(\)\s*\{\s*if\(!Directory\.Exists\(AppRoot\)\)throw new InvalidOperationException'){
 throw 'R331_UPDATE_FRESH_ROOT_PRECONDITION_CHANGED'
}
Pass 'UPDATE_FRESH_ROOT_MISSING_RETURNS_BEFORE_JOURNAL_WRITES'
if($source -notmatch 'RecoverUpgradeStageIfAny\(\);' -or
   $source -notmatch 'CheckSingleCanonicalRoot\(\);'){
 throw 'R331_UPGRADE_RECOVERY_AND_IDENTITY_GUARDS_REMOVED'
}
Pass 'EXISTING_UPGRADE_RECOVERY_AND_IDENTITY_GUARDS_PRESERVED'
$legacyTest=Join-Path $PSScriptRoot 'Test-Stable170-InPlace-R126.ps1'
$testSource=[IO.File]::ReadAllText((Resolve-Path $legacyTest).Path)
if(!$testSource.Contains('TBME_UPDATE_DIAGNOSTIC_PHASE') -or
   $testSource.Contains('R129_DIAG_') -or
   $testSource.Contains('R129_FAIL_CLOSED_DIAGNOSTIC')){
 throw 'R331_LEGACY_TEST_REQUIRES_REMOVED_DIAGNOSTIC_OUTPUT'
}
Pass 'LEGACY_UPGRADE_TEST_DOES_NOT_CONSUME_REMOVED_SIDE_EFFECT'
if($checks.Count -ne 7){throw ('R331_NATIVE_LOCAL_CASE_COUNT_'+$checks.Count)}
Write-Output 'R331_COMPILED_SETUP_DIAGNOSTIC_PATH_REMOVAL_LOCAL=7/7_PASS'
if(!$HostedFresh){return}
if($HostLabel -cnotin @('A','B') -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_SHA -cnotmatch '^[0-9a-f]{40}$' -or
   $env:GITHUB_RUN_ID -cnotmatch '^\d+$' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC'){
 throw 'R331_REFUSE_LIVE_OWNER_NON_DISPOSABLE_HOST'
}
$profile=[Environment]::GetFolderPath('UserProfile')
$local=[Environment]::GetFolderPath('LocalApplicationData')
$app=Join-Path $local 'TaskbarMonitorEnhanced'
$reg='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TaskbarMonitorEnhanced'
if([IO.Directory]::Exists($app) -or (Test-Path $reg) -or
   @(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count -ne 0){
 throw 'R331_GUEST_HAS_EXISTING_INSTALLATION_OR_RUNNING_MAIN'
}
Pass 'FRESH_DISPOSABLE_USER_INSTALL_REGISTRY_AND_MAIN_ABSENT'
$base=Join-Path $env:RUNNER_TEMP ('R331_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
if([IO.Directory]::Exists($base)){throw 'R331_HOSTED_EVIDENCE_BASE_ALREADY_EXISTS'}
[IO.Directory]::CreateDirectory($base)|Out-Null
$evidence=Join-Path $base 'TBME_R126_STABLE_UPDATE'
[IO.Directory]::CreateDirectory($evidence)|Out-Null
$sentinel=Join-Path $evidence 'external-user-canary.txt'
[IO.File]::WriteAllText($sentinel,'R331_PRESERVE_CANARY',[Text.UTF8Encoding]::new($false))
$psi=[Diagnostics.ProcessStartInfo]::new()
$psi.FileName=$path
$psi.Arguments='/update /quiet'
$psi.UseShellExecute=$false
$psi.CreateNoWindow=$true
$psi.WorkingDirectory=[IO.Path]::GetDirectoryName($path)
$psi.EnvironmentVariables['GITHUB_ACTIONS']='true'
$psi.EnvironmentVariables['RUNNER_ENVIRONMENT']='github-hosted'
$psi.EnvironmentVariables['RUNNER_OS']='Windows'
$psi.EnvironmentVariables['GITHUB_SHA']=$env:GITHUB_SHA
$psi.EnvironmentVariables['RUNNER_TEMP']=$base
$psi.EnvironmentVariables['TBME_UPDATE_DIAGNOSTIC_PHASE']='NEGATIVE_USER_EDIT'
$proc=[Diagnostics.Process]::Start($psi)
if(!$proc){throw 'R331_REAL_SETUP_PROCESS_NOT_STARTED'}
try{
 if(!$proc.WaitForExit(45000)){
  $proc.Kill();[void]$proc.WaitForExit(10000)
  throw 'R331_REAL_SETUP_NEGATIVE_EXIT_TIMEOUT'
 }
 if($proc.ExitCode -ne 34){throw ('R331_EXPECTED_FRESH_UPDATE_REJECTION_EXIT34_GOT_'+$proc.ExitCode)}
}finally{$proc.Dispose()}
Pass 'REAL_UNMODIFIED_SETUP_BINARY_FRESH_UPDATE_REJECTS_WITH_34'
$bad=Join-Path $evidence 'R129_DIAG_NEGATIVE_USER_EDIT.txt'
if(Test-Path -LiteralPath $bad){throw 'R331_OLD_DIAGNOSTIC_FILE_WAS_WRITTEN'}
if(@([IO.Directory]::GetFileSystemEntries($evidence)).Count -ne 1){throw 'R331_DIAGNOSTIC_CREATED_EXTRA_FILES'}
Pass 'ENV_SPOOFED_DIAGNOSTIC_OUTPUT_WAS_NOT_CREATED'
if([IO.File]::ReadAllText($sentinel) -cne 'R331_PRESERVE_CANARY'){
 throw 'R331_OUTSIDE_CANARY_MODIFIED'
}
Pass 'SENTINEL_PRESERVED'
if([IO.Directory]::Exists($app) -or (Test-Path $reg)){
 throw 'R331_REAL_NEGATIVE_SETUP_CREATED_NEW_APP_OR_REGISTRATION'
}
Pass 'NO_NEW_APPROOT_AND_REGISTRY_ON_FRESH_NEGATIVE'
$receipt=[ordered]@{
 Schema=1
 Revision='R331'
 Host=$HostLabel
 SourceCommit=$env:GITHUB_SHA
 Status='PASS_FRESH_REAL_SETUP_FAIL_CLOSED_WITHOUT_HOSTED_DIAGNOSTIC_WRITE'
 SetupSHA256=(Get-FileHash $path -Algorithm SHA256).Hash
 Checks=@($checks.ToArray())
 SetupExit=34
 RealSetupExecuted=$true
 DiagnosticOutputAbsent=$true
 CanaryPreserved=$true
 InstalledAppUntouched=$true
 OwnerMachineTouched=$false
 MainWasNotLaunched=$true
 ElevatedUACNotInvoked=$true
 SecurityFinalAccepted=$false
}
$receiptPath=Join-Path $base 'R331_HOSTED_DIAGNOSTIC_REMOVAL_RECEIPT.json'
[IO.File]::WriteAllText($receiptPath,($receipt|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
if($checks.Count -ne 12){throw ('R331_HOSTED_CASE_COUNT_BAD_'+$checks.Count)}
Write-Output ('R331_HOSTED_REAL_SETUP_NEGATIVE_NO_DIAGNOSTIC=12/12 '+$HostLabel+
              ' SHA256='+((Get-FileHash $receiptPath -Algorithm SHA256).Hash))
