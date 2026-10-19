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
 throw 'R318_DISPOSABLE_WINDOWS_GUEST_ONLY'
}
function SHA([string]$p){
 if(-not [IO.File]::Exists($p)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
}
$dir=Join-Path $env:RUNNER_TEMP ('R318_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $dir 'R318_INPROCESS_SHORTCUT_RECEIPT.json'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R317_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R317_ENCODED_CLEANUP_RECEIPT.json')
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$config=Join-Path $app 'config.json'
$state=Join-Path $app 'install_state.json'
$checks=[Collections.Generic.List[string]]::new()
if([IO.Directory]::Exists($dir)){throw 'R318_TEST_FIXTURE_ALREADY_PRESENT'}
[void][IO.Directory]::CreateDirectory($dir)
$initial=@{Main=(SHA $main);Config=(SHA $config);State=(SHA $state)}
$c=Get-Content $manifest -Raw|ConvertFrom-Json
$p=Get-Content $prior -Raw|ConvertFrom-Json
if($c.Commit -cne $env:GITHUB_SHA -or
   $c.SetupSHA256 -cne (SHA $setup) -or
   $c.MainSHA256 -cne $initial.Main -or
   $p.Host -cne $HostLabel -or $p.SourceCommit -cne $env:GITHUB_SHA -or
   $p.Status -cne 'PASS_EXACT_PE_INMEMORY_UNINSTALL_CLEANUP_TRANSPORT_SYNTHETIC'){
 throw 'R318_EXACT_CANDIDATE_OR_R317_PROOF_NOT_VERIFIED'
}
$checks.Add('EXACT_PE_CANDIDATE_AND_PREVIOUS_UNINSTALL_PROOF')
$asm=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
$stream=$asm.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced_Setup.cs')
if(!$stream){throw 'R318_COMPILATION_SOURCE_NOT_EMBEDDED'}
$reader=[IO.StreamReader]::new($stream)
try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
$file=(Resolve-Path (Join-Path $PSScriptRoot '..\installer\TaskbarMonitorEnhanced_Setup.cs')).Path
$normalize={param([string]$s) $s.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
$raw=[IO.File]::ReadAllText($file)
if((& $normalize $embedded) -cne (& $normalize $raw)){
 throw 'R318_EXACT_PE_SOURCE_DIFFERS_FROM_PRODUCTION'
}
$checks.Add('EXACT_PE_EMBEDDED_SHORTCUT_SOURCE_MATCH')
$type=$asm.GetType('SetupProgram',$true)
$flags=[Reflection.BindingFlags]'Static,NonPublic'
$paramTypes=[Type[]]@([string],[string],[string],[string])
$method=$type.GetMethod('Shortcut',$flags,$null,$paramTypes,$null)
$rootProperty=$type.GetProperty('AppRoot',$flags)
if(-not $method -or -not $rootProperty){throw 'R318_EXACT_FOUR_ARGUMENT_COM_SHORTCUT_METHOD_MISSING'}
$checks.Add('EXACT_PRIVATE_FOUR_ARG_METHOD_REFLECTED')
$open=$raw.IndexOf('static void Shortcut(string path,string target,string arguments,string description)',[StringComparison]::Ordinal)
$close=$raw.IndexOf('static string Sha256File(string path)',[StringComparison]::Ordinal)
if($open -lt 0 -or $close -le $open){throw 'R318_COM_SHORTCUT_METHOD_ANCHOR_INVALID'}
$implementation=$raw.Substring($open,$close-$open)
foreach($unsafe in @('tbme_shortcut_','ExecutionPolicy Bypass','Process.Start(','ProcessStartInfo(','File.WriteAllText(','powershell.exe','cmd.exe')){
 if($implementation.IndexOf($unsafe,[StringComparison]::OrdinalIgnoreCase) -ge 0){
  throw ('R318_MUTABLE_SCRIPT_OR_PROCESS_STILL_IN_SHORTCUT '+$unsafe)
 }
}
foreach($needed in @('WScript.Shell','CreateShortcut','BindingFlags.SetProperty','InvokeMember("Save"','FinalReleaseComObject')){
 if(-not $implementation.Contains($needed)){throw ('R318_INPROCESS_COM_PRIMITIVE_MISSING '+$needed)}
}
$checks.Add('NO_TEMP_SCRIPT_NO_EXTERNAL_PROCESS_IN_SHORTCUT_METHOD')
$target=Join-Path ([Environment]::SystemDirectory) 'notepad.exe'
if(-not [IO.File]::Exists($target)){throw 'R318_SYNTHETIC_TARGET_NOT_PRESENT'}
$link=Join-Path $dir "R318 ' % & harmless.lnk"
$arguments='--startup-recovery "%PATH%" & echo harmless; | $literal'
$description="R318 literal ' quotes & percent % untouched"
$wsh=$null;$shortcut=$null
try{
 if([IO.File]::Exists($link)){throw 'R318_EPHEMERAL_SHORTCUT_ALREADY_PRESENT'}
 $null=$method.Invoke($null,[object[]]@([string]$link,[string]$target,[string]$arguments,[string]$description))
 if(-not [IO.File]::Exists($link)){throw 'R318_COM_SHORTCUT_NOT_PERSISTED'}
 $checks.Add('COM_CREATED_ONLY_DISPOSABLE_LINK_FILE')
 $wsh=New-Object -ComObject WScript.Shell
 $shortcut=$wsh.CreateShortcut($link)
 $actualTarget=[IO.Path]::GetFullPath([string]$shortcut.TargetPath)
 if(-not [string]::Equals($actualTarget,$target,[StringComparison]::OrdinalIgnoreCase)){
  throw 'R318_COM_SHORTCUT_TARGET_CHANGED'
 }
 $checks.Add('SAVED_SHORTCUT_TARGET_EXACT_AFTER_COM_READBACK')
 if([string]$shortcut.Arguments -cne $arguments){
  throw 'R318_SHORTCUT_LITERAL_METACHARACTERS_CHANGED'
 }
 $checks.Add('LITERAL_COMMAND_METACHARACTER_ARGS_ARE_DATA_NOT_SCRIPT')
 if([string]$shortcut.Description -cne $description){
  throw 'R318_SHORTCUT_DESCRIPTION_CHANGED'
 }
 $checks.Add('SHORTCUT_DESCRIPTION_WITH_QUOTE_ROUNDTRIP')
 $root=[string]$rootProperty.GetValue($null,$null)
 if(-not [string]::Equals([string]$shortcut.WorkingDirectory,$root,[StringComparison]::OrdinalIgnoreCase)){
  throw 'R318_SHORTCUT_WORKING_DIRECTORY_NOT_OWNER_APPROOT'
 }
 $checks.Add('SHORTCUT_WORKING_DIRECTORY_PINNED_TO_OWNER_ROOT')
 if([int]$shortcut.WindowStyle -ne 1){throw 'R318_SAVED_SHORTCUT_WINDOWSTYLE_NOT_EXPECTED'}
 $checks.Add('SAVED_SHORTCUT_WINDOWSTYLE_ONE')
 $icon=[string]$shortcut.IconLocation
 if($icon -notmatch '(?i)TaskbarMonitorEnhanced\.exe\s*,\s*0$'){
  throw 'R318_ICON_LOCATION_NOT_OWNER_EXECUTABLE'
 }
 $checks.Add('SAVED_SHORTCUT_ICON_LOCATION_PINNED')
}finally{
 foreach($obj in @($shortcut,$wsh)){
  if($null -ne $obj -and [Runtime.InteropServices.Marshal]::IsComObject($obj)){
   [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($obj)
  }
 }
 if([IO.File]::Exists($link)){[IO.File]::Delete($link)}
}
if([IO.File]::Exists($link)){throw 'R318_SHORTCUT_FIXTURE_CLEANUP_FAILED'}
$checks.Add('SYNTHETIC_LINK_REMOVED_AFTER_TEST')
function Reject([string]$label,[string]$badLink,[string]$badTarget,[string]$needle){
 $denied=$false
 try{$null=$method.Invoke($null,[object[]]@($badLink,$badTarget,'','bad'))}
 catch{
  if($_.Exception.GetBaseException().Message -match $needle){$denied=$true}else{throw}
 }
 if(-not $denied){throw ('R318_UNSAFE_INPUT_ACCEPTED_'+$label)}
 $script:checks.Add($label)
}
Reject 'RELATIVE_LINK_REJECTED' 'shortcut.lnk' $target 'absolute'
Reject 'WRONG_EXTENSION_REJECTED' (Join-Path $dir 'bad.ps1') $target 'absolute'
Reject 'RELATIVE_TARGET_REJECTED' (Join-Path $dir 'bad-target.lnk') 'notepad.exe' 'absolute'
Reject 'MISSING_LINK_DIRECTORY_REJECTED' (Join-Path $dir 'missing\bad.lnk') $target 'directory is not available'
$remains=@([IO.Directory]::GetFileSystemEntries($dir))
if($remains.Count -ne 0){throw 'R318_EPHEMERAL_LINK_RESIDUE_OR_SCRIPT'}
$checks.Add('NO_EXTRA_TEMP_EXECUTABLE_OR_SHORTCUT_FIXTURE_RESIDUE')
if((SHA $main) -cne $initial.Main -or (SHA $config) -cne $initial.Config -or
   (SHA $state) -cne $initial.State){
 throw 'R318_HOSTED_INSTALLED_USER_FILES_CHANGED'
}
$checks.Add('HOSTED_INSTALLED_MAIN_CONFIG_STATE_BYTE_EXACT')
$record=[ordered]@{
 Schema=1;Revision='R318'
 Status='PASS_EXACT_PE_INPROCESS_COM_SHORTCUT_AND_NO_TEMP_SCRIPT'
 Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
 OriginalOwnerComputerTouched=$false
 ActualProgramFilesWritten=$false;ActualUACInvoked=$false
 OriginalProtectedSensorTaskTouched=$false
 ActualInstalledShortcutChanged=$false
 ExactPeSourceAndCOMMethodVerified=$true
 WScriptShortcutCreatedReadAndRemoved=$true
 AllShortcutPropertiesRoundtripped=$true
 PowerShellTempScriptEliminated=$true
 MetacharactersTreatedAsData=$true
 RelativeAndInvalidPathsRefused=$true
 RealInstalledUserDataUnchanged=$true
 RealOwnerInstallationOrUninstallInvoked=$false
 Checks=@($checks)
 RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receipt,($record|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
'R318_'+$HostLabel+'_EXACT_PE_COM_SHORTCUT_NO_TEMP_SCRIPT_SYNTHETIC_PASS'
