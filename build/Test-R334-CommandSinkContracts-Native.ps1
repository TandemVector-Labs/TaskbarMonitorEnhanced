[CmdletBinding()]
param([string]$SetupPath='', [switch]$HostedGuest, [ValidateSet('LOCAL','A','B')][string]$HostLabel='LOCAL')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(!$SetupPath){$SetupPath=Join-Path $PSScriptRoot '_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'}
if($PSVersionTable.PSEdition -cne 'Desktop' -or !(Test-Path $SetupPath -PathType Leaf)){
 throw 'R334_REQUIRES_COMPILED_WINDOWS_DOTNET_FRAMEWORK_SETUP'
}
$setup=(Resolve-Path -LiteralPath $SetupPath).Path
$a=[Reflection.Assembly]::LoadFrom($setup)
$t=$a.GetType('SetupProgram',$true)
$flags=[Reflection.BindingFlags]'Static,NonPublic'
$helper=$t.GetMethod('BuildElevatedSensorProcessInfo',$flags)
$pin=$t.GetMethod('OpenPinnedVerifiedMainForLaunch',$flags)
$mainInfo=$t.GetMethod('BuildPinnedMainProcessInfo',$flags)
$cleanup=$t.GetMethod('BuildDeferredUninstallCleanupProcessInfo',$flags)
$appProp=$t.GetProperty('AppRoot',$flags)
$checks=[Collections.Generic.List[string]]::new()
function Pass([string]$name){$script:checks.Add($name);Write-Output ('PASS '+$name)}
function Invoke-Fn([Reflection.MethodInfo]$method,[object[]]$inputs){
 $native=New-Object 'object[]' $inputs.Count
 for($i=0;$i -lt $inputs.Count;$i++){
  $native[$i]=if($null -eq $inputs[$i]){$null}else{$inputs[$i].PSObject.BaseObject}
 }
 try {return $method.Invoke($null,$native)}
 catch{
  $e=$_.Exception
  while($e.InnerException){$e=$e.InnerException}
  throw $e
 }
}
function Reject([string]$label,[scriptblock]$action,[string]$match){
 $why=''
 try{& $action|Out-Null;throw ('R334_FAIL_OPEN_'+$label)}
 catch{
  $errorObject=$_.Exception
  while($errorObject.InnerException){$errorObject=$errorObject.InnerException}
  $why=$errorObject.Message
 }
 if($why -match '^R334_FAIL_OPEN_' -or $why -notmatch $match){
  throw ('R334_WRONG_REJECTION_'+$label+'='+$why)
 }
 Pass $label
}
function Decode([string]$arguments,[switch]$RequireEncoded){
 $head='-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand '
 if($arguments.Contains(' -File ')){throw 'R334_UNTRUSTED_FILE_SCRIPT_TRANSPORT'}
 if($arguments.StartsWith($head,[StringComparison]::Ordinal)){
  $blob=$arguments.Substring($head.Length)
  if($blob -cnotmatch '^[A-Za-z0-9+/]+={0,2}$'){throw 'R334_UNSAFE_ENCODED_COMMAND_ALPHABET'}
  return [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($blob))
 }
 if($RequireEncoded){throw 'R334_CLEANUP_REQUIRES_ENCODED_COMMAND_NOT_COMMAND_SOURCE'}
 $prefix='-NoProfile -NonInteractive -WindowStyle Hidden -Command "& { '
 $suffix=' }"'
 if(!$arguments.StartsWith($prefix,[StringComparison]::Ordinal) -or
    !$arguments.EndsWith($suffix,[StringComparison]::Ordinal) -or
    $arguments.Length -gt 30000){
  throw 'R334_UNEXPECTED_TRUSTED_INLINE_HELPER_BOOTSTRAP'
 }
 $source=$arguments.Substring($prefix.Length,$arguments.Length-$prefix.Length-$suffix.Length)
 if($source.Contains('"') -or $source.Contains([string][char]0)){
  throw 'R334_INLINE_HELPER_BOOTSTRAP_QUOTE_OR_NULL_IN_SOURCE'
 }
 return $source
}
if(!$helper -or !$pin -or !$mainInfo -or !$cleanup -or !$appProp){throw 'R334_MISSING_SHIPPED_PROCESS_FACTORIES'}
Pass 'EXACT_THREE_PROCESS_STARTINFO_FACTORIES_PRESENT'
$resource=$a.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced_Setup.cs')
if(!$resource){throw 'R334_CANONICAL_SOURCE_RESOURCE_MISSING'}
$reader=[IO.StreamReader]::new($resource)
try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
$source=[IO.File]::ReadAllText((Resolve-Path (Join-Path $PSScriptRoot '..\installer\TaskbarMonitorEnhanced_Setup.cs')).Path)
$norm={param($x) $x.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $norm $embedded) -cne (& $norm $source)){throw 'R334_SHIPPED_PE_NOT_MATCHING_CURRENT_SOURCE'}
Pass 'REAL_PE_EMBEDDED_SOURCE_IDENTICAL'
$system=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
$payload='C:\NOT_REAL & ;\payload'
$app='C:\FAKE & ;\AppData\Local\TaskbarMonitorEnhanced'
$user="R334';Write-Output MARKER_NEVER_EXECUTED;#"
$args=New-Object 'object[]' 4
$args[0]='Install';$args[1]=$payload;$args[2]=$app;$args[3]=$user
$psi=[Diagnostics.ProcessStartInfo](Invoke-Fn $helper $args)
if(!$psi.FileName.Equals($system,[StringComparison]::OrdinalIgnoreCase) -or
   !$psi.WorkingDirectory.Equals([IO.Path]::GetDirectoryName($system),[StringComparison]::OrdinalIgnoreCase)){
 throw 'R334_ELEVATED_POWERSHELL_HOST_NOT_SYSTEM32'
}
Pass 'HELPER_PINNED_SYSTEM32_EXECUTABLE_AND_WORKDIR'
if($psi.UseShellExecute -ne $true -or $psi.Verb -cne 'runas'){throw 'R334_NATIVE_UAC_VERB_MISSING'}
Pass 'HELPER_REQUIRES_NATIVE_RUNAS_WITHOUT_BYPASS'
$text=Decode $psi.Arguments
Pass 'HELPER_COMMAND_IS_BOUNDED_UTF16_ENCODED_OR_TRUSTED_BASE64_INLINE'
foreach($pair in @(@('PAYLOAD',$payload),@('APPROOT',$app),@('IDENTITY',$user))){
 $blob=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$pair[1]))
 if(!$text.Contains("'"+$blob+"'") -or
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($blob)) -cne $pair[1]){
  throw ('R334_HELPER_ARGUMENT_BYTE_ROUNDTRIP_FAILED_'+$pair[0])
 }
 Pass ('HELPER_UTF8_BASE64_DATA_ONLY_'+$pair[0])
}
if($text.Contains('MARKER_NEVER_EXECUTED') -or
   $psi.Arguments.Contains('MARKER_NEVER_EXECUTED') -or
   $text.Contains($user) -or $text.Contains($app) -or $text.Contains($payload)){
 throw 'R334_UNTRUSTED_SYNTAX_ESCAPED_FROM_BASE64_STRING'
}
Pass 'HOSTILE_POWERSHELL_SYNTAX_NOT_INSERTED_IN_SCRIPT_SOURCE'
if(!$text.Contains("-Mode 'Install'") -or
   !$text.Contains('-ExpectedBrokerSHA256') -or
   !$text.Contains('-ExpectedSupervisorSHA256') -or
   !$text.Contains('-ExpectedBackendZipSHA256')){throw 'R334_STATIC_HELPER_MODE_OR_HASH_BINDING_REMOVED'}
