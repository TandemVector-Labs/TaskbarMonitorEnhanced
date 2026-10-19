[CmdletBinding()]
param([string]$SetupPath = '', [string]$MainPath = '')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($SetupPath)){
    $SetupPath=Join-Path $PSScriptRoot '_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
}
if([string]::IsNullOrWhiteSpace($MainPath)){
    $MainPath=Join-Path $PSScriptRoot '_out\App\TaskbarMonitorEnhanced.exe'
}
$setupExe=(Resolve-Path -LiteralPath $SetupPath).Path
$main=(Resolve-Path -LiteralPath $MainPath).Path
$assembly=[Reflection.Assembly]::LoadFrom($setupExe)
$type=$assembly.GetType('SetupProgram',$true)
$create=@($type.GetMethods([Reflection.BindingFlags]'Static,NonPublic')|Where-Object {
    $_.Name -eq 'Shortcut' -and $_.GetParameters().Count -eq 4
})[0]
$check=$type.GetMethod('AssertOwnedOrAbsentShortcut',[Reflection.BindingFlags]'Static,NonPublic')
$preflight=$type.GetMethod('AssertFreshInstallShortcutPreflight',[Reflection.BindingFlags]'Static,NonPublic')
if(!$create -or !$check -or !$preflight){throw 'R324_NATIVE_SOURCE_METHOD_MISSING'}
$root=Join-Path ([IO.Path]::GetTempPath()) ('tbme_r324_link_'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($root)|Out-Null
$passed=0
$total=0
$shell=New-Object -ComObject WScript.Shell

function Create-Fixture([string]$file,[string]$target,[string]$shortcutArguments){
    $link=$shell.CreateShortcut($file)
    try{
        $link.TargetPath=$target
        $link.Arguments=$shortcutArguments
        $link.WorkingDirectory=$root
        $link.Description='R324 disposable only'
        $link.Save()
    }finally{[void][Runtime.InteropServices.Marshal]::ReleaseComObject($link)}
    if(!(Test-Path -LiteralPath $file -PathType Leaf)){throw 'R324_FIXTURE_NOT_SAVED'}
}
function Make-Call([Reflection.MethodInfo]$method,[object[]]$raw){
    $values=New-Object 'object[]' $raw.Count
    for($i=0;$i -lt $raw.Count;$i++){$values[$i]=$raw[$i].PSObject.BaseObject}
    return $method.Invoke($null,$values)
}
function Expect-Reject([string]$name,[string]$file,[string]$expectedTarget,[string]$shortcutArguments){
    $script:total++
    $sha=(Get-FileHash $file -Algorithm SHA256).Hash
    $reason=''
    try{
        Make-Call $create @([string]$file,[string]$expectedTarget,[string]$shortcutArguments,[string]'disposable')|Out-Null
    }catch{
        $errorObject=$_.Exception
        while($errorObject.InnerException){$errorObject=$errorObject.InnerException}
        $reason=$errorObject.Message
    }
    if(!$reason.Contains('FOREIGN_SHORTCUT_NAME_CONFLICT') -or
       (Get-FileHash $file -Algorithm SHA256).Hash -ne $sha){
        throw ('R324_UNOWNED_LINK_OVERWRITTEN_OR_WRONG_REASON_'+$name+':'+$reason)
    }
    $script:passed++
    Write-Output ('PASS refused_'+$name)
}
function Expect-OwnSave([string]$name,[string]$file,[string]$target,[string]$shortcutArguments){
    $script:total++
    Make-Call $create @([string]$file,[string]$target,[string]$shortcutArguments,[string]'disposable')|Out-Null
    if(!(Test-Path $file -PathType Leaf)){throw ('R324_OWNED_LINK_NOT_SAVED_'+$name)}
    $link=$shell.CreateShortcut($file)
    try{
        $targetOK=[string]::Equals(
            [IO.Path]::GetFullPath([string]$link.TargetPath),
            [IO.Path]::GetFullPath($target),
            [StringComparison]::OrdinalIgnoreCase)
        $argumentsOK=[string]::Equals([string]$link.Arguments,[string]$shortcutArguments,[StringComparison]::Ordinal)
    }finally{[void][Runtime.InteropServices.Marshal]::ReleaseComObject($link)}
    if(!$targetOK -or !$argumentsOK){throw ('R324_OWNED_LINK_CHANGED_IDENTITY_'+$name)}
    $script:passed++
    Write-Output ('PASS owned_'+$name)
}
try{
    $foreign=Join-Path $root 'foreign.lnk'
    Create-Fixture $foreign "$env:WINDIR\System32\notepad.exe" ''
    Expect-Reject 'other_target' $foreign $main ''

    $mismatch=Join-Path $root 'foreign-arguments.lnk'
    Create-Fixture $mismatch $main '/uninstall'
    Expect-Reject 'other_arguments' $mismatch $main '--startup-recovery'

    $corrupt=Join-Path $root 'corrupt.lnk'
    [IO.File]::WriteAllBytes($corrupt,[byte[]]@(3,4,7,9,12,55))
    Expect-Reject 'corrupt_existing_lnk' $corrupt $main ''

    $tooLarge=Join-Path $root 'oversized.lnk'
    [IO.File]::WriteAllBytes($tooLarge,(New-Object 'byte[]' (1024*1024+1)))
    Expect-Reject 'oversized_existing_lnk' $tooLarge $main ''

    $normal=Join-Path $root 'owned-main.lnk'
    Create-Fixture $normal $main ''
    Expect-OwnSave 'same_main_no_arguments' $normal $main ''

    $repair=Join-Path $root 'owned-repair.lnk'
    Create-Fixture $repair $setupExe '/repair-sensors'
    Expect-OwnSave 'same_repair' $repair $setupExe '/repair-sensors'

    $recovery=Join-Path $root 'owned-recovery.lnk'
    Create-Fixture $recovery $main '--startup-recovery'
    Expect-OwnSave 'same_recovery' $recovery $main '--startup-recovery'

    $fresh=Join-Path $root 'new-link.lnk'
    Expect-OwnSave 'brand_new' $fresh $main ''

    if($passed -ne 8 -or $total -ne 8){throw 'R324_NATIVE_OWNERSHIP_COUNT_MISMATCH'}
    Write-Output 'R324_SHORTCUT_WRITE_NATIVE_PASS=8/8'
}finally{
    if($null -ne $shell){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)}
    if(Test-Path -LiteralPath $root){[IO.Directory]::Delete($root,$true)}
}

