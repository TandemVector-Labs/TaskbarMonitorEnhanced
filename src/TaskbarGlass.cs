using System.Text;
using System.IO;
using System.Web.Script.Serialization;
// R41: per-pixel taskbar background translucency with independent, contrast-safe glyphs.
// No screen pixels are stored. Only off-overlay taskbar samples are read in memory.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Globalization;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

namespace TaskbarMonitorEnhanced
{
    // R145: actual binary pill switch, with native CheckBox keyboard/accessibility semantics.
    // No TrackBar and no continuous-position state. Only the thumb position changes.
    internal sealed class GlassToggleSwitch : CheckBox
    {
        internal GlassToggleSwitch()
        {
            AutoSize=false;Size=new Size(68,34);TabStop=true;Text="";
            AccessibleRole=AccessibleRole.CheckButton;
            SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|
                ControlStyles.OptimizedDoubleBuffer|ControlStyles.ResizeRedraw,true);
            // Never composite other WinForms/native text behind this owner-painted control.
            BackColor=Color.FromArgb(20,28,38);Cursor=Cursors.Hand;
        }
        protected override void OnCheckedChanged(EventArgs e)
        {base.OnCheckedChanged(e);Invalidate();}
        protected override void OnKeyDown(KeyEventArgs e)
        {
            if(e.KeyCode==Keys.Left||e.KeyCode==Keys.Right)
            {Checked=e.KeyCode==Keys.Right;e.Handled=true;e.SuppressKeyPress=true;return;}
            base.OnKeyDown(e);
        }
        protected override void OnPaintBackground(PaintEventArgs e)
        {
            e.Graphics.Clear(BackColor);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(BackColor);
            e.Graphics.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            float h=Math.Max(12,Math.Min(ClientSize.Height-6,26f*DeviceDpi/96f));
            float w=Math.Min(ClientSize.Width-8,h*1.9f),x=4,y=(ClientSize.Height-h)/2f;
            Color track=SystemInformation.HighContrast?
                (Checked?SystemColors.Highlight:SystemColors.ControlDark):
                (Checked?Color.FromArgb(41,128,227):Color.FromArgb(96,106,121));
            if(!Enabled)track=SystemColors.GrayText;
            using(var path=new System.Drawing.Drawing2D.GraphicsPath())
            {
                path.AddArc(x,y,h,h,90,180);path.AddArc(x+w-h,y,h,h,270,180);path.CloseFigure();
                using(var brush=new SolidBrush(track))e.Graphics.FillPath(brush,path);
            }
            bool right=Checked^(RightToLeft==RightToLeft.Yes);
            float inset=Math.Max(2,h/9),d=h-2*inset;
            using(var thumb=new SolidBrush(SystemInformation.HighContrast?SystemColors.HighlightText:Color.White))
                e.Graphics.FillEllipse(thumb,right?x+w-inset-d:x+inset,y+inset,d,d);
            // The ON/OFF word lives in an independent opaque Settings label, not
            // on top of the switch's thumb or in an insufficient width at high DPI.
            if(Focused&&ShowFocusCues)ControlPaint.DrawFocusRectangle(e.Graphics,ClientRectangle);
        }
    }

    internal static class TaskbarGlassColor
    {
        internal static double Luminance(Color c)
        {
            Func<byte,double> f=v=>{double x=v/255.0;return x<=0.04045?x/12.92:Math.Pow((x+0.055)/1.055,2.4);};
            return 0.2126*f(c.R)+0.7152*f(c.G)+0.0722*f(c.B);
        }
        internal static double Contrast(Color a,Color b)
        {
            double x=Luminance(a),y=Luminance(b);
            return (Math.Max(x,y)+.05)/(Math.Min(x,y)+.05);
        }
        internal static Color EffectiveBackground(Color taskbar,Color theme,double opacity)
        {
            double q=Math.Max(0,Math.Min(1,opacity));
            return Color.FromArgb((int)Math.Round(taskbar.R+(theme.R-taskbar.R)*q),
                (int)Math.Round(taskbar.G+(theme.G-taskbar.G)*q),
                (int)Math.Round(taskbar.B+(theme.B-taskbar.B)*q));
        }
        internal static Color ReadableText(Color effective)
        {
            return Contrast(Color.White,effective)>=Contrast(Color.Black,effective)?Color.White:Color.Black;
        }
        internal static Color Fallback()
        {
            if(SystemInformation.HighContrast)return SystemColors.Window;
            try
            {
                using(RegistryKey k=Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
                {
                    object light=k==null?null:k.GetValue("SystemUsesLightTheme");
                    if(light is int)return (int)light==0?Color.FromArgb(31,31,35):Color.FromArgb(239,239,241);
                }
            }
            catch{}
            return Color.FromArgb(36,36,40);
        }

        // Never sample the monitor itself: avoid self-feedback and leaking screen contents.
        internal static Color Sample(Rectangle taskbarRect,Rectangle overlayRect,out bool actual)
        {
            actual=false;
            if(taskbarRect.Width<10||taskbarRect.Height<4)return Fallback();
            Rectangle screen=SystemInformation.VirtualScreen;
            var samples=new List<Color>();
            int centerY=taskbarRect.Top+taskbarRect.Height/2;
            int[] xs={
                taskbarRect.Left+8,taskbarRect.Left+taskbarRect.Width/5,
                taskbarRect.Left+taskbarRect.Width*2/5,taskbarRect.Left+taskbarRect.Width*3/5,
                taskbarRect.Left+taskbarRect.Width*4/5,taskbarRect.Right-8,
                overlayRect.Left-16,overlayRect.Right+16,
                overlayRect.Left-40,overlayRect.Right+40
            };
            foreach(int x in xs.Distinct())
            {
                Point p=new Point(x,centerY);
                if(!taskbarRect.Contains(p)||!screen.Contains(p)||
                   Rectangle.Inflate(overlayRect,10,3).Contains(p))continue;
                try
                {
                    using(var b=new Bitmap(1,1,PixelFormat.Format32bppArgb))
                    using(Graphics g=Graphics.FromImage(b))
                    {
                        g.CopyFromScreen(p,Point.Empty,new Size(1,1),CopyPixelOperation.SourceCopy);
                        samples.Add(b.GetPixel(0,0));
                    }
                }
                catch{}
            }
            if(samples.Count<2)return Fallback();
            // Median brightness avoids taskbar icons, time glyphs and the accent-colored Start icon.
            Color result=samples.OrderBy(Luminance).ElementAt(samples.Count/2);
            actual=true;
            return result;
        }
    }

    // Windows 11 DirectComposition can visually occlude layered Shell_TrayWnd children.
    // UpdateLayeredWindow's success is insufficient proof of readable foreground.
    // At sub-100% opacity draw a top-level click-accessible, taskbar-anchored glass
    // overlay with a verified native per-pixel surface. At 100% preserve the
    // previously accepted direct-child mode; High Contrast always remains opaque.
    internal static class TaskbarGlassHostMode
    {
        internal static bool RequiresTopLevel(double backgroundOpacity,bool highContrast)
        {
            return !highContrast; // R148: hit-testing host is independent of opacity/material, including fully opaque.
        }
    }

    internal static class TaskbarGlassPixels
    {
        internal static byte[] ReadPixels(Bitmap b,PixelFormat format)
        {
            Rectangle region=new Rectangle(0,0,b.Width,b.Height);
            BitmapData d=b.LockBits(region,ImageLockMode.ReadOnly,format);
            try
            {
                byte[] dst=new byte[b.Width*b.Height*4];
                for(int y=0;y<b.Height;y++)
                    Marshal.Copy(IntPtr.Add(d.Scan0,y*d.Stride),dst,y*b.Width*4,b.Width*4);
                return dst;
            }
            finally{b.UnlockBits(d);}
        }
        internal static void WritePixels(Bitmap b,byte[] src)
        {
            Rectangle region=new Rectangle(0,0,b.Width,b.Height);
            BitmapData d=b.LockBits(region,ImageLockMode.WriteOnly,PixelFormat.Format32bppPArgb);
            try
            {
                for(int y=0;y<b.Height;y++)
                    Marshal.Copy(src,y*b.Width*4,IntPtr.Add(d.Scan0,y*d.Stride),b.Width*4);
            }
            finally{b.UnlockBits(d);}
        }
        private static byte Byte(double x){return (byte)Math.Max(0,Math.Min(255,(int)Math.Round(x)));}
        // Semantic thermal warning color: preserve an unmistakable red tint even on
        // light taskbars, while retaining a contrasting halo around its glyphs.
        private static Color ThermalWarningInk(Color taskbarBackground)
        {
            Color[] candidates={
                Color.FromArgb(255,82,82),Color.FromArgb(255,172,172),
                Color.FromArgb(168,0,26),Color.FromArgb(37,0,8)};
            foreach(Color c in candidates)
                if(TaskbarGlassColor.Contrast(c,taskbarBackground)>=4.5)return c;
            return candidates.OrderByDescending(c=>TaskbarGlassColor.Contrast(c,taskbarBackground)).First();
        }        internal static Bitmap Compose(Bitmap full,Bitmap glyph,Bitmap halo,int opacityPercent,Color taskbar,Color themeBackground,bool glassMode,Bitmap thermalWarningMask=null)
        {
            if(full==null)throw new ArgumentNullException("full");
            if(glyph!=null&&(glyph.Width!=full.Width||glyph.Height!=full.Height))throw new ArgumentException("glyph geometry");
            if(halo!=null&&(halo.Width!=full.Width||halo.Height!=full.Height))throw new ArgumentException("halo geometry");
            if(thermalWarningMask!=null&&(thermalWarningMask.Width!=full.Width||thermalWarningMask.Height!=full.Height))
                throw new ArgumentException("thermal warning mask geometry");
            int pct=glassMode?0:Math.Max(1,Math.Min(100,opacityPercent));
            byte[] basePixels=ReadPixels(full,PixelFormat.Format32bppArgb);
            byte[] inkPixels=glyph==null?null:ReadPixels(glyph,PixelFormat.Format32bppPArgb);
            byte[] haloPixels=halo==null?null:ReadPixels(halo,PixelFormat.Format32bppPArgb);
            byte[] warningPixels=glassMode&&thermalWarningMask!=null?
                ReadPixels(thermalWarningMask,PixelFormat.Format32bppPArgb):null;
            byte[] pixels=new byte[basePixels.Length];
            bool adaptInk=glassMode; // R145: NEVER infer material or recolor ink from an opacity threshold.
            Color effectiveBackground=TaskbarGlassColor.EffectiveBackground(taskbar,themeBackground,pct/100d);
            Color chosen=TaskbarGlassColor.ReadableText(effectiveBackground);
            Color warningInk=warningPixels==null?Color.Empty:ThermalWarningInk(effectiveBackground);
            Color outline=chosen.ToArgb()==Color.White.ToArgb()?Color.Black:Color.White;
            double backgroundScale=pct/100d;
            for(int i=0;i<pixels.Length;i+=4)
            {
                double ink=inkPixels==null?0:inkPixels[i+3]/255d;
                bool thermalHot=warningPixels!=null&&warningPixels[i+3]>=128;
                Color textInk=thermalHot?warningInk:chosen;
                double ring=adaptInk&&haloPixels!=null?Math.Max(0,haloPixels[i+3]/255d-ink)*0.78:0;
                ring=Math.Min(1-ink,ring);
                double bg=(1-ink-ring)*backgroundScale*(basePixels[i+3]/255d);
                pixels[i+3]=Byte((ink+ring+bg)*255);
                for(int ch=0;ch<3;ch++)
                {
                    int textChannel=ch==0?textInk.B:ch==1?textInk.G:textInk.R;
                    int outlineChannel=ch==0?outline.B:ch==1?outline.G:outline.R;
                    double glyphContribution=adaptInk?textChannel*ink:(inkPixels==null?0:inkPixels[i+ch]);
                    pixels[i+ch]=Byte(glyphContribution+outlineChannel*ring+basePixels[i+ch]*bg);
                }
            }
            Bitmap result=new Bitmap(full.Width,full.Height,PixelFormat.Format32bppPArgb);
            try{WritePixels(result,pixels);return result;}
            catch{result.Dispose();throw;}
        }
    }

    internal static class TaskbarGlassNative
    {
        [StructLayout(LayoutKind.Sequential)] private struct NPoint { public int X,Y; public NPoint(int x,int y){X=x;Y=y;} }
        [StructLayout(LayoutKind.Sequential)] private struct NSize { public int CX,CY; public NSize(int w,int h){CX=w;CY=h;} }
        [StructLayout(LayoutKind.Sequential,Pack=1)] private struct Blend
        {
            public byte BlendOp,BlendFlags,ConstantAlpha,AlphaFormat;
        }
        [StructLayout(LayoutKind.Sequential)] private struct BitmapInfoHeader
        {
            public uint Size; public int Width,Height;
            public ushort Planes,BitCount;
            public uint Compression,SizeImage;public int XPelsPerMeter,YPelsPerMeter;
            public uint ClrUsed,ClrImportant;
        }
        [StructLayout(LayoutKind.Sequential)] private struct BitmapInfo
        {
            public BitmapInfoHeader Header;
            [MarshalAs(UnmanagedType.ByValArray, SizeConst=3)] public uint[] Colors;
        }
        [DllImport("user32.dll",SetLastError=true)] private static extern IntPtr GetDC(IntPtr window);
        [DllImport("user32.dll",SetLastError=true)] private static extern int ReleaseDC(IntPtr window,IntPtr dc);
        [DllImport("gdi32.dll",SetLastError=true)] private static extern IntPtr CreateCompatibleDC(IntPtr dc);
        [DllImport("gdi32.dll",SetLastError=true)] private static extern bool DeleteDC(IntPtr dc);
        [DllImport("gdi32.dll",SetLastError=true)] private static extern IntPtr CreateDIBSection(IntPtr dc,ref BitmapInfo info,uint use,out IntPtr bits,IntPtr section,uint offset);
        [DllImport("gdi32.dll",SetLastError=true)] private static extern IntPtr SelectObject(IntPtr dc,IntPtr obj);
        [DllImport("gdi32.dll",SetLastError=true)] private static extern bool DeleteObject(IntPtr obj);
        [DllImport("user32.dll",SetLastError=true)] private static extern bool UpdateLayeredWindow(IntPtr hwnd,IntPtr screen,ref NPoint dst,ref NSize size,IntPtr source,ref NPoint sourcePoint,uint colorKey,ref Blend blend,uint flags);

        internal static bool Upload(IntPtr window,Bitmap picture,Point screenLocation,out int win32)
        {
            win32=0;
            if(window==IntPtr.Zero||picture==null||picture.Width<1||picture.Height<1){win32=87;return false;}
            IntPtr screen=IntPtr.Zero,dc=IntPtr.Zero,dib=IntPtr.Zero,old=IntPtr.Zero;
            try
            {
                screen=GetDC(IntPtr.Zero);
                if(screen==IntPtr.Zero){win32=Marshal.GetLastWin32Error();return false;}
                dc=CreateCompatibleDC(screen);
                if(dc==IntPtr.Zero){win32=Marshal.GetLastWin32Error();return false;}
                BitmapInfo info=new BitmapInfo{
                    Header=new BitmapInfoHeader{Size=(uint)Marshal.SizeOf(typeof(BitmapInfoHeader)),Width=picture.Width,
                        Height=-picture.Height,Planes=1,BitCount=32,Compression=0,SizeImage=(uint)(picture.Width*picture.Height*4)},
                    Colors=new uint[3]};
                IntPtr pixels;
                dib=CreateDIBSection(screen,ref info,0,out pixels,IntPtr.Zero,0);
                if(dib==IntPtr.Zero||pixels==IntPtr.Zero){win32=Marshal.GetLastWin32Error();return false;}
                byte[] data=TaskbarGlassPixels.ReadPixels(picture,PixelFormat.Format32bppPArgb);
                Marshal.Copy(data,0,pixels,data.Length);
                old=SelectObject(dc,dib);
                if(old==IntPtr.Zero||old==new IntPtr(-1)){win32=Marshal.GetLastWin32Error();return false;}
                var dst=new NPoint(screenLocation.X,screenLocation.Y);
                var src=new NPoint(0,0);
                var sz=new NSize(picture.Width,picture.Height);
                var blend=new Blend{BlendOp=0,BlendFlags=0,ConstantAlpha=255,AlphaFormat=1};
                bool ok=UpdateLayeredWindow(window,screen,ref dst,ref sz,dc,ref src,0,ref blend,2);
                if(!ok)win32=Marshal.GetLastWin32Error();
                return ok;
            }
            catch(ExternalException){win32=Marshal.GetLastWin32Error();return false;}
            finally
            {
                if(dc!=IntPtr.Zero&&old!=IntPtr.Zero&&old!=new IntPtr(-1))SelectObject(dc,old);
                if(dib!=IntPtr.Zero)DeleteObject(dib);
                if(dc!=IntPtr.Zero)DeleteDC(dc);
                if(screen!=IntPtr.Zero)ReleaseDC(IntPtr.Zero,screen);
            }
        }
    }

    internal sealed partial class OverlayForm
    {
        private bool glassNativeVisualProofMode;
        internal bool RequiresGlassTopLevel
        {get{return config!=null && (!proofMode||glassNativeVisualProofMode) &&
                     TaskbarGlassHostMode.RequiresTopLevel(config.Opacity,SystemInformation.HighContrast);}}
        internal void StartGlassGuardTickForProof()
        {
            if(!proofMode||!glassNativeVisualProofMode)
                throw new InvalidOperationException("Start glass proof requires an isolated form.");
            StartGuardTick(taskbar);
        }

        internal bool StartGlassFloatingForProof
        {get{return startGlassTemporarilyFloating;}}
        internal Rectangle StartGlassLiftedBoundsForProof
        {get{return startGlassTemporaryBounds;}}
        internal int StartGlassReturnTransitionsForProof
        {get{return startGlassReturnTransitions;}}
        internal int StartGlassLiftTransitionsForProof
        {get{return startGlassLiftTransitions;}}

        internal bool RecreateNativeGlassHandleForProof()
        {
            if(!proofMode||!glassNativeVisualProofMode||!IsHandleCreated)
                throw new InvalidOperationException("Only an active isolated glass proof can recreate its HWND.");
            IntPtr previous=Handle;
            RecreateHandle();
            Application.DoEvents();
            AttachIntegrated();
            return previous!=Handle && !glassLegacyFallback &&
                   Native.IsWindowVisible(Handle) &&
                   (Native.GetWindowLongPtr(Handle,Native.GWL_STYLE).ToInt64()&Native.WS_CHILD)==0;
        }

        internal void EnableNativeGlassVisualProof()
        {
            if(!proofMode||IsHandleCreated)throw new InvalidOperationException("Glass visual proof requires a fresh proof-only instance.");
            glassNativeVisualProofMode=true;
        }
        internal bool SwitchNativeGlassForProof(double nextOpacity)
        {
            if(!proofMode||!glassNativeVisualProofMode)
                throw new InvalidOperationException("Mode transition allowed only in isolated proof instance.");
            config.Opacity=Math.Max(0,Math.Min(1,nextOpacity));
            config.Normalize();
            AttachIntegrated();
            if(!IsHandleCreated||!Native.IsWindowVisible(Handle))return false;
            long style=Native.GetWindowLongPtr(Handle,Native.GWL_STYLE).ToInt64();
            if(RequiresGlassTopLevel)
                return (style&Native.WS_CHILD)==0 && !glassLegacyFallback;
            return (style&Native.WS_CHILD)!=0 && Native.GetParent(Handle)==taskbar;
        }

        internal Rectangle AttachNativeGlassVisualProof()
        {
            if(!proofMode||!glassNativeVisualProofMode)throw new InvalidOperationException("Not a native-proof form.");
            AttachIntegrated();
            if(!RequiresGlassTopLevel||glassLegacyFallback||expectedRect.Width<500||
               !IsHandleCreated||!Native.IsWindowVisible(Handle)||
               (Native.GetWindowLongPtr(Handle,Native.GWL_STYLE).ToInt64()&Native.WS_CHILD)!=0)
                throw new InvalidOperationException("Production top-level glass compositor did not attach natively.");
            long ex=Native.GetWindowLongPtr(Handle,Native.GWL_EXSTYLE).ToInt64();
            if((ex&Native.WS_EX_LAYERED)==0||(ex&Native.WS_EX_COMPOSITED)!=0||
               (ex&Native.WS_EX_TRANSPARENT)!=0)
                throw new InvalidOperationException("Native proof top-level layered style incorrect.");
            return expectedRect;
        }

        private int glassDirectMetricRefreshCount;
        internal int GlassDirectMetricRefreshCountForProof {get{return glassDirectMetricRefreshCount;}}
        private void RefreshGlassAfterMetricCommit()
        {
            if(presentationSuppressed||!IsHandleCreated||!RequiresGlassTopLevel||glassLegacyFallback)return;
            if(proofMode&&!glassNativeVisualProofMode)return;
            if(PaintPerPixelLayer())glassDirectMetricRefreshCount++;
            // On failure PaintPerPixelLayer already records native error and applies
            // the opaque last-resort fallback; never misreport successful refresh.
        }

        private Graphics glassInkCanvas,glassHaloCanvas,glassThermalWarningCanvas;
        private bool glassLegacyFallback;
        private bool glassLegacyFallbackReady;
        private DateTime taskbarGlassSampleAt=DateTime.MinValue;
        private Color taskbarGlassColor=Color.FromArgb(32,32,36);
        private bool taskbarGlassSampled;
        private DateTime glassLastFailureAt=DateTime.MinValue;

        private void DrawThemeGlyph(Graphics g,string text,Font f,Brush brush,float x,float y)
        {
            g.DrawString(text,f,brush,x,y);
            if(glassInkCanvas==null)return;
            glassInkCanvas.DrawString(text,f,brush,x,y);
            if(glassHaloCanvas!=null)
            {
                using(var halo=new SolidBrush(Color.White))
                {
                    glassHaloCanvas.DrawString(text,f,halo,x-1,y);
                    glassHaloCanvas.DrawString(text,f,halo,x+1,y);
                    glassHaloCanvas.DrawString(text,f,halo,x,y-1);
                    glassHaloCanvas.DrawString(text,f,halo,x,y+1);
                }
            }
        }
        private void DrawThemeGlyph(Graphics g,string text,Font f,Brush brush,PointF p)
        {DrawThemeGlyph(g,text,f,brush,p.X,p.Y);}

        private Color GlassTaskbarSample()
        {
            if(proofMode&&!glassNativeVisualProofMode)return TaskbarGlassColor.Fallback();
            DateTime now=DateTime.UtcNow;
            if((now-taskbarGlassSampleAt).TotalSeconds<4)return taskbarGlassColor;
            taskbarGlassSampleAt=now;
            Rectangle frame=lastTaskbarScreenRect;
            if(frame.Width<10&&taskbar!=IntPtr.Zero)
            {
                Native.RECT rect;
                if(Native.GetWindowRect(taskbar,out rect))frame=rect.ToRectangle();
            }
            Rectangle content=new Rectangle(PointToScreen(Point.Empty),ClientSize);
            taskbarGlassColor=TaskbarGlassColor.Sample(frame,content,out taskbarGlassSampled);
            return taskbarGlassColor;
        }
        // R44 chart proof seeds ONLY a purpose-built proof-mode renderer.
        // Real taskbar metrics/history are never synthesized or persisted.
        // Isolated proof only: no telemetry process or user configuration is changed.
        internal void SetCpuTemperatureForThermalProof(float temperatureC)
        {
            if(!proofMode||!MetricStatistics.Finite(temperatureC))
                throw new InvalidOperationException("Thermal pixel stimulus is proof-only.");
            snapshot.CpuDevices.Clear();
            snapshot.CpuTempAvailable=true;
            snapshot.CpuTempCurrent=temperatureC;
        }
        internal void SeedChartHistoryForProof()
        {
            if(!proofMode)throw new InvalidOperationException("Synthetic chart fixture limited to proof mode.");
            for(int i=0;i<48;i++)
            {
                history.Add("CPU",16f+((i*13)%71));
                history.Add("RAM",26f+((i*7)%49));
                history.Add("DISK",1f+((i*11)%45));
                history.Add("GPU",14f+((i*19)%79));
                history.Add("VRAM",24f+((i*17)%65));
                history.Add("NET",1f+((i*23)%61));
            }
        }
        internal Bitmap RenderGlassPixelsForProof(string theme,int width,int height,int percent,Color taskbar)
        {return RenderGlassBitmap(ThemeCatalog.Get(theme),width,height,percent,taskbar,percent==0);}
        // Explicit test seam; production always supplies config.GlassMode, not inferred alpha.
        internal Bitmap RenderAppearanceForProof(string theme,int width,int height,int percent,Color taskbar,bool glassMode)
        {return RenderGlassBitmap(ThemeCatalog.Get(theme),width,height,percent,taskbar,glassMode);}
        private Bitmap RenderGlassBitmap(ThemeDefinition theme,int width,int height,int percent,Color taskbar,bool glassMode)
        {
            percent=glassMode?0:Math.Max(1,Math.Min(100,percent));
            width=Math.Max(1,width);height=Math.Max(1,height); // Preserve the exact native taskbar footprint, including compact 279px hosts.
            Bitmap ink=null,halo=null,full=null,thermalMask=null;
            try
            {
                if(percent<100)
                {
                    ink=new Bitmap(width,height,PixelFormat.Format32bppPArgb);
                    glassInkCanvas=Graphics.FromImage(ink);
                    glassInkCanvas.TextRenderingHint=System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                    glassInkCanvas.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                    glassInkCanvas.Clear(Color.Transparent);
                    if(glassMode)
                    {
                        halo=new Bitmap(width,height,PixelFormat.Format32bppPArgb);
                        glassHaloCanvas=Graphics.FromImage(halo);
                        glassHaloCanvas.TextRenderingHint=System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                        glassHaloCanvas.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                        glassHaloCanvas.Clear(Color.Transparent);
                        thermalMask=new Bitmap(width,height,PixelFormat.Format32bppPArgb);
                        glassThermalWarningCanvas=Graphics.FromImage(thermalMask);
                        glassThermalWarningCanvas.Clear(Color.Transparent);
                    }
                }
                full=RenderThemeDefinition(theme,width,height);
                Bitmap output=TaskbarGlassPixels.Compose(full,ink,halo,percent,taskbar,theme.Background,glassMode,thermalMask);
                if(diagnosticBeacon&&!proofMode)
                    using(Graphics beacon=Graphics.FromImage(output))PaintDiagnosticBeacon(beacon);
                return output;
            }
            finally
            {
                if(glassInkCanvas!=null){glassInkCanvas.Dispose();glassInkCanvas=null;}
                if(glassHaloCanvas!=null){glassHaloCanvas.Dispose();glassHaloCanvas=null;}
                if(glassThermalWarningCanvas!=null){glassThermalWarningCanvas.Dispose();glassThermalWarningCanvas=null;}
                if(full!=null)full.Dispose();
                if(ink!=null)ink.Dispose();
                if(halo!=null)halo.Dispose();
                if(thermalMask!=null)thermalMask.Dispose();
            }
        }
        private bool PaintPerPixelLayer()
        {
            if(presentationSuppressed||(proofMode&&!glassNativeVisualProofMode)||glassLegacyFallback||!IsHandleCreated||taskbar==IntPtr.Zero)return false;
            Rectangle r=ClientRectangle;
            if(r.Width<80||r.Height<16)return false;
            int alpha=SystemInformation.HighContrast?100:Math.Max(0,Math.Min(100,(int)Math.Round(config.Opacity*100)));
            ThemeDefinition theme=WindowsThemePolicy.Resolve(config);
            try
            {
                // Plain translucency retains theme ink and never reads desktop pixels.
                Color sampled=config.GlassMode?GlassTaskbarSample():theme.Background;
                using(Bitmap pixels=RenderGlassBitmap(theme,r.Width,r.Height,alpha,sampled,config.GlassMode&&!SystemInformation.HighContrast))
                {
                    int win32;
                    if(TaskbarGlassNative.Upload(Handle,pixels,PointToScreen(Point.Empty),out win32))
                    {
                        lastPaintMetrics=BuildMetricViews(theme);
                        return true;
                    }
                    if((DateTime.UtcNow-glassLastFailureAt).TotalSeconds>20)
                    {
                        glassLastFailureAt=DateTime.UtcNow;
                        Log.Write("ERROR","TASKBAR_GLASS_NATIVE_FAIL code="+win32+" taskbarColorSampled="+taskbarGlassSampled);
                    }
                }
            }
            catch(Exception ex)
            {
                Log.Write("ERROR","TASKBAR_GLASS_COMPOSITION_FAIL "+ex.GetType().Name+" "+ex.Message);
            }
            glassLegacyFallback=true;
            glassLegacyFallbackReady=Native.SetLayeredWindowAttributes(Handle,0,255,Native.LWA_ALPHA);
            if(!glassLegacyFallbackReady)
                Log.Write("ERROR","TASKBAR_GLASS_FALLBACK_STYLE_FAIL "+Marshal.GetLastWin32Error());
            else
                Log.Write("WARN","TASKBAR_GLASS_FALLBACK_OPAQUE: per-pixel alpha unavailable on this taskbar");
            return false;
        }

        internal bool PaintGlassForNativeProof()
        {return PaintPerPixelLayer();}
    }
}
namespace TaskbarMonitorEnhanced
{
    internal static class TaskbarGlassProof
    {
        private static void Require(bool ok,string detail)
        {if(!ok)throw new InvalidOperationException("R41 "+detail);}
        private static byte[] Pix(Bitmap b)
        {return TaskbarGlassPixels.ReadPixels(b,PixelFormat.Format32bppPArgb);}
        private static object Analyze(string name,int opacity,Color sample,Bitmap bitmap)
        {
            byte[] pixels=Pix(bitmap);
            int transparent=0,opaque=0,lightText=0,darkText=0;
            for(int i=0;i<pixels.Length;i+=4)
            {
                int a=pixels[i+3];
                if(a==0)transparent++;
                if(a>=245)
                {
                    opaque++;
                    if(pixels[i]>=245&&pixels[i+1]>=245&&pixels[i+2]>=245)lightText++;
                    if(pixels[i]<=15&&pixels[i+1]<=15&&pixels[i+2]<=15)darkText++;
                }
            }
            if(opacity==0)
            {
                Require(transparent>=bitmap.Width*bitmap.Height/2,"clear background "+name);
                Require(opaque>25,"opaque glyph coverage "+name);
                bool light=TaskbarGlassColor.ReadableText(sample).ToArgb()==Color.White.ToArgb();
                Require(light?lightText>12:darkText>12,"ink contrast choice "+name);
            }
            if(opacity==100)Require(transparent==0,"100% background should be opaque");
            return new{name,opacity,taskbar=sample.ToArgb(),transparent,opaque,lightText,darkText};
        }
        internal static int Run(string dir)
        {
            try
            {
                Directory.CreateDirectory(dir);
                var observations=new List<object>();
                int styles=0;
                using(var proof=new OverlayForm(new AppConfig(),true))
                {
                    foreach(string name in ThemeCatalog.Names)
                    {
                        foreach(Color sample in new[]{Color.FromArgb(18,20,24),Color.FromArgb(235,238,241)})
                        foreach(int pct in new[]{0,29})
                        using(Bitmap b=proof.RenderGlassPixelsForProof(name,620,48,pct,sample))
                        {
                            observations.Add(Analyze(name,pct,sample,b));
                            styles++;
                        }
                    }
                    foreach(int pct in new[]{0,1,15,30,31,50,99,100})
                    using(Bitmap b=proof.RenderGlassPixelsForProof("Bauhaus Blocks",620,48,pct,Color.FromArgb(127,125,128)))
                        observations.Add(Analyze("boundary",pct,Color.FromArgb(127,125,128),b));
                }
                Require(TaskbarGlassHostMode.RequiresTopLevel(0,false),"zero alpha top-level required");
                Require(TaskbarGlassHostMode.RequiresTopLevel(0.29,false),"29% alpha top-level required");
                Require(TaskbarGlassHostMode.RequiresTopLevel(.97,false),"97% alpha top-level required");
                Require(TaskbarGlassHostMode.RequiresTopLevel(1.0,false),"100% opacity retains the same interactive native host");
                Require(!TaskbarGlassHostMode.RequiresTopLevel(.15,true),"High Contrast forced opaque child");
                foreach(Color bg in new[]{Color.Black,Color.White,Color.FromArgb(127,127,127),Color.FromArgb(220,190,20)})
                    Require(TaskbarGlassColor.Contrast(TaskbarGlassColor.ReadableText(bg),bg)>=4.5,"contrast target");
                var json=new JavaScriptSerializer().Serialize(new{
                    Status="PASS",Tests=styles,AllThemes=ThemeCatalog.Names.Length,
                    Opacities=new[]{0,1,15,29,30,31,50,99,100},
                    ContrastMinimum=4.5,TextRetainedAtZero=true,
                    ScreenCapture=false,IndividualPixelTransparency=true,Observations=observations
                });
                File.WriteAllText(Path.Combine(dir,"GLASS_PROOF.json"),json,new UTF8Encoding(false));
                Console.WriteLine("TBME_GLASS_PROOF=PASS THEMES="+ThemeCatalog.Names.Length+" SAMPLES="+styles+" ZERO_BACKGROUND=TRUE OPAQUE_GLYPHS=TRUE");
                return 0;
            }
            catch(Exception ex)
            {
                Console.Error.WriteLine("TBME_GLASS_PROOF=FAIL "+ex);
                return 41;
            }
        }
    }
    // Exercises the real theme/metric/native bitmap painter with synthetic CPU heat,
    // but never creates a native host window or sends a user notification.
    internal static class TaskbarGlassThermalProof
    {
        private static void Require(bool ok,string label)
        {if(!ok)throw new InvalidOperationException("R272 thermal glass: "+label);}
        private static int RedForeground(Bitmap bitmap)
        {
            byte[] pixels=TaskbarGlassPixels.ReadPixels(bitmap,PixelFormat.Format32bppPArgb);
            int count=0;
            for(int i=0;i<pixels.Length;i+=4)
            {
                int a=pixels[i+3],b=pixels[i],g=pixels[i+1],r=pixels[i+2];
                if(a>=215&&r>g+22&&r>b+22&&r>=32)count++;
            }
            return count;
        }
        private static int ClearBackground(Bitmap bitmap)
        {
            byte[] pixels=TaskbarGlassPixels.ReadPixels(bitmap,PixelFormat.Format32bppPArgb);
            int count=0;
            for(int i=3;i<pixels.Length;i+=4)if(pixels[i]==0)count++;
            return count;
        }
        internal static int Run(string directory)
        {
            try
            {
                if(Directory.Exists(directory))throw new InvalidOperationException("Proof output exists.");
                Directory.CreateDirectory(directory);
                AppConfig cfg=new AppConfig();
                cfg.GlassMode=true;cfg.Opacity=0;cfg.EnableTemperatureAlerts=true;
                cfg.CpuTempWarningC=85;cfg.ShowCpu=true;cfg.ShowTemperatures=true;
                cfg.ShowRam=false;cfg.ShowGpu=false;cfg.ShowDisk=false;
                cfg.ShowVram=false;cfg.ShowNetwork=false;cfg.ShowSparklines=true;
                cfg.Normalize();
                Require(AlertPolicy.IsCpuHot(true,95,cfg),"hot rule");
                Require(!AlertPolicy.IsCpuHot(true,60,cfg),"cold rule");
                Require(!AlertPolicy.IsCpuHot(false,100,cfg),"missing data rule");
                int cases=0,hotMin=int.MaxValue,nonhotMax=0,clearMin=int.MaxValue;
                using(OverlayForm form=new OverlayForm(cfg,true))
                {
                    foreach(string theme in ThemeCatalog.Names)
                    foreach(Color taskbar in new[]{Color.FromArgb(18,20,24),Color.FromArgb(235,238,241)})
                    {
                        form.SetCpuTemperatureForThermalProof(60);
                        using(Bitmap cold=form.RenderAppearanceForProof(theme,620,48,0,taskbar,true))
                        {
                            int coldRed=RedForeground(cold);
                            Require(coldRed==0,"cold accent red "+theme+" "+taskbar);
                            nonhotMax=Math.Max(nonhotMax,coldRed);
                        }
                        form.SetCpuTemperatureForThermalProof(95);
                        using(Bitmap hot=form.RenderAppearanceForProof(theme,620,48,0,taskbar,true))
                        {
                            int hotRed=RedForeground(hot);
                            int clear=ClearBackground(hot);
                            Require(hotRed>=40,"missing hot red ink "+theme+" "+taskbar+" pixels="+hotRed);
                            Require(clear>620*48/4,"hot alert made Glass backdrop opaque "+theme);
                            hotMin=Math.Min(hotMin,hotRed);
                            clearMin=Math.Min(clearMin,clear);
                        }
                        cases++;
                    }
                    Require(cases==ThemeCatalog.Names.Length*2,"theme and taskbar background coverage");
                    cfg.EnableTemperatureAlerts=false;
                    using(Bitmap off=form.RenderAppearanceForProof("Retro Terminal",620,48,0,Color.FromArgb(18,20,24),true))
                        Require(RedForeground(off)==0,"disabled alert should not tint");
                    cfg.EnableTemperatureAlerts=true;
                    form.SetCpuTemperatureForThermalProof(95);
                    using(Bitmap normalOpacity=form.RenderAppearanceForProof("Retro Terminal",620,48,29,Color.FromArgb(18,20,24),false))
                    {
                        Require(normalOpacity.Width==620&&normalOpacity.Height==48,"ordinary opacity mode geometry");
                    }
                }
                var result=new{Revision="R272",Status="PASS",Source="REAL_OVERLAY_THEME_AND_METRIC_PAINTER",
                    HotC=95,ColdC=60,ThresholdC=85,Themes=ThemeCatalog.Names.Length,
                    ThemeBackgroundPairs=cases,HotRedPixelsMinimum=hotMin,ColdRedPixelsMaximum=nonhotMax,
                    ClearBackgroundPixelsMinimum=clearMin,OptOutTested=true,NoNativeHostInput=true,
                    NoUserSettingsOrSensorMutation=true};
                File.WriteAllText(Path.Combine(directory,"THERMAL_GLASS_PROOF.json"),
                    new JavaScriptSerializer().Serialize(result),new UTF8Encoding(false));
                Console.WriteLine("TBME_THERMAL_GLASS_PROOF=PASS PAIRS="+cases+
                    " MIN_HOT_RED="+hotMin+" MIN_CLEAR="+clearMin);
                return 0;
            }
            catch(Exception ex)
            {
                Console.Error.WriteLine("TBME_THERMAL_GLASS_PROOF=FAIL "+ex);
                return 72;
            }
        }
    }
    // Independent proof: charts must remain foreground at zero opacity.
    // Only the proof-mode instance receives synthetic history; production never does.
    internal static class TaskbarChartGlassProof
    {
        private static void Check(bool pass,string message)
        {if(!pass)throw new InvalidOperationException("R44 CHART "+message);}
        private static object Compare(string theme,Color taskbar,int opacity,
            Bitmap before,Bitmap after)
        {
            byte[] oldPixels=TaskbarGlassPixels.ReadPixels(before,PixelFormat.Format32bppPArgb);
            byte[] newPixels=TaskbarGlassPixels.ReadPixels(after,PixelFormat.Format32bppPArgb);
            int chartPixels=0,solidChart=0,clearPixels=0,inkContrast=0;
            Color expected=TaskbarGlassColor.ReadableText(
                TaskbarGlassColor.EffectiveBackground(taskbar,ThemeCatalog.Get(theme).Background,opacity/100d));
            for(int y=20;y<after.Height-2;y++)
            for(int x=3;x<after.Width-3;x++)
            {
                int i=(y*after.Width+x)*4;
                int oa=oldPixels[i+3],na=newPixels[i+3];
                if(na==0)clearPixels++;
                if(na>=190 && na-oa>=66)
                {
                    chartPixels++;
                    if(na>=245)
                    {
                        solidChart++;
                        int db=Math.Abs(newPixels[i]-expected.B);
                        int dg=Math.Abs(newPixels[i+1]-expected.G);
                        int dr=Math.Abs(newPixels[i+2]-expected.R);
                        if(db<=12&&dg<=12&&dr<=12)inkContrast++;
                    }
                }
            }
            Check(chartPixels>=16,"missing separate chart pixels for "+theme+" alpha="+opacity+" chart="+chartPixels);
            Check(solidChart>=7,"chart ink too faint for "+theme+" alpha="+opacity+" strong="+solidChart);
            if(opacity==0)
            {
                Check(inkContrast>=6,"adapted chart ink wrong for "+theme+" alpha="+opacity+" count="+inkContrast);
                Check(TaskbarGlassColor.Contrast(expected,
                    TaskbarGlassColor.EffectiveBackground(taskbar,ThemeCatalog.Get(theme).Background,opacity/100d))>=4.5,
                    "chart color WCAG threshold");
            }
            if(opacity==0)Check(clearPixels>after.Width*4,"chart proof lost clear pixels "+theme);
            return new {theme,opacity,taskbar=taskbar.ToArgb(),chartPixels,solidChart,clearPixels,inkContrast};
        }
        internal static int Run(string outputDirectory)
        {
            try
            {
                if(Directory.Exists(outputDirectory))
                    throw new InvalidOperationException("Chart proof output already exists; do not overwrite.");
                Directory.CreateDirectory(outputDirectory);
                var seen=new List<object>();
                int pairCount=0;
                var palette=new[]{Color.FromArgb(18,21,23),Color.FromArgb(238,239,242)};
                using(var config=new ChartProofConfigScope())
                using(var renderer=new OverlayForm(config.Config,true))
                {
                    renderer.SeedChartHistoryForProof();
                    foreach(string name in ThemeCatalog.Names)
                    foreach(Color bg in palette)
                    foreach(int pct in new[]{0,29})
                    {
                        config.Config.ShowSparklines=false;
                        using(Bitmap without=renderer.RenderGlassPixelsForProof(name,1100,48,pct,bg))
                        {
                            config.Config.ShowSparklines=true;
                            using(Bitmap with=renderer.RenderGlassPixelsForProof(name,1100,48,pct,bg))
                                seen.Add(Compare(name,bg,pct,without,with));
                        }
                        pairCount++;
                    }
                    // Boundary proof: alpha and manual toggle remain correct
                    foreach(int pct in new[]{1,15,30,31,50,99,100})
                    {
                        config.Config.ShowSparklines=false;
                        using(Bitmap without=renderer.RenderGlassPixelsForProof("Dark Minimal Pro",1100,48,pct,palette[0]))
                        {
                            config.Config.ShowSparklines=true;
                            using(Bitmap with=renderer.RenderGlassPixelsForProof("Dark Minimal Pro",1100,48,pct,palette[0]))
                            {
                                Check(with.Width==1100&&with.Height==48,"chart boundary geometry");
                                if(pct<=31)seen.Add(Compare("Dark Minimal Pro",palette[0],pct,without,with));
                            }
                        }
                    }
                }
                Check(pairCount==ThemeCatalog.Names.Length*4,"49-theme dark/light opacity matrix");
                var json=new JavaScriptSerializer().Serialize(new{
                    Status="PASS",Source="R44 chart foreground proof",Themes=ThemeCatalog.Names.Length,
                    Pairs=pairCount,Observed=seen.Count,
                    TestedAlphas=new[]{0,1,15,29,30,31,50,99,100},
                    ChartTypes="line,bars,quantized-lcd,dots",
                    NoRealSystemDesktopChange=true,ThemeBackgroundTransparentAtZero=true,
                    ForegroundChartIndependent=true,ContrastMinimum=4.5,Observations=seen
                });
                File.WriteAllText(Path.Combine(outputDirectory,"CHART_GLASS_PROOF.json"),json,new UTF8Encoding(false));
                Console.WriteLine("TBME_CHART_GLASS_PROOF=PASS THEMES="+ThemeCatalog.Names.Length+
                    " PAIRS="+pairCount+" BACKGROUND_ZERO_CHART_VISIBLE=TRUE");
                return 0;
            }
            catch(Exception ex)
            {
                Console.Error.WriteLine("TBME_CHART_GLASS_PROOF=FAIL "+ex);
                return 44;
            }
        }
        // Keep proof settings lifetime separate to avoid affecting global live configuration.
        private sealed class ChartProofConfigScope : IDisposable
        {
            internal readonly AppConfig Config=new AppConfig();
            public void Dispose(){}
        }
    }

