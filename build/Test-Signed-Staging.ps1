# R75 exact negative regression: unsigned builder files copied into signed-release staging
# must NEVER count as trusted signed files, while G02 unsigned SHA/determinism stays PASS.
# Transactional and non-overwriting: only deletes files created by this exact invocation.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$stage=Join-Path $root 'artifacts\signed'
$origMain=Join-Path $root 'build\_out\App\TaskbarMonitorEnhanced.exe'
$origSetup=Join-Path $root 'build\_out\Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$targetMain=Join-Path $stage 'Main\TaskbarMonitorEnhanced.exe'
$targetSetup=Join-Path $stage 'Setup\TaskbarMonitorEnhanced_Setup_1.7.8.exe'
$created=@()
if((Test-Path -LiteralPath $stage) -or
   !(Test-Path -LiteralPath $origMain -PathType Leaf) -or
   !(Test-Path -LiteralPath $origSetup -PathType Leaf)){
    throw 'R75 REFUSE: staging already exists or exact unsigned source missing'
}
$hashMain=(Get-FileHash -LiteralPath $origMain -Algorithm SHA256).Hash
$hashSetup=(Get-FileHash -LiteralPath $origSetup -Algorithm SHA256).Hash
$expected=@{
    "$targetMain"=$hashMain
    "$targetSetup"=$hashSetup
}
$manifest=Join-Path $root 'artifacts\BUILD_MANIFEST.json'
if(!(Test-Path -LiteralPath $manifest -PathType Leaf)){throw 'R75 MANIFEST REQUIRED'}
$m=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
$mapping=@{
    'TaskbarMonitorEnhanced.exe'=$hashMain
    'TaskbarMonitorEnhanced_Setup_1.7.8.exe'=$hashSetup
}
foreach($entry in $m.Outputs){
    if($mapping.ContainsKey([string]$entry.Name)){
        if($mapping[[string]$entry.Name] -cne [string]$entry.SHA256){throw 'R75 UNSIGNED BUILD OUTPUT SHA DRIFT'}
    }
}
try {
    New-Item -ItemType Directory -Path (Split-Path $targetMain -Parent) -Force|Out-Null
    New-Item -ItemType Directory -Path (Split-Path $targetSetup -Parent) -Force|Out-Null
    Copy-Item -LiteralPath $origMain -Destination $targetMain -ErrorAction Stop
    $created+= $targetMain
    Copy-Item -LiteralPath $origSetup -Destination $targetSetup -ErrorAction Stop
    $created+= $targetSetup
    foreach($f in $created){
        if((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash -cne $expected[$f]){throw 'R75 STAGED COPY SHA MISMATCH'}
    }
    $sigMain=Get-AuthenticodeSignature -LiteralPath $targetMain
    $sigSetup=Get-AuthenticodeSignature -LiteralPath $targetSetup
    if($sigMain.Status -eq 'Valid' -or $sigSetup.Status -eq 'Valid'){throw 'R75 EXPECTED UNSIGNED NEGATIVE FIXTURES'}
    $output=@(& pwsh -NoProfile -File (Join-Path $root 'build\Test-Release-Gates.ps1') -RequireStable)
    $code=$LASTEXITCODE
    if($code -ne 45){throw 'R75 STABLE FALSE POSITIVE'}
    $report=($output|Out-String)|ConvertFrom-Json
    if($report.StableReady){throw 'R75 FAKED STABLE'}
    $g2=@($report.Gates|Where-Object Gate -eq 'G02_FIVE_ACTUAL_SHA256_OUTPUTS')
    $g14=@($report.Gates|Where-Object Gate -like 'G14_*')
    $g15=@($report.Gates|Where-Object Gate -like 'G15_*')
    if($g2.Count -ne 1 -or $g2[0].Status -ne 'PASS' -or
       $g14.Count -ne 1 -or $g14[0].Status -ne 'BLOCKED' -or
       $g15.Count -ne 1 -or $g15[0].Status -ne 'BLOCKED'){throw 'R75 SIGNED/UNSIGNED HASH IDENTITY CONTRACT FAILED'}
    Write-Output ('R75_PASS G02=PASS G14=BLOCKED G15=BLOCKED UNSIGNED_COPY_SHA_MAIN='+$hashMain+' UNSIGNED_COPY_SHA_SETUP='+$hashSetup)
} finally {
    foreach($f in $created){
        if(Test-Path -LiteralPath $f -PathType Leaf){
            if((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash -cne $expected[$f]){
                throw ('R75 DEGRADED: owned stage file modified; NO UNSAFE CLEANUP: '+$f)
            }
            Remove-Item -LiteralPath $f -ErrorAction Stop
        }
    }
    foreach($folder in @((Split-Path $targetSetup -Parent),(Split-Path $targetMain -Parent),$stage)){
        if(Test-Path -LiteralPath $folder -PathType Container){
            if(@(Get-ChildItem -LiteralPath $folder -Force).Count -eq 0){Remove-Item -LiteralPath $folder -ErrorAction Stop}
        }
    }
    if((Get-FileHash -LiteralPath $origMain -Algorithm SHA256).Hash -cne $hashMain -or
       (Get-FileHash -LiteralPath $origSetup -Algorithm SHA256).Hash -cne $hashSetup){
        throw 'R75 DEGRADED UNSIGNED BUILD ARTIFACT DRIFT'
    }
}
# Nested strict gate exit 45 is expected; only after ALL proof checks and cleanup above
# return successful wrapper status for the CI step. Failures throw and never reach here.
exit 0
