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
try{
    Write-Log 'NATIVE_SAFE_LOG'
    if(!(Test-Path -LiteralPath $LogPath -PathType Leaf) -or
       (Get-Content -LiteralPath $LogPath -Raw) -notmatch 'NATIVE_SAFE_LOG'){
       throw 'R328_SAFE_LOG_WRITE_FAILED'
    }
    Pass 'ORDINARY_USER_PROFILE_LOG_WORKS'

    Write-Result 'DEGRADED' 'Native no UAC mutation test' 'NOT_STARTED' $null $false $false $false
    $result=Get-Content -LiteralPath $ResultPath -Raw |ConvertFrom-Json
    if($result.Status -cne 'DEGRADED' -or $result.SensorHealthy -ne $false -or
       $result.LogPath -cne $LogPath){throw 'R328_SAFE_RESULT_JSON_CONTRACT_FAILED'}
    Pass 'ORDINARY_RESULT_JSON_CONTRACT_PRESERVED'

    Expect-Refusal 'WRONG_SINK_NAME_REFUSED' {
        Assert-SensorUserLogSink (Join-Path $base 'foreign.txt')
    } 'SENSOR_LOG_BOUNDARY_CHANGED_TARGET'

    $oldRoot=$LogsRoot
    $LogsRoot=Join-Path $base 'wrong-logs-root'
    try{Expect-Refusal 'MUTATED_LOGS_ROOT_VARIABLE_REFUSED' { Write-Log 'NEVER_WRITE' } 'SENSOR_LOG_BOUNDARY_CHANGED_ROOT'}
    finally{$LogsRoot=$oldRoot}

    $moved=Join-Path $AppRoot 'LogsMovedBeforeWrite'
    [IO.Directory]::Move($LogsRoot,$moved)
    try{
        Expect-Refusal 'MISSING_LOG_FOLDER_REFUSED' { Write-Log 'NEVER_WRITE' } 'SENSOR_LOG_BOUNDARY_MISSING_LOG_DIRECTORY'
    }finally{[IO.Directory]::Move($moved,$LogsRoot)}

    $moved=Join-Path $AppRoot 'LogsMovedForReparse'
    [IO.Directory]::Move($LogsRoot,$moved)
    New-Item -ItemType Junction -Path $LogsRoot -Target $external -ErrorAction Stop|Out-Null
    $logJunction=$LogsRoot
    Expect-Refusal 'POST_PREFLIGHT_LOG_JUNCTION_REFUSED' {
        Write-Log 'FOREIGN_MODIFICATION_ATTEMPT'
    } 'reparse'
    Expect-Refusal 'POST_PREFLIGHT_RESULT_JUNCTION_REFUSED' {
        Write-Result 'READY' 'FOREIGN_MODIFICATION_ATTEMPT' 'NOT_STARTED' $null $false $false $true
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
    New-Item -ItemType Junction -Path $AppRoot -Target $external -ErrorAction Stop | Out-Null
    $appJunction=$AppRoot
    Expect-Refusal 'POST_PREFLIGHT_APPROOT_JUNCTION_REFUSED' {
        Write-Log 'FOREIGN_ROOT_MODIFICATION'
    } 'reparse'
    [IO.Directory]::Delete($appJunction)
    $appJunction=$null
    [IO.Directory]::Move($retired,$AppRoot)

    $pre=$source.IndexOf('Assert-SensorBoundaryNoReparse $LogsRoot',[StringComparison]::Ordinal)
    $create=$source.IndexOf('New-Item -ItemType Directory -Force -Path $LogsRoot',[StringComparison]::Ordinal)
    $post=$source.IndexOf('Assert-SensorBoundaryNoReparse $LogsRoot',$create+1)
    $functionStart=$source.IndexOf('function Write-Log(',[StringComparison]::Ordinal)
    if($pre -lt 0 -or $create -le $pre -or $post -le $create -or $functionStart -le $post){
        throw 'R328_CREATION_PATH_PRE_AND_POST_CHECK_ORDER_BROKEN'
    }
    Pass 'LOG_DIRECTORY_CREATION_PRE_AND_POST_BOUNDARY_ORDER'

    $scriptLines=$source
    if($scriptLines.IndexOf('Assert-SensorUserLogSink $LogPath',[StringComparison]::Ordinal) -lt 0 -or
       $scriptLines.IndexOf('Assert-SensorUserLogSink $ResultPath',[StringComparison]::Ordinal) -lt 0){
        throw 'R328_BOTH_WRITE_SINKS_ARE_NOT_GUARDED'
    }
    Pass 'BOTH_PRIVILEGED_USER_LOG_WRITES_HAVE_PATH_GUARDS'

    if($checks.Count -ne 12){throw ('R328_CHECK_COUNT_MISMATCH_'+$checks.Count)}
    Write-Output ('R328_PRIVILEGED_HELPER_LOG_BOUNDARY_NET48_PASS='+$checks.Count+'/12')
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
