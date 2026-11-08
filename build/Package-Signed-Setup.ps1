# R80: package an already-signed Main into a NEW unsigned Setup requiring subsequent provider signing.
# Production: only CA-trusted SignPath Foundation Main. ContractFixtureOnly: isolated CI test, never release.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$InputMain,
    [Parameter(Mandatory=$true)][string]$ExpectedMainSHA256,
    [switch]$ContractFixtureOnly
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$UnsignedMain=Join-Path $Root 'build\_out\App\TaskbarMonitorEnhanced.exe'
$UnsignedSetup=Join-Path $Root 'build\_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$Project=Join-Path $PSScriptRoot 'TaskbarMonitorEnhanced_Setup.csproj'
$StageBase=if($ContractFixtureOnly){Join-Path $Root 'artifacts\_r80_contract_only'}else{Join-Path $Root 'artifacts\signed\Setup\TO_SIGN'}
$Setup=Join-Path $StageBase 'TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$Proof=Join-Path $StageBase 'EMBEDDED_MAIN_PROOF.json'
$Verification=Join-Path $StageBase 'SETUP_VERIFY.json'
$CreatedStage=$false
if($env:COMPUTERNAME -eq ''){throw 'R80 HOST ID MISSING'}
if(!(Test-Path -LiteralPath $UnsignedMain -PathType Leaf) -or
   !(Test-Path -LiteralPath $UnsignedSetup -PathType Leaf) -or
   !(Test-Path -LiteralPath $Project -PathType Leaf)){
    throw 'R80 UNSIGNED BUILDER OUTPUTS/PROJECT MISSING'
}
if((Test-Path -LiteralPath $StageBase) -or
   ($ExpectedMainSHA256 -notmatch '^[0-9a-fA-F]{64}$')){
    throw 'R80 INVALID SHA / STAGING ALREADY EXISTS; NO OVERWRITE'
}
$main=[IO.Path]::GetFullPath($InputMain)
if(!(Test-Path -LiteralPath $main -PathType Leaf) -or
   ([IO.Path]::GetFileName($main) -cne 'TaskbarMonitorEnhanced.exe') -or
   $main -ceq [IO.Path]::GetFullPath($UnsignedMain)){
    throw 'R80 INPUT MAIN NOT A SEPARATE EXACT FILE'
}
$prefix=if($ContractFixtureOnly){[IO.Path]::GetFullPath((Join-Path $Root 'artifacts\_r80_contract_input\'))}
else{[IO.Path]::GetFullPath((Join-Path $Root 'artifacts\signed\Main\'))}
if(-not $main.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){
    throw 'R80 INPUT MAIN OUTSIDE DESIGNATED ISOLATED STAGING'
}
$inputDigest=(Get-FileHash -LiteralPath $main -Algorithm SHA256).Hash
$originalMainDigest=(Get-FileHash -LiteralPath $UnsignedMain -Algorithm SHA256).Hash
$originalSetupDigest=(Get-FileHash -LiteralPath $UnsignedSetup -Algorithm SHA256).Hash
if($inputDigest -cne $ExpectedMainSHA256.ToUpperInvariant() -or
   $inputDigest -ceq $originalMainDigest){throw 'R80 MAIN SHA MISMATCH OR UNSIGNED CONTENT REUSED'}
$sig=Get-AuthenticodeSignature -LiteralPath $main
if(!$ContractFixtureOnly){
    $name=if($sig.SignerCertificate){
        $sig.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false)
    }else{''}
    if(([string]$sig.Status -cne 'Valid') -or
       ($name -cne 'SignPath Foundation') -or
       ![bool]$sig.TimeStamperCertificate){
        throw 'R80 MAIN NOT PUBLICLY TRUSTED AND TIMESTAMPED SIGNPATH FOUNDATION'
    }
}else{
    # Tests MUST reject any actual trusted publisher, to prohibit test-only approval confusion.
    if([string]$sig.Status -ceq 'Valid'){throw 'R80 TEST FIXTURE MAY NOT BE A TRUSTED RELEASE'}
}
$package=Join-Path $Root 'build\_package'
$text=Join-Path $Root 'build\_package_text'
if(!(Test-Path -LiteralPath $package -PathType Container) -or
   !(Test-Path -LiteralPath $text -PathType Container)){
    throw 'R80 PREPARED UNSIGNED RESOURCE TREE MISSING; RUN Build.ps1 FIRST'
}
try{
    New-Item -ItemType Directory -Force -Path $StageBase | Out-Null
    $CreatedStage=$true
    $argList=@('build',$Project,'-c','Release','--nologo',
        '-p:RestoreIgnoreFailedSources=true',
        ('-p:SignedMainPayload='+$main),
        '-p:IncludePawnIOPayload=false',
        ('-p:OutputPath='+$StageBase+'\'))
    & dotnet @argList | Out-Null
    if($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $Setup -PathType Leaf)){
        throw 'R80 PACKAGING COMPILE FAILED'
    }
    $p=Start-Process -FilePath $Setup -ArgumentList @('/verify',('/verifyfile='+$Verification)) -PassThru -Wait
    if($p.ExitCode -ne 0 -or !(Test-Path -LiteralPath $Verification -PathType Leaf)){
        throw 'R80 SETUP SELF VERIFY FAILED'
    }
    $v=Get-Content -LiteralPath $Verification -Raw|ConvertFrom-Json
    $mainSize=(Get-Item -LiteralPath $main).Length
    if($v.Status -cne 'PASS' -or
       [int]$v.Resources -ne 25 -or
       $v.PawnIOBundled -ne $false -or
       [string]$v.EmbeddedMainSHA256 -cne $inputDigest -or
       [int64]$v.EmbeddedMainBytes -ne $mainSize){
        throw 'R80 EMBEDDED MAIN IS NOT THE EXACT SIGNED INPUT'
    }
    if((Get-FileHash -LiteralPath $UnsignedMain -Algorithm SHA256).Hash -cne $originalMainDigest -or
       (Get-FileHash -LiteralPath $UnsignedSetup -Algorithm SHA256).Hash -cne $originalSetupDigest){
        throw 'R80 REPRODUCIBLE UNSIGNED BASELINE WAS MODIFIED'
    }
    $result=[ordered]@{
        Schema=1
        Status=if($ContractFixtureOnly){'PASS_CONTRACT_FIXTURE_ONLY_NOT_SIGNED'}else{'READY_FOR_SIGNPATH_SETUP_SIGNING_NOT_RELEASED'}
        MainSHA256=$inputDigest
        MainBytes=$mainSize
        MainSignatureStatus=[string]$sig.Status
        SetupToSignSHA256=(Get-FileHash -LiteralPath $Setup -Algorithm SHA256).Hash
        UnsignedBuildMainSHA256=$originalMainDigest
        UnsignedBuildSetupSHA256=$originalSetupDigest
        EmbeddedMainSHA256=$v.EmbeddedMainSHA256
        EmbeddedMainBytes=$v.EmbeddedMainBytes
        ResourceCount=[int]$v.Resources
        PawnIOBundled=$false
        UpstreamDriver='EXTERNAL_MANUAL_OPT_IN_ONLY'
        ProductionTrustAccepted=$false
        SignerAuthenticodeAndPublisherPreflightPass=(!$ContractFixtureOnly)
        ProviderApprovalVerified=$false
        SetupStillNeedsSignPathSignature=$true
        NoInstalledOrWallpaperMutation=$true
    }
    $result|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $Proof -Encoding utf8
    Write-Output ($result|ConvertTo-Json -Compress -Depth 5)
} catch {
    # Preserve diagnostic artifacts on failure; never blindly delete unknown bytes.
    if($CreatedStage){Write-Warning ('R80 FAILED; stage preserved for audit: '+$StageBase)}
    throw
}
