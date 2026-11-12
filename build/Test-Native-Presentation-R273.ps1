[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$CandidateDir,[Parameter(Mandatory=$true)][ValidateSet('A','B')][string]$HostLabel,[switch]$UseInstalledCandidate)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($PSVersionTable.PSEdition -eq 'Core' -or $env:GITHUB_ACTIONS -cne 'true' -or
 $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or $env:RUNNER_OS -cne 'Windows' -or
 $env:COMPUTERNAME -match 'EMAD-PC' -or ![Environment]::UserInteractive){throw 'R146_REAL_TEST_ONLY_FRESH_HOSTED_WINDOWS_FRAMEWORK'}
Add-Type -AssemblyName System.Drawing,System.Windows.Forms,UIAutomationClient,UIAutomationTypes
$native=@'
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public static class R146Native {
 [StructLayout(LayoutKind.Sequential)] public struct Rect {public int L,T,R,B;}
 [StructLayout(LayoutKind.Sequential)] public struct Point {public int X,Y;}
 [StructLayout(LayoutKind.Sequential)] public struct Mouse {public int x,y;public uint data,flags,time;public UIntPtr extra;}
 [StructLayout(LayoutKind.Explicit)] public struct Union {[FieldOffset(0)] public Mouse m;}
 [StructLayout(LayoutKind.Sequential)] public struct Input {public uint type;public Union u;}
 public delegate bool EnumFn(IntPtr h,IntPtr data);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumFn f,IntPtr d);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p,EnumFn f,IntPtr d);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtr(IntPtr h,int n);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h,uint n);
 [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string c,string t);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int s);
 [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern void keybd_event(byte k,byte s,uint f,UIntPtr extra);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point p);
 [DllImport("user32.dll",SetLastError=true)] public static extern uint SendInput(uint n,Input[] p,int size);
 public static void Key(byte code){keybd_event(code,0,0,UIntPtr.Zero);keybd_event(code,0,2,UIntPtr.Zero);}
 public static void Click(int x,int y,bool right){Point old;GetCursorPos(out old);SetCursorPos(x,y);try{
  Input down=new Input{u=new Union{m=new Mouse{flags=right?8u:2u}}};
  Input up=new Input{u=new Union{m=new Mouse{flags=right?16u:4u}}};
  if(Marshal.SizeOf(typeof(Input))!=40||SendInput(2,new[]{down,up},40)!=2)throw new Exception("Input not delivered");
 }finally{SetCursorPos(old.X,old.Y);}}
 public static IntPtr[] Owned(uint pid,IntPtr tray){var list=new List<IntPtr>();EnumFn f=(h,d)=>{uint p;GetWindowThreadProcessId(h,out p);if(p==pid&&!list.Contains(h))list.Add(h);return true;};EnumWindows(f,IntPtr.Zero);EnumChildWindows(tray,f,IntPtr.Zero);return list.ToArray();}
 public static bool Above(IntPtr a,IntPtr b){for(int i=0;i<512;i++){b=GetWindow(b,3);if(b==IntPtr.Zero)return false;if(a==b)return true;}return false;}
 public static string Title(IntPtr h){var s=new StringBuilder(256);GetWindowText(h,s,s.Capacity);return s.ToString();}
}
'@
Add-Type -TypeDefinition $native -Language CSharp
$manifest=Get-Content (Join-Path $CandidateDir 'CANDIDATE.json') -Raw|ConvertFrom-Json
if($manifest.Commit -cne $env:GITHUB_SHA -or $manifest.Private -ne $true){throw 'R146_NOT_EXACT_PRIVATE_BUILD_ARTIFACT'}
$setup=Join-Path $CandidateDir 'Setup\TaskbarMonitorEnhanced_Setup_1.7.6.exe'
if((Get-FileHash $setup -Algorithm SHA256).Hash -cne $manifest.SetupSHA256){throw 'R146_SETUP_SHA'}
$app=Join-Path $env:LOCALAPPDATA 'TaskbarMonitorEnhanced'
$reg='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TaskbarMonitorEnhanced'
$out=Join-Path $env:RUNNER_TEMP ('TBME_R273_'+$HostLabel)
if((Test-Path $out) -or @(Get-Process TaskbarMonitorEnhanced -ErrorAction SilentlyContinue).Count){throw 'R273_NATIVE_OUTPUT_OR_PROCESS_PRESTATE'}
if($UseInstalledCandidate){
 if(!(Test-Path $app) -or !(Test-Path $reg) -or (Test-Path (Join-Path $app '.tbme-upgrade'))){throw 'R273_VERIFIED_EXISTING_CANDIDATE_REQUIRED'}
 $s=Get-Content (Join-Path $app 'install_state.json') -Raw|ConvertFrom-Json
 if($s.Version -cne '1.7.6' -or (Get-FileHash (Join-Path $app 'TaskbarMonitorEnhanced.exe') -Algorithm SHA256).Hash -cne $manifest.MainSHA256){throw 'R273_NATIVE_INSTALLED_SHA_OR_VERSION'}
}else{if((Test-Path $app) -or (Test-Path $reg)){throw 'R273_NATIVE_FRESH_VM_REQUIRED'}}
New-Item -ItemType Directory -Path $out|Out-Null
$visualFailures=New-Object 'Collections.Generic.List[string]'
$phase='INSTALL';$status='FAIL';$failure='';$process=$null;$full=$null;$taskbar=[IntPtr]::Zero;$hidTaskbar=$false;$evidence=@()
function Box([IntPtr]$h){$r=New-Object R146Native+Rect;if(![R146Native]::GetWindowRect($h,[ref]$r)){throw 'R146_RECT_FAILED'};return New-Object Drawing.Rectangle($r.L,$r.T,($r.R-$r.L),($r.B-$r.T))}
function Pump([int]$ms){$stop=[Diagnostics.Stopwatch]::StartNew();while($stop.ElapsedMilliseconds -lt $ms){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 25}}
function Capture([IntPtr]$h,[string]$label){
 $r=Box $h;$file=$label+'.png';$b=New-Object Drawing.Bitmap($r.Width,$r.Height)
 try{
  $g=[Drawing.Graphics]::FromImage($b);try{$g.CopyFromScreen($r.Location,[Drawing.Point]::Empty,$r.Size)}finally{$g.Dispose()}
  $edges=0;for($y=0;$y -lt $b.Height;$y++){for($x=1;$x -lt $b.Width;$x++){
   $a=$b.GetPixel($x,$y);$z=$b.GetPixel(($x-1),$y)
   if([Math]::Abs(([int]$a.R+$a.G+$a.B)-([int]$z.R+$z.G+$z.B)) -ge 120){$edges++}
  }}
  $b.Save((Join-Path $out $file),[Drawing.Imaging.ImageFormat]::Png)
  if($edges -lt 60){$visualFailures.Add(('R146_PHYSICAL_GLYPHS_MISSING '+$label+' EDGES='+$edges))}
  return @{State=$label;File=$file;SHA256=(Get-FileHash (Join-Path $out $file) -Algorithm SHA256).Hash;Edges=$edges;Rect=@($r.X,$r.Y,$r.Width,$r.Height);Parent=[R146Native]::GetParent($h).ToInt64();Owner=[R146Native]::GetWindow($h,4).ToInt64();OwnerMemory=[R146Native]::GetWindowLongPtr($h,-8).ToInt64();PreviousSibling=[R146Native]::GetWindow($h,3).ToInt64();ExStyle=[R146Native]::GetWindowLongPtr($h,-20).ToInt64();Style=[R146Native]::GetWindowLongPtr($h,-16).ToInt64();Foreground=[R146Native]::GetForegroundWindow().ToInt64()}
 }finally{$b.Dispose()}
}
# R163 fork-only paint readiness. WS_VISIBLE is not proof of actual text ink.
# Same RGB edge definition as Capture(): adjacent channel-sum delta >=120.
# ZERO edges must NEVER satisfy 60-edge native acceptance. No product code change.
function Probe-R163PhysicalInk([IntPtr]$h,[string]$label,[bool]$saveFrame){
 $rect=Box $h
 if($rect.Width -lt 80 -or $rect.Height -lt 16 -or $rect.Height -ge 100){
  return @{Edges=0;Colors=0;Bytes=0;SHA256='';Error='R163_INVALID_WINDOW_GEOMETRY'}
 }
 $bitmap=New-Object Drawing.Bitmap($rect.Width,$rect.Height)
 try{
  try{
   $g=[Drawing.Graphics]::FromImage($bitmap)
   try{$g.CopyFromScreen($rect.Location,[Drawing.Point]::Empty,$rect.Size)}
   finally{$g.Dispose()}
  }catch{
   return @{Edges=0;Colors=0;Bytes=0;SHA256='';Error=('R163_COPY_FROM_SCREEN_FAILED '+$_.Exception.Message)}
  }
  $ink=0
  $colors=New-Object 'System.Collections.Generic.HashSet[int]'
  for($y=0;$y -lt $bitmap.Height;$y++){
   for($x=0;$x -lt $bitmap.Width;$x++){
    $a=$bitmap.GetPixel($x,$y)
    $rgb=([int]$a.R -shl 16) -bor ([int]$a.G -shl 8) -bor [int]$a.B
    [void]$colors.Add($rgb)
    if($x -ge 1){
     $z=$bitmap.GetPixel(($x-1),$y)
     if([Math]::Abs(([int]$a.R+$a.G+$a.B)-([int]$z.R+$z.G+$z.B)) -ge 120){$ink++}
    }
   }
  }
  $file='';$sha='';$bytes=0
  if($saveFrame){
   $file=$label+'.png'
   $full=Join-Path $out $file
   if(Test-Path $full){throw ('R163_PROBE_IMAGE_OVERWRITE_REFUSED '+$file)}
   $bitmap.Save($full,[Drawing.Imaging.ImageFormat]::Png)
   $sha=(Get-FileHash $full -Algorithm SHA256).Hash
   $bytes=(Get-Item $full).Length
  }
  return @{Edges=$ink;Colors=$colors.Count;Bytes=$bytes;File=$file;SHA256=$sha;Error='';Rect=@($rect.X,$rect.Y,$rect.Width,$rect.Height)}
 }finally{$bitmap.Dispose()}
}

