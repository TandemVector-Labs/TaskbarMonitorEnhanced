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
    throw 'R352_ONLY_EXACT_GITHUB_HOSTED_WINDOWS'
}
if(!$MainPath){$MainPath=Join-Path $PSScriptRoot '_out\App\TaskbarMonitorEnhanced.exe'}
if(!(Test-Path -LiteralPath $MainPath -PathType Leaf)){throw 'R352_MAIN_PE_REQUIRED'}
$asm=[Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $MainPath).Path)
$type=$asm.GetType('TaskbarMonitorEnhanced.WindowsShellCommands',$true)
$flags=[Reflection.BindingFlags]'NonPublic,Static,Public'
$pin=$type.GetMethod('RequireSystemExecutable',$flags)
$explorer=$type.GetMethod('Explorer',$flags)
$manager=$type.GetMethod('TaskManager',$flags)
if(!$pin -or !$explorer -or !$manager){throw 'R352_WINDOWS_TOOLS_FACTORIES_NOT_COMPILED'}
$checks=[Collections.Generic.List[string]]::new()
function Pass([string]$name){$script:checks.Add($name);Write-Output ('PASS '+$name)}
function Reject([string]$name,[string]$folder,[string]$file){
    $invokeArgs=[object[]]@([string]$folder,[string]$file)
    $rejected=$false
    try{
        $value=$pin.Invoke($null,$invokeArgs)
        throw ('R352_UNTRUSTED_HOST_ACCEPTED_'+$name+'_'+$value)
    }catch{
        $e=$_.Exception
        while($e.InnerException){$e=$e.InnerException}
        if($e.Message -like 'R352_UNTRUSTED_HOST_ACCEPTED_*'){throw $e}
        if($e -isnot [IO.InvalidDataException] -and
           $e -isnot [IO.IOException] -and $e -isnot [ArgumentException]){
            throw ('R352_WRONG_REFUSAL_CLASS_'+$name+'_'+$e.GetType().FullName)
        }
        $rejected=$true
    }
    if(!$rejected){throw ('R352_FAIL_OPEN_'+$name)}
    Pass $name
}
$sys=[IO.Path]::GetFullPath((Join-Path ([Environment]::SystemDirectory) 'Taskmgr.exe'))
$win=[IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('Windows')) 'explorer.exe'))
foreach($f in @($sys,$win)){if(!(Test-Path -LiteralPath $f -PathType Leaf)){throw 'R352_OS_EXE_MISSING'}}
$tm=[Diagnostics.ProcessStartInfo]$manager.Invoke($null,$null)
$logPath=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TaskbarMonitorEnhanced\Logs'
$invokeArgs=[object[]]@([string]$logPath)
$ex=[Diagnostics.ProcessStartInfo]$explorer.Invoke($null,$invokeArgs)
if($tm.FileName -cne $sys -or !$tm.UseShellExecute -or $tm.Arguments -cne ''){
    throw 'R352_PINNED_TASK_MANAGER_DESCRIPTOR_INVALID'
}
Pass 'TRUSTED_SYSTEM_TASKMGR_DESCRIPTOR_NO_PROCESS_START'
if($ex.FileName -cne $win -or !$ex.UseShellExecute -or
   $ex.Arguments -cne ('"'+[IO.Path]::GetFullPath($logPath)+'"')){
    throw 'R352_PINNED_EXPLORER_DESCRIPTOR_INVALID'
}
Pass 'TRUSTED_WINDOWS_EXPLORER_AND_QUOTED_LITERAL_TARGET'
$fixture=Join-Path $env:RUNNER_TEMP ('tbme_r352_path_shadow_'+[Guid]::NewGuid().ToString('N'))
if(Test-Path -LiteralPath $fixture){throw 'R352_TEST_FIXTURE_OCCUPIED'}
[IO.Directory]::CreateDirectory($fixture)|Out-Null
$shadow1=Join-Path $fixture 'explorer.exe'
$shadow2=Join-Path $fixture 'Taskmgr.exe'
[IO.File]::WriteAllText($shadow1,'R352_FOREIGN_EXPLORER_CANARY')
[IO.File]::WriteAllText($shadow2,'R352_FOREIGN_TASKMGR_CANARY')
$prior=$env:PATH
try{
    $env:PATH=$fixture+[IO.Path]::PathSeparator+$prior
    $shadowedExplorer=[Diagnostics.ProcessStartInfo]$explorer.Invoke($null,$invokeArgs)
    $shadowedManager=[Diagnostics.ProcessStartInfo]$manager.Invoke($null,$null)
    if($shadowedExplorer.FileName -cne $win -or $shadowedManager.FileName -cne $sys -or
       [IO.File]::ReadAllText($shadow1) -cne 'R352_FOREIGN_EXPLORER_CANARY' -or
       [IO.File]::ReadAllText($shadow2) -cne 'R352_FOREIGN_TASKMGR_CANARY'){
       throw 'R352_UNTRUSTED_PATH_OVERRIDES_OS_TOOL'
    }
    Pass 'HOSTILE_PATH_SHADOW_IGNORED_NO_EXECUTION'
    Reject 'RELATIVE_FOLDER_REFUSED' 'relative' 'explorer.exe'
    Reject 'MISSING_FOLDER_REFUSED' (Join-Path $fixture 'missing') 'explorer.exe'
    Reject 'UNWHITELISTED_EXE_REFUSED' ([Environment]::SystemDirectory) 'cmd.exe'
}finally{
    $env:PATH=$prior
    if(([IO.Directory]::GetFileSystemEntries($fixture).Count -eq 2) -and
        [IO.File]::ReadAllText($shadow1) -ceq 'R352_FOREIGN_EXPLORER_CANARY' -and
        [IO.File]::ReadAllText($shadow2) -ceq 'R352_FOREIGN_TASKMGR_CANARY'){
        [IO.File]::Delete($shadow1)
        [IO.File]::Delete($shadow2)
        [IO.Directory]::Delete($fixture,$false)
    }else{throw 'R352_OWNED_TEST_CLEANUP_REFUSED'}
}
Pass 'FOREIGN_FAKE_EXECUTABLES_REMOVED_WITHOUT_LAUNCH'
if($checks.Count -ne 7){throw ('R352_CHECK_COUNT_'+$checks.Count)}
'R352_PINNED_UI_SYSTEM_TOOLS_NO_PATH_SHADOW=7/7'
