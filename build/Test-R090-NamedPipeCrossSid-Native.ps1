[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AssemblyPath)

# R090 — disposable GitHub-hosted Windows ONLY. UAC is disabled on these
# runners: this is a real DIFFERENT-USER SID/DACL denial test, not a UAC test.
# Never invoke on an owner's computer. No persistent credentials, drivers,
# services or protected app files are used; test identity is deleted in finally.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   [IntPtr]::Size -ne 8 -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID) -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'R090_DISPOSABLE_64BIT_HOSTED_WINDOWS_ONLY'
}
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sha=(git -C $project rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0 -or $sha -cne $env:GITHUB_SHA){
    throw 'R090_EXACT_GITHUB_SHA_REQUIRED'
}
$expectedPe=[IO.Path]::GetFullPath((Join-Path $project 'build/_out/Setup/TaskbarMonitorEnhanced_Setup_1.7.8.exe'))
$pe=[IO.Path]::GetFullPath($AssemblyPath)
if(-not [string]::Equals($pe,$expectedPe,[StringComparison]::OrdinalIgnoreCase) -or
   -not(Test-Path -LiteralPath $pe -PathType Leaf)){
    throw 'R090_REAL_BUILT_SETUP_PE_REQUIRED'
}
$me=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($me)
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
    throw 'R090_HOSTED_WINDOWS_ADMIN_ACCOUNT_NOT_PRESENT'
}
if(-not (Get-Command New-LocalUser -ErrorAction SilentlyContinue) -or
   -not (Get-Command Remove-LocalUser -ErrorAction SilentlyContinue)){
    throw 'R090_OFFICIAL_LOCALACCOUNTS_CMDLETS_UNAVAILABLE'
}
$asm=[Reflection.Assembly]::LoadFile($pe)
$t=$asm.GetType('SetupProgram+SensorStatusReceiver',$true)
$pinvoke=@"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class TbmeR090TokenNative
{
    [DllImport("advapi32.dll",EntryPoint="LogonUserW",
       CharSet=CharSet.Unicode,SetLastError=true)]
    public static extern bool LogonUser(string username,string domain,
       string password,int logonType,int provider,out IntPtr token);
    [DllImport("kernel32.dll",SetLastError=true)]
    public static extern bool CloseHandle(IntPtr token);
    // Return the *exact* Win32 CreateFileW security access result: timeout,
    // pipe-busy and general I/O errors do NOT count as access-denied.
    [DllImport("kernel32.dll",EntryPoint="CreateFileW",
       CharSet=CharSet.Unicode,SetLastError=true)]
    public static extern SafeFileHandle CreateFile(
       string fileName,uint desiredAccess,uint shareMode,
       IntPtr securityAttributes,uint creationDisposition,
       uint flagsAndAttributes,IntPtr templateFile);
}
"@
Add-Type -TypeDefinition $pinvoke -ErrorAction Stop
$receiver=[Activator]::CreateInstance($t,$true)
$ctx=$null
$token=[IntPtr]::Zero
$created=$false
$name='tbme90_'+([guid]::NewGuid().ToString('N').Substring(0,8))
try{
    $current=$me.User.Value
    $f=$t.GetField('stream',[Reflection.BindingFlags]'NonPublic,Instance')
    $pipe=[IO.Pipes.NamedPipeServerStream]$f.GetValue($receiver)
    $acl=@($pipe.GetAccessControl().GetAccessRules(
         $true,$false,[Security.Principal.SecurityIdentifier]))
    if($acl.Count -ne 1 -or
       $acl[0].IdentityReference.Value -cne $current -or
       $acl[0].AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow){
        throw 'R090_REAL_PE_PIPE_NOT_EXACT_REQUESTER_SID'
    }
    'R090_REAL_SETUP_PE_ONE_REQUESTER_SID_ONLY_DACL=PASS'
    # Runtime-only random password; NEVER print it, save it, transmit it,
    # store in an artifact, or use any existing credentials.
    $random=[byte[]]::new(28)
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($random)
    $password=('X7!a'+[Convert]::ToBase64String($random).Replace('/','z').Replace('+','y'))
    $secure=ConvertTo-SecureString $password -AsPlainText -Force
    $user=New-LocalUser -Name $name -Password $secure -Description 'Ephemeral GitHub Actions R090 SID boundary test' -AccountExpires ((Get-Date).AddHours(2)) -ErrorAction Stop
    $created=$true
    $sid=$user.SID.Value
    if(-not $sid -or [string]::Equals($sid,$current,[StringComparison]::Ordinal)){
        throw 'R090_ALTERNATE_USER_SID_NOT_DISTINCT'
    }
    'R090_EPHEMERAL_DIFFERENT_LOCAL_ACCOUNT_CREATED=TRUE'
    $pipeName=[string]$t.GetField('Name',[Reflection.BindingFlags]'Public,Instance').GetValue($receiver)
    if($pipeName -notmatch '^tbme_sensor_[a-f0-9]{32}$'){throw 'R090_REAL_RANDOM_PIPE_NAME_INVALID'}
    # R092: a real Windows interactive logon token (a distinct temporary SID)
    # is impersonated synchronously for the EXACT named-pipe CreateFile access
    # check. No second process / user profile / UAC / driver is launched.
    # .NET Framework 4.8 WindowsIdentity.Impersonate requires mandatory Undo.
    $token=[IntPtr]::Zero
    if(-not [TbmeR090TokenNative]::LogonUser($name,$env:COMPUTERNAME,$password,2,0,[ref]$token)){
        $errorCode=[Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw ('R090_LOGONUSER_WIN32_ERROR_'+$errorCode)
    }
    $password=$null
    $ctx=[Security.Principal.WindowsIdentity]::Impersonate($token)
    $kernelStatus=-1
    $pathToPipe='\\.\pipe\'+$pipeName
    # Request the same duplex rights as an actual NamedPipeClientStream.
    $requested=[uint32]3221225472 # GENERIC_READ|GENERIC_WRITE (0xc0000000)
    try{
        $effective=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        if($effective -cne $sid -or $effective -ceq $current){
            throw 'R090_IMPERSONATED_THREAD_OS_SID_NOT_SECOND_ACCOUNT'
        }
        $handle=[TbmeR090TokenNative]::CreateFile(
           $pathToPipe,$requested,[uint32]0,[IntPtr]::Zero,
           [uint32]3,[uint32]0,[IntPtr]::Zero)
        # Marshal.GetLastWin32Error must be captured before closing the handle.
        $kernelStatus=if($handle.IsInvalid){
            [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        }else{0}
        $handle.Dispose()
    }finally{
        $ctx.Undo()
        $ctx.Dispose()
        $ctx=$null
        [void][TbmeR090TokenNative]::CloseHandle($token)
        $token=[IntPtr]::Zero
    }
    if($kernelStatus -ne 5){
        throw ('R090_OTHER_SID_DID_NOT_GET_WIN32_ACCESS_DENIED_5;OS_CODE='+$kernelStatus)
    }
    'R090_OTHER_SID_REAL_KERNEL_ACCESS_DENIED_5=PASS'
    # Positive control is essential: a missing/busy pipe could otherwise
    # be misreported as a security denial. Prove the same endpoint accepts
    # the authorized requester SID immediately afterward.
    $ownHandle=[TbmeR090TokenNative]::CreateFile(
       $pathToPipe,$requested,[uint32]0,[IntPtr]::Zero,
       [uint32]3,[uint32]0,[IntPtr]::Zero)
    $ownerWin32=if($ownHandle.IsInvalid){
        [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    }else{0}
    $ownHandle.Dispose()
    if($ownerWin32 -ne 0){
        throw ('R090_EXPECTED_SAME_SID_PIPE_POSITIVE_CONTROL_FAILED;OS_CODE='+$ownerWin32)
    }
    'R090_ORIGINAL_REQUESTER_SID_CONNECTED_POSITIVE_CONTROL=PASS'
    if([bool]$t.GetProperty('HasResult',[Reflection.BindingFlags]'Public,Instance').GetValue($receiver,$null)){
        throw 'R090_UNAUTHORIZED_FRAME_ADMITTED'
    }
    'R090_WINDOWS_DISTINCT_SID_TOKEN_DENIED_NAMED_PIPE=PASS'
    'R090_REAL_UAC_AND_SEPARATE_PROCESS_UNTESTED=TRUE'
    'R090_BOTH_OWNER_DEVICES_UNTOUCHED=TRUE'
}finally{
    if($ctx){$ctx.Undo();$ctx.Dispose()}
    if($token -ne [IntPtr]::Zero){[void][TbmeR090TokenNative]::CloseHandle($token)}
    $receiver.Dispose()
    if($created){
        Remove-LocalUser -Name $name -ErrorAction Stop
        if(Get-LocalUser -Name $name -ErrorAction SilentlyContinue){
            throw 'R090_EPHEMERAL_ACCOUNT_CLEANUP_FAILED'
        }
        'R090_EPHEMERAL_OTHER_ACCOUNT_REMOVED=PASS'
    }
    $secure=$null
    $password=$null
    $random=$null
}
