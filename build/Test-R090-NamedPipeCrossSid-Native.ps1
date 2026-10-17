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
$receiver=[Activator]::CreateInstance($t,$true)
$child=$null
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
    $password=$null
    $user=New-LocalUser -Name $name -Password $secure -Description 'Ephemeral GitHub Actions R090 SID boundary test' -AccountExpires ((Get-Date).AddHours(2)) -ErrorAction Stop
    $created=$true
    $sid=$user.SID.Value
    if(-not $sid -or [string]::Equals($sid,$current,[StringComparison]::Ordinal)){
        throw 'R090_ALTERNATE_USER_SID_NOT_DISTINCT'
    }
    'R090_EPHEMERAL_DIFFERENT_LOCAL_ACCOUNT_CREATED=TRUE'
    $pipeName=[string]$t.GetField('Name',[Reflection.BindingFlags]'Public,Instance').GetValue($receiver)
    if($pipeName -notmatch '^tbme_sensor_[a-f0-9]{32}$'){throw 'R090_REAL_RANDOM_PIPE_NAME_INVALID'}
    $encodedCurrent=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($current))
    $encodedAlternate=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sid))
    $clientSource=@'
$ErrorActionPreference='Stop'
$current=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__CURRENT__'))
$expected=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__ALTERNATE__'))
$actual=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($actual -cne $expected -or $actual -ceq $current){exit 43}
$c=[IO.Pipes.NamedPipeClientStream]::new('.','__PIPE__',[IO.Pipes.PipeDirection]::InOut)
try{
    $c.Connect(3500)
    # An unexpected successful connection is a security regression.
    exit 41
}catch [UnauthorizedAccessException]{
    exit 42
}catch [IO.IOException]{
    exit 42
}catch [TimeoutException]{
    exit 42
}catch{
    exit 44
}finally{
    $c.Dispose()
}
'@
    $clientSource=$clientSource.Replace('__CURRENT__',$encodedCurrent).Replace('__ALTERNATE__',$encodedAlternate).Replace('__PIPE__',$pipeName)
    $code=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($clientSource))
    $ps=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
    $cred=[Management.Automation.PSCredential]::new(($env:COMPUTERNAME+'\'+$name),$secure)
    $child=Start-Process -FilePath $ps -Credential $cred -ArgumentList ('-NoProfile -NonInteractive -EncodedCommand '+$code) -WorkingDirectory $env:SystemRoot -PassThru -WindowStyle Hidden -ErrorAction Stop
    if(-not $child){throw 'R090_ALTERNATE_PROCESS_UNAVAILABLE'}
    if(-not $child.WaitForExit(12000)){
        try{$child.Kill()}catch{}
        throw 'R090_OTHER_USER_PROCESS_TIMEOUT'
    }
    if($child.ExitCode -eq 43){throw 'R090_OTHER_USER_PROCESS_SID_ASSERTION_FAILED'}
    if($child.ExitCode -eq 41){throw 'R090_WRONG_SID_CONNECTED_TO_REQUESTER_PIPE'}
    if($child.ExitCode -ne 42){throw ('R090_OTHER_USER_PROCESS_UNEXPECTED_EXIT_'+$child.ExitCode)}
    if([bool]$t.GetProperty('HasResult',[Reflection.BindingFlags]'Public,Instance').GetValue($receiver,$null)){
        throw 'R090_UNAUTHORIZED_FRAME_WAS_ADMITTED'
    }
    'R090_OS_DIFFERENT_SID_CLIENT_DENIED_PIPE=PASS'
    'R090_UAC_CONSENT_AND_ELEVATED_CHILD_NOT_TESTED=TRUE'
    'R090_BOTH_OWNER_DEVICES_UNTOUCHED=TRUE'
}finally{
    if($child){
        if(-not $child.HasExited){try{$child.Kill();$child.WaitForExit(3000)|Out-Null}catch{}}
        $child.Dispose()
    }
    $receiver.Dispose()
    if($created){
        Remove-LocalUser -Name $name -ErrorAction Stop
        if(Get-LocalUser -Name $name -ErrorAction SilentlyContinue){
            throw 'R090_EPHEMERAL_ACCOUNT_CLEANUP_FAILED'
        }
        'R090_EPHEMERAL_OTHER_ACCOUNT_REMOVED=PASS'
    }
    $secure=$null
    $random=$null
}
