[CmdletBinding()]
param(
 [string]$SetupPath='',
 [switch]$HostedGuest,
 [ValidateSet('LOCAL','A','B')][string]$HostLabel='LOCAL'
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($SetupPath)){
 $SetupPath=Join-Path $PSScriptRoot '_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   !(Test-Path -LiteralPath $SetupPath -PathType Leaf)){throw 'R333_COMPILED_DOTNET_FRAMEWORK_SETUP_REQUIRED'}
$setup=(Resolve-Path -LiteralPath $SetupPath).Path
$assembly=[Reflection.Assembly]::LoadFrom($setup)
$type=$assembly.GetType('SetupProgram',$true)
$flags=[Reflection.BindingFlags]'Static,NonPublic'
$occupied=$type.GetMethod('ShortcutNameOccupied',$flags)
$fresh=$type.GetMethod('AssertFreshShortcutNameUnused',$flags)
$foreign=$type.GetMethod('AssertOwnedOrAbsentShortcut',$flags)
if(!$occupied -or !$fresh -or !$foreign){throw 'R333_REAL_SETUP_MISSING_SHORTCUT_PRECHECKS'}
$checks=[Collections.Generic.List[string]]::new()
function Pass([string]$name){
 $script:checks.Add($name)
 Write-Output ('PASS '+$name)
}
function Occupied([string]$path){
 $args=New-Object 'object[]' 1
 $args[0]=[string]$path
 return [bool]$occupied.Invoke($null,$args)
}
function Fresh([string]$path){
 $args=New-Object 'object[]' 1
 $args[0]=[string]$path
 [void]$fresh.Invoke($null,$args)
}
function Foreign([string]$path,[string]$target,[string]$arguments){
 $args=New-Object 'object[]' 3
 $args[0]=[string]$path;$args[1]=[string]$target;$args[2]=[string]$arguments
 [void]$foreign.Invoke($null,$args)
}
function Expect-Throw([string]$label,[scriptblock]$action,[string]$pattern){
 $message=''
 try {
  & $action |Out-Null
  throw ('R333_FAIL_OPEN_'+$label)
 }catch {
  $e=$_.Exception
  while($null -ne $e.InnerException){$e=$e.InnerException}
  $message=$e.Message
 }
 if($message -match '^R333_FAIL_OPEN_' -or $message -notmatch $pattern){
  throw ('R333_NEGATIVE_NOT_PROVEN_'+$label+' ACTUAL='+$message)
 }
 Pass $label
}
$resource=$assembly.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced_Setup.cs')
if(!$resource){throw 'R333_EMBEDDED_SOURCE_MISSING'}
$reader=[IO.StreamReader]::new($resource,[Text.Encoding]::UTF8)
try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
$source=[IO.File]::ReadAllText((Resolve-Path (Join-Path $PSScriptRoot '..\installer\TaskbarMonitorEnhanced_Setup.cs')).Path)
$norm={param($s) $s.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $norm $source) -cne (& $norm $embedded)){throw 'R333_BUILT_SETUP_EMBEDDED_SOURCE_NOT_EXACT'}
Pass 'SETUP_EXACT_EMBEDDED_SOURCE_IDENTITY'
if($occupied.ReturnType -ne [bool]){throw 'R333_PRIVATE_OCCUPIED_RETURN_TYPE_CHANGED'}
Pass 'OCCUPANCY_SIGNATURE_BOOL_PRESERVED'

