[CmdletBinding()]
param([string]$SetupPath='', [switch]$HostedGuest,[ValidateSet('LOCAL','A','B')][string]$HostLabel='LOCAL')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop'){throw 'R335_REQUIRES_NATIVE_WINDOWS_NETFRAMEWORK'}
if([string]::IsNullOrWhiteSpace($SetupPath)) {
 $SetupPath=Join-Path $PSScriptRoot '_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
}
if(!(Test-Path -LiteralPath $SetupPath -PathType Leaf)){throw 'R335_EXACT_COMPILED_SETUP_NOT_PRESENT'}
$setup=(Resolve-Path -LiteralPath $SetupPath).Path
$assembly=[Reflection.Assembly]::LoadFrom($setup)
$resource=$assembly.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
if(!$resource){throw 'R335_PRODUCTION_HELPER_RESOURCE_MISSING'}
$reader=[IO.StreamReader]::new($resource,[Text.Encoding]::UTF8)
try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
$helperPath=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1')).Path
$production=[IO.File]::ReadAllText($helperPath,[Text.Encoding]::UTF8)
$normalize={param($x) $x.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $normalize $production) -cne (& $normalize $embedded)){throw 'R335_COMPILED_PE_HELPER_SOURCE_NOT_EXACT'}
$cls=[regex]::Matches($production,'(?s)Add-Type -TypeDefinition @''\r?\n(.*?)\r?\n''@')
if($cls.Count -ne 1 -or !$cls[0].Groups[1].Value.Contains('public sealed class TBMEScopedUserLogLease : IDisposable')){throw 'R335_REAL_PRODUCTION_HANDLE_CLASS_NOT_UNIQUE'}
Add-Type -TypeDefinition $cls[0].Groups[1].Value -ErrorAction Stop
if($null -eq ('TBMEScopedUserLogLease' -as [type])){throw 'R335_PRODUCTION_HANDLE_CLASS_NOT_LOADED'}
$checks=[Collections.Generic.List[string]]::new()
function Pass([string]$name){$script:checks.Add($name);Write-Output ('PASS '+$name)}
function CanRename([string]$path){
 $to=$path+'_moved'
 try{
  [IO.Directory]::Move($path,$to)
  [IO.Directory]::Move($to,$path)
  return $true
 }catch [IO.IOException]{return $false}
  catch [UnauthorizedAccessException]{return $false}
}
function Attempt-FileRename([string]$file){
 $out=$file+'_renamed'
 try{[IO.File]::Move($file,$out);[IO.File]::Move($out,$file);return $true}
 catch [IO.IOException]{return $false}
 catch [UnauthorizedAccessException]{return $false}
}
function Refuse([string]$name,[scriptblock]$action,[string]$reason){
 $message=''
 try{& $action|Out-Null;throw 'R335_FAIL_OPEN'}
 catch{
  $ex=$_.Exception
  while($ex.InnerException){$ex=$ex.InnerException}
  $message=$ex.Message
 }
 if($message -eq 'R335_FAIL_OPEN' -or $message -notmatch $reason){
  throw ('R335_REFUSAL_WRONG_'+$name+' ERROR='+$message)
 }
 Pass $name
}
Pass 'REAL_COMPILED_SETUP_EMBEDS_EXACT_PRODUCTION_HANDLE_SOURCE'
Pass 'PRODUCTION_LOG_GUARD_CLASS_LOADED_FROM_EMBEDDED_HELPER'
# R335 regression of the full trusted PE-helper transport, not just its C#
# handle type. It must preserve the literal here-string while compacting all
# other safe lines and stay within the Windows ShellExecute command limit.
$builder=$assembly.GetType('SetupProgram',$true).GetMethod(
 'BuildElevatedSensorProcessInfo',[Reflection.BindingFlags]'NonPublic,Static')
