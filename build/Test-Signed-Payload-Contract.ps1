# R80 CI only: prove staged Main bytes are the exact bytes embedded in a new Setup.
# Never issues code-signing requests; never installs Setup; never touches desktop or user files.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$original=Join-Path $Root 'build\_out\App\TaskbarMonitorEnhanced.exe'
$setupOrig=Join-Path $Root 'build\_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$inputDir=Join-Path $Root 'artifacts\_r80_contract_input'
$inputFile=Join-Path $inputDir 'TaskbarMonitorEnhanced.exe'
$stageDir=Join-Path $Root 'artifacts\_r80_contract_only'
$stageExe=Join-Path $stageDir 'TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$originalMainSHA=(Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash
$originalSetupSHA=(Get-FileHash -LiteralPath $setupOrig -Algorithm SHA256).Hash
if((Test-Path -LiteralPath $inputDir) -or (Test-Path -LiteralPath $stageDir)){
    throw 'R80 UNSAFE TEST RERUN; STAGING ALREADY EXISTS'
}
$created=$false
try{
    New-Item -ItemType Directory -Path $inputDir -Force | Out-Null
    $created=$true
    [byte[]]$bytes=[IO.File]::ReadAllBytes($original)
    # Change only disposable fixture, never the real unsigned build.
    [byte[]]$suffix=[Text.Encoding]::ASCII.GetBytes('R80_CONTRACT_TEST_TRAILER_NOT_AUTHENTICODE')
    [byte[]]$fixture=New-Object byte[] ($bytes.Length+$suffix.Length)
    [Array]::Copy($bytes,$fixture,$bytes.Length)
    [Array]::Copy($suffix,0,$fixture,$bytes.Length,$suffix.Length)
    [IO.File]::WriteAllBytes($inputFile,$fixture)
    $differentHash=(Get-FileHash -LiteralPath $inputFile -Algorithm SHA256).Hash
    if($differentHash -ceq $originalMainSHA){throw 'R80 FIXTURE HASH NOT DISTINCT'}
    # Fails preflight without even creating output directory.
    $bad=$false
    try{
        & (Join-Path $PSScriptRoot 'Package-Signed-Setup.ps1') -InputMain $inputFile -ExpectedMainSHA256 ('0'*64) -ContractFixtureOnly | Out-Null
    }catch{$bad=$true}
    if(!$bad -or (Test-Path -LiteralPath $stageDir)){throw 'R80 WRONG SHA WAS NOT REJECTED BEFORE MUTATION'}
    $result=@(& (Join-Path $PSScriptRoot 'Package-Signed-Setup.ps1') -InputMain $inputFile -ExpectedMainSHA256 $differentHash -ContractFixtureOnly)
    $proof=Get-Content -LiteralPath (Join-Path $stageDir 'EMBEDDED_MAIN_PROOF.json') -Raw|ConvertFrom-Json
    if($proof.Status -cne 'PASS_CONTRACT_FIXTURE_ONLY_NOT_SIGNED' -or
       $proof.ProductionTrustAccepted -ne $false -or
       $proof.SetupStillNeedsSignPathSignature -ne $true -or
       $proof.MainSHA256 -cne $differentHash -or
       $proof.EmbeddedMainSHA256 -cne $differentHash -or
       [int64]$proof.EmbeddedMainBytes -ne $fixture.Length -or
       [int]$proof.ResourceCount -ne 25 -or
       $proof.PawnIOBundled -ne $false -or
       (Get-AuthenticodeSignature -LiteralPath $stageExe).Status -eq 'Valid'){
        throw 'R80 EMBEDDED MAIN PARITY CONTRACT DID NOT PASS'
    }
    # Independent reflection-based PE manifest verification: a Setup signed later
    # must preserve the byte-for-byte embedded Main payload.
    $reader=Join-Path $PSScriptRoot 'Verify-Embedded-Main.ps1'
    $independent=@(& pwsh -NoProfile -File $reader -SetupExe $stageExe -ExpectedMainSHA256 $differentHash)
    $readExit=$LASTEXITCODE
    if($readExit -ne 0 -or $independent.Count -ne 1){throw 'R80 INDEPENDENT RESOURCE DIGEST VERIFIER FAILED'}
    $readProof=$independent[0]|ConvertFrom-Json
    if($readProof.Status -cne 'PASS_EMBEDDED_MAIN_EXACT_SHA256' -or
       $readProof.EmbeddedMainSHA256 -cne $differentHash -or
       [int64]$readProof.EmbeddedMainBytes -ne $fixture.Length){throw 'R80 INDEPENDENT RESOURCE RESULT DISAGREES'}
    $invalid=@(& pwsh -NoProfile -File $reader -SetupExe $stageExe -ExpectedMainSHA256 $originalMainSHA 2>&1)
    if($LASTEXITCODE -eq 0){throw 'R80 INDEPENDENT VERIFIER FALSELY ACCEPTED UNSIGNED ORIGINAL MAIN'}
    if((Get-FileHash -LiteralPath $original).Hash -cne $originalMainSHA -or
       (Get-FileHash -LiteralPath $setupOrig).Hash -cne $originalSetupSHA){
        throw 'R80 UNSIGNED REPRODUCIBLE BASELINE CHANGED'
    }
    Write-Output ('R80_PASS SYNTHETIC_ONLY EMBEDDED_MAIN_SHA256='+$proof.EmbeddedMainSHA256+
        ' EMBEDDED_MAIN_BYTES='+$proof.EmbeddedMainBytes+' RESOURCES='+$proof.ResourceCount+' PAWNIO_BUNDLED='+$proof.PawnIOBundled+
        ' UNSIGNED_BASELINE_PRESERVED=TRUE')
} finally {
    if($created){
        # Cleanup exact owned files only. Unknown files survive; never delete personal state.
        foreach($d in @($stageDir,$inputDir)){
            if(Test-Path -LiteralPath $d){
                $allowed=if($d -ceq $stageDir){@('TaskbarMonitorEnhanced_Setup_1.7.8.exe','TaskbarMonitorEnhanced_Setup_1.7.8.exe.config','SETUP_VERIFY.json','EMBEDDED_MAIN_PROOF.json')}
                         else{@('TaskbarMonitorEnhanced.exe')}
                $found=@(Get-ChildItem -LiteralPath $d -Force)
                if(@($found|Where-Object {$_.PSIsContainer -or $_.Name -notin $allowed}).Count -gt 0){
                    throw "R80 DEGRADED UNKNOWN STAGED FILES: $d; NO CLEANUP"
                }
                foreach($f in $found){Remove-Item -LiteralPath $f.FullName -ErrorAction Stop}
                if(@(Get-ChildItem -LiteralPath $d -Force).Count -ne 0){throw "R80 DEGRADED NONEMPTY DIRECTORY $d"}
                Remove-Item -LiteralPath $d -ErrorAction Stop
            }
        }
    }
}
# Nested negative tests intentionally return nonzero; clear only after all proof and cleanup.
exit 0
