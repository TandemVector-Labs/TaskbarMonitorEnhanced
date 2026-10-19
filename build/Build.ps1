[CmdletBinding()]
param([switch]$NoDownload)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$Root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Deps=Join-Path $PSScriptRoot '_deps'
$Out=Join-Path $PSScriptRoot '_out'
$Package=Join-Path $PSScriptRoot '_package'
$TextPackage=Join-Path $PSScriptRoot '_package_text'
$Artifacts=Join-Path $Root 'artifacts'
$LhmZip=Join-Path $Deps 'LibreHardwareMonitor.zip'
$PawnExe=Join-Path $Deps 'PawnIO_setup.exe'
$LhmDir=Join-Path $Deps 'LHM'

$LockPath=Join-Path $PSScriptRoot 'dependencies.lock.json'
if(!(Test-Path -LiteralPath $LockPath)){throw 'Dependency lock file is missing.'}
$Lock=Get-Content -LiteralPath $LockPath -Raw|ConvertFrom-Json
$LhmUrl=[string]$Lock.dependencies.LibreHardwareMonitor.url
$LhmSha=([string]$Lock.dependencies.LibreHardwareMonitor.sha256).ToUpperInvariant()
$PawnUrl=[string]$Lock.dependencies.PawnIO.url
$PawnSha=([string]$Lock.dependencies.PawnIO.sha256).ToUpperInvariant()

function Assert-Hash([string]$Path,[string]$Expected){
    if(!(Test-Path -LiteralPath $Path)){throw "Missing dependency: $Path"}
    $actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
    if($actual -ne $Expected){throw "SHA256 mismatch for $Path; expected $Expected; actual $actual"}
}
function Build([string]$Project){
    & dotnet build $Project -c Release --nologo -p:RestoreIgnoreFailedSources=true
    if($LASTEXITCODE -ne 0){throw "Build failed: $Project"}
}
function Write-CanonicalTextResource([string]$Source,[string]$Destination){
    if(!(Test-Path -LiteralPath $Source)){throw "Canonical text source missing: $Source"}
    $text=[IO.File]::ReadAllText($Source)
    $text=$text.Replace("`r`n","`n").Replace("`r","`n")
    $parent=Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent|Out-Null
    [IO.File]::WriteAllText($Destination,$text,[Text.UTF8Encoding]::new($false))
}
function Assert-PeSubsystem([string]$Path,[int]$Expected){
    if(!(Test-Path -LiteralPath $Path)){throw "PE subsystem check missing file: $Path"}
    [byte[]]$bytes=[IO.File]::ReadAllBytes($Path)
    if($bytes.Length -lt 256){throw "PE subsystem check invalid file: $Path"}
    $pe=[BitConverter]::ToInt32($bytes,0x3C)
    if($pe -lt 0 -or ($pe+96) -ge $bytes.Length){throw "PE header offset invalid: $Path"}
    if($bytes[$pe] -ne 0x50 -or $bytes[$pe+1] -ne 0x45 -or $bytes[$pe+2] -ne 0 -or $bytes[$pe+3] -ne 0){throw "PE signature invalid: $Path"}
    $subsystem=[BitConverter]::ToUInt16($bytes,$pe+24+68)
    if($subsystem -ne $Expected){throw "Unexpected PE subsystem for $Path; expected $Expected (WINDOWS_GUI), actual $subsystem"}
}

New-Item -ItemType Directory -Force -Path $Deps,$Out,$Package,$TextPackage,$Artifacts|Out-Null
if(!$NoDownload){
    Invoke-WebRequest -UseBasicParsing -Uri $LhmUrl -OutFile $LhmZip
    Invoke-WebRequest -UseBasicParsing -Uri $PawnUrl -OutFile $PawnExe
}
Assert-Hash $LhmZip $LhmSha
Assert-Hash $PawnExe $PawnSha

Remove-Item -LiteralPath $LhmDir -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -LiteralPath $LhmZip -DestinationPath $LhmDir -Force
if(!(Test-Path -LiteralPath (Join-Path $LhmDir 'LibreHardwareMonitorLib.dll'))){throw 'LibreHardwareMonitorLib.dll missing from pinned archive.'}

Remove-Item -LiteralPath $Out,$Package,$TextPackage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Out,$Package,$TextPackage|Out-Null

