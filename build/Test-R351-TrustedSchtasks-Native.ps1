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
    throw 'R351_REQUIRES_EXACT_GITHUB_HOSTED_WINDOWS_SOURCE'
}
if(!$MainPath){
    $MainPath=Join-Path $PSScriptRoot '_out\App\TaskbarMonitorEnhanced.exe'
}
if(!(Test-Path -LiteralPath $MainPath -PathType Leaf)){throw 'R351_EXACT_COMPILED_APP_MISSING'}
$asm=[Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $MainPath).Path)
$type=$asm.GetType('TaskbarMonitorEnhanced.SensorSupervisorSelfHeal',$true)
$flags=[Reflection.BindingFlags]'NonPublic,Static'
$resolve=$type.GetMethod('RequireSystemTaskSchedulerPath',$flags)
$build=$type.GetMethod('BuildTaskSchedulerRunProcessInfo',$flags)
if($null -eq $resolve -or $null -eq $build){throw 'R351_EXACT_TRUSTED_COMMAND_METHODS_MISSING'}
$checks=[Collections.Generic.List[string]]::new()
function Pass([string]$name){$script:checks.Add($name);Write-Output ('PASS '+$name)}
function Resolve-Host([string]$system){
    $args=New-Object 'object[]' 1
    $args[0]=$system
    return [string]$resolve.Invoke($null,$args)
}
function Refuse([string]$name,[string]$input){
    $rejected=$false
    try{
        $result=Resolve-Host $input
        throw ('R351_UNTRUSTED_PATH_ACCEPTED_'+$name+'_'+$result)
    }catch{
        $cause=$_.Exception
        while($cause.InnerException){$cause=$cause.InnerException}
        if($cause.Message -like 'R351_UNTRUSTED_PATH_ACCEPTED_*'){throw $cause}
        if($cause -isnot [IO.IOException] -and
           $cause -isnot [ArgumentException] -and
           $cause -isnot [UnauthorizedAccessException]){
            throw ('R351_WRONG_REFUSAL_CLASS_'+$name+'_'+$cause.GetType().FullName)
        }
        $rejected=$true
    }
    if(!$rejected){throw ('R351_FAIL_OPEN_'+$name)}
    Pass $name
}
$real=[IO.Path]::GetFullPath((Join-Path ([Environment]::SystemDirectory) 'schtasks.exe'))
if(!(Test-Path -LiteralPath $real -PathType Leaf)){throw 'R351_SYSTEM_SCHTASKS_NOT_PRESENT'}
if((Resolve-Host ([Environment]::SystemDirectory)) -cne $real){throw 'R351_SYSTEM_EXECUTABLE_NOT_PINNED'}
Pass 'EXACT_CANONICAL_SYSTEM_SCHTASKS'
$psi=[Diagnostics.ProcessStartInfo]$build.Invoke($null,$null)
if($psi.FileName -cne $real -or $psi.UseShellExecute -ne $false -or
   $psi.Verb -cne '' -or $psi.CreateNoWindow -ne $true -or
   !$psi.RedirectStandardOutput -or !$psi.RedirectStandardError -or
   $psi.WorkingDirectory -cne ([Environment]::SystemDirectory) -or
   $psi.Arguments -cne '/Run /TN "TaskbarMonitorEnhanced Sensor Broker"'){
    throw 'R351_REAL_COMPILED_PROCESS_DESCRIPTOR_UNSAFE'
}
Pass 'COMPILED_CREATEPROCESS_DESCRIPTOR_WITH_FIXED_TASK_AND_NO_SHELL'
$fixture=Join-Path $env:RUNNER_TEMP ('tbme_r351_shadow_'+[Guid]::NewGuid().ToString('N'))
if([IO.Directory]::Exists($fixture)){throw 'R351_FIXTURE_COLLISION'}
[IO.Directory]::CreateDirectory($fixture)|Out-Null
$fake=Join-Path $fixture 'schtasks.exe'
[IO.File]::WriteAllText($fake,'R351_FAKE_NEVER_EXECUTED',[Text.UTF8Encoding]::new($false))
$oldPath=$env:PATH
try{
    $env:PATH=$fixture+[IO.Path]::PathSeparator+$oldPath
    $shadow=[Diagnostics.ProcessStartInfo]$build.Invoke($null,$null)
    if($shadow.FileName -cne $real -or
       [IO.File]::ReadAllText($fake) -cne 'R351_FAKE_NEVER_EXECUTED'){
        throw 'R351_PATH_SHADOWING_CHANGED_EXACT_EXE'
    }
    Pass 'HOSTILE_PATH_SHADOW_IGNORED_WITHOUT_PROCESS_LAUNCH'
    Refuse 'RELATIVE_SYSTEM_PARENT_REFUSED' 'relative'
    Refuse 'MISSING_SYSTEM_PARENT_REFUSED' (Join-Path $fixture 'missing')
    Refuse 'EMPTY_SYSTEM_PARENT_REFUSED' ''
}finally{
    $env:PATH=$oldPath
    if([IO.Directory]::Exists($fixture) -and
       [IO.Directory]::GetFileSystemEntries($fixture).Count -eq 1 -and
       [IO.File]::ReadAllText($fake) -ceq 'R351_FAKE_NEVER_EXECUTED'){
        [IO.File]::Delete($fake)
        [IO.Directory]::Delete($fixture,$false)
    }else{
        throw 'R351_TEST_OWNED_FIXTURE_CLEANUP_REFUSED'
    }
}
Pass 'EXACT_OWNED_SHADOW_FIXTURE_REMOVED'
if($checks.Count -ne 7){throw ('R351_CHECK_COUNT_'+$checks.Count)}
'R351_SCHTASKS_EXACT_SYSTEM_HOST_NO_PATH_FALLBACK=7/7'
