[CmdletBinding()]
param([string]$SetupPath='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($SetupPath)){
 $SetupPath=Join-Path $PSScriptRoot '_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   !(Test-Path -LiteralPath $SetupPath -PathType Leaf)){
 throw 'R326_REAL_COMPILED_DOTNET_FRAMEWORK_SETUP_REQUIRED'
}
$setup=[Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $SetupPath).Path)
$type=$setup.GetType('SetupProgram',$true)
$pinMethod=$type.GetMethod('OpenPinnedVerifiedMainForLaunch',[Reflection.BindingFlags]'NonPublic,Static')
$startMethod=$type.GetMethod('BuildPinnedMainProcessInfo',[Reflection.BindingFlags]'NonPublic,Static')
if($null -eq $pinMethod -or $null -eq $startMethod){
 throw 'R326_DIRECT_MAIN_METHODS_MISSING_IN_REAL_PE'
}
$srcResource=$setup.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced_Setup.cs')
if($null -eq $srcResource){throw 'R326_CANONICAL_SOURCE_EMBEDDED_RESOURCE_MISSING'}
$reader=[IO.StreamReader]::new($srcResource)
try{$embeddedSource=$reader.ReadToEnd()}finally{$reader.Dispose()}
$source=[IO.File]::ReadAllText((Resolve-Path (Join-Path $PSScriptRoot '..\installer\TaskbarMonitorEnhanced_Setup.cs')))
$normalize={param($x) $x.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $normalize $source) -cne (& $normalize $embeddedSource)){
 throw 'R326_CANONICAL_SOURCE_NOT_EQUAL_PE_EMBED'
}
$checks=[Collections.Generic.List[string]]::new()
$checks.Add('EXACT_PE_SETUP_EMBEDS_CURRENT_SOURCE')
$posPin=$source.IndexOf('using(FileStream pinned=OpenPinnedVerifiedMainForLaunch(',[StringComparison]::Ordinal)
$posStartInfo=$source.IndexOf('BuildPinnedMainProcessInfo(pinned,AppRoot)',[StringComparison]::Ordinal)
$posStart=$source.IndexOf('Process.Start(direct)',[StringComparison]::Ordinal)
$posSuccess=$source.IndexOf('MainLaunchMode="LAUNCHED_NON_ELEVATED_SETUP"',[StringComparison]::Ordinal)
if($posPin -lt 0 -or $posStartInfo -le $posPin -or $posStart -le $posStartInfo -or $posSuccess -le $posStart -or
   $source.Contains('Process.Start(AppExe)')){
 throw 'R326_SHA_PIN_DIRECT_CREATEPROCESS_ORDER_INVALID'
}
$checks.Add('SHA_PINNED_MAIN_HANDLE_HELD_ACROSS_DIRECT_PROCESS_START')
$resource=$setup.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced.exe')
if(!$resource){throw 'R326_EMBEDDED_MAIN_NOT_FOUND'}
$memory=[IO.MemoryStream]::new()
try{$resource.CopyTo($memory)}finally{$resource.Dispose()}
$mainBytes=$memory.ToArray()
$memory.Dispose()
$sha=[Security.Cryptography.SHA256]::Create()
try{$expected=([BitConverter]::ToString($sha.ComputeHash($mainBytes))).Replace('-','')}
finally{$sha.Dispose()}
if($mainBytes.Length -lt 1024 -or $expected.Length -ne 64){throw 'R326_MAIN_RESOURCE_INVALID'}
$checks.Add('EMBEDDED_MAIN_EXPECTED_SHA_IS_FULL_HEX')

