[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$AssemblyPath,
  [switch]$LocalFixture
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop'){throw 'R091_REQUIRES_NATIVE_WINDOWS_POWERSHELL51'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$head=(git -C $root rev-parse HEAD).Trim()
if([string]::IsNullOrWhiteSpace($head)){throw 'R091_GIT_REVISION_NOT_AVAILABLE'}
$built=[IO.Path]::GetFullPath($AssemblyPath)
if(-not(Test-Path -LiteralPath $built -PathType Leaf)){throw 'R091_COMPILED_SETUP_PE_NOT_PRESENT'}
$hosted=(!$LocalFixture)
if($hosted){
  if($env:GITHUB_ACTIONS -cne 'true' -or
     $env:RUNNER_OS -cne 'Windows' -or
     $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
     $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
     $env:GITHUB_SHA -cne $head -or
     [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
       throw 'R091_ONLY_EXACT_SOURCE_HOSTED_DISPOSABLE_WINDOWS'
  }
  $expected=[IO.Path]::GetFullPath((Join-Path $root 'build/_out/Setup/TaskbarMonitorEnhanced_Setup_1.7.8.exe'))
  if(-not[string]::Equals($expected,$built,[StringComparison]::OrdinalIgnoreCase)){
    throw 'R091_HOSTED_ASSEMBLY_NOT_BUILT_FROM_CURRENT_CHECKOUT'
  }
}else{
  if($root -notlike '*tv-tbme-r091-direct-unicode-shelllink-20261017'){
    throw 'R091_LOCAL_TEST_FIXTURE_SOURCE_NOT_ISOLATED'
  }
  $expected=[IO.Path]::GetFullPath((Join-Path $root '_r091_exact_source_testonly.dll'))
  if(-not[string]::Equals($expected,$built,[StringComparison]::OrdinalIgnoreCase)){
    throw 'R091_LOCAL_COMPILED_ASSEMBLY_IDENTITY_NOT_MATCHED'
  }
}
$base=if($hosted){[IO.Path]::GetFullPath($env:RUNNER_TEMP)}else{[IO.Path]::GetFullPath([IO.Path]::GetTempPath())}
$base=$base.TrimEnd([IO.Path]::DirectorySeparatorChar)
$fixture=Join-Path $base ('tbme_r091_native_fixture_'+[Guid]::NewGuid().ToString('N'))
if(Test-Path -LiteralPath $fixture){throw 'R091_RANDOM_FIXTURE_PREEXISTS'}
if(-not[string]::Equals([IO.Path]::GetDirectoryName($fixture),$base,[StringComparison]::OrdinalIgnoreCase)){
  throw 'R091_NOT_DIRECT_CHILD_OF_TEST_TEMP'
}
$tester=Join-Path $root 'build/Test-R091-ShortcutShellLink-Native.cs'
if(-not(Test-Path -LiteralPath $tester -PathType Leaf)){throw 'R091_VERSIONED_NATIVE_TEST_SOURCE_MISSING'}
$csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if(-not(Test-Path -LiteralPath $csc -PathType Leaf)){throw 'R091_NATIVE_FRAMEWORK_4_8_COMPILER_MISSING'}
[void][IO.Directory]::CreateDirectory($fixture)
$passed=$false
try{
   $testExe=Join-Path $fixture 'Test-R091-Shortcuts.exe'
   & $csc /nologo /target:exe /platform:x64 ("/out:"+$testExe) $tester 2>&1
   if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $testExe -PathType Leaf)){
      throw 'R091_NATIVE_COM_SECURITY_TEST_BUILD_FAILED'
   }
   & $testExe $built $root 2>&1
   if($LASTEXITCODE -ne 0){throw 'R091_ACTUAL_COMPILED_SETUP_SHORTCUT_TEST_FAILED'}
   $extra=@(Get-ChildItem -LiteralPath $fixture -File -Force)
   if($extra.Count -ne 1 -or $extra[0].Name -cne 'Test-R091-Shortcuts.exe'){
      throw 'R091_TEST_CREATED_UNEXPECTED_FILES_IN_HOST_FIXTURE'
   }
   $passed=$true
   'R091_ACTUAL_SETUP_NATIVE_UNICODE_SHELLLINK_WINDOWS=PASS'
   'R091_NO_TEMP_POWER_SHELL_SCRIPT_AND_NO_UAC=PASS'
   'R091_EXACT_SOURCE_SHA='+ $head
}finally{
   if($passed){
      [IO.File]::Delete((Join-Path $fixture 'Test-R091-Shortcuts.exe'))
      [IO.Directory]::Delete($fixture,$false)
      if(Test-Path -LiteralPath $fixture){throw 'R091_TEST_OWNED_FIXTURE_CLEANUP_FAILED'}
   }else{
      Write-Warning ('R091 dedicated test-owned Temp fixture retained for diagnosis: '+$fixture)
   }
}