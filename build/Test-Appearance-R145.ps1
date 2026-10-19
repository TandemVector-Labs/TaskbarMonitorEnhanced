[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$MainPath,[Parameter(Mandatory=$true)][string]$OutDir)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# .NET Framework app is loaded into Windows PowerShell 5.1, never launched or installed.
if($PSVersionTable.PSEdition -eq 'Core'){throw 'R145_USE_WINDOWS_POWERSHELL_51_FOR_FRAMEWORK_REFLECTION'}
if(Test-Path $OutDir){throw 'R145_CONTRACT_EVIDENCE_EXISTS'}
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$a=[Reflection.Assembly]::LoadFrom([IO.Path]::GetFullPath($MainPath))
$cType=$a.GetType('TaskbarMonitorEnhanced.AppConfig',$true)
$sType=$a.GetType('TaskbarMonitorEnhanced.SettingsForm',$true)
$pType=$a.GetType('TaskbarMonitorEnhanced.TaskbarGlassPixels',$true)
$flags=[Reflection.BindingFlags]'Instance,Public,NonPublic'
$stat=[Reflection.BindingFlags]'Static,Public,NonPublic'
$c=[Activator]::CreateInstance($cType,$true)
$normalize=$cType.GetMethod('Normalize',$flags)
$readings=@()
for($pct=1;$pct -le 100;$pct++){
 $c.GlassMode=$false;$c.Opacity=$pct/100.0;$c.ConfigSchemaVersion=8
 $normalize.Invoke($c,@())|Out-Null
 if($c.GlassMode -or [Math]::Abs($c.Opacity-$pct/100.0) -gt 0.000001 -or
   [Math]::Abs($c.OpacityWhenGlassOff-$pct/100.0) -gt 0.000001){throw ('R145_MODEL_IMPLICIT_GLASS '+$pct)}
}
$c.Opacity=0.17;$c.GlassMode=$false;$normalize.Invoke($c,@())|Out-Null
$ctor=@($sType.GetConstructors($flags)|Where-Object {$_.GetParameters().Count -eq 2})[0]
$form=$ctor.Invoke([object[]]@($c,$null))
$toggle=$sType.GetField('glassModeToggle',$flags).GetValue($form)
$number=$sType.GetField('opacity',$flags).GetValue($form)
if($toggle.GetType().Name -cne 'GlassToggleSwitch' -or $toggle -is [Windows.Forms.TrackBar] -or
 !($toggle -is [Windows.Forms.CheckBox]) -or !$toggle.TabStop -or [string]::IsNullOrWhiteSpace($toggle.AccessibleName)){
 throw 'R145_NOT_A_REAL_ACCESSIBLE_PILL_TOGGLE'
}
New-Item -ItemType Directory -Path $OutDir|Out-Null
function Capture-Control([string]$name){
 $bitmap=New-Object Drawing.Bitmap($toggle.Width,$toggle.Height)
 try{$toggle.CreateControl();$toggle.DrawToBitmap($bitmap,$toggle.ClientRectangle);$bitmap.Save((Join-Path $OutDir $name),[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
}
try{
 foreach($pct in @(1,2,10,29,30,31,99,100)){
  $toggle.Checked=$false;$number.Value=$pct
  Capture-Control ('SWITCH_OFF_'+$pct+'.png')
  # Exercise inherited click behavior instead of a continuous range input.
  $click=[Windows.Forms.CheckBox].GetMethod('OnClick',$flags)
  $click.Invoke($toggle,[object[]]@([EventArgs]::Empty))|Out-Null
  if(!$toggle.Checked -or $number.Enabled -or $number.Value -ne 0){throw ('R145_SWITCH_ON '+$pct)}
  Capture-Control ('SWITCH_ON_'+$pct+'.png')
  $click.Invoke($toggle,[object[]]@([EventArgs]::Empty))|Out-Null
  if($toggle.Checked -or !$number.Enabled -or $number.Minimum -ne 1 -or $number.Value -ne $pct){throw ('R145_SWITCH_OFF_RESTORE '+$pct)}
 }
}finally{$form.Dispose()}
# Synthetic bitmaps test the REAL production compositor; no screen is sampled.
$full=New-Object Drawing.Bitmap(4,2,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
$ink=New-Object Drawing.Bitmap(4,2,[Drawing.Imaging.PixelFormat]::Format32bppPArgb)
$halo=New-Object Drawing.Bitmap(4,2,[Drawing.Imaging.PixelFormat]::Format32bppPArgb)
$fg=[Drawing.Color]::FromArgb(255,21,208,91)
$bg=[Drawing.Color]::FromArgb(255,90,70,40)
$full.SetPixel(0,0,$bg);$full.SetPixel(1,0,$bg)
$ink.SetPixel(1,0,$fg);$halo.SetPixel(2,0,[Drawing.Color]::White)
$compose=$pType.GetMethod('Compose',$stat)
# Preserve the original 100-case contract while the semantic warning mask
# extends the production compositor's internal signature from 7 to 8 args.
$composeCount=@($compose.GetParameters()).Count
if($composeCount -ne 7 -and $composeCount -ne 8){throw ('R145_UNEXPECTED_COMPOSITOR_SIGNATURE_'+$composeCount)}
function Invoke-Compose([int]$pct,[bool]$glassMode){
 $args=[object[]]@($full.PSObject.BaseObject,$ink.PSObject.BaseObject,
   $halo.PSObject.BaseObject,$pct,[Drawing.Color]::White,$bg.PSObject.BaseObject,$glassMode)
 if($composeCount -eq 8){$args+=@($null)}
 return $compose.Invoke($null,$args)
}
try{
 foreach($pct in (1..100)){
  $b=Invoke-Compose $pct $false
  try{
   $back=$b.GetPixel(0,0);$glyph=$b.GetPixel(1,0);$ring=$b.GetPixel(2,0)
   if($back.A -ne [Math]::Round(255*$pct/100.0) -or $glyph.ToArgb() -ne $fg.ToArgb() -or $ring.A -ne 0){
    throw ('R145_PLAIN_OPACITY_CHANGED_THEME_INK_OR_CREATED_HALO '+$pct)
   }
   if($pct -in @(1,10,29,30,31,100)){$readings+=@{Percent=$pct;BackgroundAlpha=$back.A;ForegroundArgb=$glyph.ToArgb();HaloAlpha=$ring.A}}
  }finally{$b.Dispose()}
 }
 $b=Invoke-Compose 17 $true
 try{if($b.GetPixel(0,0).A -ne 0 -or $b.GetPixel(1,0).A -ne 255){throw 'R145_EXPLICIT_GLASS_ALPHA_NOT_ZERO'}}finally{$b.Dispose()}
 $b=Invoke-Compose 0 $false
 try{if($b.GetPixel(0,0).A -le 0){throw 'R145_ZERO_NUMBER_IMPLICITLY_ENABLED_GLASS'}}finally{$b.Dispose()}
}finally{$full.Dispose();$ink.Dispose();$halo.Dispose()}
$result=[ordered]@{Revision='R145';Status='PASS_MODEL_REAL_CONTROL_AND_PIXEL_CONTRACT';MainSHA256=(Get-FileHash $MainPath -Algorithm SHA256).Hash;ModelOpacityCases=100;PixelOpacityCases=100;RealToggleClickCycles=8;ControlKind='CheckBox-derived pill with circular thumb';ZeroOnlyExplicitGlass=$true;OpacityOneMinimum=$true;PlainInkAndChartsKeepThemeColor=$true;Screenshots='Control-only rendering, NOT native taskbar acceptance';Readings=$readings;PersonalInstallationTouched=$false}
[IO.File]::WriteAllText((Join-Path $OutDir 'R145_CONTRACT.json'),($result|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Output ($result|ConvertTo-Json -Depth 8 -Compress)