$base=Join-Path ([IO.Path]::GetTempPath()) ('tbme_r333_occupied_'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($base)|Out-Null
$root=Join-Path $base 'start menu & literal $USER'
[IO.Directory]::CreateDirectory($root)|Out-Null
$external=Join-Path $base 'foreign-canary-directory'
[IO.Directory]::CreateDirectory($external)|Out-Null
$canary=Join-Path $external 'NEVER_CHANGE.txt'
[IO.File]::WriteAllText($canary,'R333_OUTSIDE_UNTOUCHED')
$link=$null;$retired=$null
try {
 $missing=Join-Path $root 'absent.lnk'
 if(Occupied $missing){throw 'R333_ABSENT_NAME_OCCUPIED'}
 Pass 'EXACT_ABSENT_SHORTCUT_NAME_FALSE'
 Fresh $missing
 Pass 'FRESH_ABSENT_SHORTCUT_ALLOWED'

 $other=Join-Path $root 'other.lnk'
 [IO.File]::WriteAllText($other,'R333_OTHER_LEAF_UNTOUCHED')
 if(Occupied $missing){throw 'R333_OTHER_NAME_MATCHED_WRONGLY'}
 Pass 'EXACT_LEAF_FILTER_IGNORES_NEIGHBOR'

 $foreignFile=Join-Path $root 'foreign.lnk'
 [IO.File]::WriteAllText($foreignFile,'R333_OWNED_BY_OTHER_APP')
 $fhash=(Get-FileHash $foreignFile -Algorithm SHA256).Hash
 if(!(Occupied $foreignFile)){throw 'R333_FOREIGN_REGULAR_FILE_NOT_OCCUPIED'}
 Pass 'REGULAR_FOREIGN_LINK_NAME_OCCUPIED'
 if(!(Occupied (Join-Path $root 'FOREIGN.LNK'))){throw 'R333_CASE_INSENSITIVE_LEAF_NOT_MATCHED'}
 Pass 'CASE_INSENSITIVE_LITERAL_LEAF_MATCH'
 Expect-Throw 'FRESH_REFUSES_FOREIGN_REGULAR_FILE' {Fresh $foreignFile} 'FOREIGN_SHORTCUT_NAME_CONFLICT'
 if((Get-FileHash $foreignFile -Algorithm SHA256).Hash -ne $fhash){throw 'R333_FOREIGN_FILE_BYTES_MUTATED'}
 Pass 'FOREIGN_FILE_BYTES_PRESERVED'
 Expect-Throw 'UNOWNED_SHORTCUT_REFUSES_FOREIGN_FILE' {
  Foreign $foreignFile (Join-Path $base 'legitimate-main.exe') ''
 } 'FOREIGN_SHORTCUT_NAME_CONFLICT'

 $directoryEntry=Join-Path $root 'subdir.lnk'
 [IO.Directory]::CreateDirectory($directoryEntry)|Out-Null
 if(!(Occupied $directoryEntry)){throw 'R333_DIRECTORY_WITH_LNK_NAME_NOT_OCCUPIED'}
 Pass 'DIRECTORY_WITH_LNK_NAME_OCCUPIED'
 Expect-Throw 'FRESH_REFUSES_DIRECTORY_LNK_NAME' {Fresh $directoryEntry} 'FOREIGN_SHORTCUT_NAME_CONFLICT'

 $link=Join-Path $root 'linked.lnk'
 New-Item -ItemType Junction -Path $link -Target $external -ErrorAction Stop|Out-Null
 if(!(Occupied $link)){throw 'R333_JUNCTION_ENTRY_NOT_OCCUPIED'}
 Pass 'DIRECTORY_JUNCTION_LNK_OCCUPIES_NAME'
 Expect-Throw 'FRESH_REFUSES_JUNCTION_LNK' {Fresh $link} 'FOREIGN_SHORTCUT_NAME_CONFLICT'
 $retired=$external+'_temporarily_unavailable'
 [IO.Directory]::Move($external,$retired)
 if(!(Occupied $link)){throw 'R333_DANGLING_JUNCTION_FALSELY_ABSENT'}
 Pass 'DANGLING_REPARSE_LINK_OCCUPIES_NAME'
 Expect-Throw 'FRESH_REFUSES_DANGLING_REPARSE' {Fresh $link} 'FOREIGN_SHORTCUT_NAME_CONFLICT'
 [IO.Directory]::Move($retired,$external)
 $retired=$null
 [IO.Directory]::Delete($link)
 $link=$null
 if([IO.File]::ReadAllText($canary) -cne 'R333_OUTSIDE_UNTOUCHED'){
  throw 'R333_EXTERNAL_CANARY_ALTERED'
 }
 Pass 'FOREIGN_TARGET_CANARY_PRESERVED'

 if(Occupied (Join-Path $base 'missing-parent\not-here.lnk')){
  throw 'R333_ABSENT_PARENT_FALSELY_OCCUPIED'
 }
 Pass 'NONEXISTENT_PARENT_RETURNS_ABSENT'
 Expect-Throw 'RELATIVE_SHORTCUT_PATH_REFUSED' {Occupied 'relative.lnk'} 'absolute'
 Expect-Throw 'NONLNK_EXTENSION_REFUSED' {Occupied (Join-Path $root 'bad.txt')} 'literal .lnk'
 Expect-Throw 'WILDCARD_FILENAME_REFUSED' {Occupied (Join-Path $root 'bad*.lnk')} '(?i)literal .lnk|Illegal characters'

 if($source.Contains('try{File.GetAttributes(path);return true;}') -or
    !$source.Contains('new DirectoryInfo(parent).GetFileSystemInfos(leaf)')){
  throw 'R333_SHIPPED_OCCUPANCY_STILL_HAS_OLD_SINK'
 }
 Pass 'SHIPPED_OCCUPANCY_ENUMERATES_EXACT_PARENT_LEAF'
 if($checks.Count -ne 22){throw ('R333_NATIVE_CHECK_COUNT_EXPECTED_19_GOT_'+$checks.Count)}
 Write-Output ('R333_NATIVE_SHORTCUT_EXACT_LEAF_OCCUPANCY_PASS='+$checks.Count+'/22')

 if(!$HostedGuest){return}
 if($HostLabel -cnotin @('A','B') -or
    $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
    $env:RUNNER_OS -cne 'Windows' -or $env:GITHUB_SHA -cnotmatch '^[0-9a-f]{40}$' -or
    $env:GITHUB_RUN_ID -cnotmatch '^\d+$'){
  throw 'R333_GUEST_MUST_BE_DISPOSABLE_GITHUB_WINDOWS'
 }
 $receiptDir=Join-Path $env:RUNNER_TEMP ('R333_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
 if([IO.Directory]::Exists($receiptDir)){throw 'R333_HOSTED_GUEST_PROOF_EXISTS'}
 [IO.Directory]::CreateDirectory($receiptDir)|Out-Null
 $proof=[ordered]@{
  Schema=1
  Revision='R333'
  Status='PASS_EXACT_SHORTCUT_OCCUPANCY_INCLUDING_DANGLING_REPARSE'
  Host=$HostLabel
  SourceCommit=$env:GITHUB_SHA
  SetupSHA256=(Get-FileHash $setup -Algorithm SHA256).Hash
  Checks=@($checks.ToArray())
  RealCompiledSetupLoaded=$true
  RealMainLaunched=$false
  ForeignCanaryPreserved=$true
  ActualUacInvoked=$false
  OriginalOwnerHostTouched=$false
  AtomicPathRaceProven=$false
  SecurityFinalAccepted=$false
 }
 $receipt=Join-Path $receiptDir 'R333_SHORTCUT_OCCUPANCY_RECEIPT.json'
 [IO.File]::WriteAllText($receipt,($proof|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
 Write-Output ('R333_HOSTED_GUEST_RECEIPT_SHA256='+(Get-FileHash $receipt -Algorithm SHA256).Hash)
}finally{
 if($link -and [IO.Directory]::Exists($link)){
  [IO.Directory]::Delete($link)
 }
 if($retired -and [IO.Directory]::Exists($retired)){
  [IO.Directory]::Move($retired,$external)
 }
 if([IO.Directory]::Exists($base) -and
    [IO.Path]::GetFileName($base).StartsWith('tbme_r333_occupied_',[StringComparison]::Ordinal)){
  $reparse=@(Get-ChildItem -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue|
          Where-Object {($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0})
  if($reparse.Count){throw 'R333_UNEXPECTED_REPARSE_REFUSE_TEST_SANDBOX_CLEANUP'}
  [IO.Directory]::Delete($base,$true)
 }
}
