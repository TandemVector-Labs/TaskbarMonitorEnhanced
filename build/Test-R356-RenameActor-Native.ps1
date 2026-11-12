[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][ValidateSet('Before','During')][string]$Phase,
 [Parameter(Mandatory=$true)][string]$PathB64,
 [Parameter(Mandatory=$true)][string]$CanaryB64
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'GOD13emad/TaskbarMonitorEnhanced' -or
   $env:GITHUB_REF -cne 'refs/heads/audit/r356-handle-bound-directory-disposition' -or
   $env:GITHUB_SHA -cnotmatch '^[a-f0-9]{40}$'){
 throw 'R356_RENAME_ACTOR_GUEST_ONLY'
}
$path=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($PathB64))
$canary=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($CanaryB64))
$temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\')+'\'
foreach($p in @($path,$canary)){
 if(![IO.Path]::GetFullPath($p).StartsWith($temp,[StringComparison]::OrdinalIgnoreCase)){
   throw 'R356_RENAME_ACTOR_PATH_ESCAPED_RUNNER_TEMP'
 }
}
if($path -cnotmatch '\\R356_[AB]_[0-9]{5,20}\\delete-only-this-directory$' -or
   -not [IO.Directory]::Exists($path) -or -not [IO.File]::Exists($canary)){
 throw 'R356_RENAME_ACTOR_FIXED_SYNTHETIC_FIXTURE_MISSING'
}
$sha=(Get-FileHash -LiteralPath $canary -Algorithm SHA256).Hash
$renamed=$path+'_moved'
if([IO.Directory]::Exists($renamed) -or [IO.File]::Exists($renamed)){
 throw 'R356_RENAME_ACTOR_DESTINATION_ALREADY_OCCUPIED'
}
$allowed=$false;$win32=-1
try{
 [IO.Directory]::Move($path,$renamed)
 [IO.Directory]::Move($renamed,$path)
 $allowed=$true;$win32=0
}catch [IO.IOException]{
 $win32=$_.Exception.HResult -band 65535
 if([IO.Directory]::Exists($renamed) -and -not [IO.Directory]::Exists($path)){
   try{[IO.Directory]::Move($renamed,$path)}catch{throw 'R356_ACTOR_RESTORE_OF_RENAMED_DIRECTORY_FAILED'}
 }
}catch [UnauthorizedAccessException]{
 $win32=$_.Exception.HResult -band 65535
}
if((Get-FileHash -LiteralPath $canary -Algorithm SHA256).Hash -cne $sha){
 throw 'R356_ACTOR_OUTSIDE_CANARY_CHANGED'
}
if(-not [IO.Directory]::Exists($path)){
 throw 'R356_ACTOR_ORIGINAL_PATH_NOT_PRESENT_AFTER_PROBE'
}
if($Phase -ceq 'Before' -and (-not $allowed -or $win32 -ne 0)){
 throw ('R356_ACTOR_BEFORE_MUST_SUCCEED_WIN32_'+$win32)
}
if($Phase -ceq 'During' -and ($allowed -or $win32 -ne 32)){
 throw ('R356_ACTOR_DURING_MUST_DENY_NATIVE_SHARE32_GOT_'+$win32)
}
[ordered]@{
 Revision='R356';SourceCommit=$env:GITHUB_SHA;Phase=$Phase
 Pid=$PID;RenameAllowed=$allowed;Win32Error=$win32;CanaryUnchanged=$true
}|ConvertTo-Json -Compress
