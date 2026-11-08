# R85 negative release-compatibility test. A legacy Setup WITH PawnIO must be rejected
# even if its embedded Main SHA is correct. Production OSS Setup has NO PawnIO resource.
# Test does not execute /install, install a driver or change Windows settings.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$Root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$LegacyDir=Join-Path $Root 'artifacts\_r85_forbidden_pawnio_fixture'
$Project=Join-Path $PSScriptRoot 'TaskbarMonitorEnhanced_Setup.csproj'
$OssSetup=Join-Path $Root 'build\_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$Main=Join-Path $Root 'build\_out\App\TaskbarMonitorEnhanced.exe'
$LegacySetup=Join-Path $LegacyDir 'TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$LegacyVerify=Join-Path $LegacyDir 'legacy_verify.json'
$Reader=Join-Path $PSScriptRoot 'Verify-Embedded-Main.ps1'
if(Test-Path -LiteralPath $LegacyDir){throw 'R85 UNSAFE RERUN: FORBIDDEN FIXTURE ALREADY EXISTS'}
foreach($f in @($Project,$OssSetup,$Main,$Reader)){if(!(Test-Path -LiteralPath $f -PathType Leaf)){throw ('R85 MISSING PRESTATE '+$f)}}
$mainSHA=(Get-FileHash -LiteralPath $Main).Hash
$ossSHA=(Get-FileHash -LiteralPath $OssSetup).Hash
# A clean CI runner intentionally has NO previously installed app. Its absence is a valid
# prestate, whereas a real installed user's data must remain exactly byte-identical.
$personalMain=Join-Path $env:LOCALAPPDATA 'TaskbarMonitorEnhanced\TaskbarMonitorEnhanced.exe'
$personalConfig=Join-Path $env:LOCALAPPDATA 'TaskbarMonitorEnhanced\config.json'
$hadMain=Test-Path -LiteralPath $personalMain -PathType Leaf
$hadConfig=Test-Path -LiteralPath $personalConfig -PathType Leaf
if($hadMain -ne $hadConfig){throw 'R85 PARTIAL PERSONAL APP PRESTATE'}
$publishedExeSHA=if($hadMain){(Get-FileHash -LiteralPath $personalMain).Hash}else{''}
$personalCfgSHA=if($hadConfig){(Get-FileHash -LiteralPath $personalConfig).Hash}else{''}
$bgProperties=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers' -ErrorAction SilentlyContinue
$wallMode=if($bgProperties -and $bgProperties.PSObject.Properties.Name -contains 'BackgroundType'){$bgProperties.BackgroundType}else{$null}
if($env:COMPUTERNAME -ceq 'EMAD-PC-ULTIMAT' -and
   ($publishedExeSHA -cne '05F9E069C4598FDAD327A41BF1CA34A1498D022119DB81E09F4B3B091C9BA377' -or
    $wallMode -ne 2)){throw 'R85 PROTECTED EMAD-PC BASELINE DIFFERENT'}