Pass 'HELPER_EXACT_MODE_LITERAL_AND_THREE_HASH_PINS'
Reject 'HELPER_REFUSES_NON_ALLOWLISTED_MODE' {
 $values=New-Object 'object[]' 4;$values[0]='Inject';$values[1]=$payload;$values[2]=$app;$values[3]=$user
 [void](Invoke-Fn $helper $values)
} 'Unexpected elevated sensor mode'
Reject 'HELPER_REFUSES_OVERLONG_ARGUMENT' {
 $values=New-Object 'object[]' 4;$values[0]='Install';$values[1]=$payload;$values[2]=$app;$values[3]=('x'*4097)
 [void](Invoke-Fn $helper $values)
} 'missing or too long'
$fallback=$false
foreach($n in @(2500,3500,4050)){
 $values=New-Object 'object[]' 4;$values[0]='Uninstall';$values[1]=$payload;$values[2]=$app;$values[3]=('R334;'+('x'*$n))
 $result=[Diagnostics.ProcessStartInfo](Invoke-Fn $helper $values)
 if($result.Arguments.StartsWith('-NoProfile -NonInteractive -WindowStyle Hidden -Command "',[StringComparison]::Ordinal)){
  $fallback=$true
  if($result.Arguments.Contains('R334;') -or $result.Arguments.Length -gt 30000 -or
     $result.Verb -cne 'runas' -or $result.UseShellExecute -ne $true){
   throw 'R334_LONG_HELPER_COMMAND_EXPOSED_RAW_UNTRUSTED_SOURCE'
  }
  Pass 'LONG_HELPER_COMMAND_FALLBACK_BOUNDED_WITH_ONLY_BASE64_USER_DATA'
  break
 }
}
if(!$fallback){throw 'R334_LONG_HELPER_CANNOT_REACH_TRUSTED_INLINE_FALLBACK'}