function Assert-Visible([IntPtr]$h,[Drawing.Rectangle]$original,[string]$label,[bool]$top){
 if(![R146Native]::IsWindowVisible($h)){throw ('R146_MONITOR_HIDDEN '+$label)}
 $r=Box $h
 if($r.X -ne $original.X -or $r.Y -ne $original.Y -or $r.Height -ne $original.Height -or [Math]::Abs($r.Width-$original.Width) -gt 96){throw ('R146_UNEXPECTED_MOVEMENT '+$label)}
 # R153: retain both direct owner-memory and WS_POPUP GetParent checks.
 # R152 real Start evidence showed GW_OWNER=0 but GetParent=the exact
 # taskbar and 877 physical glyph edges. Never let a relationship-walk
 # API substitute for pixels; never waive actual owner-memory or geometry.
 $ownerMemory=[R146Native]::GetWindowLongPtr($h,-8)
 $popupOwner=[R146Native]::GetParent($h)
 if($ownerMemory -ne $taskbar -or $popupOwner -ne $taskbar){
  $nativeOwner=[R146Native]::GetWindow($h,4)
  $directTray=[R146Native]::FindWindow('Shell_TrayWnd',$null)
  $frame=Capture $h ($label+'_OWNER_FAILURE')
  [IO.File]::WriteAllText((Join-Path $out ($label+'_NATIVE_FAILURE.json')),(@{ExpectedOwner=$taskbar.ToInt64();ActualOwner=$nativeOwner.ToInt64();DirectOwnerMemory=$ownerMemory.ToInt64();PopupOwner=$popupOwner.ToInt64();DirectTaskbar=$directTray.ToInt64();Frame=$frame}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
  throw ('R152_TASKBAR_OWNER_DRIFT '+$label+' EXPECTED='+$taskbar.ToInt64()+' ACTUAL='+$nativeOwner.ToInt64()+' DIRECT='+$directTray.ToInt64())
 }
 if(([R146Native]::GetWindowLongPtr($h,-16).ToInt64() -band 0x40000000) -ne 0){throw ('R151_MONITOR_BECAME_CHILD '+$label)}
 if($top -and [R146Native]::Above($taskbar,$h)){throw ('R146_MONITOR_UNDER_TASKBAR '+$label)}
}
try{
 if(!$UseInstalledCandidate){
  $install=Start-Process -FilePath $setup -ArgumentList @('/install','/quiet','/desktop=0','/startup=0') -PassThru
  if(!$install.WaitForExit(190000) -or $install.ExitCode -ne 0){throw 'R273_SETUP_DID_NOT_FINISH'}
 }
 $main=Join-Path $app 'TaskbarMonitorEnhanced.exe';$config=Join-Path $app 'config.json'
 if((Get-FileHash $main -Algorithm SHA256).Hash -cne $manifest.MainSHA256){throw 'R146_INSTALLED_MAIN_SHA'}
 $taskbar=[R146Native]::FindWindow('Shell_TrayWnd',$null)
 if($taskbar -eq [IntPtr]::Zero -or ![R146Native]::IsWindowVisible($taskbar)){throw 'R146_REAL_TASKBAR_MISSING'}
 $assembly=[Reflection.Assembly]::LoadFrom($main)
 $shell=$assembly.GetType('TaskbarMonitorEnhanced.ShellUi',$true)
 $shellMethod=$shell.GetMethod('IsStartShellForeground',[Reflection.BindingFlags]'Static,Public,NonPublic')
 foreach($mode in @('plain1','plain10','glass0','opaque100')){
  $phase=$mode
  $pct=if($mode -ceq 'plain1'){0.01}elseif($mode -ceq 'plain10'){0.10}elseif($mode -ceq 'glass0'){0.0}else{1.0}
  $fixture=@{Theme='Retro Terminal';Opacity=$pct;GlassMode=($mode -ceq 'glass0');OpacityWhenGlassOff=0.10;ConfigSchemaVersion=8;StartWithWindows=$false;ShowSparklines=$true;UpdateIntervalMs=1000}
  [IO.File]::WriteAllText($config,($fixture|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
  $process=Start-Process -FilePath $main -WorkingDirectory $app -PassThru
  $readyClock=[Diagnostics.Stopwatch]::StartNew();$readyObservations=@()
  Pump 5000 # Keep original warm-up and strict 20s total readiness deadline.
  $monitor=[IntPtr]::Zero;$paintFirst=$false;$paintLast=$null
  $lastEligible=[IntPtr]::Zero
  do{
   $process.Refresh()
   if($process.HasExited){throw ('R158_MAIN_EXITED_BEFORE_READY '+$mode+' CODE='+$process.ExitCode)}
   $observed=@()
   foreach($h in [R146Native]::Owned([uint32]$process.Id,$taskbar)){
    $visible=[R146Native]::IsWindowVisible($h);$r=Box $h
    $one=@{Handle=$h.ToInt64();Visible=$visible;Rect=@($r.X,$r.Y,$r.Width,$r.Height)}
    if($visible -and $r.Width -ge 80 -and $r.Height -ge 16 -and $r.Height -lt 100 -and (Box $taskbar).Contains($r)){
     $lastEligible=$h
     # Persist FIRST physical frame, whether ink is present or missing.
     $paint=Probe-R163PhysicalInk $h ($mode+'_R163_FIRST_PAINT') (!$paintFirst)
     $paintFirst=$true
     $paintLast=$paint
     $one.PaintEdges=$paint.Edges;$one.PaintColors=$paint.Colors;$one.PaintError=$paint.Error
     if($paint.Edges -ge 60 -and [string]$paint.Error -ceq ''){
      $monitor=$h;$observed+=@($one);break
     }
    }
    $observed+=@($one)
   }
   if($readyObservations.Count -lt 24){
    $readyObservations+=@{ElapsedMs=$readyClock.ElapsedMilliseconds;Windows=$observed}
   }
   if($monitor -eq [IntPtr]::Zero){Pump 200}
  }while($monitor -eq [IntPtr]::Zero -and $readyClock.ElapsedMilliseconds -lt 20000)
  $readyClock.Stop()
  $timeoutProbe=$null
  if($monitor -eq [IntPtr]::Zero -and $lastEligible -ne [IntPtr]::Zero){
   $timeoutProbe=Probe-R163PhysicalInk $lastEligible ($mode+'_R163_TIMEOUT_PAINT') $true
  }
  $ready=[ordered]@{Mode=$mode;Pid=$process.Id;Ready=($monitor -ne [IntPtr]::Zero);
   PaintReady=($monitor -ne [IntPtr]::Zero -and $null -ne $paintLast -and $paintLast.Edges -ge 60);
   PaintThresholdEdges=60;OriginalRgbDelta=120;
   LastMeasuredEdges=if($null -eq $paintLast){-1}else{$paintLast.Edges};
   LastMeasuredColors=if($null -eq $paintLast){0}else{$paintLast.Colors};
   TimeoutFrame=$timeoutProbe;
   ElapsedMilliseconds=$readyClock.ElapsedMilliseconds;HardDeadlineMs=20000;
   Observations=$readyObservations;ProductSourceChanged=$false;
   NoThresholdWeakening=$true;SeparateTaskbarHideInvariantRequired=$true}
  [IO.File]::WriteAllText((Join-Path $out ('R158_READY_'+$mode+'.json')),($ready|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
  if($monitor -eq [IntPtr]::Zero){
   if($lastEligible -ne [IntPtr]::Zero){
    throw ('R163_PHYSICAL_PAINT_NOT_READY_WITHIN_20_SECONDS '+$mode+
     ' EDGES='+$ready.LastMeasuredEdges+' COLORS='+$ready.LastMeasuredColors)
   }
   throw ('R158_NATIVE_WINDOW_NOT_READY_WITHIN_20_SECONDS '+$mode)
  }
  if(!$ready.PaintReady -or $ready.LastMeasuredEdges -lt 60){
   throw ('R163_UNPROVEN_NATIVE_PAINT '+$mode)
  }
  Write-Output ('R163_NATIVE_AND_ACTUAL_INK_READY MODE='+$mode+' PID='+$process.Id+
   ' ELAPSED_MS='+$readyClock.ElapsedMilliseconds+' EDGES='+$ready.LastMeasuredEdges)
  $original=Box $monitor;$top=$true
  # Original Capture() remains the separate final pixel threshold acceptance.
  $evidence+=Capture $monitor ($mode+'_NORMAL')
  # Real right-click and invoke the actual installed product's Settings menu item.
  [R146Native]::Click(($original.X+40),($original.Y+($original.Height/2)),$true);Pump 650
  Assert-Visible $monitor $original ($mode+'_MENU') $top
  $evidence+=Capture $monitor ($mode+'_MENU')
  $menuItem=$null
  $condition=New-Object Windows.Automation.AndCondition([Windows.Automation.Condition[]]@(
   (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ProcessIdProperty,[int]$process.Id)),
   (New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,'Settings...'))))
  $menuItem=[Windows.Automation.AutomationElement]::RootElement.FindFirst([Windows.Automation.TreeScope]::Descendants,$condition)
  if($null -eq $menuItem){throw 'R146_REAL_SETTINGS_MENU_ITEM_NOT_FOUND'}
  $invoke=$menuItem.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern);$invoke.Invoke();Pump 1500
  $settings=[IntPtr]::Zero
  foreach($h in [R146Native]::Owned([uint32]$process.Id,$taskbar)){if([R146Native]::Title($h) -like '* - Settings' -and [R146Native]::IsWindowVisible($h)){$settings=$h;break}}
  if($settings -eq [IntPtr]::Zero -or [R146Native]::GetForegroundWindow() -ne $settings){throw 'R146_SETTINGS_NOT_REAL_FOREGROUND'}
  $work=[Windows.Forms.Screen]::FromHandle($settings).WorkingArea
  if(!$work.Contains((Box $settings))){throw 'R146_SETTINGS_EXTENDS_BEHIND_TASKBAR'}
  Assert-Visible $monitor $original ($mode+'_SETTINGS') $top
  $evidence+=Capture $monitor ($mode+'_SETTINGS')
  [void][R146Native]::SendMessage($settings,0x0010,[IntPtr]::Zero,[IntPtr]::Zero);Pump 500
  [R146Native]::Key(0x5B);Pump 1200
  $args=[object[]]@('','',[IntPtr]::Zero)
  if(!$shellMethod.Invoke($null,$args)){throw 'R146_GENUINE_START_FOREGROUND_NOT_VERIFIED'}
  Assert-Visible $monitor $original ($mode+'_START') $top
  $evidence+=Capture $monitor ($mode+'_START')
  [R146Native]::Key(0x1B);Pump 900
  Assert-Visible $monitor $original ($mode+'_AFTER_START') $top
  # A real foreground fullscreen window covering this monitor and its taskbar.
  $full=New-Object Windows.Forms.Form
  $full.FormBorderStyle='None';$full.StartPosition='Manual';$full.Bounds=[Windows.Forms.Screen]::FromHandle($taskbar).Bounds
  $full.TopMost=$true;$full.BackColor=[Drawing.Color]::FromArgb(24,40,56);$full.Text='R146 disposable fullscreen witness';$full.Show();Pump 300
  [R146Native]::Click(($full.Left+100),($full.Top+100),$false);Pump 1500
  if([R146Native]::GetForegroundWindow() -ne $full.Handle){throw 'R146_FULLSCREEN_NOT_FOREGROUND'}
  if([R146Native]::IsWindowVisible($monitor)){throw 'R146_MONITOR_VISIBLE_WITHOUT_TASKBAR_IN_FULLSCREEN'}
  $evidence+=@{State=$mode+'_FULLSCREEN';Hidden=$true;Foreground=$full.Handle.ToInt64()}
  $full.Close();$full.Dispose();$full=$null;Pump 1500
  Assert-Visible $monitor $original ($mode+'_RETURN_FULLSCREEN') $top
  $evidence+=Capture $monitor ($mode+'_RETURN_FULLSCREEN')
  # Simulate taskbar visibility notification, only on disposable runner; always restore.
  [void][R146Native]::ShowWindow($taskbar,0);$hidTaskbar=$true;Pump 1100
  if([R146Native]::IsWindowVisible($monitor)){
   # Do not suppress this independent FAIL gate. Collect the real HWND/shell
   # visibility and optional screen-pixel evidence before the existing throw.
   $forkHide=[ordered]@{
    Mode=$mode;MainPid=$process.Id;
    TaskbarVisible=[R146Native]::IsWindowVisible($taskbar)
    MonitorVisible=[R146Native]::IsWindowVisible($monitor)
    TaskbarRect=@( (Box $taskbar).X,(Box $taskbar).Y,(Box $taskbar).Width,(Box $taskbar).Height )
    MonitorRect=@( (Box $monitor).X,(Box $monitor).Y,(Box $monitor).Width,(Box $monitor).Height )
    PopupOwner=[R146Native]::GetParent($monitor).ToInt64()
    MemoryOwner=[R146Native]::GetWindowLongPtr($monitor,-8).ToInt64()
    ProductSourceChanged=$false
    OriginalHideInvariantRetained=$true
   }
   [IO.File]::WriteAllText((Join-Path $out ($mode+'_R163_TASKBAR_HIDE_FAILURE.json')),
     ($forkHide|ConvertTo-Json -Depth 9),[Text.UTF8Encoding]::new($false))
   throw 'R146_MONITOR_IGNORES_TASKBAR_HIDE'
  }
  [void][R146Native]::ShowWindow($taskbar,4);$hidTaskbar=$false;Pump 1100
  Assert-Visible $monitor $original ($mode+'_TASKBAR_REAPPEARS') $top
  $process.Refresh();$cpu0=$process.CPU;$clock=[Diagnostics.Stopwatch]::StartNew();Pump 5000;$clock.Stop();$process.Refresh()
  $evidence+=@{State=$mode+'_CPU';Seconds=$clock.Elapsed.TotalSeconds;CpuSeconds=$process.CPU-$cpu0;PercentOfOneCore=100*($process.CPU-$cpu0)/$clock.Elapsed.TotalSeconds;Status='MEASURED_NOT_USER_PC_ACCEPTANCE'}
  [void][R146Native]::SendMessage($monitor,0x0010,[IntPtr]::Zero,[IntPtr]::Zero)
  if(!$process.WaitForExit(10000)){throw 'R146_OWN_TEST_PROCESS_DID_NOT_EXIT'};$process.Dispose();$process=$null
 }
 if($visualFailures.Count){throw ($visualFailures -join ';')}
 $status='PASS_REAL_MENU_SETTINGS_START_FULLSCREEN_TASKBAR_VISIBILITY_FOUR_MODES'
}catch{$failure=$_.Exception.ToString().Substring(0,[Math]::Min(3500,$_.Exception.ToString().Length))}
finally{
 if($hidTaskbar -and $taskbar -ne [IntPtr]::Zero){[void][R146Native]::ShowWindow($taskbar,4)}
 [R146Native]::Key(0x1B)
 if($null -ne $full){$full.Close();$full.Dispose()}
 if($null -ne $process){try{if(!$process.HasExited){$process.Kill()}}catch{}}
 try{
  $logs=@(Get-ChildItem (Join-Path $app 'Logs') -Filter 'tbme_csharp_*.log' -File -ErrorAction Stop)
  foreach($log in $logs){
   Get-Content -LiteralPath $log.FullName -Tail 1600 | Select-String -Pattern 'PRESENTATION|GLASS_NATIVE|GLASS_COMPOSITION|TASKBAR_|VISIBILITY_WATCHDOG|LOW_PRESSURE|CONTEXT_MENU|SETTINGS|START_|RECOVERY' | ForEach-Object Line | Set-Content -LiteralPath (Join-Path $out ('DIAG_'+$log.Name)) -Encoding UTF8
  }
 }catch{Write-Output ('R148_LOG_COLLECTION_WARNING '+$_.Exception.Message)}
 $r=[ordered]@{Revision='R273';Status=$status;Phase=$phase;Failure=$failure;Host=$HostLabel;EventCommit=$env:GITHUB_SHA;MainSHA256=$manifest.MainSHA256;SetupSHA256=$manifest.SetupSHA256;Evidence=$evidence;TestedModes=@('plain1','plain10','glass0','opaque100');ExpectedTaskbarOwner=$taskbar.ToInt64();PersonalComputerTouched=$false;Proof='Installed candidate + native HWND + real screenshots + real input; not synthetic taskbar paint'}
 [IO.File]::WriteAllText((Join-Path $out 'R273_NATIVE.json'),($r|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
 Write-Output ($r|ConvertTo-Json -Depth 12 -Compress)
}
if($status -notlike 'PASS_*'){throw ('R146_NATIVE_FAIL '+$failure)}