    internal sealed class GlassChildWindow : Form
    {
        protected override CreateParams CreateParams
        {
            get{CreateParams p=base.CreateParams;p.ExStyle|=0x00080000;return p;}
        }
    }
    internal static class TaskbarGlassNativeProof
    {
        internal static int Run()
        {
            try
            {
                using(var parent=new Form{ShowInTaskbar=false,FormBorderStyle=FormBorderStyle.None,StartPosition=FormStartPosition.Manual,Bounds=new Rectangle(-1500,-1500,320,64)})
                using(var child=new GlassChildWindow{FormBorderStyle=FormBorderStyle.None,ShowInTaskbar=false,StartPosition=FormStartPosition.Manual,Bounds=new Rectangle(0,0,320,48),TopLevel=false})
                using(var pixels=new Bitmap(320,48,PixelFormat.Format32bppPArgb))
                {
                    child.Parent=parent;
                    IntPtr ph=parent.Handle,ch=child.Handle;
                    using(Graphics g=Graphics.FromImage(pixels))
                    {
                        g.Clear(Color.Transparent);
                        using(var brush=new SolidBrush(Color.White))g.DrawString("ULW_ALPHA native proof",SystemFonts.DefaultFont,brush,10,10);
                    }
                    int error=0;
                    bool pass=TaskbarGlassNative.Upload(ch,pixels,new Point(-1500,-1500),out error);
                    if(!pass)throw new InvalidOperationException("UpdateLayeredWindow child error="+error);
                }
                Console.WriteLine("TBME_GLASS_NATIVE_PROOF=PASS CHILD_ULW_ALPHA=TRUE");
                return 0;
            }
            catch(Exception e)
            {
                Console.Error.WriteLine("TBME_GLASS_NATIVE_PROOF=FAIL "+e);
                return 42;
            }
        }
    }
}