$created=$false
try {
    $pr=@(& pwsh -NoProfile -File $Reader -SetupExe $OssSetup -ExpectedMainSHA256 $mainSHA)
    if($LASTEXITCODE -ne 0 -or $pr.Count -ne 1){throw 'R85 PRODUCTION OSS RESOURCE READER FAILED'}
    $oss=$pr[0]|ConvertFrom-Json
    if($oss.Status -cne 'PASS_EMBEDDED_MAIN_EXACT_SHA256' -or $oss.PawnIOBundled -ne $false){throw 'R85 OSS BUNDLED PROPRIETARY DRIVER'}
    New-Item -ItemType Directory -Path $LegacyDir -ErrorAction Stop|Out-Null
    $created=$true
    $args=@('build',$Project,'-c','Release','--nologo','-p:RestoreIgnoreFailedSources=true',
       '-p:IncludePawnIOPayload=true',('-p:OutputPath='+$LegacyDir+'\'))
    & dotnet @args | Out-Null
    if($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $LegacySetup -PathType Leaf)){throw 'R85 LEGACY NEGATIVE FIXTURE DID NOT BUILD'}
    $p=Start-Process -FilePath $LegacySetup -ArgumentList @('/verify',('/verifyfile='+$LegacyVerify)) -Wait -PassThru
    if($p.ExitCode -ne 0 -or !(Test-Path -LiteralPath $LegacyVerify -PathType Leaf)){throw 'R85 LEGACY SELFVERIFY FAILED'}
    $v=Get-Content -LiteralPath $LegacyVerify -Raw|ConvertFrom-Json
    if($v.Status -cne 'PASS' -or $v.PawnIOBundled -ne $true -or [int]$v.Resources -ne 26 -or
       $v.EmbeddedMainSHA256 -cne $mainSHA){throw 'R85 LEGACY FIXTURE DID NOT CONTAIN PINNED PAWNIO'}
    $readerRejected=$false
    try {
        & pwsh -NoProfile -File $Reader -SetupExe $LegacySetup -ExpectedMainSHA256 $mainSHA *> $null
        if($LASTEXITCODE -ne 0){$readerRejected=$true}
    }catch{$readerRejected=$true}
    if(!$readerRejected){throw 'R85 CRITICAL: OSS VERIFIER ACCEPTED PROPRIETARY PAWNIO'}
    if((Get-FileHash -LiteralPath $Main).Hash -cne $mainSHA -or (Get-FileHash -LiteralPath $OssSetup).Hash -cne $ossSHA){throw 'R85 ORIGINAL UNSIGNED BUILDER CHANGED'}
    Write-Output ('R85_OSS_NO_PROPRIETARY_BUNDLE_PASS productionEmbedded=False negativeLegacyResources='+$v.Resources+' negativeRejected=True')
} finally {
    if($created -and (Test-Path -LiteralPath $LegacyDir)){
        $allow=@('TaskbarMonitorEnhanced_Setup_1.7.8.exe','TaskbarMonitorEnhanced_Setup_1.7.8.exe.config','legacy_verify.json')
        $objects=@(Get-ChildItem -LiteralPath $LegacyDir -Force)
        if(@($objects | Where-Object {$_.PSIsContainer -or $_.Name -notin $allow}).Count -ne 0){
            throw ('R85 DEGRADED: UNKNOWN FILE IN OWNED STAGING; PRESERVED '+$LegacyDir)
        }
        foreach($f in $objects){Remove-Item -LiteralPath $f.FullName -ErrorAction Stop}
        if(@(Get-ChildItem -LiteralPath $LegacyDir -Force).Count -ne 0){throw 'R85 OWNED STAGING STILL NOT EMPTY'}
        Remove-Item -LiteralPath $LegacyDir -ErrorAction Stop
    }
}
$nowBg=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers' -ErrorAction SilentlyContinue
$nowBgMode=if($nowBg -and $nowBg.PSObject.Properties.Name -contains 'BackgroundType'){$nowBg.BackgroundType}else{$null}
if((Get-FileHash -LiteralPath $Main).Hash -cne $mainSHA -or
   (Get-FileHash -LiteralPath $OssSetup).Hash -cne $ossSHA -or
   (Test-Path -LiteralPath $personalMain -PathType Leaf) -ne $hadMain -or
   (Test-Path -LiteralPath $personalConfig -PathType Leaf) -ne $hadConfig -or
   [string]$nowBgMode -cne [string]$wallMode){throw 'R85 FINAL INSTALLATION ABSENCE/PERSONAL STATE CHANGED'}
if($hadMain -and ((Get-FileHash -LiteralPath $personalMain).Hash -cne $publishedExeSHA -or
  (Get-FileHash -LiteralPath $personalConfig).Hash -cne $personalCfgSHA)){throw 'R85 PERSONAL INSTALLED BYTES CHANGED'}
exit 0