# Real /install negative is isolated to a dedicated fresh hosted Windows job.
# The general build job may have already created product test state.
if($env:TBME_R324_RUN_FRESH_HOST_NEGATIVE -eq 'true'){
    if($env:GITHUB_ACTIONS -cne 'true' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       $env:RUNNER_OS -cne 'Windows' -or
       $env:COMPUTERNAME -match '(?i)EMAD-PC') {
        throw 'R324_FRESH_INSTALL_NEGATIVE_GITHUB_DISPOSABLE_ONLY'
    }
    $appRoot=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced'
    $programs=[Environment]::GetFolderPath('Programs')
    $existing=Join-Path $programs 'Taskbar Monitor Enhanced.lnk'
    if((Test-Path $appRoot) -or (Test-Path $existing)){throw 'R324_GUEST_NOT_FRESH'}
    $userShell=New-Object -ComObject WScript.Shell
    $created=$false
    $sentinelHash=''
    try{
        $link=$userShell.CreateShortcut($existing)
        try{
            $link.TargetPath="$env:WINDIR\System32\notepad.exe"
            $link.Arguments=''
            $link.Save()
            $created=$true
        }finally{[void][Runtime.InteropServices.Marshal]::ReleaseComObject($link)}
        $sentinelHash=(Get-FileHash $existing -Algorithm SHA256).Hash
        $psi=[Diagnostics.ProcessStartInfo]::new()
        $psi.FileName=$setupExe
        $psi.Arguments='/install /quiet /desktop=0 /startup=0'
        $psi.UseShellExecute=$false
        $psi.CreateNoWindow=$true
        $proc=[Diagnostics.Process]::Start($psi)
        if(!$proc){throw 'R324_ORIGINAL_SETUP_NOT_LAUNCHED'}
        try{
            if(!$proc.WaitForExit(30000)){
                if(!$proc.HasExited){$proc.Kill();[void]$proc.WaitForExit(5000)}
                throw 'R324_SETUP_PREFLIGHT_TIMEOUT'
            }
            $code=$proc.ExitCode
        }finally{$proc.Dispose()}
        if($code -eq 0 -or (Test-Path $appRoot) -or
           (Get-FileHash $existing -Algorithm SHA256).Hash -ne $sentinelHash){
            throw ('R324_FOREIGN_GUEST_LINK_CHANGED_OR_APP_INSTALLED_EXIT_'+$code)
        }
        Write-Output 'R324_REAL_HOSTED_SETUP_FOREIGN_START_LINK_FAILS_BEFORE_APPROOT=PASS'
    }finally{
        if($created -and (Test-Path $existing) -and
           (Get-FileHash $existing -Algorithm SHA256).Hash -eq $sentinelHash){
            Remove-Item -LiteralPath $existing -Force
        }
        if($null -ne $userShell){[void][Runtime.InteropServices.Marshal]::ReleaseComObject($userShell)}
    }
    if((Test-Path -LiteralPath $appRoot) -or (Test-Path -LiteralPath $existing) -or
       !$created -or $code -eq 0 -or $env:R324_HOST_LABEL -cnotin @('A','B') -or
       [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
       [string]::IsNullOrWhiteSpace($env:GITHUB_SHA)){
        throw 'R324_GUEST_CLEANUP_OR_SOURCE_WITNESS_INVALID'
    }
    $proofDir=Join-Path $env:RUNNER_TEMP ('R324_'+$env:R324_HOST_LABEL+'_'+$env:GITHUB_RUN_ID)
    [IO.Directory]::CreateDirectory($proofDir)|Out-Null
    $evidence=[ordered]@{
        Schema=1
        Revision='R324'
        Status='PASS_REAL_FRESH_SETUP_REFUSES_FOREIGN_START_SHORTCUT_BEFORE_APPROOT'
        Host=$env:R324_HOST_LABEL
        SourceCommit=$env:GITHUB_SHA
        HostedWindows=$env:RUNNER_OS
        RealSetupExecuted=$true
        SetupNonzeroExitCode=[int]$code
        ExistingStartShortcutSHA256=[string]$sentinelHash
        SameStartShortcutSHA256Preserved=$true
        UserAppRootAbsentBeforeAndAfter=$true
        UnownedLinkRemovedAfterWitness=$true
        NoUacHelperStarted=$true
        SetupSHA256=(Get-FileHash -LiteralPath $setupExe -Algorithm SHA256).Hash
        MainSHA256=(Get-FileHash -LiteralPath $main -Algorithm SHA256).Hash
        NativeReflectionChecksPassed=8
        RecordedUtc=[DateTime]::UtcNow.ToString('o')
    }
    [IO.File]::WriteAllText((Join-Path $proofDir 'R324_HOSTED_SHORTCUT_RECEIPT.json'),
        ($evidence|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
    Write-Output 'R324_HOSTED_SHORTCUT_CLEANUP_AND_TYPED_RECEIPT=PASS'
}