namespace TaskbarMonitorEnhanced
{
    internal static class TaskbarGlassLiveProof
    {
        internal static int Run(string output)
        {
            try
            {
                IntPtr taskbar=Native.FindWindow("Shell_TrayWnd",null);
                Native.RECT bounds;
                if(taskbar==IntPtr.Zero||!Native.IsWindowVisible(taskbar)||
                   !Native.GetWindowRect(taskbar,out bounds))
                    throw new InvalidOperationException("Visible primary Windows taskbar was not found.");
                Rectangle bar=bounds.ToRectangle();
                if(bar.Width<950||bar.Height<35)
                    throw new InvalidOperationException("Taskbar too small for isolated transient test.");
                int w=320,h=Math.Min(48,bar.Height);
                int x=Math.Max(10,bar.Width-w-375);
                int y=Math.Max(0,(bar.Height-h)/2);
                Rectangle footprint=new Rectangle(bar.Left+x,bar.Top+y,w,h);
                bool sampled;
                Color underneath=TaskbarGlassColor.Sample(bar,footprint,out sampled);
                var stages=new List<object>();
                using(var child=new GlassChildWindow{FormBorderStyle=FormBorderStyle.None,ShowInTaskbar=false,
                    StartPosition=FormStartPosition.Manual,Size=new Size(w,h)})
                using(var renderer=new OverlayForm(new AppConfig(),true))
                {
                    IntPtr hwnd=child.Handle;
                    long style=Native.GetWindowLongPtr(hwnd,Native.GWL_STYLE).ToInt64();
                    long ex=Native.GetWindowLongPtr(hwnd,Native.GWL_EXSTYLE).ToInt64();
                    Native.SetWindowLongPtr(hwnd,Native.GWL_STYLE,new IntPtr((style & ~Native.WS_POPUP)|Native.WS_CHILD));
                    IntPtr oldParent=Native.SetParent(hwnd,taskbar);
                    int parentWin32=Marshal.GetLastWin32Error();
                    if(Native.GetParent(hwnd)!=taskbar)throw new InvalidOperationException("Native parent mismatch err="+parentWin32+" old="+oldParent.ToInt64());
                    Native.SetWindowLongPtr(hwnd,Native.GWL_EXSTYLE,new IntPtr(ex|Native.WS_EX_LAYERED|Native.WS_EX_TOOLWINDOW|Native.WS_EX_NOACTIVATE));
                    bool positioned=Native.SetWindowPos(hwnd,Native.HWND_TOP,x,y,w,h,Native.SWP_NOACTIVATE|Native.SWP_SHOWWINDOW);
                    if(!positioned)throw new InvalidOperationException("Cannot position test child "+Marshal.GetLastWin32Error());
                    try
                    {
                        foreach(int p in new[]{0,10,29,30,100})
                        {
                            using(Bitmap pixels=renderer.RenderGlassPixelsForProof("Art Deco Gold",w,h,p,underneath))
                            {
                                int error;
                                if(!TaskbarGlassNative.Upload(hwnd,pixels,footprint.Location,out error))
                                    throw new InvalidOperationException("Shell taskbar child ULW_ALPHA rejected percent="+p+" code="+error);
                                Application.DoEvents();
                                System.Threading.Thread.Sleep(65);
                                stages.Add(new{Percent=p,NativeAccepted=true,PixelHash=Convert.ToBase64String(System.Security.Cryptography.SHA256.Create().ComputeHash(TaskbarGlassPixels.ReadPixels(pixels,PixelFormat.Format32bppPArgb)))});
                            }
                        }
                        long verified=Native.GetWindowLongPtr(hwnd,Native.GWL_EXSTYLE).ToInt64();
                        if((verified&Native.WS_EX_LAYERED)==0||Native.GetParent(hwnd)!=taskbar)
                            throw new InvalidOperationException("Layered style or taskbar parent drift");
                    }
                    finally {child.Hide();}
                }
                var receipt=new{Status="PASS",Source="R41 Native on actual Windows taskbar child",Stages=stages,
                   ActualTaskbarColorSampled=sampled,TaskbarRGB=String.Format(CultureInfo.InvariantCulture,
                     "#{0:X2}{1:X2}{2:X2}",underneath.R,underneath.G,underneath.B),
                   TextContrast=TaskbarGlassColor.Contrast(TaskbarGlassColor.ReadableText(underneath),underneath),
                   NoInstalledMutation=true,OutputScreenshotsSaved=false};
                File.WriteAllText(output,new JavaScriptSerializer().Serialize(receipt),new UTF8Encoding(false));
                Console.WriteLine("TBME_GLASS_LIVE_PROOF=PASS TASKBAR_PARENT=TRUE MODES=5 COLOR_SAMPLED="+sampled);
                return 0;
            }
            catch(Exception e)
            {
                Console.Error.WriteLine("TBME_GLASS_LIVE_PROOF=FAIL "+e);
                return 43;
            }
        }
    }
}