if(!$builder){throw 'R335_EXACT_ELEVATED_PROCESS_BUILDER_NOT_PRESENT'}
$args=New-Object 'object[]' 4
$args[0]='Install'
$args[1]='C:\R335_TEST_ONLY\payload & literal'
$args[2]='C:\R335_TEST_ONLY\AppData\Local\TaskbarMonitorEnhanced'
$args[3]='R335\USER_TEST_ONLY'
$psi=[Diagnostics.ProcessStartInfo]$builder.Invoke($null,$args)
$system=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
if(!$psi.FileName.Equals($system,[StringComparison]::OrdinalIgnoreCase) -or
   $psi.Verb -cne 'runas' -or $psi.UseShellExecute -ne $true){
 throw 'R335_HELPER_PROCESS_UAC_AND_SYSTEM_EXE_NO_LONGER_PINNED'
}
Pass 'BUILD_ELEVATED_HELPER_PRESERVES_SYSTEM32_RUNAS_NO_LAUNCH'
$argline=$psi.Arguments
$inline='-NoProfile -NonInteractive -WindowStyle Hidden -Command "& { '
$tail=' }"'
$encoded='-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand '
if($argline.StartsWith($encoded,[StringComparison]::Ordinal)){
 $bootstrap=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($argline.Substring($encoded.Length)))
}elseif($argline.StartsWith($inline,[StringComparison]::Ordinal) -and
       $argline.EndsWith($tail,[StringComparison]::Ordinal) -and
       $argline.Length -le 30000){
 $bootstrap=$argline.Substring($inline.Length,$argline.Length-$inline.Length-$tail.Length)
}else{throw 'R335_TRANSPORT_NOT_BOUNDED_INLINE_OR_UTF16_ENCODED'}
if($bootstrap.Contains('R335_TEST_ONLY') -or $argline.Contains('R335_TEST_ONLY')){
 throw 'R335_UNTRUSTED_PATH_REACHED_COMMAND_TEXT_OUTSIDE_BASE64'
}
Pass 'TRUSTED_HELPER_BOOTSTRAP_BOUNDED_AND_UNTRUSTED_PATHS_ENCODED'
$parts=[regex]::Matches($bootstrap,'\$blob=\[Convert\]::FromBase64String\(''([A-Za-z0-9+/=]+)''\)')
if($parts.Count -ne 1){throw 'R335_TRANSPORT_COMPRESSED_PE_HELPER_SOURCE_MISSING'}
$packed=[Convert]::FromBase64String($parts[0].Groups[1].Value)
$stream=[IO.MemoryStream]::new($packed)
$gzip=[IO.Compression.GZipStream]::new($stream,[IO.Compression.CompressionMode]::Decompress)
$textReader=[IO.StreamReader]::new($gzip,[Text.Encoding]::UTF8)
try{$trusted=$textReader.ReadToEnd()}
finally{$textReader.Dispose();$gzip.Dispose();$stream.Dispose()}
$tok=$null;$parseErr=$null
[Management.Automation.Language.Parser]::ParseInput($trusted,[ref]$tok,[ref]$parseErr)|Out-Null
if(@($parseErr).Count -ne 0){throw ('R335_TRANSPORTED_PE_HELPER_POWERSHELL_PARSE_ERRORS_'+@($parseErr).Count)}
Pass 'COMPRESSED_TRUSTED_HELPER_FULL_SCRIPT_PS51_PARSE_PASS'
$literal=$cls[0].Value.Replace(([string][char]13+[string][char]10),[string][char]10)
if(!$trusted.Contains($literal) -or
   !$trusted.Contains('public sealed class TBMEScopedUserLogLease : IDisposable')){
 throw 'R335_TRUSTED_CSHARP_HERE_LITERAL_WAS_COMPACTED_OR_CORRUPTED'
}
Pass 'TRUSTED_NATIVE_CSHARP_HERE_LITERAL_PRESERVED_BYTE_IDENTICAL'
$base=Join-Path ([IO.Path]::GetTempPath()) ('tbme_r335_loglease_'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($base)|Out-Null
$profile=Join-Path $base 'profile & literal dollar'
$local=Join-Path $profile 'AppData\Local'
$app=Join-Path $local 'TaskbarMonitorEnhanced'
$logs=Join-Path $app 'Logs'
$file=Join-Path $logs 'sensor_install.log'
$external=Join-Path $base 'foreign-outside'
[IO.Directory]::CreateDirectory($logs)|Out-Null
[IO.Directory]::CreateDirectory($external)|Out-Null
$canary=Join-Path $external 'NO_WRITE.txt'
[IO.File]::WriteAllText($canary,'R335_FOREIGN_CANARY')
[IO.File]::WriteAllText($file,'PREEXISTING_LOG')
$lease=$null
try{
 if(!(CanRename $logs) -or !(CanRename $app) -or !(Attempt-FileRename $file)){
  throw 'R335_SANDBOX_BASELINE_RENAME_EXPECTED_PERMITTED'
 }
 Pass 'BASELINE_UNGUARDED_DIR_AND_LEAF_RENAME_ALLOWED'
 $lease=[TBMEScopedUserLogLease]::new($profile,$app,$logs,$file)
 Pass 'OPENED_ALL_FIVE_NO_REPARSE_COMPONENT_HANDLES_AND_EXACT_FILE'
 if(CanRename $logs){throw 'R335_LOGS_RENAME_ALLOWED_WHILE_PINNED'}
 Pass 'GUARD_BLOCKS_LOGS_FOLDER_RENAME'
 if(CanRename $app){throw 'R335_APPROOT_RENAME_ALLOWED_WHILE_PINNED'}
 Pass 'GUARD_BLOCKS_APPROOT_FOLDER_RENAME'
 if(CanRename $local){throw 'R335_LOCAL_PARENT_RENAME_ALLOWED_WHILE_PINNED'}
 Pass 'GUARD_BLOCKS_LOCAL_PARENT_RENAME'
 if(Attempt-FileRename $file){throw 'R335_LEAF_RENAME_ALLOWED_WHILE_PINNED'}
 Pass 'GUARD_BLOCKS_EXACT_LOG_FILE_RENAME'
 $lease.Append('R335_APPEND_IS_CANARY_ONLY')
 # The FileStream holding WRITE access intentionally denies external reads
 # when their share mode denies writes. Inspect the bytes after lease disposal.
 $win=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $child='param([string]$p);try{[IO.Directory]::Move($p,($p+''_actor''));[IO.Directory]::Move(($p+''_actor''),$p);exit 61}catch [IO.IOException]{exit 0}catch [UnauthorizedAccessException]{exit 0}'
 $actor=Join-Path $base 'sandbox-actor.ps1'
 [IO.File]::WriteAllText($actor,$child,[Text.UTF8Encoding]::new($false))
 & $win -NoProfile -NonInteractive -File $actor -p $logs
 if($LASTEXITCODE -ne 0){throw ('R335_SEPARATE_PROCESS_RENAME_NOT_DENIED_'+$LASTEXITCODE)}
 Pass 'SEPARATE_UNELEVATED_PROCESS_RENAME_BLOCKED_DURING_GUARD'
 $lease.Dispose();$lease=$null
 if(![IO.File]::ReadAllText($file).Contains('R335_APPEND_IS_CANARY_ONLY')){
  throw 'R335_GUARDED_LOG_WRITE_NOT_PERSISTED'
 }
 Pass 'EXACT_PINNED_FILESTREAM_WRITE_SUCCEEDED'
 if(!(CanRename $logs) -or !(CanRename $app) -or !(Attempt-FileRename $file)){
  throw 'R335_FOLDER_OR_FILE_RENAME_STILL_BLOCKED_AFTER_DISPOSAL'
 }
 Pass 'RENAMES_REENABLED_AFTER_ALL_HANDLES_CLOSED'
 $retired=$logs+'_clean'
 [IO.Directory]::Move($logs,$retired)
 $link=$false
 try{
  New-Item -ItemType Junction -Path $logs -Target $external -ErrorAction Stop|Out-Null
  $link=$true
  Refuse 'LOGS_JUNCTION_REJECTED_BEFORE_OPEN_FILE' {[TBMEScopedUserLogLease]::new($profile,$app,$logs,$file)} 'SENSOR_LOG_HANDLE_REPARSE_OR_COMPONENT_TYPE_REFUSED'
 }finally{
  if($link -and [IO.Directory]::Exists($logs)){[IO.Directory]::Delete($logs)}
  [IO.Directory]::Move($retired,$logs)
 }
 [IO.File]::Delete($file)
 $link=$false
 try{
  New-Item -ItemType Junction -Path $file -Target $external -ErrorAction Stop|Out-Null
  $link=$true
  Refuse 'LOG_FILE_REPARSE_LINK_REJECTED_BEFORE_WRITE' {[TBMEScopedUserLogLease]::new($profile,$app,$logs,$file)} 'SENSOR_LOG_HANDLE_REPARSE_OR_COMPONENT_TYPE_REFUSED|SENSOR_LOG_HANDLE_CREATEFILE_FAILED_WIN32_5'
 }finally{
  if($link -and [IO.Directory]::Exists($file)){[IO.Directory]::Delete($file)}
  [IO.File]::WriteAllText($file,'RESTORED_LOG')
 }
 Refuse 'FOREIGN_APP_ROOT_LEXICALLY_REFUSED' {[TBMEScopedUserLogLease]::new($profile,$external,$logs,$file)} 'SENSOR_LOG_HANDLE_CANONICAL_LOG_PATH_MISMATCH'
 if([IO.File]::ReadAllText($canary) -cne 'R335_FOREIGN_CANARY'){
  throw 'R335_OUTSIDE_CANARY_MODIFIED'
 }
 Pass 'OUTSIDE_FOREIGN_CANARY_UNMODIFIED'
 $resultFile=Join-Path $logs 'sensor_install_result.json'
 $resultLease=[TBMEScopedUserLogLease]::new($profile,$app,$logs,$resultFile)
 try{$resultLease.Overwrite('{"Status":"R335_OK","SensorHealthy":false}'+[Environment]::NewLine)}
 finally{$resultLease.Dispose()}
 $result=Get-Content -LiteralPath $resultFile -Raw|ConvertFrom-Json
 if($result.Status -cne 'R335_OK' -or $result.SensorHealthy -ne $false){
  throw 'R335_UTF8_BOM_RESULT_JSON_NOT_VALID'
 }
 Pass 'GUARDED_RESULT_JSON_UTF8_BOM_AND_SCHEMA_VALID'
 $resultLease=[TBMEScopedUserLogLease]::new($profile,$app,$logs,$resultFile)
 try{$resultLease.Overwrite('{"Status":"R335_FINAL"}'+[Environment]::NewLine)}
 finally{$resultLease.Dispose()}
 $bytes=[IO.File]::ReadAllBytes($resultFile)
 $text=[Text.Encoding]::UTF8.GetString($bytes)
 if($text.Contains('R335_OK') -or !$text.Contains('R335_FINAL') -or
    $bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191){
  throw 'R335_BOM_RESULT_OVERWRITE_LEAKED_PREVIOUS_JSON'
 }
 Pass 'GUARDED_RESULT_OVERWRITE_TRUNCATES_AND_RETAINS_UTF8_BOM'
 [IO.File]::Delete($resultFile)
 $linked=$false
 try{
  New-Item -ItemType Junction -Path $resultFile -Target $external -ErrorAction Stop|Out-Null
  $linked=$true
  Refuse 'RESULT_JSON_REPARSE_LEAF_REFUSED' {[TBMEScopedUserLogLease]::new($profile,$app,$logs,$resultFile)} 'SENSOR_LOG_HANDLE_REPARSE_OR_COMPONENT_TYPE_REFUSED|SENSOR_LOG_HANDLE_CREATEFILE_FAILED_WIN32_5'
 }finally{
  if($linked -and [IO.Directory]::Exists($resultFile)){[IO.Directory]::Delete($resultFile)}
 }
 if([IO.File]::ReadAllText($canary) -cne 'R335_FOREIGN_CANARY'){
  throw 'R335_RESULT_REPARSE_WROTE_OUTSIDE_CANARY'
 }
 Pass 'RESULT_JSON_REPARSE_EXTERNAL_CANARY_INTACT'
 if($checks.Count -ne 23){throw ('R335_EXPECTED_19_CHECKS_ACTUAL_'+$checks.Count)}
 Write-Output ('R335_DISPOSABLE_USER_LOG_HANDLE_PROBE=23/23_PASS')
 if($HostedGuest){
  if($HostLabel -cnotin @('A','B') -or $env:GITHUB_ACTIONS -cne 'true' -or
     $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or $env:RUNNER_OS -cne 'Windows' -or
     $env:GITHUB_SHA -cnotmatch '^[0-9a-f]{40}$' -or $env:GITHUB_RUN_ID -cnotmatch '^\d+$'){
   throw 'R335_TEST_REQUIRES_DISPOSABLE_GITHUB_WINDOWS'
  }
  $dir=Join-Path $env:RUNNER_TEMP ('R335_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
  if(Test-Path $dir){throw 'R335_GUEST_RAW_RECEIPT_EXISTS'}
  [IO.Directory]::CreateDirectory($dir)|Out-Null
  $j=[ordered]@{Schema=1;Revision='R335';Host=$HostLabel;SourceCommit=$env:GITHUB_SHA;
   Status='PASS_SCOPED_NONDELETE_HANDLE_LOGS_APPROOT_AND_FILE';
   Checks=@($checks.ToArray());RealElevatedHelperLaunched=$false;
   ActualProgramFilesModified=$false;AtomicCrossUserUacProven=$false;
   ForeignCanaryPreserved=$true;SecurityFinalAccepted=$false}
  $receipt=Join-Path $dir 'R335_ATOMIC_LOG_HANDLE_PROBE.json'
  [IO.File]::WriteAllText($receipt,($j|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
  Write-Output ('R335_HOSTED_RAW_RECEIPT_SHA256='+(Get-FileHash $receipt -Algorithm SHA256).Hash)
 }
}finally{
 if($lease){$lease.Dispose()}
 if([IO.Directory]::Exists($base) -and [IO.Path]::GetFileName($base).StartsWith('tbme_r335_loglease_',[StringComparison]::Ordinal)){
  $links=@(Get-ChildItem -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue|
   Where-Object {($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0})
  if($links.Count -ne 0){throw 'R335_SANDBOX_REPARSE_REFUSE_CLEANUP'}
  [IO.Directory]::Delete($base,$true)
 }
}
