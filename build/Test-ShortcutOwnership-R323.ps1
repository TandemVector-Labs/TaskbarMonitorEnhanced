[CmdletBinding()]
param(
    [string]$SetupPath = '',
    [string]$MainPath = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ([string]::IsNullOrWhiteSpace($SetupPath)) {
    $SetupPath=Join-Path $PSScriptRoot '_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
}
if ([string]::IsNullOrWhiteSpace($MainPath)) {
    $MainPath=Join-Path $PSScriptRoot '_out\App\TaskbarMonitorEnhanced.exe'
}
if (!(Test-Path -LiteralPath $SetupPath -PathType Leaf) -or
    !(Test-Path -LiteralPath $MainPath -PathType Leaf)) {
    throw 'R323_EXACT_COMPILED_EXECUTABLES_REQUIRED'
}
$main=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $MainPath).Path)
$setupExe=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $SetupPath).Path)
$assembly=[Reflection.Assembly]::LoadFrom($setupExe)
$program=$assembly.GetType('SetupProgram',$true)
$method=$program.GetMethod('DeleteOwnedShortcut',[Reflection.BindingFlags]'NonPublic,Static')
if($null -eq $method -or $method.ReturnType -ne [bool]) {
    throw 'R323_OWNED_DELETE_METHOD_MISSING'
}
$base=Join-Path ([IO.Path]::GetTempPath()) ('tbme_r323_shortcuts_'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($base)
$canary=Join-Path $base 'external-user-owned-canary.txt'
[IO.File]::WriteAllText($canary,'PRESERVE-FOREIGN-OWNER')
$passed=0
$total=0
$checked=[Collections.Generic.List[string]]::new()

function Make-Shortcut([string]$name,[string]$target,[string]$shortcutArguments) {
    $dest=Join-Path $base $name
    $shell=New-Object -ComObject WScript.Shell
    $shortcut=$null
    try {
        $shortcut=$shell.CreateShortcut($dest)
        $shortcut.TargetPath=$target
        $shortcut.Arguments=$shortcutArguments
        $shortcut.WorkingDirectory=$base
        $shortcut.Description='R323 DISPOSABLE TEST ONLY'
        $shortcut.Save()
    } finally {
        if ($null -ne $shortcut) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) }
        if ($null -ne $shell) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
    }
    if (!(Test-Path -LiteralPath $dest -PathType Leaf)) {throw ('R323_FIXTURE_SHORTCUT_MISSING_'+$name)}
    return $dest
}

function Invoke-Delete([string]$file,[string]$expected,[string]$shortcutArguments) {
    $call=New-Object 'object[]' 3
    $call[0]=[string]$file
    $call[1]=[string]$expected
    $call[2]=[string]$shortcutArguments
    return [bool]$method.Invoke($null,$call)
}

function Assert-Positive([string]$name,[string]$path,[string]$target,[string]$shortcutArguments) {
    $script:total++
    if(-not (Invoke-Delete $path $target $shortcutArguments) -or
       (Test-Path -LiteralPath $path)) {
        throw ('R323_OWNED_SHORTCUT_NOT_REMOVED_'+$name)
    }
    $script:passed++
    [void]$checked.Add('PASS '+$name)
}

function Assert-Preserve([string]$name,[string]$path,[string]$target,[string]$shortcutArguments,[bool]$exists) {
    $script:total++
    $before=if($exists){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}else{'NONE'}
    if(Invoke-Delete $path $target $shortcutArguments) {
        throw ('R323_FOREIGN_SHORTCUT_WAS_DELETED_'+$name)
    }
    if($exists){
        if(!(Test-Path -LiteralPath $path -PathType Leaf) -or
           (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $before) {
            throw ('R323_USER_FILE_CHANGED_'+$name)
        }
    } elseif(Test-Path -LiteralPath $path){
        throw ('R323_MISSING_SHORTCUT_WAS_CREATED_'+$name)
    }
    $script:passed++
    [void]$checked.Add('PASS '+$name)
}

try {
    $owned=Make-Shortcut 'owned-main.lnk' $main ''
    Assert-Positive 'owned_main_no_arguments' $owned $main ''

    $repair=Make-Shortcut 'owned-repair.lnk' $setupExe '/repair-sensors'
    Assert-Positive 'owned_repair_exact_arguments' $repair $setupExe '/repair-sensors'

    $recovery=Make-Shortcut 'owned-recovery.lnk' $main '--startup-recovery'
    Assert-Positive 'owned_recovery_exact_arguments' $recovery $main '--startup-recovery'

    $foreign=Make-Shortcut 'foreign-target.lnk' "$env:SystemRoot\System32\notepad.exe" ''
    Assert-Preserve 'foreign_target_same_link_name' $foreign $main '' $true

    $wrong=Make-Shortcut 'foreign-argument.lnk' $main '/uninstall'
    Assert-Preserve 'foreign_arguments_same_binary' $wrong $main '--startup-recovery' $true

    $corrupt=Join-Path $base 'corrupt.lnk'
    [IO.File]::WriteAllBytes($corrupt,[byte[]]@(0,7,41,255,18,99))
    Assert-Preserve 'corrupt_link_refused' $corrupt $main '' $true

    $notShortcut=Join-Path $base 'user-custom.txt'
    [IO.File]::WriteAllText($notShortcut,'PRESERVE-USER-TEXT')
    Assert-Preserve 'non_lnk_extension_refused' $notShortcut $main '' $true

    $missing=Join-Path $base 'missing.lnk'
    Assert-Preserve 'missing_link_is_noop' $missing $main '' $false

    $unsafeArgs=Make-Shortcut 'unsafe-expected-arguments.lnk' $main '-EncodedCommand sensitive'
    Assert-Preserve 'unsupported_expected_arguments_refused' $unsafeArgs $main '-EncodedCommand sensitive' $true

    $invalidTarget=Make-Shortcut 'relative-expected-target.lnk' $main ''
    Assert-Preserve 'relative_expected_target_refused' $invalidTarget 'relative.exe' '' $true

    $oversize=Join-Path $base 'oversize.lnk'
    $buffer=New-Object 'byte[]' (1024*1024+1)
    [IO.File]::WriteAllBytes($oversize,$buffer)
    Assert-Preserve 'oversize_lnk_refused' $oversize $main '' $true

    if([IO.File]::ReadAllText($canary) -ne 'PRESERVE-FOREIGN-OWNER') {
        throw 'R323_EXTERNAL_CANARY_CHANGED'
    }
    if($passed -ne 11 -or $total -ne 11) { throw 'R323_NATIVE_CHECK_COUNT_MISMATCH' }
    $checked | ForEach-Object { Write-Output $_ }
    Write-Output ('R323_OWNED_SHORTCUT_NATIVE_PASS='+$passed+'/'+$total)
} finally {
    if(Test-Path -LiteralPath $base) {
        [IO.Directory]::Delete($base,$true)
    }
}