namespace TaskbarMonitorEnhanced
{
    // Real screen-pixel proof using the actual OverlayForm's production top-level
    // attach, safe taskbar placement and per-pixel paint path. Runs strictly in
    // proof mode with no config writes, no tray and no process replacement.
    internal static class TaskbarTopGlassVisualProof
    {
        private static void Check(bool ok,string reason)
        {if(!ok)throw new InvalidOperationException("R46 TOPGLASS "+reason);}

        private static string MainExecutableHash()
        {
            using(var sha=System.Security.Cryptography.SHA256.Create())
            using(var stream=File.OpenRead(Application.ExecutablePath))
                return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","");
        }

        private static Bitmap Capture(Rectangle r)
        {
            Bitmap b=new Bitmap(r.Width,r.Height,PixelFormat.Format24bppRgb);
            using(Graphics g=Graphics.FromImage(b))
                g.CopyFromScreen(r.Location,Point.Empty,r.Size,CopyPixelOperation.SourceCopy);
            return b;
        }

        internal static int Run(string dir)
        {
            try
            {
                if(Directory.Exists(dir))throw new InvalidOperationException("Native proof output already exists; do not overwrite.");
                Directory.CreateDirectory(dir);
                Native.EnableDpi();
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                IntPtr bar=Native.FindWindow("Shell_TrayWnd",null);
                Native.RECT taskbarBounds=new Native.RECT();
                Check(bar!=IntPtr.Zero && Native.IsWindowVisible(bar) && Native.GetWindowRect(bar,out taskbarBounds),
                    "primary taskbar must exist");
                AppConfig cfg=new AppConfig();
                cfg.Theme="Dark Minimal Pro";
                cfg.Position="Right";
                cfg.SafePlacement=true;
                cfg.Opacity=0;
                cfg.MinWidthLogicalPx=900;
                cfg.ShowSparklines=true;
                cfg.Normalize();
                Rectangle place=TaskbarLayout.GetSafeRectangle(bar,cfg,cfg.MinWidthLogicalPx);
                Check(place.Width>=700 && place.Height>=35 && place.Width<=1500,
                    "insufficient unused taskbar area "+place);
                Rectangle screen=SystemInformation.VirtualScreen;
                Check(screen.Contains(place),"test area must be on screen");
                // Fail rather than cover the existing user's v1.6 process.
                uint resident=0;
                foreach(System.Diagnostics.Process p in System.Diagnostics.Process.GetProcessesByName("TaskbarMonitorEnhanced"))
                {
                    try{if(p.Id!=System.Diagnostics.Process.GetCurrentProcess().Id)resident=(uint)p.Id;}
                    finally{p.Dispose();}
                }
                Check(resident!=0,"accepted v1.6 must remain resident");
                bool collides=false;
                Native.EnumChildWindows(bar,delegate(IntPtr h,IntPtr ignored)
                {
                    if(Native.GetParent(h)!=bar)return true;
                    uint pid=0;
                    Native.GetWindowThreadProcessId(h,out pid);
                    if(pid!=resident)return true;
                    Native.RECT rr;
                    if(Native.GetWindowRect(h,out rr) && rr.ToRectangle().IntersectsWith(place))
                        collides=true;
                    return true;
                },IntPtr.Zero);
                Check(!collides,"test must not cover resident v1.6 window");

                bool sampled=false;
                Color underlayColor=TaskbarGlassColor.Sample(taskbarBounds.ToRectangle(),place,out sampled);
                using(Bitmap before=Capture(place))
                using(var f=new OverlayForm(cfg,true))
                {
                    f.EnableNativeGlassVisualProof();
                    f.PrimeSettingsThemePreviewFromLiveMetrics(24,80);
                    f.Location=new Point(-30000,-30000);
                    f.Show();Application.DoEvents();
                    Rectangle actual=f.AttachNativeGlassVisualProof();
                    Check(actual==place,"production position differed from safe placement "+actual+" vs "+place);
                    int preNativeMetricUpdates=f.GlassDirectMetricRefreshCountForProof;
                    // Read real metrics while the layered popup is ALREADY visible.
                    // The telemetry commit itself must cause a native upload; relying
                    // on Invalidate/WM_PAINT would leave a static cold-start frame.
                    f.PrimeSettingsThemePreviewFromLiveMetrics(2,50);
                    int nativeMetricUpdates=f.GlassDirectMetricRefreshCountForProof-preNativeMetricUpdates;
                    Check(nativeMetricUpdates>=2,"metric snapshot failed to upload real layered pixels "+nativeMetricUpdates);
                    f.Invalidate();f.Update();Application.DoEvents();
                    System.Threading.Thread.Sleep(400);
                    using(Bitmap on=Capture(actual))
                    using(Bitmap expected=f.RenderGlassPixelsForProof(cfg.Theme,actual.Width,actual.Height,0,underlayColor))
                    {
                        before.Save(Path.Combine(dir,"UNDERLAY_BEFORE_R46.png"),ImageFormat.Png);
                        on.Save(Path.Combine(dir,"PRODUCTION_FORM_TOPGLASS_R46.png"),ImageFormat.Png);
                        int realInk=0,realGraphs=0,foregroundPixels=0,backgroundChanged=0,clearPixels=0;
                        for(int y=2;y<actual.Height-3;y++)
                        for(int x=3;x<actual.Width-3;x++)
                        {
                            int alpha=expected.GetPixel(x,y).A;
                            if(alpha==0)clearPixels++;
                            Color off=before.GetPixel(x,y),now=on.GetPixel(x,y);
                            int contrast=Math.Max(Math.Abs(off.R-now.R),
                                Math.Max(Math.Abs(off.G-now.G),Math.Abs(off.B-now.B)));
                            if(alpha>=210)
                            {
                                foregroundPixels++;
                                if(contrast>=45)
                                {
                                    if(y<20)realInk++;
                                    else realGraphs++;
                                }
                            }
                            else if(alpha==0 && contrast>65)backgroundChanged++;
                        }
                        bool pass=realInk>=100 && realGraphs>=100 &&
                            clearPixels>actual.Width*5 &&
                            backgroundChanged<Math.Max(200,clearPixels/5);
                        var receipt=new {
                            Status=pass?"PASS":"FAIL",
                            ParentWindow=Native.GetParent(f.Handle).ToInt64(),
                            NativeLayeredWindow=true,ActualProductionOverlayForm=true,
                            MetricNativeRefreshUploads=nativeMetricUpdates,
                            MainExecutableSHA256=MainExecutableHash(),
                            BackgroundOpacityPercent=0,Theme=cfg.Theme,
                            ScreenshotArea=actual.ToString(),ExpectedForegroundPixels=foregroundPixels,
                            RealTextChangedPixels=realInk,RealChartChangedPixels=realGraphs,
                            ActualTransparentBackgroundPixels=clearPixels,
                            ClearAreaChangedPixels=backgroundChanged,
                            ContrastSampledFromTaskbar=sampled,
                            ResidentInstalledV16ProcessId=resident,
                            NoResidentAppTerminated=true,NoSettingsSaved=true,
                            NoSlideshowTouched=true,TemporaryVisualOnly=true,
                            GitSourceCandidate="R46",ActualScreenshotSaved=true,
                            TimeUtc=DateTime.UtcNow.ToString("o",CultureInfo.InvariantCulture)
                        };
                        File.WriteAllText(Path.Combine(dir,"TOPGLASS_REAL_VISUAL_PROOF.json"),
                            new JavaScriptSerializer().Serialize(receipt),new UTF8Encoding(false));
                        Check(pass,"real taskbar screen delta insufficient glyph="+realInk+
                            " graph="+realGraphs+" background="+backgroundChanged);
                    }
                    // Exercise actual GDI+ window transitions (0 -> 30 -> 97 -> 100 -> 0)
                    // using the very same proof-mode OverlayForm; user config is never saved.
                    var transitions=new List<object>();
                    foreach(double percent in new[]{.30,.97,1.0,0.0})
                    {
                        bool switchOk=f.SwitchNativeGlassForProof(percent);
                        transitions.Add(new {OpacityPercent=(int)Math.Round(percent*100),WindowMode=
                            percent<1?"TOPLEVEL_PARG_B":"TASKBAR_CHILD_OPAQUE",Pass=switchOk});
                        Check(switchOk,"form mode transition failed alpha="+percent);
                        Application.DoEvents();
                        System.Threading.Thread.Sleep(120);
                    }
                    Check(f.AttachNativeGlassVisualProof()==place,"post-transition native geometry drift");
                    Application.DoEvents();
                    System.Threading.Thread.Sleep(270);
                    using(Bitmap post=Capture(place))
                    using(Bitmap expectedPost=f.RenderGlassPixelsForProof(cfg.Theme,place.Width,place.Height,0,underlayColor))
                    {
                        post.Save(Path.Combine(dir,"TOPGLASS_AFTER_100_TO_ZERO_R46.png"),ImageFormat.Png);
                        int postGlyph=0,postChart=0;
                        for(int yy=2;yy<post.Height-3;yy++)
                        for(int xx=3;xx<post.Width-3;xx++)
                        {
                            if(expectedPost.GetPixel(xx,yy).A<210)continue;
                            Color old=before.GetPixel(xx,yy),cur=post.GetPixel(xx,yy);
                            int delta=Math.Max(Math.Abs(old.R-cur.R),
                                Math.Max(Math.Abs(old.G-cur.G),Math.Abs(old.B-cur.B)));
                            if(delta>=45)
                            {
                                if(yy<20)postGlyph++;
                                else postChart++;
                            }
                        }
                        bool good=postGlyph>=100 && postChart>=100;
                        var receipt=new{
                            Status=good?"PASS":"FAIL",TotalTransitions=transitions.Count,
                            Stages=transitions,RestoredZeroAlphaGlyphPixels=postGlyph,
                            RestoredZeroAlphaChartPixels=postChart,
                            ActualProductionOverlayForm=true,NoInstalledMutation=true,
                            MainExecutableSHA256=MainExecutableHash(),
                            RealScreenCompositorVerified=true};
                        File.WriteAllText(Path.Combine(dir,"TOPGLASS_MODE_TRANSITIONS.json"),
                            new JavaScriptSerializer().Serialize(receipt),new UTF8Encoding(false));
                        Check(good,"0-30-97-100-0 real taskbar mode transitions lost glyph or graph");
                    }
                    f.Hide();Application.DoEvents();
                }
                Console.WriteLine("TBME_TOPGLASS_LIVE_PROOF=PASS REAL_PRODUCTION_FORM=TRUE CHAR_AND_GRAPH=VISIBLE");
                return 0;
            }
            catch(Exception e)
            {
                try
                {
                    Directory.CreateDirectory(dir);
                    File.WriteAllText(Path.Combine(dir,"TOPGLASS_FAILURE.txt"),e.ToString(),new UTF8Encoding(false));
                }
                catch {}
                Console.Error.WriteLine("TBME_TOPGLASS_LIVE_PROOF=FAIL "+e);
                return 46;
            }
        }
    }
}


