[CmdletBinding()]
param([string]$SetupPath='', [ValidateSet('LOCAL','A','B')][string]$HostLabel='LOCAL')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($SetupPath)){
    $SetupPath=Join-Path $PSScriptRoot '_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   !(Test-Path -LiteralPath $SetupPath -PathType Leaf)){
   throw 'R329_REQUIRES_COMPILED_SETUP_NETFRAMEWORK_ON_WINDOWS'
}
$assembly=[Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $SetupPath).Path)
$type=$assembly.GetType('SetupProgram',$true)
$pinMethod=$type.GetMethod('OpenPinnedVerifiedMainForLaunch',[Reflection.BindingFlags]'NonPublic,Static')
$psiMethod=$type.GetMethod('BuildPinnedMainProcessInfo',[Reflection.BindingFlags]'NonPublic,Static')
if(!$pinMethod -or !$psiMethod){throw 'R329_EXPECTED_REAL_PINNED_PROCESS_METHODS_MISSING'}
$sourceStream=$assembly.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced_Setup.cs')
if(!$sourceStream){throw 'R329_SOURCE_EMBEDDED_RESOURCE_MISSING'}
$sourceReader=[IO.StreamReader]::new($sourceStream)
try{$embedded=$sourceReader.ReadToEnd()}finally{$sourceReader.Dispose()}
$source=[IO.File]::ReadAllText((Resolve-Path (Join-Path $PSScriptRoot '..\installer\TaskbarMonitorEnhanced_Setup.cs')).Path)
$norm={param($s) $s.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $norm $embedded) -cne (& $norm $source)){throw 'R329_EMBEDDED_SOURCE_DIFFERS_FROM_REAL_WORKTREE'}
$checks=[Collections.Generic.List[string]]::new()
function Pass([string]$name){
    $script:checks.Add($name)
    Write-Output ('PASS '+$name)
}
Pass 'COMPILED_SETUP_EXACT_EMBEDDED_SOURCE'
$resource=$assembly.GetManifestResourceStream('Payload.TaskbarMonitorEnhanced.exe')
if(!$resource){throw 'R329_EMBEDDED_MAIN_RESOURCE_MISSING'}
$memory=[IO.MemoryStream]::new()
try{$resource.CopyTo($memory)}finally{$resource.Dispose()}
$bytes=$memory.ToArray()
$memory.Dispose()
$sha=[Security.Cryptography.SHA256]::Create()
try{$expected=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','')}
finally{$sha.Dispose()}
if($bytes.Length -lt 1024 -or $expected.Length -ne 64){throw 'R329_BAD_IMMUTABLE_MAIN_RESOURCE'}
Pass 'EMBEDDED_MAIN_SHA256_PIN_AVAILABLE'

$base=Join-Path ([IO.Path]::GetTempPath()) ('tbme_r329_real_setup_main_'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($base)|Out-Null
$profile=Join-Path $base 'user profile & literal $dollar'
$appData=Join-Path $profile 'AppData'
$local=Join-Path $appData 'Local'
$appRoot=Join-Path $local 'TaskbarMonitorEnhanced'
[IO.Directory]::CreateDirectory($appRoot)|Out-Null
$main=Join-Path $appRoot 'TaskbarMonitorEnhanced.exe'
[IO.File]::WriteAllBytes($main,$bytes)
$external=Join-Path $base 'outside-app'
[IO.Directory]::CreateDirectory($external)|Out-Null
$canary=Join-Path $external 'external-canary.txt'
[IO.File]::WriteAllText($canary,'NO_EXTERNAL_MODIFICATION')
$actor=Join-Path $base 'move-test-actor.ps1'
$actorSource=@'
param([Parameter(Mandatory=$true)][string]$PathBase64)
$ErrorActionPreference='Stop'
$target=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($PathBase64))
$moved=$target+'_actor_moved'
try {
    [IO.Directory]::Move($target,$moved)
    [IO.Directory]::Move($moved,$target)
    Write-Output 'ACTOR_RENAME_ALLOWED_AND_RESTORED'
    exit 61
}catch [IO.IOException]{
    Write-Output 'ACTOR_RENAME_BLOCKED_IO'
    exit 0
}catch [UnauthorizedAccessException]{
    Write-Output 'ACTOR_RENAME_BLOCKED_ACCESS'
    exit 0
}catch{
    Write-Output ('ACTOR_UNEXPECTED_ERROR_'+$_.Exception.GetType().Name)
    exit 70
}
'@
[IO.File]::WriteAllText($actor,$actorSource,[Text.UTF8Encoding]::new($false))
$win=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
function Try-Rename([string]$path){
    $moved=$path+'_native_moved'
    $ok=$false
    try{[IO.Directory]::Move($path,$moved);$ok=$true}
    catch [IO.IOException]{}catch [UnauthorizedAccessException]{}
    if($ok){
        [IO.Directory]::Move($moved,$path)
        return $true
    }
    return $false
}
function Invoke-SeparateActor([string]$target) {
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($target))
    $out=@(& $win -NoProfile -NonInteractive -File $actor -PathBase64 $encoded 2>&1)
    $code=$LASTEXITCODE
    if($code -notin @(0,61)){
        throw ('R329_CHILD_ACTOR_ERROR_EXIT_'+$code+' '+($out -join ' '))
    }
    if($code -eq 61 -and @($out|Where-Object {$_ -eq 'ACTOR_RENAME_ALLOWED_AND_RESTORED'}).Count -ne 1){
        throw 'R329_CHILD_RENAME_ALLOWED_WITHOUT_RESTORE_EVIDENCE'
    }
    return $code
}
$pinned=$null
try {
    foreach($pair in @(@('APPROOT',$appRoot),@('LOCAL',$local),@('APPDATA',$appData),@('PROFILE',$profile))){
        $success=$false
        for($try=0;$try -lt 5 -and !$success;$try++){
            $success=Try-Rename $pair[1]
            if(!$success){Start-Sleep -Milliseconds 70}
        }
        if(!$success){throw ('R329_UNPINNED_DIRECTORY_NOT_RENAMEABLE_'+$pair[0])}
        Pass ('BASELINE_RENAME_ALLOWED_'+$pair[0])
    }
    if((Invoke-SeparateActor $local) -ne 61){throw 'R329_CROSS_PROCESS_RENAME_WAS_NOT_POSSIBLE_WITHOUT_PIN'}
    Pass 'BASELINE_SEPARATE_PROCESS_ANCESTOR_RENAME_ALLOWED'
    $args=New-Object 'object[]' 3
    $args[0]=[string]$main
    $args[1]=[string]$appRoot
    $args[2]=[string]$expected
    $pinned=[IO.FileStream]$pinMethod.Invoke($null,$args)
    if(!$pinned.CanRead -or
       ![string]::Equals([IO.Path]::GetFullPath($pinned.Name),
                          [IO.Path]::GetFullPath($main),[StringComparison]::OrdinalIgnoreCase)){
        throw 'R329_REAL_SETUP_DID_NOT_PIN_EXPECTED_MAIN_FILE'
    }
    Pass 'PRODUCTION_METHOD_SHA_PINS_REAL_EMBEDDED_MAIN'
    foreach($pair in @(@('APPROOT',$appRoot),@('LOCAL',$local),@('APPDATA',$appData),@('PROFILE',$profile))){
        if(Try-Rename $pair[1]){throw ('R329_ANCESTOR_RENAME_SUCCEEDED_WHILE_PINNED_'+$pair[0])}
        Pass ('PINNED_MAIN_BLOCKS_RENAME_'+$pair[0])
    }
    if((Invoke-SeparateActor $local) -ne 0){
        throw 'R329_SEPARATE_PROCESS_CAN_RENAME_PINNED_MAIN_ANCESTOR'
    }
    Pass 'PINNED_MAIN_BLOCKS_SEPARATE_PROCESS_LOCAL_RENAME'
    $replacement=$false
    try{$fs=[IO.FileStream]::new($main,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$fs.Dispose()}
    catch [IO.IOException]{$replacement=$true}
    if(!$replacement){throw 'R329_SECOND_FILE_WRITER_NOT_BLOCKED'}
    Pass 'PINNED_MAIN_BLOCKS_SAME_NAME_WRITER'
    $args2=New-Object 'object[]' 2
    $args2[0]=$pinned.PSObject.BaseObject
    $args2[1]=[string]$appRoot
    $processInfo=$psiMethod.Invoke($null,$args2)
    if($processInfo.UseShellExecute -ne $false -or $processInfo.Arguments -cne '' -or
       $processInfo.FileName -cne [IO.Path]::GetFullPath($main)){
        throw 'R329_PINNED_PROCESSSTARTINFO_IDENTITY_CHANGED'
    }
    Pass 'PROCESS_STARTINFO_IS_DIRECT_NO_SHELL_NO_ARGS'
    $pinned.Position=0
    $checkSha=[Security.Cryptography.SHA256]::Create()
    try {$actual=([BitConverter]::ToString($checkSha.ComputeHash($pinned))).Replace('-','')}
    finally {$checkSha.Dispose()}
    if($actual -cne $expected){throw 'R329_PINNED_FILE_BYTES_CHANGED'}
    Pass 'OPEN_FILE_BYTES_STILL_EQUAL_IMMUTABLE_PE_HASH'
    if([IO.File]::ReadAllText($canary) -cne 'NO_EXTERNAL_MODIFICATION'){
        throw 'R329_EXTERNAL_SENTINEL_CHANGED'
    }
    Pass 'EXTERNAL_CANARY_UNMODIFIED'
}finally{if($pinned){$pinned.Dispose()}}
try {
    if(! (Try-Rename $local)){throw 'R329_LOCAL_RENAME_REMAINS_BLOCKED_AFTER_DISPOSAL'}
    Pass 'LOCAL_RENAME_RESTORED_AFTER_PIN_RELEASE'
    $actualSha=(Get-FileHash -LiteralPath $main -Algorithm SHA256).Hash
    if($actualSha -cne $expected){throw 'R329_SANDBOX_FILE_ON_DISK_CHANGED'}
    Pass 'ON_DISK_SHA_STILL_EQUALS_EMBEDDED_MAIN'
    if($checks.Count -ne 19){throw ('R329_ACCEPTANCE_CHECK_COUNT_'+$checks.Count)}
    if($HostLabel -cne 'LOCAL'){
        if($env:GITHUB_ACTIONS -cne 'true' -or
           $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
           $env:RUNNER_OS -cne 'Windows' -or
           $env:GITHUB_SHA -cnotmatch '^[0-9a-f]{40}$' -or
           $env:GITHUB_RUN_ID -cnotmatch '^\d+$'){
            throw 'R329_HOSTED_EVIDENCE_NOT_ON_DISPOSABLE_GITHUB_GUEST'
        }
        $dir=Join-Path $env:RUNNER_TEMP ('R329_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
        if([IO.Directory]::Exists($dir)){throw 'R329_HOSTED_WITNESS_DIRECTORY_ALREADY_PRESENT'}
        [IO.Directory]::CreateDirectory($dir)|Out-Null
        $receipt=[ordered]@{
            Schema=1
            Revision='R329'
            Status='PASS_PRODUCTION_PINNED_MAIN_PREVENTS_SAME_AND_CROSS_PROCESS_RENAME'
            Host=$HostLabel
            SourceCommit=$env:GITHUB_SHA
            SetupSHA256=(Get-FileHash -LiteralPath $SetupPath -Algorithm SHA256).Hash
            MainSHA256=$expected
            Checks=@($checks.ToArray())
            MainExecutableWasLaunched=$false
            OriginalOwnerHostTouched=$false
            ActualUACInvoked=$false
            ProtectedProgramFilesChanged=$false
            SecurityFinalAccepted=$false
            Scope='Windows NTFS normal rename in disposable user-owned directory; no POSIX semantics or UAC acceptance'
        }
        $receiptPath=Join-Path $dir 'R329_PINNED_MAIN_ANCESTOR_RENAME_RECEIPT.json'
        $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($receipt|ConvertTo-Json -Depth 5))
        $output=[IO.FileStream]::new($receiptPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try{$output.Write($bytes,0,$bytes.Length);$output.Flush($true)}
        finally{$output.Dispose()}
        Write-Output ('R329_TYPED_HOSTED_RECEIPT_SHA256='+(Get-FileHash -LiteralPath $receiptPath -Algorithm SHA256).Hash)
    }
    Write-Output ('R329_NATIVE_MAIN_ANCESTOR_RENAME_GUARD_PASS='+$checks.Count+'/19')
}finally{
    if([IO.Directory]::Exists($base) -and
       [IO.Path]::GetFileName($base).StartsWith('tbme_r329_real_setup_main_',[StringComparison]::Ordinal)){
        $reparse=@(Get-ChildItem -LiteralPath $base -Recurse -Force |
            Where-Object {($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0})
        if($reparse.Count -ne 0){throw 'R329_UNEXPECTED_REPARSE_REFUSE_SANDBOX_CLEANUP'}
        [IO.Directory]::Delete($base,$true)
    }
}
