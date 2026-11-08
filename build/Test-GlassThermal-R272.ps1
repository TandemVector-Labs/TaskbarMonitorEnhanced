[CmdletBinding()]
param(
    [string]$MainPath='',
    [string]$OutDir=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($MainPath)){$MainPath=Join-Path $PSScriptRoot '_out\App\TaskbarMonitorEnhanced.exe'}
if([string]::IsNullOrWhiteSpace($OutDir)){$OutDir=Join-Path $PSScriptRoot '..\artifacts\thermal-r272'}
$MainPath=(Resolve-Path -LiteralPath $MainPath).Path
$OutDir=[IO.Path]::GetFullPath($OutDir)
if(Test-Path $OutDir){throw 'R272 output already exists: fail closed against stale evidence'}
[void][IO.Directory]::CreateDirectory($OutDir)
$expectedSha=(Get-FileHash -LiteralPath $MainPath -Algorithm SHA256).Hash
$sourceHead=(& git -C (Join-Path $PSScriptRoot '..') rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0){throw 'R272 git source head unavailable'}
$dir=Join-Path $OutDir 'real-thermal-pixels'
$p=[Diagnostics.Process]::new()
$p.StartInfo.FileName=$MainPath
$p.StartInfo.Arguments='--glassthermalproof "'+$dir+'"'
$p.StartInfo.UseShellExecute=$false
$p.StartInfo.CreateNoWindow=$true
$p.StartInfo.RedirectStandardOutput=$true
$p.StartInfo.RedirectStandardError=$true
try{
    if(!$p.Start()){throw 'R272 child process did not start'}
    $stdoutAsync=$p.StandardOutput.ReadToEndAsync()
    $stderrAsync=$p.StandardError.ReadToEndAsync()
    if(!$p.WaitForExit(180000)){
        try{$p.Kill();$p.WaitForExit()}catch{}
        throw 'R272 child process timeout'
    }
    $p.WaitForExit()
    $code=$p.ExitCode
    $stdout=$stdoutAsync.GetAwaiter().GetResult()
    $stderr=$stderrAsync.GetAwaiter().GetResult()
}finally{$p.Dispose()}
[IO.File]::WriteAllText((Join-Path $OutDir 'child-stdout.txt'),$stdout,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $OutDir 'child-stderr.txt'),$stderr,[Text.UTF8Encoding]::new($false))
if($code -ne 0 -or !$stdout.Contains('TBME_THERMAL_GLASS_PROOF=PASS') -or $stderr.Contains('=FAIL')){
    throw ('R272 native compiled pixel proof failed childCode='+$code+' stdout='+$stdout+' stderr='+$stderr)
}
$receiptPath=Join-Path $dir 'THERMAL_GLASS_PROOF.json'
if(!(Test-Path $receiptPath)){throw 'R272 typed receipt absent'}
$v=Get-Content $receiptPath -Raw | ConvertFrom-Json
if($v.Revision -cne 'R272' -or $v.Status -cne 'PASS' -or
   $v.Source -cne 'REAL_OVERLAY_THEME_AND_METRIC_PAINTER' -or
   $v.HotC -ne 95 -or $v.ColdC -ne 60 -or $v.ThresholdC -ne 85 -or
   $v.Themes -ne 49 -or $v.ThemeBackgroundPairs -ne 98 -or
   $v.HotRedPixelsMinimum -lt 40 -or $v.ColdRedPixelsMaximum -ne 0 -or
   $v.ClearBackgroundPixelsMinimum -le 7440 -or
   $v.OptOutTested -ne $true -or $v.NoNativeHostInput -ne $true -or
   $v.NoUserSettingsOrSensorMutation -ne $true){
    throw 'R272 typed 49-theme thermal pixel acceptance contract failed'
}
$actualSha=(Get-FileHash $MainPath -Algorithm SHA256).Hash
if($actualSha -cne $expectedSha){throw 'R272 compiled Main mutated after proof'}
$receipt=[ordered]@{
    Revision='R272'
    Status='PASS'
    GitHead=$sourceHead
    MainSHA256=$expectedSha
    PixelReceiptSHA256=(Get-FileHash $receiptPath).Hash
    ThemePairs=$v.ThemeBackgroundPairs
    AlertPixelMinimum=$v.HotRedPixelsMinimum
    ColdPixelMaximum=$v.ColdRedPixelsMaximum
    ClearPixelMinimum=$v.ClearBackgroundPixelsMinimum
    VisualScope='Real production bitmap painter with synthetic CPU temperature; no live HWND or notification'
}
[IO.File]::WriteAllText((Join-Path $OutDir 'R272_ACCEPTANCE.json'),($receipt|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
Write-Output ('TBME_R272_THERMAL_GLASS=PASS 49_THEMES=TRUE PAIRS='+$v.ThemeBackgroundPairs+' MIN_RED='+$v.HotRedPixelsMinimum+' BINARY_SHA='+$expectedSha)