namespace TaskbarMonitorEnhanced
{
    // Isolated R53 diagnostic — never launched in the resident app.
    // Tests whether reasserting HWND_TOPMOST (no focus) during Windows 11
    // Start/Search can defeat the higher-shell compositor band. Records
    // actual pixels in a small taskbar-only rectangle, no user config writes.
    internal static class TaskbarStartZOrderProof
    {
        private static Bitmap Capture(Rectangle rectangle)
        {
            Bitmap b=new Bitmap(rectangle.Width,rectangle.Height,PixelFormat.Format24bppRgb);
            using(Graphics drawing=Graphics.FromImage(b))
                drawing.CopyFromScreen(rectangle.Location,Point.Empty,rectangle.Size,CopyPixelOperation.SourceCopy);
            return b;
        }

        private sealed class InkResult { public int Glyph;public int Chart;public int RawSignal;public int ExpectedMaskPixels;public bool VisibleInk; }
        private static InkResult Ink(Bitmap underlay,Bitmap visible,Bitmap expected)
        {
            int glyph=0,chart=0,rawLight=0,maskPixels=0;
            for(int y=2;y<visible.Height-2;y++)
            for(int x=3;x<visible.Width-3;x++)
            {
                Color shown=visible.GetPixel(x,y);
                int high=Math.Max(shown.R,Math.Max(shown.G,shown.B));
                int low=Math.Min(shown.R,Math.Min(shown.G,shown.B));
                if(high>=140||(high-low>=25&&high>=70))rawLight++;
                if(expected.GetPixel(x,y).A<210)continue;
                maskPixels++;
                Color previous=underlay.GetPixel(x,y);
                int diff=Math.Max(Math.Abs((int)shown.R-(int)previous.R),
                    Math.Max(Math.Abs((int)shown.G-(int)previous.G),
                             Math.Abs((int)shown.B-(int)previous.B)));
                if(diff>=45)
                {
                    if(y<20)glyph++;
                    else chart++;
                }
            }
            return new InkResult{Glyph= glyph,Chart=chart,RawSignal=rawLight,ExpectedMaskPixels=maskPixels,
                        VisibleInk=(glyph>=100&&chart>=100)};
        }

        private static void Require(bool truth,string why)
        {if(!truth)throw new InvalidOperationException("R53_START_COMPOSITOR "+why);}

        private static string SHA()
        {
            using(var sha=System.Security.Cryptography.SHA256.Create())
            using(var file=File.OpenRead(Application.ExecutablePath))
                return BitConverter.ToString(sha.ComputeHash(file)).Replace("-","");
        }

