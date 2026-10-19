[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$MainPath,
 [Parameter(Mandatory=$true)][string]$OutDir
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
# Inspect the exact candidate WinForms SettingsForm in Windows PowerShell 5.1.
# Never launch the running product, access user's configuration or send GUI input.
if($PSVersionTable.PSEdition -eq 'Core'){throw 'R244_WINDOWS_POWERSHELL_51_REQUIRED'}
if(Test-Path -LiteralPath $OutDir){throw 'R244_OUTPUT_PREEXISTS'}
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$path=[IO.Path]::GetFullPath($MainPath)
$a=[Reflection.Assembly]::LoadFrom($path)
$cfgType=$a.GetType('TaskbarMonitorEnhanced.AppConfig',$true)
$formType=$a.GetType('TaskbarMonitorEnhanced.SettingsForm',$true)
$flags=[Reflection.BindingFlags]'Instance,Public,NonPublic'
$config=[Activator]::CreateInstance($cfgType,$true)
$config.GlassMode=$true
$config.Opacity=0
$config.OpacityWhenGlassOff=0.1
$ctor=@($formType.GetConstructors($flags)|Where-Object {$_.GetParameters().Count -eq 2})[0]
$form=$ctor.Invoke([object[]]@($config,$null))
$results=[Collections.Generic.List[object]]::new()
$severe=[Collections.Generic.List[string]]::new()
try{
 $toggle=$formType.GetField('glassModeToggle',$flags).GetValue($form)
 $stateField=$formType.GetField('glassModeState',$flags)
 $state=if($stateField){$stateField.GetValue($form)}else{$null}
 $tabs=$formType.GetField('tabsControl',$flags).GetValue($form)
 if($null -eq $toggle -or $null -eq $tabs){throw 'R244_MISSING_SETTINGS_GLASS_OR_TABS'}
 if($tabs.TabPages.Count -ne 9){$severe.Add(('TAB_COUNT_'+$tabs.TabPages.Count))}
 if($toggle.BackColor.A -ne 255){$severe.Add('GLASS_TOGGLE_TRANSPARENT_BACKGROUND')}
 if($toggle.Text -ne ''){$severe.Add('GLASS_SWITCH_NATIVE_TEXT_NOT_EMPTY')}
 if($toggle.Width -gt 80){$severe.Add('GLASS_CONTROL_TOO_WIDE_WITH_EMBEDDED_STATUS')}
 if($null -eq $state){$severe.Add('GLASS_STATE_SEPARATE_LABEL_MISSING')}
 else{
  if($state.Parent -ne $toggle.Parent){$severe.Add('GLASS_LABEL_NOT_IN_SAME_PARENT')}
  if($state.BackColor.A -ne 255){$severe.Add('GLASS_STATE_LABEL_BACKGROUND_NOT_OPAQUE')}
  if($state.Text -cne 'On'){$severe.Add('GLASS_STATUS_NOT_ON')}
  if([Drawing.Rectangle]::Intersect($state.Bounds,$toggle.Bounds).Width -gt 0){$severe.Add('GLASS_TRACK_STATUS_OVERLAP')}
  $toggle.Checked=$false
  if($state.Text -cne 'Off'){$severe.Add('GLASS_STATUS_NOT_OFF_AFTER_TOGGLE')}
  $toggle.Checked=$true
  if($state.Text -cne 'On'){$severe.Add('GLASS_STATUS_NOT_ON_AFTER_TOGGLE')}
 }
 foreach($page in $tabs.TabPages){
  $controls=@($page.Controls|Where-Object {
      $_ -isnot [Windows.Forms.VScrollBar] -and $_ -isnot [Windows.Forms.HScrollBar]})
  $overlapCount=0
  for($i=0;$i -lt $controls.Count;$i++){
   for($j=$i+1;$j -lt $controls.Count;$j++){
    $left=$controls[$i];$right=$controls[$j]
    $int=[Drawing.Rectangle]::Intersect($left.Bounds,$right.Bounds)
    if($int.Width -ge 4 -and $int.Height -ge 4){
      $overlapCount++
      $severe.Add(('PAGE_'+$page.Text+'_SIBLING_OVERLAP_'+$left.GetType().Name+'_AND_'+$right.GetType().Name+'_XYWH_'+$int.ToString()))
    }
   }
  }
  $results.Add([ordered]@{Page=$page.Text;Controls=$controls.Count;SiblingOverlaps=$overlapCount
   AutoScrollWidth=$page.AutoScrollMinSize.Width;AutoScrollHeight=$page.AutoScrollMinSize.Height})
 }
 $toggleBitmap=New-Object Drawing.Bitmap($toggle.Width,$toggle.Height)
 New-Item -ItemType Directory -Path $OutDir -ErrorAction Stop|Out-Null
 try{
  $toggle.CreateControl()
  $toggle.DrawToBitmap($toggleBitmap,$toggle.ClientRectangle)
  $toggleBitmap.Save((Join-Path $OutDir 'R244_GLASS_SWITCH_ON.png'),[Drawing.Imaging.ImageFormat]::Png)
 }finally{$toggleBitmap.Dispose()}
 $overlapTotal=0;foreach($entry in $results){$overlapTotal+=[int]$entry['SiblingOverlaps']}
 $result=[ordered]@{
  Revision='R244';Status=if($severe.Count -eq 0){'PASS_ALL_NINE_SETTINGS_PAGES_NO_CONTROL_OVERLAP'}else{'FAIL_UI_OVERLAP_OR_GLASS_SWITCH'}
  MainSHA256=(Get-FileHash -LiteralPath $path).Hash
  SettingsPages=$tabs.TabPages.Count;CanvasBounds=@($form.Width,$form.Height)
  GlassTrackBounds=$toggle.Bounds.ToString()
  GlassTrackBackAlpha=$toggle.BackColor.A
  GlassStatusSeparate=$null -ne $state
  GlassStatusBounds=if($state){$state.Bounds.ToString()}else{'MISSING'}
  SiblingOverlapCount=$overlapTotal
  Violations=@($severe.ToArray());PageMetrics=@($results.ToArray())
  ReadOnlyCandidateUI=$true;PersonalInstallationTouched=$false
 }
 [IO.File]::WriteAllText((Join-Path $OutDir 'R244_SETTINGS_UI.json'),($result|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 Write-Output ($result|ConvertTo-Json -Compress -Depth 8)
 if($severe.Count){throw ('R244_SETTINGS_UI_FAIL_CLOSED '+($severe.ToArray() -join '; '))}
}finally{$form.Dispose()}
