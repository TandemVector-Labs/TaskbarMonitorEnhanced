[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,
 [Parameter(Mandatory=$true)][string]$CandidateDir
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
 throw 'R304_DISPOSABLE_WINDOWS_ONLY'
}

function Hash([string]$path){
 if(!(Test-Path -LiteralPath $path -PathType Leaf)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
function Expect-FailsClosed([string]$description,[string]$arguments,[string]$reason){
 $psi=[Diagnostics.ProcessStartInfo]::new()
 $psi.FileName=$script:trustedHost
 $psi.Arguments=$arguments
 $psi.UseShellExecute=$false
 $psi.CreateNoWindow=$true
 $psi.RedirectStandardOutput=$true
 $psi.RedirectStandardError=$true
 $process=[Diagnostics.Process]::Start($psi)
 if(!$process){throw ('R304_PROCESS_NOT_CREATED_'+$description)}
 try{
  $stdout=$process.StandardOutput.ReadToEndAsync()
  $stderr=$process.StandardError.ReadToEndAsync()
  if(!$process.WaitForExit(25000)){
   if(!$process.HasExited){$process.Kill();[void]$process.WaitForExit(9000)}
   throw ('R304_POWERSHELL_TEST_TIMEOUT_'+$description)
  }
  $text=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
  if($process.ExitCode -eq 0 -or $text -notmatch $reason){
   if($text.Length -gt 500){$text=$text.Substring(0,500)}
   throw ('R304_EXPECTED_PREWRITE_REFUSAL_MISSING_'+$description+' EXIT='+$process.ExitCode+' OUTPUT='+$text)
  }
  if(Test-Path -LiteralPath $script:sentinel){
   throw ('R304_ATTACK_SENTINEL_CREATED_'+$description)
  }
  $script:checks.Add($description)
 }finally{$process.Dispose()}
}

$root=Join-Path $env:RUNNER_TEMP ('R304_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $root 'R304_LONG_POWERSHELL_TRANSPORT_RECEIPT.json'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R303_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R303_PROTECTED_SENSOR_OWNER_RECEIPT.json')
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$config=Join-Path $app 'config.json'
$state=Join-Path $app 'install_state.json'
$checks=[Collections.Generic.List[string]]::new()
if(Test-Path -LiteralPath $root){throw 'R304_PREEXISTING_TEST_ROOT'}
$candidate=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
$previous=Get-Content -LiteralPath $prior -Raw|ConvertFrom-Json
if($candidate.Commit -cne $env:GITHUB_SHA -or
   (Hash $setup) -cne $candidate.SetupSHA256 -or
   (Hash $main) -cne $candidate.MainSHA256 -or
   $previous.SourceCommit -cne $env:GITHUB_SHA -or
   $previous.Host -cne $HostLabel -or
   $previous.Status -cne 'PASS_PROTECTED_SENSOR_OWNER_MARKER_REPAIR_GUARD'){
 throw 'R304_SOURCE_OR_PREVIOUS_NATIVE_RECEIPT_NOT_PINNED'
}
$original=@{ Main=(Hash $main);Config=(Hash $config);State=(Hash $state) }
[void][IO.Directory]::CreateDirectory($root)
$script:sentinel=Join-Path $root 'injection-must-not-be-executed.txt'
$script:trustedHost=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
if(-not [IO.File]::Exists($script:trustedHost)){
 throw 'R304_ABSOLUTE_SYSTEM_POWERSHELL_MISSING'
}
$assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
$type=$assembly.GetType('SetupProgram',$true)
$flags=[Reflection.BindingFlags]'Static,NonPublic'
$builder=$type.GetMethod('BuildElevatedHelperCommand',$flags)
$hostMethod=$type.GetMethod('TrustedSystemPowerShellPath',$flags)
if(!$builder -or !$hostMethod){throw 'R304_COMPILED_METHODS_NOT_FOUND'}
$hostSource=[string]$hostMethod.Invoke($null,$null)
if(-not [string]::Equals($hostSource,$script:trustedHost,[StringComparison]::OrdinalIgnoreCase)){
 throw 'R304_SYSTEM_POWER_SHELL_HOST_NOT_PINNED'
}
$checks.Add('TRUSTED_ABSOLUTE_SYSTEM_HOST_PINNED')
function Command([string]$mode,[string]$payload,[string]$application,[string]$user){
 $arguments=[object[]]::new(4)
 $arguments[0]=$mode;$arguments[1]=$payload;$arguments[2]=$application;$arguments[3]=$user
 return [string]$builder.Invoke($null,$arguments)
}
$user=[string]([Security.Principal.WindowsIdentity]::GetCurrent().Name)
$normalPayload=Join-Path $env:RUNNER_TEMP ('tbme_setup_'+('a'*32))
$normalRoot=Join-Path $env:WINDIR 'R304_Expected_PreWrite_Refusal'
$normal=Command Install $normalPayload $normalRoot $user
$encodedPrefix='-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand '
$inlinePrefix='-NoProfile -NonInteractive -WindowStyle Hidden -Command '
$shortIsEncoded=$normal.StartsWith($encodedPrefix,[StringComparison]::Ordinal)
$shortIsInline=$normal.StartsWith($inlinePrefix,[StringComparison]::Ordinal)
if((-not $shortIsEncoded -and -not $shortIsInline) -or
   ($shortIsEncoded -and $normal.Length -gt 32080) -or
   ($shortIsInline -and $normal.Length -gt 30000) -or
   $normal.Contains(' -File ')){
 throw 'R304_SHORT_UNBOUNDED_OR_UNSAFE_TRANSPORT'
}
$normalCode=if($shortIsEncoded){
 [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($normal.Substring($encodedPrefix.Length)))
}else{$normal.Substring($inlinePrefix.Length)}
$match=[regex]::Match($normalCode,"(?m)^\`$blob=\[Convert\]::FromBase64String\('([A-Za-z0-9+/=]+)'\)")
if(!$match.Success){throw 'R304_PRIOR_PE_HELPER_BLOB_NOT_ENCODED'}
$originalBlob=$match.Groups[1].Value
$checks.Add('SHORT_INMEMORY_COMMAND_PE_BLOB_PINNED')
$longName='C:\Users\'+('Q'*128)
$longPayload=$longName+'\AppData\Local\Temp\tbme_setup_'+('b'*32)
$longRoot=$longName+'\AppData\Local\TaskbarMonitorEnhanced'
$fallback=Command Install $longPayload $longRoot $user
$commandPrefix='-NoProfile -NonInteractive -WindowStyle Hidden -Command '
if(-not $fallback.StartsWith($commandPrefix,[StringComparison]::Ordinal) -or
   $fallback.Contains(' -File ') -or $fallback.Contains('ExecutionPolicy Bypass') -or
   $fallback.Length -gt 30000 -or $fallback.Contains($longRoot) -or
   $fallback.Contains($longPayload)){
 throw 'R304_LONG_PROFILE_FALLBACK_USES_UNTRUSTED_FILE_OR_RAW_ARGS'
}
$fallbackScript=$fallback.Substring($commandPrefix.Length)
$fallbackMatch=[regex]::Match($fallbackScript,"(?m)^\`$blob=\[Convert\]::FromBase64String\('([A-Za-z0-9+/=]+)'\)")
if(!$fallbackMatch.Success -or $fallbackMatch.Groups[1].Value -cne $originalBlob -or
   -not $fallbackScript.Contains('[ScriptBlock]::Create($code)')){
 throw 'R304_FALLBACK_EMBEDDED_SCRIPT_PROVENANCE_CHANGED'
}
$checks.Add('LONG_PROFILE_COMMAND_FALLBACK_HAS_EXACT_TRUSTED_PE_BLOB')
$malicious=$longPayload+"'; [IO.File]::WriteAllText('"+$script:sentinel+"','INJECTED'); #"
$attack=Command Install $malicious $longRoot $user
if(-not $attack.StartsWith($commandPrefix,[StringComparison]::Ordinal) -or
   $attack.Contains($malicious) -or $attack.Contains($script:sentinel)){
 throw 'R304_INJECTION_SYNTAX_ESCAPED_DATA_B64'
}
$checks.Add('INJECTION_TOKENS_ARE_NEVER_RAW_POWERSHELL_CODE')
$limitFailed=$false
try{$null=Command Install ('X'*4100) $normalRoot $user}
catch{
 if($_.Exception.ToString() -match 'missing or too long'){$limitFailed=$true}
 else{throw}
}
if(!$limitFailed){throw 'R304_UNBOUNDED_PARAMETER_FAILOPEN'}
$checks.Add('PER_PARAMETER_LENGTH_CAP_PRESERVED')
# The native 5.1 child runs as the current guest user, NEVER with Verb=runas.
# All three invocations must refuse before writing any optional sensor state.
Expect-FailsClosed 'SHORT_EXACT_PE_COMMAND_REFUSED_PREWRITE' $normal 'SENSOR_BOUNDARY_APP_ROOT_OUTSIDE_USER_PROFILE'
Expect-FailsClosed 'LONG_NEW_COMMAND_REFUSED_PREWRITE' $fallback 'SENSOR_BOUNDARY_APP_ROOT_OUTSIDE_USER_PROFILE'
Expect-FailsClosed 'HOSTILE_LONG_COMMAND_REFUSED_PREWRITE' $attack 'SENSOR_BOUNDARY_APP_ROOT_OUTSIDE_USER_PROFILE'
if((Hash $main) -cne $original.Main -or
   (Hash $config) -cne $original.Config -or
   (Hash $state) -cne $original.State -or
   (Test-Path -LiteralPath $script:sentinel)){
 throw 'R304_INSTALLED_MAIN_SETTINGS_OR_INJECTION_SENTINEL_CHANGED'
}
$checks.Add('GUEST_MAIN_CONFIG_STATE_AND_SENTINEL_UNCHANGED')
$record=[ordered]@{
 Schema=1;Revision='R304'
 Status='PASS_LONG_PROFILE_INMEMORY_POWERSHELL_FALLBACK'
 Host=$HostLabel;SourceCommit=$env:GITHUB_SHA;NoUAC=$true
 OriginalOwnerComputerTouched=$false
 ShortEncodedCommandUsed=$shortIsEncoded
 ShortInlineTransportVerified=$shortIsInline
 LongProfileFallbackCommandExecuted=$true
 NoUserWritableScriptExecuted=$true
 HostileInputRemainedEncoded=$true
 InstalledUserFilesUnchanged=$true
 ShortCommandLength=$normal.Length
 LongFallbackCommandLength=$fallback.Length
 HostileFallbackCommandLength=$attack.Length
 Checks=@($checks)
 RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receipt,($record|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
'R304_'+$HostLabel+'_SHORT_LONG_HOSTILE_POWERSHELL_TRANSPORT_PASS'