        internal static int Run(string folder)
        {
            bool sentWin=false;
            try
            {
                if(Directory.Exists(folder))
                    throw new InvalidOperationException("Output already exists; no overwrite.");
                Directory.CreateDirectory(folder);
                Native.EnableDpi();
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                IntPtr taskbar=Native.FindWindow("Shell_TrayWnd",null);
                Native.RECT raw=new Native.RECT();
                Require(taskbar!=IntPtr.Zero&&Native.IsWindowVisible(taskbar)&&
                    Native.GetWindowRect(taskbar,out raw),"Taskbar unavailable");
                Rectangle taskbarArea=raw.ToRectangle();
                AppConfig c=new AppConfig();
                c.Theme="Dark Minimal Pro";
                c.Position="Right"; // Do not cover resident v1.6 Left-side app.
                c.SafePlacement=true;
                c.MinWidthLogicalPx=900;
                c.Opacity=0;
                c.ShowSparklines=true;
                c.Normalize();
                Rectangle location=TaskbarLayout.GetSafeRectangle(taskbar,c,c.MinWidthLogicalPx);
                Require(location.Width>=700&&location.Height>=35&&location.Width<=1500&&
                    taskbarArea.Contains(location),"Safe gap unavailable");
                uint resident=0;
                foreach(System.Diagnostics.Process app in System.Diagnostics.Process.GetProcessesByName("TaskbarMonitorEnhanced"))
                {
                    try{if(app.Id!=System.Diagnostics.Process.GetCurrentProcess().Id)
                        resident=(uint)app.Id;}
                    finally{app.Dispose();}
                }
                Require(resident!=0,"Installed original v1.6 not running");
                bool collision=false;
                Native.EnumChildWindows(taskbar,delegate(IntPtr h,IntPtr p)
                {
                    if(Native.GetParent(h)!=taskbar)return true;
                    uint pid=0;Native.GetWindowThreadProcessId(h,out pid);
                    if(pid!=resident)return true;
                    Native.RECT bounds=new Native.RECT();
                    if(Native.GetWindowRect(h,out bounds)&&
                        bounds.ToRectangle().IntersectsWith(location))collision=true;
                    return true;
                },IntPtr.Zero);
                Require(!collision,"Proof overlaps installed original app");
                bool colorOk=false;
                Color backdrop=TaskbarGlassColor.Sample(taskbarArea,location,out colorOk);
                // Experimental alternate location is the desktop strip just ABOVE
                // taskbar, not the resident user's original taskbar gap.
                Rectangle upper=new Rectangle(taskbarArea.Left,location.Y-60,location.Width,location.Height);
                Require(SystemInformation.VirtualScreen.Contains(upper),"Upper proof strip off screen");
                using(Bitmap untouched=Capture(location))
                using(Bitmap upperUnderlay=Capture(upper))
                using(var f=new OverlayForm(c,true))
                {
                    f.EnableNativeGlassVisualProof();
                    f.PrimeSettingsThemePreviewFromLiveMetrics(22,80);
                    f.Location=new Point(-30000,-30000);
                    f.Show();Application.DoEvents();
                    Require(f.AttachNativeGlassVisualProof()==location,"Production proof mode not native popup");
                    f.PrimeSettingsThemePreviewFromLiveMetrics(3,60);
                    Require(f.GlassDirectMetricRefreshCountForProof>=3,"No live native redraw");
                    using(Bitmap mask=f.RenderGlassPixelsForProof(c.Theme,location.Width,location.Height,0,backdrop))
                    {
                        using(Bitmap baseline=Capture(location))
                        {
                            var preInk=Ink(untouched,baseline,mask);
                            baseline.Save(Path.Combine(folder,"BASELINE_VISIBLE_TASKBAR_R53.png"),ImageFormat.Png);
                            Require(preInk.VisibleInk,
                                "Real alpha-zero glyph and graph not visible before Start");
                        }
                        // Start/Search keyboard event matches production strict StartProbe.
                        Native.KeybdTap(0x1B);
                        System.Threading.Thread.Sleep(120);
                        Native.KeybdTap(0x5B);
                        sentWin=true;
                        string shellName="",shellClass="";
                        IntPtr shellHwnd=IntPtr.Zero;
                        bool opened=ShellUi.WaitForStartShell(2100,out shellName,out shellClass,out shellHwnd);
                        if(!opened)
                        {
                            Native.CtrlEsc();
                            opened=ShellUi.WaitForStartShell(2100,out shellName,out shellClass,out shellHwnd);
                        }
                        Require(opened,"Windows Start/Search shell not observed");
                        List<object> samples=new List<object>();
                        int[] signalByPhase=new int[4],visualByPhase=new int[4];
                        string[] phases=new string[]{"UNMODIFIED","REASSERT_TOPMOST",
                            "DEMOTE_THEN_REASSERT_NOACTIVATE","TEMPORARY_ABOVE_LEFT_TASKBAR_DIAGNOSTIC"};
                        for(int i=0;i<24;i++)
                        {
                            int phase=i/6;
                            bool raiseOk=true,uploaded=true;
                            if(phase==1)
                                raiseOk=Native.SetWindowPos(f.Handle,Native.HWND_TOPMOST,0,0,0,0,
                                  Native.SWP_NOSIZE|Native.SWP_NOMOVE|Native.SWP_NOACTIVATE|Native.SWP_SHOWWINDOW);
                            else if(phase>=2)
                            {
                                bool down=Native.SetWindowPos(f.Handle,new IntPtr(-2),0,0,0,0,
                                    Native.SWP_NOSIZE|Native.SWP_NOMOVE|Native.SWP_NOACTIVATE);
                                bool up=Native.SetWindowPos(f.Handle,Native.HWND_TOPMOST,0,0,0,0,
                                    Native.SWP_NOSIZE|Native.SWP_NOMOVE|Native.SWP_NOACTIVATE|Native.SWP_SHOWWINDOW);
                                raiseOk=down&&up;
                            }
                            if(phase==3)
                            {
                                // Temporary 60-pixel vertical move, within screen
                                // work area, while SearchHost shell is active.
                                raiseOk=Native.SetWindowPos(f.Handle,Native.HWND_TOPMOST,
                                    upper.X,upper.Y,upper.Width,upper.Height,
                                    Native.SWP_NOACTIVATE|Native.SWP_SHOWWINDOW);
                                uploaded=f.PaintGlassForNativeProof();
                            }
                            Application.DoEvents();
                            System.Threading.Thread.Sleep(180);
                            bool shellForeground;
                            string fgProcess="",fgClass="";IntPtr fg=IntPtr.Zero;
                            shellForeground=ShellUi.IsStartShellForeground(out fgProcess,out fgClass,out fg);
                            Rectangle locationToCapture=phase==3?upper:location;
                            using(Bitmap on=Capture(locationToCapture))
                            {
                                InkResult ink=Ink(phase==3?upperUnderlay:untouched,on,mask);
                                int rawSignal=(int)ink.RawSignal;
                                bool visible=(bool)ink.VisibleInk;
                                if(rawSignal>=300)signalByPhase[phase]++;
                                if(visible)visualByPhase[phase]++;
                                if(i==0||i==5||i==11||i==17||i==23)
                                   on.Save(Path.Combine(folder,"START_PHASE_"+phases[phase]+"_"+i+".png"),ImageFormat.Png);
                                Native.RECT rect=new Native.RECT();
                                Native.GetWindowRect(f.Handle,out rect);
                                long st=Native.GetWindowLongPtr(f.Handle,Native.GWL_STYLE).ToInt64();
                                long ex=Native.GetWindowLongPtr(f.Handle,Native.GWL_EXSTYLE).ToInt64();
                                samples.Add(new {Index=i+1,Phase=phases[phase],Ink=ink,
                                   ShellForeground=shellForeground,ForegroundProcess=fgProcess,
                                   RaiseOk=raiseOk,UploadOk=uploaded,WinVisible=Native.IsWindowVisible(f.Handle),
                                   Cloaked=Native.GetCloaked(f.Handle),NoChild=(st&Native.WS_CHILD)==0,
                                   NativeLayered=(ex&Native.WS_EX_LAYERED)!=0,
                                   NativeTopMost=(ex&Native.WS_EX_TOPMOST)!=0,
                                   Position=new int[]{rect.Left,rect.Top,rect.Right-rect.Left,rect.Bottom-rect.Top}});
                            }
                        }
                        Native.KeybdTap(0x1B);
                        sentWin=false;
                        Native.SetWindowPos(f.Handle,Native.HWND_TOPMOST,
                            location.X,location.Y,location.Width,location.Height,
                            Native.SWP_NOACTIVATE|Native.SWP_SHOWWINDOW);
                        f.PaintGlassForNativeProof();
                        System.Threading.Thread.Sleep(500);
                        Application.DoEvents();
                        bool stillShell=false;
                        string postProcess="",postClass="";IntPtr postHwnd=IntPtr.Zero;
                        stillShell=ShellUi.IsStartShellForeground(out postProcess,out postClass,out postHwnd);
                        if(stillShell)
                        {
                            Native.KeybdTap(0x1B); // second Escape if Start/Search stole focus
                            System.Threading.Thread.Sleep(650);
                        }
                        f.PaintGlassForNativeProof();
                        using(Bitmap closed=Capture(location))
                        {
                            closed.Save(Path.Combine(folder,"AFTER_START_CLOSED_R53.png"),ImageFormat.Png);
                        }
                        System.Threading.Thread.Sleep(1700);
                        Application.DoEvents();
                        f.PaintGlassForNativeProof();
                        int recoveredText=0,recoveredChart=0;
                        using(Bitmap later=Capture(location))
                        {
                            later.Save(Path.Combine(folder,"AFTER_START_CLOSED_DELAYED_R53.png"),ImageFormat.Png);
                            InkResult regained=Ink(untouched,later,mask);
                            recoveredText=regained.Glyph;recoveredChart=regained.Chart;
                        }
                        // A true new HWND can enter a different DWM z-band
                        // after SearchHost relinquishes foreground. Test that
                        // independently from merely calling SetWindowPos/ULW.
                        int hideShowGlyph=0,hideShowChart=0;
                        int recreatedSameFormGlyph=0,recreatedSameFormChart=0;
                        bool recreatedSameFormHwnd=false;
                        int newHwndGlyph=0,newHwndChart=0;
                        // Compare simple WinForms Hide/Show against actual
                        // RecreateHandle, before allocating a wholly new form.
                        f.Hide();Application.DoEvents();
                        f.Show();Application.DoEvents();
                        f.PaintGlassForNativeProof();
                        System.Threading.Thread.Sleep(340);
                        using(Bitmap toggled=Capture(location))
                        {
                            InkResult toggle=Ink(untouched,toggled,mask);
                            hideShowGlyph=toggle.Glyph;hideShowChart=toggle.Chart;
                            toggled.Save(Path.Combine(folder,"AFTER_START_HIDE_SHOW_SAME_HWND_R53.png"),ImageFormat.Png);
                        }
                        recreatedSameFormHwnd=f.RecreateNativeGlassHandleForProof();
                        System.Threading.Thread.Sleep(340);
                        using(Bitmap rebuilt=Capture(location))
                        {
                            InkResult same=Ink(untouched,rebuilt,mask);
                            recreatedSameFormGlyph=same.Glyph;
                            recreatedSameFormChart=same.Chart;
                            rebuilt.Save(Path.Combine(folder,"AFTER_START_RECREATE_SAME_FORM_R53.png"),ImageFormat.Png);
                        }
                        f.Hide();Application.DoEvents();
                        using(var recreated=new OverlayForm(c,true))
                        {
                            recreated.EnableNativeGlassVisualProof();
                            recreated.PrimeSettingsThemePreviewFromLiveMetrics(22,80);
                            recreated.Location=new Point(-30000,-30000);
                            recreated.Show();Application.DoEvents();
                            Require(recreated.AttachNativeGlassVisualProof()==location,
                                "New HWND did not reattach to same safe taskbar gap");
                            recreated.PrimeSettingsThemePreviewFromLiveMetrics(2,50);
                            System.Threading.Thread.Sleep(420);
                            Application.DoEvents();
                            using(Bitmap actualNew=Capture(location))
                            using(Bitmap maskNew=recreated.RenderGlassPixelsForProof(
                                c.Theme,location.Width,location.Height,0,backdrop))
                            {
                                InkResult fresh=Ink(untouched,actualNew,maskNew);
                                newHwndGlyph=fresh.Glyph;newHwndChart=fresh.Chart;
                                actualNew.Save(Path.Combine(folder,"AFTER_START_NEW_HWND_R53.png"),ImageFormat.Png);
                            }
                            recreated.Hide();Application.DoEvents();
                        }
                        var receipt=new {
                            Status="DIAGNOSTIC_COMPLETED_NOT_PRODUCTION_ACCEPTANCE",
                            MainSHA256=SHA(),ActualProductionOverlayForm=true,
                            NativeSamples=24,OriginalInstalledVersion="1.6.0",
                            OtherAppTerminated=false,UserConfigChanged=false,
                            SlideshowChanged=false,ProtectedSensorsChanged=false,
                            Origin=new int[]{location.X,location.Y,location.Width,location.Height},
                            StartShellProcess=shellName,StartShellClass=shellClass,
                            Phase4UpperPosition=new int[]{upper.X,upper.Y,upper.Width,upper.Height},
                            ShellStillForegroundAfterOneEscape=stillShell,
                            NativeGlyphRecoveredAfterStart=recoveredText,
                            NativeChartRecoveredAfterStart=recoveredChart,
                            HideShowGlyphAfterStart=hideShowGlyph,
                            HideShowChartAfterStart=hideShowChart,
                            RecreateSameFormHwndSucceeded=recreatedSameFormHwnd,
                            RecreateSameFormGlyphAfterStart=recreatedSameFormGlyph,
                            RecreateSameFormChartAfterStart=recreatedSameFormChart,
                            BrandNewHwndGlyphAfterStart=newHwndGlyph,
                            BrandNewHwndChartAfterStart=newHwndChart,
                            PhaseNames=phases,
                            VisibleInkSamples=visualByPhase,
                            RawSignalSamples=signalByPhase,
                            WindowsStartObserved=opened,FullSampleEvidence=samples,
                            Interpretation="Actual taskbar bitmap vs unmodified pixels; PNG strips only",
                            CaptureUtc=DateTime.UtcNow.ToString("o",CultureInfo.InvariantCulture)};
                        File.WriteAllText(Path.Combine(folder,"START_ZORDER_PROOF_R53.json"),
                            new JavaScriptSerializer().Serialize(receipt),new UTF8Encoding(false));
                        Console.WriteLine("TBME_START_ZORDER_DIAGNOSTIC=COMPLETE SAMPLES=24 "+
                            "RAW="+String.Join(",",rawSignalArray(signalByPhase))+
                            " VISIBLE="+String.Join(",",rawSignalArray(visualByPhase)));
                    }
                    f.Hide();Application.DoEvents();
                }
                return 0;
            }
            catch(Exception e)
            {
                try{
                    Directory.CreateDirectory(folder);
                    File.WriteAllText(Path.Combine(folder,"START_ZORDER_FAILURE_R53.txt"),e.ToString(),
                        new UTF8Encoding(false));}catch{}
                Console.Error.WriteLine("TBME_START_ZORDER_DIAGNOSTIC=FAIL "+e);
                return 53;
            }
            finally
            {
                if(sentWin)try{Native.KeybdTap(0x1B);}catch{}
            }
        }

