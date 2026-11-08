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
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'R321_ONLY_DISPOSABLE_GITHUB_WINDOWS_GUEST'
}
function SHA([string]$p){
 if(-not [IO.File]::Exists($p)){return 'MISSING'}
 return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
}
$root=Join-Path $env:RUNNER_TEMP ('R321_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
$receipt=Join-Path $root 'R321_PINNED_MAIN_PRELAUNCH_RECEIPT.json'
$manifest=Join-Path $CandidateDir 'CANDIDATE.json'
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$prior=Join-Path $env:RUNNER_TEMP ('R302_'+$HostLabel+'_'+$env:GITHUB_RUN_ID+'\R302_REAL_SETUP_CLEANUP_KILL_RECEIPT.json')
$app=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
$main=Join-Path $app 'TaskbarMonitorEnhanced.exe'
$config=Join-Path $app 'config.json'
$state=Join-Path $app 'install_state.json'
$checks=[Collections.Generic.List[string]]::new()
if(Test-Path -LiteralPath $root){throw 'R321_EXISTING_TEST_FIXTURE'}
[void][IO.Directory]::CreateDirectory($root)
$old=@{Main=(SHA $main);Config=(SHA $config);State=(SHA $state)}
$c=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
$prev=Get-Content -LiteralPath $prior -Raw|ConvertFrom-Json
if($c.Commit -cne $env:GITHUB_SHA -or
   $c.SetupSHA256 -cne (SHA $setup) -or
   $c.MainSHA256 -cne $old.Main -or
   $prev.Host -cne $HostLabel -or
   $prev.SourceCommit -cne $env:GITHUB_SHA -or
   $prev.Status -cne 'PASS_NATIVE_SETUP_KILLED_DURING_STAGE_CLEANUP_RECOVERED'){
 throw 'R321_CANDIDATE_OR_PREVIOUS_NATIVE_PROOF_UNTRUSTED'
}
$assembly=[Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($setup))
$type=$assembly.GetType('SetupProgram',$true)
$method=$type.GetMethod('OpenPinnedVerifiedMainForLaunch',[Reflection.BindingFlags]'Static,NonPublic')
if(!$method){throw 'R321_COMPILED_SETUP_GUARD_NOT_FOUND'}
$srcRes=$assembly.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced_Setup.cs')
if(!$srcRes){throw 'R321_COMPILED_SOURCE_RESOURCE_MISSING'}
$reader=[IO.StreamReader]::new($srcRes)
try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
$source=(Resolve-Path (Join-Path $PSScriptRoot '..\installer\TaskbarMonitorEnhanced_Setup.cs')).Path
$normal={param([string]$s) $s.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $normal $embedded) -cne (& $normal ([IO.File]::ReadAllText($source)))){
 throw 'R321_PRIVATE_EXE_COMPILED_SOURCE_DIFFERS'
}
$code=[IO.File]::ReadAllText($source)
$start=$code.IndexOf('using(FileStream pinned=OpenPinnedVerifiedMainForLaunch(',[StringComparison]::Ordinal)
$builder=$code.IndexOf('BuildPinnedMainProcessInfo(pinned,AppRoot)',[StringComparison]::Ordinal)
$launch=$code.IndexOf('Process.Start(direct)',[StringComparison]::Ordinal)
$finish=$code.IndexOf('MainLaunchMode="LAUNCHED_NON_ELEVATED_SETUP"', [StringComparison]::Ordinal)
if($start -lt 0 -or $builder -le $start -or $launch -le $builder -or
   $finish -le $launch -or $code.Contains('Process.Start(AppExe)')){
 throw 'R321_R326_GUARD_NOT_BOUND_ACROSS_DIRECT_CREATEPROCESS'
}
$checks.Add('EXACT_EMBEDDED_SOURCE_AND_REAL_LAUNCH_GUARD_ORDER')
$resource=$assembly.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced.exe')
if(!$resource){throw 'R321_TRUSTED_MAIN_RESOURCE_MISSING'}
$sourceStream=[IO.MemoryStream]::new()
try{$resource.CopyTo($sourceStream)}finally{$resource.Dispose()}
$bytes=$sourceStream.ToArray()
$sourceStream.Dispose()
$expected=[BitConverter]::ToString(([Security.Cryptography.SHA256]::Create().ComputeHash($bytes))).Replace('-','')
if($expected.Length -ne 64 -or $bytes.Length -lt 1024){throw 'R321_PE_RESOURCE_HASH_OR_SIZE_BAD'}
$checks.Add('EXACT_PE_MAIN_SHA256_AND_SOURCE_LENGTH')
$folder=Join-Path $root 'safe'
[void][IO.Directory]::CreateDirectory($folder)
$file=Join-Path $folder 'TaskbarMonitorEnhanced.exe'
[IO.File]::WriteAllBytes($file,$bytes)
function Validate([string]$path,[string]$dir,[string]$expectedHash){
 try{return $method.Invoke($null,[object[]]@($path,$dir,$expectedHash))}
 catch{throw [InvalidOperationException]::new($_.Exception.GetBaseException().Message,$_.Exception)}
}
function Reject([string]$label,[string]$path,[string]$dir,[string]$expectedHash,[string]$pattern){
 $refused=$false
 try{
  $x=Validate $path $dir $expectedHash
  if($null -ne $x){$x.Dispose()}
 }catch{if($_.Exception.ToString() -match $pattern){$refused=$true}else{throw}}
 if(!$refused){throw ('R321_FAIL_OPEN_'+$label)}
 $script:checks.Add($label)
}
$lock=[IO.FileStream](Validate $file $folder $expected)
if(!$lock.CanRead -or $lock.Length -ne $bytes.Length -or
   -not [string]::Equals([IO.Path]::GetFullPath($lock.Name),[IO.Path]::GetFullPath($file),[StringComparison]::OrdinalIgnoreCase)){
 throw 'R321_VALID_MAIN_LOCK_IS_NOT_PINNED'
}
$checks.Add('SHA_VERIFIED_MAIN_RETURNED_READABLE_PINNED_HANDLE')
$writeDenied=$false;$renameDenied=$false
try{
 try{
  $writer=[IO.FileStream]::new($file,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
  $writer.Dispose()
 }catch [IO.IOException]{$writeDenied=$true}
 try{[IO.File]::Move($file,(Join-Path $folder 'wrong-name.exe'))}
 catch [IO.IOException]{$renameDenied=$true}
 if(-not $writeDenied -or -not $renameDenied){
  throw ('R321_OPEN_HANDLE_SHARING_DID_NOT_PROTECT_FILE WRITE='+$writeDenied+' RENAME='+$renameDenied)
 }
 if((SHA $file) -cne $expected){throw 'R321_PINNED_BYTES_CHANGED'}
}finally{$lock.Dispose()}
$checks.Add('FILE_WRITE_AND_RENAME_DENIED_DURING_PROCESS_START_WINDOW')
# These hostile test cases must all fail before any GUI/process is launched.
Reject 'WRONG_EMBEDDED_MAIN_HASH_REJECTED' $file $folder ('0'*64) 'does not match'
Reject 'UNRELATED_ROOT_REJECTED' $file (Join-Path $root 'foreign') $expected 'escaped'
Reject 'UNEXPECTED_EXE_BASENAME_REJECTED' (Join-Path $folder 'evil.exe') $folder $expected 'escaped'
Reject 'RELATIVE_MAIN_PATH_REJECTED' 'TaskbarMonitorEnhanced.exe' $folder $expected 'incomplete'
Reject 'UNC_INSTALL_ROOT_REJECTED' '\\server\share\TaskbarMonitorEnhanced.exe' '\\server\share' $expected 'escaped'
$altered=[byte[]]$bytes.Clone()
$altered[36]=($altered[36] -bxor 1)
[IO.File]::WriteAllBytes($file,$altered)
Reject 'SAME_NAME_BINARY_TAMPER_REJECTED' $file $folder $expected 'does not match'
[IO.File]::WriteAllBytes($file,$bytes)
if((SHA $file) -cne $expected){throw 'R321_TEST_RESTORE_CANDIDATE_FAILED'}
$checks.Add('TEST_ONLY_MAIN_RESOURCE_EXACTLY_RESTORED')
# A folder junction with a valid PE at the target cannot escape the pin.
$outside=Join-Path $root 'outside'
[void][IO.Directory]::CreateDirectory($outside)
$outerFile=Join-Path $outside 'TaskbarMonitorEnhanced.exe'
[IO.File]::WriteAllBytes($outerFile,$bytes)
$canary=Join-Path $outside 'unrelated-canary.txt'
[IO.File]::WriteAllText($canary,'R321_PRESERVE_UNRELATED',[Text.Encoding]::ASCII)
$canaryHash=SHA $canary
$link=Join-Path $root 'junction-root'
New-Item -ItemType Junction -Path $link -Target $outside -ErrorAction Stop|Out-Null
try{
 Reject 'JUNCTION_ANCESTOR_REJECTED' (Join-Path $link 'TaskbarMonitorEnhanced.exe') $link $expected 'reparse'
}finally{[IO.Directory]::Delete($link)}
if((SHA $canary) -cne $canaryHash){throw 'R321_JUNCTION_EXTERNAL_CANARY_CHANGED'}
$checks.Add('JUNCTION_TARGET_FILE_AND_CANARY_PRESERVED')
if((SHA $main) -cne $old.Main -or (SHA $config) -cne $old.Config -or (SHA $state) -cne $old.State){
 throw 'R321_INSTALLED_GUEST_MAIN_OR_SETTINGS_CHANGED'
}
$checks.Add('CURRENT_GUEST_INSTALLATION_SETTINGS_UNCHANGED')
$record=[ordered]@{
 Schema=1;Revision='R321';Status='PASS_PINNED_MAIN_BEFORE_AUTOLAUNCH_SYNTHETIC'
 Host=$HostLabel;SourceCommit=$env:GITHUB_SHA
 ExactPEInstallerSourceVerified=$true;VerifiedMainSHA256=$expected
 ReadHandleHeldAcrossLaunchPath=$true
 ExclusiveWriterDenied=$writeDenied
 RenameBeforeLaunchDenied=$renameDenied
 AlteredSameNameBinaryRejected=$true
 JunctionAndUnsafePathsRejected=$true
 MainWasNotActuallyLaunchedInFixture=$true
 OriginalOwnerHostTouched=$false;ActualProtectedTaskTouched=$false
 ActualUACInvoked=$false;SecurityCodeQLAccepted=$false
 GuestMainAndUserSettingsPreserved=$true
 Checks=@($checks);RecordedUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText($receipt,($record|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
'R321_'+$HostLabel+'_PINNED_MAIN_HASH_AND_SHARE_BOUNDARY_PASS'