$dir=Join-Path ([IO.Path]::GetTempPath()) ('tbme_r326_direct_main_'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($dir)|Out-Null
$root=Join-Path $dir 'literal & dollar $name with spaces'
[IO.Directory]::CreateDirectory($root)|Out-Null
$file=Join-Path $root 'TaskbarMonitorEnhanced.exe'
[IO.File]::WriteAllBytes($file,$mainBytes)
$pin=$null
function Invoke-Builder([object]$handle,[string]$expectedRoot){
 $args=New-Object 'object[]' 2
 $args[0]=$handle
 $args[1]=$expectedRoot
 return $startMethod.Invoke($null,$args)
}
function Expect-Refusal([string]$label,[object]$handle,[string]$expectedRoot,[string]$message){
 $refused=$false
 try{
  $value=Invoke-Builder $handle $expectedRoot
  if($null -ne $value){throw ('R326_BAD_BUILDER_ACCEPTED_'+$label)}
 }catch{
  $failure=$_.Exception
  while($null -ne $failure.InnerException){$failure=$failure.InnerException}
  if($failure.Message -match $message){$refused=$true}
  else{throw}
 }
 if(!$refused){throw ('R326_NEGATIVE_WAS_NOT_REFUSED_'+$label)}
 $script:checks.Add($label)
}
try{
 $args=New-Object 'object[]' 3
 $args[0]=[string]$file;$args[1]=[string]$root;$args[2]=[string]$expected
 $pin=[IO.FileStream]$pinMethod.Invoke($null,$args)
 if($null -eq $pin -or !$pin.CanRead -or
    ![string]::Equals([IO.Path]::GetFullPath($pin.Name),[IO.Path]::GetFullPath($file),[StringComparison]::OrdinalIgnoreCase)){
  throw 'R326_EXACT_SHA_FILESTREAM_NOT_PINNED'
 }
 $checks.Add('READ_ONLY_EXACT_SHA_MAIN_HANDLE_PINNED')
 $built=Invoke-Builder $pin $root
 if($built.UseShellExecute -ne $false){throw 'R326_SHELLEXECUTE_NOT_DISABLED'}
 $checks.Add('REAL_PROCESSSTARTINFO_USE_SHELL_EXECUTE_FALSE')
 if($built.FileName -cne [IO.Path]::GetFullPath($file)){
  throw 'R326_DIRECT_EXECUTABLE_NOT_EXACT_FILESTREAM_PATH'
 }
 $checks.Add('REAL_PROCESSSTARTINFO_EXE_EXACT_PINNED_FILE')
 if($built.Arguments -cne ''){throw 'R326_MAIN_RECEIVES_UNTRUSTED_ARGS'}
 $checks.Add('REAL_PROCESSSTARTINFO_ARGUMENTS_EMPTY')
 if($built.Verb -cne '' -or $built.ErrorDialog -ne $false){
  throw 'R326_SHELL_VERB_OR_ERROR_DIALOG_PRESENT'
 }
 $checks.Add('REAL_PROCESSSTARTINFO_HAS_NO_SHELL_VERB')
 if($built.WorkingDirectory -cne ''){
  throw 'R326_WORKDIR_SHOULD_NOT_CONSUME_UNTRUSTED_PROFILE_PATH'
 }
 $checks.Add('REAL_PROCESSSTARTINFO_INHERITS_PREVIOUS_CWD')
 if(!$built.FileName.Contains('&') -or !$built.FileName.Contains('$name')){
  throw 'R326_META_CHARACTERS_LOST_OR_INTERPRETED'
 }
 $checks.Add('METACHARACTER_PATH_PRESERVED_AS_LITERAL_WITHOUT_SHELL')
 $writeBlocked=$false
 try{$writer=[IO.FileStream]::new($file,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$writer.Dispose()}
 catch [IO.IOException]{$writeBlocked=$true}
 if(!$writeBlocked){throw 'R326_PINNED_HANDLE_DID_NOT_DENY_WRITER'}
 $checks.Add('WRITE_DENIED_WHILE_STARTINFO_PREPARED')
 Expect-Refusal 'FOREIGN_INSTALLATION_ROOT_REFUSED' $pin (Join-Path $dir 'foreign') 'escaped'
 Expect-Refusal 'RELATIVE_INSTALLATION_ROOT_REFUSED' $pin 'relative' 'unavailable'
 Expect-Refusal 'NULL_MAIN_HANDLE_REFUSED' $null $root 'unavailable'
 $pin.Dispose();$pin=$null
 $closed=[IO.FileStream]::new($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 $closed.Dispose()
 Expect-Refusal 'DISPOSED_MAIN_HANDLE_REFUSED' $closed $root 'unavailable'
 if($checks.Count -ne 15){throw ('R326_TEST_COUNT_MISMATCH_'+$checks.Count)}
 Write-Output ('R326_DIRECT_MAIN_WINDOWS_NET48_PASS='+$checks.Count+'/15')
 foreach($item in $checks){Write-Output ('PASS '+$item)}
}finally{
 if($pin){$pin.Dispose()}
 if([IO.Directory]::Exists($dir) -and [IO.Path]::GetFileName($dir).StartsWith('tbme_r326_direct_main_',[StringComparison]::Ordinal)){
  [IO.Directory]::Delete($dir,$true)
 }
}