        private static string[] rawSignalArray(int[] items)
        {return Array.ConvertAll(items,n=>n.ToString(CultureInfo.InvariantCulture));}
    }
}


namespace TaskbarMonitorEnhanced
{
    // Actual production StartGuardTick policy with a disposable native OverlayForm.
    // No installation, telemetry upload, screen capture beyond the 900x48 gap,
    // sensor reconfiguration, wallpaper action or persistent foreground focus.
    internal static class TaskbarProductionStartFloatProof
    {
        private static void Require(bool ok,string detail)
        {if(!ok)throw new InvalidOperationException("R54_START_FLOAT "+detail);}

        private static Bitmap Capture(Rectangle r)
        {
            Bitmap b=new Bitmap(r.Width,r.Height,PixelFormat.Format24bppRgb);
            using(Graphics g=Graphics.FromImage(b))
                g.CopyFromScreen(r.Location,Point.Empty,r.Size,CopyPixelOperation.SourceCopy);
            return b;
        }

        private static int[] RealInk(Bitmap before,Bitmap current,Bitmap mask)
        {
            int text=0,chart=0,opaque=0;
            for(int y=2;y<current.Height-3;y++)
            for(int x=3;x<current.Width-3;x++)
            {
                if(mask.GetPixel(x,y).A<210)continue;
                opaque++;
                Color old=before.GetPixel(x,y),now=current.GetPixel(x,y);
                int delta=Math.Max(Math.Abs((int)old.R-now.R),
                    Math.Max(Math.Abs((int)old.G-now.G),Math.Abs((int)old.B-now.B)));
                if(delta<45)continue;
                if(y<20)text++;
                else chart++;
            }
            return new int[]{text,chart,opaque};
        }

        private static string CurrentMainSHA()
        {
            using(var sha=System.Security.Cryptography.SHA256.Create())
            using(var f=File.OpenRead(Application.ExecutablePath))
                return BitConverter.ToString(sha.ComputeHash(f)).Replace("-","");
        }

        internal static int Run(string path)
        {
            bool sentWin=false;
            try
            {
                if(Directory.Exists(path))
                    throw new InvalidOperationException("Native proof directory exists; never overwrite");
                Directory.CreateDirectory(path);
                Native.EnableDpi();
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                IntPtr bar=Native.FindWindow("Shell_TrayWnd",null);
                Native.RECT tb=new Native.RECT();
                Require(bar!=IntPtr.Zero&&Native.GetWindowRect(bar,out tb)&&Native.IsWindowVisible(bar),
                    "Real primary taskbar unavailable");
                Rectangle taskbar=tb.ToRectangle();
                AppConfig c=new AppConfig();
                c.Theme="Dark Minimal Pro";c.Position="Right";
                c.SafePlacement=true;c.Opacity=0;c.ShowSparklines=true;
                c.MinWidthLogicalPx=900;c.Normalize();
                Rectangle gap=TaskbarLayout.GetSafeRectangle(bar,c,c.MinWidthLogicalPx);
                Rectangle upper=new Rectangle(gap.X,gap.Y-gap.Height-12,gap.Width,gap.Height);
                Require(gap.Width>=700&&gap.Height>=30&&gap.Width<=1500&&
                    taskbar.Contains(gap)&&SystemInformation.VirtualScreen.Contains(upper),
                    "Safe nonintrusive taskbar gap not available");
                uint resident=0;
                foreach(System.Diagnostics.Process p in System.Diagnostics.Process.GetProcessesByName("TaskbarMonitorEnhanced"))
                {
                    try{if(p.Id!=System.Diagnostics.Process.GetCurrentProcess().Id)resident=(uint)p.Id;}
                    finally{p.Dispose();}
                }
                Require(resident>0,"Accepted installed v1.6 must be resident");
                bool collide=false;
                Native.EnumChildWindows(bar,delegate(IntPtr h,IntPtr ignore)
                {
                    if(Native.GetParent(h)!=bar)return true;
                    uint pid=0;Native.GetWindowThreadProcessId(h,out pid);
                    if(pid!=resident)return true;
                    Native.RECT native=new Native.RECT();
                    if(Native.GetWindowRect(h,out native)&&native.ToRectangle().IntersectsWith(gap))
                        collide=true;
                    return true;
                },IntPtr.Zero);
                Require(!collide,"Proof would cover installed v1.6");
                bool sampled=false;
                Color bgcolor=TaskbarGlassColor.Sample(taskbar,gap,out sampled);
                using(Bitmap uncovered=Capture(gap))
                using(Bitmap uncoveredUpper=Capture(upper))
                using(var f=new OverlayForm(c,true))
                {
                    f.EnableNativeGlassVisualProof();
                    f.PrimeSettingsThemePreviewFromLiveMetrics(24,80);
                    f.Location=new Point(-30000,-30000);
                    f.Show();Application.DoEvents();
                    Require(f.AttachNativeGlassVisualProof()==gap,
                        "Actual production OverlayForm failed initial true-alpha attach");
                    f.PrimeSettingsThemePreviewFromLiveMetrics(2,40);
                    int[] baseline;
                    using(Bitmap bm=Capture(gap))
                    using(Bitmap inkMask=f.RenderGlassPixelsForProof(c.Theme,gap.Width,gap.Height,0,bgcolor))
                    {
                        bm.Save(Path.Combine(path,"R54_BASELINE_TASKBAR.png"),ImageFormat.Png);
                        baseline=RealInk(uncovered,bm,inkMask);
                        Require(baseline[0]>=100&&baseline[1]>=100,
                            "Actual text/graph not visible before Start");
                    }
                    Native.KeybdTap(0x1B);
                    System.Threading.Thread.Sleep(120);
                    Native.KeybdTap(0x5B);sentWin=true;
                    string shellProcess="",shellClass="";IntPtr shellHwnd=IntPtr.Zero;
                    bool observed=ShellUi.WaitForStartShell(2000,out shellProcess,out shellClass,out shellHwnd);
                    if(!observed)
                    {
                        Native.CtrlEsc();
                        observed=ShellUi.WaitForStartShell(1800,out shellProcess,out shellClass,out shellHwnd);
                    }
                    Require(observed,"Start/Search OS shell not observed");
                    List<object> frames=new List<object>();
                    int floatingCount=0,visibleCount=0,shellCount=0,safeCount=0;
                    for(int i=0;i<24;i++)
                    {
                        f.StartGlassGuardTickForProof();
                        Application.DoEvents();
                        System.Threading.Thread.Sleep(220);
                        bool raised=f.StartGlassFloatingForProof;
                        Rectangle actual=raised?f.StartGlassLiftedBoundsForProof:gap;
                        Native.RECT current=new Native.RECT();
                        Native.GetWindowRect(f.Handle,out current);
                        bool safe=(raised&&actual==upper&&current.ToRectangle()==upper);
                        if(safe)safeCount++;
                        if(raised)floatingCount++;
                        string proc="",klass="";IntPtr fg=IntPtr.Zero;
                        bool shellActive=ShellUi.IsStartShellForeground(out proc,out klass,out fg);
                        if(shellActive)shellCount++;
                        using(Bitmap frame=Capture(actual))
                        using(Bitmap mask=f.RenderGlassPixelsForProof(c.Theme,actual.Width,actual.Height,0,bgcolor))
                        {
                            int[] inks=RealInk(raised?uncoveredUpper:uncovered,frame,mask);
                            bool visible=inks[0]>=100&&inks[1]>=100;
                            if(visible)visibleCount++;
                            if(i==0||i==3||i==19||i==23)
                                frame.Save(Path.Combine(path,"R54_START_SAMPLE_"+i+".png"),ImageFormat.Png);
                            frames.Add(new {
                                Sample=i+1,ShellForeground=shellActive,ShellProcess=proc,
                                StartFloating=raised,SafeRectangle=safe,
                                VisibleText=inks[0],VisibleGraph=inks[1],Visible=visible,
                                NativeUploadCount=f.GlassDirectMetricRefreshCountForProof,
                                Hwnd=f.Handle.ToInt64(),HwndVisible=Native.IsWindowVisible(f.Handle),
                                Cloaked=Native.GetCloaked(f.Handle),
                                ActualRect=new int[]{current.Left,current.Top,current.Right-current.Left,current.Bottom-current.Top}
                            });
                        }
                    }
                    Native.KeybdTap(0x1B);sentWin=false;
                    System.Threading.Thread.Sleep(320);
                    Application.DoEvents();
                    for(int attempt=0;attempt<8&&f.StartGlassFloatingForProof;attempt++)
                    {
                        f.StartGlassGuardTickForProof();
                        System.Threading.Thread.Sleep(220);
                        Application.DoEvents();
                    }
                    bool returned=!f.StartGlassFloatingForProof &&
                        f.StartGlassReturnTransitionsForProof>=1;
                    Native.RECT after=new Native.RECT();
                    Native.GetWindowRect(f.Handle,out after);
                    returned=returned&&after.ToRectangle()==gap;
                    System.Threading.Thread.Sleep(280);
                    int[] inkAfter;
                    using(Bitmap now=Capture(gap))
                    using(Bitmap mask=f.RenderGlassPixelsForProof(c.Theme,gap.Width,gap.Height,0,bgcolor))
                    {
                        inkAfter=RealInk(uncovered,now,mask);
                        now.Save(Path.Combine(path,"R54_RETURN_TO_TASKBAR.png"),ImageFormat.Png);
                    }
                    bool pass=observed&&shellCount>=18&&floatingCount==24&&
                        safeCount==24&&visibleCount==24&&returned&&
                        inkAfter[0]>=100&&inkAfter[1]>=100;
                    var receipt=new {
                        Status=pass?"PASS":"FAIL",
                        ActualProductionOverlayForm=true,
                        MainExecutableSHA256=CurrentMainSHA(),
                        NativeStartSamples=24,ShellSamples=shellCount,
                        LiftedSamples=floatingCount,SafeLiftedBoundsSamples=safeCount,
                        VisibleInkSamples=visibleCount,RequiredVisibleInkSamples=24,
                        StartLiftCount=f.StartGlassLiftTransitionsForProof,
                        StartReturnCount=f.StartGlassReturnTransitionsForProof,
                        OriginalTaskbarLocation=new int[]{gap.X,gap.Y,gap.Width,gap.Height},
                        TemporaryAboveLocation=new int[]{upper.X,upper.Y,upper.Width,upper.Height},
                        BeforeStartGlyphs=baseline[0],BeforeStartCharts=baseline[1],
                        AfterStartReturnGlyphs=inkAfter[0],AfterStartReturnCharts=inkAfter[1],
                        ReturnedExactNativeRect=returned,OriginalResidentPid=resident,
                        NoUserConfigSave=true,NoWindowsSlideshowChange=true,
                        NoInstalledExeReplacement=true,
                        NoProtectionChange=true,Frames=frames,
                        Utc=DateTime.UtcNow.ToString("o",CultureInfo.InvariantCulture)
                    };
                    File.WriteAllText(Path.Combine(path,"R54_PRODUCTION_START_FLOAT_PROOF.json"),
                        new JavaScriptSerializer().Serialize(receipt),new UTF8Encoding(false));
                    f.Hide();Application.DoEvents();
                    Console.WriteLine("TBME_R54_PRODUCTION_START_FLOAT="+(pass?"PASS":"FAIL")+
                        " FLOAT_VISIBLE="+visibleCount+"/24 RETURN_TEXT="+inkAfter[0]+
                        " RETURN_GRAPH="+inkAfter[1]);
                    return pass?0:54;
                }
            }
            catch(Exception ex)
            {
                try{Directory.CreateDirectory(path);
                    File.WriteAllText(Path.Combine(path,"R54_START_FLOAT_ERROR.txt"),
                        ex.ToString(),new UTF8Encoding(false));}catch{}
                Console.Error.WriteLine("TBME_R54_PRODUCTION_START_FLOAT=FAIL "+ex);
                return 54;
            }
            finally{if(sentWin)try{Native.KeybdTap(0x1B);}catch{}}
        }
    }
}


