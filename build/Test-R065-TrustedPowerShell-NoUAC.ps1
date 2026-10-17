[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$AssemblyPath,
    [switch]$LocalFixture
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Never run Setup, invoke UAC or mutate an installed product.
if($PSVersionTable.PSEdition -cne 'Desktop'){
    throw 'R065_WINDOWS_POWERSHELL_51_REQUIRED'
}
if(-not $LocalFixture){
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or
       $env:COMPUTERNAME -match '(?i)EMAD-PC'){
        throw 'R065_ONLY_DISPOSABLE_HOSTED_WINDOWS'
    }
    if((git rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){
        throw 'R065_SOURCE_HEAD_MISMATCH'
    }
}
$full=[IO.Path]::GetFullPath($AssemblyPath)
if(-not [IO.File]::Exists($full)){throw 'R065_SETUP_ASSEMBLY_MISSING'}
if($LocalFixture){
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if(-not $full.StartsWith($temp,[StringComparison]::OrdinalIgnoreCase) -or
       $full -notmatch '(?i)_r065_rebased_setup_only\.dll$'){
        throw 'R065_LOCAL_FIXTURE_NOT_BOUNDED'
    }
}
$assembly=[Reflection.Assembly]::LoadFile($full)
$type=$assembly.GetType('SetupProgram',$true)
$method=$type.GetMethod('TrustedWindowsPowerShellExecutable',[Reflection.BindingFlags]'NonPublic,Static')
if($null -eq $method){throw 'R065_METHOD_MISSING_IN_BUILT_SETUP'}
$trusted=[string]$method.Invoke($null,$null)
$expected=[IO.Path]::GetFullPath((Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'))
if(-not [IO.Path]::IsPathRooted($trusted) -or
   -not [string]::Equals($trusted,$expected,[StringComparison]::OrdinalIgnoreCase) -or
   -not [IO.File]::Exists($trusted) -or
   (Get-AuthenticodeSignature -LiteralPath $trusted).Status -cne 'Valid'){
    throw 'R065_OS_EXECUTABLE_IDENTITY_NOT_PROVEN'
}
$fixtureBase=if($LocalFixture){[IO.Path]::GetTempPath()}else{$env:RUNNER_TEMP}
$fixture=Join-Path $fixtureBase ('tbme_r065_path_bait_'+[Guid]::NewGuid().ToString('N'))
if(Test-Path -LiteralPath $fixture){throw 'R065_TEST_FIXTURE_ALREADY_EXISTS'}
[void][IO.Directory]::CreateDirectory($fixture)
$baitSource=Join-Path $fixture 'bait.cs'
$baitExe=Join-Path $fixture 'powershell.exe'
$sentinel=Join-Path $fixture 'BAIT_EXECUTED'
$baitCode=@"
using System;
using System.IO;
public class Bait {
 public static int Main() {
  string s=Environment.GetEnvironmentVariable("TBME_R065_SENTINEL");
  if(!String.IsNullOrWhiteSpace(s)) File.WriteAllText(s,"BAIT");
  return 79;
 }
}
"@
$savePath=$env:PATH
$saveSentinel=$env:TBME_R065_SENTINEL
try{
    [IO.File]::WriteAllText($baitSource,$baitCode,[Text.UTF8Encoding]::new($false))
    $csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64/v4.0.30319/csc.exe'
    if(-not (Test-Path -LiteralPath $csc -PathType Leaf)){throw 'R065_NET48_CSC_MISSING'}
    & $csc /nologo /target:exe ("/out:"+$baitExe) $baitSource
    if($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $baitExe -PathType Leaf)){
        throw 'R065_DISPOSABLE_BAIT_COMPILATION_FAILED'
    }
    $env:PATH=$fixture+';'+$savePath
    $env:TBME_R065_SENTINEL=$sentinel
    if([string]::Equals($trusted,$baitExe,[StringComparison]::OrdinalIgnoreCase)){
        throw 'R065_BAIT_SELECTED_INSTEAD_OF_SYSTEM_EXECUTABLE'
    }
    $psi=[Diagnostics.ProcessStartInfo]::new()
    $psi.FileName=$trusted
    $psi.WorkingDirectory=[IO.Path]::GetDirectoryName($trusted)
    $psi.Arguments='-NoProfile -NonInteractive -Command "exit 0"'
    $psi.UseShellExecute=$true
    $psi.Verb=''  # never UAC/runas
    $psi.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    $child=[Diagnostics.Process]::Start($psi)
    if($null -eq $child){throw 'R065_TRUSTED_NON_UAC_PROCESS_NOT_CREATED'}
    try{
        if(-not $child.WaitForExit(15000)){
            try{$child.Kill()}catch{}
            throw 'R065_TRUSTED_PROCESS_TIMEOUT'
        }
        if($child.ExitCode -ne 0){throw 'R065_TRUSTED_PROCESS_EXIT_FAILURE'}
    }finally{$child.Dispose()}
    if(Test-Path -LiteralPath $sentinel){throw 'R065_UNTRUSTED_PATH_BAIT_EXECUTED'}
    'R065_REAL_SHELLEXECUTE_BAIT_NOT_LAUNCHED=PASS'
    'R065_TESTED_BUILD_SHA256='+((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash)
    'R065_UAC_OR_INSTALLED_SERVICE_CALLED=FALSE'
}finally{
    $env:PATH=$savePath
    $env:TBME_R065_SENTINEL=$saveSentinel
    if(Test-Path -LiteralPath $fixture){[IO.Directory]::Delete($fixture,$true)}
}