[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AppExe)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# Never touch an actual owner's desktop or start/stop the installed app.
if($PSVersionTable.PSEdition -cne 'Desktop' -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:COMPUTERNAME -match '(?i)EMAD-PC' -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_SHA) -or
   ![Environment]::UserInteractive -or
   [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA'){
    throw 'R290_ONLY_DISPOSABLE_GITHUB_WINDOWS_INTERACTIVE_STA_ALLOWED'
}
$source=(Resolve-Path $AppExe -ErrorAction Stop).Path
if(!(Test-Path $source -PathType Leaf)){throw 'R290_APP_MISSING'}
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Drawing;
public static class R290Windows {
 [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
 public static extern IntPtr CreateWindowEx(int ex,string cls,string name,uint style,
   int x,int y,int w,int h,IntPtr parent,IntPtr menu,IntPtr module,IntPtr param);
 [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hwnd,uint cmd);
 [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr hwnd);
 [DllImport("user32.dll")] [return:MarshalAs(UnmanagedType.Bool)] public static extern bool IsWindowVisible(IntPtr hwnd);
 [DllImport("user32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
 public static extern bool DestroyWindow(IntPtr hwnd);
 [DllImport("user32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
 public static extern bool SetWindowPos(IntPtr hwnd,IntPtr after,int x,int y,int w,int h,uint flags);
 [DllImport("user32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)]
 public static extern bool GetWindowRect(IntPtr hwnd,out RECT rect);
 [StructLayout(LayoutKind.Sequential)]
 public struct RECT {public int left,top,right,bottom;}
 public static Rectangle Bounds(IntPtr h) {
  RECT r;if(!GetWindowRect(h,out r))throw new Exception("GetWindowRect failed");
  return Rectangle.FromLTRB(r.left,r.top,r.right,r.bottom);
 }
 public const uint POPUP=0x80000000, CHILD=0x40000000,VISIBLE=0x10000000;
 public const uint NO_SIZE=0x0001,NO_MOVE=0x0002,NO_ACTIVATE=0x0010;
 public static readonly IntPtr TOP=new IntPtr(0), BOTTOM=new IntPtr(1), TOPMOST=new IntPtr(-1);
}
'@ -ReferencedAssemblies @('System.Drawing','System.Windows.Forms') -ErrorAction Stop
$assembly=[Reflection.Assembly]::LoadFrom($source)
$native=$assembly.GetType('TaskbarMonitorEnhanced.TaskbarPresentationNative',$true)
$flags=[Reflection.BindingFlags]'Static,NonPublic,Public'
$childProbe=$native.GetMethod('TaskbarSiblingCovers',$flags)
$topProbe=$native.GetMethod('Above',$flags)
$policyType=$assembly.GetType('TaskbarMonitorEnhanced.TaskbarPresentationPolicy',$true)
$guard=$policyType.GetMethod('ShouldRepairOcclusion',$flags)
if($null -eq $childProbe -or $null -eq $topProbe -or $null -eq $guard){throw 'R290_APP_NATIVE_METHOD_MISSING'}
$windows=New-Object 'System.Collections.Generic.List[IntPtr]'
$tests=New-Object 'System.Collections.Generic.List[string]'
function Create([uint32]$style,[int]$x,[int]$y,[int]$w,[int]$h,[IntPtr]$owner) {
 $handle=[R290Windows]::CreateWindowEx(0,'STATIC','TBME_R290_PRIVATE',
    $style,$x,$y,$w,$h,$owner,[IntPtr]::Zero,[IntPtr]::Zero,[IntPtr]::Zero)
 if($handle -eq [IntPtr]::Zero){throw "R290_CREATE_WINDOW_FAILED $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"}
 $windows.Add($handle);return $handle
}
function Assert([bool]$ok,[string]$name) {
 if(!$ok){throw "R290_NATIVE_WINDOW_CONTRACT_FAIL $name"}
 $tests.Add($name)
}
function ChildCovered([IntPtr]$hwnd) {
 $area=[R290Windows]::Bounds($hwnd)
 return [bool]$childProbe.Invoke($null,[object[]]@($hwnd,$area))
}
function TopAbove([IntPtr]$upper,[IntPtr]$lower) {
 return [bool]$topProbe.Invoke($null,[object[]]@($upper,$lower))
}
function Place([IntPtr]$hwnd,[IntPtr]$after,[int]$x,[int]$y,[int]$w,[int]$h,[uint32]$flags) {
 if(![R290Windows]::SetWindowPos($hwnd,$after,$x,$y,$w,$h,$flags)){
  throw "R290_SET_WINDOW_POS_FAILED $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"
 }
}
try {
 # Child-sibling model: synthetic taskbar, stationary overlay and an obstructing sibling.
 $root=Create ([R290Windows]::POPUP -bor [R290Windows]::VISIBLE) 180 200 520 150 ([IntPtr]::Zero)
 $overlay=Create ([R290Windows]::CHILD -bor [R290Windows]::VISIBLE) 15 15 260 50 $root
 $cover=Create ([R290Windows]::CHILD -bor [R290Windows]::VISIBLE) 15 15 260 50 $root
 Place $cover ([R290Windows]::TOP) 0 0 0 0 ([R290Windows]::NO_SIZE -bor [R290Windows]::NO_MOVE -bor [R290Windows]::NO_ACTIVATE)
 $prev=[R290Windows]::GetWindow($overlay,3)
 $parentOverlay=[R290Windows]::GetParent($overlay)
 $parentCover=[R290Windows]::GetParent($cover)
 $coverVisible=[R290Windows]::IsWindowVisible($cover)
 $overlayBounds=[R290Windows]::Bounds($overlay)
 $coverBounds=[R290Windows]::Bounds($cover)
 "R290_CHILD_DIAGNOSTIC overlay=$overlay cover=$cover upper=$prev parentOverlay=$parentOverlay parentCover=$parentCover root=$root visible=$coverVisible overlayRect=$overlayBounds coverRect=$coverBounds"
 if($prev -ne $cover -or $parentOverlay -ne $root -or $parentCover -ne $root -or !$coverVisible){throw 'R290_FIXTURE_CHILD_RELATIONSHIP_INVALID'}
 Assert (ChildCovered $overlay) 'child-overlap-detected'
 Place $overlay ([R290Windows]::TOP) 0 0 0 0 ([R290Windows]::NO_SIZE -bor [R290Windows]::NO_MOVE -bor [R290Windows]::NO_ACTIVATE)
 Assert (!(ChildCovered $overlay)) 'child-restack-clears-overlap'
 Place $cover ([R290Windows]::TOP) 320 15 160 50 ([R290Windows]::NO_ACTIVATE)
 Assert (!(ChildCovered $overlay)) 'child-nonoverlapping-sibling-ignored'
 Place $cover ([R290Windows]::TOP) 15 15 20 8 ([R290Windows]::NO_ACTIVATE)
 Assert (!(ChildCovered $overlay)) 'child-tiny-coverage-ignored'
 # Genuine Win32 top-level z-order, not the same test as a child sibling.
 $topA=Create ([R290Windows]::POPUP -bor [R290Windows]::VISIBLE) 820 220 260 50 ([IntPtr]::Zero)
 $topB=Create ([R290Windows]::POPUP -bor [R290Windows]::VISIBLE) 820 220 260 50 ([IntPtr]::Zero)
 Place $topA ([R290Windows]::TOPMOST) 0 0 0 0 ([R290Windows]::NO_SIZE -bor [R290Windows]::NO_MOVE -bor [R290Windows]::NO_ACTIVATE)
 Assert (TopAbove $topA $topB) 'top-level-occlusion-detected'
 Place $topB ([R290Windows]::TOPMOST) 0 0 0 0 ([R290Windows]::NO_SIZE -bor [R290Windows]::NO_MOVE -bor [R290Windows]::NO_ACTIVATE)
 Assert (!(TopAbove $topA $topB)) 'top-level-restack-clears-occlusion'
 # Drive the exact production policy via reflection.
 function Gate([bool]$seen,[bool]$shell,[bool]$dialog,[int]$streak,[double]$age) {
  return [bool]$guard.Invoke($null,[object[]]@($seen,$shell,$dialog,$streak,$age))
 }
 Assert (!(Gate $false $false $false 2 20)) 'healthy-does-not-restack'
 Assert (!(Gate $true $false $false 1 20)) 'transient-occlusion-does-not-restack'
 Assert (!(Gate $true $true $false 2 20)) 'start-shell-blocks-restack'
 Assert (!(Gate $true $false $true 2 20)) 'settings-blocks-restack'
 Assert (!(Gate $true $false $false 2 2.5)) 'cooldown-blocks-restack'
 Assert (Gate $true $false $false 2 3.1) 'persistent-occlusion-permits-restack'
 $data=[ordered]@{
  Schema=1;Status='PASS';Host=$env:COMPUTERNAME;SourceCommit=$env:GITHUB_SHA
  AppSHA256=(Get-FileHash $source -Algorithm SHA256).Hash
  TestCount=$tests.Count;Assertions=@($tests);OwnerComputerTouched=$false
  WindowsCreatedOnlyInHostedDisposable=$true;RealExplorerStartAndSettingsVisuallyTested=$false
 }
 $recordPath=Join-Path $env:RUNNER_TEMP 'R290_NATIVE_ZORDER_RECEIPT.json'
 [IO.File]::WriteAllText($recordPath,($data|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
 "R290_NATIVE_ZORDER_PASS assertions=$($tests.Count)"
}finally{
 for($i=$windows.Count-1;$i -ge 0;$i--){[void][R290Windows]::DestroyWindow($windows[$i])}
}
