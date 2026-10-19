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
 throw 'R317_DISPOSABLE_WINDOWS_ONLY'
}
function Hash([string]$p){
 if(-not [IO.File]::Exists($p)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
}
$run=Join-Path $env:RUNNER_TEMP ('R317_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $run 'R317_ENCODED_CLEANUP_RECEIPT.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$prior=Join-Path $env:RUNNER_TEMP ('R316_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R316_TRUSTED_APPROOT_RECEIPT.json')
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$config=Join-Path $app 'config.json'
$state=Join-Path $app 'install_state.json'
$checks=[Collections.Generic.List[string]]::new()
if([IO.Directory]::Exists($run)){throw 'R317_TEST_ROOT_PREEXISTS'}
[void][IO.Directory]::CreateDirectory($run)
$old=@{Main=(Hash $main);Config=(Hash $config);State=(Hash $state)}
$c=Get-Content $manifest -Raw|ConvertFrom-Json
$p=Get-Content $prior -Raw|ConvertFrom-Json
if($c.Commit -cne $env:GITHUB_SHA -or
   $c.SetupSHA256 -cne (Hash $setup) -or
   $c.MainSHA256 -cne $old.Main -or
   $p.SourceCommit -cne $env:GITHUB_SHA -or
   $p.Host -cne $HostLabel -or
   $p.Status -cne 'PASS_OS_KNOWNFOLDER_CANONICAL_APPROOT_AND_REPARSE_REFUSAL'){
 throw 'R317_EXACT_PRIVATE_PE_OR_R316_PREDECESSOR_MISMATCH'
}
$assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
$sourceStream=$assembly.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced_Setup.cs')
if(!$sourceStream){throw 'R317_SETUP_SOURCE_NOT_EMBEDDED'}
$reader=[IO.StreamReader]::new($sourceStream)
try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
$source=(Resolve-Path (Join-Path $PSScriptRoot '..\installer\TaskbarMonitorEnhanced_Setup.cs')).Path
$normalize={param([string]$text) $text.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $normalize $embedded) -cne (& $normalize ([IO.File]::ReadAllText($source)))){
 throw 'R317_COMPILED_PRIVATE_SETUP_NOT_REVIEWED_SOURCE'
}
$checks.Add('EXACT_PE_PRIVATE_INSTALLER_EMBEDDED_SOURCE_PINNED')
$type=$assembly.GetType('SetupProgram',$true)
$flags=[Reflection.BindingFlags]'Static,NonPublic'
$builder=$type.GetMethod('BuildDeferredUninstallCleanupProcessInfo',$flags)
$rootProp=$type.GetProperty('AppRoot',$flags)
if(!$builder -or !$rootProp){throw 'R317_NO_DEFERRED_CLEANUP_FACTORY_IN_PE'}
$checks.Add('PURE_PRIVATE_CLEANUP_FACTORY_PRESENT')
$root=[string]$rootProp.GetValue($null,$null)
$expected=[IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'))
if(-not [string]::Equals($root,$expected,[StringComparison]::OrdinalIgnoreCase)){
 throw 'R317_OS_OWNER_CANONICAL_ROOT_CHANGED'
}
$pidSelf=[Diagnostics.Process]::GetCurrentProcess()
try{$selfPid=[int]$pidSelf.Id;$selfTicks=[long]$pidSelf.StartTime.ToUniversalTime().Ticks}finally{$pidSelf.Dispose()}
$psi=$builder.Invoke($null,[object[]]@($root,$selfPid,$selfTicks))
$prefix='-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand '
if(-not $psi.Arguments.StartsWith($prefix,[StringComparison]::Ordinal) -or
   $psi.Arguments.Contains(' -File ') -or
   $psi.Arguments.Contains(' -Command ') -or
   $psi.Arguments.Contains('ExecutionPolicy Bypass') -or
   $psi.Arguments.Contains($root) -or $psi.Arguments.Length -gt 22080){
 throw 'R317_UNSAFE_UNENCODED_CLEANUP_TRANSPORT'
}
$checks.Add('ONLY_BOUNDED_UTF16_ENCODED_COMMAND_WITHOUT_LITERAL_USER_PATH')
$trusted=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
if(-not [string]::Equals($psi.FileName,$trusted,[StringComparison]::OrdinalIgnoreCase) -or
   $psi.UseShellExecute -ne $false -or
   $psi.CreateNoWindow -ne $true -or
   $psi.WorkingDirectory -cnotmatch '^(?i)[A-Z]:\\' -or
   [string]::Equals($psi.WorkingDirectory,$root,[StringComparison]::OrdinalIgnoreCase)){
 throw 'R317_UNTRUSTED_CLEANUP_HOST_OR_CWD'
}
$checks.Add('ABSOLUTE_SYSTEM32_POWERSHELL_NOT_CMD_OR_APP_CWD')
$code=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($psi.Arguments.Substring($prefix.Length)))
$tokens=$null;$errors=$null
[void][Management.Automation.Language.Parser]::ParseInput($code,[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw 'R317_ACTUAL_IN_MEMORY_CODE_PS51_PARSER_FAILED'}
$checks.Add('EMBEDDED_CLEANUP_SCRIPT_WINPS51_PARSER_ACCEPTED')
$match=[regex]::Match($code,'(?m)^\$root=\[Text\.Encoding\]::UTF8\.GetString\(\[Convert\]::FromBase64String\(''([A-Za-z0-9+/=]+)''\)\)')
if(-not $match.Success -or
   -not [string]::Equals([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($match.Groups[1].Value)),$root,[StringComparison]::OrdinalIgnoreCase)){
 throw 'R317_APP_ROOT_NOT_IN_SAFE_BASE64_DATA_SLOT'
}
$checks.Add('APP_ROOT_UTF8_BASE64_DATA_ROUNDTRIP_BYTE_EXACT')
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if(-not $code.Contains("$" + "expectedSid='$sid'") -or
   -not $code.Contains("$" + "expectedPid=[int]$selfPid") -or
   -not $code.Contains("$" + "expectedStart=[long]$selfTicks")){
 throw 'R317_EXPECTED_ACCOUNT_PID_START_BINDINGS_MISSING'
}
$checks.Add('EFFECTIVE_SID_PARENT_PID_AND_STARTTIME_BOUND')
foreach($literal in @(
 'TBME_CLEANUP_WRONG_EFFECTIVE_TOKEN',
 'TBME_CLEANUP_ROOT_NOT_CANONICAL',
 'TBME_CLEANUP_ANCESTOR_REPARSE',
 'TBME_CLEANUP_CHILD_REPARSE',
 'TBME_CLEANUP_EXCESSIVE_ENTRY_COUNT',
 '[IO.Directory]::Delete($dir,$false)'
)){
 if(-not $code.Contains($literal)){throw ('R317_SCRIPT_PROTECTION_MISSING '+$literal)}
}
$checks.Add('LATE_ROOT_SID_AND_NONFOLLOWING_DESCENDANT_GUARDS_PRESENT')
if($code.Contains('[IO.Directory]::Delete($expectedRoot,$true)') -or
   -not $code.Contains('[IO.File]::Delete($file)') -or
   -not $code.Contains('TBME_CLEANUP_PATH_ESCAPED_OWNER_ROOT') -or
   -not $code.Contains('TBME_CLEANUP_CHANGED_DIRECTORY')){
 throw 'R317_RECURSIVE_OR_UNBOUNDED_CLEANUP_NOT_PERMITTED'
}
$checks.Add('NONRECURSIVE_EMPTY_DIRECTORY_DELETION_WITH_REPARSE_PRECHECK')
$fragmentStart=$code.IndexOf('$cursor=$expectedRoot',[StringComparison]::Ordinal)
$fragmentEndMarker='[IO.Directory]::Delete($dir,$false)'
$fragmentEnd=$code.LastIndexOf($fragmentEndMarker,[StringComparison]::Ordinal)
if($fragmentStart -lt 0 -or $fragmentEnd -le $fragmentStart -or
   $code.Contains('[IO.Directory]::Delete($expectedRoot,$true)')){
 throw 'R317_EXACT_PRODUCTION_DELETION_FRAGMENT_NOT_SAFE'
}
$fragmentClose=$code.IndexOf('}',$fragmentEnd+$fragmentEndMarker.Length)
if($fragmentClose -le $fragmentEnd -or
   $code.Substring($fragmentEnd+$fragmentEndMarker.Length,$fragmentClose-($fragmentEnd+$fragmentEndMarker.Length)).Trim().Length -ne 0){
 throw 'R317_INVALID_END_OF_NONRECURSIVE_FOREACH'
}
$fragment=$code.Substring($fragmentStart,$fragmentClose+1-$fragmentStart)
$tokFragment=$null;$errFragment=$null
[void][Management.Automation.Language.Parser]::ParseInput($fragment,[ref]$tokFragment,[ref]$errFragment)
if(@($errFragment).Count){throw 'R317_NONRECURSIVE_FRAGMENT_INVALID_SYNTAX'}
$removeSynthetic=[scriptblock]::Create($fragment)
$checks.Add('EXACT_PE_NONRECURSIVE_DELETE_FRAGMENT_EXTRACTED_AND_PARSED')
$isolated=Join-Path $run 'native-only-delete-fixture'
$nested=Join-Path $isolated 'nested'
[void][IO.Directory]::CreateDirectory($nested)
[IO.File]::WriteAllText((Join-Path $isolated 'first.txt'),'R317_SYNTHETIC_LEAF_A')
[IO.File]::WriteAllText((Join-Path $nested 'second.txt'),'R317_SYNTHETIC_LEAF_B')
$expectedRoot=$isolated
if(-not [IO.Path]::GetFullPath($expectedRoot).StartsWith(([IO.Path]::GetFullPath($run).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){
 throw 'R317_FIXTURE_NOT_CHILD_OF_HOSTED_RUNNER_TEMP'
}
& $removeSynthetic
if([IO.Directory]::Exists($isolated)){throw 'R317_NONRECURSIVE_NATIVE_DELETE_DID_NOT_FINISH'}
$checks.Add('ONLY_HOSTED_SYNTHETIC_TREE_NONRECURSIVELY_DELETED')
$external=Join-Path $run 'external-untouched-canary'
[void][IO.Directory]::CreateDirectory($external)
$canary=Join-Path $external 'preserve.txt'
[IO.File]::WriteAllText($canary,'R317_KEEP_EXTERNAL_DATA')
$canarySha=Hash $canary
$blocked=Join-Path $run 'native-only-junction-refusal'
[void][IO.Directory]::CreateDirectory($blocked)
$link=Join-Path $blocked 'unknown-junction'
New-Item -ItemType Junction -Path $link -Target $external -ErrorAction Stop|Out-Null
$expectedRoot=$blocked
$refused=$false
try{& $removeSynthetic}catch{
 if($_.Exception.ToString() -match 'TBME_CLEANUP_CHILD_REPARSE'){$refused=$true}else{throw}
}
if(-not $refused -or (Hash $canary) -cne $canarySha -or
   -not [IO.Directory]::Exists($blocked)){throw 'R317_CHILD_JUNCTION_WAS_FOLLOWED'}
[IO.Directory]::Delete($link,$false)
$checks.Add('JUNCTION_DESCENDANT_REFUSED_WITH_NO_EXTERNAL_DELETION')
$rootJunction=Join-Path $run 'native-only-root-junction'
New-Item -ItemType Junction -Path $rootJunction -Target $external -ErrorAction Stop|Out-Null
$expectedRoot=$rootJunction
$rootRefused=$false
try{& $removeSynthetic}catch{
 if($_.Exception.ToString() -match 'TBME_CLEANUP_ANCESTOR_REPARSE'){$rootRefused=$true}else{throw}
}
if(-not $rootRefused -or (Hash $canary) -cne $canarySha){
 throw 'R317_ROOT_JUNCTION_WAS_FOLLOWED'
}
[IO.Directory]::Delete($rootJunction,$false)
$checks.Add('ROOT_JUNCTION_REFUSED_WITH_EXTERNAL_CANARY_INTACT')

$sourceText=[IO.File]::ReadAllText($source)
if($sourceText.Contains('tbme_cleanup_') -or
   $sourceText.Contains('rmdir /s /q') -or
   $sourceText.Contains('new ProcessStartInfo("cmd.exe"') -or
   $sourceText.Contains('Process.Start(new ProcessStartInfo("cmd.exe"')){
 throw 'R317_MUTABLE_TEMP_BATCH_OR_CMD_STILL_IN_PRODUCTION_SETUP'
}
$checks.Add('REMOVED_MUTABLE_TEMP_BATCH_AND_UNQUALIFIED_CMD_SINK')
function MustRefuse([string]$name,[string]$path,[int]$parentProcessId,[long]$ticks){
 $rejected=$false
 try{$null=$builder.Invoke($null,([object[]]@($path,$parentProcessId,$ticks)))}
 catch{
  if($_.Exception.GetBaseException().Message -match 'Uninstall cleanup requires the exact owner root'){
   $rejected=$true
  }else{throw}
 }
 if(-not $rejected){throw ('R317_FAIL_OPEN_'+$name)}
 $script:checks.Add($name)
}
MustRefuse 'FOREIGN_SYSTEM_ROOT_REFUSED' 'C:\Windows' $selfPid $selfTicks
MustRefuse 'UNC_ROOT_REFUSED' '\\server\share' $selfPid $selfTicks
MustRefuse 'INJECTED_COMMAND_PATH_REFUSED' 'C:\Windows&whoami' $selfPid $selfTicks
MustRefuse 'CMD_PERCENT_VARIABLE_PATH_REFUSED' 'C:\Test%TBME_R317_ATTACK_PROBE%\TaskbarMonitorEnhanced' $selfPid $selfTicks
MustRefuse 'ZERO_PARENT_PID_REFUSED' $root 0 $selfTicks
MustRefuse 'INVALID_PARENT_STARTTIME_REFUSED' $root $selfPid 0
MustRefuse 'SUBFOLDER_NOT_APP_ROOT_REFUSED' (Join-Path $root 'Logs') $selfPid $selfTicks
if((Hash $main) -cne $old.Main -or (Hash $config) -cne $old.Config -or
   (Hash $state) -cne $old.State){
 throw 'R317_USER_APP_CHANGED_BY_TRANSPORT_ONLY_PROOF'
}
$checks.Add('NO_INSTALLATION_OR_SETTINGS_MUTATED')
$checks.Add('NO_CLEANUP_PROCESS_LAUNCHED_IN_TEST')
$receiptObject=[ordered]@{
 Schema=1;Revision='R317'
 Status='PASS_EXACT_PE_INMEMORY_UNINSTALL_CLEANUP_TRANSPORT_SYNTHETIC'
 Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
 MainInstallationUntouched=$true;ActualCleanupProcessLaunched=$false
 ActualDirectoryDeleted=$false;OriginalOwnerComputerTouched=$false
 NoMutableTempBatchOrCmd=$true;ProcessHostAbsolutePinned=$true
 ShellArgumentsPureBase64=$true;WrongRootsAndInjectionRefused=$true
 ScriptSyntaxAndTokenGuardVerified=$true;UserDataUnchanged=$true
 SyntheticNonrecursiveDeletionVerified=$true;SyntheticJunctionRefusalVerified=$true
 TrueUninstallCleanupEndToEndProven=$false
 Checks=@($checks)
 RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receipt,($receiptObject|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
'R317_'+$HostLabel+'_SAFE_UNINSTALL_TRANSPORT_NOT_LIVE_CLEANUP_PASS'
