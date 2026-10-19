[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$AuthorityPath,
 [Parameter(Mandatory=$true)][string]$ReceiptPath,
 [Parameter(Mandatory=$true)][string]$StopPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:GITHUB_EVENT_NAME -cne 'pull_request' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'Usefull-Skills/TaskbarMonitorEnhanced' -or
   $env:GITHUB_REF -cne 'refs/pull/10/merge' -or
   $env:GITHUB_HEAD_REF -cne 'qa/r349-r093-r091-integration-20261019' -or
   $env:GITHUB_BASE_REF -cne 'sync/personal-main-9960a06d-review' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC|ALIEMAD|SAEID|LAPTOP' -or
   $env:QA_SOURCE_SHA -cnotmatch '^[0-9a-f]{40}$'){
 throw 'R350_ACTOR_NOT_DISPOSABLE_EXACT_PR_SOURCE'
}
$principal=[Security.Principal.WindowsPrincipal]::new(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 throw 'R350_ACTOR_ALREADY_ADMIN_REQUIRED'
}
$temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')+'\'
foreach($path in @($AuthorityPath,$ReceiptPath,$StopPath)){
 if(![IO.Path]::GetFullPath($path).StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)){
  throw 'R350_ACTOR_CONTROL_OUTSIDE_RUNNER_TEMP'
 }
}
if([IO.File]::Exists($ReceiptPath) -or [IO.File]::Exists($StopPath)){
 throw 'R350_ACTOR_RECEIPT_OR_STOP_PREEXISTED'
}
$a=Get-Content -LiteralPath $AuthorityPath -Raw | ConvertFrom-Json
$expected=Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'TaskbarMonitorEnhanced\SensorBroker\TaskbarMonitorSensorBroker.exe'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($a.Schema -ne 1 -or $a.Revision -cne 'R350' -or
   $a.SourceCommit -cne $env:QA_SOURCE_SHA -or
   $a.Guest -cne $env:COMPUTERNAME -or
   $a.Sid -cne $sid -or
   -not [string]::Equals([IO.Path]::GetFullPath([string]$a.Target),
                         [IO.Path]::GetFullPath($expected),
                         [StringComparison]::OrdinalIgnoreCase) -or
   ![IO.File]::Exists($expected)){
 throw 'R350_ACTOR_AUTHORITY_OR_TARGET_INVALID'
}
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class R350ScopedDeleteLease {
 [DllImport("kernel32.dll",EntryPoint="CreateFileW",SetLastError=true,CharSet=CharSet.Unicode)]
 static extern SafeFileHandle Open(string path,uint access,uint share,IntPtr sec,uint creation,uint flags,IntPtr template);
 public static SafeFileHandle Acquire(string path) {
  SafeFileHandle h=Open(path,0x00010000,7,IntPtr.Zero,3,0x00200000,IntPtr.Zero);
  if(h.IsInvalid){int e=Marshal.GetLastWin32Error();h.Dispose();throw new IOException("R350_ACTOR_DELETE_HANDLE_FAILED_WIN32_"+e);}
  return h;
 }
}
'@
$held=$null
$released=$false
try {
 $held=[R350ScopedDeleteLease]::Acquire($expected)
 $proof=[ordered]@{
  Schema=1;Revision='R350';Status='PREOPENED_DELETE_HANDLE_HELD'
  SourceCommit=$env:QA_SOURCE_SHA;Guest=$env:COMPUTERNAME;ActorPid=$PID
  AlreadyAdmin=$true;Target=$expected;OwnerMachineTouched=$false
 }
 [IO.File]::WriteAllText($ReceiptPath,($proof|ConvertTo-Json -Compress -Depth 4),
   [Text.UTF8Encoding]::new($false))
 $until=[DateTime]::UtcNow.AddSeconds(60)
 while([DateTime]::UtcNow -lt $until){
  if([IO.File]::Exists($StopPath)){$released=$true;break}
  Start-Sleep -Milliseconds 20
 }
 if(-not $released){throw 'R350_ACTOR_STOP_NOT_OBSERVED_IN_60_SECONDS'}
}finally{
 if($null -ne $held){$held.Dispose()}
}
'R350_DISTINCT_ALREADY_ADMIN_DELETE_HANDLE_RELEASED=PASS'