$base=Join-Path ([IO.Path]::GetTempPath()) ('tbme_r334_command_'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($base)|Out-Null
$main=Join-Path $base 'TaskbarMonitorEnhanced.exe'
$fh=$null
try{
 $res=$a.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced.exe')
 if(!$res){throw 'R334_EMBEDDED_MAIN_PE_NOT_AVAILABLE'}
 $mem=[IO.MemoryStream]::new()
 try{$res.CopyTo($mem)}finally{$res.Dispose()}
 $bytes=$mem.ToArray();$mem.Dispose()
 [IO.File]::WriteAllBytes($main,$bytes)
 $hash=[Security.Cryptography.SHA256]::Create()
 try{$expected=([BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-','')}
 finally{$hash.Dispose()}
 $values=New-Object 'object[]' 3;$values[0]=$main;$values[1]=$base;$values[2]=$expected
 $fh=[IO.FileStream](Invoke-Fn $pin $values)
 Pass 'MAIN_EXACT_EMBEDDED_SHA_FILESTREAM_READ_PIN'
 $values=New-Object 'object[]' 2;$values[0]=$fh;$values[1]=$base
 $mainPsi=[Diagnostics.ProcessStartInfo](Invoke-Fn $mainInfo $values)
 if(!$mainPsi.FileName.Equals([IO.Path]::GetFullPath($main),[StringComparison]::OrdinalIgnoreCase) -or
    $mainPsi.Arguments -cne '' -or $mainPsi.UseShellExecute -ne $false -or
    $mainPsi.ErrorDialog -ne $false){throw 'R334_SHA_PINNED_MAIN_HAS_COMMAND_OR_SHELL'}
 Pass 'MAIN_SHA_PINNED_EXACT_FILENAME_NO_ARGUMENTS_NO_SHELL'
 Reject 'MAIN_REFUSES_DIFFERENT_INSTALL_ROOT' {
  $v=New-Object 'object[]' 2;$v[0]=$fh;$v[1]=(Join-Path $base 'wrong')
  [void](Invoke-Fn $mainInfo $v)
 } 'escaped|unavailable'
 $fh.Position=0
 $h=[Security.Cryptography.SHA256]::Create()
 try{$actual=([BitConverter]::ToString($h.ComputeHash($fh))).Replace('-','')}
 finally{$h.Dispose()}
 if($actual -cne $expected){throw 'R334_MAIN_FILE_BYTES_CHANGED_WHILE_PINNED'}
 Pass 'MAIN_HANDLE_SHA_MATCHES_IMMUTABLE_SETUP_RESOURCE'
}finally{
 if($fh){$fh.Dispose()}
 if([IO.Directory]::Exists($base) -and
   [IO.Path]::GetFileName($base).StartsWith('tbme_r334_command_',[StringComparison]::Ordinal)){
  [IO.Directory]::Delete($base,$true)
 }
}
$root=[string]$appProp.GetValue($null,$null)
$pidValue=[Diagnostics.Process]::GetCurrentProcess().Id
$ticks=[DateTime]::UtcNow.AddMinutes(-1).Ticks
$v=New-Object 'object[]' 3;$v[0]=$root;$v[1]=$pidValue;$v[2]=$ticks
$cleanPsi=[Diagnostics.ProcessStartInfo](Invoke-Fn $cleanup $v)
if(!$cleanPsi.FileName.Equals($system,[StringComparison]::OrdinalIgnoreCase) -or
   $cleanPsi.UseShellExecute -ne $false -or $cleanPsi.CreateNoWindow -ne $true -or
   !$cleanPsi.WorkingDirectory.Equals([Environment]::SystemDirectory,[StringComparison]::OrdinalIgnoreCase)){
 throw 'R334_CLEANUP_NOT_EXACT_NATIVE_UNELEVATED_POWERSHELL'
}
Pass 'CLEANUP_EXACT_SYSTEM_POWERSHELL_WITHOUT_SHELL'
$decoded=Decode $cleanPsi.Arguments -RequireEncoded
$rootBlob=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($root))
if(!$decoded.Contains("'"+$rootBlob+"'") -or $decoded.Contains($root) -or
   $decoded.Contains('__ROOT_B64__')){throw 'R334_CLEANUP_USER_ROOT_ENTERED_COMMAND_AS_RAW_PATH'}
Pass 'CLEANUP_ROOT_TRANSPORTED_ONLY_AS_UTF8_BASE64_DATA'
if(!$decoded.Contains('TBME_CLEANUP_WRONG_EFFECTIVE_TOKEN') -or
   !$decoded.Contains('TBME_CLEANUP_ROOT_NOT_CANONICAL') -or
   !$decoded.Contains('TBME_CLEANUP_CHILD_REPARSE') -or
   !$decoded.Contains('[IO.Directory]::Delete($dir,$false)')){
 throw 'R334_CLEANUP_OWNER_SID_REPARSE_NONRECURSIVE_GUARDS_MISSING'
}
Pass 'CLEANUP_TOKEN_CANONICAL_ROOT_AND_NONRECURSIVE_GUARDS'
foreach($case in @(
 @('FOREIGN_ROOT',(Join-Path $root 'wrong'),$pidValue,$ticks),
 @('ZERO_PID',$root,0,$ticks),
 @('ZERO_START',$root,$pidValue,0))){
 $item=$case
 Reject ('CLEANUP_REJECTS_'+$item[0]) {
  $v=New-Object 'object[]' 3;$v[0]=[string]$item[1];$v[1]=[int]$item[2];$v[2]=[long]$item[3]
  [void](Invoke-Fn $cleanup $v)
 } 'exact owner root and parent identity'
}
Pass 'ALL_THREE_FACTORIES_INSPECTED_WITHOUT_LAUNCHING_ANY_PROCESS'
if($checks.Count -ne 24){throw ('R334_WRONG_TOTAL_'+$checks.Count)}
Write-Output ('R334_THREE_COMMAND_SINKS_NATIVE='+$checks.Count+'/24 PASS')

if(!$HostedGuest){return}
if($HostLabel -cnotin @('A','B') -or $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_SHA -cnotmatch '^[a-f0-9]{40}$' -or $env:GITHUB_RUN_ID -cnotmatch '^\d+$'){
 throw 'R334_REQUIRE_DISPOSABLE_HOSTED_WINDOWS_GUEST'
}
$folder=Join-Path $env:RUNNER_TEMP ('R334_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
if([IO.Directory]::Exists($folder)){throw 'R334_EXISTING_GUEST_WITNESS_REFUSED'}
[IO.Directory]::CreateDirectory($folder)|Out-Null
$receipt=[ordered]@{
 Schema=1;Revision='R334';Host=$HostLabel;SourceCommit=$env:GITHUB_SHA;
 Status='PASS_THREE_PROCESS_COMMAND_SINK_TRUST_CONTRACTS';
 SetupSHA256=(Get-FileHash $setup -Algorithm SHA256).Hash;
 Checks=@($checks.ToArray());CompiledSetupReflected=$true;
 HelperAndCleanupInputsOnlyInEncodedData=$true;ShaPinnedMainNoShell=$true;
 NativeUacWasNotInvoked=$true;NoCleanupOrMainProcessLaunched=$true;
 WholeSecurityAccepted=$false
}
$p=Join-Path $folder 'R334_COMMAND_SINK_TRUST_RECEIPT.json'
[IO.File]::WriteAllText($p,($receipt|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Write-Output ('R334_HOSTED_GUEST_RECEIPT_SHA256='+(Get-FileHash $p -Algorithm SHA256).Hash)