namespace TaskbarMonitorEnhanced
{
    internal enum TaskbarPresentationState { Visible, Missing, Hidden, AutoHidden, Fullscreen }
    internal static class TaskbarPresentationPolicy
    {
        internal static bool CoversMonitor(Rectangle window,Rectangle monitor)
        {
            return monitor.Width>0 && monitor.Height>0 && window.Width>0 && window.Height>0 &&
                window.Left<=monitor.Left+1 && window.Top<=monitor.Top+1 &&
                window.Right>=monitor.Right-1 && window.Bottom>=monitor.Bottom-1;
        }
        internal static TaskbarPresentationState Decide(bool exists,bool visible,bool cloaked,
            Rectangle bar,Rectangle monitor,bool fullscreen,bool revealed)
        {
            if(!exists)return TaskbarPresentationState.Missing;
            if(!visible||cloaked)return TaskbarPresentationState.Hidden;
            Rectangle intersection=Rectangle.Intersect(bar,monitor);
            bool horizontal=bar.Width>=bar.Height;
            int thickness=horizontal?intersection.Height:intersection.Width;
            int original=horizontal?bar.Height:bar.Width;
            // Auto-hide leaves a 1-2px activation edge; that is not a visible taskbar.
            if(original<=0||intersection.Width<=0||intersection.Height<=0||
                thickness<Math.Min(12,Math.Max(3,original/2)))
                return TaskbarPresentationState.AutoHidden;
            if(fullscreen&&!revealed)return TaskbarPresentationState.Fullscreen;
            return TaskbarPresentationState.Visible;
        }
    }
    internal static class TaskbarPresentationNative
    {
        [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr h,uint command);
        [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr h,uint flags);
        [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr h);
        [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr h,int attr,out int value,int size);
        internal static bool Cloaked(IntPtr h)
        {
            try{int c;return h!=IntPtr.Zero && DwmGetWindowAttribute(h,14,out c,4)==0 && c!=0;}
            catch(DllNotFoundException){return false;}catch(EntryPointNotFoundException){return false;}
        }
        internal static bool Above(IntPtr upper,IntPtr lower)
        {
            if(upper==IntPtr.Zero||lower==IntPtr.Zero||upper==lower)return false;
            IntPtr h=GetWindow(lower,3); // GW_HWNDPREV, higher in this desktop's z-order.
            for(int i=0;i<512 && h!=IntPtr.Zero;i++,h=GetWindow(h,3))
                if(h==upper)return true;
            return false;
        }
        internal static bool Fullscreen(IntPtr foreground,IntPtr overlay,Rectangle monitor,bool shell)
        {
            if(shell||foreground==IntPtr.Zero||foreground==overlay||IsIconic(foreground)||Cloaked(foreground))return false;
            uint fp=0,op=0;Native.GetWindowThreadProcessId(foreground,out fp);Native.GetWindowThreadProcessId(overlay,out op);
            if(fp!=0&&fp==op)return false; // Own Settings/workspace is never a game/video fullscreen signal.
            var name=new StringBuilder(128);Native.GetClassName(foreground,name,name.Capacity);
            string cls=name.ToString();
            if(cls=="Progman"||cls=="WorkerW"||cls=="Shell_TrayWnd"||cls=="Shell_SecondaryTrayWnd")return false;
            Native.RECT r;
            return Native.IsWindowVisible(foreground)&&Native.GetWindowRect(foreground,out r)&&
                TaskbarPresentationPolicy.CoversMonitor(r.ToRectangle(),monitor);
        }
        internal static bool TaskbarRevealed(IntPtr taskbar,Rectangle bar,Rectangle overlay,IntPtr foreground)
        {
            // IsWindowVisible alone stays true for a taskbar covered by a fullscreen app.
            // Test real hit targets OUTSIDE our own monitor, without capturing any pixels.
            bool horizontal=bar.Width>=bar.Height;
            for(int i=1;i<=9;i++)
            {
                Point p=horizontal?new Point(bar.Left+bar.Width*i/10,bar.Top+bar.Height/2):
                    new Point(bar.Left+bar.Width/2,bar.Top+bar.Height*i/10);
                if(overlay.Contains(p))continue;
                Native.POINT np=new Native.POINT();np.X=p.X;np.Y=p.Y;
                IntPtr h=Native.WindowFromPoint(np);
                if(h==taskbar||GetAncestor(h,2)==taskbar)return true;
            }
            return false;
        }
    }
    internal sealed partial class OverlayForm
    {
        private bool presentationSuppressed;
        private bool EnsureTaskbarOwner()
        {
            // R151: a popup OWNER is not a WS_CHILD parent. Windows keeps an
            // owned popup above its owner. Do not reparent during Start (known
            // to be rejected); never alter Explorer styles, UIAccess or z-bands.
            if(!IsHandleCreated||taskbar==IntPtr.Zero||!Native.IsWindow(taskbar))
                throw new InvalidOperationException("Taskbar owner is unavailable");
            if((Native.GetWindowLongPtr(Handle,Native.GWL_STYLE).ToInt64()&Native.WS_CHILD)!=0)
                throw new InvalidOperationException("Taskbar-owned popup must not be WS_CHILD");
            const int ownerIndex=-8; // GWLP_HWNDPARENT for an overlapped/popup window.
            IntPtr before=Native.GetWindowLongPtr(Handle,ownerIndex);
            if(before==taskbar)return false; // No steady-state reorder or repaint.
            Native.SetWindowLongPtr(Handle,ownerIndex,taskbar);
            int error=Marshal.GetLastWin32Error();
            if(Native.GetWindowLongPtr(Handle,ownerIndex)!=taskbar)
            {
                // Ownership is changed on OUR HWND only; rollback on failure.
                Native.SetWindowLongPtr(Handle,ownerIndex,before);
                bool restored=Native.GetWindowLongPtr(Handle,ownerIndex)==before;
                throw new InvalidOperationException("Taskbar owner rejected win32="+error+" rollback="+restored);
            }
            Log.Write("INFO","TASKBAR_OWNER_ESTABLISHED owner="+taskbar.ToInt64()+" hwnd="+Handle.ToInt64());
            return true;
        }

        private bool presentationSyncing;
        private TaskbarPresentationState presentationState=TaskbarPresentationState.Visible;
        private IntPtr presentationForeground=IntPtr.Zero;
        private bool presentationShellOpen;
        private DateTime presentationNextShellCheck=DateTime.MinValue;
        private int presentationTransitions;
        internal bool PresentationSuppressedForProof {get{return presentationSuppressed;}}
        internal int PresentationTransitionsForProof {get{return presentationTransitions;}}
        internal void RefreshPresentationForProof(){RefreshTaskbarPresentation(true);}
        private bool RefreshTaskbarPresentation(bool repairOrder)
        {
            if((proofMode&&!glassNativeVisualProofMode)||IsDisposed||Disposing||!IsHandleCreated)
                return false;
            if(presentationSyncing)return presentationSuppressed;
            presentationSyncing=true;
            try
            {
                IntPtr fg=Native.GetForegroundWindow();
                bool exists=taskbar!=IntPtr.Zero&&Native.IsWindow(taskbar);
                Native.RECT raw;Rectangle bar=Rectangle.Empty;
                if(exists&&Native.GetWindowRect(taskbar,out raw))bar=raw.ToRectangle();
                Rectangle screen=Screen.FromHandle(exists?taskbar:Handle).Bounds;
                bool fgChanged=fg!=presentationForeground;
                DateTime now=DateTime.UtcNow;
                if(fgChanged||now>=presentationNextShellCheck)
                {
                    string processName,windowClass;IntPtr shell;
                    presentationShellOpen=ShellUi.IsStartShellForeground(out processName,out windowClass,out shell);
                    // Foreground may temporarily leave a still-open Start surface. Do not rescan every paint.
                    if(!presentationShellOpen)
                    {Rectangle sr;presentationShellOpen=ShellUi.IsStartSurfacePresent(out processName,out windowClass,out sr,out shell);}
                    presentationNextShellCheck=now.AddSeconds(1);
                }
                bool full=exists&&TaskbarPresentationNative.Fullscreen(fg,Handle,screen,presentationShellOpen);
                bool revealed=full&&TaskbarPresentationNative.TaskbarRevealed(taskbar,bar,expectedRect,fg);
                TaskbarPresentationState next=TaskbarPresentationPolicy.Decide(exists,
                    exists&&Native.IsWindowVisible(taskbar),exists&&TaskbarPresentationNative.Cloaked(taskbar),
                    bar,screen,full,revealed);
                bool changed=next!=presentationState;
                if(changed){presentationState=next;presentationTransitions++;Log.Write("INFO","TASKBAR_PRESENTATION_STATE "+next);}
                if(next!=TaskbarPresentationState.Visible)
                {
                    presentationSuppressed=true;
                    if(next==TaskbarPresentationState.Missing&&!recoveryPending)
                        ScheduleRecovery("TASKBAR_PRESENTATION_MISSING",750);
                    if(Visible)Hide();
                    if(hardwareFlyout!=null&&hardwareFlyout.Visible)hardwareFlyout.Hide();
                    presentationForeground=fg;
                    return true;
                }
                bool restore=presentationSuppressed||!Visible;
                presentationSuppressed=false;
                startGlassPinnedDuringShell=presentationShellOpen; // Freeze layout, NOT visibility/z-order repair.
                if(restore)Show(); // ShowWithoutActivation=true is retained.
                // The owner relationship is permanent across Start; geometry never changes host type.
                if(repairOrder&&RequiresGlassTopLevel&&expectedRect.Width>=80&&expectedRect.Height>=16&&
                    bar.Contains(expectedRect)&&!recoveryPending)
                {
                    bool ownerChanged=EnsureTaskbarOwner();
                    if(restore||changed||ownerChanged)
                    {
                        const uint flags=Native.SWP_NOACTIVATE|Native.SWP_SHOWWINDOW|Native.SWP_NOOWNERZORDER;
                        if(!Native.SetWindowPos(Handle,Native.HWND_TOPMOST,expectedRect.X,expectedRect.Y,
                            expectedRect.Width,expectedRect.Height,flags))
                            Log.Write("WARN","TASKBAR_PRESENTATION_RESTACK_FAILED "+Marshal.GetLastWin32Error());
                        // Only genuine attach/restore transitions reseat the native surface.
                        PaintPerPixelLayer();
                    }
                    if(fgChanged||restore||ownerChanged)
                    {
                        // Only OUR dialogs/menu. No steady-state taskbar cluster reassert.
                        if(settingsForm!=null&&!settingsForm.IsDisposed&&settingsForm.Visible&&settingsForm.IsHandleCreated)
                            Native.SetWindowPos(settingsForm.Handle,Native.HWND_TOPMOST,0,0,0,0,
                                Native.SWP_NOMOVE|Native.SWP_NOSIZE|Native.SWP_NOACTIVATE|Native.SWP_NOOWNERZORDER);
                        if(menu!=null&&!menu.IsDisposed&&menu.Visible&&menu.IsHandleCreated)
                            Native.SetWindowPos(menu.Handle,Native.HWND_TOPMOST,0,0,0,0,
                                Native.SWP_NOMOVE|Native.SWP_NOSIZE|Native.SWP_NOACTIVATE|Native.SWP_NOOWNERZORDER);
                        // Do not repaint/reassert the monitor merely because focus changed.
                    }
                }
                presentationForeground=fg;
                return false;
            }
            finally{presentationSyncing=false;}
        }
    }
}
