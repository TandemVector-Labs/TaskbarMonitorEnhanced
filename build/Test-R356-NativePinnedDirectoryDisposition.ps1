[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# R356 native feasibility probe only. NO production Setup/Helper mutation.
# Runs on disposable, already-admin GitHub-hosted Windows jobs only.
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:GITHUB_REPOSITORY -cne 'GOD13emad/TaskbarMonitorEnhanced' -or
   $env:GITHUB_REF -cne 'refs/heads/audit/r356-handle-bound-directory-disposition' -or
   $env:GITHUB_SHA -cnotmatch '^[a-f0-9]{40}$' -or
   $env:GITHUB_RUN_ID -cnotmatch '^[0-9]{5,20}$' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC|ALIEMAD|SAEID|LAPTOP' -or
   (git -C $PSScriptRoot rev-parse HEAD).Trim() -cne $env:GITHUB_SHA){
  throw 'R356_REFUSE_NON_DISPOSABLE_UNPINNED_SOURCE'
}
$admin=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(!$admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
  throw 'R356_ALREADY_ADMIN_GITHUB_WINDOWS_REQUIRED'
}
$native=Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
$actorScript=Join-Path $PSScriptRoot 'Test-R356-RenameActor-Native.ps1'
if(![IO.File]::Exists($native) -or ![IO.File]::Exists($actorScript)){throw 'R356_REQUIRED_NATIVE_SOURCES_MISSING'}
$temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP)
$testRoot=Join-Path $temp ('R356_'+$HostLabel+'_'+$env:GITHUB_RUN_ID)
if([IO.Directory]::Exists($testRoot) -or [IO.File]::Exists($testRoot)){throw 'R356_FIXTURE_PREEXISTS'}
[void][IO.Directory]::CreateDirectory($testRoot)
$target=Join-Path $testRoot 'delete-only-this-directory'
$outside=Join-Path $testRoot 'outside'
$canary=Join-Path $outside 'EXTERNAL_UNTOUCHED.txt'
$leaf=Join-Path $target 'test-leaf.txt'
$receipt=Join-Path $testRoot 'R356_DIRECTORY_DISPOSITION_NATIVE.json'
$checks=[Collections.Generic.List[string]]::new()
$parentPin=$null;$childPin=$null
$exitFailure='';$phase='START'
$preActorPid=0;$inActorPid=0;$nonemptyError=-1;$dispositionCode=-1;$preAllowed=$false;$inDenied=$false;$unlinkDone=$false;$outsideIntact=$false;$cleanupDone=$false
function Check([string]$label){[void]$script:checks.Add($label);Write-Output ('PASS '+$label)}
function Hash-R356File([string]$file){return (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}
function Invoke-Actor([string]$which,[string]$path,[string]$externalMarker){
  $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($path))
  $e=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($externalMarker))
  $psi=[Diagnostics.ProcessStartInfo]::new()
  $psi.FileName=$native
  $psi.Arguments='-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$actorScript+'" -Phase '+$which+' -PathB64 '+$encoded+' -CanaryB64 '+$e
  $psi.UseShellExecute=$false
  $psi.CreateNoWindow=$true
  $psi.RedirectStandardOutput=$true
  $psi.RedirectStandardError=$true
  $proc=[Diagnostics.Process]::Start($psi)
  if(!$proc){throw ('R356_NATIVE_ACTOR_START_FAILED_'+$which)}
  try{
    if(!$proc.WaitForExit(20000)){
      if(!$proc.HasExited){$proc.Kill();[void]$proc.WaitForExit(4000)}
      throw ('R356_NATIVE_ACTOR_TIMEOUT_'+$which)
    }
    $out=$proc.StandardOutput.ReadToEnd()
    $err=$proc.StandardError.ReadToEnd()
    if($proc.ExitCode -ne 0){throw ('R356_NATIVE_ACTOR_FAILED_'+$which+'_'+$err+'_'+$out)}
    $json=$out|ConvertFrom-Json
    if($json.Revision -cne 'R356' -or $json.SourceCommit -cne $env:GITHUB_SHA -or
       $json.Phase -cne $which -or $json.Pid -le 0 -or $json.CanaryUnchanged -ne $true){
      throw ('R356_NATIVE_ACTOR_RECEIPT_INVALID_'+$which)
    }
    return $json
  }finally{$proc.Dispose()}
}
try{
 $phase='CREATE_SYNTHETIC_TEMP_ONLY'
 [void][IO.Directory]::CreateDirectory($target)
 [void][IO.Directory]::CreateDirectory($outside)
 [IO.File]::WriteAllText($canary,'R356_OUTSIDE_CANARY_NEVER_CHANGE',[Text.UTF8Encoding]::new($false))
 $outsideSha=Hash-R356File $canary
 [IO.File]::WriteAllText($leaf,'R356_TEMP_LEAF_ONLY',[Text.UTF8Encoding]::new($false))
 Check 'ONLY_FRESH_HOSTED_RUNNER_TEMP_SYNTHETIC_FILES'
 $phase='COMPILE_NATIVE_DISPOSITION_CLASS'
 Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public sealed class R356NativeDirectoryLease : IDisposable {
 const uint LIST=1,DELETE=0x00010000,SHARE_READ_WRITE=3,EXISTING=3, BACKUP=0x02000000,REPARSE=0x00200000;
 const uint DIRECTORY=0x10,TAG_REPARSE=0x400;
 [StructLayout(LayoutKind.Sequential)] private struct ATTRTAG {public uint Attributes; public uint ReparseTag;}
 [StructLayout(LayoutKind.Sequential)] private struct DISPOSITION {public byte DeleteFile;}
 [DllImport("kernel32.dll",EntryPoint="CreateFileW",CharSet=CharSet.Unicode,SetLastError=true)]
 static extern SafeFileHandle Open(string path,uint access,uint sharing,IntPtr security,uint creation,uint flags,IntPtr template);
 [DllImport("kernel32.dll",EntryPoint="GetFileInformationByHandleEx",SetLastError=true)]
 static extern bool Info(SafeFileHandle handle,int cls,out ATTRTAG tag,uint len);
 [DllImport("kernel32.dll",EntryPoint="GetFinalPathNameByHandleW",CharSet=CharSet.Unicode,SetLastError=true)]
 static extern uint Final(SafeFileHandle handle,StringBuilder text,uint chars,uint flags);
 [DllImport("kernel32.dll",EntryPoint="SetFileInformationByHandle",SetLastError=true)]
 static extern bool Set(SafeFileHandle handle,int cls,ref DISPOSITION info,uint len);
 readonly SafeFileHandle handle;
 public R356NativeDirectoryLease(string path,bool writableDeletion){
   string exact=Path.GetFullPath(path).TrimEnd('\\');
   SafeFileHandle h=Open(exact,LIST | (writableDeletion?DELETE:0),SHARE_READ_WRITE,IntPtr.Zero,EXISTING,BACKUP|REPARSE,IntPtr.Zero);
   if(h.IsInvalid){int code=Marshal.GetLastWin32Error();h.Dispose();throw new IOException("R356_CREATE_WIN32_"+code);}
   try{
     ATTRTAG tag;
     if(!Info(h,9,out tag,(uint)Marshal.SizeOf(typeof(ATTRTAG))))throw new IOException("R356_INFO_WIN32_"+Marshal.GetLastWin32Error());
     if((tag.Attributes&DIRECTORY)==0 || (tag.Attributes&TAG_REPARSE)!=0)throw new IOException("R356_NON_DIRECTORY_OR_REPARSE");
     StringBuilder full=new StringBuilder(4096);
     uint n=Final(h,full,(uint)full.Capacity,0);
     if(n==0 || n>=full.Capacity)throw new IOException("R356_FINAL_WIN32_"+Marshal.GetLastWin32Error());
     string resolved=full.ToString();
     if(resolved.StartsWith(@"\\?\",StringComparison.Ordinal))resolved=resolved.Substring(4);
     if(!String.Equals(resolved.TrimEnd('\\'),exact,StringComparison.OrdinalIgnoreCase))
       throw new IOException("R356_REDIRECTED_DIR_IDENTITY");
     handle=h;
   }catch{h.Dispose();throw;}
 }
 public int MarkDeleteByExactHandle(){
   DISPOSITION flags=new DISPOSITION();flags.DeleteFile=1;
   if(Set(handle,4,ref flags,(uint)Marshal.SizeOf(typeof(DISPOSITION))))return 0;
   return Marshal.GetLastWin32Error();
 }
 public void Dispose(){handle.Dispose();}
}
'@
 Check 'MICROSOFT_SUPPORTED_HANDLE_DISPOSITION_NATIVE_CSHARP_COMPILES'
 $phase='ACTOR_BEFORE_PIN'
 $pre=Invoke-Actor 'Before' $target $canary
 if($pre.RenameAllowed -ne $true -or $pre.Win32Error -ne 0){throw 'R356_PRE_PIN_RENAME_WAS_NOT_ALLOWED_AND_RESTORED'}
 $preActorPid=[int]$pre.Pid;$preAllowed=$true
 Check 'INDEPENDENT_ACTOR_CAN_RENAME_EXACT_DIRECTORY_BEFORE_PIN'
 $phase='OPEN_NO_SHARE_DELETE_PARENT_AND_CHILD'
 $parentPin=[R356NativeDirectoryLease]::new($testRoot,$false)
 $childPin=[R356NativeDirectoryLease]::new($target,$true)
 Check 'NATIVE_LIST_AND_DELETE_ACCESS_HELD_WITHOUT_FILE_SHARE_DELETE'
 $phase='ACTOR_DURING_PIN'
 $during=Invoke-Actor 'During' $target $canary
 $inActorPid=[int]$during.Pid
 if($during.RenameAllowed -ne $false -or $during.Win32Error -ne 32 -or
    $inActorPid -eq $PID -or $inActorPid -eq $preActorPid){throw 'R356_SECOND_ACTOR_RENAME_NOT_DENIED_WIN32_32'}
 $inDenied=$true
 Check 'INDEPENDENT_ACTOR_RENAME_DENIED_WHILE_EXACT_DELETE_ACCESS_HANDLE_PINNED'
 $phase='REFUSE_NONEMPTY_HANDLE_DELETE'
 $nonemptyError=$childPin.MarkDeleteByExactHandle()
 if($nonemptyError -ne 145){throw ('R356_NONEMPTY_DIRECTORY_UNEXPECTED_DELETE_'+$nonemptyError)}
 if(![IO.File]::Exists($leaf)){throw 'R356_UNEXPECTED_NONEMPTY_FILE_LOSS'}
 Check 'HANDLE_DELETE_REJECTED_NONEMPTY_DIRECTORY_WIN32_145'
 $phase='DELETE_ONLY_SYNTHETIC_LEAF_WITH_HANDLE_STILL_PINNED'
 if((Hash-R356File $leaf) -cne ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash(
    [Text.Encoding]::UTF8.GetBytes('R356_TEMP_LEAF_ONLY')))).Replace('-','')){
   throw 'R356_SYNTHETIC_LEAF_CHANGED'
 }
 [IO.File]::Delete($leaf)
 if([IO.File]::Exists($leaf) -or @([IO.Directory]::GetFileSystemEntries($target)).Count -ne 0){
    throw 'R356_TARGET_NOT_VERIFIED_EMPTY'
 }
 Check 'KNOWN_LEAF_REMOVED_AND_PINNED_DIRECTORY_VERIFIED_EMPTY'
 $phase='SET_DISPOSITION_INFO_ON_STILL_OPEN_EXACT_HANDLE'
 $dispositionCode=$childPin.MarkDeleteByExactHandle()
 if($dispositionCode -ne 0){throw ('R356_NATIVE_DISPOSITION_FAILED_WIN32_'+$dispositionCode)}
 $childPin.Dispose();$childPin=$null
 for($i=0;$i -lt 30 -and [IO.Directory]::Exists($target);$i++){Start-Sleep -Milliseconds 50}
 if([IO.Directory]::Exists($target)){throw 'R356_HANDLE_DELETE_DID_NOT_REMOVE_EMPTY_DIRECTORY'}
 $unlinkDone=$true
 Check 'SET_FILE_INFORMATION_BY_HANDLE_DELETES_ONLY_PINNED_EMPTY_DIRECTORY'
 $phase='OUTSIDE_CANARY_AND_PARENT_CLEANUP'
 if((Hash-R356File $canary) -cne $outsideSha){throw 'R356_EXTERNAL_CANARY_CHANGED'}
 $outsideIntact=$true
 Check 'OUTSIDE_CANARY_SHA_UNMODIFIED_DURING_NATIVE_DELETE'
 $parentPin.Dispose();$parentPin=$null
 if(@([IO.Directory]::GetFileSystemEntries($outside)).Count -ne 1 -or (Hash-R356File $canary) -cne $outsideSha){
   throw 'R356_OUTSIDE_CANARY_MEMBERS_CHANGED'
 }
 [IO.File]::Delete($canary)
 [IO.Directory]::Delete($outside,$false)
 if(@([IO.Directory]::GetFileSystemEntries($testRoot)).Count -ne 0){throw 'R356_UNEXPECTED_TEST_FIXTURE_RESIDUE'}
 $cleanupDone=$true
 Check 'ALL_TEST_OWNED_FILES_REMOVED_WITHOUT_RECURSIVE_DELETE'
}catch{
 $exitFailure=$_.Exception.GetType().Name+': '+$_.Exception.Message+' PHASE='+$phase
}finally{
 if($null -ne $childPin){try{$childPin.Dispose()}catch{$exitFailure+=' CHILD_HANDLE_DISPOSE_FAILED'}}
 if($null -ne $parentPin){try{$parentPin.Dispose()}catch{$exitFailure+=' PARENT_HANDLE_DISPOSE_FAILED'}}
 $ok=(!$exitFailure -and $preAllowed -and $inDenied -and $nonemptyError -eq 145 -and
      $dispositionCode -eq 0 -and $unlinkDone -and $outsideIntact -and $cleanupDone -and $checks.Count -eq 10)
 $record=[ordered]@{
  Schema=1;Revision='R356';SourceCommit=$env:GITHUB_SHA;Host=$HostLabel
  Status=$(if($ok){'PASS_PINNED_EXACT_HANDLE_DISPOSITION_EMPTY_DIRECTORY_NO_PATH_RACE'}else{'FAIL_R356_PROTOTYPE'})
  OriginalProductImplementationChanged=$false
  RealOSNativeSetFileInformationByHandleInvoked=$true
  IndependentActorBeforePid=$preActorPid;IndependentActorDuringPid=$inActorPid
  BeforePinRenameAllowed=$preAllowed;DuringPinRenameDenied=$inDenied
  DuringNativeRenameWin32=$(if($inDenied){32}else{-1})
  NonEmptyDirectoryDeleteWin32=$nonemptyError;EmptyDirectoryDispositionWin32=$dispositionCode
  DeletedExactPinnedDirectory=$unlinkDone;OutsideCanaryIntact=$outsideIntact
  OwnedTemporaryCleanupComplete=$cleanupDone;NoOwnerMachineTouched=$true
  NoUACShown=$true;FullNTFSRaceSecurityProven=$false
  Checks=@($checks);Failure=$exitFailure
 }
 try{[IO.File]::WriteAllText($receipt,($record|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))}
 catch{Write-Output ('R356_RECEIPT_WRITE_FAILURE '+$_.Exception.Message)}
 Write-Output ('R356_NATIVE_PROTOTYPE_STATUS='+$record.Status+' CHECKS='+$checks.Count+' ERR='+$exitFailure)
}
if($exitFailure){throw ('R356_NATIVE_DISPOSITION_PROTOTYPE_FAILED '+$exitFailure)}
