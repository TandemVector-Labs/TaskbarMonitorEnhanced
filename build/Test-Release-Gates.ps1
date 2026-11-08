[CmdletBinding()]
param(
    [string]$VisualSummary='',
    [string]$RuntimeSummary='',
    [string]$CIReceipt='',
    [string]$LivePreviewReceipt='',
    [string]$TopGlassLiveReceipt='',
    [string]$TopGlassTransitionReceipt='',
    [string]$StartFloatLiveReceipt='',
    [string]$PositiveWallpaperReceipt='',
    [string]$InstalledRuntimeReceipt='',
    [string]$OutputPath='',
    [switch]$RequireStable
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
function Resolve-Evidence([string]$path) {
    if([string]::IsNullOrWhiteSpace($path)){return $null}
    $full=if([IO.Path]::IsPathRooted($path)){[IO.Path]::GetFullPath($path)}else{[IO.Path]::GetFullPath((Join-Path $root $path))}
    if(!(Test-Path -LiteralPath $full -PathType Leaf)){return $null}
    try{return Get-Content -LiteralPath $full -Raw|ConvertFrom-Json}catch{return $null}
}
function Add-Gate([string]$name,[bool]$passed,[string]$evidence,[string]$kind) {
    $script:gates.Add([ordered]@{Gate=$name;Status=$(if($passed){'PASS'}else{'BLOCKED'});Class=$kind;Evidence=$evidence})
}
$sha=(& git -C $root rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0 -or $sha.Length -ne 40){throw 'Git HEAD not available.'}
$dirty=@(& git -C $root status --porcelain)
if($LASTEXITCODE -ne 0){throw 'Git status failed.'}
$manifestPath=Join-Path $root 'artifacts\BUILD_MANIFEST.json'
$detPath=Join-Path $root 'artifacts\DETERMINISM.json'
$verifyPath=Join-Path $root 'build\_out\setup_verify.json'
$gates=[Collections.Generic.List[object]]::new()
Add-Gate 'G01_SOURCE_COMMITTED_CLEAN' ($dirty.Count -eq 0) $sha 'Candidate'
$manifest=Resolve-Evidence $manifestPath
$outputs=@()
$realHashesPass=$false
if($null -ne $manifest) {
    $outputs=@($manifest.Outputs)
    if($outputs.Count -eq 5){
        $files=@{
            'TaskbarMonitorEnhanced.exe'='build\_out\App\TaskbarMonitorEnhanced.exe';
            'TaskbarMonitorEnhanced.exe.config'='build\_out\App\TaskbarMonitorEnhanced.exe.config';
            'TaskbarMonitorSensorBroker.exe'='build\_out\Broker\TaskbarMonitorSensorBroker.exe';
            'TaskbarMonitorSensorSupervisor.exe'='build\_out\Supervisor\TaskbarMonitorSensorSupervisor.exe';
            'TaskbarMonitorEnhanced_Setup_1.7.8.exe'='build\_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
        }
        $realHashesPass=$true
        foreach($item in $outputs){
            $name=[string]$item.Name
            if(!$files.ContainsKey($name)){$realHashesPass=$false;break}
            $file=Join-Path $root $files[$name]
            if(!(Test-Path -LiteralPath $file -PathType Leaf) -or
                (Get-FileHash -LiteralPath $file).Hash -ne [string]$item.SHA256){
                $realHashesPass=$false;break
            }
        }
    }
}
Add-Gate 'G02_FIVE_ACTUAL_SHA256_OUTPUTS' $realHashesPass 'artifacts/BUILD_MANIFEST.json' 'Candidate'
$det=Resolve-Evidence $detPath
$detPass=$null -ne $det -and $det.Status -eq 'PASS' -and
    $det.ExactHead -eq $sha -and @($det.Outputs).Count -eq 5
Add-Gate 'G03_CLEAN_CLONE_DETERMINISM' $detPass 'artifacts/DETERMINISM.json' 'Candidate'
$setup=Resolve-Evidence $verifyPath
$setupPass=$null -ne $setup -and $setup.Status -eq 'PASS' -and [int]$setup.Resources -eq 25 -and $setup.PawnIOBundled -eq $false
Add-Gate 'G04_CANONICAL_SETUP_26_RESOURCES' $setupPass 'build/_out/setup_verify.json' 'Candidate'
$visual=Resolve-Evidence $VisualSummary
$visualPass=$null -ne $visual -and $visual.Status -eq 'PASS' -and $visual.GitHead -eq $sha -and
    @($visual.Results).Count -eq 10 -and @($visual.Results|Where-Object Status -ne 'PASS').Count -eq 0
Add-Gate 'G05_EXACT_SHA_TEN_VISUAL_SUITES' $visualPass $VisualSummary 'Candidate'
$chart=$null;$glass=$null
if($null -ne $visual){
    $visualDir=Split-Path -Parent ([IO.Path]::GetFullPath((Join-Path $root $VisualSummary)))
    $chart=Resolve-Evidence (Join-Path $visualDir 'chartglassproof\CHART_GLASS_PROOF.json')
    $glass=Resolve-Evidence (Join-Path $visualDir 'glassproof\GLASS_PROOF.json')
}
$chartPass=$null -ne $chart -and $chart.Status -eq 'PASS' -and [int]$chart.Themes -eq 49 -and [int]$chart.Pairs -eq 196
$glassPass=$null -ne $glass -and $glass.Status -eq 'PASS' -and [int]$glass.Tests -eq 196
Add-Gate 'G06_FOREGROUND_CHARTS_49_THEMES_196_PAIRS' $chartPass 'paired chart/glass foreground proof' 'Candidate'
Add-Gate 'G07_TEXT_ALPHA_196_PAIRS' $glassPass 'paired glyph/high-contrast proof' 'Candidate'
$runtime=Resolve-Evidence $RuntimeSummary
$runtimePass=$null -ne $runtime -and $runtime.Status -eq 'PASS' -and $runtime.Mode -eq 'CI_PORTABLE_5' -and @($runtime.Results).Count -eq 5 -and
    @($runtime.Results | Where-Object Status -ne 'PASS').Count -eq 0
Add-Gate 'G08_PORTABLE_FIVE_RUNTIME_PROBES' $runtimePass $RuntimeSummary 'Candidate'
$ci=Resolve-Evidence $CIReceipt
$ciPass=$null -ne $ci -and $ci.Status -eq 'PASS' -and $ci.Commit -eq $sha -and
    $ci.Conclusion -eq 'success' -and [int]$ci.LocalToCIOutputsMatched -eq 5 -and
    $ci.ProvenanceAttestations -eq 'PASS'
Add-Gate 'G09_EXACT_SHA_CI_SBOM_PROVENANCE' $ciPass $CIReceipt 'Candidate'
$preview=Resolve-Evidence $LivePreviewReceipt
$previewPass=$null -ne $preview -and $preview.Status -eq 'EXPIRED_CLEAN' -and
    [int]$preview.BackgroundOpacityPercent -eq 0 -and $preview.InstalledMainSHA256Still -eq '05F9E069C4598FDAD327A41BF1CA34A1498D022119DB81E09F4B3B091C9BA377' -and
    [int]$preview.VisibleChartInkPixels -ge 100 -and [int]$preview.HistorySamples -ge 12
Add-Gate 'G10_EMAD_VISUAL_ONLY_ZERO_ALPHA_REAL_METRICS' $previewPass $LivePreviewReceipt 'Candidate'
$nativeGlass=Resolve-Evidence $TopGlassLiveReceipt
$nativeTransitions=Resolve-Evidence $TopGlassTransitionReceipt
$mainActual=(Join-Path $root 'build\_out\App\TaskbarMonitorEnhanced.exe')
$mainDigest=if(Test-Path -LiteralPath $mainActual){(Get-FileHash -LiteralPath $mainActual).Hash}else{''}
$nativePass=$null -ne $nativeGlass -and $null -ne $nativeTransitions -and
    $nativeGlass.Status -eq 'PASS' -and
    $nativeGlass.MainExecutableSHA256 -eq $mainDigest -and
    $nativeGlass.ActualProductionOverlayForm -eq $true -and [int]$nativeGlass.MetricNativeRefreshUploads -ge 2 -and
    $nativeGlass.NoResidentAppTerminated -eq $true -and
    $nativeGlass.BackgroundOpacityPercent -eq 0 -and
    $nativeGlass.NativeLayeredWindow -eq $true -and
    [int]$nativeGlass.RealTextChangedPixels -ge 100 -and
    [int]$nativeGlass.RealChartChangedPixels -ge 100 -and
    [int]$nativeGlass.ActualTransparentBackgroundPixels -gt 10000 -and
    [int]$nativeGlass.ClearAreaChangedPixels -lt 100 -and
    $nativeTransitions.Status -eq 'PASS' -and
    $nativeTransitions.MainExecutableSHA256 -eq $mainDigest -and
    $nativeTransitions.ActualProductionOverlayForm -eq $true -and
    $nativeTransitions.NoInstalledMutation -eq $true -and
    [int]$nativeTransitions.TotalTransitions -eq 4 -and
    [int]$nativeTransitions.RestoredZeroAlphaGlyphPixels -ge 100 -and
    [int]$nativeTransitions.RestoredZeroAlphaChartPixels -ge 100
if($nativePass){
    $expectedPct=@(30,97,100,0)
    for($i=0;$i -lt 4;$i++){
        if($nativeTransitions.Stages[$i].OpacityPercent -ne $expectedPct[$i] -or
           $nativeTransitions.Stages[$i].Pass -ne $true){
            $nativePass=$false;break
        }
    }
}
Add-Gate 'G11_ACTUAL_OVERLAYFORM_TASKBAR_0_30_97_100_0_VISIBILITY' $nativePass $TopGlassLiveReceipt 'Candidate'
$startFloat=Resolve-Evidence $StartFloatLiveReceipt
$startFloatPass=$null -ne $startFloat -and
    $startFloat.Status -eq 'PASS' -and
    $startFloat.ActualProductionOverlayForm -eq $true -and
    $startFloat.MainExecutableSHA256 -eq $mainDigest -and
    [int]$startFloat.NativeStartSamples -eq 24 -and
    [int]$startFloat.ShellSamples -ge 18 -and
    [int]$startFloat.LiftedSamples -eq 24 -and
    [int]$startFloat.SafeLiftedBoundsSamples -eq 24 -and
    [int]$startFloat.VisibleInkSamples -eq 24 -and
    [int]$startFloat.StartLiftCount -ge 1 -and
    [int]$startFloat.StartReturnCount -ge 1 -and
    [int]$startFloat.BeforeStartGlyphs -ge 100 -and
    [int]$startFloat.BeforeStartCharts -ge 100 -and
    [int]$startFloat.AfterStartReturnGlyphs -ge 100 -and
    [int]$startFloat.AfterStartReturnCharts -ge 100 -and
    $startFloat.ReturnedExactNativeRect -eq $true -and
    [int]$startFloat.OriginalResidentPid -gt 0 -and
    $startFloat.NoUserConfigSave -eq $true -and
    $startFloat.NoWindowsSlideshowChange -eq $true -and
    $startFloat.NoInstalledExeReplacement -eq $true -and
    $startFloat.NoProtectionChange -eq $true
if($startFloatPass){
    if(@($startFloat.Frames).Count -ne 24){$startFloatPass=$false}
    else{
        foreach($frame in $startFloat.Frames){
            if($frame.Visible -ne $true -or $frame.StartFloating -ne $true -or
               $frame.SafeRectangle -ne $true -or $frame.HwndVisible -ne $true -or
               [int]$frame.Cloaked -ne 0 -or
               [int]$frame.VisibleText -lt 100 -or [int]$frame.VisibleGraph -lt 100){
                $startFloatPass=$false;break
            }
        }
    }
}
Add-Gate 'G12_START_SEARCH_24_REAL_NATIVE_INK_AND_EXACT_RETURN' $startFloatPass $StartFloatLiveReceipt 'Candidate'
# R74: raw PASS/true flags in an arbitrary JSON are not live host acceptance.
# Require a verified detached Ed25519 witness signature from an independently enrolled lab.
# The trusted-key registry intentionally has ZERO production keys until separately approved.
# R75: G02 hashes deterministic UNSIGNED builder outputs. G14 and G15 must use
# separate SIGNED release staging, since Authenticode modifies executable SHA256.
$signedMainExe=Join-Path $root 'artifacts\signed\Main\TaskbarMonitorEnhanced.exe'
$signedSetupExe=Join-Path $root 'artifacts\signed\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$expectedSignedMainDigest=''
if((Test-Path -LiteralPath $signedMainExe -PathType Leaf) -and
   (Test-Path -LiteralPath $signedSetupExe -PathType Leaf)){
    try {
        if((Get-AuthenticodeSignature -LiteralPath $signedMainExe).Status -eq 'Valid' -and
           (Get-AuthenticodeSignature -LiteralPath $signedSetupExe).Status -eq 'Valid'){
            $candidateSignedHash=(Get-FileHash -LiteralPath $signedMainExe -Algorithm SHA256).Hash
            if($candidateSignedHash -ne $mainDigest){
                $expectedSignedMainDigest=$candidateSignedHash
            }
        }
    } catch { $expectedSignedMainDigest='' }
}
$hostProofTool=Join-Path $root 'build\verify_host_acceptance.py'
$trustedHostRegistry=Join-Path $root 'build\host_acceptance_trust.json'
$hostTrustEnrolled=$false
if((Test-Path -LiteralPath $trustedHostRegistry -PathType Leaf)){
    try {
        $hostTrust=(Get-Content -LiteralPath $trustedHostRegistry -Raw)|ConvertFrom-Json
        $hostTrustEnrolled=($hostTrust.Schema -eq 1) -and (@($hostTrust.TrustedWitnesses).Count -gt 0)
    } catch { $hostTrustEnrolled=$false }
}
$wallpaperPass=$false
$wallpaperEvidence='BLOCKED: G13 requires genuine signed, independently witnessed disposable static-picture Apply+Restore proof'
$installedPass=$false
$installedEvidence='BLOCKED: G14 requires genuine signed, independently witnessed installed eight-probe/Explorer/sensor/rollback proof'
if($hostTrustEnrolled -and (Test-Path -LiteralPath $hostProofTool -PathType Leaf)){
    foreach($gateInfo in @(@('G13',$PositiveWallpaperReceipt),@('G14',$InstalledRuntimeReceipt))){
        $gateName=[string]$gateInfo[0]
        $evidenceFile=[string]$gateInfo[1]
        if([string]::IsNullOrWhiteSpace($evidenceFile)){continue}
        $evidenceFull=if([IO.Path]::IsPathRooted($evidenceFile)){[IO.Path]::GetFullPath($evidenceFile)}
                      else{[IO.Path]::GetFullPath((Join-Path $root $evidenceFile))}
        if(!(Test-Path -LiteralPath $evidenceFull -PathType Leaf)){continue}
        if($gateName -ceq 'G14' -and [string]::IsNullOrWhiteSpace($expectedSignedMainDigest)){
            $installedEvidence='BLOCKED: signed Main+Setup are required, separate from reproducible unsigned builder files'
            continue
        }
        $hostArgs=@('--gate',$gateName,'--receipt',$evidenceFull,'--source',$sha,'--expected-main',$expectedSignedMainDigest)
        try {
            $rawProof=@(& python -B $hostProofTool @hostArgs)
            $proofExit=$LASTEXITCODE
            if($proofExit -eq 0 -and $rawProof.Count -eq 1){
                $proof=$rawProof[0]|ConvertFrom-Json
                $pass=($proof.Status -ceq 'PASS_INDEPENDENT_SIGNED_HOST_EVIDENCE') -and
                      ($proof.Gate -ceq $gateName) -and
                      ($proof.SourceSHA -ceq $sha) -and
                      ($proof.ExternalHostOnly -eq $true) -and
                      ($proof.NoLocalUserMutation -eq $true) -and
                      ![string]::IsNullOrWhiteSpace([string]$proof.WitnessKeyId)
                if($gateName -ceq 'G13'){$wallpaperPass=$pass;$wallpaperEvidence='Signed external witnessed G13 proof: '+[string]$pass}
                if($gateName -ceq 'G14'){$installedPass=$pass;$installedEvidence='Signed external witnessed G14 proof: '+[string]$pass}
            }
        } catch {
            if($gateName -ceq 'G13'){$wallpaperPass=$false}
            if($gateName -ceq 'G14'){$installedPass=$false}
        }
    }
}
Add-Gate 'G13_TRUSTED_STATIC_WALLPAPER_APPLY_RESTORE' $wallpaperPass $wallpaperEvidence 'Stable'
Add-Gate 'G14_INSTALLED_TASKBAR_EXPLORER_SENSORS_ROLLBACK' $installedPass $installedEvidence 'Stable'
$setupExe=$signedSetupExe
$mainExe=$signedMainExe
# Keep original _out builder outputs immutable so G02 exact source checks remain reproducible.
$unsignedSetupExe=Join-Path $root 'build\_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
# R73: G15 must prove actual SignPath Foundation publisher, valid timestamps, matched
# exact file/product versions AND live provider-origin/payload evidence. Never trust
# self-declared "approved" JSON, a test certificate or token-less synthetic output.
$signPass=$false
$g15Evidence='BLOCKED: actual signed Main/Setup not present'
if((Test-Path -LiteralPath $setupExe -PathType Leaf) -and (Test-Path -LiteralPath $mainExe -PathType Leaf)){
    $mainPreHash=(Get-FileHash -LiteralPath $mainExe -Algorithm SHA256).Hash
    $setupPreHash=(Get-FileHash -LiteralPath $setupExe -Algorithm SHA256).Hash
    $setupSig=Get-AuthenticodeSignature -LiteralPath $setupExe
    $mainSig=Get-AuthenticodeSignature -LiteralPath $mainExe
    $setupCert=$setupSig.SignerCertificate
    $mainCert=$mainSig.SignerCertificate
    $setupName=if($setupCert){$setupCert.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false)}else{''}
    $mainName=if($mainCert){$mainCert.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false)}else{''}
    $setupInfo=(Get-Item -LiteralPath $setupExe).VersionInfo
    $mainInfo=(Get-Item -LiteralPath $mainExe).VersionInfo
    $sameCert=$null -ne $setupCert -and $null -ne $mainCert -and $setupCert.Thumbprint -ceq $mainCert.Thumbprint
    $exactMetadata=$setupInfo.ProductName -ceq 'Taskbar Monitor Enhanced' -and
        $mainInfo.ProductName -ceq 'Taskbar Monitor Enhanced' -and
        $setupInfo.ProductVersion -ceq '1.7.8+r286' -and
        $mainInfo.ProductVersion -ceq '1.7.8+r286' -and
        $setupInfo.FileVersion -ceq '1.7.8.0' -and
        $mainInfo.FileVersion -ceq '1.7.8.0'
    $cryptoPass=([string]$mainSig.Status -ceq 'Valid') -and
        ([string]$setupSig.Status -ceq 'Valid') -and
        $mainName -ceq 'SignPath Foundation' -and
        $setupName -ceq 'SignPath Foundation' -and
        $sameCert -and $exactMetadata -and
        ($mainPreHash -ne $mainDigest) -and
        (Test-Path -LiteralPath $unsignedSetupExe -PathType Leaf) -and
        ($setupPreHash -ne (Get-FileHash -LiteralPath $unsignedSetupExe -Algorithm SHA256).Hash) -and
        [bool]$mainSig.TimeStamperCertificate -and
        [bool]$setupSig.TimeStamperCertificate
    $g15Evidence='G15 local Authenticode Main='+[string]$mainSig.Status+
        ';Setup='+[string]$setupSig.Status+
        ';FoundationPublisher='+[string]($mainName -ceq 'SignPath Foundation' -and $setupName -ceq 'SignPath Foundation')+
        ';TimestampPair='+[string]([bool]$mainSig.TimeStamperCertificate -and [bool]$setupSig.TimeStamperCertificate)+
        ';SameCertificate='+[string]$sameCert+';ExactMetadata='+[string]$exactMetadata
    # R80: a signed Setup that embeds the old UNSIGNED Main must be rejected.
    # Independently hash the actual manifest resource from the signed Setup PE,
    # without executing its installer entrypoint or trusting a self-declared JSON.
    $embeddedSignedMainPass=$false
    if($cryptoPass){
        try {
            $embeddedVerifier=Join-Path $root 'build\Verify-Embedded-Main.ps1'
            if(Test-Path -LiteralPath $embeddedVerifier -PathType Leaf){
                $resourceRaw=@(& pwsh -NoProfile -File $embeddedVerifier -SetupExe $setupExe -ExpectedMainSHA256 $mainPreHash)
                $resourceExit=$LASTEXITCODE
                if($resourceExit -eq 0 -and $resourceRaw.Count -eq 1){
                    $resourceProof=$resourceRaw[0]|ConvertFrom-Json
                    $embeddedSignedMainPass=($resourceProof.Status -ceq 'PASS_EMBEDDED_MAIN_EXACT_SHA256') -and
                        ($resourceProof.EmbeddedMainSHA256 -ceq $mainPreHash) -and
                        ($resourceProof.SetupSHA256 -ceq $setupPreHash) -and
                        ([int64]$resourceProof.EmbeddedMainBytes -eq (Get-Item -LiteralPath $mainExe).Length) -and
                        ($resourceProof.ReadOnlyNoInstallerExecution -eq $true) -and
                        ($resourceProof.PawnIOBundled -eq $false)
                }
            }
        } catch { $embeddedSignedMainPass=$false }
    }
    $g15Evidence+=';SignedSetupEmbedsExactSignedMain='+[string]$embeddedSignedMainPass
    $cryptoPass=$cryptoPass -and $embeddedSignedMainPass
    if($cryptoPass){
        $providerAuditor=Join-Path $root 'build\verify_signpath_g15.py'
        $keys=@('SIGNPATH_API_TOKEN','SIGNPATH_ORGANIZATION_ID','SIGNPATH_MAIN_REQUEST_ID',
            'SIGNPATH_SETUP_REQUEST_ID','SIGNPATH_PROJECT_SLUG','SIGNPATH_RELEASE_POLICY_SLUG')
        $configured=(@($keys|Where-Object {[string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_))}).Count -eq 0)
        if($configured -and (Test-Path -LiteralPath $providerAuditor -PathType Leaf)){
            try {
                # PS native args must be one splatted array; do not split command lines before --flags.
                $providerArgs=@('--source',$sha,'--main',$mainExe,'--setup',$setupExe,
                    '--organization-id',[Environment]::GetEnvironmentVariable('SIGNPATH_ORGANIZATION_ID'),
                    '--main-request-id',[Environment]::GetEnvironmentVariable('SIGNPATH_MAIN_REQUEST_ID'),
                    '--setup-request-id',[Environment]::GetEnvironmentVariable('SIGNPATH_SETUP_REQUEST_ID'),
                    '--project-slug',[Environment]::GetEnvironmentVariable('SIGNPATH_PROJECT_SLUG'),
                    '--policy-slug',[Environment]::GetEnvironmentVariable('SIGNPATH_RELEASE_POLICY_SLUG'))
                $providerResult=@(& python -B $providerAuditor @providerArgs)
                $providerExit=$LASTEXITCODE
                if($providerExit -eq 0 -and $providerResult.Count -eq 1){
                    $proof=$providerResult[0]|ConvertFrom-Json
                    $providerMatches=($proof.Status -ceq 'PASS_SIGNPATH_PROVIDER_ORIGIN_AND_EXACT_SIGNED_BINARY') -and
                        ($proof.SourceSHA -ceq $sha) -and
                        ($proof.Main.SignedBinary.SHA256 -ceq $mainPreHash.ToLowerInvariant()) -and
                        ($proof.Setup.SignedBinary.SHA256 -ceq $setupPreHash.ToLowerInvariant()) -and
                        ($proof.Main.Request.Policy -ceq [Environment]::GetEnvironmentVariable('SIGNPATH_RELEASE_POLICY_SLUG')) -and
                        ($proof.Setup.Request.Policy -ceq [Environment]::GetEnvironmentVariable('SIGNPATH_RELEASE_POLICY_SLUG'))
                    $unchanged=(Get-FileHash -LiteralPath $mainExe -Algorithm SHA256).Hash -ceq $mainPreHash -and
                        (Get-FileHash -LiteralPath $setupExe -Algorithm SHA256).Hash -ceq $setupPreHash
                    $signPass=$providerMatches -and $unchanged
                }
                $g15Evidence+=';LiveSignPathProviderAndSignedPayload='+[string]$signPass
            } catch {
                $signPass=$false
                $g15Evidence+=';LiveSignPathProvider=FAILED_CLOSED'
            }
        } else {
            $g15Evidence+=';LiveSignPathRequest=UNAVAILABLE_NO_CREDENTIALS_OR_SIGNING_IDS'
        }
    } else {
        $g15Evidence+=';LiveSignPathRequest=SKIPPED_UNTRUSTED_OR_UNSIGNED'
    }
}
Add-Gate 'G15_AUTHENTICODE_VALID_ON_SETUP_AND_APP' $signPass $g15Evidence 'Stable'
# R72 G16 postpublication gate: a local main SHA match alone is not release evidence.
# Only call live GitHub auditing after independent G13/G14/G15 are PASS.
$mainSHA=(& git -C $root rev-parse main).Trim()
$g16Pass=$false
$g16Evidence='BLOCKED: exact main, G13-G15 and independently downloaded immutable seven-asset release required'
$stablePreconditions=@($gates|Where-Object { $_.Class -eq 'Stable' -and $_.Status -eq 'PASS' })
if($mainSHA -eq $sha -and $stablePreconditions.Count -eq 3){
    $publicAuditor=Join-Path $root 'build\verify_public_release_g16.py'
    if(Test-Path -LiteralPath $publicAuditor -PathType Leaf){
        try {
            $g16Raw=@(& python $publicAuditor --tag v1.7.0 --source $sha)
            $g16Exit=$LASTEXITCODE
            if($g16Exit -eq 0 -and $g16Raw.Count -eq 1){
                $g16Result=$g16Raw[0]|ConvertFrom-Json
                $g16Pass=($g16Result.Status -ceq 'PASS_PUBLICATION_CONTENT_ONLY' -and
                    $g16Result.Tag -ceq 'v1.7.0' -and
                    $g16Result.SourceSHA -ceq $sha -and
                    [int]$g16Result.AssetCount -eq 7 -and
                    [int]$g16Result.ManifestPayloadEntries -eq 5 -and
                    [int]$g16Result.ChecksumEntries -eq 6 -and
                    $g16Result.Immutable -eq $true -and
                    $g16Result.AssetIntegrity -ceq 'PASS' -and
                    [int64]$g16Result.GitHubMainCI -gt 0)
            }
            $g16Evidence='Live v1.7 public seven assets/manifest/checksums/immutable/exact-main-CI: '+[string]$g16Pass
        } catch {
            $g16Pass=$false
            $g16Evidence='BLOCKED: live public release verification failed closed'
        }
    }
} elseif($mainSHA -ne $sha) {
    $g16Evidence='BLOCKED: main '+$mainSHA+' differs from candidate '+$sha
}
Add-Gate 'G16_MAIN_IS_EXACT_APPROVED_COMMIT' $g16Pass $g16Evidence 'Stable'
$required=@($gates|Where-Object {$_.Class -eq 'Candidate'})
$blocked=@($gates|Where-Object {$_.Status -ne 'PASS'})
$ready=$blocked.Count -eq 0
$report=[ordered]@{Schema=1;Project='TaskbarMonitorEnhanced';SourceSHA=$sha;
    CandidateReady=(@($required|Where-Object Status -ne 'PASS').Count -eq 0);
    StableReady=$ready;Overall=$(if($ready){'PASS'}else{'BLOCKED_EXTERNAL_OR_UNPROVEN'});
    EvaluatedUtc=[DateTime]::UtcNow.ToString('o');
    Security='Read-only assessment; never installs, changes wallpaper, signs or publishes.';
    Gates=$gates}
$raw=$report|ConvertTo-Json -Depth 12
if(![string]::IsNullOrWhiteSpace($OutputPath)){
    $full=[IO.Path]::GetFullPath((Join-Path $root $OutputPath))
    if(Test-Path -LiteralPath $full){throw 'Release gate output already exists; no overwrite.'}
    $parent=Split-Path -Parent $full
    New-Item -ItemType Directory -Path $parent -Force|Out-Null
    [IO.File]::WriteAllText($full,$raw,[Text.UTF8Encoding]::new($false))
}
Write-Output $raw
if($RequireStable -and !$ready){exit 45}
if(!($report.CandidateReady)){exit 46}
