[CmdletBinding()]
param([string]$SetupPath='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($SetupPath)){
    $SetupPath=Join-Path $PSScriptRoot '_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
}
if($PSVersionTable.PSEdition -cne 'Desktop' -or
    !(Test-Path -LiteralPath $SetupPath -PathType Leaf)){
    throw 'R328_EXACT_COMPILED_FRAMEWORK_SETUP_REQUIRED'
}
$helper=(Resolve-Path (Join-Path $PSScriptRoot '..\installer\TBME_Setup_Elevated_Helper.ps1')).Path
$embeddedAssembly=[Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $SetupPath).Path)
$stream=$embeddedAssembly.GetManifestResourceStream('Payload.TBME_Setup_Elevated_Helper.ps1')
if(!$stream){throw 'R328_HELPER_PE_RESOURCE_NOT_FOUND'}
$reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8)
try{$embedded=$reader.ReadToEnd()}finally{$reader.Dispose()}
$source=[IO.File]::ReadAllText($helper)
$normalized={param($x) $x.Replace(([string][char]13+[string][char]10),[string][char]10).TrimStart([char]0xFEFF).TrimEnd()}
if((& $normalized $embedded) -cne (& $normalized $source)){throw 'R328_HELPER_PE_RESOURCE_NOT_IDENTICAL'}
$script:checks=[Collections.Generic.List[string]]::new()
function Pass([string]$name){
    $script:checks.Add($name)
    Write-Output ('PASS '+$name)
}
Pass 'EXACT_SETUP_PE_EMBEDS_TRUSTED_HELPER_SOURCE'
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($helper,[ref]$tokens,[ref]$parseErrors)
if(@($parseErrors).Count -ne 0){throw 'R328_TRUSTED_HELPER_AST_PARSE_ERRORS'}
$native=[regex]::Matches($source,'(?s)Add-Type -TypeDefinition @''\r?\n(.*?)\r?\n''@')
if($native.Count -ne 1){throw 'R335_NATIVE_CLASS_SOURCE_NOT_UNIQUE'}
Add-Type -TypeDefinition $native[0].Groups[1].Value
if($null -eq ('TBMEScopedUserLogLease' -as [type])){throw 'R335_EXPECTED_PRODUCTION_CLASS_NOT_COMPILED'}
foreach($fn in @('Assert-SensorBoundaryNoReparse','Assert-SensorUserLogSink','Write-Log','Write-Result')){
    $definition=@($ast.FindAll({param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst]},$true)|
        Where-Object Name -EQ $fn)
    if($definition.Count -ne 1){throw ('R328_FUNCTION_NOT_EXACTLY_ONE_'+$fn)}
    . ([scriptblock]::Create($definition[0].Extent.Text))
}
$base=Join-Path ([IO.Path]::GetTempPath()) ('tbme_r328_logs_'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($base)|Out-Null
$profile=Join-Path $base 'isolated profile with & $special'
$AppRoot=Join-Path $profile 'AppData\Local\TaskbarMonitorEnhanced'
[IO.Directory]::CreateDirectory($AppRoot)|Out-Null
$script:ValidatedSensorProfileRoot=$profile
$LogsRoot=Join-Path $AppRoot 'Logs'
[IO.Directory]::CreateDirectory($LogsRoot)|Out-Null
$ResultPath=Join-Path $LogsRoot 'sensor_install_result.json'
$LogPath=Join-Path $LogsRoot 'sensor_install.log'
$external=Join-Path $base 'external-canary-data'
[IO.Directory]::CreateDirectory($external)|Out-Null
$canary=Join-Path $external 'NEVER_TOUCH.txt'
[IO.File]::WriteAllText($canary,'R328_CANARY_UNCHANGED')
$SupervisorHealthy=$false
$CpuTransportHealthy=$false
$GpuTransportHealthy=$false
$StorageTransportHealthy=$false
$CpuDataAvailable=$false
$RollbackPerformed=$false
$RollbackSucceeded=$false
$PreviousSensorLayerPresent=$false
$ActiveArchitecture='R328_ISOLATED_NATIVE_TEST_ONLY'

function Expect-Refusal([string]$name,[scriptblock]$action,[string]$reason){
    $text=''
    try{
        & $action|Out-Null
        throw ('R328_FAIL_OPEN_'+$name)
    }catch{
        $errorObject=$_.Exception
        while($null -ne $errorObject.InnerException){$errorObject=$errorObject.InnerException}
        $text=$errorObject.Message
    }
    if($text -match '^R328_FAIL_OPEN_' -or $text -notmatch $reason){
        throw ('R328_EXPECTED_PREWRITE_REFUSAL_MISSING_'+$name+' ACTUAL='+$text)
    }
    Pass $name
}
$logJunction=$null
$appJunction=$null
# R080: live elevated Helper is IPC-only. Test disconnected fail-closed
# behavior here; R080/R089/R090 exercise the real PID/nonce/SID-bound
# named-pipe handoff and asInvoker persistence independently.
$script:StatusPipeClient=$null
$script:StatusLogs=[Collections.Generic.List[string]]::new()
$priorLog='R328_PREEXISTING_LOG_UNTOUCHED'
$priorResult='R328_PREEXISTING_RESULT_UNTOUCHED'
[IO.File]::WriteAllText($LogPath,$priorLog)
[IO.File]::WriteAllText($ResultPath,$priorResult)
try{
    Expect-Refusal 'NO_IPC_LOG_REFUSES_BEFORE_USER_FILE_WRITE' {
        Write-Log 'R328_NEVER_WRITE'
    } 'SENSOR_STATUS_CHANNEL_CLOSED'
    Expect-Refusal 'NO_IPC_RESULT_REFUSES_BEFORE_USER_FILE_WRITE' {
        Write-Result 'READY' 'R328_NEVER_WRITE' 'NOT_STARTED' $null $false $false $true
    } 'SENSOR_STATUS_CHANNEL_CLOSED'

    # Retain R328's detached path-boundary negative regressions for the
    # legacy guard, but never use that guard to authorize elevated writes.
    Expect-Refusal 'WRONG_SINK_NAME_REFUSED' {
        Assert-SensorUserLogSink (Join-Path $base 'foreign.txt')
    } 'SENSOR_LOG_BOUNDARY_CHANGED_TARGET'

    $oldRoot=$LogsRoot
    $LogsRoot=Join-Path $base 'wrong-logs-root'
    try{
        Expect-Refusal 'MUTATED_LOGS_ROOT_VARIABLE_REFUSED' {
            Assert-SensorUserLogSink $LogPath
        } 'SENSOR_LOG_BOUNDARY_CHANGED_ROOT'
    }finally{$LogsRoot=$oldRoot}

    $moved=Join-Path $AppRoot 'LogsMovedBeforeWrite'
    [IO.Directory]::Move($LogsRoot,$moved)
    try{
        Expect-Refusal 'MISSING_LOG_FOLDER_REFUSED' {
            Assert-SensorUserLogSink $LogPath
        } 'SENSOR_LOG_BOUNDARY_MISSING_LOG_DIRECTORY'
    }finally{[IO.Directory]::Move($moved,$LogsRoot)}

    $moved=Join-Path $AppRoot 'LogsMovedForReparse'
    [IO.Directory]::Move($LogsRoot,$moved)
    New-Item -ItemType Junction -Path $LogsRoot -Target $external -ErrorAction Stop|Out-Null
    $logJunction=$LogsRoot
    Expect-Refusal 'POST_PREFLIGHT_LOG_JUNCTION_REFUSED' {
        Assert-SensorUserLogSink $LogPath
    } 'reparse'
    Expect-Refusal 'POST_PREFLIGHT_RESULT_JUNCTION_REFUSED' {
        Assert-SensorUserLogSink $ResultPath
    } 'reparse'
    if([IO.File]::ReadAllText($canary) -cne 'R328_CANARY_UNCHANGED' -or
       @(Get-ChildItem -LiteralPath $external -File).Count -ne 1){
        throw 'R328_EXTERNAL_CANARY_OR_DIRECTORY_WAS_MODIFIED'
    }
    Pass 'JUNCTION_EXTERNAL_CANARY_AND_CONTENT_PRESERVED'
    [IO.Directory]::Delete($logJunction)
    $logJunction=$null
    [IO.Directory]::Move($moved,$LogsRoot)

    $retired=Join-Path $base 'AppRootRetiredBeforeWrite'
    [IO.Directory]::Move($AppRoot,$retired)
    New-Item -ItemType Junction -Path $AppRoot -Target $external -ErrorAction Stop|Out-Null
    $appJunction=$AppRoot
    Expect-Refusal 'POST_PREFLIGHT_APPROOT_JUNCTION_REFUSED' {
        Assert-SensorUserLogSink $LogPath
    } 'reparse'
    [IO.Directory]::Delete($appJunction)
    $appJunction=$null
    [IO.Directory]::Move($retired,$AppRoot)

    if([IO.File]::ReadAllText($LogPath) -cne $priorLog -or
       [IO.File]::ReadAllText($ResultPath) -cne $priorResult -or
       [IO.File]::ReadAllText($canary) -cne 'R328_CANARY_UNCHANGED'){
        throw 'R328_DISCONNECTED_HELPER_MUTATED_PREEXISTING_USER_FILES'
    }
    Pass 'DISCONNECTED_PRIVILEGED_HELPER_NEVER_MODIFIES_USER_LOG_RESULT'

    # The actual production Write-Log/Write-Result functions must not
    # regain direct user-owned writes. A source-only check complements
    # the real native IPC tests later in this CI job.
    $functions=@($ast.FindAll({
        param($x) $x -is [Management.Automation.Language.FunctionDefinitionAst]
    },$true))
    $logFunction=@($functions|Where-Object Name -EQ 'Write-Log')
    $resultFunction=@($functions|Where-Object Name -EQ 'Write-Result')
    if($logFunction.Count -ne 1 -or $resultFunction.Count -ne 1){
        throw 'R328_IPC_FUNCTIONS_NOT_UNIQUE'
    }
    $bodies=@($logFunction[0].Body.Extent.Text,$resultFunction[0].Body.Extent.Text)
    if($bodies[0] -notmatch 'SENSOR_STATUS_CHANNEL_CLOSED' -or
       $bodies[1] -notmatch 'SENSOR_STATUS_CHANNEL_CLOSED' -or
       $bodies[1] -notmatch '\$script:StatusPipeClient\.Write\(' -or
       $source.Contains('New-Item -ItemType Directory -Force -Path $LogsRoot')){
        throw 'R328_PRIVILEGED_USER_LOG_WRITE_REINTRODUCED'
    }
    foreach($body in $bodies){
        if($body -match '(?i)(WriteAllText|WriteAllBytes|Set-Content|Add-Content|Out-File|FileStream|TBMEScopedUserLogLease|File\]::Write)'){
            throw 'R328_PRIVILEGED_USER_FILE_WRITE_REINTRODUCED'
        }
    }
    Pass 'PRODUCTION_PRIVILEGED_STATUS_FUNCTIONS_IPC_ONLY'

    if($checks.Count -ne 12){throw ('R328_CHECK_COUNT_MISMATCH_'+$checks.Count)}
    Write-Output ('R328_PRIVILEGED_IPC_NO_USER_FILE_WRITE_NATIVE_PASS='+$checks.Count+'/12')
}finally{
    if($logJunction -and [IO.Directory]::Exists($logJunction)){
        [IO.Directory]::Delete($logJunction)
    }
    if($appJunction -and [IO.Directory]::Exists($appJunction)){
        [IO.Directory]::Delete($appJunction)
    }
    if([IO.Directory]::Exists($base) -and
       [IO.Path]::GetFileName($base).StartsWith('tbme_r328_logs_',[StringComparison]::Ordinal)){
        [IO.Directory]::Delete($base,$true)
    }
}
