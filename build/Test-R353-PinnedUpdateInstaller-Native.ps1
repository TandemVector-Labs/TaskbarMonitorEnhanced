[CmdletBinding()]
param([string]$MainPath='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'Usefull-Skills/TaskbarMonitorEnhanced' -or
   (git rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){
    throw 'R353_REQUIRES_EXACT_GITHUB_HOSTED_WINDOWS_AND_SOURCE'
}
if(!$MainPath){$MainPath=Join-Path $PSScriptRoot '_out\App\TaskbarMonitorEnhanced.exe'}
if(!(Test-Path -LiteralPath $MainPath -PathType Leaf)){throw 'R353_EXACT_COMPILED_APP_NOT_AVAILABLE'}
$asm=[Reflection.Assembly]::LoadFrom((Resolve-Path $MainPath).Path)
$type=$asm.GetType('TaskbarMonitorEnhanced.UpdateManager',$true)
$flags=[Reflection.BindingFlags]'NonPublic,Static,Public'
$pinMethod=$type.GetMethod('OpenPinnedVerifiedUpdateInstaller',$flags)
$buildMethod=$type.GetMethod('BuildPinnedUpdateInstallerProcessInfo',$flags)
if(!$pinMethod -or !$buildMethod){throw 'R353_CURRENT_APP_PINNED_UPDATE_FACTORIES_MISSING'}
$checks=[Collections.Generic.List[string]]::new()
function Pass([string]$name){$script:checks.Add($name);Write-Output ('PASS '+$name)}
function Pin([string]$candidate,[string]$sha,[string]$root){
    $invokeArgs=[object[]]@([string]$candidate,[string]$sha,[string]$root)
    return [IO.FileStream]$pinMethod.Invoke($null,$invokeArgs)
}
function Refuse([string]$name,[string]$candidate,[string]$sha,[string]$root){
    $wasRejected=$false
    try{
        $maybe=Pin $candidate $sha $root
        if($maybe){$maybe.Dispose()}
        throw ('R353_UNSAFE_PIN_ACCEPTED_'+$name)
    }catch{
        $cause=$_.Exception
        while($cause.InnerException){$cause=$cause.InnerException}
        if($cause.Message -like 'R353_UNSAFE_PIN_ACCEPTED_*'){throw $cause}
        if($cause -isnot [IO.InvalidDataException] -and
           $cause -isnot [IO.IOException] -and
           $cause -isnot [ArgumentException] -and
           $cause -isnot [UnauthorizedAccessException]){
            throw ('R353_UNEXPECTED_REFUSAL_CLASS_'+$name+'_'+$cause.GetType().FullName)
        }
        $wasRejected=$true
    }
    if(!$wasRejected){throw ('R353_FAIL_OPEN_'+$name)}
    Pass $name
}
Pass 'EXACT_COMPILED_NETFRAMEWORK_UPDATE_FACTORIES'
$temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP)
if(![IO.Path]::IsPathRooted($temp)){throw 'R353_TEMP_ROOT_NOT_ABSOLUTE'}
$fixture=Join-Path $temp ('tbme_r353_update_'+[guid]::NewGuid().ToString('N'))
if([IO.Directory]::Exists($fixture)){throw 'R353_FIXTURE_ALREADY_EXISTS'}
[IO.Directory]::CreateDirectory($fixture)|Out-Null
$updates=Join-Path $fixture 'Updates'
$foreign=Join-Path $fixture 'Foreign'
[IO.Directory]::CreateDirectory($updates)|Out-Null
[IO.Directory]::CreateDirectory($foreign)|Out-Null
$file=Join-Path $updates 'TaskbarMonitorEnhanced_Setup_1.9.9.exe'
$other=Join-Path $foreign 'TaskbarMonitorEnhanced_Setup_1.9.9.exe'
$unsafe=Join-Path $updates 'unversioned.exe'
$canary=Join-Path $foreign 'FOREIGN_READONLY_CANARY.txt'
$bytes=[byte[]]::new(4096)
for($i=0;$i -lt $bytes.Length;$i++){$bytes[$i]=[byte](($i*73+11)%256)}
[IO.File]::WriteAllBytes($file,$bytes)
[IO.File]::WriteAllBytes($other,$bytes)
[IO.File]::WriteAllBytes($unsafe,$bytes)
[IO.File]::WriteAllText($canary,'R353_FOREIGN_CANARY_UNCHANGED',[Text.UTF8Encoding]::new($false))
$sha='sha256:'+(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
$pin=$null
try{
    $pin=Pin $file $sha $updates
    if(!$pin.CanRead -or
       ![string]::Equals($pin.Name,$file,[StringComparison]::OrdinalIgnoreCase) -or
       (Get-FileHash -InputStream $pin -Algorithm SHA256).Hash -cne $sha.Substring(7).ToUpperInvariant()){
        throw 'R353_VERIFIED_OPEN_FILE_DESCRIPTOR_NOT_SHA_IDENTICAL'
    }
    $pin.Position=0
    Pass 'EXACT_SHA256_VERSIONED_UPDATE_LEAF_PINNED_READ_ONLY'
    $buildArgs=[object[]]@($pin,[string]$updates)
    $descriptor=[Diagnostics.ProcessStartInfo]$buildMethod.Invoke($null,$buildArgs)
    if($descriptor.FileName -cne $file -or
       $descriptor.Arguments -cne '' -or
       $descriptor.UseShellExecute -ne $true -or
       $descriptor.Verb -cne '' -or
       $descriptor.ErrorDialog -ne $false){
        throw 'R353_UPDATE_COMMAND_NOT_SHA_BOUND_SHELL_LITERAL'
    }
    Pass 'SAFE_PROCESSSTART_DESCRIPTOR_FROM_PINNED_HANDLE_NOT_EXECUTED'

    $blockedWrite=$false
    try{
        $handle=[IO.FileStream]::new($file,[IO.FileMode]::Open,
                                    [IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
        $handle.Dispose()
    }catch [IO.IOException]{$blockedWrite=$true}
     catch [UnauthorizedAccessException]{$blockedWrite=$true}
    if(!$blockedWrite){throw 'R353_SECOND_WRITER_OPENED_A_SHA_PINNED_EXECUTABLE'}
    Pass 'SECOND_WRITER_REFUSED_WHILE_SHA_PINNED'

    $blockedDelete=$false
    try{[IO.File]::Delete($file)}
    catch [IO.IOException]{$blockedDelete=$true}
    catch [UnauthorizedAccessException]{$blockedDelete=$true}
    if(!$blockedDelete -or -not [IO.File]::Exists($file)){
        throw 'R353_DELETION_OR_RENAME_RIGHT_WAS_NOT_BLOCKED'
    }
    Pass 'DELETE_ACCESS_REFUSED_WHILE_SHA_PINNED'

    Refuse 'MALFORMED_SHA_REFUSED' $file 'sha256:INVALID' $updates
    Refuse 'FOREIGN_DIRECTORY_REFUSED' $other $sha $updates
    Refuse 'NONVERSIONED_FILENAME_REFUSED' $unsafe $sha $updates
    Refuse 'RELATIVE_ROOT_REFUSED' $file $sha 'relative-root'
}finally{
    if($pin){$pin.Dispose()}
}
$pin=$null

# R354: verify the pinned ShellExecute descriptor can actually start a
# deterministic, self-exiting .NET Framework fixture (never the real
# installer). The test runs *only* on ephemeral GitHub-hosted Windows.
$probe=Join-Path $updates 'TaskbarMonitorEnhanced_Setup_2.0.0.exe'
if([IO.File]::Exists($probe)){throw 'R354_EXEC_FIXTURE_COLLISION'}
$inertProgram=@'
public static class R354ZeroSideEffectExitFixture {
    public static int Main() { return 27; }
}
'@
Add-Type -TypeDefinition $inertProgram -OutputType ConsoleApplication -OutputAssembly $probe -ErrorAction Stop|Out-Null
if(![IO.File]::Exists($probe)){throw 'R354_BOUNDED_INERT_PE_NOT_COMPILED'}
$probeSha='sha256:'+(Get-FileHash -LiteralPath $probe -Algorithm SHA256).Hash.ToLowerInvariant()
$launchPin=$null
$child=$null
try {
    $launchPin=Pin $probe $probeSha $updates
    $launchArgs=[object[]]@($launchPin,[string]$updates)
    $startInfo=[Diagnostics.ProcessStartInfo]$buildMethod.Invoke($null,$launchArgs)
    # R355: reflection only. Never execute a test fixture with runas/UAC.
    $repairMethod=$type.GetMethod('BuildPinnedRepairProcessInfo',$flags)
    if(!$repairMethod){throw 'R355_REPAIR_PROCESS_FACTORY_MISSING_FROM_CURRENT_PE'}
    $repairDescriptor=[Diagnostics.ProcessStartInfo]$repairMethod.Invoke($null,$launchArgs)
    if($repairDescriptor.FileName -cne $probe -or
       $repairDescriptor.Arguments -cne '/repair-sensors' -or
       $repairDescriptor.Verb -cne 'runas' -or
       !$repairDescriptor.UseShellExecute -or
       $repairDescriptor.ErrorDialog -ne $false){
        throw 'R355_REPAIR_DESCRIPTOR_NOT_BOUND_TO_SHA_PINNED_CURRENT_SETUP'
    }
    Pass 'REPAIR_RUNAS_DESCRIPTOR_SHA_PINNED_NO_UAC_TEST_EXECUTION'
    if($startInfo.FileName -cne $probe -or
       $startInfo.UseShellExecute -ne $true -or
       $startInfo.Arguments -cne ''){
        throw 'R354_NOOP_BINARY_NOT_STARTING_FROM_EXACT_PIN'
    }
    $startInfo.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    $child=[Diagnostics.Process]::Start($startInfo)
    if(!$child){throw 'R354_NOOP_PROCESS_CREATION_FAILED'}
    if(-not $child.WaitForExit(10000)){
        try{$child.Kill()}catch{}
        throw 'R354_NOOP_PROCESS_UNEXPECTED_TIMEOUT'
    }
    if($child.ExitCode -ne 27){throw ('R354_NOOP_PROCESS_WRONG_EXIT_'+$child.ExitCode)}
    Pass 'INERT_COMPILED_NET48_EXE_STARTED_WHILE_SHA_PINNED'
}finally{
    if($child){
        if(-not $child.HasExited){try{$child.Kill()}catch{}}
        $child.Dispose()
    }
    if($launchPin){$launchPin.Dispose()}
}

[IO.File]::AppendAllText($file,'TEST_ONLY_NEW_BYTES')
Refuse 'RELEASED_FILE_TAMPER_SHA_REFUSED' $file $sha $updates
if([IO.File]::ReadAllText($canary) -cne 'R353_FOREIGN_CANARY_UNCHANGED'){
    throw 'R353_FOREIGN_CANARY_CHANGED'
}
Pass 'FOREIGN_CANARY_PRESERVED'
foreach($ownedFile in @($file,$other,$unsafe,$canary,$probe)){
    if((Get-Item -LiteralPath $ownedFile -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){
        throw 'R353_UNKNOWN_REPARSE_OWNED_FILE'
    }
    [IO.File]::Delete($ownedFile)
}
[IO.Directory]::Delete($updates,$false)
[IO.Directory]::Delete($foreign,$false)
[IO.Directory]::Delete($fixture,$false)
Pass 'TEST_OWNED_RUNNER_TEMP_FIXTURE_REMOVED'
if($checks.Count -ne 14){throw ('R353_CHECK_COUNT_MISMATCH_'+$checks.Count)}
'R353_R354_R355_PINNED_UPDATE_LAUNCH_NATIVE_PASS=14/14'