# Reject truncated/missing source before compiling or packaging a candidate.
foreach($source in @('TaskbarMonitorEnhanced.cs','StudioThemes.cs','WallpaperStudio.cs','TaskbarGlass.cs','WorkspaceModels.cs','MonitorWorkspace.cs','WorkspaceSelfTest.cs')){
    $sourcePath=Join-Path $Root ('src\'+$source)
    if(!(Test-Path -LiteralPath $sourcePath) -or (Get-Item -LiteralPath $sourcePath).Length -lt 1000){throw "Missing/truncated source: $sourcePath"}
}
Build (Join-Path $PSScriptRoot 'TaskbarMonitorEnhanced.csproj')
Build (Join-Path $PSScriptRoot 'TaskbarMonitorSensorBroker.csproj')
Build (Join-Path $PSScriptRoot 'TaskbarMonitorSensorSupervisor.csproj')
Assert-PeSubsystem (Join-Path $Out 'Broker\TaskbarMonitorSensorBroker.exe') 2
Assert-PeSubsystem (Join-Path $Out 'Supervisor\TaskbarMonitorSensorSupervisor.exe') 2
Write-Host 'TBME_SENSOR_WINDOWLESS_PE=PASS'
Copy-Item (Join-Path $Out 'App\TaskbarMonitorEnhanced.exe') $Package
Copy-Item (Join-Path $Out 'App\TaskbarMonitorEnhanced.exe.config') $Package
Copy-Item (Join-Path $Out 'Broker\TaskbarMonitorSensorBroker.exe') $Package
Copy-Item (Join-Path $Out 'Supervisor\TaskbarMonitorSensorSupervisor.exe') $Package

$CanonicalTextResources=[ordered]@{
    'TaskbarMonitorEnhanced.cs'=(Join-Path $Root 'src\TaskbarMonitorEnhanced.cs')
    'StudioThemes.cs'=(Join-Path $Root 'src\StudioThemes.cs')
    'WallpaperStudio.cs'=(Join-Path $Root 'src\WallpaperStudio.cs')
    'TaskbarGlass.cs'=(Join-Path $Root 'src\TaskbarGlass.cs')
    'WorkspaceModels.cs'=(Join-Path $Root 'src\WorkspaceModels.cs')
    'MonitorWorkspace.cs'=(Join-Path $Root 'src\MonitorWorkspace.cs')
    'WorkspaceSelfTest.cs'=(Join-Path $Root 'src\WorkspaceSelfTest.cs')
    'TaskbarMonitorSensorBroker.cs'=(Join-Path $Root 'src\sensors\TaskbarMonitorSensorBroker.cs')
    'TaskbarMonitorSensorSupervisor.cs'=(Join-Path $Root 'src\sensors\TaskbarMonitorSensorSupervisor.cs')
    'TBME_Setup_Elevated_Helper.ps1'=(Join-Path $Root 'installer\TBME_Setup_Elevated_Helper.ps1')
    'LICENSE'=(Join-Path $Root 'LICENSE')
    'README.md'=(Join-Path $Root 'docs\releases\v1.7.8\INSTALLER_README.txt')
    'AUTHORS.md'=(Join-Path $Root 'AUTHORS.md')
    'COPYRIGHT_AND_ATTRIBUTION.md'=(Join-Path $Root 'COPYRIGHT_AND_ATTRIBUTION.md')
    'AI_ASSISTED_DEVELOPMENT.md'=(Join-Path $Root 'AI_ASSISTED_DEVELOPMENT.md')
    'THIRD_PARTY_NOTICES.md'=(Join-Path $Root 'THIRD_PARTY_NOTICES.md')
    'RELEASE_NOTES_v1.7.8.md'=(Join-Path $Root 'docs\releases\v1.7.8\RELEASE_NOTES.md')
    'UPSTREAM_REFERENCE_GPL_NOTICE.md'=(Join-Path $Root 'UPSTREAM_REFERENCE_GPL_NOTICE.md')
    'TaskbarMonitorEnhanced_Setup.cs'=(Join-Path $Root 'installer\TaskbarMonitorEnhanced_Setup.cs')
}
foreach($entry in $CanonicalTextResources.GetEnumerator()){
    Write-CanonicalTextResource ([string]$entry.Value) (Join-Path $TextPackage ([string]$entry.Key))
}
Write-Host 'TBME_CANONICAL_TEXT_PAYLOAD=PASS'

Build (Join-Path $PSScriptRoot 'TaskbarMonitorEnhanced_Setup.csproj')
$Setup=Join-Path $Out 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
if(!(Test-Path -LiteralPath $Setup)){throw 'Setup output missing.'}

# SignPath Foundation requires uniform signed-artifact project and ProductVersion metadata.
# Fail before packaging a Setup whose Authenticode metadata cannot match Main.
$SigningMain=(Join-Path $Out 'App\TaskbarMonitorEnhanced.exe')
$SigningMainInfo=(Get-Item -LiteralPath $SigningMain).VersionInfo
$SigningSetupInfo=(Get-Item -LiteralPath $Setup).VersionInfo
$SigningProject='Taskbar Monitor Enhanced'
if($SigningMainInfo.ProductName -cne $SigningProject -or
   $SigningSetupInfo.ProductName -cne $SigningProject -or
   [string]::IsNullOrWhiteSpace($SigningMainInfo.ProductVersion) -or
   $SigningMainInfo.ProductVersion -cne $SigningSetupInfo.ProductVersion -or
   $SigningMainInfo.FileVersion -cne $SigningSetupInfo.FileVersion){
    throw ('SIGNING_METADATA_MISMATCH: Main ProductName='+$SigningMainInfo.ProductName+
      ' ProductVersion='+$SigningMainInfo.ProductVersion+' FileVersion='+$SigningMainInfo.FileVersion+
      '; Setup ProductName='+$SigningSetupInfo.ProductName+' ProductVersion='+$SigningSetupInfo.ProductVersion+
      ' FileVersion='+$SigningSetupInfo.FileVersion)
}
Write-Host ('TBME_SIGNING_METADATA_MAIN_SETUP=PASS ProductVersion='+$SigningMainInfo.ProductVersion)
$SigningMetadata=[ordered]@{
    Schema=1;Status='PASS';Project=$SigningProject;
    MainProductVersion=$SigningMainInfo.ProductVersion;
    SetupProductVersion=$SigningSetupInfo.ProductVersion;
    MainFileVersion=$SigningMainInfo.FileVersion;
    SetupFileVersion=$SigningSetupInfo.FileVersion;
    MainSHA256=(Get-FileHash -LiteralPath $SigningMain -Algorithm SHA256).Hash;
    SetupSHA256=(Get-FileHash -LiteralPath $Setup -Algorithm SHA256).Hash;
    UntrustedBinarySigningStatus='METADATA_READY_NOT_PUBLIC_SIGNED'
}
$SigningMetadata | ConvertTo-Json -Depth 4 |
    Set-Content -LiteralPath (Join-Path $Out 'signing_metadata.json') -Encoding UTF8

$Verify=Join-Path $Out 'setup_verify.json'
Remove-Item -LiteralPath $Verify -Force -ErrorAction SilentlyContinue
$vp=Start-Process -FilePath $Setup -ArgumentList @('/verify',("/verifyfile="+$Verify)) -Wait -PassThru
if($vp.ExitCode -ne 0){throw "Setup /verify failed with exit $($vp.ExitCode)"}
if(!(Test-Path -LiteralPath $Verify)){throw 'Setup /verify did not create its verification file.'}
$v=Get-Content -LiteralPath $Verify -Raw|ConvertFrom-Json
if([string]$v.Status -ne 'PASS' -or [int]$v.Resources -ne 25 -or $v.PawnIOBundled -ne $false){throw 'OSS Setup must contain 25 required resources and no proprietary PawnIO installer.'}

& (Join-Path $PSScriptRoot 'Test-Workspace.ps1') -Executable (Join-Path $Package 'TaskbarMonitorEnhanced.exe') -OutputDirectory (Join-Path $Out 'contracts')
if($LASTEXITCODE -ne 0){throw 'Application contract suite failed.'}

$manifest=[ordered]@{
    Version='1.7.8'
    Build='V1_7_8_R286_OPTIONAL_TEMP_SOUND'
    GeneratedUtc=[datetime]::UtcNow.ToString('o')
    Dependencies=[ordered]@{
        LibreHardwareMonitor=[ordered]@{Version=[string]$Lock.dependencies.LibreHardwareMonitor.version;Url=$LhmUrl;SHA256=$LhmSha}
        PawnIO=[ordered]@{Version=[string]$Lock.dependencies.PawnIO.version;Url=$PawnUrl;SHA256=$PawnSha}
    }
    Outputs=@()
}
foreach($f in @((Join-Path $Package 'TaskbarMonitorEnhanced.exe'),(Join-Path $Package 'TaskbarMonitorEnhanced.exe.config'),(Join-Path $Package 'TaskbarMonitorSensorBroker.exe'),(Join-Path $Package 'TaskbarMonitorSensorSupervisor.exe'),$Setup)){
    $manifest.Outputs += [ordered]@{Name=[IO.Path]::GetFileName($f);Bytes=(Get-Item -LiteralPath $f).Length;SHA256=(Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash.ToUpperInvariant()}
}
$manifest|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $Artifacts 'BUILD_MANIFEST.json') -Encoding UTF8
Copy-Item $Setup (Join-Path $Artifacts ([IO.Path]::GetFileName($Setup))) -Force
Write-Host 'TBME_REPRO_BUILD=PASS'
