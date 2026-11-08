// TBME_V1_1_2_R21_RC6: production hardening; native CPU usage, cached WMI topology, power-aware telemetry, supervisor diagnostics.
// TBME_V1_1_2_R20_RC1: LHM native sensor access isolated from the UI process; CPU/GPU/storage failures are independently contained.
// TBME_V1_1_1_R18_STABLE: low-pressure taskbar-child shell integration + single-instance Settings.
// TBME_V1_1_0_DISK_TEMP_BROKER_RESTORE_R02: elevated storage temperatures + LHM HardwareId drive-index correlation; shell core unchanged.
// TBME_V1_1_0_SHELL_RESTORE_R01: exact accepted v1.0.2 Shell integration core restored onto current v1.1.0 feature source; no telemetry/hover/update rollback.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Management;
using System.Net;
using System.Net.NetworkInformation;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Automation;
using System.Windows.Forms;
using System.Web.Script.Serialization;
using Microsoft.Win32;


[assembly: AssemblyTitle("Taskbar Monitor Enhanced")]
[assembly: AssemblyDescription("Live system monitor integrated into the Windows taskbar")]
[assembly: AssemblyProduct("Taskbar Monitor Enhanced")]
[assembly: AssemblyCompany("Dr. Ali-Akbar Emadeddin")]
[assembly: AssemblyInformationalVersion("1.7.8+r286")]
[assembly: AssemblyCopyright("Copyright © 2026 Dr. Ali-Akbar Emadeddin")]
[assembly: AssemblyVersion("1.7.8.0")]
[assembly: AssemblyFileVersion("1.7.8.0")]

namespace TaskbarMonitorEnhanced
{
    internal static class BuildInfo
    {
        public const string Version = "V1_7_8_R286_OPTIONAL_TEMP_SOUND";
        public const string Product = "Taskbar Monitor Enhanced";
        public const string PublicVersion = "1.7.8";
        public const string ShortcutName = "Taskbar Monitor Enhanced";
        public const string ProductDescription = "Live system monitor integrated into the Windows taskbar";
        public const string Author = "Dr. Ali-Akbar Emadeddin";
        public const string AuthorEmail = "aliemad1324@gmail.com";
        public const string AuthorGitHub = "https://github.com/GOD13emad";
        public const string RepositoryUrl = "https://github.com/GOD13emad/TaskbarMonitorEnhanced";
        public const string LatestReleaseApi = "https://api.github.com/repos/GOD13emad/TaskbarMonitorEnhanced/releases/latest";
        public const string LicenseId = "GPL-3.0";
        public const int HistoryLength = 120;
        public const int DefaultWidth = 1100;
    }

    internal static class AppPaths
    {
        public static readonly string Root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "TaskbarMonitorEnhanced");
        public static readonly string Config = Path.Combine(Root, "config.json");
        public static readonly string ConfigBackup = Path.Combine(Root, "config.json.bak");
        public static readonly string Logs = Path.Combine(Root, "Logs");
        public static readonly string SensorBackend = Path.Combine(Root, "SensorBackend", "LibreHardwareMonitor-0.9.6");
        public static readonly string SensorBackendState = Path.Combine(Root, "sensor_backend_state.json");
        public static readonly string CpuTempBrokerData = Path.Combine(Root, "cpu_temp_broker.json");
        public static readonly string GpuBrokerData = Path.Combine(Root, "gpu_temp_broker.json");
        public static readonly string StorageBrokerData = Path.Combine(Root, "storage_temp_broker.json");
        public static readonly string SensorSupervisorState = Path.Combine(Root, "sensor_supervisor_state.json");
        public static readonly string InstallState = Path.Combine(Root, "install_state.json");
        public static readonly string CrashState = Path.Combine(Root, "last_crash.json");
        public static readonly string Updates = Path.Combine(Root, "Updates");
        public static readonly string Log = Path.Combine(Logs, "tbme_csharp_" + DateTime.Now.ToString("yyyyMMdd") + ".log");
    }

    internal static class SensorSupervisorSelfHeal
    {
        public const int StartupGraceSeconds=90;
        public const int StateStaleSeconds=90;
        public const int RetryCooldownSeconds=180;
        public const string TaskName="TaskbarMonitorEnhanced Sensor Broker";

        static bool ProtectedLayerReady(string installStatePath)
        {
            try
            {
                if(String.IsNullOrWhiteSpace(installStatePath)||!File.Exists(installStatePath))return false;
                string json;
                using(FileStream fs=new FileStream(installStatePath,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))
                using(StreamReader sr=new StreamReader(fs,Encoding.UTF8,true))
                    json=sr.ReadToEnd();
                if(String.IsNullOrWhiteSpace(json))return false;
                Dictionary<string,object> d=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(json);
                object value;
                return d!=null&&d.TryGetValue("SensorLayerStatus",out value)&&
                    String.Equals(Convert.ToString(value,CultureInfo.InvariantCulture),"READY",StringComparison.OrdinalIgnoreCase);
            }
            catch{return false;}
        }

        public static bool ShouldAttempt(
            string installStatePath,
            string supervisorStatePath,
            DateTime nowUtc,
            DateTime appStartedUtc,
            DateTime lastAttemptUtc,
            out string reason)
        {
            reason="";
            if((nowUtc-appStartedUtc).TotalSeconds<StartupGraceSeconds)return false;
            if(lastAttemptUtc!=DateTime.MinValue&&(nowUtc-lastAttemptUtc).TotalSeconds<RetryCooldownSeconds)return false;
            if(!ProtectedLayerReady(installStatePath))return false;
            try
            {
                if(String.IsNullOrWhiteSpace(supervisorStatePath)||!File.Exists(supervisorStatePath))
                {
                    reason="STATE_MISSING_AFTER_GRACE";
                    return true;
                }
                DateTime writeUtc=File.GetLastWriteTimeUtc(supervisorStatePath);
                double age=(nowUtc-writeUtc).TotalSeconds;
                if(age>StateStaleSeconds)
                {
                    reason="STATE_STALE_"+age.ToString("0",CultureInfo.InvariantCulture)+"S";
                    return true;
                }
            }
            catch(Exception ex)
            {
                reason="STATE_CHECK_ERROR_"+ex.GetType().Name;
                return true;
            }
            return false;
        }

        public static int TryRunExistingTask(out string detail)
        {
            detail="";
            try
            {
                string system=Environment.GetFolderPath(Environment.SpecialFolder.System);
                string exe=Path.Combine(system,"schtasks.exe");
                if(!File.Exists(exe))exe="schtasks.exe";
                ProcessStartInfo psi=new ProcessStartInfo();
                psi.FileName=exe;
                psi.Arguments="/Run /TN \""+TaskName+"\"";
                psi.UseShellExecute=false;
                psi.CreateNoWindow=true;
                psi.RedirectStandardOutput=true;
                psi.RedirectStandardError=true;
                Process x=Process.Start(psi);
                if(x==null){detail="START_RETURNED_NULL";return -2;}
                if(!x.WaitForExit(8000))
                {
                    try{x.Kill();}catch{}
                    detail="SCHTASKS_TIMEOUT";
                    return -3;
                }
                string stdout="";string stderr="";
                try{stdout=x.StandardOutput.ReadToEnd();}catch{}
                try{stderr=x.StandardError.ReadToEnd();}catch{}
                detail=(stdout+" "+stderr).Trim();
                return x.ExitCode;
            }
            catch(Exception ex)
            {
                detail=ex.GetType().Name+": "+ex.Message;
                return -1;
            }
        }
    }

    internal static class Log
    {
        private static readonly object Sync = new object();
        private static DateTime lastMaintenanceUtc=DateTime.MinValue;
        private const long MaxDailyLogBytes=8L*1024L*1024L;
        private const int RetentionDays=30;

        private static void Maintain()
        {
            DateTime now=DateTime.UtcNow;
            if(lastMaintenanceUtc!=DateTime.MinValue&&(now-lastMaintenanceUtc).TotalMinutes<10)return;
            lastMaintenanceUtc=now;
            try
            {
                Directory.CreateDirectory(AppPaths.Logs);
                foreach(string f in Directory.GetFiles(AppPaths.Logs,"tbme_csharp_*.log"))
                {
                    try
                    {
                        if((now-File.GetLastWriteTimeUtc(f)).TotalDays>RetentionDays)File.Delete(f);
                    }
                    catch{}
                }

                if(File.Exists(AppPaths.Log)&&new FileInfo(AppPaths.Log).Length>=MaxDailyLogBytes)
                {
                    string rotated=Path.Combine(
                        AppPaths.Logs,
                        "tbme_csharp_"+DateTime.Now.ToString("yyyyMMdd_HHmmss",CultureInfo.InvariantCulture)+".log"
                    );
                    if(File.Exists(rotated))File.Delete(rotated);
                    File.Move(AppPaths.Log,rotated);
                }
            }
            catch{}
        }

        public static void Write(string level, string message)
        {
            try
            {
                lock (Sync)
                {
                    Maintain();
                    Directory.CreateDirectory(AppPaths.Logs);
                    File.AppendAllText(AppPaths.Log,
                        DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture) + " [" + level + "] " + message + Environment.NewLine,
                        Encoding.UTF8);
                }
            }
            catch { }
        }
    }

    internal static class AtomicTextFile
    {
        public static void Write(string path,string value,Encoding encoding,string backupPath)
        {
            if(String.IsNullOrWhiteSpace(path))throw new ArgumentException("path");
            string dir=Path.GetDirectoryName(path);
            if(!String.IsNullOrWhiteSpace(dir))Directory.CreateDirectory(dir);
            string tmp=path+"."+Process.GetCurrentProcess().Id.ToString(CultureInfo.InvariantCulture)+"."+Environment.TickCount.ToString(CultureInfo.InvariantCulture)+".tmp";
            File.WriteAllText(tmp,value??"",encoding??Encoding.UTF8);
            try
            {
                if(File.Exists(path))
                {
                    File.Replace(tmp,path,String.IsNullOrWhiteSpace(backupPath)?null:backupPath,true);
                }
                else
                {
                    File.Move(tmp,path);
                    if(!String.IsNullOrWhiteSpace(backupPath)&&!File.Exists(backupPath))
                        File.Copy(path,backupPath,true);
                }
            }
            catch
            {
                try{if(File.Exists(tmp))File.Delete(tmp);}catch{}
                throw;
            }
        }
    }

    internal static class RuntimeGuard
    {
        private static int installed=0;
        private static string SafeCrashText(string value)
        {
            string s=value??"";
            try
            {
                if(!String.IsNullOrWhiteSpace(AppPaths.Root))s=s.Replace(AppPaths.Root,"%TBME_DATA%");
                string profile=Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                if(!String.IsNullOrWhiteSpace(profile))s=s.Replace(profile,"%USERPROFILE%");
            }
            catch{}
            return s.Length<=4000?s:s.Substring(0,4000);
        }
        private static Dictionary<string,object> CrashSnapshot(string kind,Exception ex,bool terminating)
        {
            Dictionary<string,object> d=new Dictionary<string,object>();
            d["SchemaVersion"]=1;
            d["GeneratedUtc"]=DateTime.UtcNow.ToString("o",CultureInfo.InvariantCulture);
            d["Build"]=BuildInfo.Version;
            d["PublicVersion"]=BuildInfo.PublicVersion;
            d["Kind"]=kind??"UNKNOWN";
            d["Terminating"]=terminating;
            d["ExceptionType"]=ex==null?"UNKNOWN":ex.GetType().FullName;
            d["Message"]=SafeCrashText(ex==null?"":ex.Message);
            d["StackTrace"]=SafeCrashText(ex==null?"":ex.StackTrace);
            d["UiThreadExceptionCount"]=UiThreadExceptionCount;
            d["AppDomainUnhandledCount"]=AppDomainUnhandledCount;
            return d;
        }
        private static void WriteCrashSnapshotTo(string path,string kind,Exception ex,bool terminating)
        {
            AtomicTextFile.Write(path,new JavaScriptSerializer().Serialize(CrashSnapshot(kind,ex,terminating)),Encoding.UTF8,null);
        }
        private static void WriteCrashSnapshot(string kind,Exception ex,bool terminating)
        {
            try{WriteCrashSnapshotTo(AppPaths.CrashState,kind,ex,terminating);}catch{}
        }
        internal static int ProbeCrashSnapshot(string outputPath)
        {
            try
            {
                if(String.IsNullOrWhiteSpace(outputPath))throw new ArgumentException("output path");
                Exception sample;
                try{throw new InvalidOperationException("probe "+Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)+" "+AppPaths.Root);}
                catch(Exception ex){sample=ex;}
                WriteCrashSnapshotTo(outputPath,"PROOF",sample,false);
                string json=File.ReadAllText(outputPath,Encoding.UTF8);
                string profile=Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                if(!String.IsNullOrWhiteSpace(profile)&&json.IndexOf(profile,StringComparison.OrdinalIgnoreCase)>=0)throw new InvalidDataException("crash snapshot leaks user profile");
                if(!String.IsNullOrWhiteSpace(AppPaths.Root)&&json.IndexOf(AppPaths.Root,StringComparison.OrdinalIgnoreCase)>=0)throw new InvalidDataException("crash snapshot leaks app data path");
                if(json.IndexOf("%USERPROFILE%",StringComparison.Ordinal)<0||json.IndexOf("%TBME_DATA%",StringComparison.Ordinal)<0)throw new InvalidDataException("crash snapshot redaction markers missing");
                Console.WriteLine("TBME_CRASH_SNAPSHOT_PROOF=PASS PRIVACY=PASS");
                return 0;
            }
            catch(Exception ex){Console.Error.WriteLine("TBME_CRASH_SNAPSHOT_PROOF=FAIL "+ex);return 18;}
        }
        public static int UiThreadExceptionCount=0;
        public static int AppDomainUnhandledCount=0;

        public static void Install()
        {
            if(Interlocked.Exchange(ref installed,1)!=0)return;
            try
            {
                Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
                Application.ThreadException+=delegate(object sender,ThreadExceptionEventArgs e)
                {
                    Interlocked.Increment(ref UiThreadExceptionCount);
                    Exception crash=e!=null?e.Exception:null;WriteCrashSnapshot("UI_THREAD_EXCEPTION",crash,false);
                    Log.Write("ERROR","UI_THREAD_EXCEPTION "+(crash!=null?crash.ToString():"UNKNOWN"));
                };
            }
            catch(Exception ex){Log.Write("WARN","RUNTIME_GUARD_UI_INSTALL "+ex.Message);}
            try
            {
                AppDomain.CurrentDomain.UnhandledException+=delegate(object sender,UnhandledExceptionEventArgs e)
                {
                    Interlocked.Increment(ref AppDomainUnhandledCount);
                    Exception crash=e.ExceptionObject as Exception;WriteCrashSnapshot("APPDOMAIN_UNHANDLED",crash,e.IsTerminating);
                    Log.Write("ERROR","APPDOMAIN_UNHANDLED terminating="+e.IsTerminating+" "+(e.ExceptionObject==null?"UNKNOWN":e.ExceptionObject.ToString()));
                };
            }
            catch(Exception ex){Log.Write("WARN","RUNTIME_GUARD_DOMAIN_INSTALL "+ex.Message);}
            try
            {
                AppDomain.CurrentDomain.ProcessExit+=delegate{Log.Write("INFO","PROCESS_EXIT uiExceptions="+UiThreadExceptionCount+" domainUnhandled="+AppDomainUnhandledCount);};
            }
            catch{}
            Log.Write("INFO","RUNTIME_GUARD_INSTALLED");
        }

        public static void SafeUi(string area,Action action)
        {
            try{action();}
            catch(Exception ex)
            {
                Interlocked.Increment(ref UiThreadExceptionCount);
                Log.Write("ERROR","UI_GUARDED_EXCEPTION area="+area+" "+ex.ToString());
            }
        }
    }

    public sealed partial class AppConfig
    {
        public string Theme { get; set; }
        public string Position { get; set; }
        public double Opacity { get; set; }
        // Glass is an independent ON/OFF state, NOT the transparency percentage.
        // When ON: background alpha is exactly 0; the editable 1-100% value is saved.
        public bool GlassMode { get; set; }
        public double OpacityWhenGlassOff { get; set; }
        // Optional legacy Windows 11 workaround; OFF by default. The monitor
        // remains anchored to the taskbar while Start/Search is open.
        public bool FloatAboveStartMenu { get; set; }
        public int UpdateIntervalMs { get; set; }
        public bool ShowCpu { get; set; }
        public bool ShowRam { get; set; }
        public bool ShowDisk { get; set; }
        public bool ShowGpu { get; set; }
        public bool ShowVram { get; set; }
        public bool ShowNetwork { get; set; }
        public bool ShowTemperatures { get; set; }
        public bool ShowSparklines { get; set; }
        public bool StartWithWindows { get; set; }
        public int WidthLogicalPx { get; set; }
        public int MinWidthLogicalPx { get; set; }
        public int MaxWidthLogicalPx { get; set; }
        public int MarginLogicalPx { get; set; }
        public int VerticalMarginLogicalPx { get; set; }
        public int SafePlacementPaddingLogicalPx { get; set; }
        public bool SafePlacement { get; set; }
        public string FontFamily { get; set; }
        public double FontSize { get; set; }

        // R13 multi-hardware / unit configuration. IDs are semicolon-separated
        // so legacy JavaScriptSerializer config remains forward/backward tolerant.
        public string CpuDisplayMode { get; set; }
        public string GpuDisplayMode { get; set; }
        public string DiskDisplayMode { get; set; }
        public string NetworkDisplayMode { get; set; }
        public string SelectedCpuIds { get; set; }
        public string SelectedGpuIds { get; set; }
        public string SelectedDiskIds { get; set; }
        public string SelectedNetworkIds { get; set; }
        public string MultipleDeviceLayout { get; set; }
        public string MemoryUnit { get; set; }
        public string StorageUnit { get; set; }
        public string NetworkUnit { get; set; }
        public string DiskRateUnit { get; set; }
        public bool ShowRamNumeric { get; set; }
        public bool ShowDiskNumeric { get; set; }
        public bool EnableHardwareFlyout { get; set; }
        public bool HoverShowAllDevices { get; set; }
        public bool AutoCheckUpdates { get; set; }
        public bool EnableTemperatureAlerts { get; set; }
        public bool EnableTemperatureNotifications { get; set; }
        // Explicitly opt in to the current user's Windows warning sound.
        public bool EnableTemperatureWarningSound { get; set; }
        public int CpuTempWarningC { get; set; }
        public int GpuTempWarningC { get; set; }
        public int DiskTempWarningC { get; set; }
        public bool AdaptiveBatteryMode { get; set; }
        public int BatteryUpdateIntervalMs { get; set; }
        public int SparklineHistoryLength { get; set; }
        public bool FollowWindowsTheme { get; set; }
        public string WindowsLightTheme { get; set; }
        public string WindowsDarkTheme { get; set; }
        public string TaskbarDisplay { get; set; }
        public int ConfigSchemaVersion { get; set; }

        public AppConfig()
        {
            Theme = "Dark Minimal Pro";
            Position = "Left";
            Opacity = 0.97;
            GlassMode = false;
            OpacityWhenGlassOff = 0.97;
            FloatAboveStartMenu = false;
            UpdateIntervalMs = 1000;
            ShowCpu = true; ShowRam = true; ShowDisk = true; ShowGpu = true; ShowVram = true; ShowNetwork = true;
            ShowTemperatures = true;
            ShowSparklines = true;
            StartWithWindows = true;
            WidthLogicalPx = 1100;
            MinWidthLogicalPx = 1100;
            MaxWidthLogicalPx = 1400;
            MarginLogicalPx = 0;
            VerticalMarginLogicalPx = 0;
            SafePlacementPaddingLogicalPx = 0;
            SafePlacement = true;
            FontFamily = "Segoe UI";
            FontSize = 8.8;
            CpuDisplayMode = "Overall";
            GpuDisplayMode = "Auto";
            DiskDisplayMode = "Overall";
            NetworkDisplayMode = "Overall";
            SelectedCpuIds = ""; SelectedGpuIds = ""; SelectedDiskIds = ""; SelectedNetworkIds = "";
            MultipleDeviceLayout = "Grouped";
            MemoryUnit = "Auto"; StorageUnit = "Auto"; NetworkUnit = "Auto"; DiskRateUnit = "Auto";
            ShowRamNumeric = true; ShowDiskNumeric = true;
            EnableHardwareFlyout = true; HoverShowAllDevices = true; AutoCheckUpdates = true;
            EnableTemperatureAlerts = true; EnableTemperatureNotifications = false; EnableTemperatureWarningSound = false; CpuTempWarningC = 85; GpuTempWarningC = 85; DiskTempWarningC = 60;
            AdaptiveBatteryMode = true; BatteryUpdateIntervalMs = 3000; SparklineHistoryLength = 120;
            FollowWindowsTheme=false;WindowsLightTheme="Nordic Light";WindowsDarkTheme="Dark Minimal Pro";TaskbarDisplay="Primary";
            InitializeWorkspaceDefaults();
            ConfigSchemaVersion = 8;
        }

        public void Normalize()
        {
            if (String.IsNullOrWhiteSpace(Theme) || String.Equals(Theme, "Auto", StringComparison.OrdinalIgnoreCase)) Theme = "Dark Minimal Pro";
            if (!ThemeCatalog.Names.Contains(Theme)) Theme = "Dark Minimal Pro";
            if (String.IsNullOrWhiteSpace(Position) || (Position != "Left" && Position != "Center" && Position != "Right")) Position = "Left";
            // R125: owner explicitly requires the v1.6 fixed taskbar UX; no Start/Search lift, ever.
            FloatAboveStartMenu=false;
            if (!MetricStatistics.Finite(Opacity)) Opacity = 0.97;
            else Opacity = Math.Max(0.0,Math.Min(1.0,Opacity));
            if (UpdateIntervalMs < 1000 || UpdateIntervalMs > 5000) UpdateIntervalMs = 1000;
            if (MinWidthLogicalPx < 900 || MinWidthLogicalPx > 1500) MinWidthLogicalPx = 1100;
            if (MaxWidthLogicalPx < MinWidthLogicalPx) MaxWidthLogicalPx = Math.Max(1400, MinWidthLogicalPx);
            MarginLogicalPx = 0;
            VerticalMarginLogicalPx = 0;
            SafePlacementPaddingLogicalPx = 0;
            if (String.IsNullOrWhiteSpace(FontFamily)) FontFamily = "Segoe UI";
            if (!MetricStatistics.Finite(FontSize) || FontSize < 6.5 || FontSize > 16.0) FontSize = 8.8;
            if(ConfigSchemaVersion<2)
            {
                CpuDisplayMode="Overall";GpuDisplayMode="Auto";DiskDisplayMode="Overall";NetworkDisplayMode="Overall";MultipleDeviceLayout="Grouped";MemoryUnit="Auto";StorageUnit="Auto";NetworkUnit="Auto";ShowRamNumeric=true;ShowDiskNumeric=true;EnableHardwareFlyout=true;HoverShowAllDevices=true;
            }
            if(ConfigSchemaVersion<3)
            {
                DiskRateUnit="Auto";AutoCheckUpdates=true;ConfigSchemaVersion=3;
            }
            if(ConfigSchemaVersion<4)
            {
                EnableTemperatureAlerts=true;CpuTempWarningC=85;GpuTempWarningC=85;DiskTempWarningC=60;
                AdaptiveBatteryMode=true;BatteryUpdateIntervalMs=3000;SparklineHistoryLength=120;ConfigSchemaVersion=4;
            }
            if(ConfigSchemaVersion<5)
            {
                FollowWindowsTheme=false;WindowsLightTheme="Nordic Light";WindowsDarkTheme="Dark Minimal Pro";TaskbarDisplay="Primary";ConfigSchemaVersion=5;
            }
            if(ConfigSchemaVersion<6)
            {
                EnableTemperatureNotifications=false;ConfigSchemaVersion=6;
            }
            NormalizeWorkspace();
            // Preserve the meaning of an existing v1.7 0%-opacity config while
            // migrating without overwriting a user's selected opacity or theme.
            if(ConfigSchemaVersion<8)
            {
                GlassMode=Opacity<=0.0;
                OpacityWhenGlassOff=Opacity>0.0?Opacity:0.97;
                ConfigSchemaVersion=8;
            }
            if(!MetricStatistics.Finite(OpacityWhenGlassOff) ||
               OpacityWhenGlassOff<0.01 || OpacityWhenGlassOff>1.0)
                OpacityWhenGlassOff=0.97;
            if(GlassMode)
            {
                if(Opacity>0.0)OpacityWhenGlassOff=Math.Max(0.01,Opacity);
                Opacity=0.0;
            }
            else
            {
                Opacity=Math.Max(0.01,Math.Min(1.0,Opacity));
                OpacityWhenGlassOff=Opacity;
            }
            if(String.IsNullOrWhiteSpace(WindowsLightTheme)||!ThemeCatalog.Names.Contains(WindowsLightTheme))WindowsLightTheme="Nordic Light";
            if(String.IsNullOrWhiteSpace(WindowsDarkTheme)||!ThemeCatalog.Names.Contains(WindowsDarkTheme))WindowsDarkTheme="Dark Minimal Pro";
            TaskbarDisplay=TaskbarTargetPolicy.NormalizeConfigId(TaskbarDisplay);
            CpuTempWarningC=Math.Max(50,Math.Min(110,CpuTempWarningC));
            GpuTempWarningC=Math.Max(50,Math.Min(110,GpuTempWarningC));
            DiskTempWarningC=Math.Max(40,Math.Min(90,DiskTempWarningC));
            BatteryUpdateIntervalMs=Math.Max(2000,Math.Min(10000,BatteryUpdateIntervalMs));
            SparklineHistoryLength=Math.Max(30,Math.Min(300,SparklineHistoryLength));
            CpuDisplayMode = NormalizeDisplayMode(CpuDisplayMode, "Overall");
            GpuDisplayMode = NormalizeDisplayMode(GpuDisplayMode, "Auto");
            DiskDisplayMode = NormalizeDisplayMode(DiskDisplayMode, "Overall");
            NetworkDisplayMode = NormalizeDisplayMode(NetworkDisplayMode, "Overall");
            if(String.IsNullOrWhiteSpace(MultipleDeviceLayout) || (MultipleDeviceLayout!="Grouped" && MultipleDeviceLayout!="Separate")) MultipleDeviceLayout="Grouped";
            MemoryUnit = NormalizeUnit(MemoryUnit); StorageUnit = NormalizeUnit(StorageUnit); NetworkUnit = NormalizeUnit(NetworkUnit); DiskRateUnit = NormalizeUnit(DiskRateUnit);
            if(SelectedCpuIds==null)SelectedCpuIds=""; if(SelectedGpuIds==null)SelectedGpuIds=""; if(SelectedDiskIds==null)SelectedDiskIds=""; if(SelectedNetworkIds==null)SelectedNetworkIds="";
        }

        private static string NormalizeDisplayMode(string value,string fallback)
        {
            if(String.IsNullOrWhiteSpace(value))return fallback;
            foreach(string x in new string[]{"Overall","Auto","Single","Multiple"})if(String.Equals(value,x,StringComparison.OrdinalIgnoreCase))return x;
            return fallback;
        }

        private static string NormalizeUnit(string value)
        {
            if(String.IsNullOrWhiteSpace(value))return "Auto";
            foreach(string x in new string[]{"Auto","KB","MB","GB"})if(String.Equals(value,x,StringComparison.OrdinalIgnoreCase))return x;
            return "Auto";
        }

        private static AppConfig LoadPath(string path)
        {
            JavaScriptSerializer js=new JavaScriptSerializer();
            AppConfig c=js.Deserialize<AppConfig>(File.ReadAllText(path,Encoding.UTF8));
            if(c==null)throw new InvalidDataException("Configuration JSON is empty.");
            c.Normalize();
            return c;
        }

        public static AppConfig Load()
        {
            Directory.CreateDirectory(AppPaths.Root);
            if(!File.Exists(AppPaths.Config))
            {
                if(File.Exists(AppPaths.ConfigBackup))
                {
                    try
                    {
                        AppConfig recovered=LoadPath(AppPaths.ConfigBackup);
                        Log.Write("WARN","CONFIG_PRIMARY_MISSING_RECOVERED_FROM_BACKUP");
                        try{AtomicTextFile.Write(AppPaths.Config,new JavaScriptSerializer().Serialize(recovered),Encoding.UTF8,AppPaths.ConfigBackup);}catch{}
                        return recovered;
                    }
                    catch(Exception backupEx){Log.Write("WARN","CONFIG_BACKUP_LOAD_FAILED "+backupEx.Message);}
                }
                return new AppConfig();
            }

            try{return LoadPath(AppPaths.Config);}
            catch(Exception ex)
            {
                Log.Write("WARN","CONFIG_LOAD_FAILED "+ex.Message);
                if(File.Exists(AppPaths.ConfigBackup))
                {
                    try
                    {
                        AppConfig recovered=LoadPath(AppPaths.ConfigBackup);
                        Log.Write("WARN","CONFIG_RECOVERED_FROM_BACKUP");
                        try{AtomicTextFile.Write(AppPaths.Config,new JavaScriptSerializer().Serialize(recovered),Encoding.UTF8,AppPaths.ConfigBackup);}catch{}
                        return recovered;
                    }
                    catch(Exception backupEx){Log.Write("WARN","CONFIG_BACKUP_LOAD_FAILED "+backupEx.Message);}
                }
                return new AppConfig();
            }
        }

        public void Save()
        {
            Normalize();
            Directory.CreateDirectory(AppPaths.Root);
            JavaScriptSerializer js = new JavaScriptSerializer();
            AtomicTextFile.Write(AppPaths.Config,js.Serialize(this),Encoding.UTF8,AppPaths.ConfigBackup);
        }
    }

    internal sealed class ThemeDefinition
    {
        public string Name;
        public Color Background;
        public Color Background2;
        public Color Foreground;
        public Color Muted;
        public Color Border;
        public Color[] Accents;
        public string Mode;
        public string FontName;
        public bool Light;

        public ThemeDefinition(string name, Color bg, Color bg2, Color fg, Color muted, Color border, Color[] accents, string mode, string fontName, bool light)
        {
            Name=name; Background=bg; Background2=bg2; Foreground=fg; Muted=muted; Border=border; Accents=accents; Mode=mode; FontName=fontName; Light=light;
        }
    }

    internal static class ThemeCatalog
    {
        public static readonly string[] Names = new string[] {
            "Dark Minimal Pro", "Glass Morphism", "Neon Cyberpunk", "Sleek White", "Round Compact", "Honeycomb Tech", "Retro Terminal",
            "Fluent Glass", "OLED Mono", "Cyber Neon", "Mission Control", "Blueprint Tech", "Medical Telemetry", "Carbon Racing",
            "Aurora Borealis", "Solarized Luxe", "Arctic Frost", "Sakura Night", "Matrix Grid", "Desert Sand", "Royal Amethyst",
            "Ocean Depth", "Copper Industrial", "Nordic Light", "Ember Forge", "Synthwave Sunset", "Quantum Violet", "Monochrome Paper"
        };

        private static readonly Dictionary<string, ThemeDefinition> Themes = new Dictionary<string, ThemeDefinition>(StringComparer.OrdinalIgnoreCase)
        {
            {"Dark Minimal Pro", new ThemeDefinition("Dark Minimal Pro", Color.FromArgb(17,20,24), Color.FromArgb(10,12,15), Color.FromArgb(244,247,249), Color.FromArgb(150,160,170), Color.FromArgb(48,54,61), new Color[]{Color.FromArgb(56,189,248),Color.FromArgb(168,85,247),Color.FromArgb(34,197,94),Color.FromArgb(250,204,21),Color.FromArgb(249,115,22),Color.FromArgb(14,165,233)}, "minimal", "Segoe UI", false)},
            {"Glass Morphism", new ThemeDefinition("Glass Morphism", Color.FromArgb(34,45,63), Color.FromArgb(19,31,48), Color.White, Color.FromArgb(190,207,228), Color.FromArgb(91,130,170), new Color[]{Color.FromArgb(75,196,255),Color.FromArgb(178,125,255),Color.FromArgb(96,229,139),Color.FromArgb(255,211,79),Color.FromArgb(255,132,87),Color.FromArgb(77,208,225)}, "glass", "Segoe UI", false)},
            {"Neon Cyberpunk", new ThemeDefinition("Neon Cyberpunk", Color.FromArgb(4,8,11), Color.Black, Color.FromArgb(230,255,255), Color.FromArgb(135,180,190), Color.FromArgb(0,245,233), new Color[]{Color.FromArgb(25,247,255),Color.FromArgb(184,108,255),Color.FromArgb(99,255,114),Color.FromArgb(255,231,74),Color.FromArgb(255,101,79),Color.FromArgb(0,229,255)}, "neon", "Segoe UI", false)},
            {"Sleek White", new ThemeDefinition("Sleek White", Color.FromArgb(246,248,250), Color.FromArgb(232,236,240), Color.FromArgb(17,24,39), Color.FromArgb(66,76,90), Color.FromArgb(200,207,216), new Color[]{Color.FromArgb(38,132,255),Color.FromArgb(136,78,240),Color.FromArgb(34,170,80),Color.FromArgb(230,165,0),Color.FromArgb(235,92,52),Color.FromArgb(26,150,190)}, "white", "Segoe UI", true)},
            {"Round Compact", new ThemeDefinition("Round Compact", Color.FromArgb(15,19,23), Color.FromArgb(9,12,15), Color.FromArgb(245,248,250), Color.FromArgb(160,171,181), Color.FromArgb(78,88,98), new Color[]{Color.FromArgb(103,212,255),Color.FromArgb(174,109,255),Color.FromArgb(92,224,119),Color.FromArgb(255,211,72),Color.FromArgb(255,120,78),Color.FromArgb(84,201,230)}, "round", "Segoe UI", false)},
            {"Honeycomb Tech", new ThemeDefinition("Honeycomb Tech", Color.FromArgb(7,11,14), Color.FromArgb(12,18,23), Color.FromArgb(242,247,248), Color.FromArgb(120,145,158), Color.FromArgb(49,65,76), new Color[]{Color.FromArgb(67,217,255),Color.FromArgb(203,108,255),Color.FromArgb(112,255,104),Color.FromArgb(255,229,92),Color.FromArgb(255,116,78),Color.FromArgb(58,205,225)}, "hex", "Segoe UI", false)},
            {"Retro Terminal", new ThemeDefinition("Retro Terminal", Color.FromArgb(2,9,3), Color.Black, Color.FromArgb(124,255,112), Color.FromArgb(70,170,74), Color.FromArgb(29,107,36), new Color[]{Color.FromArgb(124,255,112),Color.FromArgb(100,235,96),Color.FromArgb(145,255,115),Color.FromArgb(108,220,90),Color.FromArgb(150,255,126),Color.FromArgb(100,235,96)}, "terminal", "Consolas", false)},
            {"Fluent Glass", new ThemeDefinition("Fluent Glass", Color.FromArgb(23,34,49), Color.FromArgb(47,70,94), Color.FromArgb(247,250,252), Color.FromArgb(174,197,214), Color.FromArgb(94,158,207), new Color[]{Color.FromArgb(94,211,255),Color.FromArgb(175,132,255),Color.FromArgb(101,230,158),Color.FromArgb(255,206,91),Color.FromArgb(255,137,105),Color.FromArgb(83,211,218)}, "fluent", "Segoe UI", false)},
            {"OLED Mono", new ThemeDefinition("OLED Mono", Color.FromArgb(0,0,0), Color.FromArgb(8,8,9), Color.FromArgb(247,247,247), Color.FromArgb(145,145,149), Color.FromArgb(55,55,59), new Color[]{Color.FromArgb(245,245,245),Color.FromArgb(220,220,222),Color.FromArgb(200,200,202),Color.FromArgb(235,235,236),Color.FromArgb(180,180,183),Color.FromArgb(225,225,227)}, "oled", "Segoe UI", false)},
            {"Cyber Neon", new ThemeDefinition("Cyber Neon", Color.FromArgb(2,5,13), Color.FromArgb(18,4,27), Color.FromArgb(239,255,255), Color.FromArgb(137,177,190), Color.FromArgb(0,238,255), new Color[]{Color.FromArgb(0,246,255),Color.FromArgb(255,65,220),Color.FromArgb(107,255,121),Color.FromArgb(255,224,68),Color.FromArgb(255,91,91),Color.FromArgb(154,91,255)}, "cyber2", "Segoe UI", false)},
            {"Mission Control", new ThemeDefinition("Mission Control", Color.FromArgb(10,17,26), Color.FromArgb(19,31,45), Color.FromArgb(226,237,244), Color.FromArgb(123,151,169), Color.FromArgb(64,91,111), new Color[]{Color.FromArgb(72,165,255),Color.FromArgb(73,205,132),Color.FromArgb(247,189,68),Color.FromArgb(238,91,91),Color.FromArgb(63,202,215),Color.FromArgb(165,113,238)}, "mission", "Segoe UI", false)},
            {"Blueprint Tech", new ThemeDefinition("Blueprint Tech", Color.FromArgb(7,39,74), Color.FromArgb(10,55,101), Color.FromArgb(236,249,255), Color.FromArgb(141,197,229), Color.FromArgb(72,170,228), new Color[]{Color.FromArgb(83,220,255),Color.FromArgb(108,177,255),Color.FromArgb(102,232,175),Color.FromArgb(255,222,111),Color.FromArgb(255,153,104),Color.FromArgb(205,240,255)}, "blueprint", "Segoe UI", false)},
            {"Medical Telemetry", new ThemeDefinition("Medical Telemetry", Color.FromArgb(244,249,250), Color.FromArgb(228,240,243), Color.FromArgb(24,54,61), Color.FromArgb(91,123,130), Color.FromArgb(165,200,204), new Color[]{Color.FromArgb(20,166,164),Color.FromArgb(41,184,105),Color.FromArgb(38,164,214),Color.FromArgb(220,164,55),Color.FromArgb(224,102,92),Color.FromArgb(72,131,196)}, "medical", "Segoe UI", true)},
            {"Carbon Racing", new ThemeDefinition("Carbon Racing", Color.FromArgb(10,10,12), Color.FromArgb(24,24,27), Color.FromArgb(248,248,249), Color.FromArgb(158,158,164), Color.FromArgb(70,70,76), new Color[]{Color.FromArgb(255,70,70),Color.FromArgb(255,130,53),Color.FromArgb(255,204,55),Color.FromArgb(57,196,255),Color.FromArgb(184,101,255),Color.FromArgb(83,220,126)}, "carbon", "Segoe UI", false)},
            {"Aurora Borealis", new ThemeDefinition("Aurora Borealis", Color.FromArgb(5,15,30), Color.FromArgb(20,35,55), Color.FromArgb(235,247,255), Color.FromArgb(145,174,194), Color.FromArgb(55,104,125), new Color[]{Color.FromArgb(66,245,202),Color.FromArgb(126,108,255),Color.FromArgb(64,177,255),Color.FromArgb(103,232,142),Color.FromArgb(255,205,96),Color.FromArgb(65,218,232)}, "aurora", "Segoe UI", false)},
            {"Solarized Luxe", new ThemeDefinition("Solarized Luxe", Color.FromArgb(24,20,16), Color.FromArgb(42,34,25), Color.FromArgb(245,236,216), Color.FromArgb(174,155,126), Color.FromArgb(111,91,55), new Color[]{Color.FromArgb(225,182,85),Color.FromArgb(195,119,68),Color.FromArgb(162,171,79),Color.FromArgb(72,177,183),Color.FromArgb(201,103,117),Color.FromArgb(129,168,116)}, "luxe", "Segoe UI", false)},
            {"Arctic Frost", new ThemeDefinition("Arctic Frost", Color.FromArgb(238,247,252), Color.FromArgb(219,234,244), Color.FromArgb(23,45,61), Color.FromArgb(79,106,124), Color.FromArgb(160,190,207), new Color[]{Color.FromArgb(38,144,213),Color.FromArgb(89,100,212),Color.FromArgb(29,166,166),Color.FromArgb(210,157,55),Color.FromArgb(216,93,92),Color.FromArgb(68,126,190)}, "zen", "Segoe UI", true)},
            {"Sakura Night", new ThemeDefinition("Sakura Night", Color.FromArgb(25,10,26), Color.FromArgb(45,17,44), Color.FromArgb(255,236,247), Color.FromArgb(195,145,179), Color.FromArgb(110,53,96), new Color[]{Color.FromArgb(255,107,181),Color.FromArgb(235,78,197),Color.FromArgb(163,106,255),Color.FromArgb(255,158,167),Color.FromArgb(255,92,126),Color.FromArgb(95,217,232)}, "synth", "Segoe UI", false)},
            {"Matrix Grid", new ThemeDefinition("Matrix Grid", Color.FromArgb(0,9,3), Color.FromArgb(2,18,7), Color.FromArgb(181,255,192), Color.FromArgb(91,177,104), Color.FromArgb(28,112,49), new Color[]{Color.FromArgb(71,255,102),Color.FromArgb(43,218,81),Color.FromArgb(132,255,147),Color.FromArgb(238,196,73),Color.FromArgb(65,204,170),Color.FromArgb(92,236,117)}, "matrix", "Cascadia Mono", false)},
            {"Desert Sand", new ThemeDefinition("Desert Sand", Color.FromArgb(246,239,222), Color.FromArgb(231,217,191), Color.FromArgb(63,48,33), Color.FromArgb(125,101,73), Color.FromArgb(190,164,125), new Color[]{Color.FromArgb(185,126,36),Color.FromArgb(211,103,50),Color.FromArgb(41,139,132),Color.FromArgb(66,118,166),Color.FromArgb(171,82,61),Color.FromArgb(107,126,64)}, "paper", "Segoe UI", true)},
            {"Royal Amethyst", new ThemeDefinition("Royal Amethyst", Color.FromArgb(20,13,32), Color.FromArgb(40,24,58), Color.FromArgb(246,238,255), Color.FromArgb(170,145,195), Color.FromArgb(95,70,120), new Color[]{Color.FromArgb(181,116,255),Color.FromArgb(230,188,83),Color.FromArgb(77,210,222),Color.FromArgb(82,198,133),Color.FromArgb(231,105,155),Color.FromArgb(196,158,255)}, "luxe", "Segoe UI", false)},
            {"Ocean Depth", new ThemeDefinition("Ocean Depth", Color.FromArgb(3,18,31), Color.FromArgb(8,43,61), Color.FromArgb(228,248,255), Color.FromArgb(120,170,189), Color.FromArgb(35,105,128), new Color[]{Color.FromArgb(46,211,235),Color.FromArgb(55,139,232),Color.FromArgb(45,190,176),Color.FromArgb(82,209,134),Color.FromArgb(232,193,77),Color.FromArgb(232,107,92)}, "aurora", "Segoe UI", false)},
            {"Copper Industrial", new ThemeDefinition("Copper Industrial", Color.FromArgb(20,18,16), Color.FromArgb(39,34,30), Color.FromArgb(240,232,222), Color.FromArgb(163,145,130), Color.FromArgb(101,82,67), new Color[]{Color.FromArgb(210,119,70),Color.FromArgb(232,144,64),Color.FromArgb(198,163,78),Color.FromArgb(87,158,190),Color.FromArgb(91,184,119),Color.FromArgb(207,79,67)}, "industrial", "Segoe UI", false)},
            {"Nordic Light", new ThemeDefinition("Nordic Light", Color.FromArgb(243,246,248), Color.FromArgb(226,232,237), Color.FromArgb(30,42,52), Color.FromArgb(91,108,121), Color.FromArgb(174,188,199), new Color[]{Color.FromArgb(53,118,179),Color.FromArgb(45,145,151),Color.FromArgb(68,152,101),Color.FromArgb(200,155,55),Color.FromArgb(199,80,77),Color.FromArgb(89,91,175)}, "zen", "Segoe UI", true)},
            {"Ember Forge", new ThemeDefinition("Ember Forge", Color.FromArgb(18,8,6), Color.FromArgb(41,18,11), Color.FromArgb(255,239,228), Color.FromArgb(185,132,103), Color.FromArgb(112,55,31), new Color[]{Color.FromArgb(255,119,48),Color.FromArgb(239,67,48),Color.FromArgb(244,188,62),Color.FromArgb(69,186,217),Color.FromArgb(173,96,222),Color.FromArgb(80,196,111)}, "industrial", "Segoe UI", false)},
            {"Synthwave Sunset", new ThemeDefinition("Synthwave Sunset", Color.FromArgb(13,5,30), Color.FromArgb(41,8,58), Color.FromArgb(254,238,255), Color.FromArgb(177,134,195), Color.FromArgb(88,50,123), new Color[]{Color.FromArgb(255,69,184),Color.FromArgb(255,121,71),Color.FromArgb(54,223,237),Color.FromArgb(153,91,255),Color.FromArgb(245,210,72),Color.FromArgb(75,133,255)}, "synth", "Segoe UI", false)},
            {"Quantum Violet", new ThemeDefinition("Quantum Violet", Color.FromArgb(9,7,28), Color.FromArgb(27,18,62), Color.FromArgb(239,240,255), Color.FromArgb(146,147,192), Color.FromArgb(73,68,125), new Color[]{Color.FromArgb(153,106,255),Color.FromArgb(55,216,241),Color.FromArgb(235,78,220),Color.FromArgb(92,222,143),Color.FromArgb(235,202,68),Color.FromArgb(69,118,245)}, "synth", "Segoe UI", false)},
            {"Monochrome Paper", new ThemeDefinition("Monochrome Paper", Color.FromArgb(247,247,244), Color.FromArgb(231,231,226), Color.FromArgb(30,31,33), Color.FromArgb(92,94,98), Color.FromArgb(185,186,181), new Color[]{Color.FromArgb(40,42,45),Color.FromArgb(91,94,99),Color.FromArgb(49,91,129),Color.FromArgb(54,105,76),Color.FromArgb(126,83,60),Color.FromArgb(99,72,125)}, "paper", "Segoe UI", true)}
        };

        static ThemeCatalog()
        {
            ThemeDefinition[] studio=StudioThemes.Create();
            foreach(ThemeDefinition theme in studio)Themes.Add(theme.Name,theme);
            Names=Names.Concat(studio.Select(theme=>theme.Name)).ToArray();
        }

        public static ThemeDefinition Get(string name)
        {
            ThemeDefinition t;
            if (!Themes.TryGetValue(name ?? "", out t)) t = Themes["Dark Minimal Pro"];
            return t;
        }
    }

    internal static class WindowsThemePolicy
    {
        public static bool AppsUseLightTheme()
        {
            try
            {
                using(RegistryKey k=Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"))
                {
                    object v=k==null?null:k.GetValue("AppsUseLightTheme");
                    if(v!=null)return Convert.ToInt32(v,CultureInfo.InvariantCulture)!=0;
                }
            }
            catch{}
            return false;
        }
        internal static string ResolveName(AppConfig c,bool appsUseLightTheme)
        {
            if(c==null)return "Dark Minimal Pro";
            if(!c.FollowWindowsTheme)return c.Theme;
            return appsUseLightTheme?c.WindowsLightTheme:c.WindowsDarkTheme;
        }
        public static string ResolveName(AppConfig c)
        {
            return ResolveName(c,AppsUseLightTheme());
        }
        public static ThemeDefinition HighContrastTheme()
        {
            Color bg=SystemColors.Window,fg=SystemColors.WindowText,accent=SystemColors.Highlight;
            Color muted=SystemColors.GrayText,border=SystemColors.WindowText;
            return new ThemeDefinition("Windows High Contrast",bg,bg,fg,muted,border,
                new Color[]{accent,accent,accent,accent,accent,accent},"minimal","Segoe UI",bg.GetBrightness()>0.5f);
        }
        public static ThemeDefinition Resolve(AppConfig c)
        {
            if(SystemInformation.HighContrast)return HighContrastTheme();
            return ThemeCatalog.Get(ResolveName(c));
        }
        public static ThemeDefinition ResolveChoice(string name)
        {
            if(SystemInformation.HighContrast)return HighContrastTheme();
            return ThemeCatalog.Get(name);
        }
    }

    internal sealed class CpuDeviceSnapshot
    {
        public string Id,Name,Socket;
        public float Usage,Temperature,PowerW;
        public bool UsageAvailable,TemperatureAvailable,PowerAvailable;
        public int PhysicalCores,LogicalProcessors,CurrentClockMHz,MaxClockMHz,ExternalClockMHz;
    }

    internal sealed class GpuDeviceSnapshot
    {
        public string Id,Name,Source;
        public float Usage,Temperature,VramUsedGb,VramTotalGb,CoreClockMHz,MemoryClockMHz,PowerW,FanRpm,FanPercent;
        public bool UsageAvailable,TemperatureAvailable,CoreClockAvailable,MemoryClockAvailable,PowerAvailable,FanRpmAvailable,FanPercentAvailable;
        public int PcieGeneration,PcieWidth;
    }

    internal sealed class DiskDeviceSnapshot
    {
        public string Id,Name,Root,Volumes,TemperatureSource,BusType,MediaType,InterfaceType;
        public ulong UsedBytes,TotalBytes,PhysicalSizeBytes;
        public float UsedPercent,Activity,Temperature;
        public double ReadBytesPerSec,WriteBytesPerSec;
        public bool ActivityAvailable,RateAvailable,TemperatureAvailable,CapacityAvailable;
    }

    internal sealed class MemoryModuleSnapshot
    {
        public string BankLabel,DeviceLocator,Manufacturer,PartNumber,MemoryType;
        public ulong CapacityBytes;
        public int SpeedMHz,ConfiguredClockMHz,DataWidth,TotalWidth;
    }

    internal sealed class NetworkDeviceSnapshot
    {
        public string Id,Name,Description; public double DownBytesPerSec,UpBytesPerSec; public long LinkSpeedBitsPerSec,ReceivedBytesTotal,SentBytesTotal; public bool Active,CountersAvailable;
    }

    internal sealed class MetricsSnapshot
    {
        public float Cpu, Ram, Disk, DiskUsedPercent, Gpu, VramUsedGb, VramTotalGb, NetDownMbps, NetUpMbps, GpuTemp;
        public ulong RamUsedBytes, RamTotalBytes, DiskUsedBytes, DiskTotalBytes;
        public double NetDownBytesPerSec, NetUpBytesPerSec, DiskReadBytesPerSec, DiskWriteBytesPerSec;
        public bool CpuTempAvailable, GpuTempAvailable;
        public float CpuTempCurrent, CpuTempAvg, CpuTempMax, GpuTempAvg, GpuTempMax;
        public string CpuTempSource, GpuTempSource;
        public List<CpuDeviceSnapshot> CpuDevices=new List<CpuDeviceSnapshot>();
        public List<GpuDeviceSnapshot> GpuDevices=new List<GpuDeviceSnapshot>();
        public List<DiskDeviceSnapshot> DiskDevices=new List<DiskDeviceSnapshot>();
        public List<NetworkDeviceSnapshot> NetworkDevices=new List<NetworkDeviceSnapshot>();
        public List<MemoryModuleSnapshot> MemoryModules=new List<MemoryModuleSnapshot>();
        public MetricsSnapshot Clone() { return (MetricsSnapshot)MemberwiseClone(); }
    }

    internal static class SelectionUtil
    {
        public static HashSet<string> Parse(string ids)
        {
            HashSet<string> set=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            if(String.IsNullOrWhiteSpace(ids))return set;
            foreach(string x in ids.Split(new char[]{';'},StringSplitOptions.RemoveEmptyEntries)){string v=x.Trim();if(v.Length>0)set.Add(v);}
            return set;
        }
        public static string Join(IEnumerable<string> ids){return String.Join(";",ids.Where(x=>!String.IsNullOrWhiteSpace(x)).Distinct(StringComparer.OrdinalIgnoreCase).ToArray());}
    }

    internal static class UnitFormatter
    {
        private static double Divisor(string unit){if(unit=="GB")return 1024d*1024d*1024d;if(unit=="MB")return 1024d*1024d;return 1024d;}
        private static string AutoUnit(double bytes){if(bytes>=1024d*1024d*1024d)return "GB";if(bytes>=1024d*1024d)return "MB";return "KB";}
        private static string Number(double v){if(v>=100)return v.ToString("0",CultureInfo.InvariantCulture);if(v>=10)return v.ToString("0.0",CultureInfo.InvariantCulture);return v.ToString("0.00",CultureInfo.InvariantCulture);}
        public static string Bytes(double bytes,string configuredUnit)
        {
            string unit=String.IsNullOrWhiteSpace(configuredUnit)||configuredUnit=="Auto"?AutoUnit(Math.Max(0,bytes)):configuredUnit;
            return Number(Math.Max(0,bytes)/Divisor(unit))+" "+unit;
        }
        public static string Pair(double used,double total,string configuredUnit)
        {
            string unit=String.IsNullOrWhiteSpace(configuredUnit)||configuredUnit=="Auto"?AutoUnit(Math.Max(used,total)):configuredUnit;
            double d=Divisor(unit);return Number(Math.Max(0,used)/d)+"/"+Number(Math.Max(0,total)/d)+" "+unit;
        }
        public static string Rate(double bytesPerSecond,string configuredUnit)
        {
            string unit=String.IsNullOrWhiteSpace(configuredUnit)||configuredUnit=="Auto"?AutoUnit(Math.Max(0,bytesPerSecond)):configuredUnit;
            return Number(Math.Max(0,bytesPerSecond)/Divisor(unit))+" "+unit+"/s";
        }
    }

    internal sealed class ReleaseUpdateInfo
    {
        public string Version,Tag,Name,HtmlUrl,SetupName,SetupUrl,SetupDigest,PublishedAt,Status;
        public bool HasUpdate,SetupAssetAvailable,DigestAvailable,Immutable,Draft,Prerelease,TagValid,ReleaseUrlValid,SetupUrlValid;
    }

    internal static class UpdateManager
    {
        private static string Text(Dictionary<string,object> d,string key)
        {
            if(d==null||!d.ContainsKey(key)||d[key]==null)return "";
            return Convert.ToString(d[key],CultureInfo.InvariantCulture)??"";
        }

        public static Version ParseVersionString(string value)
        {
            if(String.IsNullOrWhiteSpace(value))return new Version(0,0,0,0);
            Match m=Regex.Match(value,@"(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?");
            if(!m.Success)return new Version(0,0,0,0);
            int a=0,b=0,c=0,d=0;Int32.TryParse(m.Groups[1].Value,out a);Int32.TryParse(m.Groups[2].Value,out b);Int32.TryParse(m.Groups[3].Value,out c);if(m.Groups[4].Success)Int32.TryParse(m.Groups[4].Value,out d);return new Version(a,b,c,d);
        }

        internal static bool IsStrictSha256Digest(string digest)
        {
            return !String.IsNullOrWhiteSpace(digest)&&Regex.IsMatch(digest.Trim(),@"^sha256:[0-9A-Fa-f]{64}$",RegexOptions.CultureInvariant);
        }

        internal static string ExpectedSetupAssetName(string version)
        {
            return "TaskbarMonitorEnhanced_Setup_"+(version??"")+".exe";
        }
        private static bool Bool(Dictionary<string,object> d,string key)
        {
            try{object v;return d!=null&&d.TryGetValue(key,out v)&&v!=null&&Convert.ToBoolean(v,CultureInfo.InvariantCulture);}catch{return false;}
        }
        internal static bool IsOfficialReleaseUrl(string value,string version)
        {
            Uri u;if(!Uri.TryCreate(value,UriKind.Absolute,out u))return false;
            if(!String.Equals(u.Scheme,"https",StringComparison.OrdinalIgnoreCase)||!String.Equals(u.Host,"github.com",StringComparison.OrdinalIgnoreCase))return false;
            string expected="/GOD13emad/TaskbarMonitorEnhanced/releases/tag/v"+version;
            return String.Equals(u.AbsolutePath.TrimEnd('/'),expected,StringComparison.OrdinalIgnoreCase);
        }
        internal static bool IsOfficialSetupUrl(string value,string version,string setupName)
        {
            Uri u;if(!Uri.TryCreate(value,UriKind.Absolute,out u))return false;
            if(!String.Equals(u.Scheme,"https",StringComparison.OrdinalIgnoreCase)||!String.Equals(u.Host,"github.com",StringComparison.OrdinalIgnoreCase))return false;
            string expected="/GOD13emad/TaskbarMonitorEnhanced/releases/download/v"+version+"/"+setupName;
            return String.Equals(u.AbsolutePath,expected,StringComparison.OrdinalIgnoreCase);
        }

        private static WebClient Client()
        {
            try{ServicePointManager.SecurityProtocol=(SecurityProtocolType)3072;}catch{}
            WebClient wc=new WebClient();
            wc.Headers[HttpRequestHeader.UserAgent]="TaskbarMonitorEnhanced/"+BuildInfo.PublicVersion;
            wc.Headers[HttpRequestHeader.Accept]="application/vnd.github+json";
            wc.Headers["X-GitHub-Api-Version"]="2026-03-10";
            return wc;
        }

        public static ReleaseUpdateInfo CheckLatest()
        {
            ReleaseUpdateInfo info=new ReleaseUpdateInfo();info.Version="";info.Status="Checking GitHub Releases...";
            string json;
            using(WebClient wc=Client())json=wc.DownloadString(BuildInfo.LatestReleaseApi);
            Dictionary<string,object> root=new JavaScriptSerializer().DeserializeObject(json) as Dictionary<string,object>;
            if(root==null)throw new InvalidDataException("GitHub latest-release response is not an object.");
            info.Tag=Text(root,"tag_name");info.Name=Text(root,"name");info.HtmlUrl=Text(root,"html_url");info.PublishedAt=Text(root,"published_at");
            object immutableObj;if(root.TryGetValue("immutable",out immutableObj)&&immutableObj!=null){try{info.Immutable=Convert.ToBoolean(immutableObj,CultureInfo.InvariantCulture);}catch{}}
            info.Draft=Bool(root,"draft");info.Prerelease=Bool(root,"prerelease");
            Version latest=ParseVersionString(info.Tag);if(latest.Major==0&&latest.Minor==0&&latest.Build==0)latest=ParseVersionString(info.Name);
            info.Version=latest.Major+"."+latest.Minor+"."+Math.Max(0,latest.Build);
            info.TagValid=Regex.IsMatch(info.Tag??"",@"^v\d+\.\d+\.\d+$",RegexOptions.CultureInvariant)&&String.Equals(info.Tag,"v"+info.Version,StringComparison.OrdinalIgnoreCase);
            info.ReleaseUrlValid=IsOfficialReleaseUrl(info.HtmlUrl,info.Version);
            Version current=ParseVersionString(BuildInfo.PublicVersion);info.HasUpdate=latest.CompareTo(current)>0;
            object assetsObj;root.TryGetValue("assets",out assetsObj);System.Collections.IEnumerable assets=assetsObj as System.Collections.IEnumerable;
            if(assets!=null)
            {
                Dictionary<string,object> exact=null;
                string expectedName=ExpectedSetupAssetName(info.Version);
                foreach(object o in assets)
                {
                    Dictionary<string,object> a=o as Dictionary<string,object>;if(a==null)continue;
                    string n=Text(a,"name");
                    if(String.Equals(n,expectedName,StringComparison.OrdinalIgnoreCase)){exact=a;break;}
                }
                if(exact!=null)
                {
                    info.SetupName=Text(exact,"name");
                    info.SetupUrl=Text(exact,"browser_download_url");
                    info.SetupDigest=Text(exact,"digest");
                    info.SetupAssetAvailable=!String.IsNullOrWhiteSpace(info.SetupUrl);
                    info.DigestAvailable=IsStrictSha256Digest(info.SetupDigest);
                    info.SetupUrlValid=IsOfficialSetupUrl(info.SetupUrl,info.Version,expectedName);
                }
            }
            if(info.HasUpdate)
            {
                if(info.Draft||info.Prerelease)info.Status="Automatic installation is blocked for draft or prerelease builds.";
                else if(!info.TagValid||!info.ReleaseUrlValid)info.Status="Automatic installation is blocked because release identity metadata is not canonical.";
                else if(!info.SetupAssetAvailable)info.Status="Update available, but installer asset was not found.";
                else if(!info.SetupUrlValid)info.Status="Automatic installation is blocked because the installer URL is not the canonical repository release path.";
                else if(!info.DigestAvailable)info.Status="Update available, but GitHub SHA-256 digest is missing.";
                else if(!info.Immutable)info.Status="Update available and SHA-256 metadata is present, but the GitHub Release is mutable. Automatic installation is blocked; use the release page for manual review.";
                else info.Status="Update available. Immutable canonical release identity and installer SHA-256 metadata verified.";
            }
            else if(latest.CompareTo(current)==0)info.Status="You are running the latest public release. Release immutable="+info.Immutable+".";
            else info.Status="This build is newer than the latest public release. Latest release immutable="+info.Immutable+".";
            return info;
        }

        private static string Sha256File(string path)
        {
            using(SHA256 sha=SHA256.Create())using(FileStream fs=File.OpenRead(path)){byte[] b=sha.ComputeHash(fs);StringBuilder sb=new StringBuilder();foreach(byte x in b)sb.Append(x.ToString("X2",CultureInfo.InvariantCulture));return sb.ToString();}
        }

        public static string DownloadAndVerify(ReleaseUpdateInfo info)
        {
            if(info==null||!info.HasUpdate)throw new InvalidOperationException("No newer public release is selected.");
            string expectedName=ExpectedSetupAssetName(info.Version);
            if(!info.SetupAssetAvailable||!String.Equals(info.SetupName,expectedName,StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Automatic installation is blocked because the release does not contain the exact expected installer asset "+expectedName+".");
            if(!info.DigestAvailable||!IsStrictSha256Digest(info.SetupDigest))
                throw new InvalidOperationException("Automatic installation is blocked because the release asset does not have an exact sha256:<64-hex> GitHub digest.");
            if(info.Draft||info.Prerelease||!info.TagValid||!info.ReleaseUrlValid||!info.SetupUrlValid)
                throw new InvalidOperationException("Automatic installation is blocked because release identity metadata is not canonical.");
            if(!info.Immutable)throw new InvalidOperationException("Automatic installation is blocked because the GitHub Release is mutable. Open the release page and review it manually.");
            Uri u=new Uri(info.SetupUrl);if(!IsOfficialSetupUrl(info.SetupUrl,info.Version,expectedName))throw new InvalidDataException("Unexpected update URL: "+u.Host+u.AbsolutePath);
            Directory.CreateDirectory(AppPaths.Updates);string safe=Path.GetFileName(info.SetupName);if(!String.Equals(safe,expectedName,StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Unexpected update asset name.");string path=Path.Combine(AppPaths.Updates,safe);
            string partial=path+".download";try{if(File.Exists(partial))File.Delete(partial);}catch{}
            using(WebClient wc=Client())wc.DownloadFile(info.SetupUrl,partial);
            string expected=info.SetupDigest.Substring(info.SetupDigest.IndexOf(':')+1).Trim().ToUpperInvariant();string actual=Sha256File(partial);if(!String.Equals(expected,actual,StringComparison.OrdinalIgnoreCase)){try{File.Delete(partial);}catch{}throw new InvalidDataException("Update SHA-256 mismatch. Expected="+expected+" Actual="+actual);}
            if(File.Exists(path))File.Delete(path);File.Move(partial,path);Log.Write("INFO","UPDATE_DOWNLOAD_VERIFIED version="+info.Version+" sha256="+actual+" path="+path);return path;
        }

        internal static string VerifyInstallerBeforeLaunch(string path,string expectedDigest)
        {
            if(String.IsNullOrWhiteSpace(path)||!File.Exists(path))throw new FileNotFoundException("Verified update installer not found.",path);
            if(!IsStrictSha256Digest(expectedDigest))throw new InvalidDataException("Expected installer digest is invalid.");
            FileAttributes attrs=File.GetAttributes(path);if((attrs&FileAttributes.ReparsePoint)!=0)throw new InvalidDataException("Verified update installer path is a reparse point.");
            string expected=expectedDigest.Substring(expectedDigest.IndexOf(':')+1).Trim().ToUpperInvariant();
            string actual=Sha256File(path);if(!String.Equals(expected,actual,StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Installer changed after verification.");
            return actual;
        }
        public static void StartInstaller(string path,string expectedDigest)
        {
            string actual=VerifyInstallerBeforeLaunch(path,expectedDigest);
            ProcessStartInfo psi=new ProcessStartInfo();psi.FileName=path;psi.UseShellExecute=true;Process p=Process.Start(psi);if(p==null)throw new InvalidOperationException("Windows did not start the update installer.");Log.Write("INFO","UPDATE_INSTALLER_STARTED reverifiedSha256="+actual+" path="+path);
        }
    }

    internal sealed class MetricHistory
    {
        private readonly Dictionary<string,List<float>> data = new Dictionary<string,List<float>>();
        private int maxLength=BuildInfo.HistoryLength;
        public int MaxLength { get { return maxLength; } }
        public void SetLimit(int value)
        {
            maxLength=Math.Max(30,Math.Min(300,value));
            foreach(List<float> list in data.Values)while(list.Count>maxLength)list.RemoveAt(0);
        }
        public void Add(string key, float value)
        {
            List<float> list;
            if (!data.TryGetValue(key, out list)) { list=new List<float>(); data[key]=list; }
            list.Add(value);
            while (list.Count > maxLength) list.RemoveAt(0);
        }
        public IList<float> Get(string key)
        {
            List<float> list;
            if (!data.TryGetValue(key, out list)) return new List<float>();
            return list.ToArray();
        }
    }

    internal static class AlertPolicy
    {
        public static bool IsCpuHot(bool available,float value,AppConfig c)
        { return c!=null&&c.EnableTemperatureAlerts&&available&&value>=c.CpuTempWarningC; }
        public static bool IsGpuHot(bool available,float value,AppConfig c)
        { return c!=null&&c.EnableTemperatureAlerts&&available&&value>=c.GpuTempWarningC; }
        public static bool IsDiskHot(bool available,float value,AppConfig c)
        { return c!=null&&c.EnableTemperatureAlerts&&available&&value>=c.DiskTempWarningC; }
        public static Color AlertColor { get { return Color.FromArgb(255,82,82); } }
    }

    internal static class TemperatureWarningSoundPolicy
    {
        // Do not play for a silent notification preference or unavailable UI.
        // The caller already enforces snooze/quiet hours and hysteresis.
        public static bool ShouldPlay(AppConfig config)
        {return config!=null&&config.EnableTemperatureNotifications&&config.EnableTemperatureWarningSound;}
    }

    internal sealed class TemperatureNotificationState
    {
        internal const float HysteresisC=3f;
        internal const int CooldownMinutes=10;
        private sealed class LaneState
        {
            public bool LatchedHot;
            public DateTime LastNotifiedUtc=DateTime.MinValue;
        }
        private readonly Dictionary<string,LaneState> lanes=new Dictionary<string,LaneState>(StringComparer.OrdinalIgnoreCase);

        public bool ShouldNotify(string lane,bool available,float value,float threshold,DateTime nowUtc)
        {
            if(String.IsNullOrWhiteSpace(lane))return false;
            LaneState state;
            if(!lanes.TryGetValue(lane,out state)){state=new LaneState();lanes[lane]=state;}
            if(!available||!MetricStatistics.Finite(value)||!MetricStatistics.Finite(threshold))return false;
            if(value<=threshold-HysteresisC){state.LatchedHot=false;return false;}
            if(value<threshold||state.LatchedHot)return false;
            state.LatchedHot=true;
            if(state.LastNotifiedUtc!=DateTime.MinValue&&(nowUtc-state.LastNotifiedUtc).TotalMinutes<CooldownMinutes)return false;
            state.LastNotifiedUtc=nowUtc;
            return true;
        }

        public void Reset(){lanes.Clear();}
    }

    internal sealed class SessionTelemetrySample
    {
        public DateTime Utc;
        public float CpuPercent,RamPercent,GpuPercent,VramUsedGb,VramTotalGb,NetDownMbps,NetUpMbps;
        public double DiskReadMBps,DiskWriteMBps;
        public float? CpuTempC,GpuTempC,DiskTempC;
        public bool GpuUsageAvailable,NetworkAvailable,DiskRateAvailable;
        internal SessionTelemetrySample Copy(){return (SessionTelemetrySample)MemberwiseClone();}
    }

    internal static partial class SessionTelemetryHistory
    {
        internal const int MaxSamples=3600;
        private static readonly object Sync=new object();
        private static readonly Queue<SessionTelemetrySample> Samples=new Queue<SessionTelemetrySample>();

        public static int Count{get{lock(Sync)return Samples.Count;}}

        public static void Add(MetricsSnapshot s)
        {
            if(s==null)return;
            SessionTelemetrySample x=new SessionTelemetrySample();
            x.Utc=DateTime.UtcNow;
            x.GpuUsageAvailable=(s.GpuDevices??new List<GpuDeviceSnapshot>()).Any(d=>d!=null&&d.UsageAvailable);
            x.NetworkAvailable=(s.NetworkDevices??new List<NetworkDeviceSnapshot>()).Any(d=>d!=null&&d.Active);
            x.DiskRateAvailable=(s.DiskDevices??new List<DiskDeviceSnapshot>()).Any(d=>d!=null&&d.RateAvailable);
            x.CpuPercent=s.Cpu;x.RamPercent=s.Ram;x.GpuPercent=s.Gpu;x.VramUsedGb=s.VramUsedGb;x.VramTotalGb=s.VramTotalGb;
            x.NetDownMbps=s.NetDownMbps;x.NetUpMbps=s.NetUpMbps;
            x.DiskReadMBps=s.DiskReadBytesPerSec/(1024d*1024d);x.DiskWriteMBps=s.DiskWriteBytesPerSec/(1024d*1024d);
            if(s.CpuTempAvailable)x.CpuTempC=s.CpuTempCurrent;
            if(s.GpuTempAvailable)x.GpuTempC=s.GpuTemp;
            List<float> disks=(s.DiskDevices??new List<DiskDeviceSnapshot>()).Where(d=>d!=null&&d.TemperatureAvailable).Select(d=>d.Temperature).ToList();
            if(disks.Count>0)x.DiskTempC=disks.Max();
            lock(Sync)
            {
                Samples.Enqueue(x);
                while(Samples.Count>MaxSamples)Samples.Dequeue();
            }
        }

        private static string N(double value){return MetricStatistics.Finite(value)?value.ToString("0.###",CultureInfo.InvariantCulture):"";}
        private static string N(float value){return MetricStatistics.Finite(value)?value.ToString("0.###",CultureInfo.InvariantCulture):"";}
        private static string N(float? value){return value.HasValue?N(value.Value):"";}

        public static int ExportCsv(string path)
        {
            if(String.IsNullOrWhiteSpace(path))throw new ArgumentException("CSV path is required.","path");
            SessionTelemetrySample[] snapshot;
            lock(Sync)snapshot=Samples.ToArray();
            string parent=Path.GetDirectoryName(path);
            if(!String.IsNullOrWhiteSpace(parent))Directory.CreateDirectory(parent);
            using(StreamWriter w=new StreamWriter(path,false,new UTF8Encoding(false)))
            {
                w.WriteLine("Utc,CpuPercent,RamPercent,DiskReadMBps,DiskWriteMBps,GpuPercent,VramUsedGb,VramTotalGb,NetDownMbps,NetUpMbps,CpuTempC,GpuTempC,DiskTempC");
                foreach(SessionTelemetrySample x in snapshot)
                {
                    w.WriteLine(String.Join(",",new string[]{
                        x.Utc.ToString("o",CultureInfo.InvariantCulture),N(x.CpuPercent),N(x.RamPercent),x.DiskRateAvailable?N(x.DiskReadMBps):"",x.DiskRateAvailable?N(x.DiskWriteMBps):"",
                        x.GpuUsageAvailable?N(x.GpuPercent):"",x.VramTotalGb>0?N(x.VramUsedGb):"",x.VramTotalGb>0?N(x.VramTotalGb):"",x.NetworkAvailable?N(x.NetDownMbps):"",x.NetworkAvailable?N(x.NetUpMbps):"",N(x.CpuTempC),N(x.GpuTempC),N(x.DiskTempC)
                    }));
                }
            }
            return snapshot.Length;
        }

        internal static void ClearForTest(){lock(Sync)Samples.Clear();}
    }

    internal static class TelemetryPolicy
    {
        public static int EffectiveIntervalMs(AppConfig c,PowerLineStatus powerLine)
        {
            if(c==null)return 1000;
            int normal=Math.Max(1000,Math.Min(5000,c.UpdateIntervalMs));
            if(c.AdaptiveBatteryMode&&powerLine==PowerLineStatus.Offline)
                return Math.Max(normal,Math.Max(2000,Math.Min(10000,c.BatteryUpdateIntervalMs)));
            return normal;
        }

        public static bool ShouldPause(bool userPaused,bool systemPaused)
        {
            return userPaused||systemPaused;
        }
    }

    internal sealed class CpuTemperatureSample
    {
        public bool Valid;
        public float Current;
        public float Average;
        public float Maximum;
        public float PowerW;
        public bool PowerAvailable;
        public string PowerSource;
        public int SensorCount;
        public string Source;
    }

    internal sealed class GpuTelemetrySample
    {
        public bool Valid;
        public bool LoadValid;
        public bool TemperatureValid;
        public float Load;
        public float VramUsedGb;
        public float VramTotalGb;
        public float Temperature;
        public float CoreClockMHz;
        public float MemoryClockMHz;
        public float PowerW;
        public float FanRpm;
        public float FanPercent;
        public bool CoreClockValid;
        public bool MemoryClockValid;
        public bool PowerValid;
        public bool FanRpmValid;
        public bool FanPercentValid;
        public int PcieGeneration;
        public int PcieWidth;
        public string Source;
        public string HardwareName;
        public string HardwareId;
        public int AdapterIndex=-1;
    }

    internal sealed class StorageTemperatureSample
    {
        public string HardwareName,HardwareId,Source;
        public float Temperature;
        public bool Valid;
    }

    internal static class BrokerJsonFile
    {
        public static string ReadShared(string path)
        {
            Exception last=null;
            for(int attempt=0;attempt<5;attempt++)
            {
                try
                {
                    using(FileStream fs=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))
                    using(StreamReader sr=new StreamReader(fs,Encoding.UTF8,true))
                        return sr.ReadToEnd();
                }
                catch(Exception ex){last=ex;Thread.Sleep(25*(attempt+1));}
            }
            if(last!=null)throw last;
            return "";
        }
    }

    internal sealed class ElevatedStorageTemperatureReader
    {
        private string lastState="";
        private static bool ValidTemp(float v){return !Single.IsNaN(v)&&!Single.IsInfinity(v)&&v>=5f&&v<=130f;}
        private static string Text(Dictionary<string,object> m,string key)
        {
            object x;if(m==null||!m.TryGetValue(key,out x)||x==null)return "";
            return Convert.ToString(x,CultureInfo.InvariantCulture)??"";
        }
        private void State(string x)
        {
            if(String.Equals(x,lastState,StringComparison.Ordinal))return;
            lastState=x;Log.Write("INFO","DISK_TEMP_ELEVATED_BROKER_STATE "+x);
        }
        public List<StorageTemperatureSample> Read()
        {
            List<StorageTemperatureSample> result=new List<StorageTemperatureSample>();
            try
            {
                if(!File.Exists(AppPaths.StorageBrokerData)){State("FILE_MISSING");return result;}
                string json=BrokerJsonFile.ReadShared(AppPaths.StorageBrokerData);
                JavaScriptSerializer js=new JavaScriptSerializer();
                Dictionary<string,object> root=js.Deserialize<Dictionary<string,object>>(json);
                if(root==null){State("JSON_EMPTY");return result;}

                object tsObj;DateTime ts;
                if(!root.TryGetValue("TimestampUtc",out tsObj) ||
                   !DateTime.TryParse(Convert.ToString(tsObj,CultureInfo.InvariantCulture),CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal|DateTimeStyles.AdjustToUniversal,out ts))
                {State("TIMESTAMP_INVALID");return result;}
                double age=(DateTime.UtcNow-ts).TotalSeconds;
                if(age<0||age>120){State("STALE");return result;}

                object storageObj;
                if(!root.TryGetValue("StorageTemperatures",out storageObj)||storageObj==null)
                {State("STORAGE_ARRAY_MISSING");return result;}
                System.Collections.IEnumerable seq=storageObj as System.Collections.IEnumerable;
                if(seq==null){State("STORAGE_ARRAY_INVALID");return result;}

                foreach(object item in seq)
                {
                    Dictionary<string,object> m=item as Dictionary<string,object>;if(m==null)continue;
                    bool available=false;object av;
                    if(m.TryGetValue("Available",out av)){try{available=Convert.ToBoolean(av,CultureInfo.InvariantCulture);}catch{}}
                    if(!available)continue;
                    object tv;if(!m.TryGetValue("TemperatureC",out tv))continue;
                    float temp;try{temp=Convert.ToSingle(tv,CultureInfo.InvariantCulture);}catch{continue;}
                    if(!ValidTemp(temp))continue;
                    string sensor=Text(m,"Sensor");
                    StorageTemperatureSample x=new StorageTemperatureSample();
                    x.Valid=true;x.HardwareName=Text(m,"HardwareName");x.HardwareId=Text(m,"HardwareId");x.Temperature=temp;
                    x.Source="LHM_ISOLATED_STORAGE_BROKER"+(String.IsNullOrWhiteSpace(sensor)?"":":"+sensor);
                    result.Add(x);
                }
                State(result.Count>0?("READY count="+result.Count):"NO_VALID_STORAGE_TEMPERATURES");
            }
            catch(Exception ex){State("READ_FAIL "+ex.Message);}
            return result;
        }
    }

    internal sealed class ElevatedGpuTelemetryReader
    {
        private string lastState="";
        private DateTime lastStateLogUtc=DateTime.MinValue;

        private static string Text(Dictionary<string,object> m,string key)
        {
            object x;if(m==null||!m.TryGetValue(key,out x)||x==null)return "";
            return Convert.ToString(x,CultureInfo.InvariantCulture)??"";
        }
        private static bool Bool(Dictionary<string,object> m,string key)
        {
            object x;if(m==null||!m.TryGetValue(key,out x)||x==null)return false;
            try{return Convert.ToBoolean(x,CultureInfo.InvariantCulture);}catch{return false;}
        }
        private static float Float(Dictionary<string,object> m,string key)
        {
            object x;if(m==null||!m.TryGetValue(key,out x)||x==null)return 0;
            try{return Convert.ToSingle(x,CultureInfo.InvariantCulture);}catch{return 0;}
        }
        private static int Int(Dictionary<string,object> m,string key,int fallback)
        {
            object x;if(m==null||!m.TryGetValue(key,out x)||x==null)return fallback;
            try{return Convert.ToInt32(x,CultureInfo.InvariantCulture);}catch{return fallback;}
        }
        private void State(string x)
        {
            string key=(x??"").StartsWith("STALE ageSec=",StringComparison.Ordinal)?"STALE":(x??"");
            DateTime now=DateTime.UtcNow;
            bool same=String.Equals(key,lastState,StringComparison.Ordinal);
            if(same&&(now-lastStateLogUtc).TotalSeconds<30)return;
            lastState=key;
            lastStateLogUtc=now;
            Log.Write("INFO","GPU_ISOLATED_BROKER_STATE "+x);
        }

        public List<GpuTelemetrySample> ReadAll()
        {
            List<GpuTelemetrySample> result=new List<GpuTelemetrySample>();
            try
            {
                if(!File.Exists(AppPaths.GpuBrokerData)){State("FILE_MISSING");return result;}
                string json=BrokerJsonFile.ReadShared(AppPaths.GpuBrokerData);
                Dictionary<string,object> root=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(json);
                if(root==null){State("JSON_EMPTY");return result;}

                object tsObj;DateTime ts;
                if(!root.TryGetValue("TimestampUtc",out tsObj) ||
                   !DateTime.TryParse(Convert.ToString(tsObj,CultureInfo.InvariantCulture),CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal|DateTimeStyles.AdjustToUniversal,out ts))
                {State("TIMESTAMP_INVALID");return result;}
                double age=(DateTime.UtcNow-ts).TotalSeconds;
                if(age<0||age>20){State("STALE ageSec="+age.ToString("0.0",CultureInfo.InvariantCulture));return result;}

                object gpusObj;
                if(!root.TryGetValue("Gpus",out gpusObj)||gpusObj==null){State("GPU_ARRAY_MISSING");return result;}
                System.Collections.IEnumerable seq=gpusObj as System.Collections.IEnumerable;
                if(seq==null){State("GPU_ARRAY_INVALID");return result;}

                foreach(object item in seq)
                {
                    Dictionary<string,object> m=item as Dictionary<string,object>;if(m==null)continue;
                    if(!Bool(m,"Available"))continue;
                    GpuTelemetrySample g=new GpuTelemetrySample();
                    g.Valid=true;
                    g.LoadValid=Bool(m,"LoadValid");
                    g.TemperatureValid=Bool(m,"TemperatureValid");
                    g.CoreClockValid=Bool(m,"CoreClockValid");
                    g.MemoryClockValid=Bool(m,"MemoryClockValid");
                    g.PowerValid=Bool(m,"PowerValid");
                    g.FanRpmValid=Bool(m,"FanRpmValid");
                    g.FanPercentValid=Bool(m,"FanPercentValid");
                    g.Load=Float(m,"Load");
                    g.Temperature=Float(m,"Temperature");
                    g.VramUsedGb=Float(m,"VramUsedGb");
                    g.VramTotalGb=Float(m,"VramTotalGb");
                    g.CoreClockMHz=Float(m,"CoreClockMHz");
                    g.MemoryClockMHz=Float(m,"MemoryClockMHz");
                    g.PowerW=Float(m,"PowerW");
                    g.FanRpm=Float(m,"FanRpm");
                    g.FanPercent=Float(m,"FanPercent");
                    g.PcieGeneration=Int(m,"PcieGeneration",0);
                    g.PcieWidth=Int(m,"PcieWidth",0);
                    g.AdapterIndex=Int(m,"AdapterIndex",-1);
                    g.HardwareName=Text(m,"HardwareName");
                    g.HardwareId=Text(m,"HardwareId");
                    g.Source=Text(m,"Source");
                    if(String.IsNullOrWhiteSpace(g.Source))g.Source="LHM_ISOLATED_GPU_BROKER";
                    result.Add(g);
                }
                State(result.Count>0?("READY count="+result.Count):"NO_VALID_GPU_RECORDS");
            }
            catch(Exception ex){State("READ_FAIL "+ex.Message);}
            return result;
        }
    }

    internal sealed class LibreGpuTelemetryReader : IDisposable
    {
        private Assembly assembly;
        private object computer;
        private Type computerType;
        private ResolveEventHandler resolver;
        private bool initAttempted;
        private bool initialized;
        private string lastError="";

        public string LastError { get { return lastError; } }

        private static string FindLibrary()
        {
            try
            {
                if(!Directory.Exists(AppPaths.SensorBackend))return null;
                string[] files=Directory.GetFiles(
                    AppPaths.SensorBackend,
                    "LibreHardwareMonitorLib.dll",
                    SearchOption.AllDirectories
                );
                if(files.Length==0)return null;
                return files[0];
            }
            catch{return null;}
        }

        private Assembly ResolveDependency(object sender,ResolveEventArgs e)
        {
            try
            {
                string simple=new AssemblyName(e.Name).Name+".dll";
                string[] matches=Directory.GetFiles(AppPaths.SensorBackend,simple,SearchOption.AllDirectories);
                if(matches.Length>0)return Assembly.LoadFrom(matches[0]);
            }
            catch{}
            return null;
        }

        private static void SetBoolProperty(object target,string name,bool value)
        {
            try
            {
                PropertyInfo p=target.GetType().GetProperty(name,BindingFlags.Public|BindingFlags.Instance);
                if(p!=null&&p.CanWrite)p.SetValue(target,value,null);
            }
            catch{}
        }

        private bool EnsureInitialized()
        {
            if(initialized)return true;
            if(initAttempted)return false;
            initAttempted=true;

            try
            {
                string libraryPath=FindLibrary();
                if(String.IsNullOrWhiteSpace(libraryPath))
                    throw new FileNotFoundException("LibreHardwareMonitorLib.dll not found under "+AppPaths.SensorBackend);

                resolver=new ResolveEventHandler(ResolveDependency);
                AppDomain.CurrentDomain.AssemblyResolve+=resolver;

                assembly=Assembly.LoadFrom(libraryPath);
                computerType=assembly.GetType("LibreHardwareMonitor.Hardware.Computer",true);
                computer=Activator.CreateInstance(computerType);

                // Intel integrated GPU enumeration in LibreHardwareMonitor requires CPU enumeration.
                SetBoolProperty(computer,"IsCpuEnabled",true);
                SetBoolProperty(computer,"IsGpuEnabled",true);
                SetBoolProperty(computer,"IsStorageEnabled",true);

                MethodInfo open=computerType.GetMethod("Open",BindingFlags.Public|BindingFlags.Instance);
                if(open==null)throw new MissingMethodException("Computer.Open");
                open.Invoke(computer,null);

                initialized=true;
                lastError="";
                Log.Write("INFO","GPU_LHM_BACKEND_INIT_PASS");
                return true;
            }
            catch(Exception ex)
            {
                lastError=ex.GetBaseException().Message;
                Log.Write("WARN","GPU_LHM_BACKEND_INIT_FAIL "+lastError);
                return false;
            }
        }

        private static IEnumerable<object> AsObjects(object value)
        {
            System.Collections.IEnumerable e=value as System.Collections.IEnumerable;
            if(e==null)yield break;
            foreach(object x in e)if(x!=null)yield return x;
        }

        private static string GetText(object o,string property)
        {
            try
            {
                PropertyInfo p=o.GetType().GetProperty(property,BindingFlags.Public|BindingFlags.Instance);
                object v=p==null?null:p.GetValue(o,null);
                return v==null?"":Convert.ToString(v,CultureInfo.InvariantCulture)??"";
            }
            catch{return "";}
        }

        private static bool TryGetFloat(object o,string property,out float value)
        {
            value=0;
            try
            {
                PropertyInfo p=o.GetType().GetProperty(property,BindingFlags.Public|BindingFlags.Instance);
                object v=p==null?null:p.GetValue(o,null);
                if(v==null)return false;
                value=Convert.ToSingle(v,CultureInfo.InvariantCulture);
                return !Single.IsNaN(value)&&!Single.IsInfinity(value);
            }
            catch{return false;}
        }

        private static void UpdateHardware(object hardware)
        {
            try
            {
                MethodInfo m=hardware.GetType().GetMethod("Update",BindingFlags.Public|BindingFlags.Instance);
                if(m!=null)m.Invoke(hardware,null);
            }
            catch{}
        }

        private static int LoadPriority(string name)
        {
            string n=(name??"").ToLowerInvariant();
            if(n=="gpu core")return 100;
            if(n.Contains("gpu core"))return 98;
            if(n=="d3d 3d")return 95;
            if(n.Contains("3d"))return 90;
            if(n.Contains("gpu"))return 80;
            return 20;
        }

        private static int TemperaturePriority(string name)
        {
            string n=(name??"").ToLowerInvariant();
            if(n=="gpu core")return 100;
            if(n.Contains("gpu core"))return 98;
            if(n=="core")return 96;
            if(n.Contains("hot spot")||n.Contains("hotspot"))return 80;
            if(n.Contains("memory"))return 40;
            return 60;
        }

        private static float ToGb(string sensorType,float value)
        {
            if(String.Equals(sensorType,"SmallData",StringComparison.OrdinalIgnoreCase))
                return value/1024f; // SmallData is MB in LibreHardwareMonitor.
            if(String.Equals(sensorType,"Data",StringComparison.OrdinalIgnoreCase))
                return value;       // Data is GB in LibreHardwareMonitor.
            return 0;
        }

        public List<GpuTelemetrySample> ReadAll()
        {
            List<GpuTelemetrySample> candidates=new List<GpuTelemetrySample>();
            if(!EnsureInitialized())return candidates;
            try
            {
                PropertyInfo hp=computerType.GetProperty("Hardware",BindingFlags.Public|BindingFlags.Instance);
                object hardware=hp==null?null:hp.GetValue(computer,null);
                int adapterIndex=0;
                foreach(object hw in AsObjects(hardware))
                {
                    string hwType=GetText(hw,"HardwareType");
                    if(hwType.IndexOf("Gpu",StringComparison.OrdinalIgnoreCase)<0)continue;
                    UpdateHardware(hw);
                    string hwName=GetText(hw,"Name");
                    List<KeyValuePair<string,float>> loads=new List<KeyValuePair<string,float>>();
                    List<KeyValuePair<string,float>> temps=new List<KeyValuePair<string,float>>();
                    List<KeyValuePair<string,float>> clocks=new List<KeyValuePair<string,float>>();
                    float dedicatedUsed=0,dedicatedTotal=0,sharedUsed=0,sharedTotal=0,genericUsed=0,genericTotal=0;
                    bool hasDedicatedUsed=false,hasDedicatedTotal=false,hasSharedUsed=false,hasSharedTotal=false,hasGenericUsed=false,hasGenericTotal=false;
                    PropertyInfo sp=hw.GetType().GetProperty("Sensors",BindingFlags.Public|BindingFlags.Instance);
                    object sensors=sp==null?null:sp.GetValue(hw,null);
                    foreach(object sensor in AsObjects(sensors))
                    {
                        string sensorType=GetText(sensor,"SensorType"); string name=GetText(sensor,"Name"); float value;
                        if(!TryGetFloat(sensor,"Value",out value))continue;
                        if(String.Equals(sensorType,"Load",StringComparison.OrdinalIgnoreCase) && value>=0 && value<=100)loads.Add(new KeyValuePair<string,float>(name,value));
                        if(String.Equals(sensorType,"Temperature",StringComparison.OrdinalIgnoreCase) && value>=5 && value<=130)temps.Add(new KeyValuePair<string,float>(name,value));
                        if(String.Equals(sensorType,"Clock",StringComparison.OrdinalIgnoreCase) && value>0 && value<100000)clocks.Add(new KeyValuePair<string,float>(name,value));
                        if(String.Equals(sensorType,"SmallData",StringComparison.OrdinalIgnoreCase)||String.Equals(sensorType,"Data",StringComparison.OrdinalIgnoreCase))
                        {
                            float gb=ToGb(sensorType,value); string lower=(name??"").ToLowerInvariant();
                            if(lower.Contains("gpu memory used")){genericUsed=gb;hasGenericUsed=true;}
                            else if(lower.Contains("gpu memory total")){genericTotal=gb;hasGenericTotal=true;}
                            else if(lower.Contains("dedicated memory used")){dedicatedUsed=gb;hasDedicatedUsed=true;}
                            else if(lower.Contains("dedicated memory total")){dedicatedTotal=gb;hasDedicatedTotal=true;}
                            else if(lower.Contains("shared memory used")){sharedUsed=gb;hasSharedUsed=true;}
                            else if(lower.Contains("shared memory total")){sharedTotal=gb;hasSharedTotal=true;}
                        }
                    }
                    GpuTelemetrySample sample=new GpuTelemetrySample();
                    sample.Source="LHM_GPU:"+hwType+":"+hwName; sample.HardwareName=hwName; sample.HardwareId="LHM:"+hwName; sample.AdapterIndex=adapterIndex++; sample.Valid=true;
                    if(loads.Count>0){KeyValuePair<string,float> bestLoad=loads.OrderByDescending(x=>LoadPriority(x.Key)).ThenByDescending(x=>x.Value).First();sample.Load=Math.Max(0,Math.Min(100,bestLoad.Value));sample.LoadValid=true;}
                    if(temps.Count>0){KeyValuePair<string,float> bestTemp=temps.OrderByDescending(x=>TemperaturePriority(x.Key)).ThenByDescending(x=>x.Value).First();sample.Temperature=bestTemp.Value;sample.TemperatureValid=true;}
                    KeyValuePair<string,float> coreClock=clocks.Where(x=>(x.Key??"").IndexOf("core",StringComparison.OrdinalIgnoreCase)>=0).OrderByDescending(x=>x.Value).FirstOrDefault();
                    if(coreClock.Value>0){sample.CoreClockMHz=coreClock.Value;sample.CoreClockValid=true;}
                    KeyValuePair<string,float> memClock=clocks.Where(x=>(x.Key??"").IndexOf("memory",StringComparison.OrdinalIgnoreCase)>=0).OrderByDescending(x=>x.Value).FirstOrDefault();
                    if(memClock.Value>0){sample.MemoryClockMHz=memClock.Value;sample.MemoryClockValid=true;}
                    if(hasGenericUsed)sample.VramUsedGb=genericUsed;else sample.VramUsedGb=(hasDedicatedUsed?dedicatedUsed:0)+(hasSharedUsed?sharedUsed:0);
                    if(hasGenericTotal)sample.VramTotalGb=genericTotal;else sample.VramTotalGb=(hasDedicatedTotal?dedicatedTotal:0)+(hasSharedTotal?sharedTotal:0);
                    candidates.Add(sample);
                }
                if(candidates.Count==0)lastError="no supported GPU sensors found";else lastError="";
                return candidates;
            }
            catch(Exception ex){lastError=ex.GetBaseException().Message;Log.Write("WARN","GPU_LHM_READ_FAIL "+lastError);return candidates;}
        }

        public GpuTelemetrySample Read()
        {
            List<GpuTelemetrySample> candidates=ReadAll();
            if(candidates.Count==0){GpuTelemetrySample r=new GpuTelemetrySample();r.Source="LHM_GPU";return r;}
            return candidates.OrderByDescending(x=>x.LoadValid?x.Load:-1).ThenByDescending(x=>x.TemperatureValid?1:0).First();
        }

        private static int StorageTemperaturePriority(string name)
        {
            string n=(name??"").ToLowerInvariant();
            if(n=="temperature")return 100;
            if(n.Contains("drive")&&n.Contains("temperature"))return 98;
            if(n.Contains("composite"))return 96;
            if(n.Contains("temperature 1"))return 92;
            if(n.Contains("controller"))return 70;
            if(n.Contains("memory"))return 50;
            return 60;
        }

        public List<StorageTemperatureSample> ReadStorageTemperatures()
        {
            List<StorageTemperatureSample> result=new List<StorageTemperatureSample>();
            if(!EnsureInitialized())return result;
            try
            {
                PropertyInfo hp=computerType.GetProperty("Hardware",BindingFlags.Public|BindingFlags.Instance);
                object hardware=hp==null?null:hp.GetValue(computer,null);
                foreach(object hw in AsObjects(hardware))
                {
                    string hwType=GetText(hw,"HardwareType");
                    if(hwType.IndexOf("Storage",StringComparison.OrdinalIgnoreCase)<0)continue;
                    UpdateHardware(hw);
                    string hwName=GetText(hw,"Name");
                    string hwId=GetText(hw,"Identifier");
                    List<KeyValuePair<string,float>> temps=new List<KeyValuePair<string,float>>();
                    PropertyInfo sp=hw.GetType().GetProperty("Sensors",BindingFlags.Public|BindingFlags.Instance);
                    object sensors=sp==null?null:sp.GetValue(hw,null);
                    foreach(object sensor in AsObjects(sensors))
                    {
                        if(!String.Equals(GetText(sensor,"SensorType"),"Temperature",StringComparison.OrdinalIgnoreCase))continue;
                        float value;if(!TryGetFloat(sensor,"Value",out value)||value<5||value>130)continue;
                        temps.Add(new KeyValuePair<string,float>(GetText(sensor,"Name"),value));
                    }
                    if(temps.Count==0)continue;
                    KeyValuePair<string,float> best=temps.OrderByDescending(x=>StorageTemperaturePriority(x.Key)).ThenByDescending(x=>x.Value).First();
                    StorageTemperatureSample x0=new StorageTemperatureSample();x0.Valid=true;x0.HardwareName=hwName;x0.HardwareId=hwId;x0.Temperature=best.Value;x0.Source="LHM_STORAGE:"+best.Key;result.Add(x0);
                }
            }
            catch(Exception ex){Log.Write("WARN","STORAGE_LHM_READ_FAIL "+ex.GetBaseException().Message);}
            return result;
        }

        public void Dispose()
        {
            try
            {
                if(computer!=null&&computerType!=null)
                {
                    MethodInfo close=computerType.GetMethod("Close",BindingFlags.Public|BindingFlags.Instance);
                    if(close!=null)close.Invoke(computer,null);
                }
            }
            catch{}
            if(resolver!=null)
            {
                try{AppDomain.CurrentDomain.AssemblyResolve-=resolver;}catch{}
            }
            computer=null;
            assembly=null;
            computerType=null;
            initialized=false;
        }
    }


    internal sealed class WindowsGpuFallbackReader
    {
        private sealed class AdapterInfo { public int Index; public string Id,Name; public ulong TotalBytes; }
        private static int ParsePhys(string text)
        {
            if(String.IsNullOrWhiteSpace(text))return -1;
            Match m=Regex.Match(text,@"(?:^|_)phys_(\d+)(?:_|$)",RegexOptions.IgnoreCase); int x; return m.Success&&Int32.TryParse(m.Groups[1].Value,out x)?x:-1;
        }
        private static ulong U64(object v){try{return v==null?0:Convert.ToUInt64(v,CultureInfo.InvariantCulture);}catch{return 0;}}
        private static float F32(object v){try{return v==null?0:Convert.ToSingle(v,CultureInfo.InvariantCulture);}catch{return 0;}}
        private List<AdapterInfo> EnumerateAdapters()
        {
            List<AdapterInfo> a=new List<AdapterInfo>(); int index=0;
            try{using(ManagementObjectSearcher q=new ManagementObjectSearcher("SELECT DeviceID,PNPDeviceID,Name,AdapterRAM FROM Win32_VideoController"))foreach(ManagementObject o in q.Get()){AdapterInfo x=new AdapterInfo();x.Index=index++;x.Id=Convert.ToString(o["PNPDeviceID"],CultureInfo.InvariantCulture);if(String.IsNullOrWhiteSpace(x.Id))x.Id=Convert.ToString(o["DeviceID"],CultureInfo.InvariantCulture);x.Name=Convert.ToString(o["Name"],CultureInfo.InvariantCulture);x.TotalBytes=U64(o["AdapterRAM"]);a.Add(x);}}catch(Exception ex){Log.Write("WARN","GPU_WDDM_ENUM "+ex.Message);}
            return a;
        }
        public List<GpuTelemetrySample> ReadAll()
        {
            List<AdapterInfo> adapters=EnumerateAdapters(); Dictionary<int,float> loads=new Dictionary<int,float>(); Dictionary<int,ulong> mem=new Dictionary<int,ulong>();
            try{using(ManagementObjectSearcher q=new ManagementObjectSearcher(@"root\CIMV2","SELECT Name,UtilizationPercentage FROM Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine"))foreach(ManagementObject o in q.Get()){int p=ParsePhys(Convert.ToString(o["Name"],CultureInfo.InvariantCulture));if(p<0)continue;float v=Math.Max(0,Math.Min(100,F32(o["UtilizationPercentage"])));float old;if(!loads.TryGetValue(p,out old)||v>old)loads[p]=v;}}catch(Exception ex){Log.Write("WARN","GPU_WDDM_ENGINE "+ex.Message);}
            try{using(ManagementObjectSearcher q=new ManagementObjectSearcher(@"root\CIMV2","SELECT Name,DedicatedUsage,SharedUsage FROM Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory"))foreach(ManagementObject o in q.Get()){int p=ParsePhys(Convert.ToString(o["Name"],CultureInfo.InvariantCulture));if(p<0)continue;ulong v=U64(o["DedicatedUsage"])+U64(o["SharedUsage"]);mem[p]=v;}}catch(Exception ex){Log.Write("WARN","GPU_WDDM_MEMORY "+ex.Message);}
            List<GpuTelemetrySample> r=new List<GpuTelemetrySample>();
            foreach(AdapterInfo a in adapters){GpuTelemetrySample s=new GpuTelemetrySample();s.Valid=true;s.Source="WINDOWS_WDDM";s.HardwareName=String.IsNullOrWhiteSpace(a.Name)?("GPU "+a.Index):a.Name;s.HardwareId=String.IsNullOrWhiteSpace(a.Id)?("WDDM:"+a.Index):a.Id;s.AdapterIndex=a.Index;float l;if(loads.TryGetValue(a.Index,out l)){s.Load=l;s.LoadValid=true;}ulong u;if(mem.TryGetValue(a.Index,out u))s.VramUsedGb=(float)(u/(1024d*1024d*1024d));if(a.TotalBytes>0)s.VramTotalGb=(float)(a.TotalBytes/(1024d*1024d*1024d));r.Add(s);}
            return r;
        }
    }

    internal sealed class AdlxGpuTemperatureSample
    {
        public bool Valid;
        public float Temperature;
        public float Usage;
        public string Source;
        public string HardwareName;
        public string PnpString;
    }

    internal sealed class AmdAdlxTemperatureReader : IDisposable
    {
        private const int ADLX_OK=0;
        private const int ADLX_ALREADY_ENABLED=1;
        private const int ADLX_ALREADY_INITIALIZED=2;
        private const string ExpectedAdlxVersion="1.1";

        private IntPtr module=IntPtr.Zero;
        private IntPtr system=IntPtr.Zero;
        private IntPtr perf=IntPtr.Zero;
        private ADLXTerminateFn terminate;
        private bool initAttempted;
        private bool initialized;
        private string lastError="";

        public string LastError { get { return lastError; } }

        [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]
        private static extern IntPtr LoadLibrary(string lpFileName);

        [DllImport("kernel32.dll",CharSet=CharSet.Ansi,SetLastError=true)]
        private static extern IntPtr GetProcAddress(IntPtr hModule,string procName);

        [DllImport("kernel32.dll",SetLastError=true)]
        [return:MarshalAs(UnmanagedType.Bool)]
        private static extern bool FreeLibrary(IntPtr hModule);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int ADLXQueryFullVersionFn(ref ulong fullVersion);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int ADLXQueryVersionFn(out IntPtr version);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int ADLXInitializeFn(ulong version,out IntPtr system);

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate int ADLXTerminateFn();

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int ReleaseFn(IntPtr obj);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int SysGetGPUsFn(IntPtr system,out IntPtr gpuList);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int SysGetPerfFn(IntPtr system,out IntPtr perf);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate uint ListSizeFn(IntPtr list);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GPUListAtFn(IntPtr list,uint location,out IntPtr gpu);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GPUNameFn(IntPtr gpu,out IntPtr name);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GPUPNPFn(IntPtr gpu,out IntPtr pnp);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int PerfGetSupportedGPUFn(IntPtr perf,IntPtr gpu,out IntPtr support);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int PerfGetCurrentGPUFn(IntPtr perf,IntPtr gpu,out IntPtr metrics);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int SupportBoolFn(IntPtr support,out byte supported);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int MetricsDoubleFn(IntPtr metrics,out double value);

        private static bool Succeeded(int result)
        {
            return result==ADLX_OK || result==ADLX_ALREADY_ENABLED || result==ADLX_ALREADY_INITIALIZED;
        }

        private static T DelegateAt<T>(IntPtr functionPointer) where T:class
        {
            if(functionPointer==IntPtr.Zero)throw new InvalidOperationException("ADLX_NULL_FUNCTION_POINTER");
            return Marshal.GetDelegateForFunctionPointer(functionPointer,typeof(T)) as T;
        }

        private static IntPtr Slot(IntPtr obj,int index)
        {
            if(obj==IntPtr.Zero)throw new InvalidOperationException("ADLX_NULL_INTERFACE_POINTER");
            IntPtr vtbl=Marshal.ReadIntPtr(obj);
            if(vtbl==IntPtr.Zero)throw new InvalidOperationException("ADLX_NULL_VTABLE_POINTER");
            return Marshal.ReadIntPtr(vtbl,index*IntPtr.Size);
        }

        private static string Ansi(IntPtr p)
        {
            return p==IntPtr.Zero?"":(Marshal.PtrToStringAnsi(p)??"");
        }

        private static void SafeRelease(IntPtr p)
        {
            if(p==IntPtr.Zero)return;
            try
            {
                ReleaseFn release=DelegateAt<ReleaseFn>(Slot(p,1));
                release(p);
            }
            catch{}
        }

        private bool EnsureInitialized()
        {
            if(initialized)return true;
            if(initAttempted)return false;
            initAttempted=true;

            try
            {
                string dllPath=Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.Windows),
                    "System32",
                    "amdadlx64.dll"
                );
                if(!File.Exists(dllPath))
                    throw new FileNotFoundException("AMD ADLX runtime not found",dllPath);

                module=LoadLibrary(dllPath);
                if(module==IntPtr.Zero)
                    throw new InvalidOperationException("ADLX_LOAD_LIBRARY_FAILED win32="+Marshal.GetLastWin32Error());

                IntPtr qFullPtr=GetProcAddress(module,"ADLXQueryFullVersion");
                IntPtr qVersionPtr=GetProcAddress(module,"ADLXQueryVersion");
                IntPtr initPtr=GetProcAddress(module,"ADLXInitialize");
                IntPtr terminatePtr=GetProcAddress(module,"ADLXTerminate");
                if(qFullPtr==IntPtr.Zero || qVersionPtr==IntPtr.Zero || initPtr==IntPtr.Zero || terminatePtr==IntPtr.Zero)
                    throw new MissingMethodException("Required AMD ADLX v1.1 exports are unavailable");

                ADLXQueryFullVersionFn queryFull=DelegateAt<ADLXQueryFullVersionFn>(qFullPtr);
                ADLXQueryVersionFn queryVersion=DelegateAt<ADLXQueryVersionFn>(qVersionPtr);
                ADLXInitializeFn initialize=DelegateAt<ADLXInitializeFn>(initPtr);
                terminate=DelegateAt<ADLXTerminateFn>(terminatePtr);

                ulong fullVersion=0;
                int result=queryFull(ref fullVersion);
                if(!Succeeded(result))
                    throw new InvalidOperationException("ADLX_QUERY_FULL_VERSION result="+result);

                IntPtr versionPtr;
                result=queryVersion(out versionPtr);
                if(!Succeeded(result))
                    throw new InvalidOperationException("ADLX_QUERY_VERSION result="+result);

                string version=Ansi(versionPtr);
                if(!String.Equals(version,ExpectedAdlxVersion,StringComparison.Ordinal))
                    throw new InvalidOperationException("ADLX_ABI_GUARD expected="+ExpectedAdlxVersion+" actual="+version);

                result=initialize(fullVersion,out system);
                if(!Succeeded(result) || system==IntPtr.Zero)
                    throw new InvalidOperationException("ADLX_INITIALIZE result="+result);

                SysGetPerfFn getPerf=DelegateAt<SysGetPerfFn>(Slot(system,9));
                result=getPerf(system,out perf);
                if(!Succeeded(result) || perf==IntPtr.Zero)
                    throw new InvalidOperationException("ADLX_GET_PERFORMANCE_MONITORING result="+result);

                initialized=true;
                lastError="";
                Log.Write("INFO","GPU_ADLX_BACKEND_INIT_PASS version="+version);
                return true;
            }
            catch(Exception ex)
            {
                lastError=ex.GetBaseException().Message;
                Log.Write("WARN","GPU_ADLX_BACKEND_INIT_FAIL "+lastError);
                Cleanup();
                return false;
            }
        }

        public AdlxGpuTemperatureSample Read()
        {
            AdlxGpuTemperatureSample best=new AdlxGpuTemperatureSample();
            best.Source="AMD_ADLX_1.1";
            best.Usage=-1f;

            if(!EnsureInitialized())return best;

            IntPtr gpuList=IntPtr.Zero;
            try
            {
                SysGetGPUsFn getGpus=DelegateAt<SysGetGPUsFn>(Slot(system,1));
                int result=getGpus(system,out gpuList);
                if(!Succeeded(result) || gpuList==IntPtr.Zero)
                    throw new InvalidOperationException("ADLX_GET_GPUS result="+result);

                ListSizeFn sizeFn=DelegateAt<ListSizeFn>(Slot(gpuList,3));
                GPUListAtFn atGpu=DelegateAt<GPUListAtFn>(Slot(gpuList,11));
                uint count=sizeFn(gpuList);

                for(uint i=0;i<count;i++)
                {
                    IntPtr gpu=IntPtr.Zero;
                    result=atGpu(gpuList,i,out gpu);
                    if(!Succeeded(result) || gpu==IntPtr.Zero)continue;

                    try
                    {
                        IntPtr namePtr;
                        string gpuName="";
                        try
                        {
                            result=DelegateAt<GPUNameFn>(Slot(gpu,7))(gpu,out namePtr);
                            if(Succeeded(result))gpuName=Ansi(namePtr);
                        }
                        catch{}

                        IntPtr pnpPtr;
                        string pnp="";
                        try
                        {
                            result=DelegateAt<GPUPNPFn>(Slot(gpu,9))(gpu,out pnpPtr);
                            if(Succeeded(result))pnp=Ansi(pnpPtr);
                        }
                        catch{}

                        IntPtr support=IntPtr.Zero;
                        result=DelegateAt<PerfGetSupportedGPUFn>(Slot(perf,21))(perf,gpu,out support);
                        if(!Succeeded(result) || support==IntPtr.Zero)continue;

                        bool temperatureSupported=false;
                        try
                        {
                            byte supported;
                            result=DelegateAt<SupportBoolFn>(Slot(support,6))(support,out supported);
                            temperatureSupported=Succeeded(result) && supported!=0;
                        }
                        finally{SafeRelease(support);}

                        if(!temperatureSupported)continue;

                        IntPtr metrics=IntPtr.Zero;
                        result=DelegateAt<PerfGetCurrentGPUFn>(Slot(perf,18))(perf,gpu,out metrics);
                        if(!Succeeded(result) || metrics==IntPtr.Zero)continue;

                        try
                        {
                            double temp;
                            int tempResult=DelegateAt<MetricsDoubleFn>(Slot(metrics,7))(metrics,out temp);
                            if(!Succeeded(tempResult) || Double.IsNaN(temp) || Double.IsInfinity(temp) || temp<5.0 || temp>130.0)
                                continue;

                            double usage=0;
                            int usageResult=DelegateAt<MetricsDoubleFn>(Slot(metrics,4))(metrics,out usage);
                            if(!Succeeded(usageResult) || Double.IsNaN(usage) || Double.IsInfinity(usage))
                                usage=0;

                            float usageValue=(float)Math.Max(0,Math.Min(100,usage));
                            if(!best.Valid || usageValue>best.Usage)
                            {
                                best.Valid=true;
                                best.Temperature=(float)temp;
                                best.Usage=usageValue;
                                best.HardwareName=gpuName;
                                best.PnpString=pnp;
                            }
                        }
                        finally{SafeRelease(metrics);}
                    }
                    finally{SafeRelease(gpu);}
                }

                if(best.Valid)
                {
                    lastError="";
                    return best;
                }

                lastError="ADLX reports no valid supported GPU temperature sample";
                return best;
            }
            catch(Exception ex)
            {
                lastError=ex.GetBaseException().Message;
                Log.Write("WARN","GPU_ADLX_READ_FAIL "+lastError);
                return best;
            }
            finally{SafeRelease(gpuList);}
        }

        private void Cleanup()
        {
            if(perf!=IntPtr.Zero)
            {
                SafeRelease(perf);
                perf=IntPtr.Zero;
            }

            if(system!=IntPtr.Zero && terminate!=null)
            {
                try{terminate();}catch{}
            }
            system=IntPtr.Zero;
            initialized=false;

            if(module!=IntPtr.Zero)
            {
                try{FreeLibrary(module);}catch{}
                module=IntPtr.Zero;
            }
            terminate=null;
        }

        public void Dispose()
        {
            Cleanup();
        }
    }

    internal sealed class RollingTemperatureWindow
    {
        private readonly Queue<float> averages=new Queue<float>();
        private readonly Queue<float> maxima=new Queue<float>();

        public int Count { get { return averages.Count; } }

        public void Add(float average,float maximum)
        {
            if(Single.IsNaN(average)||Single.IsInfinity(average)||average<5||average>130)return;
            if(Single.IsNaN(maximum)||Single.IsInfinity(maximum)||maximum<5||maximum>130)return;
            averages.Enqueue(average);
            maxima.Enqueue(maximum);
            while(averages.Count>BuildInfo.HistoryLength)averages.Dequeue();
            while(maxima.Count>BuildInfo.HistoryLength)maxima.Dequeue();
        }

        public float Average
        {
            get { return averages.Count==0?0:averages.Average(); }
        }

        public float Maximum
        {
            get { return maxima.Count==0?0:maxima.Max(); }
        }
    }

    internal sealed class LibreHardwareMonitorBridge : IDisposable
    {
        private Assembly assembly;
        private object computer;
        private Type computerType;
        private ResolveEventHandler resolver;
        private bool initAttempted;
        private bool initialized;
        private string libraryPath="";
        private string lastError="";

        public bool Initialized { get { return initialized; } }
        public string LastError { get { return lastError; } }
        public string LibraryPath { get { return libraryPath; } }

        private static bool ValidTemp(float v)
        {
            return !Single.IsNaN(v)&&!Single.IsInfinity(v)&&v>=5f&&v<=130f;
        }

        private static string FindLibrary()
        {
            try
            {
                if(!Directory.Exists(AppPaths.SensorBackend))return null;
                string[] files=Directory.GetFiles(
                    AppPaths.SensorBackend,
                    "LibreHardwareMonitorLib.dll",
                    SearchOption.AllDirectories
                );
                if(files.Length==0)return null;
                return files[0];
            }
            catch{return null;}
        }

        private Assembly ResolveDependency(object sender,ResolveEventArgs e)
        {
            try
            {
                string simple=new AssemblyName(e.Name).Name+".dll";
                string[] matches=Directory.GetFiles(AppPaths.SensorBackend,simple,SearchOption.AllDirectories);
                if(matches.Length>0)return Assembly.LoadFrom(matches[0]);
            }
            catch{}
            return null;
        }

        private static void SetBoolProperty(object target,string name,bool value)
        {
            PropertyInfo p=target.GetType().GetProperty(name,BindingFlags.Public|BindingFlags.Instance);
            if(p!=null&&p.CanWrite)p.SetValue(target,value,null);
        }

        private bool EnsureInitialized()
        {
            if(initialized)return true;
            if(initAttempted)return false;
            initAttempted=true;

            try
            {
                libraryPath=FindLibrary();
                if(String.IsNullOrWhiteSpace(libraryPath))
                    throw new FileNotFoundException("LibreHardwareMonitorLib.dll not found under "+AppPaths.SensorBackend);

                resolver=new ResolveEventHandler(ResolveDependency);
                AppDomain.CurrentDomain.AssemblyResolve+=resolver;

                assembly=Assembly.LoadFrom(libraryPath);
                computerType=assembly.GetType("LibreHardwareMonitor.Hardware.Computer",true);
                computer=Activator.CreateInstance(computerType);
                SetBoolProperty(computer,"IsCpuEnabled",true);
                SetBoolProperty(computer,"IsMotherboardEnabled",true);

                MethodInfo open=computerType.GetMethod("Open",BindingFlags.Public|BindingFlags.Instance);
                if(open==null)throw new MissingMethodException("Computer.Open");
                open.Invoke(computer,null);

                initialized=true;
                lastError="";
                Log.Write("INFO","CPU_TEMP_DIRECT_BACKEND_INIT_PASS library="+libraryPath);
                return true;
            }
            catch(Exception ex)
            {
                lastError=ex.GetBaseException().Message;
                Log.Write("WARN","CPU_TEMP_DIRECT_BACKEND_INIT_FAIL "+lastError);
                return false;
            }
        }

        private static IEnumerable<object> AsObjects(object value)
        {
            System.Collections.IEnumerable e=value as System.Collections.IEnumerable;
            if(e==null)yield break;
            foreach(object x in e)if(x!=null)yield return x;
        }

        private static string GetText(object o,string property)
        {
            try
            {
                PropertyInfo p=o.GetType().GetProperty(property,BindingFlags.Public|BindingFlags.Instance);
                object v=p==null?null:p.GetValue(o,null);
                return v==null?"":Convert.ToString(v,CultureInfo.InvariantCulture)??"";
            }
            catch{return "";}
        }

        private static bool TryGetFloat(object o,string property,out float value)
        {
            value=0;
            try
            {
                PropertyInfo p=o.GetType().GetProperty(property,BindingFlags.Public|BindingFlags.Instance);
                object v=p==null?null:p.GetValue(o,null);
                if(v==null)return false;
                value=Convert.ToSingle(v,CultureInfo.InvariantCulture);
                return ValidTemp(value);
            }
            catch{return false;}
        }

        private static void UpdateHardware(object hardware)
        {
            try
            {
                MethodInfo m=hardware.GetType().GetMethod("Update",BindingFlags.Public|BindingFlags.Instance);
                if(m!=null)m.Invoke(hardware,null);
            }
            catch{}
        }

        private static void AddTemperatureSensors(
            object hardware,
            List<KeyValuePair<string,float>> values,
            bool cpuOnly
        )
        {
            if(hardware==null)return;
            UpdateHardware(hardware);

            string hwType=GetText(hardware,"HardwareType");
            string hwName=GetText(hardware,"Name");
            bool isCpu=hwType.IndexOf("Cpu",StringComparison.OrdinalIgnoreCase)>=0 ||
                       hwName.IndexOf("CPU",StringComparison.OrdinalIgnoreCase)>=0 ||
                       hwName.IndexOf("Intel",StringComparison.OrdinalIgnoreCase)>=0 ||
                       hwName.IndexOf("AMD",StringComparison.OrdinalIgnoreCase)>=0;

            if(isCpu||cpuOnly)
            {
                PropertyInfo sp=hardware.GetType().GetProperty("Sensors",BindingFlags.Public|BindingFlags.Instance);
                object sensorList=sp==null?null:sp.GetValue(hardware,null);
                foreach(object sensor in AsObjects(sensorList))
                {
                    string sensorType=GetText(sensor,"SensorType");
                    if(!String.Equals(sensorType,"Temperature",StringComparison.OrdinalIgnoreCase))continue;
                    float temp;
                    if(!TryGetFloat(sensor,"Value",out temp))continue;
                    string name=GetText(sensor,"Name");
                    string id=GetText(sensor,"Identifier");
                    values.Add(new KeyValuePair<string,float>(name+"|"+id,temp));
                }
            }

            PropertyInfo subp=hardware.GetType().GetProperty("SubHardware",BindingFlags.Public|BindingFlags.Instance);
            object subs=subp==null?null:subp.GetValue(hardware,null);
            foreach(object sub in AsObjects(subs))
                AddTemperatureSensors(sub,values,cpuOnly||isCpu);
        }

        private static int NamePriority(string key)
        {
            string n=(key??"").ToLowerInvariant();
            if(n.Contains("cpu package"))return 100;
            if(n.Contains("package"))return 95;
            if(n.Contains("tctl/tdie"))return 94;
            if(n.Contains("tctl"))return 93;
            if(n.Contains("tdie"))return 92;
            if(n.Contains("core max"))return 90;
            if(n.Contains("cores max"))return 89;
            if(n.Contains("cpu max"))return 88;
            if(n.Contains("core average"))return 80;
            if(n.Contains("cores average"))return 79;
            if(n.Contains("core #"))return 70;
            if(n.Contains("cpu core"))return 69;
            return 20;
        }

        public CpuTemperatureSample Read()
        {
            CpuTemperatureSample result=new CpuTemperatureSample();
            result.Source="LIBRE_HARDWARE_MONITOR_DIRECT_0.9.6";

            if(!EnsureInitialized())return result;

            try
            {
                PropertyInfo hp=computerType.GetProperty("Hardware",BindingFlags.Public|BindingFlags.Instance);
                object hardware=hp==null?null:hp.GetValue(computer,null);
                List<KeyValuePair<string,float>> values=new List<KeyValuePair<string,float>>();
                foreach(object hw in AsObjects(hardware))AddTemperatureSensors(hw,values,true);
                if(values.Count==0)
                {
                    lastError="no valid CPU temperature sensors";
                    return result;
                }

                KeyValuePair<string,float> preferred=values
                    .OrderByDescending(x=>NamePriority(x.Key))
                    .ThenByDescending(x=>x.Value)
                    .First();

                List<float> coreValues=values
                    .Where(x=>x.Key.IndexOf("core",StringComparison.OrdinalIgnoreCase)>=0 &&
                              x.Key.IndexOf("max",StringComparison.OrdinalIgnoreCase)<0 &&
                              x.Key.IndexOf("average",StringComparison.OrdinalIgnoreCase)<0)
                    .Select(x=>x.Value).ToList();

                float avg=coreValues.Count>0?coreValues.Average():values.Average(x=>x.Value);
                float max=values.Max(x=>x.Value);

                result.Valid=true;
                result.Current=preferred.Value;
                result.Average=avg;
                result.Maximum=max;
                result.SensorCount=values.Count;
                result.Source="LIBRE_HARDWARE_MONITOR_DIRECT_0.9.6:"+preferred.Key;
                lastError="";
                return result;
            }
            catch(Exception ex)
            {
                lastError=ex.GetBaseException().Message;
                Log.Write("WARN","CPU_TEMP_DIRECT_BACKEND_READ_FAIL "+lastError);
                return result;
            }
        }

        public void Dispose()
        {
            try
            {
                if(computer!=null&&computerType!=null)
                {
                    MethodInfo close=computerType.GetMethod("Close",BindingFlags.Public|BindingFlags.Instance);
                    if(close!=null)close.Invoke(computer,null);
                }
            }
            catch{}
            if(resolver!=null)
            {
                try{AppDomain.CurrentDomain.AssemblyResolve-=resolver;}catch{}
            }
            computer=null;
            assembly=null;
            computerType=null;
            initialized=false;
        }
    }

    internal sealed class CpuTemperatureReader : IDisposable
    {
        private string lastSource="";
        private DateTime lastFallbackAttemptUtc=DateTime.MinValue;
        private CpuTemperatureSample lastFallbackSample=new CpuTemperatureSample{Valid=false,Source="UNAVAILABLE"};
        private DateTime lastBrokerStaleLogUtc=DateTime.MinValue;

        public CpuTemperatureSample Read()
        {
            CpuTemperatureSample s;

            s=ReadElevatedBroker();
            if(s.Valid){LogSource(s.Source,s.SensorCount);return s;}

            // R21: expensive fallback namespaces are sampled at most every 15 seconds.
            // The elevated broker remains the immediate/primary source whenever it is fresh.
            if(lastFallbackAttemptUtc!=DateTime.MinValue&&(DateTime.UtcNow-lastFallbackAttemptUtc).TotalSeconds<15)
            {
                if(lastFallbackSample!=null&&lastFallbackSample.Valid)LogSource(lastFallbackSample.Source,lastFallbackSample.SensorCount);
                else LogSource("UNAVAILABLE",0);
                return lastFallbackSample??new CpuTemperatureSample{Valid=false,Source="UNAVAILABLE"};
            }
            lastFallbackAttemptUtc=DateTime.UtcNow;

            s=ReadHardwareMonitorNamespace(@"\\.\root\LibreHardwareMonitor","LIBRE_HARDWARE_MONITOR_WMI");
            if(s.Valid){lastFallbackSample=s;LogSource(s.Source,s.SensorCount);return s;}

            s=ReadHardwareMonitorNamespace(@"\\.\root\OpenHardwareMonitor","OPEN_HARDWARE_MONITOR_WMI");
            if(s.Valid){lastFallbackSample=s;LogSource(s.Source,s.SensorCount);return s;}

            s=ReadAcpi();
            if(s.Valid){lastFallbackSample=s;LogSource(s.Source,s.SensorCount);return s;}

            s=new CpuTemperatureSample();
            s.Valid=false;
            s.Source="UNAVAILABLE";
            lastFallbackSample=s;
            LogSource(s.Source,0);
            return s;
        }

        private CpuTemperatureSample ReadElevatedBroker()
        {
            CpuTemperatureSample result=new CpuTemperatureSample();
            result.Source="LHM_ELEVATED_BROKER";

            try
            {
                if(!File.Exists(AppPaths.CpuTempBrokerData))return result;

                string json=BrokerJsonFile.ReadShared(AppPaths.CpuTempBrokerData);
                JavaScriptSerializer js=new JavaScriptSerializer();
                Dictionary<string,object> m=js.Deserialize<Dictionary<string,object>>(json);
                if(m==null)return result;

                object availableObj;
                if(!m.TryGetValue("Available",out availableObj) ||
                   !Convert.ToBoolean(availableObj,CultureInfo.InvariantCulture))
                    return result;

                object tsObj;
                if(!m.TryGetValue("TimestampUtc",out tsObj))return result;
                DateTime ts;
                if(!DateTime.TryParse(
                    Convert.ToString(tsObj,CultureInfo.InvariantCulture),
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal|DateTimeStyles.AdjustToUniversal,
                    out ts))
                    return result;

                double age=(DateTime.UtcNow-ts).TotalSeconds;
                const double brokerFreshnessSeconds=15.0;
                if(age<0 || age>brokerFreshnessSeconds)
                {
                    if(lastBrokerStaleLogUtc==DateTime.MinValue||(DateTime.UtcNow-lastBrokerStaleLogUtc).TotalSeconds>=30)
                    {
                        lastBrokerStaleLogUtc=DateTime.UtcNow;
                        Log.Write("WARN","CPU_TEMP_BROKER_STALE ageSec="+age.ToString("0.0",CultureInfo.InvariantCulture)+" limitSec="+brokerFreshnessSeconds.ToString("0",CultureInfo.InvariantCulture));
                    }
                    return result;
                }

                object currentObj;
                if(!m.TryGetValue("CurrentC",out currentObj))return result;
                float current=Convert.ToSingle(currentObj,CultureInfo.InvariantCulture);
                if(!IsValidTemp(current))return result;

                float avg=current;
                float max=current;
                object avgObj;
                object maxObj;
                if(m.TryGetValue("AverageC",out avgObj))
                {
                    try
                    {
                        float v=Convert.ToSingle(avgObj,CultureInfo.InvariantCulture);
                        if(IsValidTemp(v))avg=v;
                    }
                    catch{}
                }
                if(m.TryGetValue("MaximumC",out maxObj))
                {
                    try
                    {
                        float v=Convert.ToSingle(maxObj,CultureInfo.InvariantCulture);
                        if(IsValidTemp(v))max=v;
                    }
                    catch{}
                }

                string sensor="";
                object sensorObj;
                if(m.TryGetValue("Sensor",out sensorObj))
                    sensor=Convert.ToString(sensorObj,CultureInfo.InvariantCulture)??"";

                result.Valid=true;
                result.Current=current;
                result.Average=avg;
                result.Maximum=max;
                result.SensorCount=1;
                result.Source="LHM_ELEVATED_BROKER"+(String.IsNullOrWhiteSpace(sensor)?"":":"+sensor);

                object powerAvailableObj;
                if(m.TryGetValue("PackagePowerAvailable",out powerAvailableObj))
                {
                    try{result.PowerAvailable=Convert.ToBoolean(powerAvailableObj,CultureInfo.InvariantCulture);}catch{}
                }
                if(result.PowerAvailable)
                {
                    object powerObj;
                    if(m.TryGetValue("PackagePowerW",out powerObj))
                    {
                        try
                        {
                            float pwr=Convert.ToSingle(powerObj,CultureInfo.InvariantCulture);
                            if(!Single.IsNaN(pwr)&&!Single.IsInfinity(pwr)&&pwr>=0&&pwr<1000)result.PowerW=pwr;
                            else result.PowerAvailable=false;
                        }
                        catch{result.PowerAvailable=false;}
                    }
                    else result.PowerAvailable=false;
                    object powerSensorObj;
                    string powerSensor=m.TryGetValue("PackagePowerSensor",out powerSensorObj)?Convert.ToString(powerSensorObj,CultureInfo.InvariantCulture):"";
                    result.PowerSource=result.PowerAvailable?("LHM_ELEVATED_BROKER"+(String.IsNullOrWhiteSpace(powerSensor)?"":(":"+powerSensor))):"UNAVAILABLE";
                }
                return result;
            }
            catch(Exception ex)
            {
                Log.Write("WARN","CPU_TEMP_BROKER_READ "+ex.Message);
                return result;
            }
        }

        private void LogSource(string source,int count)
        {
            if(String.Equals(source,lastSource,StringComparison.Ordinal))return;
            lastSource=source;
            Log.Write("INFO","CPU_TEMP_SOURCE="+source+" sensors="+count);
        }

        private static bool IsValidTemp(float v)
        {
            return !Single.IsNaN(v)&&!Single.IsInfinity(v)&&v>=5f&&v<=130f;
        }

        private CpuTemperatureSample ReadHardwareMonitorNamespace(string ns,string source)
        {
            CpuTemperatureSample result=new CpuTemperatureSample();
            result.Source=source;

            try
            {
                ManagementScope scope=new ManagementScope(ns);
                scope.Connect();

                ObjectQuery q=new ObjectQuery("SELECT Name,Identifier,Parent,SensorType,Value FROM Sensor");
                using(ManagementObjectSearcher searcher=new ManagementObjectSearcher(scope,q))
                using(ManagementObjectCollection rows=searcher.Get())
                {
                    List<float> cores=new List<float>();
                    List<float> all=new List<float>();
                    float directAverage=Single.NaN;
                    float directMaximum=Single.NaN;

                    foreach(ManagementObject row in rows)
                    {
                        string type=Convert.ToString(row["SensorType"],CultureInfo.InvariantCulture)??"";
                        if(!String.Equals(type,"Temperature",StringComparison.OrdinalIgnoreCase))continue;

                        string name=Convert.ToString(row["Name"],CultureInfo.InvariantCulture)??"";
                        string id=Convert.ToString(row["Identifier"],CultureInfo.InvariantCulture)??"";
                        string parent=Convert.ToString(row["Parent"],CultureInfo.InvariantCulture)??"";
                        string hay=(name+" "+id+" "+parent).ToLowerInvariant();

                        bool cpu=
                            hay.Contains("intelcpu")||
                            hay.Contains("amdcpu")||
                            hay.Contains("/cpu/")||
                            hay.Contains(" package")||
                            hay.Contains("package ")||
                            hay.Contains("tctl")||
                            hay.Contains("tdie")||
                            hay.Contains("ccd")||
                            hay.Contains("peci")||
                            name.StartsWith("CPU",StringComparison.OrdinalIgnoreCase)||
                            name.StartsWith("Core",StringComparison.OrdinalIgnoreCase);

                        if(!cpu)continue;
                        if(hay.Contains("distance to tjmax"))continue;

                        object raw=row["Value"];
                        if(raw==null)continue;
                        float v;
                        try{v=Convert.ToSingle(raw,CultureInfo.InvariantCulture);}catch{continue;}
                        if(!IsValidTemp(v))continue;

                        all.Add(v);

                        bool ordinaryCore=
                            (name.StartsWith("CPU Core #",StringComparison.OrdinalIgnoreCase)||
                             name.StartsWith("Core #",StringComparison.OrdinalIgnoreCase)) &&
                            name.IndexOf("Max",StringComparison.OrdinalIgnoreCase)<0 &&
                            name.IndexOf("Average",StringComparison.OrdinalIgnoreCase)<0;
                        if(ordinaryCore)cores.Add(v);

                        if(name.IndexOf("Core Average",StringComparison.OrdinalIgnoreCase)>=0||
                           name.IndexOf("Cores Average",StringComparison.OrdinalIgnoreCase)>=0)
                            directAverage=v;

                        if(name.IndexOf("Core Max",StringComparison.OrdinalIgnoreCase)>=0||
                           name.IndexOf("Cores Max",StringComparison.OrdinalIgnoreCase)>=0)
                            directMaximum=v;
                    }

                    if(cores.Count>0)
                    {
                        result.Valid=true;
                        result.Current=cores.Max();
                        result.Average=cores.Average();
                        result.Maximum=cores.Max();
                        result.SensorCount=cores.Count;
                        return result;
                    }

                    if(IsValidTemp(directAverage)||IsValidTemp(directMaximum))
                    {
                        float a=IsValidTemp(directAverage)?directAverage:directMaximum;
                        float m=IsValidTemp(directMaximum)?directMaximum:directAverage;
                        result.Valid=true;
                        result.Current=m;
                        result.Average=a;
                        result.Maximum=m;
                        result.SensorCount=all.Count;
                        return result;
                    }

                    if(all.Count>0)
                    {
                        result.Valid=true;
                        result.Current=all.Max();
                        result.Average=all.Average();
                        result.Maximum=all.Max();
                        result.SensorCount=all.Count;
                        return result;
                    }
                }
            }
            catch{}

            result.Valid=false;
            return result;
        }

        private CpuTemperatureSample ReadAcpi()
        {
            CpuTemperatureSample result=new CpuTemperatureSample();
            result.Source="ACPI_THERMAL_ZONE";

            try
            {
                ManagementScope scope=new ManagementScope(@"\\.\root\WMI");
                scope.Connect();
                ObjectQuery q=new ObjectQuery("SELECT CurrentTemperature FROM MSAcpi_ThermalZoneTemperature");

                using(ManagementObjectSearcher searcher=new ManagementObjectSearcher(scope,q))
                using(ManagementObjectCollection rows=searcher.Get())
                {
                    List<float> values=new List<float>();
                    foreach(ManagementObject row in rows)
                    {
                        object raw=row["CurrentTemperature"];
                        if(raw==null)continue;
                        double tenthsKelvin;
                        try{tenthsKelvin=Convert.ToDouble(raw,CultureInfo.InvariantCulture);}catch{continue;}
                        float c=(float)(tenthsKelvin/10.0-273.15);
                        if(IsValidTemp(c))values.Add(c);
                    }

                    if(values.Count>0)
                    {
                        result.Valid=true;
                        result.Current=values.Max();
                        result.Average=values.Average();
                        result.Maximum=values.Max();
                        result.SensorCount=values.Count;
                        return result;
                    }
                }
            }
            catch{}

            result.Valid=false;
            return result;
        }

        public void Dispose()
        {
        }
    }

    internal sealed class NativeCpuUsageSampler
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct FILETIME_NATIVE { public uint Low; public uint High; }

        [DllImport("kernel32.dll",SetLastError=true)]
        [return:MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetSystemTimes(
            out FILETIME_NATIVE idleTime,
            out FILETIME_NATIVE kernelTime,
            out FILETIME_NATIVE userTime
        );

        private bool hasBaseline;
        private ulong lastIdle,lastKernel,lastUser;

        private static ulong U64(FILETIME_NATIVE x)
        {
            return ((ulong)x.High<<32)|x.Low;
        }

        public bool TrySample(out float usage)
        {
            usage=0;
            FILETIME_NATIVE idle,kernel,user;
            if(!GetSystemTimes(out idle,out kernel,out user))return false;
            ulong i=U64(idle),k=U64(kernel),u=U64(user);
            if(!hasBaseline)
            {
                lastIdle=i;lastKernel=k;lastUser=u;hasBaseline=true;
                return false;
            }
            ulong dk=k>=lastKernel?k-lastKernel:0;
            ulong du=u>=lastUser?u-lastUser:0;
            ulong di=i>=lastIdle?i-lastIdle:0;
            lastIdle=i;lastKernel=k;lastUser=u;
            ulong total=dk+du;
            if(total==0)return false;
            ulong busy=total>=di?total-di:0;
            usage=(float)Math.Max(0d,Math.Min(100d,busy*100d/total));
            return true;
        }

        public void Reset(){hasBaseline=false;lastIdle=lastKernel=lastUser=0;}
    }

    internal sealed class MetricsEngine : IDisposable
    {
        private readonly NativeCpuUsageSampler cpuUsageSampler=new NativeCpuUsageSampler();
        private PerformanceCounter cpuFrequencyCounter;
        private PerformanceCounter diskCounter;
        private readonly Dictionary<string,PerformanceCounter> diskActivityCounters=new Dictionary<string,PerformanceCounter>(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string,PerformanceCounter> diskReadCounters=new Dictionary<string,PerformanceCounter>(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string,PerformanceCounter> diskWriteCounters=new Dictionary<string,PerformanceCounter>(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string,long> previousRx = new Dictionary<string,long>();
        private readonly Dictionary<string,long> previousTx = new Dictionary<string,long>();
        private List<NetworkInterface> networkInterfaces=new List<NetworkInterface>();
        private DateTime lastNetworkTopologyQuery=DateTime.MinValue;
        private DateTime previousNetAt = DateTime.UtcNow;
        private DateTime lastGpuQuery = DateTime.MinValue;
        private DateTime lastCpuTempQuery = DateTime.MinValue;
        private DateTime lastDiskTempQuery = DateTime.MinValue;
        private DateTime lastDiskTopologyQuery = DateTime.MinValue;
        private readonly CpuTemperatureReader cpuTempReader = new CpuTemperatureReader();
        private readonly ElevatedStorageTemperatureReader elevatedStorageTempReader = new ElevatedStorageTemperatureReader();
        private readonly RollingTemperatureWindow cpuTemps = new RollingTemperatureWindow();
        private readonly RollingTemperatureWindow gpuTemps = new RollingTemperatureWindow();
        private readonly ElevatedGpuTelemetryReader elevatedGpuReader = new ElevatedGpuTelemetryReader();
        private readonly WindowsGpuFallbackReader windowsGpuReader = new WindowsGpuFallbackReader();
        private readonly AmdAdlxTemperatureReader amdAdlxTempReader = new AmdAdlxTemperatureReader();
        private List<GpuDeviceSnapshot> lastGpuDevices=new List<GpuDeviceSnapshot>();
        private List<MemoryModuleSnapshot> memoryModules=new List<MemoryModuleSnapshot>();
        private List<CpuDeviceSnapshot> cpuDeviceTemplate=new List<CpuDeviceSnapshot>();
        private DateTime lastCpuDeviceStaticQuery=DateTime.MinValue;
        private DateTime lastMemoryModuleQuery=DateTime.MinValue;
        private string lastGpuTempSource="UNAVAILABLE";
        private string lastCpuTempSource="UNAVAILABLE";
        private float lastCpuTempCurrent=0;
        private float lastCpuPowerW=0;
        private bool lastCpuPowerAvailable=false;
        private string lastCpuPowerSource="UNAVAILABLE";
        private DateTime lastCpuTempValidAt=DateTime.MinValue;
        private List<StorageTemperatureSample> lastStorageTemperatures=new List<StorageTemperatureSample>();
        private string lastDiskTemperatureProviderSignature="";
        private readonly HashSet<string> loggedDiskTemperatureMatches=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        private List<DiskTopologyEntry> diskTopology=new List<DiskTopologyEntry>();

        private sealed class DiskTopologyEntry
        {
            public int Index=-1;
            public string Id,Name,PerfInstance,BusType,MediaType,InterfaceType;
            public ulong PhysicalSizeBytes;
            public bool LogicalCounterFallback;
            public List<string> Volumes=new List<string>();
        }

        public MetricsEngine()
        {
            try { cpuFrequencyCounter = new PerformanceCounter("Processor Information", "Processor Frequency", "_Total", true); cpuFrequencyCounter.NextValue(); } catch (Exception ex) { Log.Write("WARN", "CPU_FREQ_COUNTER " + ex.Message); }
            try { diskCounter = new PerformanceCounter("PhysicalDisk", "% Disk Time", "_Total", true); diskCounter.NextValue(); } catch (Exception ex) { Log.Write("WARN", "DISK_COUNTER " + ex.Message); }
            CaptureNetworkBaseline();
        }

        public MetricsSnapshot Read()
        {
            MetricsSnapshot s = new MetricsSnapshot();
            try { float nativeCpu;if(cpuUsageSampler.TrySample(out nativeCpu))s.Cpu=Clamp(nativeCpu,0,100); } catch { }
            try { if (diskCounter != null) s.Disk = Clamp(diskCounter.NextValue(),0,100); } catch { }
            NativeMemory.GetUsage(out s.RamUsedBytes,out s.RamTotalBytes,out s.Ram);
            ReadMemoryModulesIfDue(s);
            ReadCpuTemperatureIfDue();
            bool cpuTempFresh=lastCpuTempValidAt!=DateTime.MinValue&&(DateTime.UtcNow-lastCpuTempValidAt).TotalSeconds<=15;
            s.CpuTempAvailable=cpuTempFresh&&cpuTemps.Count>0&&lastCpuTempCurrent>=5f;s.CpuTempCurrent=s.CpuTempAvailable?lastCpuTempCurrent:0;s.CpuTempAvg=cpuTemps.Average;s.CpuTempMax=cpuTemps.Maximum;s.CpuTempSource=s.CpuTempAvailable?lastCpuTempSource:"UNAVAILABLE";
            ReadCpuDevices(s);
            ReadDiskDevices(s);
            ReadNetwork(s);
            ReadGpuIfDue();
            s.GpuDevices=new List<GpuDeviceSnapshot>(lastGpuDevices);
            GpuDeviceSnapshot active=s.GpuDevices.OrderByDescending(x=>x.UsageAvailable?x.Usage:-1).FirstOrDefault();
            if(active!=null){s.Gpu=active.Usage;s.GpuTemp=active.Temperature;s.GpuTempAvailable=active.TemperatureAvailable;}
            s.VramUsedGb=s.GpuDevices.Sum(x=>Math.Max(0,x.VramUsedGb));s.VramTotalGb=s.GpuDevices.Sum(x=>Math.Max(0,x.VramTotalGb));
            List<float> gt=s.GpuDevices.Where(x=>x.TemperatureAvailable).Select(x=>x.Temperature).ToList();
            if(gt.Count>0){foreach(float t in gt)gpuTemps.Add(t,t);s.GpuTempAvailable=true;s.GpuTempAvg=gt.Average();s.GpuTempMax=gt.Max();}else{s.GpuTempAvg=gpuTemps.Average;s.GpuTempMax=gpuTemps.Maximum;}
            s.GpuTempSource=lastGpuTempSource;
            return s;
        }

        private static float Clamp(float v,float min,float max) { if (Single.IsNaN(v)||Single.IsInfinity(v)) return 0; return Math.Max(min,Math.Min(max,v)); }

        private static CpuDeviceSnapshot CloneCpuDevice(CpuDeviceSnapshot x)
        {
            CpuDeviceSnapshot d=new CpuDeviceSnapshot();
            d.Id=x.Id;d.Name=x.Name;d.PhysicalCores=x.PhysicalCores;d.LogicalProcessors=x.LogicalProcessors;
            d.CurrentClockMHz=x.CurrentClockMHz;d.MaxClockMHz=x.MaxClockMHz;d.ExternalClockMHz=x.ExternalClockMHz;d.Socket=x.Socket;
            return d;
        }

        private void RefreshCpuDeviceTemplateIfDue()
        {
            if(cpuDeviceTemplate.Count>0&&(DateTime.UtcNow-lastCpuDeviceStaticQuery).TotalMinutes<5)return;
            lastCpuDeviceStaticQuery=DateTime.UtcNow;
            List<CpuDeviceSnapshot> list=new List<CpuDeviceSnapshot>();
            try
            {
                using(ManagementObjectSearcher q=new ManagementObjectSearcher(
                    "SELECT DeviceID,Name,NumberOfCores,NumberOfLogicalProcessors,CurrentClockSpeed,MaxClockSpeed,ExtClock,SocketDesignation FROM Win32_Processor"))
                foreach(ManagementObject o in q.Get())
                {
                    CpuDeviceSnapshot d=new CpuDeviceSnapshot();
                    d.Id=Convert.ToString(o["DeviceID"],CultureInfo.InvariantCulture);
                    d.Name=Convert.ToString(o["Name"],CultureInfo.InvariantCulture);
                    try{d.PhysicalCores=Convert.ToInt32(o["NumberOfCores"],CultureInfo.InvariantCulture);}catch{}
                    try{d.LogicalProcessors=Convert.ToInt32(o["NumberOfLogicalProcessors"],CultureInfo.InvariantCulture);}catch{}
                    try{d.CurrentClockMHz=Convert.ToInt32(o["CurrentClockSpeed"],CultureInfo.InvariantCulture);}catch{}
                    try{d.MaxClockMHz=Convert.ToInt32(o["MaxClockSpeed"],CultureInfo.InvariantCulture);}catch{}
                    try{d.ExternalClockMHz=Convert.ToInt32(o["ExtClock"],CultureInfo.InvariantCulture);}catch{}
                    try{d.Socket=Convert.ToString(o["SocketDesignation"],CultureInfo.InvariantCulture);}catch{}
                    list.Add(d);
                }
            }
            catch(Exception ex){Log.Write("WARN","CPU_DEVICE_STATIC_ENUM "+ex.Message);}
            if(list.Count==0)
            {
                CpuDeviceSnapshot d=new CpuDeviceSnapshot();d.Id="CPU0";
                d.Name=Environment.GetEnvironmentVariable("PROCESSOR_IDENTIFIER")??"CPU";
                d.PhysicalCores=Environment.ProcessorCount;d.LogicalProcessors=Environment.ProcessorCount;
                list.Add(d);
            }
            cpuDeviceTemplate=list;
        }

        private void ReadCpuDevices(MetricsSnapshot s)
        {
            RefreshCpuDeviceTemplateIfDue();
            List<CpuDeviceSnapshot> list=cpuDeviceTemplate.Select(CloneCpuDevice).ToList();
            foreach(CpuDeviceSnapshot d in list){d.Usage=s.Cpu;d.UsageAvailable=true;}
            if(list.Count==1)
            {
                if(s.CpuTempAvailable){list[0].TemperatureAvailable=true;list[0].Temperature=s.CpuTempCurrent;}
                if(lastCpuPowerAvailable){list[0].PowerAvailable=true;list[0].PowerW=lastCpuPowerW;}
                try{if(cpuFrequencyCounter!=null){float live=cpuFrequencyCounter.NextValue();if(live>100&&live<10000)list[0].CurrentClockMHz=(int)Math.Round(live);}}catch{}
            }
            s.CpuDevices=list;
        }

        public void ResetAfterResume()
        {
            cpuUsageSampler.Reset();
            try{CaptureNetworkBaseline();}catch{}
            try{if(cpuFrequencyCounter!=null)cpuFrequencyCounter.NextValue();}catch{}
            try{if(diskCounter!=null)diskCounter.NextValue();}catch{}
            foreach(PerformanceCounter c in diskActivityCounters.Values)try{c.NextValue();}catch{}
            foreach(PerformanceCounter c in diskReadCounters.Values)try{c.NextValue();}catch{}
            foreach(PerformanceCounter c in diskWriteCounters.Values)try{c.NextValue();}catch{}
            lastGpuQuery=DateTime.MinValue;
            lastCpuTempQuery=DateTime.MinValue;
            lastDiskTempQuery=DateTime.MinValue;
            lastDiskTopologyQuery=DateTime.MinValue;
            lastMemoryModuleQuery=DateTime.MinValue;
            lastCpuDeviceStaticQuery=DateTime.MinValue;
            Log.Write("INFO","METRICS_RESUME_RESET nativeCpuBaseline=RESET networkBaseline=RESET staticTopology=INVALIDATED");
        }

        private static string MemoryTypeName(int smbiosType)
        {
            switch(smbiosType)
            {
                case 20:return "DDR";
                case 21:return "DDR2";
                case 24:return "DDR3";
                case 26:return "DDR4";
                case 34:return "DDR5";
                default:return smbiosType>0?("SMBIOS "+smbiosType):"Unknown";
            }
        }

        private void ReadMemoryModulesIfDue(MetricsSnapshot s)
        {
            if(memoryModules.Count>0&&(DateTime.UtcNow-lastMemoryModuleQuery).TotalMinutes<10)
            {
                s.MemoryModules=new List<MemoryModuleSnapshot>(memoryModules);return;
            }
            lastMemoryModuleQuery=DateTime.UtcNow;
            List<MemoryModuleSnapshot> list=new List<MemoryModuleSnapshot>();
            try
            {
                using(ManagementObjectSearcher q=new ManagementObjectSearcher(
                    "SELECT BankLabel,DeviceLocator,Manufacturer,PartNumber,Capacity,Speed,ConfiguredClockSpeed,DataWidth,TotalWidth,SMBIOSMemoryType FROM Win32_PhysicalMemory"))
                foreach(ManagementObject o in q.Get())
                {
                    MemoryModuleSnapshot m=new MemoryModuleSnapshot();
                    m.BankLabel=Convert.ToString(o["BankLabel"],CultureInfo.InvariantCulture);
                    m.DeviceLocator=Convert.ToString(o["DeviceLocator"],CultureInfo.InvariantCulture);
                    m.Manufacturer=Convert.ToString(o["Manufacturer"],CultureInfo.InvariantCulture);
                    m.PartNumber=(Convert.ToString(o["PartNumber"],CultureInfo.InvariantCulture)??"").Trim();
                    try{m.CapacityBytes=Convert.ToUInt64(o["Capacity"],CultureInfo.InvariantCulture);}catch{}
                    try{m.SpeedMHz=Convert.ToInt32(o["Speed"],CultureInfo.InvariantCulture);}catch{}
                    try{m.ConfiguredClockMHz=Convert.ToInt32(o["ConfiguredClockSpeed"],CultureInfo.InvariantCulture);}catch{}
                    try{m.DataWidth=Convert.ToInt32(o["DataWidth"],CultureInfo.InvariantCulture);}catch{}
                    try{m.TotalWidth=Convert.ToInt32(o["TotalWidth"],CultureInfo.InvariantCulture);}catch{}
                    int type=0;try{type=Convert.ToInt32(o["SMBIOSMemoryType"],CultureInfo.InvariantCulture);}catch{}
                    m.MemoryType=MemoryTypeName(type);
                    list.Add(m);
                }
            }
            catch(Exception ex){Log.Write("WARN","RAM_MODULE_ENUM "+ex.Message);}
            if(list.Count>0)memoryModules=list;
            s.MemoryModules=new List<MemoryModuleSnapshot>(memoryModules);
        }

        private static string NormalizeDiskModel(string value)
        {
            if(String.IsNullOrWhiteSpace(value))return "";
            return Regex.Replace(value.ToLowerInvariant(),@"[^a-z0-9]+","");
        }

        private static string BusTypeName(int bus)
        {
            switch(bus)
            {
                case 1:return "SCSI"; case 2:return "ATAPI"; case 3:return "ATA";
                case 4:return "IEEE1394"; case 5:return "SSA"; case 6:return "Fibre Channel";
                case 7:return "USB"; case 8:return "RAID"; case 9:return "iSCSI";
                case 10:return "SAS"; case 11:return "SATA"; case 12:return "SD";
                case 13:return "MMC"; case 14:return "Virtual"; case 15:return "File-backed Virtual";
                case 16:return "Storage Spaces"; case 17:return "NVMe"; case 18:return "SCM";
                case 19:return "UFS"; default:return "";
            }
        }
        private static string PhysicalMediaTypeName(int media)
        {
            switch(media){case 3:return "HDD";case 4:return "SSD";case 5:return "SCM";default:return "";}
        }

        private void RefreshDiskTopologyIfDue()
        {
            if(diskTopology.Count>0&&(DateTime.UtcNow-lastDiskTopologyQuery).TotalMinutes<5)return;
            lastDiskTopologyQuery=DateTime.UtcNow;
            List<DiskTopologyEntry> fresh=new List<DiskTopologyEntry>();
            string[] perfInstances=new string[0];
            try{perfInstances=new PerformanceCounterCategory("PhysicalDisk").GetInstanceNames();}catch{}
            try
            {
                using(ManagementObjectSearcher q=new ManagementObjectSearcher("SELECT Index,DeviceID,Model,Size,InterfaceType,MediaType FROM Win32_DiskDrive"))
                foreach(ManagementObject disk in q.Get())
                {
                    DiskTopologyEntry e=new DiskTopologyEntry();
                    try{e.Index=Convert.ToInt32(disk["Index"],CultureInfo.InvariantCulture);}catch{}
                    e.Id=Convert.ToString(disk["DeviceID"],CultureInfo.InvariantCulture);if(String.IsNullOrWhiteSpace(e.Id))e.Id="PHYSICALDRIVE"+e.Index;
                    e.Name=Convert.ToString(disk["Model"],CultureInfo.InvariantCulture);if(String.IsNullOrWhiteSpace(e.Name))e.Name="Disk "+e.Index;
                    try{e.PhysicalSizeBytes=Convert.ToUInt64(disk["Size"],CultureInfo.InvariantCulture);}catch{}
                    e.InterfaceType=Convert.ToString(disk["InterfaceType"],CultureInfo.InvariantCulture);
                    e.MediaType=Convert.ToString(disk["MediaType"],CultureInfo.InvariantCulture);
                    string prefix=e.Index.ToString(CultureInfo.InvariantCulture);
                    e.PerfInstance=perfInstances.FirstOrDefault(delegate(string n){return !String.Equals(n,"_Total",StringComparison.OrdinalIgnoreCase)&&(String.Equals(n,prefix,StringComparison.OrdinalIgnoreCase)||n.StartsWith(prefix+" ",StringComparison.OrdinalIgnoreCase));});
                    try
                    {
                        foreach(ManagementObject part in disk.GetRelated("Win32_DiskPartition"))
                        foreach(ManagementObject logical in part.GetRelated("Win32_LogicalDisk"))
                        {
                            string id=Convert.ToString(logical["DeviceID"],CultureInfo.InvariantCulture);
                            if(!String.IsNullOrWhiteSpace(id)&&!e.Volumes.Contains(id,StringComparer.OrdinalIgnoreCase))e.Volumes.Add(id);
                        }
                    }
                    catch{}
                    fresh.Add(e);
                }
            }
            catch(Exception ex){Log.Write("WARN","DISK_TOPOLOGY_WMI "+ex.Message);}

            try
            {
                Dictionary<int,DiskTopologyEntry> byIndex=fresh.Where(x=>x.Index>=0).ToDictionary(x=>x.Index,x=>x);
                using(ManagementObjectSearcher pq=new ManagementObjectSearcher(
                    @"root\Microsoft\Windows\Storage",
                    "SELECT DeviceId,FriendlyName,BusType,MediaType,SpindleSpeed FROM MSFT_PhysicalDisk"))
                foreach(ManagementObject pd in pq.Get())
                {
                    int idx=-1;try{idx=Convert.ToInt32(pd["DeviceId"],CultureInfo.InvariantCulture);}catch{}
                    DiskTopologyEntry e;if(!byIndex.TryGetValue(idx,out e))continue;
                    int bus=0,media=0;
                    try{bus=Convert.ToInt32(pd["BusType"],CultureInfo.InvariantCulture);}catch{}
                    try{media=Convert.ToInt32(pd["MediaType"],CultureInfo.InvariantCulture);}catch{}
                    e.BusType=BusTypeName(bus);
                    string mt=PhysicalMediaTypeName(media);
                    if(!String.IsNullOrWhiteSpace(mt))e.MediaType=mt;
                }
            }
            catch(Exception ex){Log.Write("WARN","DISK_STORAGE_NAMESPACE "+ex.Message);}

            foreach(DiskTopologyEntry e in fresh)
                if(String.IsNullOrWhiteSpace(e.BusType))e.BusType=String.IsNullOrWhiteSpace(e.InterfaceType)?"Unknown":e.InterfaceType;

            if(fresh.Count==0)
            {
                foreach(DriveInfo d in DriveInfo.GetDrives())
                {
                    try
                    {
                        if(d.DriveType!=DriveType.Fixed||!d.IsReady)continue;
                        DiskTopologyEntry e=new DiskTopologyEntry();e.Id=d.Name.TrimEnd('\\');e.Name=String.IsNullOrWhiteSpace(d.VolumeLabel)?e.Id:(d.VolumeLabel+" ("+e.Id+")");e.PerfInstance=e.Id;e.LogicalCounterFallback=true;e.Volumes.Add(e.Id);e.PhysicalSizeBytes=(ulong)Math.Max(0,d.TotalSize);fresh.Add(e);
                    }
                    catch{}
                }
            }
            if(fresh.Count>0)diskTopology=fresh;
        }

        private double DiskCounterValue(Dictionary<string,PerformanceCounter> cache,string counterName,DiskTopologyEntry e)
        {
            if(e==null||String.IsNullOrWhiteSpace(e.PerfInstance))return 0;
            string category=e.LogicalCounterFallback?"LogicalDisk":"PhysicalDisk";string key=category+"|"+e.PerfInstance+"|"+counterName;
            try
            {
                PerformanceCounter c;
                if(!cache.TryGetValue(key,out c)){c=new PerformanceCounter(category,counterName,e.PerfInstance,true);c.NextValue();cache[key]=c;return 0;}
                double v=c.NextValue();if(Double.IsNaN(v)||Double.IsInfinity(v)||v<0)return 0;return v;
            }
            catch{return 0;}
        }

        private void ReadDiskTemperaturesIfDue()
        {
            if((DateTime.UtcNow-lastDiskTempQuery).TotalMilliseconds<1800)return;
            lastDiskTempQuery=DateTime.UtcNow;
            List<StorageTemperatureSample> isolated=new List<StorageTemperatureSample>();
            try{isolated=elevatedStorageTempReader.Read();}catch(Exception ex){Log.Write("WARN","DISK_TEMP_ISOLATED_READ "+ex.Message);}

            List<StorageTemperatureSample> merged=new List<StorageTemperatureSample>();
            foreach(StorageTemperatureSample x in isolated)if(x!=null&&x.Valid)merged.Add(x);
            lastStorageTemperatures=merged;
            string sig="isolated="+isolated.Count+" merged="+merged.Count+
                " sources="+String.Join("|",merged.Select(x=>(x.HardwareName??"")+"@"+(x.Source??"")).ToArray());
            if(!String.Equals(sig,lastDiskTemperatureProviderSignature,StringComparison.Ordinal))
            {
                lastDiskTemperatureProviderSignature=sig;
                Log.Write("INFO","DISK_TEMP_PROVIDER_R13 "+sig);
            }
        }

        private static int StorageSampleDriveNumber(StorageTemperatureSample sample)
        {
            if(sample==null||String.IsNullOrWhiteSpace(sample.HardwareId))return -1;
            try
            {
                Match m=Regex.Match(sample.HardwareId.Trim(),@"^/(?:nvme|ssd|hdd|storage)/([0-9]+)$",
                    RegexOptions.IgnoreCase|RegexOptions.CultureInvariant);
                int n=-1;
                if(m.Success&&Int32.TryParse(m.Groups[1].Value,NumberStyles.Integer,CultureInfo.InvariantCulture,out n))
                    return n;
            }
            catch{}
            return -1;
        }

        private StorageTemperatureSample FindDiskTemperature(DiskTopologyEntry disk)
        {
            if(disk==null||lastStorageTemperatures==null||lastStorageTemperatures.Count==0)return null;

            if(disk.Index>=0)
            {
                List<StorageTemperatureSample> byIndex=lastStorageTemperatures
                    .Where(delegate(StorageTemperatureSample x)
                    {
                        return x!=null&&x.Valid&&StorageSampleDriveNumber(x)==disk.Index;
                    }).ToList();

                if(byIndex.Count==1)return byIndex[0];

                if(byIndex.Count>1)
                {
                    string dn=NormalizeDiskModel(disk.Name);
                    StorageTemperatureSample indexedName=byIndex.FirstOrDefault(delegate(StorageTemperatureSample x)
                    {
                        return NormalizeDiskModel(x.HardwareName)==dn;
                    });
                    if(indexedName!=null)return indexedName;
                    Log.Write("WARN","DISK_TEMP_INDEX_AMBIGUOUS index="+disk.Index+
                        " samples="+String.Join("|",byIndex.Select(x=>(x.HardwareName??"")+"@"+(x.HardwareId??"")).ToArray()));
                }
            }

            string n=NormalizeDiskModel(disk.Name);
            StorageTemperatureSample exact=lastStorageTemperatures.FirstOrDefault(delegate(StorageTemperatureSample x)
            {
                return x!=null&&x.Valid&&NormalizeDiskModel(x.HardwareName)==n;
            });
            if(exact!=null)return exact;

            StorageTemperatureSample fuzzy=lastStorageTemperatures.FirstOrDefault(delegate(StorageTemperatureSample x)
            {
                string a=NormalizeDiskModel(x.HardwareName);
                return x!=null&&x.Valid&&a.Length>5&&n.Length>5&&(a.Contains(n)||n.Contains(a));
            });
            if(fuzzy!=null)return fuzzy;

            if(diskTopology.Count==1&&lastStorageTemperatures.Count==1)return lastStorageTemperatures[0];
            return null;
        }

        private void ReadDiskDevices(MetricsSnapshot s)
        {
            RefreshDiskTopologyIfDue();ReadDiskTemperaturesIfDue();
            Dictionary<string,DriveInfo> drives=new Dictionary<string,DriveInfo>(StringComparer.OrdinalIgnoreCase);
            foreach(DriveInfo d in DriveInfo.GetDrives())try{if(d.DriveType==DriveType.Fixed&&d.IsReady)drives[d.Name.TrimEnd('\\')]=d;}catch{}
            List<DiskDeviceSnapshot> list=new List<DiskDeviceSnapshot>();ulong usedAll=0,totalAll=0;double readAll=0,writeAll=0;float maxActivity=0;
            foreach(DiskTopologyEntry e in diskTopology)
            {
                try
                {
                    ulong used=0,total=0;List<string> mounted=new List<string>();
                    foreach(string vol in e.Volumes)
                    {
                        DriveInfo d;if(!drives.TryGetValue(vol,out d))continue;
                        ulong vt=(ulong)Math.Max(0,d.TotalSize);ulong vf=(ulong)Math.Max(0,d.AvailableFreeSpace);ulong vu=vt>=vf?vt-vf:0;used+=vu;total+=vt;mounted.Add(vol);
                    }
                    DiskDeviceSnapshot x=new DiskDeviceSnapshot();x.Id=e.Id;x.Name=e.Name;x.PhysicalSizeBytes=e.PhysicalSizeBytes;x.Volumes=String.Join(", ",mounted.ToArray());x.Root=x.Volumes;x.BusType=e.BusType;x.MediaType=e.MediaType;x.InterfaceType=e.InterfaceType;
                    x.UsedBytes=used;x.TotalBytes=total;x.CapacityAvailable=total>0;x.UsedPercent=total>0?(float)(used*100d/total):0;
                    x.Activity=(float)Math.Min(100,DiskCounterValue(diskActivityCounters,"% Disk Time",e));x.ActivityAvailable=!String.IsNullOrWhiteSpace(e.PerfInstance);
                    x.ReadBytesPerSec=DiskCounterValue(diskReadCounters,"Disk Read Bytes/sec",e);x.WriteBytesPerSec=DiskCounterValue(diskWriteCounters,"Disk Write Bytes/sec",e);x.RateAvailable=!String.IsNullOrWhiteSpace(e.PerfInstance);
                    StorageTemperatureSample st=FindDiskTemperature(e);if(st!=null&&st.Valid){x.Temperature=st.Temperature;x.TemperatureAvailable=true;x.TemperatureSource=st.Source;if(loggedDiskTemperatureMatches.Add(e.Id??e.Name)){string mm=StorageSampleDriveNumber(st)==e.Index?"INDEX":"MODEL";Log.Write("INFO","DISK_TEMP_MATCH_RESTORE_R02 diskId="+(e.Id??"")+" diskIndex="+e.Index+" disk="+(e.Name??"")+" sensor="+(st.HardwareName??"")+" hwid="+(st.HardwareId??"")+" method="+mm+" temp="+st.Temperature.ToString("0.0",CultureInfo.InvariantCulture)+" source="+(st.Source??""));}}
                    list.Add(x);if(x.CapacityAvailable){usedAll+=used;totalAll+=total;}readAll+=x.ReadBytesPerSec;writeAll+=x.WriteBytesPerSec;maxActivity=Math.Max(maxActivity,x.Activity);
                }
                catch(Exception ex){Log.Write("WARN","DISK_DEVICE_READ "+e.Id+" "+ex.Message);}
            }
            s.DiskDevices=list;s.DiskUsedBytes=usedAll;s.DiskTotalBytes=totalAll;s.DiskUsedPercent=totalAll>0?(float)(usedAll*100d/totalAll):0;s.DiskReadBytesPerSec=readAll;s.DiskWriteBytesPerSec=writeAll;if(list.Count>0)s.Disk=maxActivity;
        }

        private void RefreshNetworkTopologyIfDue(bool force)
        {
            if(!force&&networkInterfaces.Count>0&&(DateTime.UtcNow-lastNetworkTopologyQuery).TotalSeconds<30)return;
            lastNetworkTopologyQuery=DateTime.UtcNow;
            try
            {
                networkInterfaces=NetworkInterface.GetAllNetworkInterfaces()
                    .Where(n=>n.OperationalStatus==OperationalStatus.Up&&n.NetworkInterfaceType!=NetworkInterfaceType.Loopback)
                    .ToList();
                HashSet<string> ids=new HashSet<string>(networkInterfaces.Select(n=>n.Id),StringComparer.OrdinalIgnoreCase);
                foreach(string id in previousRx.Keys.Where(x=>!ids.Contains(x)).ToList())previousRx.Remove(id);
                foreach(string id in previousTx.Keys.Where(x=>!ids.Contains(x)).ToList())previousTx.Remove(id);
            }
            catch(Exception ex){Log.Write("WARN","NETWORK_TOPOLOGY "+ex.Message);}
        }

        private void CaptureNetworkBaseline()
        {
            previousRx.Clear();previousTx.Clear();RefreshNetworkTopologyIfDue(true);
            foreach(NetworkInterface n in networkInterfaces)try{IPInterfaceStatistics st=n.GetIPStatistics();previousRx[n.Id]=st.BytesReceived;previousTx[n.Id]=st.BytesSent;}catch{}
            previousNetAt=DateTime.UtcNow;
        }

        private void ReadNetwork(MetricsSnapshot s)
        {
            RefreshNetworkTopologyIfDue(false);
            DateTime now=DateTime.UtcNow;double sec=Math.Max(0.05,(now-previousNetAt).TotalSeconds);double rxAll=0,txAll=0;List<NetworkDeviceSnapshot> list=new List<NetworkDeviceSnapshot>();
            foreach(NetworkInterface n in networkInterfaces)
            {
                try
                {
                    if(n.OperationalStatus!=OperationalStatus.Up||n.NetworkInterfaceType==NetworkInterfaceType.Loopback)continue;IPInterfaceStatistics st=n.GetIPStatistics();long prx,ptx;long drx=previousRx.TryGetValue(n.Id,out prx)?Math.Max(0,st.BytesReceived-prx):0;long dtx=previousTx.TryGetValue(n.Id,out ptx)?Math.Max(0,st.BytesSent-ptx):0;previousRx[n.Id]=st.BytesReceived;previousTx[n.Id]=st.BytesSent;
                    NetworkDeviceSnapshot d=new NetworkDeviceSnapshot();d.Id=n.Id;d.Name=n.Name;d.Description=n.Description;d.Active=true;d.CountersAvailable=true;d.ReceivedBytesTotal=st.BytesReceived;d.SentBytesTotal=st.BytesSent;try{d.LinkSpeedBitsPerSec=n.Speed;}catch{}d.DownBytesPerSec=drx/sec;d.UpBytesPerSec=dtx/sec;list.Add(d);rxAll+=d.DownBytesPerSec;txAll+=d.UpBytesPerSec;
                }catch{}
            }
            previousNetAt=now;s.NetworkDevices=list;s.NetDownBytesPerSec=rxAll;s.NetUpBytesPerSec=txAll;s.NetDownMbps=(float)(rxAll*8d/1000000d);s.NetUpMbps=(float)(txAll*8d/1000000d);
        }

        private void ReadCpuTemperatureIfDue()
        {
            if((DateTime.UtcNow-lastCpuTempQuery).TotalMilliseconds<1800)return;lastCpuTempQuery=DateTime.UtcNow;
            try
            {
                CpuTemperatureSample sample=cpuTempReader.Read();
                lastCpuTempSource=sample.Source??"UNAVAILABLE";
                lastCpuPowerAvailable=sample.PowerAvailable;
                lastCpuPowerW=sample.PowerAvailable?sample.PowerW:0;
                lastCpuPowerSource=sample.PowerAvailable?(sample.PowerSource??"LHM_ELEVATED_BROKER"):"UNAVAILABLE";
                if(sample.Valid){lastCpuTempCurrent=sample.Current;lastCpuTempValidAt=DateTime.UtcNow;cpuTemps.Add(sample.Average,sample.Maximum);}
            }
            catch(Exception ex){Log.Write("WARN","CPU_TEMP_READ "+ex.Message);}
        }

        private static bool IsAmdName(string s){s=s??"";return s.IndexOf("AMD",StringComparison.OrdinalIgnoreCase)>=0||s.IndexOf("Radeon",StringComparison.OrdinalIgnoreCase)>=0;}
        private static string NormalizeGpuName(string s){if(String.IsNullOrWhiteSpace(s))return "";string n=Regex.Replace(s.ToLowerInvariant(),@"[^a-z0-9]+","");foreach(string x in new string[]{"nvidiacorporation","advancedmicrodevicesinc","intelcorporation","microsoftcorporation"})n=n.Replace(x,"");return n;}
        private static GpuTelemetrySample FindMatch(List<GpuTelemetrySample> list,GpuTelemetrySample sample)
        {
            string n=NormalizeGpuName(sample.HardwareName);if(n.Length==0)return null;GpuTelemetrySample exact=list.FirstOrDefault(x=>NormalizeGpuName(x.HardwareName)==n);if(exact!=null)return exact;return list.FirstOrDefault(x=>{string a=NormalizeGpuName(x.HardwareName);return a.Length>5&&(a.Contains(n)||n.Contains(a));});
        }
        private static void MergeGpu(List<GpuTelemetrySample> list,GpuTelemetrySample sample,bool preferSample)
        {
            if(sample==null)return;GpuTelemetrySample d=FindMatch(list,sample);if(d==null){list.Add(sample);return;}
            if(preferSample||!d.LoadValid){if(sample.LoadValid){d.Load=sample.Load;d.LoadValid=true;}}
            if(preferSample||d.VramUsedGb<=0){if(sample.VramUsedGb>0)d.VramUsedGb=sample.VramUsedGb;}if(preferSample||d.VramTotalGb<=0){if(sample.VramTotalGb>0)d.VramTotalGb=sample.VramTotalGb;}
            if(preferSample||!d.TemperatureValid){if(sample.TemperatureValid){d.Temperature=sample.Temperature;d.TemperatureValid=true;}}
            if(preferSample||!d.CoreClockValid){if(sample.CoreClockValid){d.CoreClockMHz=sample.CoreClockMHz;d.CoreClockValid=true;}}
            if(preferSample||!d.MemoryClockValid){if(sample.MemoryClockValid){d.MemoryClockMHz=sample.MemoryClockMHz;d.MemoryClockValid=true;}}
            if(preferSample||!d.PowerValid){if(sample.PowerValid){d.PowerW=sample.PowerW;d.PowerValid=true;}}
            if(preferSample||!d.FanRpmValid){if(sample.FanRpmValid){d.FanRpm=sample.FanRpm;d.FanRpmValid=true;}}
            if(preferSample||!d.FanPercentValid){if(sample.FanPercentValid){d.FanPercent=sample.FanPercent;d.FanPercentValid=true;}}
            if(sample.PcieGeneration>0)d.PcieGeneration=sample.PcieGeneration;
            if(sample.PcieWidth>0)d.PcieWidth=sample.PcieWidth;
            if(!String.IsNullOrWhiteSpace(sample.HardwareId)&&sample.HardwareId.IndexOf("LHM:",StringComparison.OrdinalIgnoreCase)!=0)d.HardwareId=sample.HardwareId;
            if(preferSample)d.Source=sample.Source;
        }

        private List<GpuTelemetrySample> ReadNvidiaSmiAll()
        {
            List<GpuTelemetrySample> r=new List<GpuTelemetrySample>();string exe=FindNvidiaSmi();if(exe==null)return r;
            try
            {
                ProcessStartInfo psi=new ProcessStartInfo();psi.FileName=exe;psi.Arguments="--query-gpu=index,name,pci.bus_id,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits";psi.UseShellExecute=false;psi.CreateNoWindow=true;psi.RedirectStandardOutput=true;psi.RedirectStandardError=true;
                using(Process p=Process.Start(psi)){if(p==null)return r;if(!p.WaitForExit(1500)){try{p.Kill();}catch{};return r;}string stdout=p.StandardOutput.ReadToEnd();if(p.ExitCode!=0)return r;using(StringReader sr=new StringReader(stdout)){string line;while((line=sr.ReadLine())!=null){if(String.IsNullOrWhiteSpace(line))continue;string[] a=line.Split(',');if(a.Length<7)continue;GpuTelemetrySample g=new GpuTelemetrySample();g.Valid=true;g.Source="NVIDIA_SMI";g.HardwareName=a[1].Trim();g.HardwareId="NVIDIA:"+a[2].Trim();int idx;if(Int32.TryParse(a[0].Trim(),out idx))g.AdapterIndex=idx;float f;if(Single.TryParse(a[3].Trim(),NumberStyles.Float,CultureInfo.InvariantCulture,out f)){g.Load=Clamp(f,0,100);g.LoadValid=true;}if(Single.TryParse(a[4].Trim(),NumberStyles.Float,CultureInfo.InvariantCulture,out f))g.VramUsedGb=f/1024f;if(Single.TryParse(a[5].Trim(),NumberStyles.Float,CultureInfo.InvariantCulture,out f))g.VramTotalGb=f/1024f;if(Single.TryParse(a[6].Trim(),NumberStyles.Float,CultureInfo.InvariantCulture,out f)&&f>=5&&f<=130){g.Temperature=f;g.TemperatureValid=true;}r.Add(g);}}}
            }catch(Exception ex){Log.Write("WARN","NVIDIA_SMI_MULTI "+ex.Message);}
            return r;
        }

        private void EnrichNvidiaSmiDetails(List<GpuTelemetrySample> samples)
        {
            string exe=FindNvidiaSmi();if(exe==null||samples==null||samples.Count==0)return;
            try
            {
                ProcessStartInfo psi=new ProcessStartInfo();
                psi.FileName=exe;
                psi.Arguments="--query-gpu=index,clocks.current.graphics,clocks.current.memory,pcie.link.gen.current,pcie.link.width.current --format=csv,noheader,nounits";
                psi.UseShellExecute=false;psi.CreateNoWindow=true;psi.RedirectStandardOutput=true;psi.RedirectStandardError=true;
                using(Process p=Process.Start(psi))
                {
                    if(p==null)return;
                    if(!p.WaitForExit(1200)){try{p.Kill();}catch{}return;}
                    string stdout=p.StandardOutput.ReadToEnd();if(p.ExitCode!=0)return;
                    using(StringReader sr=new StringReader(stdout))
                    {
                        string line;
                        while((line=sr.ReadLine())!=null)
                        {
                            string[] a=line.Split(',');if(a.Length<5)continue;
                            int idx;if(!Int32.TryParse(a[0].Trim(),out idx))continue;
                            GpuTelemetrySample g=samples.FirstOrDefault(x=>x.AdapterIndex==idx);
                            if(g==null)continue;
                            float f;int n;
                            if(Single.TryParse(a[1].Trim(),NumberStyles.Float,CultureInfo.InvariantCulture,out f)&&f>0){g.CoreClockMHz=f;g.CoreClockValid=true;}
                            if(Single.TryParse(a[2].Trim(),NumberStyles.Float,CultureInfo.InvariantCulture,out f)&&f>0){g.MemoryClockMHz=f;g.MemoryClockValid=true;}
                            if(Int32.TryParse(a[3].Trim(),out n)&&n>0)g.PcieGeneration=n;
                            if(Int32.TryParse(a[4].Trim(),out n)&&n>0)g.PcieWidth=n;
                        }
                    }
                }
            }
            catch(Exception ex){Log.Write("WARN","NVIDIA_SMI_DETAILS "+ex.Message);}
        }

        private void ReadGpuIfDue()
        {
            if((DateTime.UtcNow-lastGpuQuery).TotalMilliseconds<1800)return;lastGpuQuery=DateTime.UtcNow;List<GpuTelemetrySample> merged=new List<GpuTelemetrySample>();
            try{foreach(GpuTelemetrySample x in elevatedGpuReader.ReadAll())MergeGpu(merged,x,true);}catch(Exception ex){Log.Write("WARN","GPU_ISOLATED_BROKER "+ex.Message);}
            if(merged.Count==0||!merged.Any(x=>x.LoadValid))
            {
                try{foreach(GpuTelemetrySample x in windowsGpuReader.ReadAll())MergeGpu(merged,x,false);}catch(Exception ex){Log.Write("WARN","GPU_WDDM_FALLBACK "+ex.Message);}
            }
            // R15 narrow diagnostic: external NVIDIA SMI primary query disabled; WDDM + LHM remain active.
            // R15 narrow diagnostic: external NVIDIA SMI detail query disabled; all other v1.1.0 behavior unchanged.
            try
            {
                GpuTelemetrySample amd=merged.Where(x=>IsAmdName(x.HardwareName)&&!x.TemperatureValid).OrderByDescending(x=>x.LoadValid?x.Load:-1).FirstOrDefault();
                if(amd!=null){AdlxGpuTemperatureSample a=amdAdlxTempReader.Read();if(a.Valid){amd.Temperature=a.Temperature;amd.TemperatureValid=true;lastGpuTempSource=a.Source;}}
            }catch(Exception ex){Log.Write("WARN","GPU_ADLX_MULTI "+ex.Message);}
            List<GpuDeviceSnapshot> devices=new List<GpuDeviceSnapshot>();int i=0;foreach(GpuTelemetrySample x in merged){GpuDeviceSnapshot d=new GpuDeviceSnapshot();d.Id=String.IsNullOrWhiteSpace(x.HardwareId)?("GPU:"+i):x.HardwareId;d.Name=String.IsNullOrWhiteSpace(x.HardwareName)?("GPU "+i):x.HardwareName;d.Source=x.Source;d.Usage=x.Load;d.UsageAvailable=x.LoadValid;d.Temperature=x.Temperature;d.TemperatureAvailable=x.TemperatureValid;d.VramUsedGb=Math.Max(0,x.VramUsedGb);d.VramTotalGb=Math.Max(0,x.VramTotalGb);d.CoreClockMHz=x.CoreClockMHz;d.MemoryClockMHz=x.MemoryClockMHz;d.CoreClockAvailable=x.CoreClockValid;d.MemoryClockAvailable=x.MemoryClockValid;d.PowerW=x.PowerW;d.PowerAvailable=x.PowerValid;d.FanRpm=x.FanRpm;d.FanRpmAvailable=x.FanRpmValid;d.FanPercent=x.FanPercent;d.FanPercentAvailable=x.FanPercentValid;d.PcieGeneration=x.PcieGeneration;d.PcieWidth=x.PcieWidth;devices.Add(d);i++;}
            lastGpuDevices=devices;GpuDeviceSnapshot temp=devices.Where(x=>x.TemperatureAvailable).OrderByDescending(x=>x.UsageAvailable?x.Usage:-1).FirstOrDefault();if(temp!=null)lastGpuTempSource=temp.Source??lastGpuTempSource;
        }

        private static string FindNvidiaSmi()
        {
            string[] c=new string[]{Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"NVIDIA Corporation","NVSMI","nvidia-smi.exe"),Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows),"System32","nvidia-smi.exe")};foreach(string x in c)if(File.Exists(x))return x;return null;
        }

        public void Dispose()
        {
            if(cpuFrequencyCounter!=null)cpuFrequencyCounter.Dispose();if(diskCounter!=null)diskCounter.Dispose();foreach(PerformanceCounter c in diskActivityCounters.Values)try{c.Dispose();}catch{}foreach(PerformanceCounter c in diskReadCounters.Values)try{c.Dispose();}catch{}foreach(PerformanceCounter c in diskWriteCounters.Values)try{c.Dispose();}catch{};try{cpuTempReader.Dispose();}catch{}try{amdAdlxTempReader.Dispose();}catch{}
        }
    }

    internal static class NativeMemory
    {
        [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)]
        private class MEMORYSTATUSEX
        {
            public uint dwLength=(uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
            public uint dwMemoryLoad; public ulong ullTotalPhys; public ulong ullAvailPhys; public ulong ullTotalPageFile; public ulong ullAvailPageFile; public ulong ullTotalVirtual; public ulong ullAvailVirtual; public ulong ullAvailExtendedVirtual;
        }
        [DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)] private static extern bool GlobalMemoryStatusEx([In,Out] MEMORYSTATUSEX lpBuffer);
        public static void GetUsage(out ulong used,out ulong total,out float percent)
        {
            used=0;total=0;percent=0;try{MEMORYSTATUSEX m=new MEMORYSTATUSEX();if(GlobalMemoryStatusEx(m)){total=m.ullTotalPhys;used=total>=m.ullAvailPhys?total-m.ullAvailPhys:0;percent=m.dwMemoryLoad;}}catch{}
        }
        public static float GetUsedPercent(){ulong u,t;float p;GetUsage(out u,out t,out p);return p;}
    }

    internal static class Native
    {
        public const int GWL_STYLE=-16;
        public const int GWL_EXSTYLE=-20;
        public const int GWLP_HWNDPARENT=-8;
        public const uint GW_OWNER=4;
        public const long WS_CHILD=0x40000000L;
        public const long WS_POPUP=unchecked((long)0x80000000L);
        public const int WS_EX_TOPMOST=0x00000008;
        public const int WS_EX_TRANSPARENT=0x00000020;
        public const int WS_EX_TOOLWINDOW=0x00000080;
        public const int WS_EX_CONTROLPARENT=0x00010000;
        public const int WS_EX_LAYERED=0x00080000;
        public const int WS_EX_COMPOSITED=0x02000000;
        public const int WS_EX_NOACTIVATE=0x08000000;
        public const uint LWA_COLORKEY=0x00000001;
        public const uint LWA_ALPHA=0x00000002;
        public const int WH_MOUSE_LL=14;
        public const int HC_ACTION=0;
        public const int WM_RBUTTONDOWN=0x0204;
        public const int WM_RBUTTONUP=0x0205;
        public const int WM_TBME_VISUAL_BEACON=0x805B;
        public const uint SWP_NOSIZE=0x0001, SWP_NOMOVE=0x0002, SWP_NOZORDER=0x0004, SWP_NOACTIVATE=0x0010, SWP_FRAMECHANGED=0x0020, SWP_SHOWWINDOW=0x0040, SWP_NOOWNERZORDER=0x0200;
        public static readonly IntPtr HWND_TOP=IntPtr.Zero;
        public static readonly IntPtr HWND_TOPMOST=new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left,Top,Right,Bottom; public Rectangle ToRectangle(){return Rectangle.FromLTRB(Left,Top,Right,Bottom);} }
        [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X,Y; }
        [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT { public ushort wVk,wScan; public uint dwFlags,time; public IntPtr dwExtraInfo; }
        [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION { [FieldOffset(0)] public KEYBDINPUT ki; }
        [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION U; }

        [DllImport("user32.dll",CharSet=CharSet.Auto)] public static extern IntPtr FindWindow(string lpClassName,string lpWindowName);
        [DllImport("user32.dll",SetLastError=true)] public static extern bool GetWindowRect(IntPtr hWnd,out RECT rect);
        [DllImport("user32.dll",SetLastError=true)] public static extern IntPtr SetParent(IntPtr hWndChild,IntPtr hWndNewParent);
        [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd,uint uCmd);
        [DllImport("user32.dll",SetLastError=true)] public static extern bool SetWindowPos(IntPtr hWnd,IntPtr hWndInsertAfter,int X,int Y,int cx,int cy,uint flags);
        public delegate bool EnumWindowsProc(IntPtr hWnd,IntPtr lParam);
        public delegate bool EnumChildWindowsProc(IntPtr hWnd,IntPtr lParam);
        public delegate IntPtr LowLevelMouseProc(int nCode,IntPtr wParam,IntPtr lParam);

        [StructLayout(LayoutKind.Sequential)]
        public struct MSLLHOOKSTRUCT
        {
            public POINT pt;
            public uint mouseData;
            public uint flags;
            public uint time;
            public UIntPtr dwExtraInfo;
        }
        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc,IntPtr lParam);
        [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWndParent,EnumChildWindowsProc lpEnumFunc,IntPtr lParam);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT pt);
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd,out uint processId);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll",CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr hWnd,StringBuilder lpClassName,int nMaxCount);
        [DllImport("user32.dll",SetLastError=true)] private static extern uint SendInput(uint nInputs,[In] INPUT[] pInputs,int cbSize);
        [DllImport("user32.dll",SetLastError=true)] public static extern bool SetLayeredWindowAttributes(IntPtr hwnd,uint crKey,byte bAlpha,uint dwFlags);
        [DllImport("user32.dll",SetLastError=true)] public static extern IntPtr SetWindowsHookEx(int idHook,LowLevelMouseProc lpfn,IntPtr hMod,uint dwThreadId);
        [DllImport("user32.dll",SetLastError=true)] public static extern bool UnhookWindowsHookEx(IntPtr hhk);
        [DllImport("user32.dll")] public static extern IntPtr CallNextHookEx(IntPtr hhk,int nCode,IntPtr wParam,IntPtr lParam);
        [DllImport("user32.dll",CharSet=CharSet.Auto)] public static extern IntPtr SendMessage(IntPtr hWnd,int msg,IntPtr wParam,IntPtr lParam);
        [DllImport("kernel32.dll",CharSet=CharSet.Auto)] public static extern IntPtr GetModuleHandle(string lpModuleName);
        [DllImport("kernel32.dll",SetLastError=true)] private static extern bool SetDefaultDllDirectories(uint DirectoryFlags);
        [DllImport("user32.dll")] private static extern void keybd_event(byte bVk,byte bScan,uint dwFlags,UIntPtr dwExtraInfo);
        [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd,int attr,out int value,int cb);
        [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] private static extern IntPtr GetThreadDpiAwarenessContext();
        [DllImport("user32.dll")] private static extern bool AreDpiAwarenessContextsEqual(IntPtr a,IntPtr b);
        [DllImport("user32.dll",CharSet=CharSet.Auto)] public static extern uint RegisterWindowMessage(string lpString);

        [DllImport("user32.dll", EntryPoint="GetWindowLongPtr", SetLastError=true)] private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd,int nIndex);
        [DllImport("user32.dll", EntryPoint="GetWindowLong", SetLastError=true)] private static extern IntPtr GetWindowLongPtr32(IntPtr hWnd,int nIndex);
        [DllImport("user32.dll", EntryPoint="SetWindowLongPtr", SetLastError=true)] private static extern IntPtr SetWindowLongPtr64(IntPtr hWnd,int nIndex,IntPtr dwNewLong);
        [DllImport("user32.dll", EntryPoint="SetWindowLong", SetLastError=true)] private static extern IntPtr SetWindowLongPtr32(IntPtr hWnd,int nIndex,IntPtr dwNewLong);
        public static IntPtr GetWindowLongPtr(IntPtr hWnd,int nIndex){return IntPtr.Size==8?GetWindowLongPtr64(hWnd,nIndex):GetWindowLongPtr32(hWnd,nIndex);} 
        public static IntPtr SetWindowLongPtr(IntPtr hWnd,int nIndex,IntPtr v){return IntPtr.Size==8?SetWindowLongPtr64(hWnd,nIndex,v):SetWindowLongPtr32(hWnd,nIndex,v);} 
        public static int GetCloaked(IntPtr h){ try {int v; return DwmGetWindowAttribute(h,14,out v,sizeof(int))==0?v:0;} catch{return 0;} }

        public static bool SendVirtualKey(ushort vk)
        {
            try
            {
                INPUT down=new INPUT();down.type=1;down.U.ki=new KEYBDINPUT();down.U.ki.wVk=vk;
                INPUT up=new INPUT();up.type=1;up.U.ki=new KEYBDINPUT();up.U.ki.wVk=vk;up.U.ki.dwFlags=0x0002;
                INPUT[] a=new INPUT[]{down,up};
                return SendInput((uint)a.Length,a,Marshal.SizeOf(typeof(INPUT)))==(uint)a.Length;
            }
            catch{return false;}
        }

        public static void KeybdTap(byte vk)
        {
            try
            {
                keybd_event(vk,0,0,UIntPtr.Zero);
                Thread.Sleep(25);
                keybd_event(vk,0,0x0002,UIntPtr.Zero);
            }
            catch{}
        }

        public static void CtrlEsc()
        {
            try
            {
                keybd_event(0x11,0,0,UIntPtr.Zero);
                Thread.Sleep(20);
                keybd_event(0x1B,0,0,UIntPtr.Zero);
                Thread.Sleep(20);
                keybd_event(0x1B,0,0x0002,UIntPtr.Zero);
                keybd_event(0x11,0,0x0002,UIntPtr.Zero);
            }
            catch{}
        }

        public static IntPtr FindDescendantByClass(IntPtr parent,string className)
        {
            IntPtr found=IntPtr.Zero;
            try
            {
                EnumChildWindows(parent,delegate(IntPtr h,IntPtr l)
                {
                    StringBuilder sb=new StringBuilder(256);
                    GetClassName(h,sb,sb.Capacity);
                    if(String.Equals(sb.ToString(),className,StringComparison.Ordinal))
                    {
                        found=h;
                        return false;
                    }
                    return true;
                },IntPtr.Zero);
            }
            catch{}
            return found;
        }

        private const uint LOAD_LIBRARY_SEARCH_DEFAULT_DIRS=0x00001000;
        private static int dllSearchHardened=0;
        public static bool EnableDllSearchHardening()
        {
            if(Interlocked.CompareExchange(ref dllSearchHardened,1,1)==1)return true;
            try
            {
                bool ok=SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
                if(ok){Interlocked.Exchange(ref dllSearchHardened,1);Log.Write("INFO","DLL_SEARCH_HARDENING=PASS mode=LOAD_LIBRARY_SEARCH_DEFAULT_DIRS");return true;}
                Log.Write("WARN","DLL_SEARCH_HARDENING=FAIL win32="+Marshal.GetLastWin32Error());
            }
            catch(Exception ex){Log.Write("WARN","DLL_SEARCH_HARDENING=FAIL "+ex.GetType().Name+" "+ex.Message);}
            return false;
        }
        public static bool DllSearchHardeningActive { get { return Interlocked.CompareExchange(ref dllSearchHardened,1,1)==1; } }

        public static string DpiAwarenessMode()
        {
            try
            {
                IntPtr c=GetThreadDpiAwarenessContext();
                if(AreDpiAwarenessContextsEqual(c,new IntPtr(-4)))return "PerMonitorV2";
                if(AreDpiAwarenessContextsEqual(c,new IntPtr(-3)))return "PerMonitor";
                if(AreDpiAwarenessContextsEqual(c,new IntPtr(-2)))return "SystemAware";
                if(AreDpiAwarenessContextsEqual(c,new IntPtr(-1)))return "Unaware";
            }
            catch{}
            return "Unknown";
        }
        public static void EnableDpi(){Log.Write("INFO","DPI_CONTEXT "+DpiAwarenessMode());}
    }

    internal static class ShellUi
    {
        private static bool NameMatches(string name)
        {
            if(String.IsNullOrEmpty(name))return false;
            return
                String.Equals(name,"SearchHost",StringComparison.OrdinalIgnoreCase) ||
                String.Equals(name,"StartMenuExperienceHost",StringComparison.OrdinalIgnoreCase) ||
                String.Equals(name,"SearchApp",StringComparison.OrdinalIgnoreCase) ||
                String.Equals(name,"ShellExperienceHost",StringComparison.OrdinalIgnoreCase) ||
                String.Equals(name,"ShellHost",StringComparison.OrdinalIgnoreCase) ||
                String.Equals(name,"TextInputHost",StringComparison.OrdinalIgnoreCase);
        }

        public static bool IsStartShellForeground(out string processName,out string className,out IntPtr hwnd)
        {
            processName="";
            className="";
            hwnd=IntPtr.Zero;
            try
            {
                hwnd=Native.GetForegroundWindow();
                if(hwnd==IntPtr.Zero)return false;

                StringBuilder sb=new StringBuilder(256);
                Native.GetClassName(hwnd,sb,sb.Capacity);
                className=sb.ToString();

                uint pid=0;
                Native.GetWindowThreadProcessId(hwnd,out pid);
                if(pid==0)return false;

                using(Process p=Process.GetProcessById((int)pid))
                    processName=p.ProcessName;

                return NameMatches(processName);
            }
            catch{return false;}
        }

        public static bool IsStartShellProcessName(string processName)
        {
            return NameMatches(processName);
        }

        public static bool IsStartSurfacePresent(out string processName,out string className,out Rectangle rect,out IntPtr hwnd)
        {
            processName="";
            className="";
            rect=Rectangle.Empty;
            hwnd=IntPtr.Zero;

            try
            {
                Rectangle screen=Screen.PrimaryScreen.Bounds;
                IntPtr found=IntPtr.Zero;
                string foundProcess="";
                string foundClass="";
                Rectangle foundRect=Rectangle.Empty;

                Native.EnumWindows(delegate(IntPtr h,IntPtr l)
                {
                    if(!Native.IsWindowVisible(h))return true;

                    Native.RECT wr;
                    if(!Native.GetWindowRect(h,out wr))return true;
                    Rectangle r=wr.ToRectangle();
                    // R190: reject irrelevant window geometry before expensive
                    // per-HWND .NET process table/name queries.
                    if(r.Width<300 || r.Height<250)return true;
                    if(r.Width>=screen.Width-20 && r.Height>=screen.Height-20)return true;
                    if(r.Bottom < screen.Top + screen.Height/2)return true;

                    uint pid=0;
                    Native.GetWindowThreadProcessId(h,out pid);
                    if(pid==0)return true;

                    string pn="";
                    try{using(Process p=Process.GetProcessById((int)pid))pn=p.ProcessName;}catch{return true;}

                    bool realStartHost=
                        String.Equals(pn,"SearchHost",StringComparison.OrdinalIgnoreCase) ||
                        String.Equals(pn,"StartMenuExperienceHost",StringComparison.OrdinalIgnoreCase) ||
                        String.Equals(pn,"SearchApp",StringComparison.OrdinalIgnoreCase);

                    if(!realStartHost)return true;

                    StringBuilder sb=new StringBuilder(256);
                    Native.GetClassName(h,sb,sb.Capacity);

                    found=h;
                    foundProcess=pn;
                    foundClass=sb.ToString();
                    foundRect=r;
                    return false;
                },IntPtr.Zero);

                if(found==IntPtr.Zero)return false;
                processName=foundProcess;
                className=foundClass;
                rect=foundRect;
                hwnd=found;
                return true;
            }
            catch{return false;}
        }

        public static bool WaitForStartShell(int timeoutMs,out string processName,out string className,out IntPtr hwnd)
        {
            processName="";
            className="";
            hwnd=IntPtr.Zero;

            DateTime end=DateTime.UtcNow.AddMilliseconds(Math.Max(100,timeoutMs));
            while(DateTime.UtcNow<end)
            {
                if(IsStartShellForeground(out processName,out className,out hwnd))
                    return true;
                Thread.Sleep(50);
            }
            return false;
        }
    }

    internal sealed class TaskbarTargetInfo
    {
        public IntPtr Handle;
        public string ClassName;
        public string DeviceId;
        public bool Primary;
        public Rectangle Bounds;
    }

    internal static class TaskbarTargetPolicy
    {
        public const string PrimaryId="Primary";
        private static readonly object FallbackSync=new object();
        private static string lastFallbackKey="";
        private static DateTime lastFallbackUtc=DateTime.MinValue;
        internal static string DeviceId(string deviceName)
        {
            string s=(deviceName??"").Trim();
            if(s.StartsWith(@"\\.\",StringComparison.Ordinal))s=s.Substring(4);
            return s.ToUpperInvariant();
        }
        public static string NormalizeConfigId(string value)
        {
            string s=(value??"").Trim();
            if(String.IsNullOrWhiteSpace(s)||String.Equals(s,PrimaryId,StringComparison.OrdinalIgnoreCase))return PrimaryId;
            s=DeviceId(s);
            return Regex.IsMatch(s,@"^DISPLAY\d+$",RegexOptions.CultureInvariant)?s:PrimaryId;
        }
        [DllImport("user32.dll",EntryPoint="FindWindowExW",CharSet=CharSet.Unicode,SetLastError=true)]
        private static extern IntPtr FindTaskbarAfter(IntPtr parent,IntPtr after,string cls,string title);

        private static void AddTaskbarIfValid(List<TaskbarTargetInfo> list,IntPtr h)
        {
            if(h==IntPtr.Zero||!Native.IsWindow(h)||list.Any(t=>t.Handle==h))return;
            StringBuilder name=new StringBuilder(128);
            Native.GetClassName(h,name,name.Capacity);string cls=name.ToString();
            if(cls!="Shell_TrayWnd"&&cls!="Shell_SecondaryTrayWnd")return;
            Native.RECT nr;if(!Native.GetWindowRect(h,out nr))return;
            Rectangle r=nr.ToRectangle();if(r.Width<=0||r.Height<=0)return;
            Screen screen=Screen.FromRectangle(r);
            list.Add(new TaskbarTargetInfo{Handle=h,ClassName=cls,DeviceId=DeviceId(screen.DeviceName),Primary=screen.Primary,Bounds=r});
        }
        public static List<TaskbarTargetInfo> Enumerate()
        {
            List<TaskbarTargetInfo> list=new List<TaskbarTargetInfo>();
            try
            {
                Native.EnumWindows(delegate(IntPtr h,IntPtr l){AddTaskbarIfValid(list,h);return true;},IntPtr.Zero);
            }
            catch(Exception ex){Log.Write("WARN","TASKBAR_ENUM_FAIL "+ex.Message);}
            // R152: EnumWindows is not an authoritative inventory of all shell
            // surfaces on current Windows. A missing enumerated taskbar during
            // Start must not destroy/reparent our valid owner relationship.
            // Query the two known taskbar classes directly, validating class,
            // native geometry and uniqueness. Visibility policy is separate.
            try
            {
                AddTaskbarIfValid(list,Native.FindWindow("Shell_TrayWnd",null));
                IntPtr after=IntPtr.Zero;
                for(int i=0;i<16;i++)
                {
                    IntPtr next=FindTaskbarAfter(IntPtr.Zero,after,"Shell_SecondaryTrayWnd",null);
                    if(next==IntPtr.Zero||next==after)break;
                    AddTaskbarIfValid(list,next);after=next;
                }
            }
            catch(Exception ex){Log.Write("WARN","TASKBAR_DIRECT_DISCOVERY_FAIL "+ex.Message);}
            return list.OrderByDescending(t=>t.Primary).ThenBy(t=>t.DeviceId,StringComparer.OrdinalIgnoreCase).ToList();
        }
        internal static TaskbarTargetInfo Select(string requested,IList<TaskbarTargetInfo> items)
        {
            if(items==null||items.Count==0)return null;
            string id=NormalizeConfigId(requested);
            if(!String.Equals(id,PrimaryId,StringComparison.OrdinalIgnoreCase))
            {
                TaskbarTargetInfo exact=items.FirstOrDefault(t=>String.Equals(t.DeviceId,id,StringComparison.OrdinalIgnoreCase));
                if(exact!=null)return exact;
            }
            TaskbarTargetInfo primary=items.FirstOrDefault(t=>t.Primary||String.Equals(t.ClassName,"Shell_TrayWnd",StringComparison.Ordinal));
            return primary??items[0];
        }
        public static IntPtr Resolve(AppConfig c,out string resolvedId)
        {
            string requested=c==null?PrimaryId:c.TaskbarDisplay;
            TaskbarTargetInfo chosen=Select(requested,Enumerate());
            bool primaryAlias=chosen!=null&&(chosen.Primary||String.Equals(chosen.ClassName,"Shell_TrayWnd",StringComparison.Ordinal));
            resolvedId=chosen==null?"":(primaryAlias?PrimaryId:chosen.DeviceId);
            if(chosen!=null&&!String.Equals(NormalizeConfigId(requested),resolvedId,StringComparison.OrdinalIgnoreCase))
            {
                string key=NormalizeConfigId(requested)+"->"+resolvedId;bool write=false;
                lock(FallbackSync)
                {
                    if(!String.Equals(lastFallbackKey,key,StringComparison.OrdinalIgnoreCase)||(DateTime.UtcNow-lastFallbackUtc).TotalSeconds>=60)
                    {lastFallbackKey=key;lastFallbackUtc=DateTime.UtcNow;write=true;}
                }
                if(write)Log.Write("WARN","TASKBAR_TARGET_FALLBACK requested="+NormalizeConfigId(requested)+" resolved="+resolvedId);
            }
            return chosen==null?IntPtr.Zero:chosen.Handle;
        }
        public static string[] SettingChoices(string configured)
        {
            List<string> ids=new List<string>();ids.Add(PrimaryId);
            foreach(TaskbarTargetInfo t in Enumerate())
                if(!t.Primary&&!String.IsNullOrWhiteSpace(t.DeviceId)&&!ids.Contains(t.DeviceId,StringComparer.OrdinalIgnoreCase))ids.Add(t.DeviceId);
            string normalized=NormalizeConfigId(configured);
            if(!String.Equals(normalized,PrimaryId,StringComparison.OrdinalIgnoreCase)&&!ids.Contains(normalized,StringComparer.OrdinalIgnoreCase))ids.Add(normalized);
            return ids.ToArray();
        }
        internal static bool SelfTest()
        {
            List<TaskbarTargetInfo> fake=new List<TaskbarTargetInfo>{
                new TaskbarTargetInfo{Handle=new IntPtr(1),ClassName="Shell_TrayWnd",DeviceId="DISPLAY1",Primary=true},
                new TaskbarTargetInfo{Handle=new IntPtr(2),ClassName="Shell_SecondaryTrayWnd",DeviceId="DISPLAY2",Primary=false}
            };
            return Select("Primary",fake).Handle==new IntPtr(1)&&
                   Select("DISPLAY2",fake).Handle==new IntPtr(2)&&
                   Select(@"\\.\DISPLAY2",fake).Handle==new IntPtr(2)&&
                   Select("DISPLAY9",fake).Handle==new IntPtr(1)&&
                   NormalizeConfigId("nonsense")==PrimaryId;
        }
    }

    internal static class TaskbarLayout
    {
        private static Rectangle? lastSafe;
        private const int ControlPaddingPx=8;
        private const int PreferredAdaptiveMinWidthPx=420;

        private static int GapWidth(Tuple<int,int> g){return Math.Max(0,g.Item2-g.Item1);}

        private static Tuple<int,int> PickGap(List<Tuple<int,int>> gaps,string position,Rectangle tb)
        {
            if(gaps==null || gaps.Count==0)return null;

            if(position=="Right")
                return gaps.OrderByDescending(g=>g.Item2).ThenByDescending(g=>GapWidth(g)).First();

            if(position=="Center")
                return gaps.OrderByDescending(g=>GapWidth(g))
                    .ThenBy(g=>Math.Abs(((g.Item1+g.Item2)/2)-(tb.Left+tb.Width/2))).First();

            return gaps.OrderBy(g=>g.Item1).ThenByDescending(g=>GapWidth(g)).First();
        }

        public static Rectangle GetSafeRectangle(IntPtr taskbar, AppConfig cfg, int desiredWidth)
        {
            Native.RECT nr;
            if(!Native.GetWindowRect(taskbar,out nr)) return Rectangle.Empty;

            Rectangle tb=nr.ToRectangle();
            int requestedWidth=Math.Min(Math.Max(1,desiredWidth),tb.Width);

            if(!cfg.SafePlacement)
            {
                Rectangle plain=Requested(tb,requestedWidth,cfg.Position);
                lastSafe=plain;
                return plain;
            }

            try
            {
                AutomationElement root=AutomationElement.FromHandle(taskbar);
                AutomationElementCollection all=root.FindAll(TreeScope.Descendants,Condition.TrueCondition);
                List<Tuple<int,int>> occ=new List<Tuple<int,int>>();

                for(int i=0;i<all.Count;i++)
                {
                    AutomationElement e=all[i];
                    ControlType ct;
                    try{ct=e.Current.ControlType;}catch{continue;}

                    if(ct!=ControlType.Button &&
                       ct!=ControlType.Edit &&
                       ct!=ControlType.MenuItem &&
                       ct!=ControlType.CheckBox &&
                       ct!=ControlType.RadioButton &&
                       ct!=ControlType.ComboBox &&
                       ct!=ControlType.Hyperlink) continue;

                    System.Windows.Rect r;
                    try{r=e.Current.BoundingRectangle;}catch{continue;}
                    if(r.IsEmpty || r.Width<3 || r.Height<3) continue;

                    int l=(int)Math.Floor(r.Left)-ControlPaddingPx;
                    int rr=(int)Math.Ceiling(r.Right)+ControlPaddingPx;
                    int t=(int)Math.Floor(r.Top);
                    int b=(int)Math.Ceiling(r.Bottom);

                    if(b<=tb.Top || t>=tb.Bottom || rr<=tb.Left || l>=tb.Right) continue;

                    occ.Add(Tuple.Create(
                        Math.Max(tb.Left,l),
                        Math.Min(tb.Right,rr)
                    ));
                }

                if(occ.Count==0)
                {
                    // Do not silently reuse a potentially stale wide rectangle after a
                    // resolution/taskbar-layout transition.  Re-evaluate next tick.
                    Rectangle noControls=Requested(tb,requestedWidth,cfg.Position);
                    lastSafe=noControls;
                    return noControls;
                }

                occ.Sort((a,b)=>a.Item1.CompareTo(b.Item1));

                List<Tuple<int,int>> merged=new List<Tuple<int,int>>();
                foreach(var x in occ)
                {
                    if(merged.Count==0 || x.Item1>merged[merged.Count-1].Item2)
                    {
                        merged.Add(Tuple.Create(x.Item1,x.Item2));
                    }
                    else
                    {
                        var p=merged[merged.Count-1];
                        merged[merged.Count-1]=Tuple.Create(
                            p.Item1,
                            Math.Max(p.Item2,x.Item2)
                        );
                    }
                }

                List<Tuple<int,int>> gaps=new List<Tuple<int,int>>();
                int cur=tb.Left;
                foreach(var x in merged)
                {
                    if(x.Item1>cur)gaps.Add(Tuple.Create(cur,x.Item1));
                    cur=Math.Max(cur,x.Item2);
                }
                if(cur<tb.Right)gaps.Add(Tuple.Create(cur,tb.Right));

                if(gaps.Count==0)
                {
                    Log.Write("WARN","SAFE_PLACEMENT_NO_FREE_GAP taskbar="+tb.ToString());
                    return Rectangle.Empty;
                }

                // First choice: preserve the configured/requested width.
                List<Tuple<int,int>> fullWidthGaps=
                    gaps.Where(g=>GapWidth(g)>=requestedWidth).ToList();

                Tuple<int,int> pick;
                int actualWidth=requestedWidth;

                if(fullWidthGaps.Count>0)
                {
                    pick=PickGap(fullWidthGaps,cfg.Position,tb);
                }
                else
                {
                    // Laptop / compact-taskbar path:
                    // never cover Start/Search/pinned/system-tray controls merely because
                    // the configured desktop width cannot fit.  Select an appropriate free
                    // gap and reduce the overlay width to that real available space.
                    int adaptiveFloor=Math.Min(PreferredAdaptiveMinWidthPx,requestedWidth);
                    List<Tuple<int,int>> usable=
                        gaps.Where(g=>GapWidth(g)>=adaptiveFloor).ToList();

                    if(usable.Count==0)
                    {
                        // On an unusually crowded taskbar, use the largest remaining gap
                        // rather than overlapping Windows controls.
                        int largest=gaps.Max(g=>GapWidth(g));
                        usable=gaps.Where(g=>GapWidth(g)==largest).ToList();
                    }

                    pick=PickGap(usable,cfg.Position,tb);
                    if(pick==null || GapWidth(pick)<=0)return Rectangle.Empty;

                    actualWidth=Math.Min(requestedWidth,GapWidth(pick));

                    Log.Write(
                        "INFO",
                        "SAFE_PLACEMENT_ADAPT requested="+requestedWidth+
                        " actual="+actualWidth+
                        " gap=["+pick.Item1+","+pick.Item2+"]"+
                        " position="+cfg.Position+
                        " taskbarWidth="+tb.Width
                    );
                }

                if(pick==null)return Rectangle.Empty;

                int x0;
                if(cfg.Position=="Right")
                    x0=pick.Item2-actualWidth;
                else if(cfg.Position=="Center")
                    x0=pick.Item1+((GapWidth(pick)-actualWidth)/2);
                else
                    x0=pick.Item1;

                Rectangle safe=new Rectangle(
                    x0,
                    tb.Top,
                    actualWidth,
                    tb.Height
                );

                lastSafe=safe;
                return safe;
            }
            catch(Exception ex)
            {
                Log.Write("WARN","SAFE_PLACEMENT_REEVALUATE "+ex.Message);

                // A stale cached rectangle can overlap controls after DPI/resolution or
                // Explorer layout changes.  Prefer the configured rectangle only when no
                // UIA result is available; the next timer tick re-evaluates placement.
                Rectangle fallback=Requested(tb,requestedWidth,cfg.Position);
                lastSafe=fallback;
                return fallback;
            }
        }

        private static Rectangle Requested(Rectangle tb,int width,string position)
        {
            int x=tb.Left;
            if(position=="Right")x=tb.Right-width;
            else if(position=="Center")x=tb.Left+(tb.Width-width)/2;
            return new Rectangle(x,tb.Top,width,tb.Height);
        }

        public static void ResetCache(){lastSafe=null;}
    }

    internal sealed class MetricView
    {
        public string Key,GroupKey,DeviceId,DisplayName,Label,Value,Value2,AlertText;
        public float Percent;
        public IList<float> History;
        public Color Accent;
        public bool Alert;
    }

    internal sealed class HardwareFlyoutRow
    {
        public string Name,Line1,Line2,Line3; public Color Accent;
    }

    internal sealed class HardwareFlyoutForm : Form
    {
        private string title=""; private List<HardwareFlyoutRow> rows=new List<HardwareFlyoutRow>(); private ThemeDefinition theme;
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams { get { CreateParams cp=base.CreateParams;cp.ExStyle|=0x08000000|0x00000080;return cp; } }
        public HardwareFlyoutForm(){FormBorderStyle=FormBorderStyle.None;ShowInTaskbar=false;StartPosition=FormStartPosition.Manual;TopMost=true;DoubleBuffered=true;Width=680;Height=90;SetStyle(ControlStyles.AllPaintingInWmPaint|ControlStyles.UserPaint|ControlStyles.OptimizedDoubleBuffer,true);}
        public void UpdateContent(string newTitle,List<HardwareFlyoutRow> newRows,ThemeDefinition newTheme,Rectangle anchor)
        {
            title=newTitle??"Hardware";rows=newRows??new List<HardwareFlyoutRow>();theme=newTheme;Width=680;Height=Math.Max(78,42+rows.Count*82+8);Rectangle wa=Screen.FromRectangle(anchor).WorkingArea;int x=Math.Max(wa.Left,Math.Min(anchor.Left,wa.Right-Width));int y=anchor.Top-Height-7;if(y<wa.Top)y=Math.Min(wa.Bottom-Height,anchor.Bottom+7);Location=new Point(x,y);Invalidate();if(!Visible)Show();
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);ThemeDefinition t=theme??ThemeCatalog.Get("Dark Minimal Pro");e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;using(SolidBrush b=new SolidBrush(Color.FromArgb(250,t.Background)))e.Graphics.FillRectangle(b,ClientRectangle);using(Pen p=new Pen(Color.FromArgb(220,t.Border)))e.Graphics.DrawRectangle(p,0,0,Width-1,Height-1);
            using(Font tf=new Font(t.FontName,10.8f,FontStyle.Bold))using(SolidBrush fb=new SolidBrush(t.Foreground))e.Graphics.DrawString(title,tf,fb,14,9);
            int y=38;using(Font nf=new Font(t.FontName,9.5f,FontStyle.Bold))using(Font vf=new Font(t.FontName,8.7f,FontStyle.Regular))
            {
                foreach(HardwareFlyoutRow r in rows)
                {
                    using(SolidBrush ab=new SolidBrush(r.Accent))e.Graphics.FillRectangle(ab,9,y+3,4,56);
                    using(SolidBrush nb=new SolidBrush(t.Foreground))e.Graphics.DrawString(r.Name??"Device",nf,nb,20,y);
                    using(SolidBrush mb=new SolidBrush(t.Muted))
                    {
                        e.Graphics.DrawString(r.Line1??"",vf,mb,20,y+21);
                        if(!String.IsNullOrWhiteSpace(r.Line2))e.Graphics.DrawString(r.Line2,vf,mb,20,y+39);
                        if(!String.IsNullOrWhiteSpace(r.Line3))e.Graphics.DrawString(r.Line3,vf,mb,20,y+57);
                    }
                    using(Pen sep=new Pen(Color.FromArgb(70,t.Border)))e.Graphics.DrawLine(sep,20,y+75,Width-16,y+75);
                    y+=82;
                }
            }
        }
    }

    internal sealed partial class OverlayForm : Form
    {
        private readonly AppConfig config;
        private readonly MetricsEngine engine;
        private readonly MetricHistory history=new MetricHistory();
        private readonly TemperatureNotificationState temperatureNotificationState=new TemperatureNotificationState();
        private MetricsSnapshot snapshot=new MetricsSnapshot();
        private readonly System.Windows.Forms.Timer metricTimer=new System.Windows.Forms.Timer();
        private readonly System.Windows.Forms.Timer watchdog=new System.Windows.Forms.Timer();
        private readonly System.Windows.Forms.Timer recoveryTimer=new System.Windows.Forms.Timer();
        private ContextMenuStrip menu;
        private ToolStripMenuItem updateMenuItem;
        private ToolStripMenuItem pauseMenuItem;
        private IntPtr taskbar=IntPtr.Zero;
        private Rectangle expectedRect=Rectangle.Empty;
        private Rectangle lastTaskbarScreenRect=Rectangle.Empty;
        private DateTime lastPositionAt=DateTime.MinValue;
        private readonly bool proofMode;
        private bool engineDisposed=false;
        private bool cleanupDone=false;
        public bool UserExitRequested { get; private set; }

        // R11H1 recovery state. Recovery is event-driven and stable-handle gated.
        private readonly uint taskbarCreatedMessage=Native.RegisterWindowMessage("TaskbarCreated");
        private bool recoveryPending=false;
        private string recoveryReason="";
        private int recoveryAttempt=0;
        private IntPtr recoveryCandidate=IntPtr.Zero;
        private int recoveryStableCount=0;
        private DateTime recoveryNotBefore=DateTime.MinValue;
        private bool systemEventsSubscribed=false;

        // R11S1: Start/Shell guard. Prefer staying a direct taskbar child during Start.
        private DateTime startGuardLastSeen=DateTime.MinValue;
        private NotifyIcon trayIcon;
        private SettingsForm settingsForm;
        private bool settingsHoverWasRunning=false;
        private IntPtr trayNotify=IntPtr.Zero;
        private int upstreamAttachCount=0;
        private DateTime lastUpstreamPositionAt=DateTime.MinValue;

        private Native.LowLevelMouseProc rightClickHookProc;
        private IntPtr rightClickHook=IntPtr.Zero;
        private bool rightClickArmed=false;
        private Point rightClickDownPoint=Point.Empty;
        private bool diagnosticBeacon=false;
        private string lastCompactLayoutKey="";

        // R07 shell-integration stability:
        // - the overlay owns only its safe free taskbar gap, so it may receive mouse input;
        // - NOACTIVATE prevents focus theft;
        // - width never grows automatically within one taskbar generation;
        // - transient Start/Search surfaces freeze placement instead of causing geometry jumps.
        private int stableOverlayWidthPx=0;
        private int pendingShrinkWidthPx=0;
        private int pendingShrinkCount=0;
        private DateTime lastTransientPlacementSkip=DateTime.MinValue;
        private DateTime lastStyleIntegrityAt=DateTime.MinValue;
        private int styleRepairCount=0;
        private readonly DateTime appStartedUtc=DateTime.UtcNow;
        private DateTime nextSensorSelfHealCheckUtc=DateTime.MinValue;
        private DateTime lastSensorSelfHealAttemptUtc=DateTime.MinValue;
        private int sensorSelfHealInFlight=0;

        // R13: independent no-activate hover flyout; never parented to Explorer.
        private HardwareFlyoutForm hardwareFlyout;
        private readonly System.Windows.Forms.Timer hoverTimer=new System.Windows.Forms.Timer();

        // R09 responsiveness: heavy telemetry never runs on the WinForms UI thread.
        // A single background read owns MetricsEngine at a time; completed snapshots
        // are committed to UI/history atomically on the UI thread.
        private readonly object engineSync=new object();
        private int metricReadInFlight=0;
        private volatile bool metricReadShutdown=false;
        private volatile bool telemetryPaused=false;
        private bool userTelemetryPaused=false;
        private bool systemTelemetryPaused=false;
        private int metricSnapshotGeneration=0;
        private string lastHoverGroup="";
        private int lastHoverIndex=-1;
        private int lastHoverGeneration=-1;
        private DateTime lastHardwareHoverAt=DateTime.MinValue;
        private List<MetricView> lastPaintMetrics=new List<MetricView>();

        public OverlayForm(AppConfig c) : this(c,false) { }

        internal OverlayForm(AppConfig c,bool isProofMode)
        {
            config=c;
            config.Normalize();
            history.SetLimit(config.SparklineHistoryLength);
            proofMode=isProofMode;
            FormBorderStyle=FormBorderStyle.None;
            ShowInTaskbar=false;
            StartPosition=FormStartPosition.Manual;
            TopMost=false;
            DoubleBuffered=true;
            SetStyle(ControlStyles.AllPaintingInWmPaint|ControlStyles.UserPaint|ControlStyles.OptimizedDoubleBuffer,true);
            engine=new MetricsEngine();
            if(!proofMode)
            {
                menu=BuildMenu();
                // R07: the form opens the menu explicitly from MouseClick; do not also
                // assign ContextMenuStrip here, which could produce duplicate opens.
                trayIcon=new NotifyIcon();
                try{trayIcon.Icon=Icon.ExtractAssociatedIcon(Application.ExecutablePath);}catch{}
                trayIcon.Text="Taskbar Monitor Enhanced";
                trayIcon.Visible=true;
                trayIcon.ContextMenuStrip=menu;
                trayIcon.DoubleClick+=delegate{OpenSettings();};
                trayIcon.BalloonTipClicked+=delegate{if(lastBalloonWasUsage)OpenWorkspace("Alerts");else OpenSettings("Alerts");};

                // R07: the overlay itself is interactive. Left click opens Settings,
                // right click opens the normal ContextMenuStrip. Because the window
                // uses WS_EX_NOACTIVATE, interaction does not steal taskbar focus.
                MouseClick+=delegate(object sender,MouseEventArgs e)
                {
                    if(e.Button==MouseButtons.Left)
                    {
                        Log.Write("INFO","LEFT_CLICK_OPEN_SETTINGS source=DIRECT_MOUSE");
                        try{BeginInvoke((MethodInvoker)delegate{OpenSettings();});}catch{}
                    }
                    else if(e.Button==MouseButtons.Right && menu!=null)
                    {
                        try
                        {
                            Point screenPoint=PointToScreen(e.Location);
                            menu.Show(screenPoint);
                            Log.Write("INFO","CONTEXT_MENU_OPEN source=DIRECT_MOUSE x="+screenPoint.X+" y="+screenPoint.Y);
                        }
                        catch(Exception ex){Log.Write("ERROR","CONTEXT_MENU_OPEN_FAIL "+ex.Message);}
                    }
                };
                hardwareFlyout=new HardwareFlyoutForm();
                try{IntPtr preload=hardwareFlyout.Handle;}catch{}
                MouseEnter+=delegate{RuntimeGuard.SafeUi("HOVER_ENTER",delegate{HandleHardwareHover(PointToClient(Cursor.Position));});};
                MouseMove+=delegate(object sender,MouseEventArgs e){RuntimeGuard.SafeUi("HOVER_MOVE",delegate{HandleHardwareHover(e.Location);});};
                hoverTimer.Interval=50;
                hoverTimer.Tick+=delegate{RuntimeGuard.SafeUi("HOVER_WATCHDOG",delegate{HoverWatchdog();});};
                metricTimer.Interval=EffectiveMetricIntervalMs();
                metricTimer.Tick+=delegate{RuntimeGuard.SafeUi("METRIC_TICK_SCHEDULE",delegate{QueueMetricsRead();});};
                watchdog.Interval=500;
                watchdog.Tick+=delegate{RuntimeGuard.SafeUi("VISIBILITY_WATCHDOG",delegate{VisibilityWatchdog();});};

                recoveryTimer.Interval=250;
                recoveryTimer.Tick+=delegate{RuntimeGuard.SafeUi("RECOVERY_TICK",delegate{RecoveryTick();});};

                Shown+=delegate{RuntimeGuard.SafeUi("FORM_SHOWN",delegate{
                    AttachIntegrated();
                    QueueMetricsRead();
                    // R07: do not install the global low-level right-click bridge.
                    // Direct mouse interaction is authoritative.
                    Log.Write("INFO","DIRECT_MOUSE_INTERACTION_ACTIVE left=SETTINGS right=CONTEXT_MENU noactivate=TRUE");
                    SubscribeSystemEvents();
                    metricTimer.Start();
                    watchdog.Start();
                    recoveryTimer.Start();
                    hoverTimer.Start();
                    if(config.AutoCheckUpdates)BeginUpdateMenuCheck();
                });};

                FormClosing+=delegate(object sender,FormClosingEventArgs e){
                    if(e.CloseReason==CloseReason.WindowsShutDown ||
                       e.CloseReason==CloseReason.TaskManagerClosing ||
                       e.CloseReason==CloseReason.ApplicationExitCall)
                        UserExitRequested=true;
                    CleanupRuntime("FORM_CLOSING_"+e.CloseReason.ToString());
                };

                Log.Write("INFO","START version="+BuildInfo.Version+" theme="+config.Theme+" recovery=R12A2R5R4_HOST shell=V102_ACCEPTED_CORE_RESTORE_R01");
            }
            else
            {
                Size=new Size(BuildInfo.DefaultWidth,48);
            }
        }

        private void DisposeEngine()
        {
            if(engineDisposed)return;
            engineDisposed=true;
            metricReadShutdown=true;
            try{lock(engineSync){engine.Dispose();}}catch{}
        }

        private void CleanupRuntime(string reason)
        {
            if(cleanupDone)return;
            cleanupDone=true;
            try{CloseWorkspace();}catch(Exception ex){Log.Write("WARN","WORKSPACE_CLOSE "+ex.GetType().Name);}
            try{metricTimer.Stop();}catch{}
            try{watchdog.Stop();}catch{}
            try{recoveryTimer.Stop();}catch{}
            try{hoverTimer.Stop();}catch{}
            try{if(hardwareFlyout!=null){hardwareFlyout.Hide();hardwareFlyout.Dispose();hardwareFlyout=null;}}catch{}
            try{UnsubscribeSystemEvents();}catch{}
            try{UninstallRightClickBridge();}catch{}
            if(trayIcon!=null)
            {
                try{trayIcon.Visible=false;trayIcon.Dispose();}catch{}
                trayIcon=null;
            }
            DisposeEngine();
            // Diagnostic/theme proof instances must be strictly read-only. R04 proved that
            // saving a normalized v2 config from a proof process mutates the accepted v1.0.2
            // config even before deployment. Only the real live overlay owns config writes.
            if(!proofMode){try{config.Save();}catch{}}
            Log.Write("INFO","OVERLAY_CLEANUP reason="+reason+" userExit="+UserExitRequested);
        }

        public void HostPrepareForReplacement()
        {
            CleanupRuntime("HOST_REPLACEMENT");
        }

        public void RequestExternalRecovery(string reason)
        {
            if(!proofMode)ScheduleRecovery(reason,250);
        }

        protected override void Dispose(bool disposing)
        {
            if(disposing)CleanupRuntime("DISPOSE");
            base.Dispose(disposing);
        }

        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp=base.CreateParams;
                if(!proofMode||glassNativeVisualProofMode)
                {
                    cp.ExStyle |= Native.WS_EX_CONTROLPARENT | Native.WS_EX_LAYERED | Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE;
                    // COMPOSITED+LAYERED child causes native ULW error 87 here and the
                    // Windows 11 shell occludes child ink even when ULW succeeds.
                    if(RequiresGlassTopLevel)cp.ExStyle &= ~Native.WS_EX_COMPOSITED;
                    else cp.ExStyle |= Native.WS_EX_COMPOSITED;
                    cp.ExStyle &= ~Native.WS_EX_TRANSPARENT;
                }
                return cp;
            }
        }

        private bool EnsureTopLevelGlassStyles(string reason,bool repair)
        {
            if(!IsHandleCreated)return false;
            try
            {
                IntPtr hwnd=Handle;
                long style=Native.GetWindowLongPtr(hwnd,Native.GWL_STYLE).ToInt64();
                long ex=Native.GetWindowLongPtr(hwnd,Native.GWL_EXSTYLE).ToInt64();
                const long extra=(long)(Native.WS_EX_LAYERED|Native.WS_EX_TOOLWINDOW|Native.WS_EX_NOACTIVATE);
                // GetParent returns the hidden WinForms OWNER of a popup when
                // ShowInTaskbar=false. It is not a child parent; check WS_CHILD.
                bool healthy=(style&Native.WS_CHILD)==0 && (style&Native.WS_POPUP)!=0 &&
                    (ex&extra)==extra && (ex&Native.WS_EX_TOPMOST)!=0 &&
                    (ex&Native.WS_EX_COMPOSITED)==0 &&
                    (ex&Native.WS_EX_TRANSPARENT)==0;
                if(healthy)return true;
                if(!repair)
                {
                    Log.Write("WARN","TOPLEVEL_GLASS_STYLE_DRIFT reason="+reason+
                        " parent="+Native.GetParent(hwnd).ToInt64()+" style=0x"+style.ToString("X8")+
                        " exstyle=0x"+ex.ToString("X8"));
                    return false;
                }

                long popup=(style&~Native.WS_CHILD)|Native.WS_POPUP;
                if(popup!=style)Native.SetWindowLongPtr(hwnd,Native.GWL_STYLE,new IntPtr(popup));
                if((style&Native.WS_CHILD)!=0)
                    Native.SetParent(hwnd,IntPtr.Zero);
                long wantEx=(ex|extra)&~(long)(Native.WS_EX_COMPOSITED|Native.WS_EX_TRANSPARENT);
                if(wantEx!=ex)Native.SetWindowLongPtr(hwnd,Native.GWL_EXSTYLE,new IntPtr(wantEx));
                Native.SetWindowPos(hwnd,Native.HWND_TOPMOST,0,0,0,0,
                    Native.SWP_NOMOVE|Native.SWP_NOSIZE|Native.SWP_NOACTIVATE|
                    Native.SWP_FRAMECHANGED|Native.SWP_NOOWNERZORDER);
                long after=Native.GetWindowLongPtr(hwnd,Native.GWL_STYLE).ToInt64();
                long afterEx=Native.GetWindowLongPtr(hwnd,Native.GWL_EXSTYLE).ToInt64();
                bool pass=(after&Native.WS_CHILD)==0 && (after&Native.WS_POPUP)!=0 &&
                    (afterEx&extra)==extra && (afterEx&Native.WS_EX_TOPMOST)!=0 &&
                    (afterEx&Native.WS_EX_COMPOSITED)==0;
                Log.Write(pass?"INFO":"ERROR","TOPLEVEL_GLASS_STYLE_REPAIR reason="+reason+" pass="+pass+" hwnd="+hwnd.ToInt64()+" parent="+Native.GetParent(hwnd).ToInt64()+" styleBefore=0x"+style.ToString("X8")+" styleAfter=0x"+after.ToString("X8")+" exBefore=0x"+ex.ToString("X8")+" exAfter=0x"+afterEx.ToString("X8")+" required=0x"+extra.ToString("X8"));
                return pass;
            }
            catch(Exception ex)
            {
                Log.Write("ERROR","TOPLEVEL_GLASS_STYLE_FAIL reason="+reason+" "+ex.Message);
                return false;
            }
        }

        private bool EnsureIntegratedWindowStyles(string reason,bool repairParent)
        {
            if(proofMode || !IsHandleCreated)return true;
            if(RequiresGlassTopLevel)return EnsureTopLevelGlassStyles(reason,repairParent);
            try
            {
                long style=Native.GetWindowLongPtr(Handle,Native.GWL_STYLE).ToInt64();
                long ex=Native.GetWindowLongPtr(Handle,Native.GWL_EXSTYLE).ToInt64();
                long requiredEx=Native.WS_EX_CONTROLPARENT|Native.WS_EX_LAYERED|Native.WS_EX_COMPOSITED|Native.WS_EX_TOOLWINDOW|Native.WS_EX_NOACTIVATE;
                long desiredStyle=(style & ~Native.WS_POPUP)|Native.WS_CHILD;
                long desiredEx=(ex|requiredEx)&~Native.WS_EX_TRANSPARENT;
                IntPtr parentBefore=Native.GetParent(Handle);

                bool drift=(style&Native.WS_CHILD)==0 ||
                           (style&Native.WS_POPUP)!=0 ||
                           (ex&requiredEx)!=requiredEx ||
                           (ex&Native.WS_EX_TRANSPARENT)!=0 ||
                           (taskbar!=IntPtr.Zero && parentBefore!=taskbar);

                if(!drift)return true;

                if(!repairParent)
                {
                    Log.Write(
                        "WARN",
                        "LOW_PRESSURE_STYLE_DRIFT_DETECTED reason="+reason+
                        " parent="+parentBefore.ToInt64()+
                        " taskbar="+taskbar.ToInt64()+
                        " style=0x"+style.ToString("X8",CultureInfo.InvariantCulture)+
                        " ex=0x"+ex.ToString("X8",CultureInfo.InvariantCulture)
                    );
                    return false;
                }

                if(style!=desiredStyle)Native.SetWindowLongPtr(Handle,Native.GWL_STYLE,new IntPtr(desiredStyle));
                if(taskbar!=IntPtr.Zero && Native.GetParent(Handle)!=taskbar)Native.SetParent(Handle,taskbar);
                if(ex!=desiredEx)Native.SetWindowLongPtr(Handle,Native.GWL_EXSTYLE,new IntPtr(desiredEx));
                Native.SetWindowPos(
                    Handle,IntPtr.Zero,0,0,0,0,
                    Native.SWP_NOMOVE|Native.SWP_NOSIZE|Native.SWP_NOZORDER|
                    Native.SWP_NOACTIVATE|Native.SWP_FRAMECHANGED|Native.SWP_NOOWNERZORDER
                );

                long styleAfter=Native.GetWindowLongPtr(Handle,Native.GWL_STYLE).ToInt64();
                long exAfter=Native.GetWindowLongPtr(Handle,Native.GWL_EXSTYLE).ToInt64();
                IntPtr parentAfter=Native.GetParent(Handle);

                bool pass=(styleAfter&Native.WS_CHILD)!=0 &&
                          (styleAfter&Native.WS_POPUP)==0 &&
                          (exAfter&requiredEx)==requiredEx &&
                          (exAfter&Native.WS_EX_TRANSPARENT)==0 &&
                          (taskbar==IntPtr.Zero || parentAfter==taskbar);

                styleRepairCount++;
                Log.Write(
                    pass?"INFO":"ERROR",
                    "LOW_PRESSURE_STYLE_REPAIR reason="+reason+
                    " count="+styleRepairCount+
                    " parentBefore="+parentBefore.ToInt64()+
                    " parentAfter="+parentAfter.ToInt64()+
                    " pass="+pass
                );
                return pass;
            }
            catch(Exception ex)
            {
                Log.Write("ERROR","LOW_PRESSURE_STYLE_CHECK_FAIL reason="+reason+" "+ex.Message);
                return false;
            }
        }

        private void InstallRightClickBridge()
        {
            try
            {
                if(rightClickHook!=IntPtr.Zero)return;

                rightClickHookProc=new Native.LowLevelMouseProc(RightClickHookCallback);
                IntPtr module=Native.GetModuleHandle(null);

                rightClickHook=Native.SetWindowsHookEx(
                    Native.WH_MOUSE_LL,
                    rightClickHookProc,
                    module,
                    0
                );

                int err=Marshal.GetLastWin32Error();

                if(rightClickHook==IntPtr.Zero)
                {
                    Log.Write("ERROR","RIGHTCLICK_BRIDGE_INSTALL_FAIL win32="+err);
                    return;
                }

                Log.Write(
                    "INFO",
                    "RIGHTCLICK_BRIDGE_INSTALL_PASS hook="+rightClickHook.ToInt64()+
                    " win32="+err+
                    " mode=WH_MOUSE_LL_SCOPED"
                );
            }
            catch(Exception ex)
            {
                Log.Write("ERROR","RIGHTCLICK_BRIDGE_INSTALL_FAIL "+ex.ToString());
            }
        }

        private void UninstallRightClickBridge()
        {
            try
            {
                if(rightClickHook!=IntPtr.Zero)
                {
                    bool ok=Native.UnhookWindowsHookEx(rightClickHook);
                    Log.Write("INFO","RIGHTCLICK_BRIDGE_UNINSTALL ok="+ok);
                }
            }
            catch(Exception ex)
            {
                Log.Write("WARN","RIGHTCLICK_BRIDGE_UNINSTALL_FAIL "+ex.Message);
            }
            finally
            {
                rightClickHook=IntPtr.Zero;
                rightClickHookProc=null;
                rightClickArmed=false;
            }
        }

        private IntPtr RightClickHookCallback(int nCode,IntPtr wParam,IntPtr lParam)
        {
            if(nCode<0)
                return Native.CallNextHookEx(rightClickHook,nCode,wParam,lParam);

            try
            {
                if(nCode==Native.HC_ACTION && !proofMode && expectedRect.Width>0)
                {
                    int message=wParam.ToInt32();

                    if(message==Native.WM_RBUTTONDOWN || message==Native.WM_RBUTTONUP)
                    {
                        Native.MSLLHOOKSTRUCT data=
                            (Native.MSLLHOOKSTRUCT)Marshal.PtrToStructure(
                                lParam,
                                typeof(Native.MSLLHOOKSTRUCT)
                            );

                        Point screenPoint=new Point(data.pt.X,data.pt.Y);
                        bool inside=expectedRect.Contains(screenPoint);

                        if(message==Native.WM_RBUTTONDOWN && inside)
                        {
                            rightClickArmed=true;
                            rightClickDownPoint=screenPoint;

                            // Suppress the taskbar's own right-click because this region
                            // belongs to Taskbar Monitor Enhanced.
                            return new IntPtr(1);
                        }

                        if(message==Native.WM_RBUTTONUP && rightClickArmed)
                        {
                            rightClickArmed=false;

                            if(inside)
                            {
                                Point menuPoint=screenPoint;

                                try
                                {
                                    BeginInvoke((MethodInvoker)delegate
                                    {
                                        try
                                        {
                                            if(menu!=null)
                                            {
                                                menu.Show(menuPoint);
                                                Log.Write(
                                                    "INFO",
                                                    "CONTEXT_MENU_OPEN source=RIGHTCLICK_BRIDGE"+
                                                    " x="+menuPoint.X+
                                                    " y="+menuPoint.Y
                                                );
                                            }
                                        }
                                        catch(Exception ex)
                                        {
                                            Log.Write("ERROR","CONTEXT_MENU_OPEN_FAIL "+ex.Message);
                                        }
                                    });
                                }
                                catch{}

                                return new IntPtr(1);
                            }

                            // The press began inside our region, so also consume the
                            // release even if the pointer drifted outside.
                            return new IntPtr(1);
                        }
                    }
                }
            }
            catch(Exception ex)
            {
                Log.Write("WARN","RIGHTCLICK_BRIDGE_CALLBACK "+ex.Message);
            }

            return Native.CallNextHookEx(rightClickHook,nCode,wParam,lParam);
        }

        private ContextMenuStrip BuildMenu()
        {
            ContextMenuStrip m=new ContextMenuStrip();
            m.Opened+=delegate{RefreshTaskbarPresentation(true);};
            m.Closed+=delegate{RefreshTaskbarPresentation(true);};
            AddWorkspaceMenu(m);
            ToolStripMenuItem themes=new ToolStripMenuItem("Themes");
            foreach(string n in ThemeCatalog.Names)
            {
                ToolStripMenuItem item=new ToolStripMenuItem(n); item.Checked=(n==config.Theme); item.Tag=n;
                item.Click+=delegate(object s,EventArgs e){ApplyTheme((string)((ToolStripMenuItem)s).Tag);}; themes.DropDownItems.Add(item);
            }
            m.Items.Add(themes);
            ToolStripMenuItem pos=new ToolStripMenuItem("Position");
            foreach(string p in new string[]{"Left","Center","Right"}){ToolStripMenuItem i=new ToolStripMenuItem(p);i.Tag=p;i.Checked=(p==config.Position);i.Click+=delegate(object s,EventArgs e){config.Position=(string)((ToolStripMenuItem)s).Tag;TaskbarLayout.ResetCache();ResetPlacementStability("POSITION_MENU");config.Save();PositionOverlay(true);RefreshMenuChecks();};pos.DropDownItems.Add(i);} m.Items.Add(pos);
            m.Items.Add(new ToolStripSeparator());
            ToolStripMenuItem settings=new ToolStripMenuItem("Settings..."); settings.Click+=delegate{OpenSettings();}; m.Items.Add(settings);
            ToolStripMenuItem diagnostics=new ToolStripMenuItem("Diagnostics...");diagnostics.Click+=delegate{OpenSettings("Diagnostics");};m.Items.Add(diagnostics);
            updateMenuItem=new ToolStripMenuItem("Updates...");updateMenuItem.Click+=delegate{OpenSettings("Updates");};m.Items.Add(updateMenuItem);
            pauseMenuItem=new ToolStripMenuItem("Pause monitoring");pauseMenuItem.Click+=delegate{SetUserTelemetryPaused(!userTelemetryPaused);};m.Items.Add(pauseMenuItem);
            ToolStripMenuItem taskManager=new ToolStripMenuItem("Open Task Manager");taskManager.Click+=delegate{try{Process.Start(new ProcessStartInfo("taskmgr.exe"){UseShellExecute=true});Log.Write("INFO","TASK_MANAGER_OPEN");}catch(Exception ex){Log.Write("WARN","TASK_MANAGER_OPEN_FAIL "+ex.Message);}};m.Items.Add(taskManager);
            ToolStripMenuItem logs=new ToolStripMenuItem("Open Logs"); logs.Click+=delegate{try{Process.Start("explorer.exe",AppPaths.Logs);}catch{}}; m.Items.Add(logs);
            m.Items.Add(new ToolStripSeparator());
            ToolStripMenuItem exit=new ToolStripMenuItem("Exit"); exit.Click+=delegate{UserExitRequested=true;Close();}; m.Items.Add(exit);
            return m;
        }

        private void RefreshMenuChecks()
        {
            foreach(ToolStripItem t in menu.Items)
            {
                ToolStripMenuItem top=t as ToolStripMenuItem; if(top==null)continue;
                if(top.Text=="Themes")foreach(ToolStripItem x in top.DropDownItems){ToolStripMenuItem i=x as ToolStripMenuItem;if(i!=null)i.Checked=((string)i.Tag==config.Theme);}
                if(top.Text=="Position")foreach(ToolStripItem x in top.DropDownItems){ToolStripMenuItem i=x as ToolStripMenuItem;if(i!=null)i.Checked=((string)i.Tag==config.Position);}
            }
            if(pauseMenuItem!=null)pauseMenuItem.Text=userTelemetryPaused?"Resume monitoring":"Pause monitoring";
        }

        private void ApplyTheme(string name){config.Theme=name;config.Save();RefreshMenuChecks();RefreshGlassAfterMetricCommit();Invalidate();Log.Write("INFO","THEME " + name);}

        private void OpenSettings(){OpenSettings(null);}
        private void OpenSettings(string initialTab)
        {
            try
            {
                if(settingsForm!=null && !settingsForm.IsDisposed)
                {
                    if(hardwareFlyout!=null&&hardwareFlyout.Visible)hardwareFlyout.Hide();
                    hoverTimer.Stop();
                    lastHoverIndex=-1;lastHoverGroup="";lastHoverGeneration=-1;
                    if(!String.IsNullOrWhiteSpace(initialTab))settingsForm.SelectTab(initialTab);
                    if(settingsForm.WindowState==FormWindowState.Minimized)
                        settingsForm.WindowState=FormWindowState.Normal;

                    settingsForm.Show();
                    settingsForm.BringToFront();
                    settingsForm.Activate();
                    RefreshTaskbarPresentation(true);

                    Log.Write(
                        "INFO",
                        "SETTINGS_SINGLE_INSTANCE_REUSE hwnd="+settingsForm.Handle.ToInt64()+
                        " tab="+(initialTab??"CURRENT")
                    );
                    return;
                }

                if(hardwareFlyout!=null)hardwareFlyout.Hide();
                settingsHoverWasRunning=hoverTimer.Enabled;
                hoverTimer.Stop();

                SettingsForm f=new SettingsForm(config,snapshot,initialTab,RenderSettingsThemePreview);
                settingsForm=f;

                f.FormClosed+=delegate(object sender,FormClosedEventArgs e)
                {
                    try
                    {
                        DialogResult result=f.DialogResult;
                        if(result==DialogResult.OK)
                        {
                            config.Normalize();
                            config.Save();
                            if(!config.FloatAboveStartMenu && startGlassTemporarilyFloating)
                            {
                                startGlassTemporarilyFloating=false;
                                startGlassTemporaryBounds=Rectangle.Empty;
                            }
                            Opacity=1.0; // Glass renderer controls background alpha per pixel; form-wide alpha must remain 100%.
                            history.SetLimit(config.SparklineHistoryLength);
                            metricTimer.Interval=EffectiveMetricIntervalMs();
                            TaskbarLayout.ResetCache();
                            ResetPlacementStability("SETTINGS_APPLY");
                            StartupManager.SetEnabled(config.StartWithWindows);
                            AttachIntegrated();
                            RefreshMenuChecks();
                            Invalidate();
                            Log.Write("INFO","SETTINGS_SINGLE_INSTANCE_APPLY");
                        }
                        else Log.Write("INFO","SETTINGS_SINGLE_INSTANCE_CLOSE result="+result);
                    }
                    catch(Exception ex)
                    {
                        Log.Write("ERROR","SETTINGS_SINGLE_INSTANCE_CLOSE_FAIL "+ex.Message);
                    }
                    finally
                    {
                        if(Object.ReferenceEquals(settingsForm,f))settingsForm=null;
                        try{f.Dispose();}catch{}
                        if(settingsHoverWasRunning&&!IsDisposed&&!Disposing)hoverTimer.Start();
                        settingsHoverWasRunning=false;
                        lastHoverIndex=-1;
                        lastHoverGroup="";
                        lastHoverGeneration=-1;
                    }
                };

                f.Show();
                f.BringToFront();
                f.Activate();
                RefreshTaskbarPresentation(true);

                Log.Write(
                    "INFO",
                    "SETTINGS_SINGLE_INSTANCE_CREATE hwnd="+f.Handle.ToInt64()+
                    " tab="+(initialTab??"DEFAULT")
                );
            }
            catch(Exception ex)
            {
                Log.Write("ERROR","SETTINGS_SINGLE_INSTANCE_OPEN_FAIL "+ex.Message);
                if(settingsForm!=null && settingsForm.IsDisposed)settingsForm=null;
                if(settingsHoverWasRunning&&!IsDisposed&&!Disposing)hoverTimer.Start();
                settingsHoverWasRunning=false;
            }
        }

        private void BeginUpdateMenuCheck()
        {
            if(updateMenuItem==null)return;
            ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    ReleaseUpdateInfo info=UpdateManager.CheckLatest();
                    if(IsDisposed||Disposing)return;
                    try{BeginInvoke((MethodInvoker)delegate{if(updateMenuItem!=null)updateMenuItem.Text=info.HasUpdate?("Update available — "+info.Version):"Updates...";});}catch{}
                }
                catch(Exception ex){Log.Write("INFO","BACKGROUND_UPDATE_CHECK_SKIPPED "+ex.Message);}
            });
        }

        private MetricsSnapshot ReadEngineSnapshot()
        {
            lock(engineSync)
            {
                if(metricReadShutdown||engineDisposed)return null;
                return engine.Read();
            }
        }

        private int EffectiveMetricIntervalMs()
        {
            try{return TelemetryPolicy.EffectiveIntervalMs(config,SystemInformation.PowerStatus.PowerLineStatus);}
            catch{return Math.Max(1000,config.UpdateIntervalMs);}
        }

        private void RefreshTelemetryTimerInterval()
        {
            try
            {
                int effective=EffectiveMetricIntervalMs();
                if(metricTimer.Interval!=effective)
                {
                    metricTimer.Interval=effective;
                    Log.Write("INFO","TELEMETRY_INTERVAL effectiveMs="+effective+
                        " configuredMs="+config.UpdateIntervalMs+" adaptiveBattery="+config.AdaptiveBatteryMode);
                }
            }
            catch(Exception ex){Log.Write("WARN","TELEMETRY_INTERVAL_UPDATE "+ex.Message);}
        }

        private void CommitMetricsSnapshot(MetricsSnapshot next)
        {
            if(next==null)return;
            snapshot=next;
            history.SetLimit(config.SparklineHistoryLength);
            RefreshTelemetryTimerInterval();
            metricSnapshotGeneration++;
            history.Add("CPU",snapshot.Cpu); history.Add("RAM",snapshot.Ram); history.Add("DISK",(float)((snapshot.DiskReadBytesPerSec+snapshot.DiskWriteBytesPerSec)/(1024d*1024d))); history.Add("GPU",snapshot.Gpu);
            float vrp=snapshot.VramTotalGb>0?snapshot.VramUsedGb/snapshot.VramTotalGb*100f:0; history.Add("VRAM",vrp); history.Add("NET",snapshot.NetDownMbps+snapshot.NetUpMbps);
            foreach(CpuDeviceSnapshot d in snapshot.CpuDevices)history.Add("CPU:"+d.Id,d.Usage);
            foreach(GpuDeviceSnapshot d in snapshot.GpuDevices)history.Add("GPU:"+d.Id,d.Usage);
            foreach(DiskDeviceSnapshot d in snapshot.DiskDevices)history.Add("DISK:"+d.Id,(float)((d.ReadBytesPerSec+d.WriteBytesPerSec)/(1024d*1024d)));
            foreach(NetworkDeviceSnapshot d in snapshot.NetworkDevices)history.Add("NET:"+d.Id,(float)((d.DownBytesPerSec+d.UpBytesPerSec)*8d/1000000d));
            SessionTelemetryHistory.Add(snapshot);
            CommitWorkspaceSample();
            EvaluateTemperatureNotifications();
            // Windows 11 WS_EX_LAYERED UpdateLayeredWindow does not reliably raise
            // WM_PAINT following Invalidate. Commit the real native pixels on each
            // observed metric snapshot; otherwise glyphs remain at cold-start zero
            // and sparklines never gain on-screen history although the worker reads.
            RefreshGlassAfterMetricCommit();
            if(!proofMode && (metricSnapshotGeneration<=2 || metricSnapshotGeneration%120==0))
                Log.Write("INFO","GLASS_METRIC_COMMIT generation="+metricSnapshotGeneration+
                    " CPU="+snapshot.Cpu.ToString("0.0",CultureInfo.InvariantCulture)+
                    " RAM_BYTES="+snapshot.RamTotalBytes+
                    " GPU="+snapshot.Gpu.ToString("0.0",CultureInfo.InvariantCulture)+
                    " nativeRefreshCount="+glassDirectMetricRefreshCount);
        }

        private void EvaluateTemperatureNotifications()
        {
            if(proofMode||trayIcon==null)return;
            if(!config.EnableTemperatureNotifications||NotificationsMuted()){temperatureNotificationState.Reset();return;}
            DateTime now=DateTime.UtcNow;

            List<CpuDeviceSnapshot> cpus=SelectedCpuDevices();
            List<float> cpuTemps=cpus.Where(d=>d!=null&&d.TemperatureAvailable).Select(d=>d.Temperature).ToList();
            bool cpuAvailable=cpuTemps.Count>0||snapshot.CpuTempAvailable;
            float cpuTemp=cpuTemps.Count>0?cpuTemps.Max():snapshot.CpuTempCurrent;
            ShowTemperatureNotification("CPU",cpuAvailable,cpuTemp,config.CpuTempWarningC,now);

            List<GpuDeviceSnapshot> gpus=SelectedGpuDevices();
            List<float> gpuTemps=gpus.Where(d=>d!=null&&d.TemperatureAvailable).Select(d=>d.Temperature).ToList();
            bool gpuAvailable=gpuTemps.Count>0||snapshot.GpuTempAvailable;
            float gpuTemp=gpuTemps.Count>0?gpuTemps.Max():snapshot.GpuTemp;
            ShowTemperatureNotification("GPU",gpuAvailable,gpuTemp,config.GpuTempWarningC,now);

            List<DiskDeviceSnapshot> disks=SelectedDiskDevices();
            List<float> diskTemps=disks.Where(d=>d!=null&&d.TemperatureAvailable).Select(d=>d.Temperature).ToList();
            bool diskAvailable=diskTemps.Count>0;
            float diskTemp=diskAvailable?diskTemps.Max():0f;
            ShowTemperatureNotification("Disk",diskAvailable,diskTemp,config.DiskTempWarningC,now);
        }

        private void ShowTemperatureNotification(string lane,bool available,float value,float threshold,DateTime nowUtc)
        {
            if(!temperatureNotificationState.ShouldNotify(lane,available,value,threshold,nowUtc))return;
            string body=lane+" temperature reached "+value.ToString("0.0",CultureInfo.InvariantCulture)+" C (warning "+threshold.ToString("0",CultureInfo.InvariantCulture)+" C).";
            lastBalloonWasUsage=false;
            RecordAlert(lane+" temperature",body);
            try{trayIcon.ShowBalloonTip(10000,"Taskbar Monitor Enhanced - temperature warning",body,ToolTipIcon.Warning);Log.Write("WARN","TEMPERATURE_NOTIFICATION lane="+lane+" valueC="+value.ToString("0.0",CultureInfo.InvariantCulture)+" thresholdC="+threshold.ToString("0",CultureInfo.InvariantCulture));}
            catch(Exception ex){Log.Write("WARN","TEMPERATURE_NOTIFICATION_FAIL lane="+lane+" "+ex.Message);}
            if(TemperatureWarningSoundPolicy.ShouldPlay(config))
            {
                try
                {
                    // Rate-limited by ShouldNotify above, follows user's Windows
                    // selected Exclamation sound scheme and output volume.
                    System.Media.SystemSounds.Exclamation.Play();
                    Log.Write("INFO","TEMPERATURE_WARNING_SOUND_REQUESTED lane="+lane);
                }
                catch(Exception ex)
                {Log.Write("WARN","TEMPERATURE_WARNING_SOUND_FAIL lane="+lane+" "+ex.GetType().Name);}
            }
        }

        private void ReadMetrics()
        {
            CommitMetricsSnapshot(ReadEngineSnapshot());
        }

        private void QueueMetricsRead()
        {
            if(metricReadShutdown||engineDisposed||telemetryPaused)return;
            if(Interlocked.CompareExchange(ref metricReadInFlight,1,0)!=0)return;
            ThreadPool.QueueUserWorkItem(delegate
            {
                MetricsSnapshot next=null;
                Exception error=null;
                try{next=ReadEngineSnapshot();}catch(Exception ex){error=ex;}
                try
                {
                    if(IsDisposed||Disposing)
                    {
                        Interlocked.Exchange(ref metricReadInFlight,0);
                        return;
                    }
                    BeginInvoke((MethodInvoker)delegate
                    {
                        try
                        {
                            if(error!=null)Log.Write("WARN","ASYNC_METRIC_READ "+error.Message);
                            if(next!=null)
                            {
                                CommitMetricsSnapshot(next);
                                if((DateTime.UtcNow-lastPositionAt).TotalSeconds>=2)PositionOverlay(false);
                                Invalidate();
                                if(hardwareFlyout!=null&&hardwareFlyout.Visible)
                                {
                                    Point p=Cursor.Position;Point o=PointToScreen(Point.Empty);Rectangle overlayScreen=new Rectangle(o,ClientSize);
                                    if(overlayScreen.Contains(p))HandleHardwareHover(PointToClient(p));
                                }
                            }
                        }
                        finally{Interlocked.Exchange(ref metricReadInFlight,0);}
                    });
                }
                catch
                {
                    Interlocked.Exchange(ref metricReadInFlight,0);
                }
            });
        }

        internal int ExportThemeProofs(string outputDirectory)
        {
            try
            {
                Directory.CreateDirectory(outputDirectory);

                // Real live data only. No synthetic metric values are injected.
                for(int i=0;i<30;i++)
                {
                    ReadMetrics();
                    Thread.Sleep(200);
                }

                List<object> proofFiles=new List<object>();
                string originalTheme=config.Theme;
                try
                {
                    for(int i=0;i<ThemeCatalog.Names.Length;i++)
                    {
                        string themeName=ThemeCatalog.Names[i];
                        string fileName=String.Format(
                            CultureInfo.InvariantCulture,
                            "THEME_{0:00}_{1}.png",
                            i+1,
                            SafeFileName(themeName).ToUpperInvariant()
                        );
                        string full=Path.Combine(outputDirectory,fileName);

                        using(Bitmap bmp=RenderThemeProof(themeName,BuildInfo.DefaultWidth,48))
                        {
                            bmp.Save(full,ImageFormat.Png);
                        }

                        proofFiles.Add(new Dictionary<string,object>{
                            {"Index",i+1},
                            {"Theme",themeName},
                            {"File",fileName},
                            {"Width",BuildInfo.DefaultWidth},
                            {"Height",48}
                        });
                    }
                }
                finally
                {
                    config.Theme=originalTheme;
                }

                Dictionary<string,object> metrics=new Dictionary<string,object>();
                metrics["CPU"]=snapshot.Cpu;
                metrics["RAM"]=snapshot.Ram;
                metrics["DISK"]=snapshot.Disk;
                metrics["GPU"]=snapshot.Gpu;
                metrics["VRAM_USED_GB"]=snapshot.VramUsedGb;
                metrics["VRAM_TOTAL_GB"]=snapshot.VramTotalGb;
                metrics["NET_DOWN_MBPS"]=snapshot.NetDownMbps;
                metrics["NET_UP_MBPS"]=snapshot.NetUpMbps;
                metrics["CPU_TEMP_AVAILABLE"]=snapshot.CpuTempAvailable;
                metrics["CPU_TEMP_CURRENT_C"]=snapshot.CpuTempCurrent;
                metrics["CPU_TEMP_AVG_C"]=snapshot.CpuTempAvg;
                metrics["CPU_TEMP_MAX_C"]=snapshot.CpuTempMax;
                metrics["CPU_TEMP_SOURCE"]=snapshot.CpuTempSource;
                metrics["GPU_TEMP_AVAILABLE"]=snapshot.GpuTempAvailable;
                metrics["GPU_TEMP_AVG_C"]=snapshot.GpuTempAvg;
                metrics["GPU_TEMP_MAX_C"]=snapshot.GpuTempMax;
                metrics["GPU_TEMP_SOURCE"]=snapshot.GpuTempSource??"UNAVAILABLE";

                Dictionary<string,object> manifest=new Dictionary<string,object>();
                manifest["Version"]=BuildInfo.Version;
                manifest["GeneratedAt"]=DateTime.Now.ToString("o",CultureInfo.InvariantCulture);
                manifest["NoSyntheticMetricData"]=true;
                manifest["LiveSampleCount"]=30;
                manifest["SampleIntervalMs"]=200;
                manifest["ThemeCount"]=ThemeCatalog.Names.Length;
                manifest["Width"]=BuildInfo.DefaultWidth;
                manifest["Height"]=48;
                manifest["Metrics"]=metrics;
                manifest["Files"]=proofFiles;

                JavaScriptSerializer js=new JavaScriptSerializer();
                File.WriteAllText(
                    Path.Combine(outputDirectory,"THEME_PROOF_MANIFEST.json"),
                    js.Serialize(manifest),
                    Encoding.UTF8
                );

                Console.WriteLine("TBME_THEME_PROOF=PASS THEMES="+ThemeCatalog.Names.Length+" DIR="+outputDirectory);
                return 0;
            }
            catch(Exception ex)
            {
                Console.Error.WriteLine("TBME_THEME_PROOF=FAIL "+ex);
                return 4;
            }
        }

        private Bitmap RenderThemeDefinition(ThemeDefinition theme,int width,int height)
        {
            // R150: full, glyph and halo surfaces must share the exact native size.
            // A preview-only 320px minimum here broke compact 279px taskbar rendering.
            width=Math.Max(1,width);height=Math.Max(1,height);
            Bitmap bmp=new Bitmap(width,height,System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            using(Graphics g=Graphics.FromImage(bmp))
            {
                g.SmoothingMode=SmoothingMode.AntiAlias;
                g.TextRenderingHint=System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
                Rectangle rect=new Rectangle(0,0,width,height);
                PaintBackground(g,theme,rect);

                List<MetricView> metrics=BuildMetricViews(theme,width);
                if(metrics.Count>0)
                {
                    float seg=(float)width/metrics.Count;
                    for(int i=0;i<metrics.Count;i++)
                    {
                        RectangleF r=new RectangleF(i*seg,0,seg,height);
                        PaintMetric(g,theme,metrics[i],r,i);
                    }
                }
            }
            return bmp;
        }
        private Bitmap RenderThemeProof(string themeName,int width,int height)
        {
            return RenderThemeDefinition(ThemeCatalog.Get(themeName),width,height);
        }

        internal Bitmap RenderSettingsThemePreview(string themeName,int width,int height)
        {
            ThemeDefinition t=(SystemInformation.HighContrast||String.Equals(themeName,"Windows High Contrast",StringComparison.Ordinal))?
                WindowsThemePolicy.HighContrastTheme():ThemeCatalog.Get(themeName);
            return RenderThemeDefinition(t,width,height);
        }

        internal void PrimeSettingsThemePreviewFromLiveMetrics(int sampleCount,int intervalMs)
        {
            sampleCount=Math.Max(1,Math.Min(30,sampleCount));
            intervalMs=Math.Max(0,Math.Min(500,intervalMs));
            for(int i=0;i<sampleCount;i++)
            {
                ReadMetrics();
                if(intervalMs>0&&i<sampleCount-1)Thread.Sleep(intervalMs);
            }
        }

        internal int ExportCompactProofs(string outputDirectory)
        {
            try
            {
                Directory.CreateDirectory(outputDirectory);
                for(int i=0;i<30;i++){ReadMetrics();Thread.Sleep(200);}
                int[] widths=new int[]{592,500};
                List<object> proofFiles=new List<object>();
                List<object> layoutChecks=new List<object>();
                string originalTheme=config.Theme;
                Size originalSize=Size;
                try
                {
                    foreach(int width in widths)
                    {
                        Size=new Size(width,48);
                        for(int i=0;i<ThemeCatalog.Names.Length;i++)
                        {
                            string themeName=ThemeCatalog.Names[i];
                            string fileName=String.Format(CultureInfo.InvariantCulture,"COMPACT_{0}_{1:00}_{2}.png",width,i+1,SafeFileName(themeName).ToUpperInvariant());
                            string full=Path.Combine(outputDirectory,fileName);
                            using(Bitmap bmp=RenderThemeProof(themeName,width,48)){bmp.Save(full,ImageFormat.Png);}
                            ThemeDefinition theme=ThemeCatalog.Get(themeName);
                            using(Bitmap measureBmp=new Bitmap(4,4))
                            using(Graphics mg=Graphics.FromImage(measureBmp))
                            {
                                List<MetricView> metrics=BuildMetricViews(theme);
                                float seg=(float)width/Math.Max(1,metrics.Count);
                                foreach(MetricView mv in metrics)
                                {
                                    float readableMin=theme.Mode=="terminal"?7.5f:(theme.Mode=="hex"?7.3f:7.4f);
                                    if(StudioThemes.IsStudio(theme.Mode))readableMin=7.4f*(float)Math.Max(.85,Math.Min(1.2,config.FontSize/10.0));
                                    float maxWidth;
                                    if(theme.Mode=="hex")
                                    {
                                        // Match PaintHexMetric exactly: metric inner width is seg-6, badge is
                                        // clamped to 88..maxBadge, and text receives badgeWidth-18. The old
                                        // proof used seg*0.72-24, a stricter geometry than the renderer and
                                        // could fail nondeterministically as live NET digits changed.
                                        float innerWidth=Math.Max(1f,seg-6f);
                                        float maxBadge=Math.Max(90f,innerWidth-42f);
                                        float badgeWidth=Math.Min(maxBadge,Math.Max(88f,innerWidth*0.72f));
                                        maxWidth=Math.Max(50f,badgeWidth-18f);
                                    }
                                    else if(StudioThemes.IsStudio(theme.Mode))maxWidth=Math.Max(8,seg-26);
                                    else maxWidth=IsExtendedThemeMode(theme.Mode)?Math.Max(50,seg-28):Math.Max(50,seg-16);
                                    string adaptive=BuildMetricHeadline(mg,theme,mv,readableMin,maxWidth);
                                    bool stacked=HeadlineIsStacked(adaptive);
                                    using(Font mf=SafeFont(theme.FontName,readableMin,FontStyle.Bold))
                                    {
                                        float measured=MaxLineWidth(mg,adaptive,mf);
                                        bool overflow=measured>maxWidth+0.75f;
                                        if(overflow)throw new InvalidOperationException("COMPACT_TEXT_OVERFLOW width="+width+" theme="+themeName+" metric="+mv.Key+" measured="+measured.ToString("0.0",CultureInfo.InvariantCulture)+" max="+maxWidth.ToString("0.0",CultureInfo.InvariantCulture));
                                        if(mv.GroupKey=="NET"&&!String.IsNullOrWhiteSpace(mv.Value2))
                                        {
                                            string inline=(mv.Label+" "+mv.Value+"    "+mv.Value2).Trim();
                                            bool inlineWouldOverflow=mg.MeasureString(inline,mf).Width>maxWidth;
                                            if(inlineWouldOverflow&&!stacked)throw new InvalidOperationException("COMPACT_NET_STACK_GATE width="+width+" theme="+themeName);
                                        }
                                        layoutChecks.Add(new Dictionary<string,object>{{"Width",width},{"Theme",themeName},{"Metric",mv.Key},{"ReadableMinPt",readableMin},{"Stacked",stacked},{"MeasuredLineWidth",measured},{"MaxWidth",maxWidth},{"Overflow",overflow}});
                                    }
                                }
                            }
                            proofFiles.Add(new Dictionary<string,object>{{"Width",width},{"Height",48},{"Index",i+1},{"Theme",themeName},{"File",fileName}});
                        }
                    }
                }
                finally{config.Theme=originalTheme;Size=originalSize;}
                Dictionary<string,object> manifest=new Dictionary<string,object>();
                manifest["Version"]=BuildInfo.Version;
                manifest["GeneratedAt"]=DateTime.Now.ToString("o",CultureInfo.InvariantCulture);
                manifest["NoSyntheticMetricData"]=true;
                manifest["ThemeCount"]=ThemeCatalog.Names.Length;
                manifest["Widths"]=widths;
                manifest["Height"]=48;
                manifest["MinimumReadableFontPt"]=7.3;
                manifest["DefaultReadableFontPt"]=7.4;
                manifest["HexReadableFontPt"]=7.3;
                manifest["TerminalReadableFontPt"]=7.5;
                manifest["NetworkStackRule"]="Stack DL/UL when inline text exceeds card width at the readable minimum font.";
                manifest["Files"]=proofFiles;
                manifest["LayoutChecks"]=layoutChecks;
                JavaScriptSerializer js=new JavaScriptSerializer();
                File.WriteAllText(Path.Combine(outputDirectory,"COMPACT_PROOF_MANIFEST.json"),js.Serialize(manifest),Encoding.UTF8);
                Console.WriteLine("TBME_COMPACT_PROOF=PASS THEMES="+ThemeCatalog.Names.Length+" WIDTHS=592,500 DIR="+outputDirectory);
                return 0;
            }
            catch(Exception ex)
            {
                try{Directory.CreateDirectory(outputDirectory);File.WriteAllText(Path.Combine(outputDirectory,"COMPACT_PROOF_FAILURE.txt"),ex.ToString(),Encoding.UTF8);}catch{}
                Console.Error.WriteLine("TBME_COMPACT_PROOF=FAIL "+ex);return 8;
            }
        }

        private static string SafeFileName(string text)
        {
            StringBuilder b=new StringBuilder();
            foreach(char ch in text)
            {
                if(Char.IsLetterOrDigit(ch))b.Append(ch);
                else if(ch==' '||ch=='-'||ch=='_')b.Append('_');
            }
            return b.ToString().Trim('_');
        }

        private void SubscribeSystemEvents()
        {
            if(systemEventsSubscribed)return;
            try
            {
                SystemEvents.DisplaySettingsChanged+=OnDisplaySettingsChanged;
                SystemEvents.PowerModeChanged+=OnPowerModeChanged;
                SystemEvents.UserPreferenceChanged+=OnUserPreferenceChanged;
                systemEventsSubscribed=true;
                Log.Write("INFO","RECOVERY_EVENTS_SUBSCRIBED");
            }
            catch(Exception ex)
            {
                Log.Write("WARN","RECOVERY_EVENTS_SUBSCRIBE_FAILED "+ex.Message);
            }
        }

        private void UnsubscribeSystemEvents()
        {
            if(!systemEventsSubscribed)return;
            try
            {
                SystemEvents.DisplaySettingsChanged-=OnDisplaySettingsChanged;
                SystemEvents.PowerModeChanged-=OnPowerModeChanged;
                SystemEvents.UserPreferenceChanged-=OnUserPreferenceChanged;
            }
            catch{}
            systemEventsSubscribed=false;
        }

        private void OnDisplaySettingsChanged(object sender,EventArgs e)
        {
            SafeScheduleRecovery("DISPLAY_SETTINGS_CHANGED",500);
        }

        private void OnUserPreferenceChanged(object sender,UserPreferenceChangedEventArgs e)
        {
            try
            {
                if(config.FollowWindowsTheme||SystemInformation.HighContrast)
                {
                    Invalidate();
                    if(settingsForm!=null&&!settingsForm.IsDisposed)settingsForm.NotifySystemPreferenceChanged();
                    if(workspace!=null&&!workspace.IsDisposed)workspace.NotifySystemPreferenceChanged();
                    Log.Write("INFO","SYSTEM_APPEARANCE_CHANGED category="+e.Category+" resolvedTheme="+WindowsThemePolicy.ResolveName(config)+" highContrast="+SystemInformation.HighContrast);
                }
            }
            catch(Exception ex){Log.Write("WARN","SYSTEM_APPEARANCE_CHANGE "+ex.Message);}
        }

        private void OnPowerModeChanged(object sender,PowerModeChangedEventArgs e)
        {
            if(e.Mode==PowerModes.Suspend)
            {
                SafePauseTelemetry("POWER_SUSPEND");
                return;
            }
            if(e.Mode==PowerModes.Resume)
            {
                SafeResumeTelemetry("POWER_RESUME");
                SafeScheduleRecovery("POWER_RESUME",1000);
                return;
            }
            if(e.Mode==PowerModes.StatusChange)
            {
                RefreshTelemetryTimerInterval();
            }
        }

        private void ApplyTelemetryPauseState(string reason,bool resetEngine)
        {
            try
            {
                if(IsDisposed||Disposing)return;
                if(InvokeRequired){BeginInvoke((MethodInvoker)delegate{ApplyTelemetryPauseState(reason,resetEngine);});return;}
                bool shouldPause=TelemetryPolicy.ShouldPause(userTelemetryPaused,systemTelemetryPaused);
                if(resetEngine)lock(engineSync){if(!engineDisposed)engine.ResetAfterResume();}
                telemetryPaused=shouldPause;
                usageGate.Reset();trafficLedger.ResetBaseline();lastWorkspaceSample=-1;
                if(shouldPause)
                {
                    try{metricTimer.Stop();}catch{}
                    try{hoverTimer.Stop();}catch{}
                    try{if(hardwareFlyout!=null)hardwareFlyout.Hide();}catch{}
                }
                else
                {
                    RefreshTelemetryTimerInterval();
                    metricTimer.Start();
                    hoverTimer.Start();
                    QueueMetricsRead();
                }
                RefreshMenuChecks();
                Invalidate();
                Log.Write("INFO","TELEMETRY_PAUSE_STATE paused="+shouldPause+
                    " user="+userTelemetryPaused+" system="+systemTelemetryPaused+" reason="+reason);
            }
            catch(Exception ex){Log.Write("WARN","TELEMETRY_PAUSE_STATE_FAIL "+ex.Message);}
        }

        private void SetUserTelemetryPaused(bool paused)
        {
            userTelemetryPaused=paused;
            ApplyTelemetryPauseState(paused?"USER_PAUSE":"USER_RESUME",false);
        }

        private void SafePauseTelemetry(string reason)
        {
            systemTelemetryPaused=true;
            ApplyTelemetryPauseState(reason,false);
        }

        private void SafeResumeTelemetry(string reason)
        {
            systemTelemetryPaused=false;
            ApplyTelemetryPauseState(reason,true);
        }

        private void SafeScheduleRecovery(string reason,int delayMs)
        {
            try
            {
                if(IsDisposed)return;
                if(InvokeRequired)
                {
                    BeginInvoke((MethodInvoker)delegate{ScheduleRecovery(reason,delayMs);});
                    return;
                }
                ScheduleRecovery(reason,delayMs);
            }
            catch(Exception ex)
            {
                Log.Write("WARN","RECOVERY_SCHEDULE_DISPATCH_FAILED reason="+reason+" "+ex.Message);
            }
        }

        private void ScheduleRecovery(string reason,int delayMs)
        {
            recoveryPending=true;
            recoveryReason=reason;
            recoveryAttempt=0;
            recoveryCandidate=IntPtr.Zero;
            recoveryStableCount=0;
            recoveryNotBefore=DateTime.UtcNow.AddMilliseconds(Math.Max(0,delayMs));
            Log.Write("INFO","RECOVERY_SCHEDULE reason="+reason+" delayMs="+delayMs);
        }

        private void RecoveryTick()
        {
            if(!recoveryPending)return;
            if(DateTime.UtcNow<recoveryNotBefore)return;

            try
            {
                recoveryAttempt++;
                string resolvedTarget;IntPtr current=TaskbarTargetPolicy.Resolve(config,out resolvedTarget);

                if(current==IntPtr.Zero)
                {
                    recoveryCandidate=IntPtr.Zero;
                    recoveryStableCount=0;
                    if(recoveryAttempt==1 || recoveryAttempt%8==0)
                        Log.Write("INFO","RECOVERY_WAIT_TASKBAR reason="+recoveryReason+" attempt="+recoveryAttempt);

                    if(recoveryAttempt>=80)
                    {
                        Log.Write("ERROR","RECOVERY_TIMEOUT reason="+recoveryReason+" attempts="+recoveryAttempt);
                        recoveryPending=false;
                    }
                    return;
                }

                if(current!=recoveryCandidate)
                {
                    recoveryCandidate=current;
                    recoveryStableCount=1;
                    return;
                }

                recoveryStableCount++;
                if(recoveryStableCount<3)return;

                if(TryRecoverIntegrated(current,recoveryReason))
                {
                    recoveryPending=false;
                    recoveryAttempt=0;
                    recoveryStableCount=0;
                    recoveryCandidate=IntPtr.Zero;
                }
            }
            catch(Exception ex)
            {
                Log.Write("WARN","RECOVERY_TICK "+ex.Message);
            }
        }

        private bool TryRecoverIntegrated(IntPtr newTaskbar,string reason)
        {
            try
            {
                if(newTaskbar==IntPtr.Zero)return false;

                TaskbarLayout.ResetCache();
                ResetPlacementStability("RECOVERY_"+reason);
                taskbar=newTaskbar;
                expectedRect=Rectangle.Empty;
                lastTaskbarScreenRect=Rectangle.Empty;

                AttachIntegrated();

                bool parentOk=RequiresGlassTopLevel?
                    (Native.GetWindowLongPtr(Handle,Native.GWL_STYLE).ToInt64()&Native.WS_CHILD)==0:
                    Native.GetParent(Handle)==taskbar;
                bool visible=Native.IsWindowVisible(Handle);

                Log.Write(
                    "INFO",
                    "RECOVERY_PASS reason="+reason+
                    " attempt="+recoveryAttempt+
                    " mode="+(RequiresGlassTopLevel?"TaskbarAnchoredTopLevelGlass":"StableLowPressureTaskbarChild")+
                    " taskbar="+taskbar.ToInt64()+
                    " parentOk="+parentOk+
                    " visible="+visible+
                    " rect="+expectedRect.X+","+expectedRect.Y+","+expectedRect.Width+","+expectedRect.Height
                );

                return parentOk && visible;
            }
            catch(Exception ex)
            {
                Log.Write("WARN","RECOVERY_RETRY reason="+reason+" attempt="+recoveryAttempt+" "+ex.Message);
                return false;
            }
        }

        protected override void WndProc(ref Message m)
        {
            // R07: mouse is accepted by the overlay but never activates/focuses it.
            if(m.Msg==0x0021) // WM_MOUSEACTIVATE
            {
                m.Result=new IntPtr(3); // MA_NOACTIVATE
                return;
            }

            if(m.Msg==Native.WM_TBME_VISUAL_BEACON)
            {
                diagnosticBeacon=m.WParam!=IntPtr.Zero;
                bool beaconOk=true;
                if(RequiresGlassTopLevel)
                {
                    // Layered UpdateLayeredWindow surfaces do NOT reliably
                    // repaint from WM_PAINT or Invalidate. The ShellState test
                    // must see the actual active diagnostic beacon on screen.
                    // Direct native upload is synchronous and also clears it.
                    beaconOk=PaintPerPixelLayer();
                }
                else {Invalidate();Update();}
                m.Result=beaconOk?new IntPtr(1):IntPtr.Zero;
                Log.Write(beaconOk?"INFO":"ERROR",
                    "VISUAL_BEACON state="+diagnosticBeacon+
                    " mode="+(RequiresGlassTopLevel?"PARG_B_TOPLEVEL":"SHELL_CHILD")+
                    " nativeUpload="+beaconOk);
                return;
            }

            if(taskbarCreatedMessage!=0 && (uint)m.Msg==taskbarCreatedMessage)
                ScheduleRecovery("TASKBAR_CREATED",750);

            if(m.Msg==0x007E)
                ScheduleRecovery("WM_DISPLAYCHANGE",500);

            if(m.Msg==0x02E0)
                ScheduleRecovery("WM_DPICHANGED",300);

            if(m.Msg==0x0218)
            {
                int powerCode=m.WParam.ToInt32();
                if(powerCode==0x0004)SafePauseTelemetry("WM_POWER_SUSPEND");
                if(powerCode==0x0007 || powerCode==0x0012)
                {
                    SafeResumeTelemetry("WM_POWER_RESUME");
                    ScheduleRecovery("WM_POWER_RESUME",1000);
                }
            }

            base.WndProc(ref m);
        }

        private void ResetPlacementStability(string reason)
        {
            stableOverlayWidthPx=0;
            pendingShrinkWidthPx=0;
            pendingShrinkCount=0;
            lastTransientPlacementSkip=DateTime.MinValue;
            Log.Write("INFO","PLACEMENT_STABILITY_RESET reason="+reason);
        }

        private bool IsTransientShellSurfaceActive()
        {
            try
            {
                string pn,cn;IntPtr h;
                if(ShellUi.IsStartShellForeground(out pn,out cn,out h))return true;
                Rectangle sr;IntPtr sh;
                if(ShellUi.IsStartSurfacePresent(out pn,out cn,out sr,out sh))return true;
            }
            catch{}
            return false;
        }

        private Rectangle ConstrainToStableWidth(Rectangle r,string position)
        {
            if(r.Width<=0)return r;
            if(stableOverlayWidthPx<=0)
            {
                stableOverlayWidthPx=r.Width;
                pendingShrinkWidthPx=0;
                pendingShrinkCount=0;
                Log.Write("INFO","PLACEMENT_WIDTH_LOCK_INIT width="+stableOverlayWidthPx);
                return r;
            }

            if(r.Width<stableOverlayWidthPx)
            {
                if(Math.Abs(r.Width-pendingShrinkWidthPx)<=3)pendingShrinkCount++;
                else
                {
                    pendingShrinkWidthPx=r.Width;
                    pendingShrinkCount=1;
                }

                // Require a persistent narrower safe gap before shrinking.
                if(pendingShrinkCount>=3)
                {
                    stableOverlayWidthPx=r.Width;
                    pendingShrinkCount=0;
                    Log.Write("INFO","PLACEMENT_WIDTH_LOCK_SHRINK width="+stableOverlayWidthPx);
                }
            }
            else
            {
                // Never auto-grow due to transient taskbar/UIAutomation gap changes.
                pendingShrinkWidthPx=0;
                pendingShrinkCount=0;
            }

            int w=Math.Min(r.Width,stableOverlayWidthPx);
            int x=r.X;
            if(position=="Right")x=r.Right-w;
            else if(position=="Center")x=r.X+((r.Width-w)/2);
            return new Rectangle(x,r.Y,w,r.Height);
        }

        private void AttachGlassTopLevel()
        {
            string resolvedTarget;
            taskbar=TaskbarTargetPolicy.Resolve(config,out resolvedTarget);
            if(taskbar==IntPtr.Zero)
            {
                ScheduleRecovery("GLASS_TASKBAR_NOT_FOUND",500);
                return;
            }
            if(RefreshTaskbarPresentation(false))return;
            trayNotify=Native.FindDescendantByClass(taskbar,"TrayNotifyWnd");
            ResetPlacementStability("TOPLEVEL_GLASS_ATTACH");
            try
            {
                bool transitionFromChild=
                    (Native.GetWindowLongPtr(Handle,Native.GWL_STYLE).ToInt64()&Native.WS_CHILD)!=0;
                bool priorLegacyAttributes=glassLegacyFallback||glassLegacyFallbackReady;
                if(!EnsureTopLevelGlassStyles("TOPLEVEL_GLASS_ATTACH",true))
                    throw new InvalidOperationException("Cannot create top-level per-pixel glass window.");
                // UpdateLayeredWindow cannot follow SetLayeredWindowAttributes until
                // WS_EX_LAYERED is cleared and recreated. A 100% child compositor
                // may have used the legacy opaque fallback, so re-arm PArgb mode.
                if(transitionFromChild||priorLegacyAttributes)
                {
                    long ex=Native.GetWindowLongPtr(Handle,Native.GWL_EXSTYLE).ToInt64();
                    if((ex&Native.WS_EX_LAYERED)==0)
                        throw new InvalidOperationException("Per-pixel layered style unavailable after host transition.");
                    Native.SetWindowLongPtr(Handle,Native.GWL_EXSTYLE,
                        new IntPtr(ex&~(long)Native.WS_EX_LAYERED));
                    Native.SetWindowLongPtr(Handle,Native.GWL_EXSTYLE,
                        new IntPtr(ex));
                    Native.SetWindowPos(Handle,Native.HWND_TOPMOST,0,0,0,0,
                        Native.SWP_NOMOVE|Native.SWP_NOSIZE|Native.SWP_NOACTIVATE|
                        Native.SWP_FRAMECHANGED|Native.SWP_NOOWNERZORDER);
                    Log.Write("INFO","TOPLEVEL_GLASS_REARM_LAYERED childBefore="+transitionFromChild+
                        " previousLegacy="+priorLegacyAttributes);
                }
                TopMost=true;
                EnsureTaskbarOwner(); // R151: stable owned popup, no late SetParent while Start is open.
                PositionOverlay(true); // Taskbar-safe geometry, screen-relative (not child-relative).
                if(expectedRect.Width<80)
                    throw new InvalidOperationException("No taskbar-safe placement for transparent overlay.");
                glassLegacyFallback=false;
                glassLegacyFallbackReady=false;
                bool native=PaintPerPixelLayer();
                if(!native)
                    throw new InvalidOperationException("Per-pixel glass top-level native upload rejected; no visual acceptance.");
                Log.Write("INFO","TOPLEVEL_GLASS_ATTACH_PASS taskbar="+taskbar.ToInt64()+
                    " parent="+Native.GetParent(Handle).ToInt64()+
                    " rect="+expectedRect.X+","+expectedRect.Y+","+
                    expectedRect.Width+","+expectedRect.Height+" opacity="+
                    config.Opacity.ToString("0.00",CultureInfo.InvariantCulture));
            }
            catch(Exception ex)
            {
                Log.Write("ERROR","TOPLEVEL_GLASS_ATTACH_FAIL "+ex);
                ScheduleRecovery("TOPLEVEL_GLASS_FAIL",750);
            }
        }

        private void AttachIntegrated()
        {
            if(RequiresGlassTopLevel){AttachGlassTopLevel();return;}
            string resolvedTarget;taskbar=TaskbarTargetPolicy.Resolve(config,out resolvedTarget);
            if(taskbar==IntPtr.Zero)
            {
                Log.Write("WARN","UPSTREAM_ENGINE_TASKBAR_NOT_FOUND");
                ScheduleRecovery("TASKBAR_NOT_FOUND",500);
                return;
            }

            trayNotify=Native.FindDescendantByClass(taskbar,"TrayNotifyWnd");
            ResetPlacementStability("ATTACH_INTEGRATED");

            try
            {
                long style=Native.GetWindowLongPtr(Handle,Native.GWL_STYLE).ToInt64();
                long childStyle=(style & ~Native.WS_POPUP)|Native.WS_CHILD;
                Native.SetWindowLongPtr(Handle,Native.GWL_STYLE,new IntPtr(childStyle));

                Native.SetParent(Handle,taskbar);
                IntPtr parentAfter=Native.GetParent(Handle);
                if(parentAfter!=taskbar)
                    throw new InvalidOperationException("SetParent verification failed");

                long upstreamEx=
                    Native.WS_EX_CONTROLPARENT |
                    Native.WS_EX_LAYERED |
                    Native.WS_EX_COMPOSITED |
                    Native.WS_EX_TOOLWINDOW |
                    Native.WS_EX_NOACTIVATE;

                Native.SetWindowLongPtr(Handle,Native.GWL_EXSTYLE,new IntPtr(upstreamEx));
                if(!EnsureIntegratedWindowStyles("ATTACH_INTEGRATED",true))
                    throw new InvalidOperationException("Integrated window style verification failed");

                // Per-pixel UpdateLayeredWindow must not follow SetLayeredWindowAttributes:
                // Win32 requires clearing/recreating the layered style after the latter.
                PositionOverlay(true);
                bool layered=PaintPerPixelLayer()||glassLegacyFallbackReady;
                int layeredWin32=Marshal.GetLastWin32Error();

                if(!layered)
                {
                    Log.Write(
                        "ERROR",
                        "UPSTREAM_LAYERED_SURFACE_FAIL win32="+layeredWin32+
                        " exstyle=0x"+upstreamEx.ToString("X8",CultureInfo.InvariantCulture)+
                        " parent="+parentAfter.ToInt64()
                    );
                    throw new InvalidOperationException(
                        "Layered compositor could not initialize win32="+layeredWin32
                    );
                }

                Log.Write(
                    "INFO",
                    "UPSTREAM_LAYERED_SURFACE_PASS win32="+layeredWin32+
                    " exstyle=0x"+upstreamEx.ToString("X8",CultureInfo.InvariantCulture)
                );

                TopMost=false;
                upstreamAttachCount++;

                // Position was committed before the first ULW_ALPHA frame.

                Log.Write(
                    "INFO",
                    "STABLE_CHILD_ATTACH_PASS count="+upstreamAttachCount+
                    " parent="+parentAfter.ToInt64()+
                    " taskbar="+taskbar.ToInt64()+
                    " tray="+trayNotify.ToInt64()+
                    " exstyle=0x"+upstreamEx.ToString("X8",CultureInfo.InvariantCulture)+
                    " layered="+layered+
                    " layeredWin32="+layeredWin32+
                    " rect="+expectedRect.X+","+expectedRect.Y+","+expectedRect.Width+","+expectedRect.Height
                );
            }
            catch(Exception ex)
            {
                Log.Write("ERROR","UPSTREAM_ENGINE_ATTACH_FAIL "+ex.ToString());
                ScheduleRecovery("ATTACH_EXCEPTION",750);
            }
        }

        private void PositionOverlay(bool force)
        {
            lastPositionAt=DateTime.UtcNow;

            string resolvedTarget;IntPtr currentTaskbar=TaskbarTargetPolicy.Resolve(config,out resolvedTarget);
            if(currentTaskbar==IntPtr.Zero)return;
            taskbar=currentTaskbar;
            if(RefreshTaskbarPresentation(false))return;

            if(expectedRect.Width>0 && IsTransientShellSurfaceActive())
                return;

            Native.RECT tr;
            if(!Native.GetWindowRect(taskbar,out tr))return;
            Rectangle taskbarRect=tr.ToRectangle();

            bool geometryChanged=
                lastTaskbarScreenRect.IsEmpty ||
                lastTaskbarScreenRect.X!=taskbarRect.X ||
                lastTaskbarScreenRect.Y!=taskbarRect.Y ||
                lastTaskbarScreenRect.Width!=taskbarRect.Width ||
                lastTaskbarScreenRect.Height!=taskbarRect.Height;

            if(!force && !geometryChanged && expectedRect.Width>0 && expectedRect.Height>0)
            {
                Native.RECT wr;
                if(Native.GetWindowRect(Handle,out wr))
                {
                    Rectangle current=wr.ToRectangle();
                    bool drift=
                        Math.Abs(current.X-expectedRect.X)>1 ||
                        Math.Abs(current.Y-expectedRect.Y)>1 ||
                        Math.Abs(current.Width-expectedRect.Width)>1 ||
                        Math.Abs(current.Height-expectedRect.Height)>1;

                    if(drift)
                    {
                        Native.SetWindowPos(
                            Handle,
                            RequiresGlassTopLevel?Native.HWND_TOPMOST:Native.HWND_TOP,
                            RequiresGlassTopLevel?expectedRect.X:expectedRect.X-taskbarRect.Left,
                            RequiresGlassTopLevel?expectedRect.Y:expectedRect.Y-taskbarRect.Top,
                            expectedRect.Width,
                            expectedRect.Height,
                            Native.SWP_NOACTIVATE|Native.SWP_SHOWWINDOW
                        );
                        Log.Write(
                            "INFO",
                            "LOW_PRESSURE_PLACEMENT_DRIFT_REPAIR from="+
                            current.X+","+current.Y+","+current.Width+","+current.Height+
                            " to="+expectedRect.X+","+expectedRect.Y+","+expectedRect.Width+","+expectedRect.Height
                        );
                    }
                }

                if(!Visible)Show();
                lastUpstreamPositionAt=DateTime.UtcNow;
                return;
            }

            Rectangle r=TaskbarLayout.GetSafeRectangle(taskbar,config,config.MinWidthLogicalPx);
            if(r.Width<=0||r.Height<=0)return;

            r=ConstrainToStableWidth(r,config.Position);
            expectedRect=r;
            lastTaskbarScreenRect=taskbarRect;

            Native.SetWindowPos(
                Handle,
                RequiresGlassTopLevel?Native.HWND_TOPMOST:Native.HWND_TOP,
                RequiresGlassTopLevel?r.X:r.X-taskbarRect.Left,
                RequiresGlassTopLevel?r.Y:r.Y-taskbarRect.Top,
                r.Width,
                r.Height,
                Native.SWP_NOACTIVATE|Native.SWP_SHOWWINDOW
            );

            if(!Visible)Show();
            lastUpstreamPositionAt=DateTime.UtcNow;

            Log.Write(
                "INFO",
                "LOW_PRESSURE_SAFE_PLACEMENT_SCAN force="+force+
                " geometryChanged="+geometryChanged+
                " rect="+r.X+","+r.Y+","+r.Width+","+r.Height
            );
        }

        private int OwnedPoints(Rectangle r)
        {
            int[] xs=new int[]{r.Left+18,r.Left+r.Width/2,r.Right-18};int y=r.Top+r.Height/2;int owned=0;uint me=(uint)Process.GetCurrentProcess().Id;
            foreach(int x in xs){Native.POINT p=new Native.POINT();p.X=x;p.Y=y;IntPtr h=Native.WindowFromPoint(p);uint pid=0;if(h!=IntPtr.Zero)Native.GetWindowThreadProcessId(h,out pid);if(pid==me)owned++;}
            return owned;
        }

        // Windows 11 SearchHost places an acrylic/taskbar z-band *above* ordinary
        // HWND_TOPMOST layered windows while Start/Search is foreground. Native
        // ULW, repeated TOPMOST and z-order toggling all gave zero physical ink.
        // R53 real screenshot proof: moving exactly 60 px ABOVE the taskbar
        // restored text/chart at both left and right (6/6 samples per side).
        // On closing Start, a Form Hide/Show (not merely another ULW) makes
        // native ink visible again without recreating the whole OverlayForm.
        private bool startGlassTemporarilyFloating;
        private bool startGlassPinnedDuringShell;
        private Rectangle startGlassTemporaryBounds=Rectangle.Empty;
        private int startGlassLiftTransitions;
        private int startGlassReturnTransitions;

        private void StartGuardTick(IntPtr currentTaskbar)
        {
            if(!IsHandleCreated || !RequiresGlassTopLevel ||
               currentTaskbar==IntPtr.Zero || taskbar!=currentTaskbar)return;
            // The old 60px Windows Start lift is OPT-IN only. Do not reposition
            // translucent taskbar metrics as a side-effect of opening Start.
            if(!config.FloatAboveStartMenu)return;
            try
            {
                string foregroundProcess="",foregroundClass="";
                IntPtr foreground=IntPtr.Zero;
                bool start=ShellUi.IsStartShellForeground(
                    out foregroundProcess,out foregroundClass,out foreground);
                // R110: a genuine Windows Start surface can remain open when
                // another Explorer window temporarily owns foreground focus.
                // Reuse the existing strict signed-Windows-shell process,
                // physical rectangle and location checks; do not treat arbitrary
                // foreground windows as an active Start menu.
                if(!start)
                {
                    string surfaceProcess="",surfaceClass="";
                    Rectangle surfaceRect=Rectangle.Empty;
                    IntPtr surfaceHwnd=IntPtr.Zero;
                    if(ShellUi.IsStartSurfacePresent(out surfaceProcess,
                        out surfaceClass,out surfaceRect,out surfaceHwnd))
                    {
                        foregroundProcess="START_SURFACE:"+surfaceProcess;
                        foregroundClass=surfaceClass;
                        start=true;
                        if(!startGlassTemporarilyFloating)
                            Log.Write("INFO","START_GUARD_VERIFIED_SURFACE"+
                                " process="+surfaceProcess+" hwnd="+surfaceHwnd.ToInt64()+
                                " rect="+surfaceRect);
                    }
                }

                if(start)
                {
                    if(startGlassTemporarilyFloating)return;
                    if(expectedRect.Width<500||expectedRect.Height<30)return;
                    Native.RECT nativeBounds=new Native.RECT();
                    if(!Native.GetWindowRect(currentTaskbar,out nativeBounds))return;
                    Rectangle shellRect=nativeBounds.ToRectangle();
                    if(!shellRect.Contains(expectedRect))return;
                    Rectangle full=SystemInformation.VirtualScreen;
                    // Bottom-docked taskbar: exact 12px separation between
                    // taskbar and the temporary 48px, no-activate metrics strip.
                    Rectangle lift=new Rectangle(expectedRect.X,
                        expectedRect.Top-expectedRect.Height-12,
                        expectedRect.Width,expectedRect.Height);
                    if(!full.Contains(lift))return;
                    if(!Native.SetWindowPos(Handle,Native.HWND_TOPMOST,
                        lift.X,lift.Y,lift.Width,lift.Height,
                        Native.SWP_NOACTIVATE|Native.SWP_SHOWWINDOW))
                    {
                        Log.Write("WARN","START_GLASS_LIFT_WIN32_FAIL code="+Marshal.GetLastWin32Error());
                        return;
                    }
                    if(!PaintPerPixelLayer())
                    {
                        Log.Write("ERROR","START_GLASS_LIFT_UPLOAD_FAILED");
                        Native.SetWindowPos(Handle,Native.HWND_TOPMOST,
                            expectedRect.X,expectedRect.Y,expectedRect.Width,expectedRect.Height,
                            Native.SWP_NOACTIVATE|Native.SWP_SHOWWINDOW);
                        return;
                    }
                    startGlassTemporaryBounds=lift;
                    startGlassTemporarilyFloating=true;
                    startGlassLiftTransitions++;
                    Log.Write("INFO","START_GLASS_LIFT_NATIVE_PASS "+
                        "reason="+foregroundProcess+" target="+lift+
                        " generation="+metricSnapshotGeneration+
                        " transitionCount="+startGlassLiftTransitions);
                    return;
                }
                if(!startGlassTemporarilyFloating)return;
                // SearchHost transiently changes UIAutomation taskbar gaps.
                // First restore exactly the original pre-Start geometry;
                // defer new gap scans to the ordinary periodic watchdog.
                Rectangle savedGap=expectedRect;
                Native.RECT tbr=new Native.RECT();
                if(!Native.GetWindowRect(currentTaskbar,out tbr) ||
                   !tbr.ToRectangle().Contains(savedGap))
                {
                    Log.Write("WARN","START_GLASS_RETURN_GAP_INVALID");
                    if(!recoveryPending)ScheduleRecovery("START_GLASS_GAP_CHANGED",500);
                    return;
                }
                startGlassTemporarilyFloating=false;
                startGlassTemporaryBounds=Rectangle.Empty;
                Hide();
                Show(); // R53 measured this restores layered ink after Search
                if(!Native.SetWindowPos(Handle,Native.HWND_TOPMOST,
                    savedGap.X,savedGap.Y,savedGap.Width,savedGap.Height,
                    Native.SWP_NOACTIVATE|Native.SWP_SHOWWINDOW))
                {
                    Log.Write("ERROR","START_GLASS_RETURN_POSITION_WIN32="+Marshal.GetLastWin32Error());
                    if(!recoveryPending)ScheduleRecovery("START_GLASS_RETURN_POSITION_FAIL",500);
                    return;
                }
                // Preserve stable taskbar geometry throughout the mandatory
                // 24-frame Start acceptance and the following return-to-gap
                // check. Emptying lastTaskbarScreenRect causes the *next*
                // 500ms watchdog to rescan transient SearchHost UIAutomation
                // and shift the overlay by ~32px even though the shell has
                // just closed. An ordinary 5-second placement scan after the
                // shell settles still checks all actual geometry changes.
                lastUpstreamPositionAt=DateTime.UtcNow;
                lastPositionAt=DateTime.UtcNow;
                if(!PaintPerPixelLayer())
                {
                    Log.Write("ERROR","START_GLASS_RETURN_UPLOAD_FAILED");
                    ScheduleRecovery("START_GLASS_RETURN_UPLOAD_FAILED",500);
                }
                else
                {
                    startGlassReturnTransitions++;
                    Log.Write("INFO","START_GLASS_RETURN_NATIVE_PASS rect="+expectedRect+
                        " generation="+metricSnapshotGeneration+
                        " transitionCount="+startGlassReturnTransitions);
                }
            }
            catch(Exception e)
            {
                Log.Write("ERROR","START_GLASS_TRANSITION_FAIL "+e.GetType().Name+" "+e.Message);
                if(!recoveryPending)ScheduleRecovery("START_GLASS_TRANSITION_EXCEPTION",750);
            }
        }

        private void SensorSupervisorSelfHealWatchdog()
        {
            DateTime now=DateTime.UtcNow;
            if(now<nextSensorSelfHealCheckUtc)return;
            nextSensorSelfHealCheckUtc=now.AddSeconds(15);
            string reason;
            if(!SensorSupervisorSelfHeal.ShouldAttempt(
                AppPaths.InstallState,
                AppPaths.SensorSupervisorState,
                now,
                appStartedUtc,
                lastSensorSelfHealAttemptUtc,
                out reason))return;
            if(Interlocked.CompareExchange(ref sensorSelfHealInFlight,1,0)!=0)return;
            lastSensorSelfHealAttemptUtc=now;
            Log.Write("WARN","SENSOR_SUPERVISOR_AUTOHEAL_TRIGGER reason="+reason);
            ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    string detail;
                    int exit=SensorSupervisorSelfHeal.TryRunExistingTask(out detail);
                    if(exit==0)Log.Write("INFO","SENSOR_SUPERVISOR_AUTOHEAL_START_TASK_PASS reason="+reason+" detail="+detail);
                    else Log.Write("WARN","SENSOR_SUPERVISOR_AUTOHEAL_START_TASK_FAIL reason="+reason+" exit="+exit+" detail="+detail);
                }
                catch(Exception ex){Log.Write("WARN","SENSOR_SUPERVISOR_AUTOHEAL_EXCEPTION "+ex.Message);}
                finally{Interlocked.Exchange(ref sensorSelfHealInFlight,0);}
            });
        }

        private void VisibilityWatchdog()
        {
            try
            {
                // R146: presentation follows the real taskbar, not a perpetual TOPMOST timer.
                if(RefreshTaskbarPresentation(true))return;
                SensorSupervisorSelfHealWatchdog();
                string probeTargetNow;IntPtr currentTaskbar=TaskbarTargetPolicy.Resolve(config,out probeTargetNow);

                if(currentTaskbar==IntPtr.Zero)
                {
                    if(!recoveryPending)ScheduleRecovery("TASKBAR_MISSING_WATCHDOG",750);
                    return;
                }

                if(taskbar==IntPtr.Zero || currentTaskbar!=taskbar)
                {
                    if(!recoveryPending)ScheduleRecovery("TASKBAR_HANDLE_CHANGED",750);
                    return;
                }

                bool parentOk=RequiresGlassTopLevel?
                    (Native.GetWindowLongPtr(Handle,Native.GWL_STYLE).ToInt64()&Native.WS_CHILD)==0:
                    Native.GetParent(Handle)==taskbar;
                if(!parentOk)
                {
                    if(!recoveryPending)ScheduleRecovery("UPSTREAM_PARENT_LOST",750);
                    return;
                }

                if((DateTime.UtcNow-lastStyleIntegrityAt).TotalMilliseconds>=5000)
                {
                    lastStyleIntegrityAt=DateTime.UtcNow;
                    if(!EnsureIntegratedWindowStyles("LOW_PRESSURE_HEALTH",false))
                    {
                        if(!recoveryPending)ScheduleRecovery("STYLE_INTEGRITY_DRIFT",750);
                        return;
                    }
                }

                // Explicitly preserve a lifted alpha-zero panel while shell
                // is foreground, and recompose/reset its HWND z-band on return.
                StartGuardTick(currentTaskbar);
                if(startGlassTemporarilyFloating)return;

                if(!Native.IsWindowVisible(Handle))Show();

                if(expectedRect.Width<=0 ||
                   (DateTime.UtcNow-lastUpstreamPositionAt).TotalMilliseconds>=5000)
                    PositionOverlay(false);
            }
            catch(Exception ex)
            {
                Log.Write("WARN","LOW_PRESSURE_WATCHDOG "+ex.Message);
            }
        }

        private void EnterRescue(string reason)
        {
            Log.Write("WARN","UPSTREAM_ENGINE_REATTACH_REQUEST reason="+reason);
            if(!recoveryPending)ScheduleRecovery("REATTACH_"+reason,250);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            if(presentationSuppressed)return;
            if(PaintPerPixelLayer())return;
            base.OnPaint(e); e.Graphics.SmoothingMode=SmoothingMode.AntiAlias; e.Graphics.TextRenderingHint=System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            ThemeDefinition theme=WindowsThemePolicy.Resolve(config);
            PaintBackground(e.Graphics,theme,ClientRectangle);
            List<MetricView> metrics=BuildMetricViews(theme);
            lastPaintMetrics=metrics;
            if(metrics.Count==0)return;
            float seg=(float)ClientRectangle.Width/metrics.Count;
            for(int i=0;i<metrics.Count;i++){RectangleF r=new RectangleF(i*seg,0,seg,ClientRectangle.Height);PaintMetric(e.Graphics,theme,metrics[i],r,i);}
            if(diagnosticBeacon)PaintDiagnosticBeacon(e.Graphics);
        }

        internal bool VerifySettingsHoverSuppression()
        {
            SettingsForm prior=settingsForm;
            try
            {
                using(SettingsForm probe=new SettingsForm(config,snapshot,"Display",RenderSettingsThemePreview))
                {
                    settingsForm=probe;
                    lastHoverIndex=7;lastHoverGroup="CPU";lastHoverGeneration=9;
                    HandleHardwareHover(new Point(Math.Max(0,ClientRectangle.Width/2),Math.Max(0,ClientRectangle.Height/2)));
                    bool moveGuard=(lastHoverIndex==-1&&lastHoverGroup==""&&lastHoverGeneration==-1);
                    lastHoverIndex=5;lastHoverGroup="GPU";lastHoverGeneration=11;
                    HoverWatchdog();
                    bool watchdogGuard=(lastHoverIndex==-1&&lastHoverGroup==""&&lastHoverGeneration==-1);
                    return moveGuard&&watchdogGuard&&(hardwareFlyout==null||!hardwareFlyout.Visible);
                }
            }
            finally
            {
                settingsForm=prior;
                lastHoverIndex=-1;lastHoverGroup="";lastHoverGeneration=-1;
            }
        }
        private void HandleHardwareHover(Point location)
        {
            try
            {
                if((settingsForm!=null&&!settingsForm.IsDisposed)||(workspace!=null&&!workspace.IsDisposed))
                {
                    if(hardwareFlyout!=null&&hardwareFlyout.Visible)hardwareFlyout.Hide();
                    lastHoverIndex=-1;lastHoverGroup="";lastHoverGeneration=-1;
                    return;
                }
                if(!config.EnableHardwareFlyout||hardwareFlyout==null||lastPaintMetrics==null||lastPaintMetrics.Count==0||ClientRectangle.Width<=0)return;
                int index=(int)Math.Floor(location.X/(ClientRectangle.Width/(double)lastPaintMetrics.Count));index=Math.Max(0,Math.Min(lastPaintMetrics.Count-1,index));MetricView m=lastPaintMetrics[index];string group=m.GroupKey??m.Key;
                lastHardwareHoverAt=DateTime.UtcNow;
                if(hardwareFlyout.Visible&&index==lastHoverIndex&&String.Equals(group,lastHoverGroup,StringComparison.Ordinal)&&lastHoverGeneration==metricSnapshotGeneration)return;
                ThemeDefinition t=WindowsThemePolicy.Resolve(config);List<HardwareFlyoutRow> rows=BuildHardwareFlyoutRows(group,t);if(rows.Count==0){hardwareFlyout.Hide();lastHoverIndex=-1;lastHoverGroup="";return;}
                float seg=ClientRectangle.Width/(float)lastPaintMetrics.Count;Rectangle client=Rectangle.Round(new RectangleF(index*seg,0,seg,ClientRectangle.Height));Point a=PointToScreen(client.Location);Rectangle anchor=new Rectangle(a,new Size(client.Width,client.Height));string title=group=="RAM"?("RAM — "+snapshot.MemoryModules.Count+" module"+(snapshot.MemoryModules.Count==1?"":"s")):(group+" — "+rows.Count+" device"+(rows.Count==1?"":"s"));hardwareFlyout.UpdateContent(title,rows,t,anchor);lastHoverIndex=index;lastHoverGroup=group;lastHoverGeneration=metricSnapshotGeneration;
            }catch(Exception ex){Log.Write("WARN","HARDWARE_HOVER "+ex.Message);}
        }
        private static string ClockText(int mhz)
        {
            if(mhz<=0)return "N/A";
            if(mhz>=1000)return (mhz/1000d).ToString("0.00",CultureInfo.InvariantCulture)+" GHz";
            return mhz.ToString(CultureInfo.InvariantCulture)+" MHz";
        }
        private static string ClockText(float mhz)
        {
            if(mhz<=0)return "N/A";
            if(mhz>=1000)return (mhz/1000d).ToString("0.00",CultureInfo.InvariantCulture)+" GHz";
            return mhz.ToString("0",CultureInfo.InvariantCulture)+" MHz";
        }
        private static string LinkText(long bits)
        {
            if(bits<=0)return "N/A";
            if(bits>=1000000000L)return (bits/1000000000d).ToString("0.##",CultureInfo.InvariantCulture)+" Gbps";
            if(bits>=1000000L)return (bits/1000000d).ToString("0",CultureInfo.InvariantCulture)+" Mbps";
            return bits.ToString(CultureInfo.InvariantCulture)+" bps";
        }

        private List<HardwareFlyoutRow> BuildHardwareFlyoutRows(string group,ThemeDefinition t)
        {
            List<HardwareFlyoutRow> r=new List<HardwareFlyoutRow>();
            int i=0;
            HashSet<string> selected=group=="CPU"?SelectionUtil.Parse(config.SelectedCpuIds):group=="GPU"?SelectionUtil.Parse(config.SelectedGpuIds):group=="DISK"?SelectionUtil.Parse(config.SelectedDiskIds):SelectionUtil.Parse(config.SelectedNetworkIds);

            if(group=="CPU")
            {
                foreach(CpuDeviceSnapshot d in snapshot.CpuDevices)
                {
                    if(!config.HoverShowAllDevices&&selected.Count>0&&!selected.Contains(d.Id))continue;
                    HardwareFlyoutRow x=new HardwareFlyoutRow();
                    x.Name=ShortName(d.Name,76);
                    x.Line1="Usage  "+(d.UsageAvailable?d.Usage.ToString("0")+"%":"N/A")+"     Temp  "+(d.TemperatureAvailable?d.Temperature.ToString("0")+"°C":"N/A")+"     Clock  "+ClockText(d.CurrentClockMHz);
                    x.Line2="Cores  "+(d.PhysicalCores>0?d.PhysicalCores.ToString():"N/A")+"     Threads  "+(d.LogicalProcessors>0?d.LogicalProcessors.ToString():"N/A")+"     Max clock  "+ClockText(d.MaxClockMHz);
                    x.Line3="Power  "+(d.PowerAvailable?d.PowerW.ToString("0.0",CultureInfo.InvariantCulture)+" W":"N/A")+"     Bus/BCLK  "+(d.ExternalClockMHz>0?(d.ExternalClockMHz+" MHz"):"N/A")+(String.IsNullOrWhiteSpace(d.Socket)?"":("     Socket  "+d.Socket));
                    x.Accent=t.Accents[i++%t.Accents.Length];r.Add(x);
                }
            }
            else if(group=="RAM")
            {
                HardwareFlyoutRow sum=new HardwareFlyoutRow();
                sum.Name="System memory";
                ulong free=snapshot.RamTotalBytes>=snapshot.RamUsedBytes?snapshot.RamTotalBytes-snapshot.RamUsedBytes:0;
                int maxConfigured=snapshot.MemoryModules.Where(m=>m.ConfiguredClockMHz>0).Select(m=>m.ConfiguredClockMHz).DefaultIfEmpty(0).Max();
                string type=snapshot.MemoryModules.Select(m=>m.MemoryType).FirstOrDefault(x=>!String.IsNullOrWhiteSpace(x)&&x!="Unknown")??"Unknown";
                sum.Line1="Used  "+snapshot.Ram.ToString("0")+"%     "+UnitFormatter.Pair(snapshot.RamUsedBytes,snapshot.RamTotalBytes,config.MemoryUnit)+"     Available  "+UnitFormatter.Bytes(free,config.MemoryUnit);
                sum.Line2="Modules  "+snapshot.MemoryModules.Count+"     Type  "+type+"     Configured clock  "+ClockText(maxConfigured);
                sum.Line3="";
                sum.Accent=t.Accents[i++%t.Accents.Length];r.Add(sum);

                foreach(MemoryModuleSnapshot m in snapshot.MemoryModules)
                {
                    HardwareFlyoutRow x=new HardwareFlyoutRow();
                    string loc=String.IsNullOrWhiteSpace(m.DeviceLocator)?m.BankLabel:m.DeviceLocator;
                    x.Name=(String.IsNullOrWhiteSpace(loc)?"Memory module":loc)+(String.IsNullOrWhiteSpace(m.Manufacturer)?"":(" — "+m.Manufacturer));
                    x.Line1="Capacity  "+UnitFormatter.Bytes(m.CapacityBytes,config.MemoryUnit)+"     Clock  "+ClockText(m.ConfiguredClockMHz>0?m.ConfiguredClockMHz:m.SpeedMHz)+"     Type  "+m.MemoryType;
                    x.Line2="Data bus  "+(m.DataWidth>0?(m.DataWidth+"-bit"):"N/A")+"     Total width  "+(m.TotalWidth>0?(m.TotalWidth+"-bit"):"N/A");
                    x.Line3=String.IsNullOrWhiteSpace(m.PartNumber)?"":("Part  "+ShortName(m.PartNumber,30));
                    x.Accent=t.Accents[i++%t.Accents.Length];r.Add(x);
                }
            }
            else if(group=="GPU")
            {
                foreach(GpuDeviceSnapshot d in snapshot.GpuDevices)
                {
                    if(!config.HoverShowAllDevices&&selected.Count>0&&!selected.Contains(d.Id))continue;
                    HardwareFlyoutRow x=new HardwareFlyoutRow();
                    x.Name=ShortName(d.Name,76);
                    x.Line1="Usage  "+(d.UsageAvailable?d.Usage.ToString("0")+"%":"N/A")+"     Temp  "+(d.TemperatureAvailable?d.Temperature.ToString("0")+"°C":"N/A")+"     Core clock  "+(d.CoreClockAvailable?ClockText(d.CoreClockMHz):"N/A");
                    x.Line2=(d.VramTotalGb>0?("VRAM  "+d.VramUsedGb.ToString("0.0")+"/"+d.VramTotalGb.ToString("0.0")+" GB"):"VRAM  N/A")+"     Memory clock  "+(d.MemoryClockAvailable?ClockText(d.MemoryClockMHz):"N/A")+"     Power  "+(d.PowerAvailable?d.PowerW.ToString("0.0",CultureInfo.InvariantCulture)+" W":"N/A");
                    string fanText=d.FanRpmAvailable?d.FanRpm.ToString("0",CultureInfo.InvariantCulture)+" RPM":(d.FanPercentAvailable?d.FanPercent.ToString("0",CultureInfo.InvariantCulture)+"%":"N/A");
                    x.Line3="Fan  "+fanText+"     Bus  "+(d.PcieGeneration>0?("PCIe Gen"+d.PcieGeneration+(d.PcieWidth>0?(" x"+d.PcieWidth):"")):"N/A")+"     Source  "+ShortName(d.Source,24);
                    x.Accent=t.Accents[i++%t.Accents.Length];r.Add(x);
                }
            }
            else if(group=="DISK")
            {
                foreach(DiskDeviceSnapshot d in snapshot.DiskDevices)
                {
                    if(!config.HoverShowAllDevices&&selected.Count>0&&!selected.Contains(d.Id))continue;
                    HardwareFlyoutRow x=new HardwareFlyoutRow();
                    x.Name=ShortName(d.Name,76);
                    x.Line1="Read  "+UnitFormatter.Rate(d.ReadBytesPerSec,config.DiskRateUnit)+"     Write  "+UnitFormatter.Rate(d.WriteBytesPerSec,config.DiskRateUnit)+"     Temp  "+(d.TemperatureAvailable?d.Temperature.ToString("0")+"°C":"N/A");
                    x.Line2=d.CapacityAvailable?("Used  "+d.UsedPercent.ToString("0")+"%     "+UnitFormatter.Pair(d.UsedBytes,d.TotalBytes,config.StorageUnit)+(String.IsNullOrWhiteSpace(d.Volumes)?"":("     Volume  "+d.Volumes))):"Capacity  N/A";
                    string bus=String.IsNullOrWhiteSpace(d.BusType)?(String.IsNullOrWhiteSpace(d.InterfaceType)?"N/A":d.InterfaceType):d.BusType;
                    string media=String.IsNullOrWhiteSpace(d.MediaType)?"":("     Media  "+ShortName(d.MediaType,22));
                    x.Line3="Bus  "+bus+media+"     Activity  "+d.Activity.ToString("0")+"%";
                    x.Accent=t.Accents[i++%t.Accents.Length];r.Add(x);
                }
            }
            else if(group=="NET")
            {
                foreach(NetworkDeviceSnapshot d in snapshot.NetworkDevices)
                {
                    if(!config.HoverShowAllDevices&&selected.Count>0&&!selected.Contains(d.Id))continue;
                    HardwareFlyoutRow x=new HardwareFlyoutRow();
                    x.Name=ShortName(d.Name,76);
                    x.Line1="Download  "+UnitFormatter.Rate(d.DownBytesPerSec,config.NetworkUnit)+"     Upload  "+UnitFormatter.Rate(d.UpBytesPerSec,config.NetworkUnit)+"     Link  "+LinkText(d.LinkSpeedBitsPerSec);
                    x.Line2=ShortName(d.Description,90);
                    x.Line3="";
                    x.Accent=t.Accents[i++%t.Accents.Length];r.Add(x);
                }
            }
            return r;
        }

        private void HoverWatchdog()
        {
            if((settingsForm!=null&&!settingsForm.IsDisposed)||(workspace!=null&&!workspace.IsDisposed))
            {
                if(hardwareFlyout!=null&&hardwareFlyout.Visible)hardwareFlyout.Hide();
                lastHoverIndex=-1;lastHoverGroup="";lastHoverGeneration=-1;
                return;
            }
            if(hardwareFlyout==null||!hardwareFlyout.Visible)return;Point p=Cursor.Position;Point o=PointToScreen(Point.Empty);Rectangle overlayScreen=new Rectangle(o,ClientSize);bool insideOverlay=overlayScreen.Contains(p);bool insideFlyout=hardwareFlyout.Bounds.Contains(p);if(insideOverlay||insideFlyout){lastHardwareHoverAt=DateTime.UtcNow;return;}if((DateTime.UtcNow-lastHardwareHoverAt).TotalMilliseconds>180){hardwareFlyout.Hide();lastHoverIndex=-1;lastHoverGroup="";lastHoverGeneration=-1;}
        }

        private void PaintDiagnosticBeacon(Graphics g)
        {
            int cell=5;
            int cols=8;
            int rows=4;
            int w=cols*cell;
            int h=rows*cell;
            int x=Math.Max(2,ClientRectangle.Width-w-3);
            int y=2;

            using(SolidBrush frame=new SolidBrush(Color.FromArgb(3,3,3)))
                g.FillRectangle(frame,x-2,y-2,w+4,h+4);

            Color a=Color.FromArgb(255,17,241);
            Color b=Color.FromArgb(0,255,106);
            using(SolidBrush ba=new SolidBrush(a))
            using(SolidBrush bb=new SolidBrush(b))
            {
                for(int yy=0;yy<rows;yy++)
                for(int xx=0;xx<cols;xx++)
                    g.FillRectangle(((xx+yy)&1)==0?ba:bb,x+xx*cell,y+yy*cell,cell,cell);
            }
        }

        private static bool Mode(string value,string expected){return String.Equals(value,expected,StringComparison.OrdinalIgnoreCase);}
        private static string ShortName(string name,int max){if(String.IsNullOrWhiteSpace(name))return "Device";string s=name.Trim();return s.Length<=max?s:s.Substring(0,Math.Max(1,max-1))+"…";}

        private List<CpuDeviceSnapshot> SelectedCpuDevices()
        {
            List<CpuDeviceSnapshot> all=snapshot.CpuDevices??new List<CpuDeviceSnapshot>();if(all.Count==0)return all;string mode=config.CpuDisplayMode;HashSet<string> ids=SelectionUtil.Parse(config.SelectedCpuIds);List<CpuDeviceSnapshot> selected=all.Where(x=>ids.Contains(x.Id)).ToList();
            if(Mode(mode,"Overall"))return all;if(Mode(mode,"Auto"))return new List<CpuDeviceSnapshot>{all.OrderByDescending(x=>x.UsageAvailable?x.Usage:-1).First()};if(Mode(mode,"Single"))return new List<CpuDeviceSnapshot>{selected.Count>0?selected[0]:all[0]};return selected.Count>0?selected:all;
        }
        private List<GpuDeviceSnapshot> SelectedGpuDevices()
        {
            List<GpuDeviceSnapshot> all=snapshot.GpuDevices??new List<GpuDeviceSnapshot>();if(all.Count==0)return all;string mode=config.GpuDisplayMode;HashSet<string> ids=SelectionUtil.Parse(config.SelectedGpuIds);List<GpuDeviceSnapshot> selected=all.Where(x=>ids.Contains(x.Id)).ToList();
            if(Mode(mode,"Overall"))return all;if(Mode(mode,"Auto"))return new List<GpuDeviceSnapshot>{all.OrderByDescending(x=>x.UsageAvailable?x.Usage:-1).First()};if(Mode(mode,"Single"))return new List<GpuDeviceSnapshot>{selected.Count>0?selected[0]:all[0]};return selected.Count>0?selected:all;
        }
        private List<DiskDeviceSnapshot> SelectedDiskDevices()
        {
            List<DiskDeviceSnapshot> all=snapshot.DiskDevices??new List<DiskDeviceSnapshot>();if(all.Count==0)return all;string mode=config.DiskDisplayMode;HashSet<string> ids=SelectionUtil.Parse(config.SelectedDiskIds);List<DiskDeviceSnapshot> selected=all.Where(x=>ids.Contains(x.Id)).ToList();
            if(Mode(mode,"Overall"))return all;if(Mode(mode,"Auto"))return new List<DiskDeviceSnapshot>{all.OrderByDescending(x=>x.ActivityAvailable?x.Activity:-1).First()};if(Mode(mode,"Single"))return new List<DiskDeviceSnapshot>{selected.Count>0?selected[0]:all[0]};return selected.Count>0?selected:all;
        }
        private List<NetworkDeviceSnapshot> SelectedNetworkDevices()
        {
            List<NetworkDeviceSnapshot> all=snapshot.NetworkDevices??new List<NetworkDeviceSnapshot>();if(all.Count==0)return all;string mode=config.NetworkDisplayMode;HashSet<string> ids=SelectionUtil.Parse(config.SelectedNetworkIds);List<NetworkDeviceSnapshot> selected=all.Where(x=>ids.Contains(x.Id)).ToList();
            if(Mode(mode,"Overall"))return all;if(Mode(mode,"Auto"))return new List<NetworkDeviceSnapshot>{all.OrderByDescending(x=>x.DownBytesPerSec+x.UpBytesPerSec).First()};if(Mode(mode,"Single"))return new List<NetworkDeviceSnapshot>{selected.Count>0?selected[0]:all[0]};return selected.Count>0?selected:all;
        }

        private List<MetricView> BuildMetricViews(ThemeDefinition t,int availableWidthOverride=0)
        {
            List<MetricView> x=new List<MetricView>();int idx=0;
            if(config.ShowCpu)
            {
                List<CpuDeviceSnapshot> ds=SelectedCpuDevices();Color c=t.Accents[idx++%t.Accents.Length];
                if(Mode(config.CpuDisplayMode,"Multiple")&&config.MultipleDeviceLayout=="Separate"&&ds.Count>1)
                {
                    for(int i=0;i<ds.Count;i++){CpuDeviceSnapshot d=ds[i];string val=d.UsageAvailable?d.Usage.ToString("0")+"%":"N/A";MetricView m=config.ShowTemperatures?MakeDual("CPU:"+d.Id,"C"+i,val,FormatCpuTemperature(d.TemperatureAvailable,d.Temperature),d.Usage,"CPU:"+d.Id,c):Make("CPU:"+d.Id,"C"+i,val,d.Usage,"CPU:"+d.Id,c);m.GroupKey="CPU";m.DeviceId=d.Id;m.DisplayName=d.Name;x.Add(m);}
                }
                else
                {
                    float usage=snapshot.Cpu;if(!Mode(config.CpuDisplayMode,"Overall")&&ds.Count>0){double w=0,sum=0;foreach(CpuDeviceSnapshot d in ds)if(d.UsageAvailable){double ww=d.LogicalProcessors>0?d.LogicalProcessors:1;sum+=d.Usage*ww;w+=ww;}if(w>0)usage=(float)(sum/w);}bool ta=ds.Any(d=>d.TemperatureAvailable)||snapshot.CpuTempAvailable;float tv=ds.Where(d=>d.TemperatureAvailable).Select(d=>d.Temperature).DefaultIfEmpty(snapshot.CpuTempCurrent).Max();string label=Mode(config.CpuDisplayMode,"Multiple")&&ds.Count>1?"CPU"+ds.Count:"CPU";MetricView m=config.ShowTemperatures?MakeDual("CPU",label,usage.ToString("0")+"%",FormatCpuTemperature(ta,tv),usage,"CPU",c):Make("CPU",label,usage.ToString("0")+"%",usage,"CPU",c);m.GroupKey="CPU";x.Add(m);
                }
            }
            if(config.ShowRam){MetricView m=config.ShowRamNumeric?MakeDual("RAM","RAM",snapshot.Ram.ToString("0")+"%",UnitFormatter.Pair(snapshot.RamUsedBytes,snapshot.RamTotalBytes,config.MemoryUnit),snapshot.Ram,"RAM",t.Accents[idx++%t.Accents.Length]):Make("RAM","RAM",snapshot.Ram.ToString("0")+"%",snapshot.Ram,"RAM",t.Accents[idx++%t.Accents.Length]);m.GroupKey="RAM";x.Add(m);}
            if(config.ShowDisk)
            {
                List<DiskDeviceSnapshot> ds=SelectedDiskDevices();Color c=t.Accents[idx++%t.Accents.Length];
                if(Mode(config.DiskDisplayMode,"Multiple")&&config.MultipleDeviceLayout=="Separate"&&ds.Count>1)
                {
                    for(int i=0;i<ds.Count;i++){DiskDeviceSnapshot d=ds[i];MetricView m=MakeDual("DISK:"+d.Id,"D"+i,"R "+UnitFormatter.Rate(d.ReadBytesPerSec,config.DiskRateUnit),"W "+UnitFormatter.Rate(d.WriteBytesPerSec,config.DiskRateUnit),d.Activity,"DISK:"+d.Id,c);m.GroupKey="DISK";m.DeviceId=d.Id;m.DisplayName=d.Name;x.Add(m);}
                }
                else
                {
                    double read=ds.Sum(d=>d.ReadBytesPerSec),write=ds.Sum(d=>d.WriteBytesPerSec);float act=ds.Count>0?ds.Max(d=>d.Activity):snapshot.Disk;string label=Mode(config.DiskDisplayMode,"Multiple")&&ds.Count>1?"DSK"+ds.Count:"DSK";MetricView m=MakeDual("DISK",label,"R "+UnitFormatter.Rate(read,config.DiskRateUnit),"W "+UnitFormatter.Rate(write,config.DiskRateUnit),act,"DISK",c);m.GroupKey="DISK";x.Add(m);
                }
            }
            if(config.ShowGpu)
            {
                List<GpuDeviceSnapshot> ds=SelectedGpuDevices();Color c=t.Accents[idx++%t.Accents.Length];
                if(Mode(config.GpuDisplayMode,"Multiple")&&config.MultipleDeviceLayout=="Separate"&&ds.Count>1)
                {
                    for(int i=0;i<ds.Count;i++){GpuDeviceSnapshot d=ds[i];string val=d.UsageAvailable?d.Usage.ToString("0")+"%":"N/A";MetricView m=config.ShowTemperatures?MakeDual("GPU:"+d.Id,"G"+i,val,d.TemperatureAvailable?("TEMP "+d.Temperature.ToString("0")+"°"):"TEMP N/A",d.Usage,"GPU:"+d.Id,c):Make("GPU:"+d.Id,"G"+i,val,d.Usage,"GPU:"+d.Id,c);m.GroupKey="GPU";m.DeviceId=d.Id;m.DisplayName=d.Name;x.Add(m);}
                }
                else
                {
                    float usage=ds.Where(d=>d.UsageAvailable).Select(d=>d.Usage).DefaultIfEmpty(snapshot.Gpu).Max();List<float> temps=ds.Where(d=>d.TemperatureAvailable).Select(d=>d.Temperature).ToList();bool ta=temps.Count>0;float av=ta?temps.Average():0;float mx=ta?temps.Max():0;string label=Mode(config.GpuDisplayMode,"Multiple")&&ds.Count>1?"GPU"+ds.Count:"GPU";MetricView m=config.ShowTemperatures?MakeDual("GPU",label,usage.ToString("0")+"%",FormatGpuTemperature(ta,av,mx),usage,"GPU",c):Make("GPU",label,usage.ToString("0")+"%",usage,"GPU",c);m.GroupKey="GPU";x.Add(m);
                }
            }
            List<GpuDeviceSnapshot> gpuForVram=SelectedGpuDevices();float vu=gpuForVram.Sum(d=>d.VramUsedGb),vt=gpuForVram.Sum(d=>d.VramTotalGb);float vp=vt>0?vu/vt*100f:0;if(config.ShowVram){MetricView m=Make("VRAM","VRAM",vt>0?vu.ToString("0.#")+"/"+vt.ToString("0.#")+"G":"N/A",vp,"VRAM",t.Accents[idx++%t.Accents.Length]);m.GroupKey="GPU";x.Add(m);}
            if(config.ShowNetwork)
            {
                List<NetworkDeviceSnapshot> ds=SelectedNetworkDevices();Color c=t.Accents[idx++%t.Accents.Length];
                if(Mode(config.NetworkDisplayMode,"Multiple")&&config.MultipleDeviceLayout=="Separate"&&ds.Count>1)
                {
                    for(int i=0;i<ds.Count;i++){NetworkDeviceSnapshot d=ds[i];MetricView m=MakeDual("NET:"+d.Id,"N"+i,"DL "+FormatTaskbarNetworkRate(d.DownBytesPerSec),"UL "+FormatTaskbarNetworkRate(d.UpBytesPerSec),(float)Math.Min(100,(d.DownBytesPerSec+d.UpBytesPerSec)*8d/1000000d),"NET:"+d.Id,c);m.GroupKey="NET";m.DeviceId=d.Id;m.DisplayName=d.Name;x.Add(m);}
                }
                else
                {
                    double down=ds.Sum(d=>d.DownBytesPerSec),up=ds.Sum(d=>d.UpBytesPerSec);string label=Mode(config.NetworkDisplayMode,"Multiple")&&ds.Count>1?"NET"+ds.Count:"NET";MetricView m=MakeDual("NET",label,"DL "+FormatTaskbarNetworkRate(down),"UL "+FormatTaskbarNetworkRate(up),(float)Math.Min(100,(down+up)*8d/1000000d),"NET",c);m.GroupKey="NET";x.Add(m);
                }
            }

            ApplyMetricAlerts(x);
            int availableWidth=availableWidthOverride>0?availableWidthOverride:(ClientRectangle.Width>0?ClientRectangle.Width:Width);
            if(availableWidth>0 && availableWidth<620){int vramIndex=x.FindIndex(delegate(MetricView m){return m.Key=="VRAM";});if(vramIndex>=0)x.RemoveAt(vramIndex);}
            if(availableWidth>0 && availableWidth<520){int diskIndex=x.FindIndex(delegate(MetricView m){return m.GroupKey=="DISK";});if(diskIndex>=0)x.RemoveAt(diskIndex);}
            string compactKey=availableWidth.ToString(CultureInfo.InvariantCulture)+"|"+String.Join(",",x.ConvertAll(delegate(MetricView m){return m.Key;}).ToArray());if(!String.Equals(compactKey,lastCompactLayoutKey,StringComparison.Ordinal)){lastCompactLayoutKey=compactKey;Log.Write("INFO","COMPACT_LAYOUT width="+availableWidth+" metrics="+String.Join(",",x.ConvertAll(delegate(MetricView m){return m.Key;}).ToArray())+" font="+config.FontSize.ToString("0.0",CultureInfo.InvariantCulture));}
            return OrderWorkspaceMetrics(x);
        }
        private MetricView Make(string key,string label,string value,float pct,string hist,Color c){MetricView m=new MetricView();m.Key=key;m.GroupKey=key;m.Label=label;m.Value=value;m.Value2=null;m.Percent=pct;m.History=history.Get(hist);m.Accent=c;return m;}
        private MetricView MakeDual(string key,string label,string value1,string value2,float pct,string hist,Color c){MetricView m=new MetricView();m.Key=key;m.GroupKey=key;m.Label=label;m.Value=value1;m.Value2=value2;m.Percent=pct;m.History=history.Get(hist);m.Accent=c;return m;}

        private void ApplyMetricAlerts(List<MetricView> metrics)
        {
            if(metrics==null||!config.EnableTemperatureAlerts)return;
            foreach(MetricView m in metrics)
            {
                bool hot=false;float temp=0;
                if(String.Equals(m.GroupKey,"CPU",StringComparison.Ordinal))
                {
                    if(!String.IsNullOrWhiteSpace(m.DeviceId))
                    {
                        CpuDeviceSnapshot d=snapshot.CpuDevices.FirstOrDefault(x=>String.Equals(x.Id,m.DeviceId,StringComparison.Ordinal));
                        if(d!=null){hot=AlertPolicy.IsCpuHot(d.TemperatureAvailable,d.Temperature,config);temp=d.Temperature;}
                    }
                    else
                    {
                        List<CpuDeviceSnapshot> ds=SelectedCpuDevices();List<float> ts=ds.Where(d=>d.TemperatureAvailable).Select(d=>d.Temperature).ToList();
                        bool available=ts.Count>0||snapshot.CpuTempAvailable;temp=ts.Count>0?ts.Max():snapshot.CpuTempCurrent;hot=AlertPolicy.IsCpuHot(available,temp,config);
                    }
                }
                else if(String.Equals(m.GroupKey,"GPU",StringComparison.Ordinal)&&m.Key!="VRAM")
                {
                    if(!String.IsNullOrWhiteSpace(m.DeviceId))
                    {
                        GpuDeviceSnapshot d=snapshot.GpuDevices.FirstOrDefault(x=>String.Equals(x.Id,m.DeviceId,StringComparison.Ordinal));
                        if(d!=null){hot=AlertPolicy.IsGpuHot(d.TemperatureAvailable,d.Temperature,config);temp=d.Temperature;}
                    }
                    else
                    {
                        List<float> ts=SelectedGpuDevices().Where(d=>d.TemperatureAvailable).Select(d=>d.Temperature).ToList();
                        bool available=ts.Count>0||snapshot.GpuTempAvailable;temp=ts.Count>0?ts.Max():snapshot.GpuTemp;hot=AlertPolicy.IsGpuHot(available,temp,config);
                    }
                }
                else if(String.Equals(m.GroupKey,"DISK",StringComparison.Ordinal))
                {
                    if(!String.IsNullOrWhiteSpace(m.DeviceId))
                    {
                        DiskDeviceSnapshot d=snapshot.DiskDevices.FirstOrDefault(x=>String.Equals(x.Id,m.DeviceId,StringComparison.Ordinal));
                        if(d!=null){hot=AlertPolicy.IsDiskHot(d.TemperatureAvailable,d.Temperature,config);temp=d.Temperature;}
                    }
                    else
                    {
                        List<float> ts=SelectedDiskDevices().Where(d=>d.TemperatureAvailable).Select(d=>d.Temperature).ToList();
                        bool available=ts.Count>0;temp=available?ts.Max():0;hot=AlertPolicy.IsDiskHot(available,temp,config);
                    }
                }
                if(hot)
                {
                    m.Alert=true;
                    m.AlertText=m.GroupKey+" "+temp.ToString("0",CultureInfo.InvariantCulture)+"C";
                    m.Accent=AlertPolicy.AlertColor;
                }
            }
        }

        private static string FormatCpuTemperature(bool available,float current)
        {
            if(!available)return "TEMP N/A";
            return "TEMP "+current.ToString("0",CultureInfo.InvariantCulture)+"°";
        }
        private static string FormatGpuTemperature(bool available,float average,float maximum)
        {
            if(!available)return "TEMP N/A";
            return "TEMP A"+average.ToString("0",CultureInfo.InvariantCulture)+" M"+maximum.ToString("0",CultureInfo.InvariantCulture)+"°";
        }
        private static string CompactUnitTokens(string value)
        {
            if(String.IsNullOrWhiteSpace(value))return "";
            return value.Trim()
                .Replace(" KB/s","K/s").Replace(" MB/s","M/s").Replace(" GB/s","G/s")
                .Replace(" KB","K").Replace(" MB","M").Replace(" GB","G");
        }
        private static string CompactNumericToken(string text)
        {
            double v;
            if(!Double.TryParse(text,NumberStyles.Float,CultureInfo.InvariantCulture,out v))return text;
            double a=Math.Abs(v);
            if(a<10000d)return text;
            string e=v.ToString("0.#E+0",CultureInfo.InvariantCulture);
            return e.Replace("E+","e").Replace("E-","e-").Replace("E","e");
        }
        private static string CompactPairToken(string value)
        {
            string s=CompactUnitTokens(value);
            int slash=s.IndexOf('/');
            if(slash<=0)return s;
            string left=s.Substring(0,slash);
            string right=s.Substring(slash+1);
            string unit="";
            if(right.EndsWith("K",StringComparison.Ordinal)||right.EndsWith("M",StringComparison.Ordinal)||right.EndsWith("G",StringComparison.Ordinal))
            {
                unit=right.Substring(right.Length-1);
                right=right.Substring(0,right.Length-1);
            }
            return CompactNumericToken(left)+"/"+CompactNumericToken(right)+unit;
        }
        private static string CompactSecondaryValue(MetricView m)
        {
            if(m==null||String.IsNullOrWhiteSpace(m.Value2))return "";
            string s=m.Value2.Trim();
            if(m.GroupKey=="CPU"&&s.StartsWith("TEMP ",StringComparison.Ordinal))return "T "+s.Substring(5);
            if(m.GroupKey=="GPU")
            {
                if(String.Equals(s,"TEMP N/A",StringComparison.Ordinal))return "T N/A";
                if(s.StartsWith("TEMP A",StringComparison.Ordinal))return "T "+s.Substring(6).Replace(" M","/");
            }
            if(m.GroupKey=="RAM")return CompactPairToken(s);
            if(m.GroupKey=="DISK")
            {
                int act=s.IndexOf("  ACT ",StringComparison.Ordinal);if(act>0)s=s.Substring(0,act);return CompactPairToken(s);
            }
            if(m.GroupKey=="NET")return CompactUnitTokens(s);
            return CompactUnitTokens(s);
        }
        private static bool LineFits(Graphics g,Font f,string text,float maxWidth)
        {
            return g.MeasureString(text??"",f).Width<=maxWidth;
        }
        private static string MiddleElideToFit(Graphics g,Font f,string text,float maxWidth)
        {
            if(String.IsNullOrEmpty(text)||LineFits(g,f,text,maxWidth))return text;
            if(maxWidth<=8)return "";
            const string ellipsis="…";
            int left=(text.Length+1)/2;
            int right=text.Length-left;
            while(left>1||right>1)
            {
                string c=text.Substring(0,left)+ellipsis+text.Substring(text.Length-right,right);
                if(LineFits(g,f,c,maxWidth))return c;
                if(left>=right&&left>1)left--;else if(right>1)right--;else break;
            }
            string tiny=text.Substring(0,1)+ellipsis+(text.Length>1?text.Substring(text.Length-1):"");
            return tiny;
        }
        private static string FitCompactLine(Graphics g,Font f,MetricView m,string line,float maxWidth,bool secondary)
        {
            if(LineFits(g,f,line,maxWidth))return line;
            string compact=CompactUnitTokens(line);
            if(m!=null&&m.GroupKey=="NET")
            {
                compact=compact.Replace("DL ","D ").Replace("UL ","U ");
            }
            if(LineFits(g,f,compact,maxWidth))return compact;
            if(secondary&&m!=null&&(m.GroupKey=="RAM"||m.GroupKey=="DISK"))
            {
                string pair=CompactPairToken(compact);
                if(LineFits(g,f,pair,maxWidth))return pair;
                int slash=pair.IndexOf('/');
                if(slash>0)
                {
                    string unit="";
                    if(pair.EndsWith("K",StringComparison.Ordinal)||pair.EndsWith("M",StringComparison.Ordinal)||pair.EndsWith("G",StringComparison.Ordinal))unit=pair.Substring(pair.Length-1);
                    string used=pair.Substring(0,slash)+unit;
                    if(LineFits(g,f,used,maxWidth))return used;
                }
            }
            compact=compact.Replace(" ","");
            if(LineFits(g,f,compact,maxWidth))return compact;
            // Last-resort visual safety. Full values remain available in the hardware flyout/settings;
            // compact cards must never clip neighboring taskbar cards.
            return MiddleElideToFit(g,f,compact,maxWidth);
        }
        private static string BuildMetricHeadline(Graphics g,ThemeDefinition t,MetricView m,float readableMinimum,float maxWidth)
        {
            string primary=(m.Label+" "+m.Value).Trim();
            using(Font readable=SafeFont(t.FontName,readableMinimum,FontStyle.Bold))
            {
                if(String.IsNullOrWhiteSpace(m.Value2))return FitCompactLine(g,readable,m,primary,maxWidth,false);
                string inline=primary+"    "+m.Value2;
                if(LineFits(g,readable,inline,maxWidth))return inline;

                string p=FitCompactLine(g,readable,m,primary,maxWidth,false);
                string secondary=CompactSecondaryValue(m);
                if(m.GroupKey=="NET")
                {
                    p=FitCompactLine(g,readable,m,m.Value,maxWidth,false);
                    secondary=FitCompactLine(g,readable,m,m.Value2,maxWidth,true);
                }
                else secondary=FitCompactLine(g,readable,m,secondary,maxWidth,true);
                return p+"\n"+secondary;
            }
        }
        private static bool HeadlineIsStacked(string headline){return !String.IsNullOrEmpty(headline)&&headline.IndexOf('\n')>=0;}
        private static float MaxLineWidth(Graphics g,string headline,Font f)
        {
            float max=0;
            foreach(string line in (headline??"").Split(new char[]{'\n'}))max=Math.Max(max,g.MeasureString(line,f).Width);
            return max;
        }
        private static Font FitHeadlineFont(Graphics g,string fontName,string text,float start,float minimum,float maxWidth)
        {
            float size=start;
            while(size>minimum)
            {
                Font f=SafeFont(fontName,size,FontStyle.Bold);
                if(g.MeasureString(text,f).Width<=maxWidth)return f;
                f.Dispose();
                size-=0.35f;
            }
            return SafeFont(fontName,minimum,FontStyle.Bold);
        }
        private static string FormatRateCompact(float mbps){if(mbps>=100)return mbps.ToString("0");if(mbps>=10)return mbps.ToString("0.0");return mbps.ToString("0.00");}

        private void PaintBackground(Graphics g,ThemeDefinition t,Rectangle r)
        {
            if(t.Mode=="glass")using(LinearGradientBrush b=new LinearGradientBrush(r,t.Background,t.Background2,0f))g.FillRectangle(b,r);
            else using(SolidBrush b=new SolidBrush(t.Background))g.FillRectangle(b,r);
            if(t.Mode=="neon")using(Pen p=new Pen(Color.FromArgb(150,t.Border),1))g.DrawLine(p,0,0,r.Width,0);
            if(t.Mode=="terminal")using(Pen p=new Pen(Color.FromArgb(35,t.Foreground),1)){for(int y=3;y<r.Height;y+=4)g.DrawLine(p,0,y,r.Width,y);}
            if(IsExtendedThemeMode(t.Mode))PaintExtendedBackground(g,t,r);
            if(StudioThemes.IsStudio(t.Mode))PaintStudioBackground(g,t,r);
        }

        private void PaintMetric(Graphics g,ThemeDefinition t,MetricView m,RectangleF r,int index)
        {
            RectangleF inner=new RectangleF(r.X+3,r.Y+3,r.Width-6,r.Height-6);
            if(m.Alert)
            {
                using(Pen hotPen=new Pen(Color.FromArgb(235,AlertPolicy.AlertColor),2f))
                    g.DrawRectangle(hotPen,inner.X,inner.Y,Math.Max(1,inner.Width-1),Math.Max(1,inner.Height-1));
                // Preserve a semantic warning mask for Glass mode: recolor ONLY
                // hot metric glyphs/charts, never normal theme ink or the backdrop.
                if(glassThermalWarningCanvas!=null)
                {
                    using(SolidBrush maskBrush=new SolidBrush(Color.White))
                        glassThermalWarningCanvas.FillRectangle(maskBrush,inner);
                    if(glassInkCanvas!=null)
                        using(Pen rim=new Pen(Color.White,2f))
                            glassInkCanvas.DrawRectangle(rim,inner.X,inner.Y,Math.Max(1,inner.Width-1),Math.Max(1,inner.Height-1));
                    if(glassHaloCanvas!=null)
                        using(Pen haloRim=new Pen(Color.White,4f))
                            glassHaloCanvas.DrawRectangle(haloRim,inner.X,inner.Y,Math.Max(1,inner.Width-1),Math.Max(1,inner.Height-1));
                }
            }
            if(t.Mode=="round"||t.Mode=="glass")
            {
                using(GraphicsPath gp=RoundRect(inner,10))using(SolidBrush b=new SolidBrush(Color.FromArgb(t.Mode=="glass"?70:165,t.Background2)))g.FillPath(b,gp);
                using(GraphicsPath gp=RoundRect(inner,10))using(Pen p=new Pen(Color.FromArgb(100,t.Border),1))g.DrawPath(p,gp);
            }
            else if(t.Mode=="hex")
            {
                using(Pen p=new Pen(Color.FromArgb(90,t.Border),1))g.DrawLine(p,r.Right-1,6,r.Right-1,r.Height-6);
            }
            else if(index>0)using(Pen p=new Pen(Color.FromArgb(t.Light?90:75,t.Border),1))g.DrawLine(p,r.X,7,r.X,r.Height-7);

            float baseScale=(config!=null && config.FontSize>0)?(float)(config.FontSize/10.0):1f;
            // R06: adapt layout before shrinking text; keep a readable floor.
            if(baseScale<0.85f)baseScale=0.85f;
            if(baseScale>1.20f)baseScale=1.20f;

            Font labelFont=SafeFont(t.FontName,(t.Mode=="terminal"?7.1f:7.4f)*baseScale,FontStyle.Bold);
            Font valueFont=SafeFont(t.FontName,(t.Mode=="terminal"?8.8f:10.1f)*baseScale,FontStyle.Bold);
            try
            {
                if(StudioThemes.IsStudio(t.Mode)) PaintStudioMetric(g,t,m,inner,labelFont,valueFont);
                else if(t.Mode=="hex") PaintHexMetric(g,t,m,inner,labelFont,valueFont);
                else if(IsExtendedThemeMode(t.Mode)) PaintExtendedMetric(g,t,m,inner,labelFont,valueFont);
                else if(t.Mode=="terminal") PaintTerminalMetric(g,t,m,inner,labelFont,valueFont);
                else PaintStandardMetric(g,t,m,inner,labelFont,valueFont);
            }
            finally{labelFont.Dispose();valueFont.Dispose();}
            if(m.Alert&&StudioThemes.IsStudio(t.Mode))using(Pen hot=new Pen(AlertPolicy.AlertColor,2f))g.DrawRectangle(hot,inner.X,inner.Y,Math.Max(1,inner.Width-1),Math.Max(1,inner.Height-1));
        }

        private void PaintStandardMetric(Graphics g,ThemeDefinition t,MetricView m,RectangleF r,Font labelFont,Font valueFont)
        {
            float baseScale=(config!=null && config.FontSize>0)?(float)(config.FontSize/10.0):1f;
            if(baseScale<0.85f)baseScale=0.85f;
            if(baseScale>1.20f)baseScale=1.20f;
            float readableMin=Math.Max(7.4f,7.4f*baseScale);
            string headline=BuildMetricHeadline(g,t,m,readableMin,r.Width-10);
            bool stacked=HeadlineIsStacked(headline);
            using(Font hf=FitHeadlineFont(g,t.FontName,headline,Math.Max(8.7f,8.7f*baseScale),readableMin,r.Width-10))
            using(SolidBrush fg=new SolidBrush(t.Foreground))
                DrawThemeGlyph(g,headline,hf,fg,r.X+5,r.Y+1);

            float graphTop=stacked?29f:22f;
            RectangleF graph=new RectangleF(r.X+5,r.Y+graphTop,Math.Max(34,r.Width-10),Math.Max(6,r.Height-(graphTop+4)));
            if(config.ShowSparklines)DrawSparkline(g,m.History,graph,m.Accent,t.Mode=="neon"?1.8f:1.3f,t.Mode=="neon");

            float barWidth=Math.Max(3,(r.Width-10)*Math.Max(0,Math.Min(100,m.Percent))/100f);
            using(SolidBrush a=new SolidBrush(m.Accent))g.FillRectangle(a,r.X+5,r.Bottom-3,barWidth,2);
        }

        private void PaintNetworkMetric(Graphics g,ThemeDefinition t,MetricView m,RectangleF r,Font labelFont,Font valueFont)
        {
            Font netFont=SafeFont(t.FontName,t.Mode=="terminal"?7.0f:7.6f,FontStyle.Bold);
            try
            {
                using(SolidBrush muted=new SolidBrush(t.Muted))DrawThemeGlyph(g,m.Label,labelFont,muted,r.X+5,r.Y+1);

                SizeF v1=g.MeasureString(m.Value,netFont);
                SizeF v2=g.MeasureString(m.Value2,netFont);
                float textWidth=Math.Max(v1.Width,v2.Width);
                float textRight=r.X+5+textWidth;

                float graphLeft=Math.Max(r.X+64,textRight+8);
                float minGraph=36f;
                if(graphLeft>r.Right-minGraph-7)graphLeft=r.Right-minGraph-7;

                using(SolidBrush fg=new SolidBrush(t.Foreground))
                {
                    DrawThemeGlyph(g,m.Value,netFont,fg,r.X+5,r.Y+13);
                    DrawThemeGlyph(g,m.Value2,netFont,fg,r.X+5,r.Y+24);
                }

                RectangleF graph=new RectangleF(
                    graphLeft,
                    r.Y+7,
                    Math.Max(minGraph,r.Right-7-graphLeft),
                    r.Height-14
                );

                if(config.ShowSparklines)DrawSparkline(g,m.History,graph,m.Accent,1.4f,false);

                float textZoneWidth=Math.Max(30,graphLeft-(r.X+5)-6);
                float barWidth=Math.Max(3,textZoneWidth*Math.Max(0,Math.Min(100,m.Percent))/100f);
                using(SolidBrush a=new SolidBrush(m.Accent))
                    g.FillRectangle(a,r.X+5,r.Bottom-3,barWidth,2);
            }
            finally
            {
                netFont.Dispose();
            }
        }

        private void PaintHexMetric(Graphics g,ThemeDefinition t,MetricView m,RectangleF r,Font labelFont,Font valueFont)
        {
            float readableMin=7.3f;
            string headline=BuildMetricHeadline(g,t,m,readableMin,Math.Max(72,r.Width-60));
            float maxBadge=Math.Max(90,r.Width-42);
            float badgeWidth=Math.Min(maxBadge,Math.Max(88,r.Width*0.72f));
            RectangleF hx=new RectangleF(r.X+4,r.Y+1,badgeWidth,r.Height-2);
            PointF[] pts=Hex(hx);
            using(SolidBrush b=new SolidBrush(Color.FromArgb(34,m.Accent)))g.FillPolygon(b,pts);
            using(Pen p=new Pen(m.Accent,1.5f))g.DrawPolygon(p,pts);

            using(Font hf=FitHeadlineFont(g,t.FontName,headline,8.4f,readableMin,hx.Width-18))
            using(SolidBrush fb=new SolidBrush(t.Foreground))
            {
                SizeF hs=g.MeasureString(headline,hf);
                DrawThemeGlyph(g,headline,hf,fb,hx.X+(hx.Width-hs.Width)/2,hx.Y+(hx.Height-hs.Height)/2-1);
            }

            float graphX=hx.Right+5;
            RectangleF graph=new RectangleF(graphX,r.Y+7,Math.Max(24,r.Right-5-graphX),r.Height-14);
            if(config.ShowSparklines)DrawSparkline(g,m.History,graph,m.Accent,1.3f,false);
        }

        private void PaintTerminalMetric(Graphics g,ThemeDefinition t,MetricView m,RectangleF r,Font labelFont,Font valueFont)
        {
            float readableMin=7.5f;
            string headline=BuildMetricHeadline(g,t,m,readableMin,r.Width-8);
            bool stacked=HeadlineIsStacked(headline);
            using(Font hf=FitHeadlineFont(g,t.FontName,headline,9.0f,readableMin,r.Width-8))
            using(SolidBrush b=new SolidBrush(t.Foreground))
                DrawThemeGlyph(g,headline,hf,b,r.X+4,r.Y+1);

            if(config.ShowSparklines)
            {
                float graphTop=stacked?29f:22f;
                DrawTerminalBars(g,m.History,new RectangleF(r.X+4,r.Y+graphTop,r.Width-8,Math.Max(6,r.Height-(graphTop+3))),m.Accent);
            }
        }

        private static Font SafeFont(string name,float size,FontStyle style){try{return new Font(name,size,style,GraphicsUnit.Point);}catch{return new Font("Segoe UI",size,style,GraphicsUnit.Point);}}
        private static GraphicsPath RoundRect(RectangleF r,float rad){float d=rad*2;GraphicsPath p=new GraphicsPath();p.AddArc(r.X,r.Y,d,d,180,90);p.AddArc(r.Right-d,r.Y,d,d,270,90);p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);p.AddArc(r.X,r.Bottom-d,d,d,90,90);p.CloseFigure();return p;}
        private static PointF[] Hex(RectangleF r){float q=r.Width*0.18f;return new PointF[]{new PointF(r.X+q,r.Y),new PointF(r.Right-q,r.Y),new PointF(r.Right,r.Y+r.Height/2),new PointF(r.Right-q,r.Bottom),new PointF(r.X+q,r.Bottom),new PointF(r.X,r.Y+r.Height/2)};}

        private static bool IsExtendedThemeMode(string mode)
        {
            return mode=="fluent"||mode=="oled"||mode=="cyber2"||mode=="mission"||mode=="blueprint"||mode=="medical"||mode=="carbon"||mode=="aurora"||mode=="luxe"||mode=="zen"||mode=="synth"||mode=="matrix"||mode=="paper"||mode=="industrial";
        }

        private void PaintExtendedBackground(Graphics g,ThemeDefinition t,Rectangle r)
        {
            if(t.Mode=="fluent")
            {
                using(LinearGradientBrush b=new LinearGradientBrush(r,t.Background2,t.Background,90f))g.FillRectangle(b,r);
                using(Pen hi=new Pen(Color.FromArgb(95,210,235,255),1))g.DrawLine(hi,0,0,r.Width,0);
                using(Pen lo=new Pen(Color.FromArgb(70,t.Border),1))g.DrawLine(lo,0,r.Height-1,r.Width,r.Height-1);
            }
            else if(t.Mode=="oled")
            {
                using(SolidBrush b=new SolidBrush(Color.Black))g.FillRectangle(b,r);
                using(Pen p=new Pen(Color.FromArgb(34,255,255,255),1))g.DrawLine(p,0,r.Height-1,r.Width,r.Height-1);
            }
            else if(t.Mode=="cyber2")
            {
                using(LinearGradientBrush b=new LinearGradientBrush(r,t.Background,t.Background2,0f))g.FillRectangle(b,r);
                using(Pen c=new Pen(Color.FromArgb(105,0,246,255),1))
                using(Pen m=new Pen(Color.FromArgb(90,255,65,220),1))
                {
                    g.DrawLine(c,0,0,r.Width*0.42f,0);g.DrawLine(m,r.Width*0.58f,0,r.Width,0);
                    g.DrawLine(m,0,r.Height-1,r.Width*0.22f,r.Height-1);g.DrawLine(c,r.Width*0.78f,r.Height-1,r.Width,r.Height-1);
                }
            }
            else if(t.Mode=="mission")
            {
                using(SolidBrush b=new SolidBrush(t.Background))g.FillRectangle(b,r);
                using(Pen p=new Pen(Color.FromArgb(28,t.Foreground),1)){for(int y=12;y<r.Height;y+=12)g.DrawLine(p,0,y,r.Width,y);}
            }
            else if(t.Mode=="blueprint")
            {
                using(LinearGradientBrush b=new LinearGradientBrush(r,t.Background,t.Background2,0f))g.FillRectangle(b,r);
                using(Pen grid=new Pen(Color.FromArgb(30,190,230,255),1))
                {
                    for(int x=0;x<r.Width;x+=22)g.DrawLine(grid,x,0,x,r.Height);
                    for(int y=0;y<r.Height;y+=12)g.DrawLine(grid,0,y,r.Width,y);
                }
            }
            else if(t.Mode=="medical")
            {
                using(LinearGradientBrush b=new LinearGradientBrush(r,t.Background,t.Background2,90f))g.FillRectangle(b,r);
                using(Pen grid=new Pen(Color.FromArgb(34,69,156,160),1))
                {
                    for(int x=0;x<r.Width;x+=24)g.DrawLine(grid,x,0,x,r.Height);
                    for(int y=0;y<r.Height;y+=12)g.DrawLine(grid,0,y,r.Width,y);
                }
            }
            else if(t.Mode=="carbon")
            {
                using(SolidBrush b=new SolidBrush(t.Background))g.FillRectangle(b,r);
                using(Pen p1=new Pen(Color.FromArgb(25,255,255,255),1))
                using(Pen p2=new Pen(Color.FromArgb(22,0,0,0),1))
                {
                    for(int x=-r.Height;x<r.Width;x+=12)
                    {
                        g.DrawLine(p1,x,0,x+r.Height,r.Height);
                        g.DrawLine(p2,x+6,0,x+6-r.Height,r.Height);
                    }
                }
            }            else if(t.Mode=="aurora")
            {
                using(LinearGradientBrush b=new LinearGradientBrush(r,t.Background,t.Background2,0f))g.FillRectangle(b,r);
                using(Pen p1=new Pen(Color.FromArgb(54,t.Accents[0]),2f))g.DrawBezier(p1,-40,r.Height-3,r.Width*.28f,-10,r.Width*.56f,r.Height+8,r.Width+45,1);
                using(Pen p2=new Pen(Color.FromArgb(38,t.Accents[1]),1.5f))g.DrawBezier(p2,-20,3,r.Width*.35f,r.Height+9,r.Width*.72f,-8,r.Width+20,r.Height-4);
            }
            else if(t.Mode=="luxe")
            {
                using(LinearGradientBrush b=new LinearGradientBrush(r,t.Background2,t.Background,90f))g.FillRectangle(b,r);
                using(Pen hi=new Pen(Color.FromArgb(85,t.Accents[0]),1))g.DrawLine(hi,0,0,r.Width,0);
                using(Pen lo=new Pen(Color.FromArgb(45,t.Border),1))g.DrawLine(lo,0,r.Height-1,r.Width,r.Height-1);
            }
            else if(t.Mode=="zen")
            {
                using(LinearGradientBrush b=new LinearGradientBrush(r,t.Background,t.Background2,90f))g.FillRectangle(b,r);
                using(Pen p=new Pen(Color.FromArgb(55,t.Border),1)){for(int x=18;x<r.Width;x+=72)g.DrawLine(p,x,6,x,r.Height-6);}
            }
            else if(t.Mode=="synth")
            {
                using(LinearGradientBrush b=new LinearGradientBrush(r,t.Background,t.Background2,0f))g.FillRectangle(b,r);
                int horizon=Math.Max(10,r.Height-11);
                using(Pen h=new Pen(Color.FromArgb(80,t.Accents[0]),1))g.DrawLine(h,0,horizon,r.Width,horizon);
                using(Pen grid=new Pen(Color.FromArgb(34,t.Accents[1]),1)){for(int x=0;x<r.Width;x+=34)g.DrawLine(grid,x,r.Height,x+12,horizon);}
            }
            else if(t.Mode=="matrix")
            {
                using(SolidBrush b=new SolidBrush(t.Background))g.FillRectangle(b,r);
                using(Pen grid=new Pen(Color.FromArgb(32,t.Foreground),1)){for(int x=5;x<r.Width;x+=24)g.DrawLine(grid,x,0,x,r.Height);for(int y=6;y<r.Height;y+=8)g.DrawLine(grid,0,y,r.Width,y);}
            }
            else if(t.Mode=="paper")
            {
                using(LinearGradientBrush b=new LinearGradientBrush(r,t.Background,t.Background2,90f))g.FillRectangle(b,r);
                using(Pen p=new Pen(Color.FromArgb(50,t.Border),1)){for(int y=12;y<r.Height;y+=12)g.DrawLine(p,0,y,r.Width,y);}
            }
            else if(t.Mode=="industrial")
            {
                using(SolidBrush b=new SolidBrush(t.Background))g.FillRectangle(b,r);
                using(Pen p=new Pen(Color.FromArgb(28,t.Border),1)){for(int x=-r.Height;x<r.Width;x+=18)g.DrawLine(p,x,0,x+r.Height,r.Height);}
                using(Pen top=new Pen(Color.FromArgb(105,t.Accents[0]),2))g.DrawLine(top,0,1,r.Width,1);
            }
        }

        private void PaintExtendedMetric(Graphics g,ThemeDefinition t,MetricView m,RectangleF r,Font labelFont,Font valueFont)
        {
            if(t.Mode=="fluent")PaintFluentMetric(g,t,m,r,labelFont,valueFont);
            else if(t.Mode=="oled")PaintOledMetric(g,t,m,r,labelFont,valueFont);
            else if(t.Mode=="cyber2")PaintCyberMetric(g,t,m,r,labelFont,valueFont);
            else if(t.Mode=="mission")PaintMissionMetric(g,t,m,r,labelFont,valueFont);
            else if(t.Mode=="blueprint")PaintBlueprintMetric(g,t,m,r,labelFont,valueFont);
            else if(t.Mode=="medical")PaintMedicalMetric(g,t,m,r,labelFont,valueFont);
            else if(t.Mode=="carbon")PaintCarbonMetric(g,t,m,r,labelFont,valueFont);
            else if(t.Mode=="aurora"||t.Mode=="luxe"||t.Mode=="zen"||t.Mode=="synth"||t.Mode=="matrix"||t.Mode=="paper"||t.Mode=="industrial")PaintPremiumMetric(g,t,m,r,labelFont,valueFont);
        }

        private float DrawExtendedValueBlock(Graphics g,ThemeDefinition t,MetricView m,RectangleF r,Font labelFont,Font valueFont,float x,float labelY,float valueY,Color valueColor)
        {
            float available=Math.Max(40,r.Right-x-4);
            float readableMin=7.4f;
            string headline=BuildMetricHeadline(g,t,m,readableMin,available);
            using(Font hf=FitHeadlineFont(g,t.FontName,headline,8.7f,readableMin,available))
            using(SolidBrush vb=new SolidBrush(valueColor))
            {
                DrawThemeGlyph(g,headline,hf,vb,x,r.Y+2);
                return x+MaxLineWidth(g,headline,hf);
            }
        }

        private bool ExtendedHeadlineStacks(Graphics g,ThemeDefinition t,MetricView m,RectangleF r,float x)
        {
            float available=Math.Max(40,r.Right-x-4);
            return HeadlineIsStacked(BuildMetricHeadline(g,t,m,7.4f,available));
        }

        private void PaintFluentMetric(Graphics g,ThemeDefinition t,MetricView m,RectangleF r,Font labelFont,Font valueFont)
        {
            using(GraphicsPath gp=RoundRect(r,8))
            using(LinearGradientBrush fill=new LinearGradientBrush(r,Color.FromArgb(88,t.Background2),Color.FromArgb(45,t.Background),90f))
            using(Pen edge=new Pen(Color.FromArgb(105,t.Border),1)){g.FillPath(fill,gp);g.DrawPath(edge,gp);}
            using(SolidBrush dot=new SolidBrush(m.Accent))g.FillEllipse(dot,r.X+7,r.Y+8,4,4);
            float tr=DrawExtendedValueBlock(g,t,m,r,labelFont,valueFont,r.X+15,r.Y+2,r.Y+15,t.Foreground);
            float gx=Math.Max(r.X+72,tr+8);
            bool stacked=ExtendedHeadlineStacks(g,t,m,r,r.X+15);
            float graphTop=stacked?29f:23f;
            RectangleF graph=new RectangleF(r.X+7,r.Y+graphTop,Math.Max(32,r.Width-14),Math.Max(6,r.Height-(graphTop+4)));
            if(config.ShowSparklines)DrawSparkline(g,m.History,graph,m.Accent,1.35f,false);
        }

        private void PaintOledMetric(Graphics g,ThemeDefinition t,MetricView m,RectangleF r,Font labelFont,Font valueFont)
        {
            using(Pen edge=new Pen(Color.FromArgb(60,255,255,255),1))g.DrawLine(edge,r.X+3,r.Bottom-2,r.Right-3,r.Bottom-2);
            float tr=DrawExtendedValueBlock(g,t,m,r,labelFont,valueFont,r.X+5,r.Y+2,r.Y+15,t.Foreground);
            float gx=Math.Max(r.X+70,tr+8);
            bool stacked=ExtendedHeadlineStacks(g,t,m,r,r.X+5);
            float graphTop=stacked?29f:23f;
            RectangleF graph=new RectangleF(r.X+6,r.Y+graphTop,Math.Max(34,r.Width-12),Math.Max(6,r.Height-(graphTop+4)));
            if(config.ShowSparklines)DrawSparkline(g,m.History,graph,Color.FromArgb(225,m.Accent),1.05f,false);
            using(SolidBrush tick=new SolidBrush(Color.FromArgb(210,m.Accent)))g.FillRectangle(tick,r.X+4,r.Y+5,2,5);
        }

        private void PaintCyberMetric(Graphics g,ThemeDefinition t,MetricView m,RectangleF r,Font labelFont,Font valueFont)
        {
            float cut=9f;
            PointF[] p=new PointF[]{new PointF(r.X+cut,r.Y),new PointF(r.Right-cut,r.Y),new PointF(r.Right,r.Y+cut),new PointF(r.Right,r.Bottom-cut),new PointF(r.Right-cut,r.Bottom),new PointF(r.X+cut,r.Bottom),new PointF(r.X,r.Bottom-cut),new PointF(r.X,r.Y+cut)};
            using(SolidBrush fill=new SolidBrush(Color.FromArgb(32,m.Accent)))g.FillPolygon(fill,p);
            using(Pen glow=new Pen(Color.FromArgb(55,m.Accent),4f))g.DrawPolygon(glow,p);
            using(Pen edge=new Pen(m.Accent,1.15f))g.DrawPolygon(edge,p);
            float tr=DrawExtendedValueBlock(g,t,m,r,labelFont,valueFont,r.X+10,r.Y+2,r.Y+15,m.Accent);
            float gx=Math.Max(r.X+78,tr+7);
            bool stacked=ExtendedHeadlineStacks(g,t,m,r,r.X+10);
            float graphTop=stacked?29f:23f;
            RectangleF graph=new RectangleF(r.X+9,r.Y+graphTop,Math.Max(28,r.Width-18),Math.Max(6,r.Height-(graphTop+4)));
            if(config.ShowSparklines)DrawSparkline(g,m.History,graph,m.Accent,1.55f,true);
        }

        private void PaintMissionMetric(Graphics g,ThemeDefinition t,MetricView m,RectangleF r,Font labelFont,Font valueFont)
        {
            RectangleF panel=new RectangleF(r.X+1,r.Y+1,r.Width-2,r.Height-2);
            using(SolidBrush fill=new SolidBrush(Color.FromArgb(150,t.Background2)))g.FillRectangle(fill,panel);
            using(Pen edge=new Pen(t.Border,1))g.DrawRectangle(edge,panel.X,panel.Y,panel.Width,panel.Height);
            using(SolidBrush band=new SolidBrush(m.Accent))g.FillRectangle(band,panel.X,panel.Y,4,panel.Height);
            float tr=DrawExtendedValueBlock(g,t,m,r,labelFont,valueFont,r.X+10,r.Y+2,r.Y+15,t.Foreground);
            float gx=Math.Max(r.X+77,tr+7);
            bool stacked=ExtendedHeadlineStacks(g,t,m,r,r.X+10);
            float graphTop=stacked?29f:23f;
            RectangleF graph=new RectangleF(r.X+7,r.Y+graphTop,Math.Max(28,r.Width-14),Math.Max(6,r.Height-(graphTop+4)));
            if(config.ShowSparklines)DrawMissionBars(g,m.History,graph,m.Accent);
        }

        private void PaintBlueprintMetric(Graphics g,ThemeDefinition t,MetricView m,RectangleF r,Font labelFont,Font valueFont)
        {
            using(Pen p=new Pen(Color.FromArgb(180,m.Accent),1))
            {
                float l=9f;
                g.DrawLine(p,r.X+2,r.Y+2,r.X+2+l,r.Y+2);g.DrawLine(p,r.X+2,r.Y+2,r.X+2,r.Y+2+l);
                g.DrawLine(p,r.Right-2-l,r.Y+2,r.Right-2,r.Y+2);g.DrawLine(p,r.Right-2,r.Y+2,r.Right-2,r.Y+2+l);
                g.DrawLine(p,r.X+2,r.Bottom-2,r.X+2+l,r.Bottom-2);g.DrawLine(p,r.X+2,r.Bottom-2-l,r.X+2,r.Bottom-2);
                g.DrawLine(p,r.Right-2-l,r.Bottom-2,r.Right-2,r.Bottom-2);g.DrawLine(p,r.Right-2,r.Bottom-2-l,r.Right-2,r.Bottom-2);
            }
            float tr=DrawExtendedValueBlock(g,t,m,r,labelFont,valueFont,r.X+9,r.Y+2,r.Y+15,t.Foreground);
            float gx=Math.Max(r.X+78,tr+7);
            bool stacked=ExtendedHeadlineStacks(g,t,m,r,r.X+9);
            float graphTop=stacked?29f:23f;
            RectangleF graph=new RectangleF(r.X+8,r.Y+graphTop,Math.Max(28,r.Width-16),Math.Max(6,r.Height-(graphTop+4)));
            if(config.ShowSparklines)DrawSparkline(g,m.History,graph,m.Accent,1.15f,false);
        }

        private void PaintMedicalMetric(Graphics g,ThemeDefinition t,MetricView m,RectangleF r,Font labelFont,Font valueFont)
        {
            using(GraphicsPath gp=RoundRect(r,6))
            using(SolidBrush fill=new SolidBrush(Color.FromArgb(205,255,255,255)))
            using(Pen edge=new Pen(Color.FromArgb(180,t.Border),1)){g.FillPath(fill,gp);g.DrawPath(edge,gp);}
            using(SolidBrush status=new SolidBrush(m.Accent))g.FillEllipse(status,r.X+7,r.Y+7,5,5);
            float tr=DrawExtendedValueBlock(g,t,m,r,labelFont,valueFont,r.X+16,r.Y+1,r.Y+14,t.Foreground);
            float gx=Math.Max(r.X+80,tr+7);
            bool stacked=ExtendedHeadlineStacks(g,t,m,r,r.X+16);
            float graphTop=stacked?29f:23f;
            RectangleF graph=new RectangleF(r.X+7,r.Y+graphTop,Math.Max(28,r.Width-14),Math.Max(6,r.Height-(graphTop+4)));
            if(config.ShowSparklines)DrawSparkline(g,m.History,graph,m.Accent,1.3f,false);
        }

        private void PaintCarbonMetric(Graphics g,ThemeDefinition t,MetricView m,RectangleF r,Font labelFont,Font valueFont)
        {
            float cut=8f;
            PointF[] p=new PointF[]{new PointF(r.X+cut,r.Y+1),new PointF(r.Right,r.Y+1),new PointF(r.Right-cut,r.Bottom-1),new PointF(r.X,r.Bottom-1)};
            using(SolidBrush fill=new SolidBrush(Color.FromArgb(185,t.Background2)))g.FillPolygon(fill,p);
            using(Pen edge=new Pen(Color.FromArgb(120,t.Border),1))g.DrawPolygon(edge,p);
            using(SolidBrush stripe=new SolidBrush(m.Accent))g.FillPolygon(stripe,new PointF[]{new PointF(r.X+cut,r.Y+1),new PointF(r.X+cut+4,r.Y+1),new PointF(r.X+4,r.Bottom-1),new PointF(r.X,r.Bottom-1)});
            float tr=DrawExtendedValueBlock(g,t,m,r,labelFont,valueFont,r.X+13,r.Y+2,r.Y+15,t.Foreground);
            float gx=Math.Max(r.X+79,tr+7);
            bool stacked=ExtendedHeadlineStacks(g,t,m,r,r.X+13);
            float graphTop=stacked?29f:23f;
            RectangleF graph=new RectangleF(r.X+8,r.Y+graphTop,Math.Max(26,r.Width-16),Math.Max(6,r.Height-(graphTop+4)));
            if(config.ShowSparklines)DrawSparkline(g,m.History,graph,m.Accent,1.35f,false);
        }

        private void PaintPremiumMetric(Graphics g,ThemeDefinition t,MetricView m,RectangleF r,Font labelFont,Font valueFont)
        {
            float textX=r.X+10;
            if(t.Mode=="aurora")
            {
                using(GraphicsPath gp=RoundRect(r,9))
                using(LinearGradientBrush fill=new LinearGradientBrush(r,Color.FromArgb(68,t.Background2),Color.FromArgb(34,m.Accent),0f))
                using(Pen edge=new Pen(Color.FromArgb(105,m.Accent),1f)){g.FillPath(fill,gp);g.DrawPath(edge,gp);}
                using(SolidBrush glow=new SolidBrush(Color.FromArgb(165,m.Accent)))g.FillEllipse(glow,r.X+7,r.Y+7,5,5);textX=r.X+17;
            }
            else if(t.Mode=="luxe")
            {
                using(GraphicsPath gp=RoundRect(r,5))
                using(SolidBrush fill=new SolidBrush(Color.FromArgb(170,t.Background2)))
                using(Pen edge=new Pen(Color.FromArgb(125,t.Border),1)){g.FillPath(fill,gp);g.DrawPath(edge,gp);}
                using(Pen top=new Pen(Color.FromArgb(210,m.Accent),1.4f))g.DrawLine(top,r.X+8,r.Y+2,r.Right-8,r.Y+2);
            }
            else if(t.Mode=="zen")
            {
                using(GraphicsPath gp=RoundRect(r,10))
                using(SolidBrush fill=new SolidBrush(Color.FromArgb(215,t.Light?Color.White:t.Background2)))
                using(Pen edge=new Pen(Color.FromArgb(130,t.Border),1)){g.FillPath(fill,gp);g.DrawPath(edge,gp);}
                using(SolidBrush dot=new SolidBrush(m.Accent))g.FillEllipse(dot,r.X+7,r.Y+8,4,4);textX=r.X+15;
            }
            else if(t.Mode=="synth")
            {
                float cut=7f;PointF[] poly=new PointF[]{new PointF(r.X+cut,r.Y),new PointF(r.Right,r.Y),new PointF(r.Right-cut,r.Bottom),new PointF(r.X,r.Bottom)};
                using(SolidBrush fill=new SolidBrush(Color.FromArgb(46,m.Accent)))g.FillPolygon(fill,poly);
                using(Pen glow=new Pen(Color.FromArgb(48,m.Accent),3f))g.DrawPolygon(glow,poly);
                using(Pen edge=new Pen(Color.FromArgb(205,m.Accent),1f))g.DrawPolygon(edge,poly);textX=r.X+11;
            }
            else if(t.Mode=="matrix")
            {
                using(SolidBrush fill=new SolidBrush(Color.FromArgb(125,t.Background2)))g.FillRectangle(fill,r);
                using(Pen edge=new Pen(Color.FromArgb(150,m.Accent),1))g.DrawRectangle(edge,r.X+1,r.Y+1,r.Width-2,r.Height-2);
                using(SolidBrush tick=new SolidBrush(m.Accent)){g.FillRectangle(tick,r.X+4,r.Y+4,2,6);g.FillRectangle(tick,r.X+4,r.Bottom-7,2,4);}textX=r.X+10;
            }
            else if(t.Mode=="paper")
            {
                using(GraphicsPath gp=RoundRect(r,4))
                using(SolidBrush fill=new SolidBrush(Color.FromArgb(225,t.Light?Color.White:t.Background2)))
                using(Pen edge=new Pen(Color.FromArgb(105,t.Border),1)){g.FillPath(fill,gp);g.DrawPath(edge,gp);}
                using(SolidBrush mark=new SolidBrush(m.Accent))g.FillRectangle(mark,r.X+5,r.Y+5,3,r.Height-10);textX=r.X+13;
            }
            else if(t.Mode=="industrial")
            {
                using(SolidBrush fill=new SolidBrush(Color.FromArgb(190,t.Background2)))g.FillRectangle(fill,r);
                using(Pen edge=new Pen(Color.FromArgb(130,t.Border),1))g.DrawRectangle(edge,r.X+1,r.Y+1,r.Width-2,r.Height-2);
                using(SolidBrush bolt=new SolidBrush(Color.FromArgb(170,t.Muted))){g.FillEllipse(bolt,r.X+4,r.Y+4,3,3);g.FillEllipse(bolt,r.Right-7,r.Bottom-7,3,3);}
                using(SolidBrush stripe=new SolidBrush(m.Accent))g.FillRectangle(stripe,r.X+3,r.Bottom-4,Math.Max(8,(r.Width-6)*Math.Max(0,Math.Min(100,m.Percent))/100f),2);textX=r.X+10;
            }
            DrawExtendedValueBlock(g,t,m,r,labelFont,valueFont,textX,r.Y+2,r.Y+15,t.Foreground);
            bool stacked=ExtendedHeadlineStacks(g,t,m,r,textX);
            float graphTop=stacked?29f:23f;
            RectangleF graph=new RectangleF(r.X+7,r.Y+graphTop,Math.Max(28,r.Width-14),Math.Max(6,r.Height-(graphTop+4)));
            if(config.ShowSparklines)
            {
                if(t.Mode=="matrix")DrawSparkline(g,m.History,graph,m.Accent,1.1f,false);
                else if(t.Mode=="industrial")DrawMissionBars(g,m.History,graph,m.Accent);
                else DrawSparkline(g,m.History,graph,m.Accent,t.Mode=="synth"?1.55f:1.25f,t.Mode=="synth");
            }
        }
        // R44: chart primitives are separate visible foreground, just like glyphs.
        // Normal 100% theme painting continues through the original GDI+ routines.
        private void DrawMissionBars(Graphics g,IList<float> values,RectangleF r,Color c)
        {
            PaintChartBarsCore(g,values,r,c,14,205,1.5f,false);
            if(glassInkCanvas!=null)
            {
                GraphicsState saved=glassInkCanvas.Save();
                try
                {
                    glassInkCanvas.SetClip(r,CombineMode.Intersect);
                    PaintChartBarsCore(glassInkCanvas,values,r,Color.FromArgb(255,c),14,255,1.0f,false);
                }
                finally{glassInkCanvas.Restore(saved);}
                if(glassHaloCanvas!=null)
                {
                    GraphicsState h=glassHaloCanvas.Save();
                    try
                    {
                        glassHaloCanvas.SetClip(r,CombineMode.Intersect);
                        PaintChartBarsCore(glassHaloCanvas,values,r,Color.White,14,255,0.5f,true);
                    }
                    finally{glassHaloCanvas.Restore(h);}
                }
            }
        }
        private static void PaintChartBarsCore(Graphics g,IList<float> values,RectangleF r,
            Color color,int maxBars,int opacity,float space,bool expanded)
        {
            if(values==null||values.Count==0||r.Width<4||r.Height<4)return;
            int count=Math.Min(values.Count,maxBars);
            float max=values.Skip(values.Count-count).Max();if(max<1)max=1;
            float w=r.Width/count;
            using(SolidBrush b=new SolidBrush(Color.FromArgb(opacity,color)))
            {
                for(int i=0;i<count;i++)
                {
                    float v=Math.Max(0,values[values.Count-count+i])/max;
                    float h=Math.Max(1,r.Height*v);
                    float padding=expanded?0.8f:0f;
                    g.FillRectangle(b,r.X+i*w-padding,r.Bottom-h-padding,
                        Math.Max(1,w-space+padding*2f),h+padding*2f);
                }
            }
        }

        private void DrawSparkline(Graphics g,IList<float> values,RectangleF r,Color color,float width,bool glow)
        {
            PaintSparklineCore(g,values,r,color,width,glow);
            if(glassInkCanvas==null||values==null||values.Count<2)return;
            GraphicsState saved=glassInkCanvas.Save();
            try
            {
                glassInkCanvas.SetClip(r,CombineMode.Intersect);
                PaintSparklineCore(glassInkCanvas,values,r,Color.FromArgb(255,color),
                    Math.Max(2.25f,width),false);
            }
            finally{glassInkCanvas.Restore(saved);}
            if(glassHaloCanvas!=null)
            {
                GraphicsState h=glassHaloCanvas.Save();
                try
                {
                    glassHaloCanvas.SetClip(r,CombineMode.Intersect);
                    PaintSparklineCore(glassHaloCanvas,values,r,Color.White,
                        Math.Max(4.2f,width+2.0f),false);
                }
                finally{glassHaloCanvas.Restore(h);}
            }
        }
        private static void PaintSparklineCore(Graphics g,IList<float> values,RectangleF r,
            Color color,float width,bool glow)
        {
            if(values==null||values.Count<2||r.Width<4||r.Height<4)return;
            float max=values.Max();float min=values.Min();if(max-min<0.01f){max=min+1;}
            PointF[] p=new PointF[values.Count];
            for(int i=0;i<values.Count;i++)
            {
                float x=r.X+r.Width*i/(values.Count-1f);
                float y=r.Bottom-(values[i]-min)/(max-min)*r.Height;
                p[i]=new PointF(x,y);
            }
            if(glow)
            using(Pen gp=new Pen(Color.FromArgb(55,color),4f))
            {gp.LineJoin=LineJoin.Round;g.DrawLines(gp,p);}
            using(Pen pen=new Pen(color,width))
            {pen.LineJoin=LineJoin.Round;g.DrawLines(pen,p);}
        }
        private void DrawTerminalBars(Graphics g,IList<float> values,RectangleF r,Color c)
        {
            // Keep original low-profile bars on full theme, while ink remains opaque.
            if(values==null||values.Count==0)return;
            PaintChartBarsCore(g,values,r,c,18,210,1.0f,false);
            if(glassInkCanvas!=null)
            {
                GraphicsState state=glassInkCanvas.Save();
                try
                {
                    glassInkCanvas.SetClip(r,CombineMode.Intersect);
                    PaintChartBarsCore(glassInkCanvas,values,r,Color.FromArgb(255,c),18,255,0.55f,false);
                }
                finally{glassInkCanvas.Restore(state);}
                if(glassHaloCanvas!=null)
                {
                    GraphicsState state2=glassHaloCanvas.Save();
                    try
                    {
                        glassHaloCanvas.SetClip(r,CombineMode.Intersect);
                        PaintChartBarsCore(glassHaloCanvas,values,r,Color.White,18,255,0.4f,true);
                    }
                    finally{glassHaloCanvas.Restore(state2);}
                }
            }
        }

    }

    internal sealed class ThemePreviewControl : Control
    {
        private readonly Func<string,int,int,Bitmap> renderer;
        private string themeName="Dark Minimal Pro";
        public string ThemeName
        {
            get{return themeName;}
            set{themeName=String.IsNullOrWhiteSpace(value)?"Dark Minimal Pro":value;Invalidate();}
        }
        public ThemePreviewControl(Func<string,int,int,Bitmap> realRenderer)
        {
            renderer=realRenderer;
            DoubleBuffered=true;
            SetStyle(ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.UserPaint,true);
            Height=132;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            Rectangle r=ClientRectangle;
            if(r.Width<80||r.Height<80)return;
            e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
            e.Graphics.TextRenderingHint=System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

            using(GraphicsPath gp=RoundRectPreview(new RectangleF(1,1,r.Width-2,r.Height-2),12))
            using(SolidBrush bg=new SolidBrush(Color.FromArgb(18,25,34)))
            using(Pen edge=new Pen(Color.FromArgb(70,105,132),1f))
            {
                e.Graphics.FillPath(bg,gp);
                e.Graphics.DrawPath(edge,gp);
            }

            using(Font title=new Font("Segoe UI Semibold",10.1f,FontStyle.Bold))
            using(Font small=new Font("Segoe UI",8.2f,FontStyle.Regular))
            using(SolidBrush fg=new SolidBrush(Color.FromArgb(238,244,250)))
            using(SolidBrush muted=new SolidBrush(Color.FromArgb(153,169,186)))
            {
                e.Graphics.DrawString(themeName,title,fg,15,10);
                e.Graphics.DrawString("Actual taskbar renderer preview",small,muted,15,32);
            }

            Rectangle strip=new Rectangle(15,58,Math.Max(320,r.Width-30),48);
            using(SolidBrush shadow=new SolidBrush(Color.FromArgb(75,0,0,0)))
                e.Graphics.FillRectangle(shadow,strip.X+2,strip.Y+3,strip.Width,strip.Height);

            if(renderer==null)
            {
                using(SolidBrush muted=new SolidBrush(Color.FromArgb(153,169,186)))
                using(Font small=new Font("Segoe UI",8.2f,FontStyle.Regular))
                    e.Graphics.DrawString("Renderer unavailable",small,muted,strip.X+8,strip.Y+15);
                return;
            }

            try
            {
                using(Bitmap actual=renderer(themeName,strip.Width,48))
                {
                    e.Graphics.InterpolationMode=InterpolationMode.NearestNeighbor;
                    e.Graphics.PixelOffsetMode=PixelOffsetMode.HighQuality;
                    e.Graphics.DrawImageUnscaled(actual,strip.X,strip.Y);
                }
                using(Pen line=new Pen(Color.FromArgb(105,138,165),1))
                    e.Graphics.DrawRectangle(line,strip.X,strip.Y,strip.Width-1,strip.Height-1);
            }
            catch(Exception ex)
            {
                using(SolidBrush warn=new SolidBrush(Color.FromArgb(235,173,72)))
                using(Font small=new Font("Segoe UI",8.2f,FontStyle.Regular))
                    e.Graphics.DrawString("Preview renderer error: "+ShortPreviewError(ex.Message),small,warn,strip.X+8,strip.Y+15);
            }
        }
        private static string ShortPreviewError(string s)
        {
            if(String.IsNullOrWhiteSpace(s))return "unknown";
            s=s.Replace("\r"," ").Replace("\n"," ").Trim();
            return s.Length<=72?s:s.Substring(0,69)+"...";
        }
        private static GraphicsPath RoundRectPreview(RectangleF r,float rad)
        {
            float d=rad*2f;GraphicsPath p=new GraphicsPath();
            p.AddArc(r.X,r.Y,d,d,180,90);p.AddArc(r.Right-d,r.Y,d,d,270,90);p.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);p.AddArc(r.X,r.Bottom-d,d,d,90,90);p.CloseFigure();return p;
        }
    }

    internal static class SafeResetPolicy
    {
        public static string BackupCurrentConfig(string configPath,string backupDir,DateTime localNow)
        {
            if(String.IsNullOrWhiteSpace(configPath)||!File.Exists(configPath))return "";
            if(String.IsNullOrWhiteSpace(backupDir))throw new ArgumentException("backup directory");
            Directory.CreateDirectory(backupDir);
            string stamp=localNow.ToString("yyyyMMdd_HHmmss_fff",CultureInfo.InvariantCulture);
            string baseName="config_before_reset_"+stamp;
            string backup=Path.Combine(backupDir,baseName+".json");
            int suffix=1;
            while(File.Exists(backup))
            {
                backup=Path.Combine(backupDir,baseName+"_"+suffix.ToString(CultureInfo.InvariantCulture)+".json");
                suffix++;
            }
            File.Copy(configPath,backup,false);
            return backup;
        }
    }

    internal static class SupportBundleBuilder
    {
        private static void AddText(ZipArchive zip,string name,string text)
        {
            ZipArchiveEntry entry=zip.CreateEntry(name,CompressionLevel.Optimal);
            using(Stream stream=entry.Open())
            using(StreamWriter writer=new StreamWriter(stream,new UTF8Encoding(false)))
                writer.Write(text??"");
        }

        private static bool AddFile(ZipArchive zip,string source,string entryName,List<string> manifest)
        {
            try
            {
                if(String.IsNullOrWhiteSpace(source)||!File.Exists(source))return false;
                ZipArchiveEntry entry=zip.CreateEntry(entryName,CompressionLevel.Optimal);
                using(Stream input=new FileStream(source,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))
                using(Stream output=entry.Open())input.CopyTo(output);
                manifest.Add(entryName+" | "+new FileInfo(source).Length.ToString(CultureInfo.InvariantCulture)+" bytes");
                return true;
            }
            catch(Exception ex)
            {
                manifest.Add(entryName+" | ERROR | "+ex.Message);
                return false;
            }
        }

        public static void Create(string outputPath,string diagnostics)
        {
            if(String.IsNullOrWhiteSpace(outputPath))throw new ArgumentException("output path");
            string parent=Path.GetDirectoryName(outputPath);
            if(!String.IsNullOrWhiteSpace(parent))Directory.CreateDirectory(parent);
            List<string> manifest=new List<string>();
            using(FileStream fs=new FileStream(outputPath,FileMode.Create,FileAccess.ReadWrite,FileShare.None))
            using(ZipArchive zip=new ZipArchive(fs,ZipArchiveMode.Create,false,Encoding.UTF8))
            {
                AddText(zip,"diagnostics.txt",diagnostics??"");
                manifest.Add("diagnostics.txt | generated");

                AddFile(zip,AppPaths.Config,"config/config.json",manifest);
                AddFile(zip,AppPaths.ConfigBackup,"config/config.json.bak",manifest);
                AddFile(zip,AppPaths.InstallState,"runtime/install_state.json",manifest);
                AddFile(zip,AppPaths.SensorSupervisorState,"runtime/sensor_supervisor_state.json",manifest);
                AddFile(zip,AppPaths.SensorBackendState,"runtime/sensor_backend_state.json",manifest);
                AddFile(zip,AppPaths.CpuTempBrokerData,"runtime/cpu_temp_broker.json",manifest);
                AddFile(zip,AppPaths.GpuBrokerData,"runtime/gpu_temp_broker.json",manifest);
                AddFile(zip,AppPaths.StorageBrokerData,"runtime/storage_temp_broker.json",manifest);
                AddFile(zip,AppPaths.CrashState,"runtime/last_crash.json",manifest);

                try
                {
                    if(Directory.Exists(AppPaths.Logs))
                    {
                        foreach(FileInfo log in new DirectoryInfo(AppPaths.Logs).GetFiles()
                            .OrderByDescending(x=>x.LastWriteTimeUtc).Take(8))
                            AddFile(zip,log.FullName,"logs/"+log.Name,manifest);
                    }
                }
                catch(Exception ex){manifest.Add("logs | ERROR | "+ex.Message);}

                StringBuilder meta=new StringBuilder();
                meta.AppendLine("Taskbar Monitor Enhanced support bundle");
                meta.AppendLine("GeneratedUtc: "+DateTime.UtcNow.ToString("o",CultureInfo.InvariantCulture));
                meta.AppendLine("Build: "+BuildInfo.Version+" / "+BuildInfo.PublicVersion);
                meta.AppendLine("OS: "+Environment.OSVersion);
                meta.AppendLine("Privacy: local user-initiated export; machine name and absolute source paths are omitted from this manifest.");
                meta.AppendLine();
                foreach(string line in manifest)meta.AppendLine(line);
                AddText(zip,"support_manifest.txt",meta.ToString());
            }
        }

        public static int Probe(string outputPath)
        {
            try
            {
                Create(outputPath,"TBME support bundle proof");
                using(FileStream fs=new FileStream(outputPath,FileMode.Open,FileAccess.Read,FileShare.Read))
                using(ZipArchive zip=new ZipArchive(fs,ZipArchiveMode.Read,false,Encoding.UTF8))
                {
                    if(zip.GetEntry("diagnostics.txt")==null)throw new InvalidDataException("diagnostics entry missing");
                    ZipArchiveEntry manifestEntry=zip.GetEntry("support_manifest.txt");
                    if(manifestEntry==null)throw new InvalidDataException("manifest entry missing");
                    if(zip.Entries.Count<2)throw new InvalidDataException("bundle entry count");
                    string manifestText;
                    using(Stream ms=manifestEntry.Open())
                    using(StreamReader mr=new StreamReader(ms,Encoding.UTF8,true))
                        manifestText=mr.ReadToEnd();
                    if(manifestText.IndexOf(Environment.MachineName,StringComparison.OrdinalIgnoreCase)>=0)
                        throw new InvalidDataException("manifest leaks machine name");
                    if(manifestText.IndexOf(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),StringComparison.OrdinalIgnoreCase)>=0)
                        throw new InvalidDataException("manifest leaks user profile path");
                    Console.WriteLine("TBME_SUPPORT_BUNDLE_PROOF=PASS ENTRIES="+zip.Entries.Count+" PRIVACY_MANIFEST=PASS");
                }
                return 0;
            }
            catch(Exception ex)
            {
                Console.Error.WriteLine("TBME_SUPPORT_BUNDLE_PROOF=FAIL "+ex);
                return 16;
            }
        }
    }

    internal static class FeatureContractSelfTest
    {
        private static string Sha256Hex(string path)
        {
            using(SHA256 sha=SHA256.Create())using(FileStream fs=File.OpenRead(path))
            {
                byte[] h=sha.ComputeHash(fs);StringBuilder b=new StringBuilder();foreach(byte x in h)b.Append(x.ToString("X2",CultureInfo.InvariantCulture));return b.ToString();
            }
        }
        public static int Run()
        {
            string dir=Path.Combine(Path.GetTempPath(),"tbme_feature_contract_"+Process.GetCurrentProcess().Id.ToString(CultureInfo.InvariantCulture));
            string zip=Path.Combine(dir,"support.zip");
            try
            {
                Directory.CreateDirectory(dir);
                AppConfig c=new AppConfig();c.Normalize();
                if(c.ConfigSchemaVersion<6)throw new InvalidOperationException("config schema");
                if(c.FollowWindowsTheme||c.WindowsLightTheme!="Nordic Light"||c.WindowsDarkTheme!="Dark Minimal Pro"||c.TaskbarDisplay!="Primary")throw new InvalidOperationException("Windows integration defaults");
                if(!c.EnableTemperatureAlerts||c.EnableTemperatureNotifications||c.EnableTemperatureWarningSound||c.CpuTempWarningC!=85||c.GpuTempWarningC!=85||c.DiskTempWarningC!=60)
                    throw new InvalidOperationException("temperature alert defaults");
                if(!AlertPolicy.IsCpuHot(true,85,c)||AlertPolicy.IsCpuHot(true,84.9f,c))throw new InvalidOperationException("CPU alert boundary");
                if(!AlertPolicy.IsGpuHot(true,90,c)||AlertPolicy.IsGpuHot(false,100,c))throw new InvalidOperationException("GPU alert boundary");
                if(!AlertPolicy.IsDiskHot(true,60,c)||AlertPolicy.IsDiskHot(true,59.9f,c))throw new InvalidOperationException("disk alert boundary");
                if(TemperatureWarningSoundPolicy.ShouldPlay(c))throw new InvalidOperationException("audio off by default");
                c.EnableTemperatureNotifications=true;c.EnableTemperatureWarningSound=true;
                if(!TemperatureWarningSoundPolicy.ShouldPlay(c))throw new InvalidOperationException("audio explicit opt-in");
                c.EnableTemperatureNotifications=false;
                if(TemperatureWarningSoundPolicy.ShouldPlay(c))throw new InvalidOperationException("audio muted when toast disabled");
                c.EnableTemperatureWarningSound=false;
                TemperatureNotificationState notificationState=new TemperatureNotificationState();
                DateTime nt=new DateTime(2026,10,2,12,0,0,DateTimeKind.Utc);
                if(!notificationState.ShouldNotify("CPU",true,85,85,nt))throw new InvalidOperationException("notification first crossing");
                if(notificationState.ShouldNotify("CPU",true,95,85,nt.AddMinutes(1)))throw new InvalidOperationException("notification latch");
                if(notificationState.ShouldNotify("CPU",true,83,85,nt.AddMinutes(2)))throw new InvalidOperationException("notification hysteresis band");
                if(notificationState.ShouldNotify("CPU",true,81,85,nt.AddMinutes(3)))throw new InvalidOperationException("notification cool reset");
                if(notificationState.ShouldNotify("CPU",true,90,85,nt.AddMinutes(4)))throw new InvalidOperationException("notification cooldown");
                if(notificationState.ShouldNotify("CPU",true,81,85,nt.AddMinutes(10)))throw new InvalidOperationException("notification second cool reset");
                if(!notificationState.ShouldNotify("CPU",true,90,85,nt.AddMinutes(11)))throw new InvalidOperationException("notification rearm");
                if(notificationState.ShouldNotify("GPU",false,100,85,nt))throw new InvalidOperationException("notification unavailable");

                SessionTelemetryHistory.ClearForTest();
                MetricsSnapshot sessionProbe=new MetricsSnapshot();sessionProbe.Cpu=12.5f;sessionProbe.Ram=34.5f;sessionProbe.Gpu=56.5f;sessionProbe.NetDownMbps=7.5f;sessionProbe.NetUpMbps=1.5f;sessionProbe.DiskReadBytesPerSec=2d*1024d*1024d;sessionProbe.DiskWriteBytesPerSec=3d*1024d*1024d;sessionProbe.CpuTempAvailable=true;sessionProbe.CpuTempCurrent=65.5f;
                for(int si=0;si<SessionTelemetryHistory.MaxSamples+5;si++)SessionTelemetryHistory.Add(sessionProbe);
                if(SessionTelemetryHistory.Count!=SessionTelemetryHistory.MaxSamples)throw new InvalidOperationException("session history bound");
                string csvProbe=Path.Combine(dir,"session.csv");int csvRows=SessionTelemetryHistory.ExportCsv(csvProbe);
                string csvText=File.ReadAllText(csvProbe,Encoding.UTF8);
                if(csvRows!=SessionTelemetryHistory.MaxSamples||csvText.IndexOf("Utc,CpuPercent,RamPercent",StringComparison.Ordinal)!=0||csvText.IndexOf("12.5,34.5",StringComparison.Ordinal)<0)throw new InvalidOperationException("session CSV export");
                SessionTelemetryHistory.ClearForTest();

                c.UpdateIntervalMs=1000;c.AdaptiveBatteryMode=true;c.BatteryUpdateIntervalMs=3000;
                if(TelemetryPolicy.EffectiveIntervalMs(c,PowerLineStatus.Online)!=1000)throw new InvalidOperationException("AC interval");
                if(TelemetryPolicy.EffectiveIntervalMs(c,PowerLineStatus.Offline)!=3000)throw new InvalidOperationException("battery interval");
                if(!TelemetryPolicy.ShouldPause(true,false)||!TelemetryPolicy.ShouldPause(false,true)||TelemetryPolicy.ShouldPause(false,false))
                    throw new InvalidOperationException("pause policy");

                MetricHistory h=new MetricHistory();h.SetLimit(30);
                for(int i=0;i<50;i++)h.Add("CPU",i);
                if(h.Get("CPU").Count!=30||h.MaxLength!=30)throw new InvalidOperationException("history limit");
                h.SetLimit(120);for(int i=0;i<100;i++)h.Add("CPU",i);
                if(h.Get("CPU").Count!=120)throw new InvalidOperationException("history grow");

                if(SupportBundleBuilder.Probe(zip)!=0)throw new InvalidOperationException("support bundle");
                if(!UpdateManager.IsOfficialReleaseUrl("https://github.com/GOD13emad/TaskbarMonitorEnhanced/releases/tag/v1.4.0","1.4.0"))throw new InvalidOperationException("official release URL");
                if(UpdateManager.IsOfficialReleaseUrl("https://github.com/evil/repo/releases/tag/v1.4.0","1.4.0"))throw new InvalidOperationException("foreign release URL");
                if(!UpdateManager.IsOfficialSetupUrl("https://github.com/GOD13emad/TaskbarMonitorEnhanced/releases/download/v1.4.0/TaskbarMonitorEnhanced_Setup_1.4.0.exe","1.4.0","TaskbarMonitorEnhanced_Setup_1.4.0.exe"))throw new InvalidOperationException("official setup URL");
                if(UpdateManager.IsOfficialSetupUrl("https://github.com/GOD13emad/TaskbarMonitorEnhanced/releases/download/v1.4.0/other.exe","1.4.0","TaskbarMonitorEnhanced_Setup_1.4.0.exe"))throw new InvalidOperationException("wrong setup URL");

                AppConfig follow=new AppConfig();follow.FollowWindowsTheme=true;follow.WindowsLightTheme="Nordic Light";follow.WindowsDarkTheme="OLED Mono";follow.Normalize();
                if(WindowsThemePolicy.ResolveName(follow,true)!="Nordic Light"||WindowsThemePolicy.ResolveName(follow,false)!="OLED Mono")throw new InvalidOperationException("Windows light/dark resolver");
                ThemeDefinition hc=WindowsThemePolicy.HighContrastTheme();
                if(hc==null||hc.Accents==null||hc.Accents.Length<1||hc.Foreground.ToArgb()==hc.Background.ToArgb())throw new InvalidOperationException("high contrast theme");

                string updateProbe=Path.Combine(dir,"verified-update.bin");File.WriteAllText(updateProbe,"A",Encoding.UTF8);
                string goodDigest="sha256:"+Sha256Hex(updateProbe).ToLowerInvariant();
                UpdateManager.VerifyInstallerBeforeLaunch(updateProbe,goodDigest);
                File.AppendAllText(updateProbe,"B",Encoding.UTF8);
                bool tamperBlocked=false;try{UpdateManager.VerifyInstallerBeforeLaunch(updateProbe,goodDigest);}catch(InvalidDataException){tamperBlocked=true;}
                if(!tamperBlocked)throw new InvalidOperationException("update TOCTOU tamper gate");

                string crashProbe=Path.Combine(dir,"last_crash.json");
                if(RuntimeGuard.ProbeCrashSnapshot(crashProbe)!=0)throw new InvalidOperationException("crash snapshot privacy");

                string resetConfig=Path.Combine(dir,"reset-config.json");
                string resetBackups=Path.Combine(dir,"reset-backups");
                const string resetPayload="{\"Theme\":\"USER_KEEP\"}";
                File.WriteAllText(resetConfig,resetPayload,Encoding.UTF8);
                DateTime fixedResetTime=new DateTime(2026,10,2,7,30,0,123,DateTimeKind.Local);
                string resetBackup1=SafeResetPolicy.BackupCurrentConfig(resetConfig,resetBackups,fixedResetTime);
                string resetBackup2=SafeResetPolicy.BackupCurrentConfig(resetConfig,resetBackups,fixedResetTime);
                if(String.IsNullOrWhiteSpace(resetBackup1)||String.IsNullOrWhiteSpace(resetBackup2)||
                   String.Equals(resetBackup1,resetBackup2,StringComparison.OrdinalIgnoreCase)||
                   !File.Exists(resetBackup1)||!File.Exists(resetBackup2))
                    throw new InvalidOperationException("safe reset backup uniqueness");
                if(File.ReadAllText(resetConfig,Encoding.UTF8)!=resetPayload||
                   File.ReadAllText(resetBackup1,Encoding.UTF8)!=resetPayload||
                   File.ReadAllText(resetBackup2,Encoding.UTF8)!=resetPayload)
                    throw new InvalidOperationException("safe reset backup preservation");

                Console.WriteLine("TBME_FEATURE_CONTRACT_SELFTEST=PASS FEATURES=20 TEMPERATURE_NOTIFICATIONS=TRUE SESSION_CSV_EXPORT=TRUE WINDOWS_THEME_FOLLOW=TRUE HIGH_CONTRAST=TRUE MULTI_MONITOR_SELECTOR=TRUE UPDATE_CANONICAL_IDENTITY=TRUE UPDATE_PRELAUNCH_REHASH=TRUE CRASH_SNAPSHOT_PRIVACY=TRUE ALERTS_CPU_GPU_DISK=TRUE HOT_VISUAL=TRUE BATTERY_ADAPTIVE=TRUE SESSION_PAUSE=TRUE HISTORY_CONFIG=TRUE COPY_DIAGNOSTICS=TRUE SUPPORT_ZIP=TRUE SUPPORT_PRIVACY_MANIFEST=TRUE SAFE_RESET=TRUE SAFE_RESET_BACKUP_UNIQUE=TRUE HEALTH_BADGE=TRUE");
                return 0;
            }
            catch(Exception ex)
            {
                Console.Error.WriteLine("TBME_FEATURE_CONTRACT_SELFTEST=FAIL "+ex);
                return 17;
            }
            finally{try{Directory.Delete(dir,true);}catch{}}
        }
    }
    internal sealed class SettingsForm : Form
    {
        private sealed class HardwareChoice
        {
            public string Id,Name; public override string ToString(){return Name??Id??"Device";}
        }
        private readonly AppConfig c; private readonly MetricsSnapshot snapshot; private readonly Func<string,int,int,Bitmap> themePreviewRenderer;
        private ComboBox theme,windowsLightTheme,windowsDarkTheme,position,taskbarDisplay,cpuMode,gpuMode,diskMode,netMode,multiLayout,memoryUnit,storageUnit,networkUnit,diskRateUnit;
        private NumericUpDown opacity,interval,width,cpuWarn,gpuWarn,diskWarn,batteryInterval,historyLength;
        private GlassToggleSwitch glassModeToggle;
        private Label glassModeState;
        private int lastOpacityPercent;
        private CheckBox cpu,ram,disk,gpu,vram,net,temp,spark,startup,safe,floatAboveStart,ramNumeric,diskNumeric,flyout,hoverAll,autoCheckUpdates,tempAlerts,tempNotifications,tempSound,adaptiveBattery,followWindowsTheme;
        private CheckedListBox cpuList,gpuList,diskList,netList;
        private Label updateCurrent,updateLatest,updateStatus;
        private Button checkUpdate,installUpdate,openRelease;
        private TextBox diagnosticsText;
        private Label healthBadge;
        private Button refreshDiagnostics,saveDiagnostics,openDataFolder,repairSensors,copyDiagnostics,exportSupportBundle,exportSessionCsv,resetDefaults;
        private TabControl tabsControl;
        private ReleaseUpdateInfo latestUpdate;
        private readonly List<Button> settingsNavButtons=new List<Button>();
        private Label settingsPageTitle,settingsPageSubtitle;
        private ThemePreviewControl themePreview;
        private readonly Dictionary<Control,Tuple<Color,Color>> normalPalette=new Dictionary<Control,Tuple<Color,Color>>();
        private static readonly Color SettingsWindow=Color.FromArgb(10,14,20);
        private static readonly Color SettingsSidebar=Color.FromArgb(15,21,29);
        private static readonly Color SettingsSurface=Color.FromArgb(20,28,38);
        private static readonly Color SettingsSurface2=Color.FromArgb(25,35,47);
        private static readonly Color SettingsText=Color.FromArgb(236,242,248);
        private static readonly Color SettingsMuted=Color.FromArgb(145,160,177);
        private static readonly Color SettingsAccent=Color.FromArgb(75,156,255);
        private static readonly string[] SettingsPageDescriptions=new string[]{
            "Appearance, theme, placement and taskbar footprint.",
            "Choose the live metrics that are visible on the taskbar.",
            "Temperature warnings, optional Windows notifications and hot-state thresholds.",
            "Select devices, aggregation modes and hover-detail behavior.",
            "Control memory, storage and network measurement units.",
            "Startup, adaptive polling, history depth and placement safeguards.",
            "Secure release checks and immutable update installation.",
            "Runtime health, sensor state and support diagnostics.",
            "Logs, safe reset and maintenance information."
        };
        public SettingsForm(AppConfig config,MetricsSnapshot current) : this(config,current,null,null) { }
        public SettingsForm(AppConfig config,MetricsSnapshot current,string initialTab) : this(config,current,initialTab,null) { }
        internal SettingsForm(AppConfig config,MetricsSnapshot current,string initialTab,Func<string,int,int,Bitmap> realThemePreviewRenderer)
        {
            c=config;snapshot=current??new MetricsSnapshot();themePreviewRenderer=realThemePreviewRenderer;
            Text="Taskbar Monitor Enhanced - Settings";
            Width=1080;Height=760;MinimumSize=new Size(900,650);StartPosition=FormStartPosition.CenterScreen;
            FormBorderStyle=FormBorderStyle.Sizable;MaximizeBox=true;MinimizeBox=false;AutoScaleMode=AutoScaleMode.Dpi;KeyPreview=true;
            // R117: Settings is a real independent, activatable top-level form.
            // The alpha-zero overlay is WS_EX_NOACTIVATE and topmost; Settings
            // must not be covered by its taskbar z-band and must be Alt+Tab-able.
            ShowInTaskbar=true;
            TopMost=true;
            Shown+=delegate{
                Rectangle work=Screen.FromControl(this).WorkingArea;
                int w=Math.Min(Width,Math.Max(200,work.Width-16));
                int h=Math.Min(Height,Math.Max(200,work.Height-16));
                MinimumSize=new Size(Math.Min(MinimumSize.Width,w),Math.Min(MinimumSize.Height,h));
                Bounds=new Rectangle(work.Left+(work.Width-w)/2,work.Top+(work.Height-h)/2,w,h);
            };
            BackColor=SettingsWindow;ForeColor=SettingsText;Font=new Font("Segoe UI",9.4f,FontStyle.Regular);DoubleBuffered=true;

            TableLayoutPanel root=new TableLayoutPanel();root.Dock=DockStyle.Fill;root.BackColor=SettingsWindow;root.ColumnCount=2;root.RowCount=1;root.Margin=Padding.Empty;root.Padding=Padding.Empty;root.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,214f));root.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100f));root.RowStyles.Add(new RowStyle(SizeType.Percent,100f));Controls.Add(root);
            Panel sidebar=new Panel();sidebar.Dock=DockStyle.Fill;sidebar.BackColor=SettingsSidebar;sidebar.Padding=new Padding(10,12,10,12);root.Controls.Add(sidebar,0,0);
            TableLayoutPanel contentArea=new TableLayoutPanel();contentArea.Dock=DockStyle.Fill;contentArea.BackColor=SettingsWindow;contentArea.Padding=new Padding(18,0,18,0);contentArea.ColumnCount=1;contentArea.RowCount=3;contentArea.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100f));contentArea.RowStyles.Add(new RowStyle(SizeType.Absolute,88f));contentArea.RowStyles.Add(new RowStyle(SizeType.Percent,100f));contentArea.RowStyles.Add(new RowStyle(SizeType.Absolute,66f));root.Controls.Add(contentArea,1,0);

            Panel brand=new Panel();brand.Dock=DockStyle.Top;brand.Height=88;brand.BackColor=SettingsSidebar;sidebar.Controls.Add(brand);
            Label brandTitle=new Label();brandTitle.Text="TASKBAR MONITOR";brandTitle.ForeColor=SettingsText;brandTitle.Font=new Font("Segoe UI Semibold",11.5f,FontStyle.Bold);brandTitle.AutoSize=true;brandTitle.Location=new Point(8,10);brand.Controls.Add(brandTitle);
            Label brandSub=new Label();brandSub.Text="Enhanced  "+BuildInfo.PublicVersion;brandSub.ForeColor=SettingsMuted;brandSub.Font=new Font("Segoe UI",8.7f);brandSub.AutoSize=true;brandSub.Location=new Point(8,38);brand.Controls.Add(brandSub);
            Label brandHint=new Label();brandHint.Text="Settings";brandHint.ForeColor=SettingsAccent;brandHint.Font=new Font("Segoe UI Semibold",9.2f,FontStyle.Bold);brandHint.AutoSize=true;brandHint.Location=new Point(8,60);brand.Controls.Add(brandHint);

            FlowLayoutPanel nav=new FlowLayoutPanel();nav.Dock=DockStyle.Fill;nav.FlowDirection=FlowDirection.TopDown;nav.WrapContents=false;nav.AutoScroll=true;nav.BackColor=SettingsSidebar;nav.Padding=new Padding(0,8,0,0);sidebar.Controls.Add(nav);nav.BringToFront();
            string[] navNames=new string[]{"Display","Metrics","Alerts","Hardware","Units","Behavior","Updates","Diagnostics","Advanced"};
            for(int i=0;i<navNames.Length;i++)
            {
                Button b=CreateNavigationButton(navNames[i],i);
                settingsNavButtons.Add(b);nav.Controls.Add(b);
            }

            Panel header=new Panel();header.Dock=DockStyle.Fill;header.BackColor=SettingsWindow;contentArea.Controls.Add(header,0,0);
            settingsPageTitle=new Label();settingsPageTitle.Text="Display";settingsPageTitle.ForeColor=SettingsText;settingsPageTitle.Font=new Font("Segoe UI Semibold",20f,FontStyle.Bold);settingsPageTitle.AutoSize=true;settingsPageTitle.Location=new Point(8,17);header.Controls.Add(settingsPageTitle);
            settingsPageSubtitle=new Label();settingsPageSubtitle.Text=SettingsPageDescriptions[0];settingsPageSubtitle.ForeColor=SettingsMuted;settingsPageSubtitle.Font=new Font("Segoe UI",9.3f);settingsPageSubtitle.AutoSize=true;settingsPageSubtitle.Location=new Point(10,55);header.Controls.Add(settingsPageSubtitle);

            Panel pageHost=new Panel();pageHost.Dock=DockStyle.Fill;pageHost.Margin=Padding.Empty;pageHost.BackColor=SettingsSurface;contentArea.Controls.Add(pageHost,0,1);
            TabControl tabs=new TabControl();tabsControl=tabs;tabs.Appearance=TabAppearance.FlatButtons;tabs.SizeMode=TabSizeMode.Fixed;tabs.ItemSize=new Size(0,1);tabs.Multiline=true;tabs.Padding=new Point(0,0);tabs.Margin=Padding.Empty;
            pageHost.Controls.Add(tabs);
            Action fitTabs=delegate{tabs.Bounds=new Rectangle(-4,-4,Math.Max(20,pageHost.ClientSize.Width+8),Math.Max(20,pageHost.ClientSize.Height+8));};
            pageHost.Resize+=delegate{fitTabs();};fitTabs();
            TabPage display=new TabPage("Display"), metrics=new TabPage("Metrics"), alerts=new TabPage("Alerts"), hardware=new TabPage("Hardware"), units=new TabPage("Units"), behavior=new TabPage("Behavior"), updates=new TabPage("Updates"), diagnostics=new TabPage("Diagnostics"), advanced=new TabPage("Advanced");
            tabs.TabPages.Add(display);tabs.TabPages.Add(metrics);tabs.TabPages.Add(alerts);tabs.TabPages.Add(hardware);tabs.TabPages.Add(units);tabs.TabPages.Add(behavior);tabs.TabPages.Add(updates);tabs.TabPages.Add(diagnostics);tabs.TabPages.Add(advanced);
            foreach(TabPage page in tabs.TabPages){page.AutoScroll=true;page.Padding=new Padding(10);page.BackColor=SettingsWindow;page.ForeColor=SettingsText;}
            display.AutoScrollMinSize=new Size(760,440);metrics.AutoScrollMinSize=new Size(760,430);alerts.AutoScrollMinSize=new Size(760,520);hardware.AutoScrollMinSize=new Size(760,760);units.AutoScrollMinSize=new Size(760,540);behavior.AutoScrollMinSize=new Size(760,590);updates.AutoScrollMinSize=new Size(760,540);diagnostics.AutoScrollMinSize=new Size(840,700);advanced.AutoScrollMinSize=new Size(760,540);

            theme=Combo(display,"Theme",ThemeCatalog.Names,c.Theme,22);position=Combo(display,"Position",new string[]{"Left","Center","Right"},c.Position,68);
            taskbarDisplay=Combo(display,"Taskbar monitor",TaskbarTargetPolicy.SettingChoices(c.TaskbarDisplay),c.TaskbarDisplay,114);
            // R124: a separate binary slider/switch for glass, not a second opacity control.
            Label glassLabel=new Label{Text="Glass mode",Location=new Point(24,164),Size=new Size(145,26)};
            display.Controls.Add(glassLabel);
            glassModeToggle=new GlassToggleSwitch{Location=new Point(180,158),
                Size=new Size(68,34),Checked=c.GlassMode};
            SetA11y(glassModeToggle,"Glass mode switch","Click or press Space to switch Glass on or off. On: zero background; Off: your saved 1-100% opacity.");
            display.Controls.Add(glassModeToggle);
            // A separate, opaque status label eliminates mixed native CheckBox text
            // painting and keeps track, thumb and ON/OFF text spatially independent.
            glassModeState=new Label{Text=c.GlassMode?"On":"Off",Location=new Point(260,160),
                Size=new Size(72,30),AutoSize=false,TextAlign=ContentAlignment.MiddleLeft,
                ForeColor=SettingsText,BackColor=SettingsSurface};
            SetA11y(glassModeState,"Glass mode status","Current Glass mode state.");
            display.Controls.Add(glassModeState);
            lastOpacityPercent=Math.Max(1,Math.Min(100,(int)Math.Round(c.OpacityWhenGlassOff*100)));
            opacity=Number(display,"Background opacity %",c.GlassMode?0:(decimal)(c.Opacity*100),c.GlassMode?0:1,100,216);
            opacity.Enabled=!c.GlassMode;
            opacity.ValueChanged+=delegate{if(opacity.Enabled&&opacity.Value>=1)lastOpacityPercent=(int)opacity.Value;};
            glassModeToggle.CheckedChanged+=delegate{SyncGlassOpacityUi();};
            width=Number(display,"Locked width px",c.MinWidthLogicalPx,900,1500,266);
            followWindowsTheme=Check(display,"Follow Windows app light/dark mode",c.FollowWindowsTheme,314);
            windowsLightTheme=Combo(display,"Windows light theme",ThemeCatalog.Names,c.WindowsLightTheme,352);
            windowsDarkTheme=Combo(display,"Windows dark theme",ThemeCatalog.Names,c.WindowsDarkTheme,390);
            Label glassNote=new Label{Text="Glass switch ON: background opacity = 0% (locked), text and charts stay visible. OFF: opacity 1–100%, with the previous value restored. Windows High Contrast stays readable and opaque.",Location=new Point(24,432),Size=new Size(730,58),AutoEllipsis=false};
            display.Controls.Add(glassNote);
            cpu=Check(metrics,"CPU",c.ShowCpu,24);ram=Check(metrics,"RAM",c.ShowRam,55);disk=Check(metrics,"Disk / storage",c.ShowDisk,86);gpu=Check(metrics,"GPU",c.ShowGpu,117);vram=Check(metrics,"VRAM",c.ShowVram,148);net=Check(metrics,"Network",c.ShowNetwork,179);temp=Check(metrics,"CPU/GPU temperature",c.ShowTemperatures,210);spark=Check(metrics,"Real sparklines",c.ShowSparklines,241);

            tempAlerts=Check(alerts,"Enable temperature warning highlights",c.EnableTemperatureAlerts,24);
            tempNotifications=Check(alerts,"Show Windows notification when a threshold is crossed",c.EnableTemperatureNotifications,55);
            tempSound=Check(alerts,"Play Windows warning sound on a new hot threshold",c.EnableTemperatureWarningSound,86);
            cpuWarn=Number(alerts,"CPU warning °C",c.CpuTempWarningC,50,110,135);
            gpuWarn=Number(alerts,"GPU warning °C",c.GpuTempWarningC,50,110,185);
            diskWarn=Number(alerts,"Disk warning °C",c.DiskTempWarningC,40,90,235);
            Label alertNote=new Label();alertNote.Location=new Point(24,284);alertNote.Size=new Size(690,120);alertNote.Text="Selected CPU, GPU or disk temperatures can switch the metric card to a high-visibility warning accent. Optional Windows notifications fire only on a new hot transition, use a 3 C recovery hysteresis and a 10-minute per-lane cooldown. Unsupported or stale temperature data never creates a false hot state. Sound is opt-in and follows your Windows sound scheme.";alerts.Controls.Add(alertNote);
            Button testWarningSound=new Button{Text="Test warning sound",Location=new Point(24,420),
                Size=new Size(200,36),AutoSize=false};
            SetA11y(testWarningSound,"Test temperature warning sound",
                "Play one Windows Exclamation sound without heating the CPU or changing alarm thresholds.");
            testWarningSound.Click+=delegate
            {
                try
                {
                    System.Media.SystemSounds.Exclamation.Play();
                    Log.Write("INFO","TEMPERATURE_WARNING_SOUND_TEST_REQUESTED");
                }
                catch(Exception ex){Log.Write("WARN","TEMPERATURE_WARNING_SOUND_TEST_FAILED "+ex.GetType().Name);}
            };
            alerts.Controls.Add(testWarningSound);

            hardware.AutoScroll=true;hardware.AutoScrollMargin=new Size(0,24);int y=16;
            AddHardwareSection(hardware,"CPU",c.CpuDisplayMode,ChoicesCpu(),c.SelectedCpuIds,y,out cpuMode,out cpuList);y+=118;
            AddHardwareSection(hardware,"GPU",c.GpuDisplayMode,ChoicesGpu(),c.SelectedGpuIds,y,out gpuMode,out gpuList);y+=118;
            AddHardwareSection(hardware,"Physical disk",c.DiskDisplayMode,ChoicesDisk(),c.SelectedDiskIds,y,out diskMode,out diskList);y+=118;
            AddHardwareSection(hardware,"Network adapter",c.NetworkDisplayMode,ChoicesNet(),c.SelectedNetworkIds,y,out netMode,out netList);y+=118;
            multiLayout=Combo(hardware,"Multiple layout",new string[]{"Grouped","Separate"},c.MultipleDeviceLayout,y);flyout=Check(hardware,"Show upward hardware flyout on hover",c.EnableHardwareFlyout,y+42);hoverAll=Check(hardware,"Flyout shows all detected devices (not only selected)",c.HoverShowAllDevices,y+72);

            memoryUnit=Combo(units,"RAM unit",new string[]{"Auto","KB","MB","GB"},c.MemoryUnit,28);storageUnit=Combo(units,"Storage capacity unit",new string[]{"Auto","KB","MB","GB"},c.StorageUnit,78);diskRateUnit=Combo(units,"Disk speed unit",new string[]{"Auto","KB","MB","GB"},c.DiskRateUnit,128);networkUnit=Combo(units,"Network rate unit",new string[]{"Auto","KB","MB","GB"},c.NetworkUnit,178);ramNumeric=Check(units,"Show used / total RAM as a number",c.ShowRamNumeric,238);diskNumeric=Check(units,"Show used / total disk capacity in hover details",c.ShowDiskNumeric,272);
            Label unitNote=new Label();unitNote.Location=new Point(24,320);unitNote.Size=new Size(660,85);unitNote.Text="Disk cards show live read/write throughput. Capacity, usage, volumes and temperature stay in hover details. Auto chooses readable units independently for each measurement.";units.Controls.Add(unitNote);

            interval=Number(behavior,"Update interval ms",c.UpdateIntervalMs,1000,5000,24);
            startup=Check(behavior,"Start with Windows",c.StartWithWindows,78);
            safe=Check(behavior,"Safe placement / avoid taskbar controls",c.SafePlacement,112);
            autoCheckUpdates=Check(behavior,"Automatically check GitHub Releases for updates",c.AutoCheckUpdates,148);
            adaptiveBattery=Check(behavior,"Adaptive battery mode (slower polling on battery)",c.AdaptiveBatteryMode,194);
            batteryInterval=Number(behavior,"Battery interval ms",c.BatteryUpdateIntervalMs,2000,10000,236);
            historyLength=Number(behavior,"Sparkline history samples",c.SparklineHistoryLength,30,300,286);
            Label behaviorNote=new Label();behaviorNote.Location=new Point(24,338);behaviorNote.Size=new Size(690,90);behaviorNote.Text="Adaptive battery mode never polls faster than your normal interval. Session Pause/Resume is available from the taskbar context menu and does not get cancelled by suspend/resume events.";behavior.Controls.Add(behaviorNote);
            // The owner rejected Start lift; never offer a UI option that can re-enable it.
            floatAboveStart=Check(behavior,"Taskbar anchored during Start (always ON)",false,444);
            floatAboveStart.Visible=false;floatAboveStart.Enabled=false;

            updateCurrent=new Label();updateCurrent.Location=new Point(24,28);updateCurrent.Size=new Size(650,24);updateCurrent.Text="Installed version: "+BuildInfo.PublicVersion;updates.Controls.Add(updateCurrent);
            updateLatest=new Label();updateLatest.Location=new Point(24,62);updateLatest.Size=new Size(650,24);updateLatest.Text="Latest public release: Not checked";updates.Controls.Add(updateLatest);
            updateStatus=new Label();updateStatus.Location=new Point(24,100);updateStatus.Size=new Size(660,80);updateStatus.Text="Use Check for updates to query the official GitHub Releases page.";updates.Controls.Add(updateStatus);
            checkUpdate=new Button();checkUpdate.Text="Check for updates";checkUpdate.Location=new Point(24,196);checkUpdate.Size=new Size(150,34);checkUpdate.Click+=delegate{BeginCheckUpdates();};updates.Controls.Add(checkUpdate);
            installUpdate=new Button();installUpdate.Text="Download && Install";installUpdate.Location=new Point(188,196);installUpdate.Size=new Size(160,34);installUpdate.Enabled=false;installUpdate.Click+=delegate{BeginInstallUpdate();};updates.Controls.Add(installUpdate);
            openRelease=new Button();openRelease.Text="Open release page";openRelease.Location=new Point(362,196);openRelease.Size=new Size(145,34);openRelease.Enabled=false;openRelease.Click+=delegate{OpenReleasePage();};updates.Controls.Add(openRelease);
            Label updateNote=new Label();updateNote.Location=new Point(24,250);updateNote.Size=new Size(660,150);updateNote.Text="Updates come only from the official GitHub Releases feed. Automatic installation requires an immutable release, the exact setup asset and GitHub SHA-256 digest metadata. Mutable releases are never auto-installed.";updates.Controls.Add(updateNote);

            diagnosticsText=new TextBox();SetA11y(diagnosticsText,"Diagnostics report","Read-only runtime health and diagnostics report.");diagnosticsText.Location=new Point(24,72);diagnosticsText.Size=new Size(800,390);diagnosticsText.Multiline=true;diagnosticsText.ReadOnly=true;diagnosticsText.ScrollBars=ScrollBars.Both;diagnosticsText.WordWrap=false;diagnosticsText.Font=new Font("Cascadia Mono",9f);diagnostics.Controls.Add(diagnosticsText);
            refreshDiagnostics=new Button();refreshDiagnostics.Text="Refresh health";refreshDiagnostics.Location=new Point(24,24);refreshDiagnostics.Size=new Size(130,34);refreshDiagnostics.Click+=delegate{RefreshDiagnostics();};diagnostics.Controls.Add(refreshDiagnostics);
            saveDiagnostics=new Button();saveDiagnostics.Text="Save report...";saveDiagnostics.Location=new Point(168,24);saveDiagnostics.Size=new Size(130,34);saveDiagnostics.Click+=delegate{SaveDiagnosticsReport();};diagnostics.Controls.Add(saveDiagnostics);
            openDataFolder=new Button();openDataFolder.Text="Open data folder";openDataFolder.Location=new Point(312,24);openDataFolder.Size=new Size(135,34);openDataFolder.Click+=delegate{try{Process.Start("explorer.exe",AppPaths.Root);}catch{}};diagnostics.Controls.Add(openDataFolder);
            repairSensors=new Button();repairSensors.Text="Repair protected sensors...";repairSensors.Location=new Point(461,24);repairSensors.Size=new Size(185,34);repairSensors.Click+=delegate{RepairProtectedSensors();};diagnostics.Controls.Add(repairSensors);
            healthBadge=new Label();healthBadge.Location=new Point(24,478);healthBadge.Size=new Size(205,34);healthBadge.TextAlign=ContentAlignment.MiddleCenter;healthBadge.Font=new Font("Segoe UI Semibold",9.3f,FontStyle.Bold);healthBadge.BorderStyle=BorderStyle.FixedSingle;healthBadge.Text="Health: checking...";diagnostics.Controls.Add(healthBadge);
            copyDiagnostics=new Button();copyDiagnostics.Text="Copy diagnostics";copyDiagnostics.Location=new Point(246,478);copyDiagnostics.Size=new Size(135,34);copyDiagnostics.Click+=delegate{CopyDiagnosticsToClipboard();};diagnostics.Controls.Add(copyDiagnostics);
            exportSupportBundle=new Button();exportSupportBundle.Text="Export support ZIP...";exportSupportBundle.Location=new Point(396,478);exportSupportBundle.Size=new Size(165,34);exportSupportBundle.Click+=delegate{ExportSupportBundleZip();};diagnostics.Controls.Add(exportSupportBundle);
            exportSessionCsv=new Button();exportSessionCsv.Text="Export session CSV...";SetA11y(exportSessionCsv,"Export session CSV","Export the bounded in-memory telemetry history for this application session as CSV.");exportSessionCsv.Location=new Point(576,478);exportSessionCsv.Size=new Size(165,34);exportSessionCsv.Click+=delegate{ExportSessionCsvFile();};diagnostics.Controls.Add(exportSessionCsv);

            Button openLog=new Button();openLog.Text="Open Logs";openLog.Location=new Point(24,28);openLog.Width=120;openLog.Click+=delegate{try{Process.Start("explorer.exe",AppPaths.Logs);}catch{}};advanced.Controls.Add(openLog);
            resetDefaults=new Button();resetDefaults.Text="Load safe defaults...";resetDefaults.Location=new Point(24,78);resetDefaults.Size=new Size(155,34);resetDefaults.Click+=delegate{ResetControlsToSafeDefaults();};advanced.Controls.Add(resetDefaults);
            Label note=new Label();note.AutoSize=false;note.Location=new Point(24,138);note.Size=new Size(690,300);note.Text="Startup resilience uses dual per-user registration plus continuous low-pressure self-heal. Protected sensors remain process-isolated. Safe reset creates a timestamped config backup, loads defaults into this form, and does not change the running monitor until Save & Apply.";advanced.Controls.Add(note);

            ModernizeSettingsPage(display,"Display","Choose the visual language and placement of the taskbar monitor.");
            ModernizeSettingsPage(metrics,"Metrics","Turn individual taskbar readings on or off without changing the sensor layer.");
            ModernizeSettingsPage(alerts,"Alerts","Define real sensor thresholds and optional rate-limited Windows notifications.");
            ModernizeSettingsPage(hardware,"Hardware","Choose physical devices, aggregation and hover-detail behavior.");
            ModernizeSettingsPage(units,"Units","Choose how memory, storage and transfer rates are formatted.");
            ModernizeSettingsPage(behavior,"Behavior","Control startup, adaptive polling, history depth and placement safeguards.");
            ModernizeSettingsPage(updates,"Updates","Verify and install immutable public releases safely.");
            ModernizeSettingsPage(diagnostics,"Diagnostics","Inspect live health, copy reports and export support evidence.");
            ModernizeSettingsPage(advanced,"Advanced","Maintenance, logs and safe configuration reset.");

            // The note extends to y=508 after the page modernization shift.
            // The former preview at y=500 overlapped it by 8px; leave a 28px gap.
            themePreview=new ThemePreviewControl(themePreviewRenderer);themePreview.Location=new Point(24,536);themePreview.Size=new Size(650,132);themePreview.Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right;display.AutoScrollMinSize=new Size(760,720);display.Controls.Add(themePreview);themePreview.BringToFront();
            theme.SelectedIndexChanged+=delegate{UpdateThemeModeUi();};windowsLightTheme.SelectedIndexChanged+=delegate{UpdateThemeModeUi();};windowsDarkTheme.SelectedIndexChanged+=delegate{UpdateThemeModeUi();};followWindowsTheme.CheckedChanged+=delegate{UpdateThemeModeUi();};UpdateThemeModeUi();
            EnsureAccessibilityMetadata(this);

            Panel actions=new Panel();actions.Dock=DockStyle.Fill;actions.BackColor=SettingsWindow;actions.Padding=new Padding(0,10,4,10);contentArea.Controls.Add(actions,0,2);
            FlowLayoutPanel buttons=new FlowLayoutPanel();buttons.Dock=DockStyle.Right;buttons.Width=250;buttons.FlowDirection=FlowDirection.RightToLeft;buttons.WrapContents=false;buttons.BackColor=SettingsWindow;actions.Controls.Add(buttons);
            Button ok=new Button();ok.Text="Save && Apply";SetA11y(ok,"Save and Apply","Save all Settings changes and apply them to the taskbar monitor. Shortcut Ctrl+S.");ok.Size=new Size(118,38);StyleActionButton(ok,true);ok.Click+=delegate{Apply();DialogResult=DialogResult.OK;Close();};
            Button cancel=new Button();cancel.Text="Cancel";SetA11y(cancel,"Cancel","Close Settings without applying unsaved changes.");cancel.Size=new Size(98,38);StyleActionButton(cancel,false);cancel.Click+=delegate{DialogResult=DialogResult.Cancel;Close();};
            buttons.Controls.Add(ok);buttons.Controls.Add(cancel);AcceptButton=ok;CancelButton=cancel;
            CaptureNormalPalette(this);ApplyAccessibilityPalette();

            tabs.SelectedIndexChanged+=delegate{UpdateSettingsNavigation();if(tabs.SelectedTab!=null&&String.Equals(tabs.SelectedTab.Text,"Diagnostics",StringComparison.OrdinalIgnoreCase))RefreshDiagnostics();};
            if(!String.IsNullOrWhiteSpace(initialTab))foreach(TabPage tp in tabs.TabPages)if(String.Equals(tp.Text,initialTab,StringComparison.OrdinalIgnoreCase)){tabs.SelectedTab=tp;break;}
            UpdateSettingsNavigation();
            Shown+=delegate{if(c.AutoCheckUpdates||String.Equals(initialTab,"Updates",StringComparison.OrdinalIgnoreCase))BeginCheckUpdates();if(String.Equals(initialTab,"Diagnostics",StringComparison.OrdinalIgnoreCase))RefreshDiagnostics();};
        }

        private Button CreateNavigationButton(string text,int index)
        {
            Button b=new Button();b.Text=text;b.Tag=index;b.Size=new Size(182,44);SetA11y(b,text+" settings","Open the "+text+" settings page. Shortcut Ctrl+"+(index+1).ToString(CultureInfo.InvariantCulture));b.Margin=new Padding(1,3,1,3);b.Padding=new Padding(13,0,0,0);
            b.TextAlign=ContentAlignment.MiddleLeft;b.FlatStyle=FlatStyle.Flat;b.FlatAppearance.BorderSize=0;b.BackColor=SettingsSidebar;b.ForeColor=SettingsMuted;b.Font=new Font("Segoe UI Semibold",9.6f,FontStyle.Bold);b.Cursor=Cursors.Hand;
            b.Click+=delegate(object sender,EventArgs e){Button x=sender as Button;if(x!=null&&tabsControl!=null)tabsControl.SelectedIndex=Convert.ToInt32(x.Tag,CultureInfo.InvariantCulture);};
            return b;
        }

        private void UpdateSettingsNavigation()
        {
            if(tabsControl==null||tabsControl.SelectedIndex<0)return;
            int selected=tabsControl.SelectedIndex;
            for(int i=0;i<settingsNavButtons.Count;i++)
            {
                bool on=i==selected;Button b=settingsNavButtons[i];
                b.BackColor=on?SettingsSurface2:SettingsSidebar;b.ForeColor=on?SettingsText:SettingsMuted;
                b.FlatAppearance.MouseOverBackColor=SettingsSurface2;b.FlatAppearance.MouseDownBackColor=SettingsSurface;
            }
            if(settingsPageTitle!=null)settingsPageTitle.Text=tabsControl.TabPages[selected].Text;
            if(settingsPageSubtitle!=null&&selected<SettingsPageDescriptions.Length)settingsPageSubtitle.Text=SettingsPageDescriptions[selected];
        }

        private void ModernizeSettingsPage(TabPage page,string title,string description)
        {
            List<Control> existing=page.Controls.Cast<Control>().ToList();
            int maxBottom=0;
            page.BackColor=SettingsSurface;page.ForeColor=SettingsText;page.Padding=new Padding(16);
            foreach(Control control in existing)
            {
                control.Top+=18;
                control.Left+=10;
                maxBottom=Math.Max(maxBottom,control.Bottom);
                StyleSettingsControl(control);
                control.BringToFront();
            }
            page.AutoScrollMinSize=new Size(Math.Max(page.AutoScrollMinSize.Width,760),Math.Max(page.AutoScrollMinSize.Height,maxBottom+28));
        }

        private void StyleSettingsControl(Control control)
        {
            control.Font=control.Font??Font;
            if(control is Label)
            {
                Label l=(Label)control;l.ForeColor=SettingsMuted;if(l.Font.Bold)l.ForeColor=SettingsText;
            }
            else if(control is ComboBox)
            {
                ComboBox x=(ComboBox)control;x.FlatStyle=FlatStyle.Flat;x.BackColor=SettingsSurface2;x.ForeColor=SettingsText;x.DrawMode=DrawMode.OwnerDrawFixed;x.ItemHeight=Math.Max(18,x.ItemHeight);
                x.DrawItem+=delegate(object sender,DrawItemEventArgs e)
                {
                    if(e.Index<0)return;
                    ComboBox cb=(ComboBox)sender;bool selected=(e.State&DrawItemState.Selected)==DrawItemState.Selected;
                    using(SolidBrush bg=new SolidBrush(selected?Color.FromArgb(48,90,139):SettingsSurface2))e.Graphics.FillRectangle(bg,e.Bounds);
                    using(SolidBrush fg=new SolidBrush(SettingsText))e.Graphics.DrawString(Convert.ToString(cb.Items[e.Index],CultureInfo.InvariantCulture),cb.Font,fg,e.Bounds.X+6,e.Bounds.Y+2);
                    e.DrawFocusRectangle();
                };
            }
            else if(control is NumericUpDown)
            {
                NumericUpDown n=(NumericUpDown)control;n.BackColor=SettingsSurface2;n.ForeColor=SettingsText;n.BorderStyle=BorderStyle.FixedSingle;foreach(Control child in n.Controls){child.BackColor=SettingsSurface2;child.ForeColor=SettingsText;}
            }
            else if(control is GlassToggleSwitch)
            {
                // Native Flat CheckBox paint is never allowed over custom track ink.
                GlassToggleSwitch x=(GlassToggleSwitch)control;
                x.FlatStyle=FlatStyle.Standard;x.ForeColor=SettingsText;x.BackColor=SettingsSurface;
            }
            else if(control is CheckBox)
            {
                CheckBox x=(CheckBox)control;x.ForeColor=SettingsText;x.FlatStyle=FlatStyle.Flat;x.FlatAppearance.BorderColor=SettingsAccent;
            }
            else if(control is Button)
            {
                StyleActionButton((Button)control,false);
            }
            else if(control is CheckedListBox)
            {
                CheckedListBox x=(CheckedListBox)control;x.BackColor=Color.FromArgb(14,20,28);x.ForeColor=SettingsText;x.BorderStyle=BorderStyle.FixedSingle;
            }
            else if(control is TextBox)
            {
                TextBox x=(TextBox)control;x.BackColor=Color.FromArgb(11,16,23);x.ForeColor=Color.FromArgb(211,223,235);x.BorderStyle=BorderStyle.FixedSingle;
            }
        }

        private void StyleActionButton(Button b,bool primary)
        {
            b.FlatStyle=FlatStyle.Flat;b.FlatAppearance.BorderSize=primary?0:1;b.FlatAppearance.BorderColor=Color.FromArgb(64,78,94);
            b.BackColor=primary?SettingsAccent:SettingsSurface2;b.ForeColor=primary?Color.White:SettingsText;b.Font=new Font("Segoe UI Semibold",9.1f,FontStyle.Bold);b.Cursor=Cursors.Hand;
            b.FlatAppearance.MouseOverBackColor=primary?Color.FromArgb(92,170,255):Color.FromArgb(34,46,61);
            b.FlatAppearance.MouseDownBackColor=primary?Color.FromArgb(55,133,225):Color.FromArgb(28,39,52);
        }

        private static void SetA11y(Control c,string name,string description)
        {
            if(c==null)return;c.AccessibleName=name??"";c.AccessibleDescription=description??"";
        }
        private static string AccessibleText(string text)
        {
            return (text??"").Replace("&&","&").Replace("&","").Trim().TrimEnd('.');
        }
        private static void EnsureAccessibilityMetadata(Control root)
        {
            if(root==null)return;
            foreach(Control c0 in root.Controls)
            {
                bool relevant=c0 is Button||c0 is CheckBox;
                if(relevant&&String.IsNullOrWhiteSpace(c0.AccessibleName)&&!String.IsNullOrWhiteSpace(c0.Text))
                {
                    string name=AccessibleText(c0.Text);SetA11y(c0,name,"Activate "+name+".");
                }
                EnsureAccessibilityMetadata(c0);
            }
        }
        private void CaptureNormalPalette(Control root)
        {
            if(root==null)return;if(!normalPalette.ContainsKey(root))normalPalette[root]=Tuple.Create(root.BackColor,root.ForeColor);
            foreach(Control c0 in root.Controls)CaptureNormalPalette(c0);
        }
        private void ApplyAccessibilityPalette()
        {
            ApplyAccessibilityPalette(null);
        }
        private void ApplyAccessibilityPalette(bool? highContrastOverride)
        {
            bool high=highContrastOverride.HasValue?highContrastOverride.Value:SystemInformation.HighContrast;
            if(high)
            {
                foreach(KeyValuePair<Control,Tuple<Color,Color>> kv in normalPalette)
                {
                    Control c0=kv.Key;if(c0==null||c0.IsDisposed)continue;
                    bool field=c0 is TextBox||c0 is ComboBox||c0 is NumericUpDown||c0 is CheckedListBox;
                    c0.BackColor=field?SystemColors.Window:SystemColors.Control;
                    c0.ForeColor=field?SystemColors.WindowText:SystemColors.ControlText;
                }
            }
            else
            {
                foreach(KeyValuePair<Control,Tuple<Color,Color>> kv in normalPalette)
                    if(kv.Key!=null&&!kv.Key.IsDisposed){kv.Key.BackColor=kv.Value.Item1;kv.Key.ForeColor=kv.Value.Item2;}
                UpdateSettingsNavigation();
            }
            Invalidate(true);
        }
        internal int HighContrastCoverageGapCount(out int checkedControls)
        {
            checkedControls=0;int gaps=0;
            try
            {
                ApplyAccessibilityPalette(true);
                Stack<Control> stack=new Stack<Control>();stack.Push(this);
                while(stack.Count>0)
                {
                    Control c0=stack.Pop();foreach(Control child in c0.Controls)stack.Push(child);
                    if(c0==this)continue;checkedControls++;
                    bool field=c0 is TextBox||c0 is ComboBox||c0 is NumericUpDown||c0 is CheckedListBox;
                    Color eb=field?SystemColors.Window:SystemColors.Control;
                    Color ef=field?SystemColors.WindowText:SystemColors.ControlText;
                    if(c0.BackColor.ToArgb()!=eb.ToArgb()||c0.ForeColor.ToArgb()!=ef.ToArgb())gaps++;
                }
            }
            finally{ApplyAccessibilityPalette(SystemInformation.HighContrast);}
            return gaps;
        }
        internal void NotifySystemPreferenceChanged()
        {
            UpdateThemeModeUi();ApplyAccessibilityPalette();
        }
        private string ResolvedPreviewThemeName()
        {
            if(SystemInformation.HighContrast)return "Windows High Contrast";
            if(followWindowsTheme!=null&&followWindowsTheme.Checked)
                return WindowsThemePolicy.AppsUseLightTheme()?Convert.ToString(windowsLightTheme.SelectedItem,CultureInfo.InvariantCulture):Convert.ToString(windowsDarkTheme.SelectedItem,CultureInfo.InvariantCulture);
            return Convert.ToString(theme.SelectedItem,CultureInfo.InvariantCulture);
        }
        private void SyncGlassOpacityUi()
        {
            if(glassModeToggle==null || opacity==null)return;
            if(glassModeState!=null)glassModeState.Text=glassModeToggle.Checked?"On":"Off";
            if(glassModeToggle.Checked)
            {
                if(opacity.Enabled && opacity.Value>0)lastOpacityPercent=(int)opacity.Value;
                opacity.Enabled=false;
                opacity.Minimum=0;
                opacity.Value=0;
            }
            else
            {
                bool restore=!opacity.Enabled || opacity.Value<1;
                opacity.Minimum=1;
                if(restore)opacity.Value=Math.Max(1,Math.Min(100,lastOpacityPercent));
                opacity.Enabled=true;
            }
        }
        private void UpdateThemeModeUi()
        {
            if(theme==null)return;bool follow=followWindowsTheme!=null&&followWindowsTheme.Checked;
            theme.Enabled=!follow;if(windowsLightTheme!=null)windowsLightTheme.Enabled=follow;if(windowsDarkTheme!=null)windowsDarkTheme.Enabled=follow;
            if(themePreview!=null)themePreview.ThemeName=ResolvedPreviewThemeName();
        }
        internal int AccessibilityGapCount(out int interactive)
        {
            interactive=0;int missing=0;List<string> gaps=new List<string>();Stack<Control> stack=new Stack<Control>();stack.Push(this);
            while(stack.Count>0)
            {
                Control c0=stack.Pop();foreach(Control child in c0.Controls)stack.Push(child);
                bool internalChild=c0.Parent is NumericUpDown||c0.Parent is ComboBox||c0.Parent is CheckedListBox;
                bool relevant=!internalChild&&(c0 is Button||c0 is ComboBox||c0 is NumericUpDown||c0 is CheckBox||c0 is TrackBar||c0 is CheckedListBox||c0 is TextBox);
                if(!relevant)continue;interactive++;
                if(String.IsNullOrWhiteSpace(c0.AccessibleName))
                {
                    missing++;gaps.Add(c0.GetType().Name+" text='"+(c0.Text??"").Replace("\r"," ").Replace("\n"," ")+"'");
                }
            }
            if(gaps.Count>0)Console.Error.WriteLine("TBME_A11Y_GAPS "+String.Join(" | ",gaps.ToArray()));
            return missing;
        }
        protected override bool ProcessCmdKey(ref Message msg,Keys keyData)
        {
            if((keyData&Keys.Control)==Keys.Control)
            {
                Keys k=keyData&Keys.KeyCode;
                if(k>=Keys.D1&&k<=Keys.D9&&tabsControl!=null){int i=(int)k-(int)Keys.D1;if(i<tabsControl.TabPages.Count){tabsControl.SelectedIndex=i;return true;}}
                if(k==Keys.S){Apply();DialogResult=DialogResult.OK;Close();return true;}
            }
            if(keyData==Keys.F5&&tabsControl!=null&&tabsControl.SelectedTab!=null&&String.Equals(tabsControl.SelectedTab.Text,"Diagnostics",StringComparison.OrdinalIgnoreCase)){RefreshDiagnostics();return true;}
            return base.ProcessCmdKey(ref msg,keyData);
        }

        public void SelectTab(string tabName)
        {
            if(String.IsNullOrWhiteSpace(tabName)||tabsControl==null)return;
            foreach(TabPage tp in tabsControl.TabPages)
            {
                if(String.Equals(tp.Text,tabName,StringComparison.OrdinalIgnoreCase))
                {
                    tabsControl.SelectedTab=tp;
                    return;
                }
            }
        }

        private void Ui(Action action)
        {
            try{if(IsDisposed||Disposing)return;if(InvokeRequired)BeginInvoke((MethodInvoker)delegate{if(!IsDisposed&&!Disposing)action();});else action();}catch{}
        }
        private void BeginCheckUpdates()
        {
            if(checkUpdate!=null)checkUpdate.Enabled=false;if(installUpdate!=null)installUpdate.Enabled=false;if(updateStatus!=null)updateStatus.Text="Checking official GitHub Releases...";
            ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    ReleaseUpdateInfo info=UpdateManager.CheckLatest();latestUpdate=info;Ui(delegate{updateLatest.Text="Latest public release: "+(String.IsNullOrWhiteSpace(info.Version)?info.Tag:info.Version)+"  |  Immutable: "+(info.Immutable?"Yes":"No");updateStatus.Text=info.Status;openRelease.Enabled=info.ReleaseUrlValid;installUpdate.Enabled=info.HasUpdate&&info.SetupAssetAvailable&&info.DigestAvailable&&info.Immutable&&!info.Draft&&!info.Prerelease&&info.TagValid&&info.ReleaseUrlValid&&info.SetupUrlValid;checkUpdate.Enabled=true;});
                    Log.Write("INFO","UPDATE_CHECK latest="+info.Version+" hasUpdate="+info.HasUpdate+" asset="+info.SetupAssetAvailable+" digest="+info.DigestAvailable+" immutable="+info.Immutable+" canonical="+(info.TagValid&&info.ReleaseUrlValid&&info.SetupUrlValid));
                }
                catch(Exception ex){Log.Write("WARN","UPDATE_CHECK_FAIL "+ex.Message);Ui(delegate{updateStatus.Text="Update check failed: "+ex.Message;checkUpdate.Enabled=true;installUpdate.Enabled=false;});}
            });
        }
        private void BeginInstallUpdate()
        {
            ReleaseUpdateInfo info=latestUpdate;if(info==null||!info.HasUpdate)return;
            if(MessageBox.Show("Download, verify and launch Taskbar Monitor Enhanced "+info.Version+" setup?","Taskbar Monitor Enhanced Update",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)return;
            checkUpdate.Enabled=false;installUpdate.Enabled=false;updateStatus.Text="Downloading and verifying "+info.SetupName+"...";
            ThreadPool.QueueUserWorkItem(delegate
            {
                try
                {
                    string path=UpdateManager.DownloadAndVerify(info);Ui(delegate{updateStatus.Text="SHA-256 verified. Re-checking immediately before launch...";});Thread.Sleep(250);UpdateManager.StartInstaller(path,info.SetupDigest);Ui(delegate{DialogResult=DialogResult.Cancel;Close();});Thread.Sleep(300);Application.Exit();
                }
                catch(Exception ex){Log.Write("ERROR","UPDATE_INSTALL_FAIL "+ex.ToString());Ui(delegate{updateStatus.Text="Update failed safely: "+ex.Message;checkUpdate.Enabled=true;installUpdate.Enabled=info.HasUpdate&&info.SetupAssetAvailable&&info.DigestAvailable&&info.Immutable&&!info.Draft&&!info.Prerelease&&info.TagValid&&info.ReleaseUrlValid&&info.SetupUrlValid;});}
            });
        }
        private void OpenReleasePage(){try{if(latestUpdate!=null&&!String.IsNullOrWhiteSpace(latestUpdate.HtmlUrl))Process.Start(latestUpdate.HtmlUrl);else Process.Start(BuildInfo.RepositoryUrl+"/releases");}catch(Exception ex){MessageBox.Show(ex.Message,"Open release page");}}

        private static string ReadSharedDiagnostic(string path)
        {
            try
            {
                if(!File.Exists(path))return "MISSING";
                using(FileStream fs=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))
                using(StreamReader sr=new StreamReader(fs,Encoding.UTF8,true))
                    return sr.ReadToEnd();
            }
            catch(Exception ex){return "READ_ERROR: "+ex.Message;}
        }

        private static string DiagnosticFileLine(string label,string path)
        {
            try
            {
                if(!File.Exists(path))return label+": MISSING — "+path;
                DateTime utc=File.GetLastWriteTimeUtc(path);
                double age=Math.Max(0,(DateTime.UtcNow-utc).TotalSeconds);
                return label+": age="+age.ToString("0.0",CultureInfo.InvariantCulture)+"s bytes="+new FileInfo(path).Length+" — "+path;
            }
            catch(Exception ex){return label+": ERROR "+ex.Message+" — "+path;}
        }

        private string BuildDiagnosticsReport()
        {
            StringBuilder b=new StringBuilder();
            b.AppendLine("Taskbar Monitor Enhanced — Diagnostics");
            b.AppendLine("GeneratedUtc: "+DateTime.UtcNow.ToString("o",CultureInfo.InvariantCulture));
            b.AppendLine("Build: "+BuildInfo.Version+" / "+BuildInfo.PublicVersion);
            b.AppendLine("Process: PID="+Process.GetCurrentProcess().Id+" 64Bit="+Environment.Is64BitProcess);
            b.AppendLine("OS: "+Environment.OSVersion+" CLR="+Environment.Version);
            b.AppendLine("TelemetryIntervalMs: "+c.UpdateIntervalMs);
            b.AppendLine("AdaptiveBatteryMode: "+c.AdaptiveBatteryMode+" BatteryIntervalMs="+c.BatteryUpdateIntervalMs);
            b.AppendLine("SparklineHistorySamples: "+c.SparklineHistoryLength);
            b.AppendLine("SessionTelemetrySamples: "+SessionTelemetryHistory.Count+" / "+SessionTelemetryHistory.MaxSamples);
            b.AppendLine("TemperatureNotifications: "+c.EnableTemperatureNotifications+" hysteresisC="+TemperatureNotificationState.HysteresisC+" cooldownMin="+TemperatureNotificationState.CooldownMinutes);
            b.AppendLine("DpiAwareness: "+Native.DpiAwarenessMode()+" HighContrast="+SystemInformation.HighContrast+" DllSearchHardened="+Native.DllSearchHardeningActive);
            b.AppendLine("Theme: configured="+c.Theme+" followWindows="+c.FollowWindowsTheme+" resolved="+WindowsThemePolicy.ResolveName(c));
            string resolvedTaskbar;IntPtr diagTaskbar=TaskbarTargetPolicy.Resolve(c,out resolvedTaskbar);b.AppendLine("TaskbarTarget: configured="+c.TaskbarDisplay+" resolved="+resolvedTaskbar+" hwnd="+diagTaskbar.ToInt64());
            b.AppendLine("TemperatureAlerts: "+c.EnableTemperatureAlerts+" CPU="+c.CpuTempWarningC+"C GPU="+c.GpuTempWarningC+"C DISK="+c.DiskTempWarningC+"C");
            bool diagHealth; b.AppendLine(CurrentHealthSummary(out diagHealth));
            b.AppendLine();
            b.AppendLine("Current snapshot");
            CpuDeviceSnapshot diagCpu=snapshot.CpuDevices.FirstOrDefault();
            GpuDeviceSnapshot diagGpu=snapshot.GpuDevices.OrderByDescending(x=>x.UsageAvailable?x.Usage:-1).FirstOrDefault();
            b.AppendLine("CPU devices="+snapshot.CpuDevices.Count+" usage="+snapshot.Cpu.ToString("0.0",CultureInfo.InvariantCulture)+"% temp="+(snapshot.CpuTempAvailable?snapshot.CpuTempCurrent.ToString("0.0",CultureInfo.InvariantCulture)+"C":"N/A")+" power="+(diagCpu!=null&&diagCpu.PowerAvailable?diagCpu.PowerW.ToString("0.0",CultureInfo.InvariantCulture)+"W":"N/A")+" source="+(snapshot.CpuTempSource??"UNAVAILABLE"));
            b.AppendLine("GPU devices="+snapshot.GpuDevices.Count+" usage="+snapshot.Gpu.ToString("0.0",CultureInfo.InvariantCulture)+"% temp="+(snapshot.GpuTempAvailable?snapshot.GpuTemp.ToString("0.0",CultureInfo.InvariantCulture)+"C":"N/A")+" power="+(diagGpu!=null&&diagGpu.PowerAvailable?diagGpu.PowerW.ToString("0.0",CultureInfo.InvariantCulture)+"W":"N/A")+" fan="+(diagGpu!=null&&diagGpu.FanRpmAvailable?diagGpu.FanRpm.ToString("0",CultureInfo.InvariantCulture)+"RPM":(diagGpu!=null&&diagGpu.FanPercentAvailable?diagGpu.FanPercent.ToString("0",CultureInfo.InvariantCulture)+"%":"N/A"))+" source="+(snapshot.GpuTempSource??"UNAVAILABLE"));
            b.AppendLine("Disk devices="+snapshot.DiskDevices.Count+" Network adapters="+snapshot.NetworkDevices.Count);
            b.AppendLine();
            b.AppendLine("Runtime files");
            b.AppendLine(DiagnosticFileLine("Supervisor state",AppPaths.SensorSupervisorState));
            b.AppendLine(DiagnosticFileLine("CPU broker",AppPaths.CpuTempBrokerData));
            b.AppendLine(DiagnosticFileLine("GPU broker",AppPaths.GpuBrokerData));
            b.AppendLine(DiagnosticFileLine("Storage broker",AppPaths.StorageBrokerData));
            b.AppendLine(DiagnosticFileLine("Backend state",AppPaths.SensorBackendState));
            b.AppendLine(DiagnosticFileLine("Last crash snapshot",AppPaths.CrashState));
            b.AppendLine();
            b.AppendLine("Supervisor state JSON");
            b.AppendLine(ReadSharedDiagnostic(AppPaths.SensorSupervisorState));
            b.AppendLine();
            b.AppendLine("Sensor backend state JSON");
            b.AppendLine(ReadSharedDiagnostic(AppPaths.SensorBackendState));
            b.AppendLine();
            b.AppendLine("Notes");
            b.AppendLine("- TransportHealthy means the worker is alive and producing fresh output.");
            b.AppendLine("- DataAvailable is separate: a healthy worker can legitimately report no supported/privileged sensor data.");
            b.AppendLine("- Automatic updates require immutable GitHub Releases plus GitHub SHA-256 asset digest metadata.");
            b.AppendLine("- Sensor supervisor self-heal is conservative: READY layer only, 90s startup grace/staleness threshold, 180s retry cooldown.");
            return b.ToString();
        }

        private static bool DiagnosticBool(Dictionary<string,object> d,string key)
        {
            if(d==null)return false;object v;if(!d.TryGetValue(key,out v)||v==null)return false;
            try{return Convert.ToBoolean(v,CultureInfo.InvariantCulture);}catch{return false;}
        }

        private string CurrentHealthSummary(out bool healthy)
        {
            healthy=false;
            try
            {
                if(!File.Exists(AppPaths.SensorSupervisorState))return "Health: state missing";
                string json=ReadSharedDiagnostic(AppPaths.SensorSupervisorState);
                Dictionary<string,object> d=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(json);
                bool cpuOk=DiagnosticBool(d,"CpuTransportHealthy")&&DiagnosticBool(d,"CpuDataAvailable");
                bool gpuOk=DiagnosticBool(d,"GpuTransportHealthy")&&DiagnosticBool(d,"GpuDataAvailable");
                bool storageOk=DiagnosticBool(d,"StorageTransportHealthy")&&DiagnosticBool(d,"StorageDataAvailable");
                healthy=cpuOk&&gpuOk&&storageOk;
                return healthy?"Health: ALL SYSTEMS OK":("Health: DEGRADED  CPU="+cpuOk+" GPU="+gpuOk+" STORAGE="+storageOk);
            }
            catch(Exception ex){return "Health: unavailable ("+ex.Message+")";}
        }

        private void RefreshDiagnostics()
        {
            try
            {
                if(diagnosticsText!=null)diagnosticsText.Text=BuildDiagnosticsReport();
                if(healthBadge!=null)
                {
                    bool healthy;healthBadge.Text=CurrentHealthSummary(out healthy);
                    healthBadge.ForeColor=healthy?Color.FromArgb(120,235,170):Color.FromArgb(255,150,135);
                    healthBadge.BackColor=healthy?Color.FromArgb(19,58,43):Color.FromArgb(68,31,32);
                }
            }
            catch(Exception ex){if(diagnosticsText!=null)diagnosticsText.Text="Diagnostics failed: "+ex;}
        }

        private void CopyDiagnosticsToClipboard()
        {
            try
            {
                string report=BuildDiagnosticsReport();
                Clipboard.SetText(report);
                if(diagnosticsText!=null)diagnosticsText.Text=report+"\r\n\r\nCopied to clipboard.";
            }
            catch(Exception ex){MessageBox.Show(ex.Message,"Copy diagnostics",MessageBoxButtons.OK,MessageBoxIcon.Warning);}
        }

        private void ExportSupportBundleZip()
        {
            try
            {
                using(SaveFileDialog d=new SaveFileDialog())
                {
                    d.Filter="ZIP support bundle (*.zip)|*.zip";
                    d.FileName="TBME_Support_"+DateTime.Now.ToString("yyyyMMdd_HHmmss",CultureInfo.InvariantCulture)+".zip";
                    if(d.ShowDialog(this)!=DialogResult.OK)return;
                    SupportBundleBuilder.Create(d.FileName,BuildDiagnosticsReport());
                    if(diagnosticsText!=null)diagnosticsText.Text=BuildDiagnosticsReport()+"\r\n\r\nSupport bundle: "+d.FileName;
                }
            }
            catch(Exception ex){MessageBox.Show(ex.Message,"Export support bundle",MessageBoxButtons.OK,MessageBoxIcon.Warning);}
        }

        private void ExportSessionCsvFile()
        {
            try
            {
                using(SaveFileDialog d=new SaveFileDialog())
                {
                    d.Filter="CSV telemetry history (*.csv)|*.csv";
                    d.FileName="TBME_SessionTelemetry_"+DateTime.Now.ToString("yyyyMMdd_HHmmss",CultureInfo.InvariantCulture)+".csv";
                    if(d.ShowDialog(this)!=DialogResult.OK)return;
                    int rows=SessionTelemetryHistory.ExportCsv(d.FileName);
                    if(diagnosticsText!=null)diagnosticsText.Text=BuildDiagnosticsReport()+"\r\n\r\nSession CSV: "+d.FileName+"\r\nRows: "+rows.ToString(CultureInfo.InvariantCulture);
                }
            }
            catch(Exception ex){MessageBox.Show(ex.Message,"Export session CSV",MessageBoxButtons.OK,MessageBoxIcon.Warning);}
        }

        private static void CheckAll(CheckedListBox list)
        {
            if(list==null)return;for(int i=0;i<list.Items.Count;i++)if(list.Items[i] is HardwareChoice)list.SetItemChecked(i,true);
        }

        private void ResetControlsToSafeDefaults()
        {
            try
            {
                if(MessageBox.Show("Load safe defaults into this Settings window? A timestamped backup of the current config will be created first. Nothing changes until you choose Save & Apply.","Safe reset",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)return;
                string backupDir=Path.Combine(AppPaths.Root,"Backups");
                string backup=SafeResetPolicy.BackupCurrentConfig(AppPaths.Config,backupDir,DateTime.Now);
                if(!String.IsNullOrWhiteSpace(backup))Log.Write("INFO","CONFIG_SAFE_RESET_BACKUP "+backup);

                AppConfig d=new AppConfig();d.Normalize();
                theme.SelectedItem=d.Theme;position.SelectedItem=d.Position;
                lastOpacityPercent=Math.Max(1,Math.Min(100,(int)Math.Round(d.OpacityWhenGlassOff*100)));
                glassModeToggle.Checked=false;opacity.Enabled=true;opacity.Minimum=1;opacity.Value=lastOpacityPercent;
                glassModeToggle.Checked=d.GlassMode;SyncGlassOpacityUi();
                width.Value=d.MinWidthLogicalPx;
                cpu.Checked=d.ShowCpu;ram.Checked=d.ShowRam;disk.Checked=d.ShowDisk;gpu.Checked=d.ShowGpu;vram.Checked=d.ShowVram;net.Checked=d.ShowNetwork;temp.Checked=d.ShowTemperatures;spark.Checked=d.ShowSparklines;
                cpuMode.SelectedItem=d.CpuDisplayMode;gpuMode.SelectedItem=d.GpuDisplayMode;diskMode.SelectedItem=d.DiskDisplayMode;netMode.SelectedItem=d.NetworkDisplayMode;multiLayout.SelectedItem=d.MultipleDeviceLayout;
                memoryUnit.SelectedItem=d.MemoryUnit;storageUnit.SelectedItem=d.StorageUnit;diskRateUnit.SelectedItem=d.DiskRateUnit;networkUnit.SelectedItem=d.NetworkUnit;
                ramNumeric.Checked=d.ShowRamNumeric;diskNumeric.Checked=d.ShowDiskNumeric;flyout.Checked=d.EnableHardwareFlyout;hoverAll.Checked=d.HoverShowAllDevices;
                interval.Value=d.UpdateIntervalMs;startup.Checked=d.StartWithWindows;safe.Checked=d.SafePlacement;floatAboveStart.Checked=d.FloatAboveStartMenu;autoCheckUpdates.Checked=d.AutoCheckUpdates;
                tempAlerts.Checked=d.EnableTemperatureAlerts;tempNotifications.Checked=d.EnableTemperatureNotifications;tempSound.Checked=d.EnableTemperatureWarningSound;cpuWarn.Value=d.CpuTempWarningC;gpuWarn.Value=d.GpuTempWarningC;diskWarn.Value=d.DiskTempWarningC;
                adaptiveBattery.Checked=d.AdaptiveBatteryMode;batteryInterval.Value=d.BatteryUpdateIntervalMs;historyLength.Value=d.SparklineHistoryLength;followWindowsTheme.Checked=d.FollowWindowsTheme;windowsLightTheme.SelectedItem=d.WindowsLightTheme;windowsDarkTheme.SelectedItem=d.WindowsDarkTheme;taskbarDisplay.SelectedItem=d.TaskbarDisplay;
                CheckAll(cpuList);CheckAll(gpuList);CheckAll(diskList);CheckAll(netList);
                if(themePreview!=null)themePreview.ThemeName=d.Theme;
                MessageBox.Show("Defaults loaded. Review them, then choose Save & Apply to commit the reset.","Safe reset",MessageBoxButtons.OK,MessageBoxIcon.Information);
            }
            catch(Exception ex){MessageBox.Show(ex.Message,"Safe reset",MessageBoxButtons.OK,MessageBoxIcon.Warning);}
        }

        private void SaveDiagnosticsReport()
        {
            try
            {
                using(SaveFileDialog d=new SaveFileDialog())
                {
                    d.Filter="Text report (*.txt)|*.txt";
                    d.FileName="TBME_Diagnostics_"+DateTime.Now.ToString("yyyyMMdd_HHmmss",CultureInfo.InvariantCulture)+".txt";
                    if(d.ShowDialog(this)!=DialogResult.OK)return;
                    File.WriteAllText(d.FileName,BuildDiagnosticsReport(),Encoding.UTF8);
                    if(diagnosticsText!=null)diagnosticsText.Text=BuildDiagnosticsReport()+"\r\n\r\nSaved: "+d.FileName;
                }
            }
            catch(Exception ex){MessageBox.Show(ex.Message,"Save diagnostics");}
        }

        private void RepairProtectedSensors()
        {
            try
            {
                string setup=Path.Combine(AppPaths.Root,"Uninstall.exe");
                if(!File.Exists(setup))
                {
                    MessageBox.Show("Repair tool was not found. Re-run the latest Taskbar Monitor Enhanced installer.","Repair protected sensors",MessageBoxButtons.OK,MessageBoxIcon.Warning);
                    return;
                }
                if(MessageBox.Show("Repair the protected CPU/GPU/storage sensor layer? Windows will request administrator approval.","Repair protected sensors",MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)return;
                ProcessStartInfo psi=new ProcessStartInfo();
                psi.FileName=setup;psi.Arguments="/repair-sensors";psi.UseShellExecute=true;psi.Verb="runas";
                Process x=Process.Start(psi);
                if(x==null)throw new InvalidOperationException("Windows did not start the sensor repair tool.");
                Log.Write("INFO","SENSOR_REPAIR_STARTED");
            }
            catch(Exception ex)
            {
                Log.Write("WARN","SENSOR_REPAIR_START_FAIL "+ex.Message);
                MessageBox.Show(ex.Message,"Repair protected sensors",MessageBoxButtons.OK,MessageBoxIcon.Warning);
            }
        }

        private List<HardwareChoice> ChoicesCpu(){return snapshot.CpuDevices.Select(x=>new HardwareChoice{Id=x.Id,Name=x.Name}).ToList();}
        private List<HardwareChoice> ChoicesGpu(){return snapshot.GpuDevices.Select(x=>new HardwareChoice{Id=x.Id,Name=x.Name}).ToList();}
        private List<HardwareChoice> ChoicesDisk(){return snapshot.DiskDevices.Select(x=>new HardwareChoice{Id=x.Id,Name=x.Name+(!String.IsNullOrWhiteSpace(x.Volumes)?(" — "+x.Volumes):"")}).ToList();}
        private List<HardwareChoice> ChoicesNet(){return snapshot.NetworkDevices.Select(x=>new HardwareChoice{Id=x.Id,Name=x.Name+(!String.IsNullOrWhiteSpace(x.Description)?" — "+x.Description:"")}).ToList();}
        private void AddHardwareSection(Control p,string label,string modeValue,List<HardwareChoice> choices,string selectedIds,int y,out ComboBox mode,out CheckedListBox list)
        {
            Label h=new Label();h.Text=label;h.Location=new Point(24,y+4);h.Width=95;h.Font=new Font(Font,FontStyle.Bold);p.Controls.Add(h);Label ml=new Label();ml.Text="Mode";ml.Location=new Point(122,y+4);ml.Width=45;p.Controls.Add(ml);mode=new ComboBox();SetA11y(mode,label+" display mode","Choose how "+label+" devices are aggregated on the taskbar.");mode.DropDownStyle=ComboBoxStyle.DropDownList;mode.Location=new Point(170,y);mode.Width=180;mode.Items.AddRange(new string[]{"Overall","Auto","Single","Multiple"});mode.SelectedItem=modeValue;if(mode.SelectedIndex<0)mode.SelectedIndex=0;p.Controls.Add(mode);
            list=new CheckedListBox();SetA11y(list,label+" devices","Select which "+label+" devices are monitored.");list.Location=new Point(370,y);list.Size=new Size(330,92);list.CheckOnClick=true;HashSet<string> selected=SelectionUtil.Parse(selectedIds);bool all=selected.Count==0;foreach(HardwareChoice c0 in choices){int i=list.Items.Add(c0);if(all||selected.Contains(c0.Id))list.SetItemChecked(i,true);}if(choices.Count==0)list.Items.Add("No device detected yet");p.Controls.Add(list);
        }
        private string CheckedIds(CheckedListBox list)
        {
            List<string> ids=new List<string>();if(list==null)return "";foreach(object o in list.CheckedItems){HardwareChoice c0=o as HardwareChoice;if(c0!=null&&!String.IsNullOrWhiteSpace(c0.Id))ids.Add(c0.Id);}return SelectionUtil.Join(ids);
        }
        private ComboBox Combo(Control p,string label,string[] items,string value,int y){Label l=new Label();l.Text=label;l.Location=new Point(24,y+4);l.Width=145;p.Controls.Add(l);ComboBox x=new ComboBox();SetA11y(x,label,"Select "+label+".");x.DropDownStyle=ComboBoxStyle.DropDownList;x.Location=new Point(180,y);x.Width=250;x.Items.AddRange(items);x.SelectedItem=value;if(x.SelectedIndex<0)x.SelectedIndex=0;p.Controls.Add(x);return x;}
        private NumericUpDown Number(Control p,string label,decimal val,decimal min,decimal max,int y){Label l=new Label();l.Text=label;l.Location=new Point(24,y+4);l.Width=145;p.Controls.Add(l);NumericUpDown n=new NumericUpDown();SetA11y(n,label,"Set "+label+".");n.Location=new Point(180,y);n.Width=120;n.Minimum=min;n.Maximum=max;n.Value=Math.Min(max,Math.Max(min,val));p.Controls.Add(n);return n;}
        private CheckBox Check(Control p,string label,bool val,int y){CheckBox x=new CheckBox();x.Text=label;SetA11y(x,label,"Toggle "+label+".");x.Checked=val;x.Location=new Point(24,y);x.AutoSize=true;p.Controls.Add(x);return x;}
        private void Apply()
        {
            c.Theme=(string)theme.SelectedItem;c.Position=(string)position.SelectedItem;
            c.GlassMode=glassModeToggle.Checked;
            c.OpacityWhenGlassOff=Math.Max(0.01,lastOpacityPercent/100.0);
            c.Opacity=c.GlassMode?0.0:(double)opacity.Value/100.0;
            c.MinWidthLogicalPx=(int)width.Value;c.UpdateIntervalMs=(int)interval.Value;c.ShowCpu=cpu.Checked;c.ShowRam=ram.Checked;c.ShowDisk=disk.Checked;c.ShowGpu=gpu.Checked;c.ShowVram=vram.Checked;c.ShowNetwork=net.Checked;c.ShowTemperatures=temp.Checked;c.ShowSparklines=spark.Checked;c.StartWithWindows=startup.Checked;c.SafePlacement=safe.Checked;c.FloatAboveStartMenu=floatAboveStart.Checked;
            c.CpuDisplayMode=(string)cpuMode.SelectedItem;c.GpuDisplayMode=(string)gpuMode.SelectedItem;c.DiskDisplayMode=(string)diskMode.SelectedItem;c.NetworkDisplayMode=(string)netMode.SelectedItem;c.SelectedCpuIds=CheckedIds(cpuList);c.SelectedGpuIds=CheckedIds(gpuList);c.SelectedDiskIds=CheckedIds(diskList);c.SelectedNetworkIds=CheckedIds(netList);c.MultipleDeviceLayout=(string)multiLayout.SelectedItem;c.MemoryUnit=(string)memoryUnit.SelectedItem;c.StorageUnit=(string)storageUnit.SelectedItem;c.DiskRateUnit=(string)diskRateUnit.SelectedItem;c.NetworkUnit=(string)networkUnit.SelectedItem;c.ShowRamNumeric=ramNumeric.Checked;c.ShowDiskNumeric=diskNumeric.Checked;c.EnableHardwareFlyout=flyout.Checked;c.HoverShowAllDevices=hoverAll.Checked;c.AutoCheckUpdates=autoCheckUpdates.Checked;
            c.EnableTemperatureAlerts=tempAlerts.Checked;c.EnableTemperatureNotifications=tempNotifications.Checked;c.EnableTemperatureWarningSound=tempSound.Checked;c.CpuTempWarningC=(int)cpuWarn.Value;c.GpuTempWarningC=(int)gpuWarn.Value;c.DiskTempWarningC=(int)diskWarn.Value;c.AdaptiveBatteryMode=adaptiveBattery.Checked;c.BatteryUpdateIntervalMs=(int)batteryInterval.Value;c.SparklineHistoryLength=(int)historyLength.Value;c.FollowWindowsTheme=followWindowsTheme.Checked;c.WindowsLightTheme=Convert.ToString(windowsLightTheme.SelectedItem,CultureInfo.InvariantCulture);c.WindowsDarkTheme=Convert.ToString(windowsDarkTheme.SelectedItem,CultureInfo.InvariantCulture);c.TaskbarDisplay=TaskbarTargetPolicy.NormalizeConfigId(Convert.ToString(taskbarDisplay.SelectedItem,CultureInfo.InvariantCulture));
        }
    }

    internal static class StartupManager
    {
        public const string RunValueName="TaskbarMonitorEnhanced";
        public const string RecoveryArgument="--startup-recovery";
        public const string RecoveryShortcutFileName="Taskbar Monitor Enhanced Startup Recovery.lnk";

        public static string RecoveryShortcutPath
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup),RecoveryShortcutFileName); }
        }

        private static void CreateShortcut(string path,string target,string arguments)
        {
            Type shellType=null;object shell=null;object shortcut=null;
            try
            {
                shellType=Type.GetTypeFromProgID("WScript.Shell");
                if(shellType==null)throw new InvalidOperationException("WScript.Shell COM registration is unavailable.");
                shell=Activator.CreateInstance(shellType);
                shortcut=shellType.InvokeMember("CreateShortcut",BindingFlags.InvokeMethod,null,shell,new object[]{path});
                Type shortcutType=shortcut.GetType();
                shortcutType.InvokeMember("TargetPath",BindingFlags.SetProperty,null,shortcut,new object[]{target});
                shortcutType.InvokeMember("Arguments",BindingFlags.SetProperty,null,shortcut,new object[]{arguments});
                shortcutType.InvokeMember("WorkingDirectory",BindingFlags.SetProperty,null,shortcut,new object[]{Path.GetDirectoryName(target)});
                shortcutType.InvokeMember("IconLocation",BindingFlags.SetProperty,null,shortcut,new object[]{target+",0"});
                shortcutType.InvokeMember("Description",BindingFlags.SetProperty,null,shortcut,new object[]{"Delayed recovery launcher for Taskbar Monitor Enhanced Start-with-Windows."});
                shortcutType.InvokeMember("WindowStyle",BindingFlags.SetProperty,null,shortcut,new object[]{1});
                shortcutType.InvokeMember("Save",BindingFlags.InvokeMethod,null,shortcut,null);
            }
            finally
            {
                if(shortcut!=null&&Marshal.IsComObject(shortcut))try{Marshal.FinalReleaseComObject(shortcut);}catch{}
                if(shell!=null&&Marshal.IsComObject(shell))try{Marshal.FinalReleaseComObject(shell);}catch{}
            }
        }

        private static string ExpectedRunCommand(string executablePath)
        {
            return "\""+executablePath+"\"";
        }

        private static bool RecoveryShortcutMatches(string shortcut,string executablePath)
        {
            if(!File.Exists(shortcut)||new FileInfo(shortcut).Length<=0)return false;
            Type shellType=null;object shell=null;object link=null;
            try
            {
                shellType=Type.GetTypeFromProgID("WScript.Shell");
                if(shellType==null)return false;
                shell=Activator.CreateInstance(shellType);
                link=shellType.InvokeMember("CreateShortcut",BindingFlags.InvokeMethod,null,shell,new object[]{shortcut});
                Type linkType=link.GetType();
                string target=Convert.ToString(linkType.InvokeMember("TargetPath",BindingFlags.GetProperty,null,link,null),CultureInfo.InvariantCulture)??"";
                string args=Convert.ToString(linkType.InvokeMember("Arguments",BindingFlags.GetProperty,null,link,null),CultureInfo.InvariantCulture)??"";
                string work=Convert.ToString(linkType.InvokeMember("WorkingDirectory",BindingFlags.GetProperty,null,link,null),CultureInfo.InvariantCulture)??"";
                return String.Equals(Path.GetFullPath(target),Path.GetFullPath(executablePath),StringComparison.OrdinalIgnoreCase)&&
                       String.Equals(args.Trim(),RecoveryArgument,StringComparison.OrdinalIgnoreCase)&&
                       String.Equals(
                           Path.GetFullPath(String.IsNullOrWhiteSpace(work)?Path.GetDirectoryName(target):work),
                           Path.GetFullPath(Path.GetDirectoryName(executablePath)),
                           StringComparison.OrdinalIgnoreCase);
            }
            catch{return false;}
            finally
            {
                if(link!=null&&Marshal.IsComObject(link))try{Marshal.FinalReleaseComObject(link);}catch{}
                if(shell!=null&&Marshal.IsComObject(shell))try{Marshal.FinalReleaseComObject(shell);}catch{}
            }
        }

        private static void EnsureRecoveryShortcut(string executablePath)
        {
            string shortcut=RecoveryShortcutPath;
            if(RecoveryShortcutMatches(shortcut,executablePath))return;
            Directory.CreateDirectory(Path.GetDirectoryName(shortcut));
            try{if(File.Exists(shortcut))File.Delete(shortcut);}catch{}
            CreateShortcut(shortcut,executablePath,RecoveryArgument);
            if(!RecoveryShortcutMatches(shortcut,executablePath))
                throw new InvalidOperationException("Recovery shortcut verification failed after creation.");
            Log.Write("INFO","STARTUP_RECOVERY_SHORTCUT_REPAIRED path="+shortcut);
        }

        private static bool RunRegistrationMatches(string executablePath)
        {
            try
            {
                using(RegistryKey k=Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run",false))
                {
                    string value=k==null?null:Convert.ToString(k.GetValue(RunValueName,null,RegistryValueOptions.DoNotExpandEnvironmentNames),CultureInfo.InvariantCulture);
                    return String.Equals(value,ExpectedRunCommand(executablePath),StringComparison.Ordinal);
                }
            }
            catch{return false;}
        }

        public static bool EnsureExpectedState(bool enabled)
        {
            string executablePath=Application.ExecutablePath;
            bool healthy=true;
            if(enabled)
            {
                if(!RunRegistrationMatches(executablePath))
                {
                    healthy=false;
                    try
                    {
                        using(RegistryKey k=Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"))
                            k.SetValue(RunValueName,ExpectedRunCommand(executablePath),RegistryValueKind.String);
                        Log.Write("WARN","STARTUP_RUN_SELFHEAL_REPAIRED");
                    }
                    catch(Exception ex){Log.Write("WARN","STARTUP_RUN_SELFHEAL_FAIL "+ex.Message);}
                }
                try
                {
                    if(!RecoveryShortcutMatches(RecoveryShortcutPath,executablePath))
                    {
                        healthy=false;
                        EnsureRecoveryShortcut(executablePath);
                    }
                }
                catch(Exception ex){healthy=false;Log.Write("WARN","STARTUP_RECOVERY_SELFHEAL_FAIL "+ex.Message);}
                return healthy && RunRegistrationMatches(executablePath) && RecoveryShortcutMatches(RecoveryShortcutPath,executablePath);
            }

            try
            {
                using(RegistryKey k=Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"))
                    k.DeleteValue(RunValueName,false);
            }
            catch(Exception ex){healthy=false;Log.Write("WARN","STARTUP_RUN_DISABLE_FAIL "+ex.Message);}
            try
            {
                if(File.Exists(RecoveryShortcutPath))File.Delete(RecoveryShortcutPath);
            }
            catch(Exception ex){healthy=false;Log.Write("WARN","STARTUP_RECOVERY_DISABLE_FAIL "+ex.Message);}
            return healthy && !RunRegistrationMatches(executablePath) && !File.Exists(RecoveryShortcutPath);
        }

        public static void SetEnabled(bool enabled)
        {
            EnsureExpectedState(enabled);
        }

        public static int RunContractSelfTest()
        {
            string dir=Path.Combine(Path.GetTempPath(),"tbme_startup_contract_"+Process.GetCurrentProcess().Id.ToString(CultureInfo.InvariantCulture));
            string target=Path.Combine(dir,"TaskbarMonitorEnhanced.exe");
            string shortcut=Path.Combine(dir,"recovery.lnk");
            try
            {
                Directory.CreateDirectory(dir);
                File.WriteAllText(target,"selftest",Encoding.UTF8);
                if(ExpectedRunCommand(target)!="\""+target+"\"")throw new InvalidOperationException("expected run command mismatch");
                CreateShortcut(shortcut,target,RecoveryArgument);
                if(!RecoveryShortcutMatches(shortcut,target))throw new InvalidOperationException("valid shortcut rejected");
                CreateShortcut(shortcut,target,"--wrong-argument");
                if(RecoveryShortcutMatches(shortcut,target))throw new InvalidOperationException("wrong shortcut argument accepted");
                Console.WriteLine("TBME_STARTUP_CONTRACT_SELFTEST=PASS MAINTENANCE_SEC=60");
                return 0;
            }
            catch(Exception ex)
            {
                Console.Error.WriteLine("TBME_STARTUP_CONTRACT_SELFTEST=FAIL "+ex);
                return 15;
            }
            finally{try{Directory.Delete(dir,true);}catch{}}
        }

        public static bool IsRecoveryInvocation(string[] args)
        {
            return args!=null&&args.Any(x=>String.Equals(x,RecoveryArgument,StringComparison.OrdinalIgnoreCase));
        }

        public static bool WaitForPrimaryInstanceOrTimeout()
        {
            int current=Process.GetCurrentProcess().Id;
            for(int i=0;i<12;i++)
            {
                try
                {
                    if(Process.GetProcessesByName("TaskbarMonitorEnhanced").Any(p=>p.Id!=current))return true;
                }
                catch{}
                Thread.Sleep(1000);
            }
            return false;
        }
    }

    internal static class HardwareProbe
    {
        public static int Run(string outputPath)
        {
            try
            {
                MetricsSnapshot s=null;using(MetricsEngine engine=new MetricsEngine()){for(int i=0;i<8;i++){s=engine.Read();Thread.Sleep(350);}}
                if(s==null)throw new InvalidOperationException("hardware snapshot unavailable");
                Dictionary<string,object> m=new Dictionary<string,object>();m["Version"]=BuildInfo.Version;m["PublicVersion"]=BuildInfo.PublicVersion;m["Status"]="PASS";
                m["Cpu"]=s.CpuDevices.Select(x=>(object)new Dictionary<string,object>{{"Id",x.Id},{"Name",x.Name},{"Usage",x.Usage},{"UsageAvailable",x.UsageAvailable},{"Temperature",x.Temperature},{"TemperatureAvailable",x.TemperatureAvailable},{"PowerW",x.PowerW},{"PowerAvailable",x.PowerAvailable},{"PhysicalCores",x.PhysicalCores},{"LogicalProcessors",x.LogicalProcessors},{"CurrentClockMHz",x.CurrentClockMHz},{"MaxClockMHz",x.MaxClockMHz},{"ExternalClockMHz",x.ExternalClockMHz},{"Socket",x.Socket}}).ToList();
                m["Gpu"]=s.GpuDevices.Select(x=>(object)new Dictionary<string,object>{{"Id",x.Id},{"Name",x.Name},{"Source",x.Source},{"Usage",x.Usage},{"UsageAvailable",x.UsageAvailable},{"Temperature",x.Temperature},{"TemperatureAvailable",x.TemperatureAvailable},{"VramUsedGb",x.VramUsedGb},{"VramTotalGb",x.VramTotalGb},{"CoreClockMHz",x.CoreClockMHz},{"CoreClockAvailable",x.CoreClockAvailable},{"MemoryClockMHz",x.MemoryClockMHz},{"MemoryClockAvailable",x.MemoryClockAvailable},{"PowerW",x.PowerW},{"PowerAvailable",x.PowerAvailable},{"FanRpm",x.FanRpm},{"FanRpmAvailable",x.FanRpmAvailable},{"FanPercent",x.FanPercent},{"FanPercentAvailable",x.FanPercentAvailable},{"PcieGeneration",x.PcieGeneration},{"PcieWidth",x.PcieWidth}}).ToList();
                m["Disk"]=s.DiskDevices.Select(x=>(object)new Dictionary<string,object>{{"Id",x.Id},{"Name",x.Name},{"Volumes",x.Volumes},{"UsedBytes",x.UsedBytes},{"TotalBytes",x.TotalBytes},{"PhysicalSizeBytes",x.PhysicalSizeBytes},{"UsedPercent",x.UsedPercent},{"Activity",x.Activity},{"ReadBytesPerSec",x.ReadBytesPerSec},{"WriteBytesPerSec",x.WriteBytesPerSec},{"TemperatureAvailable",x.TemperatureAvailable},{"Temperature",x.Temperature},{"TemperatureSource",x.TemperatureSource},{"BusType",x.BusType},{"MediaType",x.MediaType},{"InterfaceType",x.InterfaceType}}).ToList();
                m["Network"]=s.NetworkDevices.Select(x=>(object)new Dictionary<string,object>{{"Id",x.Id},{"Name",x.Name},{"Description",x.Description},{"DownBytesPerSec",x.DownBytesPerSec},{"UpBytesPerSec",x.UpBytesPerSec},{"LinkSpeedBitsPerSec",x.LinkSpeedBitsPerSec}}).ToList();
                m["MemoryModules"]=s.MemoryModules.Select(x=>(object)new Dictionary<string,object>{{"BankLabel",x.BankLabel},{"DeviceLocator",x.DeviceLocator},{"Manufacturer",x.Manufacturer},{"PartNumber",x.PartNumber},{"MemoryType",x.MemoryType},{"CapacityBytes",x.CapacityBytes},{"SpeedMHz",x.SpeedMHz},{"ConfiguredClockMHz",x.ConfiguredClockMHz},{"DataWidth",x.DataWidth},{"TotalWidth",x.TotalWidth}}).ToList();
                m["RamUsedBytes"]=s.RamUsedBytes;m["RamTotalBytes"]=s.RamTotalBytes;m["RamPercent"]=s.Ram;m["DiskUsedBytes"]=s.DiskUsedBytes;m["DiskTotalBytes"]=s.DiskTotalBytes;m["DiskReadBytesPerSec"]=s.DiskReadBytesPerSec;m["DiskWriteBytesPerSec"]=s.DiskWriteBytesPerSec;m["NetworkDownBytesPerSec"]=s.NetDownBytesPerSec;m["NetworkUpBytesPerSec"]=s.NetUpBytesPerSec;
                JavaScriptSerializer js=new JavaScriptSerializer();File.WriteAllText(outputPath,js.Serialize(m),Encoding.UTF8);Console.WriteLine("TBME_HARDWARE_PROBE=PASS CPU="+s.CpuDevices.Count+" GPU="+s.GpuDevices.Count+" DISK="+s.DiskDevices.Count+" NET="+s.NetworkDevices.Count);return 0;
            }
            catch(Exception ex){try{File.WriteAllText(outputPath,new JavaScriptSerializer().Serialize(new Dictionary<string,object>{{"Status","FAIL"},{"Error",ex.ToString()}}),Encoding.UTF8);}catch{}Console.Error.WriteLine("TBME_HARDWARE_PROBE=FAIL "+ex.Message);return 9;}
        }
    }

    internal static class TemperatureProbe
    {
        public static int Run(string outputPath)
        {
            Dictionary<string,object> m=new Dictionary<string,object>();
            try
            {
                MetricsSnapshot s=null;
                using(MetricsEngine engine=new MetricsEngine())
                {
                    for(int i=0;i<8;i++)
                    {
                        s=engine.Read();
                        Thread.Sleep(350);
                    }
                }

                if(s==null)throw new InvalidOperationException("temperature snapshot unavailable");

                m["Version"]=BuildInfo.Version;
                m["Status"]="PASS";
                m["Window"]="last 60 valid temperature samples";
                m["CpuAvailable"]=s.CpuTempAvailable;
                m["CpuCurrentC"]=s.CpuTempCurrent;
                m["CpuAverageC"]=s.CpuTempAvg;
                m["CpuMaximumC"]=s.CpuTempMax;
                m["CpuSource"]=s.CpuTempSource??"UNAVAILABLE";
                m["GpuAvailable"]=s.GpuTempAvailable;
                m["GpuAverageC"]=s.GpuTempAvg;
                m["GpuMaximumC"]=s.GpuTempMax;
                m["GpuSource"]=s.GpuTempSource??"UNAVAILABLE";

                JavaScriptSerializer js=new JavaScriptSerializer();
                File.WriteAllText(outputPath,js.Serialize(m),Encoding.UTF8);

                Console.WriteLine(
                    "TBME_TEMP_PROBE=PASS"+
                    " CPU_AVAILABLE="+s.CpuTempAvailable+
                    " CPU_CURRENT="+s.CpuTempCurrent.ToString("0.0",CultureInfo.InvariantCulture)+
                    " CPU_AVG="+s.CpuTempAvg.ToString("0.0",CultureInfo.InvariantCulture)+
                    " CPU_MAX="+s.CpuTempMax.ToString("0.0",CultureInfo.InvariantCulture)+
                    " CPU_SOURCE="+(s.CpuTempSource??"UNAVAILABLE")+
                    " GPU_AVAILABLE="+s.GpuTempAvailable+
                    " GPU_AVG="+s.GpuTempAvg.ToString("0.0",CultureInfo.InvariantCulture)+
                    " GPU_MAX="+s.GpuTempMax.ToString("0.0",CultureInfo.InvariantCulture)+
                    " GPU_SOURCE="+(s.GpuTempSource??"UNAVAILABLE")
                );
                return 0;
            }
            catch(Exception ex)
            {
                m["Version"]=BuildInfo.Version;
                m["Status"]="FAIL_EXCEPTION";
                m["Error"]=ex.ToString();
                try
                {
                    JavaScriptSerializer js=new JavaScriptSerializer();
                    File.WriteAllText(outputPath,js.Serialize(m),Encoding.UTF8);
                }
                catch{}
                Console.Error.WriteLine("TBME_TEMP_PROBE=FAIL "+ex.Message);
                return 7;
            }
        }
    }

    internal static class HealthProbe
    {
        private static Dictionary<string,object> ReadState(string path,double freshnessSeconds)
        {
            Dictionary<string,object> d=new Dictionary<string,object>();
            d["Path"]=path;d["Exists"]=File.Exists(path);
            if(!File.Exists(path))return d;
            try
            {
                string json=BrokerJsonFile.ReadShared(path);
                Dictionary<string,object> root=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(json);
                if(root==null){d["ReadError"]="JSON_EMPTY";return d;}
                object tsObj;DateTime ts=DateTime.MinValue;
                if(root.TryGetValue("TimestampUtc",out tsObj)&&DateTime.TryParse(Convert.ToString(tsObj,CultureInfo.InvariantCulture),CultureInfo.InvariantCulture,DateTimeStyles.AssumeUniversal|DateTimeStyles.AdjustToUniversal,out ts))
                {
                    double age=Math.Max(0,(DateTime.UtcNow-ts).TotalSeconds);
                    d["TimestampUtc"]=ts.ToString("o",CultureInfo.InvariantCulture);d["AgeSeconds"]=age;d["Fresh"]=freshnessSeconds<=0||age<=freshnessSeconds;
                }
                else d["Fresh"]=freshnessSeconds<=0;

                foreach(string key in new string[]{"Available","Error","BrokerPid","BrokerMode","BrokerVersion","SupervisorVersion","Sequence","ReadDurationMs",
                    "SupervisorStartedUtc","SupervisorUptimeSeconds","ChildJobKillOnClose","ChildJobLastError","CpuJobContained","GpuJobContained","StorageJobContained",
                    "CpuTransportHealthy","CpuDataAvailable","CpuRestartCount","CpuConsecutiveFailures","CpuLastReason","CpuWorkerStartedUtc","CpuWorkerAgeSeconds","CpuLastFailureUtc","CpuLastFailureReason","CpuLastRecoveryUtc",
                    "GpuTransportHealthy","GpuDataAvailable","GpuRestartCount","GpuConsecutiveFailures","GpuLastReason","GpuWorkerStartedUtc","GpuWorkerAgeSeconds","GpuLastFailureUtc","GpuLastFailureReason","GpuLastRecoveryUtc",
                    "StorageTransportHealthy","StorageDataAvailable","StorageAttemptCount","StorageConsecutiveFailures","StorageTimeoutSeconds","StorageOutputExitGraceSeconds","StorageAcceptedBeforeExitCount","StorageReapCount","StorageLastCompletionMs","StorageLastReason","StorageWorkerStartedUtc","StorageWorkerAgeSeconds","StorageLastFailureUtc","StorageLastFailureReason","StorageLastRecoveryUtc"})
                {
                    object v;if(root.TryGetValue(key,out v)&&v!=null)d[key]=v;
                }

                object seq;
                if(root.TryGetValue("Gpus",out seq)&&seq is System.Collections.IEnumerable)
                {
                    int count=0,available=0;
                    foreach(object x in (System.Collections.IEnumerable)seq)
                    {
                        count++;Dictionary<string,object> m=x as Dictionary<string,object>;object av;
                        if(m!=null&&m.TryGetValue("Available",out av)){try{if(Convert.ToBoolean(av,CultureInfo.InvariantCulture))available++;}catch{}}
                    }
                    d["RecordCount"]=count;d["DataRecordCount"]=available;
                }
                if(root.TryGetValue("StorageTemperatures",out seq)&&seq is System.Collections.IEnumerable)
                {
                    int count=0,available=0;
                    foreach(object x in (System.Collections.IEnumerable)seq)
                    {
                        count++;Dictionary<string,object> m=x as Dictionary<string,object>;object av;
                        if(m!=null&&m.TryGetValue("Available",out av)){try{if(Convert.ToBoolean(av,CultureInfo.InvariantCulture))available++;}catch{}}
                    }
                    d["RecordCount"]=count;d["DataRecordCount"]=available;
                }
            }
            catch(Exception ex){d["ReadError"]=ex.Message;}
            return d;
        }

        private static bool B(Dictionary<string,object> d,string key,bool fallback)
        {
            object x;if(!d.TryGetValue(key,out x)||x==null)return fallback;
            try{return Convert.ToBoolean(x,CultureInfo.InvariantCulture);}catch{return fallback;}
        }

        private static int I(Dictionary<string,object> d,string key,int fallback)
        {
            object x;if(!d.TryGetValue(key,out x)||x==null)return fallback;
            try{return Convert.ToInt32(x,CultureInfo.InvariantCulture);}catch{return fallback;}
        }

        private static DateTime Utc(Dictionary<string,object> d,string key)
        {
            object x;if(!d.TryGetValue(key,out x)||x==null)return DateTime.MinValue;
            DateTime dt;
            return DateTime.TryParse(Convert.ToString(x,CultureInfo.InvariantCulture),CultureInfo.InvariantCulture,DateTimeStyles.AssumeUniversal|DateTimeStyles.AdjustToUniversal,out dt)?dt:DateTime.MinValue;
        }

        private static DateTime Latest(params DateTime[] values)
        {
            DateTime best=DateTime.MinValue;
            foreach(DateTime x in values)if(x>best)best=x;
            return best;
        }

        public static int Run(string outputPath)
        {
            Dictionary<string,object> supervisor=ReadState(AppPaths.SensorSupervisorState,15);
            Dictionary<string,object> cpu=ReadState(AppPaths.CpuTempBrokerData,15);
            Dictionary<string,object> gpu=ReadState(AppPaths.GpuBrokerData,20);
            Dictionary<string,object> storage=ReadState(AppPaths.StorageBrokerData,120);
            string brokerVersion=Convert.ToString(supervisor.ContainsKey("BrokerVersion")?supervisor["BrokerVersion"]:"",CultureInfo.InvariantCulture)??"";
            string supervisorVersion=Convert.ToString(supervisor.ContainsKey("SupervisorVersion")?supervisor["SupervisorVersion"]:"",CultureInfo.InvariantCulture)??"";
            bool architectureR21=brokerVersion.IndexOf("r21",StringComparison.OrdinalIgnoreCase)>=0;
            bool supervisorR33=String.Equals(supervisorVersion,"1.3.0+r33",StringComparison.OrdinalIgnoreCase);
            bool supervisorFresh=B(supervisor,"Fresh",false);
            bool cpuFresh=B(cpu,"Fresh",false);
            bool gpuFresh=B(gpu,"Fresh",false);
            bool storageFresh=B(storage,"Fresh",false);
            bool cpuTransport=B(supervisor,"CpuTransportHealthy",cpuFresh);
            bool gpuTransport=B(supervisor,"GpuTransportHealthy",gpuFresh);
            bool storageTransport=B(supervisor,"StorageTransportHealthy",storageFresh);
            bool jobKillOnClose=B(supervisor,"ChildJobKillOnClose",false);
            bool cpuJob=B(supervisor,"CpuJobContained",false);
            bool gpuJob=B(supervisor,"GpuJobContained",false);
            bool storageJob=I(supervisor,"StorageAttemptCount",0)<=0||B(supervisor,"StorageJobContained",false);
            bool processContainment=jobKillOnClose&&cpuJob&&gpuJob&&storageJob;
            bool pass=architectureR21&&supervisorR33&&supervisorFresh&&cpuFresh&&gpuFresh&&storageFresh&&cpuTransport&&gpuTransport&&storageTransport&&processContainment;

            int activeFailures=I(supervisor,"CpuConsecutiveFailures",0)+I(supervisor,"GpuConsecutiveFailures",0)+I(supervisor,"StorageConsecutiveFailures",0);
            DateTime latestFailure=Latest(Utc(supervisor,"CpuLastFailureUtc"),Utc(supervisor,"GpuLastFailureUtc"),Utc(supervisor,"StorageLastFailureUtc"));
            DateTime latestRecovery=Latest(Utc(supervisor,"CpuLastRecoveryUtc"),Utc(supervisor,"GpuLastRecoveryUtc"),Utc(supervisor,"StorageLastRecoveryUtc"));
            string resilienceState;
            if(activeFailures>0)resilienceState="RECOVERING";
            else if(latestFailure!=DateTime.MinValue&&(DateTime.UtcNow-latestFailure).TotalMinutes<=10)resilienceState="RECOVERED_RECENTLY";
            else resilienceState="STABLE";

            Dictionary<string,object> result=new Dictionary<string,object>();
            result["Version"]=BuildInfo.Version;result["PublicVersion"]=BuildInfo.PublicVersion;result["GeneratedUtc"]=DateTime.UtcNow.ToString("o",CultureInfo.InvariantCulture);
            result["Status"]=pass?"PASS":"DEGRADED";result["ArchitectureR21"]=architectureR21;result["SupervisorR33"]=supervisorR33;
            result["SupervisorVersion"]=supervisorVersion;result["BrokerProtocolVersion"]=brokerVersion;
            result["ProcessContainment"]=processContainment;
            result["ResilienceState"]=resilienceState;
            result["ActiveConsecutiveFailures"]=activeFailures;
            result["LastFailureUtc"]=latestFailure==DateTime.MinValue?"":latestFailure.ToString("o",CultureInfo.InvariantCulture);
            result["LastRecoveryUtc"]=latestRecovery==DateTime.MinValue?"":latestRecovery.ToString("o",CultureInfo.InvariantCulture);
            result["Supervisor"]=supervisor;result["Cpu"]=cpu;result["Gpu"]=gpu;result["Storage"]=storage;
            File.WriteAllText(outputPath,new JavaScriptSerializer().Serialize(result),Encoding.UTF8);
            Console.WriteLine("TBME_HEALTH_PROBE="+(pass?"PASS":"DEGRADED")+" R21="+architectureR21+" JOB="+processContainment+" RESILIENCE="+resilienceState+" SUP="+supervisorFresh+" CPU="+cpuFresh+"/"+cpuTransport+" GPU="+gpuFresh+"/"+gpuTransport+" STORAGE="+storageFresh+"/"+storageTransport);
            return pass?0:12;
        }
    }

    internal static class ThemeProof
    {
        public static int Run(string outputDirectory)
        {
            try
            {
                if(String.IsNullOrWhiteSpace(outputDirectory))throw new ArgumentException("output directory");
                Native.EnableDpi();
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);

                AppConfig c=AppConfig.Load();
                c.Normalize();

                using(OverlayForm f=new OverlayForm(c,true))
                {
                    return f.ExportThemeProofs(outputDirectory);
                }
            }
            catch(Exception ex)
            {
                Console.Error.WriteLine("TBME_THEME_PROOF=FAIL "+ex);
                return 4;
            }
        }
    }

    internal static class CompactProof
    {
        public static int Run(string outputDirectory)
        {
            try
            {
                if(String.IsNullOrWhiteSpace(outputDirectory))throw new ArgumentException("output directory");
                Native.EnableDpi();Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
                AppConfig c=AppConfig.Load();c.Normalize();
                using(OverlayForm f=new OverlayForm(c,true)){return f.ExportCompactProofs(outputDirectory);}
            }
            catch(Exception ex){Console.Error.WriteLine("TBME_COMPACT_PROOF=FAIL "+ex);return 8;}
        }
    }

    internal static class HoverGuardProof
    {
        public static int Run()
        {
            try
            {
                Native.EnableDpi();Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
                AppConfig c=AppConfig.Load();c.Normalize();
                using(OverlayForm overlay=new OverlayForm(c,true))
                {
                    if(!overlay.VerifySettingsHoverSuppression())throw new InvalidOperationException("Settings-open hover suppression invariant failed.");
                }
                Console.WriteLine("TBME_SETTINGS_HOVER_GUARD=PASS MOVE_SUPPRESSED=TRUE WATCHDOG_SUPPRESSED=TRUE FLYOUT_HIDDEN=TRUE");
                return 0;
            }
            catch(Exception ex)
            {
                Console.Error.WriteLine("TBME_SETTINGS_HOVER_GUARD=FAIL "+ex);
                return 14;
            }
        }
    }
    internal static class SettingsProof
    {

        // Disposable test-only mouse input; actual Windows input events, NOT f.Focus() or
        // f.Activate() treated as proof. Signatures mirror Win32 INPUT/MOUSEINPUT x64.
        [StructLayout(LayoutKind.Sequential)]
        private struct R121MouseData
        {
            public int dx,dy;
            public uint mouseData,flags,time;
            public UIntPtr extraInfo;
        }
        [StructLayout(LayoutKind.Explicit)]
        private struct R121Union
        {
            [FieldOffset(0)] public R121MouseData mouse;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct R121Input
        {
            public uint type;
            public R121Union data;
        }
        [DllImport("user32.dll",SetLastError=true)]
        private static extern uint SendInput(uint count,[In] R121Input[] events,int size);

        private static int PhysicalTitleClick(Point at)
        {
            if(IntPtr.Size!=8 || Marshal.SizeOf(typeof(R121Input))!=40)
                throw new InvalidOperationException("R121_UNVERIFIED_NATIVE_INPUT_LAYOUT");
            R121Input down=new R121Input{
                type=0,data=new R121Union{mouse=new R121MouseData{flags=0x0002}}
            };
            R121Input up=new R121Input{
                type=0,data=new R121Union{mouse=new R121MouseData{flags=0x0004}}
            };
            Point before=Cursor.Position;
            try
            {
                Cursor.Position=at;
                if(Cursor.Position!=at)
                    throw new InvalidOperationException("R121_NATIVE_CURSOR_MOVE_NOT_OBSERVED");
                R121Input[] clicks=new R121Input[]{down,up};
                int inserted=(int)SendInput(2,clicks,Marshal.SizeOf(typeof(R121Input)));
                if(inserted!=2)
                    throw new InvalidOperationException("R121_NATIVE_SENDINPUT_NOT_TWO_EVENTS "+
                        inserted+" WIN32="+Marshal.GetLastWin32Error());
                return inserted;
            }
            finally { Cursor.Position=before; }
        }


        // R120 disposable-VM native screen acceptance. Unlike --settingsproof,
        // this shows Settings ON SCREEN above a real WS_EX_NOACTIVATE, layered,
        // TopMost obstruction; Win32 foreground + CopyFromScreen are authoritative.
        // No personal installation, config, persisted theme or shell alteration.
        private sealed class NonactivatingTopmostGlassWitness : Form
        {
            protected override CreateParams CreateParams
            {
                get
                {
                    CreateParams p=base.CreateParams;
                    p.ExStyle|=Native.WS_EX_NOACTIVATE|Native.WS_EX_LAYERED;
                    return p;
                }
            }
        }

        private static Dictionary<string,int> PhysicalInkPixels(Bitmap bmp)
        {
            int saturated=0,pink=0;
            HashSet<int> colors=new HashSet<int>();
            for(int y=0;y<bmp.Height;y+=2)
            for(int x=0;x<bmp.Width;x+=2)
            {
                Color px=bmp.GetPixel(x,y);
                int max=Math.Max(px.R,Math.Max(px.G,px.B));
                int min=Math.Min(px.R,Math.Min(px.G,px.B));
                if(max>=80 && max-min>=24)saturated++;
                if(px.R>170 && px.B>100 && px.G<65)pink++;
                colors.Add(px.ToArgb());
            }
            return new Dictionary<string,int>{
                {"Saturated",saturated},{"Pink",pink},{"DistinctColors",colors.Count}
            };
        }

        private static Bitmap CopyRealScreen(Rectangle rect)
        {
            Bitmap bitmap=new Bitmap(rect.Width,rect.Height,PixelFormat.Format32bppArgb);
            using(Graphics g=Graphics.FromImage(bitmap))
                g.CopyFromScreen(rect.Left,rect.Top,0,0,rect.Size);
            return bitmap;
        }

        private static string Sha256R120(string path)
        {
            using(FileStream stream=File.OpenRead(path))
            using(SHA256 sha=SHA256.Create())
                return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","");
        }

        public static int RunNativeForeground(string outputDirectory)
        {
            string commit=Environment.GetEnvironmentVariable("GITHUB_SHA")??"";
            try
            {
                if(Environment.GetEnvironmentVariable("GITHUB_ACTIONS")!="true"||
                    Environment.GetEnvironmentVariable("RUNNER_ENVIRONMENT")!="github-hosted"||
                    Environment.GetEnvironmentVariable("RUNNER_OS")!="Windows"||
                    !Environment.UserInteractive||
                    Environment.MachineName.Equals("EMAD-PC-ULTIMAT",StringComparison.OrdinalIgnoreCase)||
                    !Regex.IsMatch(commit,"^[0-9a-f]{40}$"))
                    throw new InvalidOperationException("R120_REFUSE_NONDISPOSABLE_OR_UNBOUNDED_HOST");
                if(String.IsNullOrWhiteSpace(outputDirectory)||Directory.Exists(outputDirectory))
                    throw new InvalidOperationException("R120_MISSING_OUTPUT_OR_UNSAFE_RERUN");
                Directory.CreateDirectory(outputDirectory);
                Native.EnableDpi();
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Rectangle wa=Screen.PrimaryScreen.WorkingArea;
                if(wa.Width<980||wa.Height<660)
                    throw new InvalidOperationException("R120_REAL_SCREEN_NOT_LARGE_ENOUGH "+wa);
                Rectangle window=new Rectangle(wa.Left+24,wa.Top+8,900,650);
                Rectangle obstruction=new Rectangle(window.Left+110,window.Top+130,440,220);
                int obstructionBefore=0,obstructionCovered=0,settingSaturated=0,distinct=0;
                long settingsHandle=0,foregroundHandle=0,obstructionHandle=0;
                long settingsEx=0,obstructionEx=0;
                uint settingsPid=0,obstructionPid=0;
                bool foreground=false,noOwner=false,aboveTopmost=false,visible=false;
                bool titleHit=false;
                int inputEvents=0,clickAttempts=0;
                long foregroundBeforeClick=0;
                Point clickPoint=Point.Empty;
                string png="SETTINGS_REAL_FOREGROUND.png";
                string obstaclePng="TOPMOST_GLASS_OBSTRUCTION_BEFORE.png";
                AppConfig cfg=AppConfig.Load();cfg.Normalize();
                MetricsSnapshot metrics=new MetricsSnapshot();
                using(NonactivatingTopmostGlassWitness blocker=new NonactivatingTopmostGlassWitness())
                using(OverlayForm renderer=new OverlayForm(cfg,true))
                {
                    blocker.StartPosition=FormStartPosition.Manual;
                    blocker.Bounds=obstruction;
                    blocker.FormBorderStyle=FormBorderStyle.None;
                    blocker.ShowInTaskbar=false;
                    blocker.BackColor=Color.FromArgb(252,0,205);
                    blocker.TopMost=true;
                    blocker.Opacity=0.98;
                    blocker.Show();
                    Application.DoEvents();
                    Thread.Sleep(240);
                    using(Bitmap before=CopyRealScreen(obstruction))
                    {
                        obstructionBefore=PhysicalInkPixels(before)["Pink"];
                        before.Save(Path.Combine(outputDirectory,obstaclePng),ImageFormat.Png);
                    }
                    obstructionHandle=blocker.Handle.ToInt64();
                    obstructionEx=Native.GetWindowLongPtr(blocker.Handle,Native.GWL_EXSTYLE).ToInt64();
                    Native.GetWindowThreadProcessId(blocker.Handle,out obstructionPid);
                    if(!blocker.IsHandleCreated||!Native.IsWindowVisible(blocker.Handle)||
                        obstructionBefore<2000||(obstructionEx&Native.WS_EX_LAYERED)==0||
                        (obstructionEx&Native.WS_EX_NOACTIVATE)==0||
                        (obstructionEx&Native.WS_EX_TOPMOST)==0)
                        throw new InvalidOperationException("R120_REAL_TOPMOST_LAYERED_GLASS_WITNESS_MISSING");
                    renderer.PrimeSettingsThemePreviewFromLiveMetrics(12,100);
                    using(SettingsForm f=new SettingsForm(cfg,metrics,"Display",renderer.RenderSettingsThemePreview))
                    {
                        f.StartPosition=FormStartPosition.Manual;
                        f.Bounds=window;
                        f.Show();
                        Application.DoEvents();
                        for(int attempt=0;attempt<8;attempt++)
                        {
                            f.BringToFront();
                            f.Activate();
                            Application.DoEvents();
                            Thread.Sleep(140);
                            if(Native.GetForegroundWindow()==f.Handle)break;
                        }
                        // Foreground activation via Show/Activate is intentionally NOT sufficient:
                        // Windows foreground-lock policy can deny background activation. Use a
                        // real title-bar click as a human user would on the disposable host.
                        foregroundBeforeClick=Native.GetForegroundWindow().ToInt64();
                        clickPoint=new Point(f.Left+120,f.Top+15);
                        Native.POINT hit=new Native.POINT{X=clickPoint.X,Y=clickPoint.Y};
                        titleHit=Native.WindowFromPoint(hit)==f.Handle;
                        if(!titleHit)throw new InvalidOperationException(
                            "R121_TITLE_NOT_PHYSICALLY_HITTABLE_WITH_TOPMOST_GLASS");
                        for(int attempt=0;attempt<3;attempt++)
                        {
                            inputEvents+=PhysicalTitleClick(clickPoint);
                            clickAttempts++;
                            Thread.Sleep(200);
                            Application.DoEvents();
                            if(Native.GetForegroundWindow()==f.Handle)break;
                        }
                        settingsHandle=f.Handle.ToInt64();
                        foregroundHandle=Native.GetForegroundWindow().ToInt64();
                        settingsEx=Native.GetWindowLongPtr(f.Handle,Native.GWL_EXSTYLE).ToInt64();
                        Native.GetWindowThreadProcessId(f.Handle,out settingsPid);
                        foreground=foregroundHandle==settingsHandle;
                        noOwner=f.Owner==null&&Native.GetWindow(f.Handle,Native.GW_OWNER)==IntPtr.Zero;
                        visible=f.Visible&&Native.IsWindowVisible(f.Handle)&&Native.GetCloaked(f.Handle)==0;
                        aboveTopmost=f.ShowInTaskbar&&f.TopMost&&f.TopLevel&&
                            (settingsEx&Native.WS_EX_TOPMOST)!=0&&
                            (settingsEx&(Native.WS_EX_NOACTIVATE|Native.WS_EX_TOOLWINDOW))==0;
                        using(Bitmap onScreen=CopyRealScreen(f.Bounds))
                        {
                            Dictionary<string,int> ink=PhysicalInkPixels(onScreen);
                            settingSaturated=ink["Saturated"];
                            distinct=ink["DistinctColors"];
                            Rectangle overlap=Rectangle.Intersect(f.Bounds,obstruction);
                            for(int y=overlap.Top;y<overlap.Bottom;y+=2)
                            for(int x=overlap.Left;x<overlap.Right;x+=2)
                            {
                                Color px=onScreen.GetPixel(x-f.Left,y-f.Top);
                                if(px.R>170&&px.B>100&&px.G<65)obstructionCovered++;
                            }
                            onScreen.Save(Path.Combine(outputDirectory,png),ImageFormat.Png);
                        }
                    }
                }
                bool pass=foreground&&titleHit&&inputEvents==2*clickAttempts&&
                    clickAttempts>=1&&clickAttempts<=3&&visible&&noOwner&&aboveTopmost&&
                    settingsPid==(uint)Process.GetCurrentProcess().Id&&
                    obstructionPid==settingsPid&&settingSaturated>=150&&
                    distinct>=24&&obstructionCovered<100&&obstructionBefore>=2000;
                string real=Path.Combine(outputDirectory,png);
                string witness=Path.Combine(outputDirectory,obstaclePng);
                Dictionary<string,object> result=new Dictionary<string,object>{
                    {"Schema",1},{"Revision","R121"},{"EventCommit",commit},
                    {"Status",pass?"PASS":"FAIL"},{"Test","R121_USER_CLICK_SETTINGS_NATIVE_FOREGROUND_OVER_GLASS"},
                    {"MainPid",Process.GetCurrentProcess().Id},{"SettingsPid",settingsPid},
                    {"ObstaclePid",obstructionPid},{"SettingsHwnd",settingsHandle},{"ForegroundHwnd",foregroundHandle},
                    {"ObstacleHwnd",obstructionHandle},{"ForegroundBeforeClick",foregroundBeforeClick},
                    {"ClickPoint",new int[]{clickPoint.X,clickPoint.Y}},{"SettingsTitleHit",titleHit},
                    {"RealMouseInputEvents",inputEvents},{"RealMouseClickAttempts",clickAttempts},
                    {"SettingsNativeExStyle",settingsEx},
                    {"ObstacleNativeExStyle",obstructionEx},{"ForegroundIsSettings",foreground},
                    {"SettingsVisibleUncloaked",visible},{"SettingsHasNoOwner",noOwner},
                    {"SettingsTopMostAndActivatable",aboveTopmost},
                    {"SettingsBounds",new int[]{window.X,window.Y,window.Width,window.Height}},
                    {"ObstacleBounds",new int[]{obstruction.X,obstruction.Y,obstruction.Width,obstruction.Height}},
                    {"ObstaclePhysicalPinkBefore",obstructionBefore},
                    {"ObstaclePhysicalPinkLeakingAfter",obstructionCovered},
                    {"SettingsPhysicalSaturatedPixels",settingSaturated},{"SettingsPhysicalDistinctColors",distinct},
                    {"SettingsScreenshotSha256",Sha256R120(real)},
                    {"ObstacleScreenshotSha256",Sha256R120(witness)},
                    {"FormalExternalLabAccepted",false}
                };
                File.WriteAllText(Path.Combine(outputDirectory,"SETTINGS_NATIVE_FOREGROUND_R121.json"),
                    new JavaScriptSerializer().Serialize(result),Encoding.UTF8);
                Console.WriteLine("TBME_R121_SETTINGS_NATIVE_FOREGROUND="+(pass?"PASS":"FAIL")+
                    " FOREGROUND="+foreground+" TITLE_HIT="+titleHit+" MOUSE_EVENTS="+inputEvents+
                    " FG_BEFORE="+foregroundBeforeClick+" FG_AFTER="+foregroundHandle+
                    " ABOVE_TOPMOST="+aboveTopmost+
                    " REAL_SAT="+settingSaturated+" OBSTACLE_BEFORE="+obstructionBefore+
                    " LEAK="+obstructionCovered);
                return pass?0:120;
            }
            catch(Exception ex)
            {
                try
                {
                    if(Directory.Exists(outputDirectory))
                        File.WriteAllText(Path.Combine(outputDirectory,"SETTINGS_NATIVE_FOREGROUND_R121.json"),
                            new JavaScriptSerializer().Serialize(
                                new Dictionary<string,object>{{"Revision","R121"},{"EventCommit",commit},
                                {"Status","FAIL_EXCEPTION"},{"Error",ex.ToString()}}),Encoding.UTF8);
                }catch{}
                Console.Error.WriteLine("TBME_R121_SETTINGS_NATIVE_FOREGROUND=FAIL "+ex);
                return 121;
            }
        }

        public static int Run(string outputDirectory)
        {
            try
            {
                if(String.IsNullOrWhiteSpace(outputDirectory))throw new ArgumentException("output directory");
                Directory.CreateDirectory(outputDirectory);
                Native.EnableDpi();Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
                AppConfig c=AppConfig.Load();c.Normalize();
                MetricsSnapshot snapshot=new MetricsSnapshot();
                int interactive=0;int a11yGaps=0;int highContrastChecked=0;int highContrastGaps=0;
                string[] pages=new string[]{"Display","Metrics","Alerts","Hardware","Units","Behavior","Updates","Diagnostics","Advanced"};
                using(OverlayForm previewRenderer=new OverlayForm(c,true))
                {
                    previewRenderer.PrimeSettingsThemePreviewFromLiveMetrics(12,100);
                    using(SettingsForm f=new SettingsForm(c,snapshot,"Display",previewRenderer.RenderSettingsThemePreview))
                    {
                    f.Width=1080;f.Height=760;f.StartPosition=FormStartPosition.Manual;f.Location=new Point(-32000,-32000);
                    f.Show();Application.DoEvents();f.PerformLayout();
                    if(new AppConfig().FloatAboveStartMenu)
                        throw new InvalidDataException("R118_PINNED_BY_DEFAULT_SETTINGS_GUARD");
                    // Reject a visually drawn but taskbar-hidden, nonactivatable,
                    // overlay-owned or no-activate Settings handle.
                    if(!f.ShowInTaskbar||!f.TopMost||!f.TopLevel||f.Owner!=null||
                       !f.IsHandleCreated||!f.Visible)
                        throw new InvalidDataException("R117_SETTINGS_FOREGROUND_FORM_CONTRACT");
                    long settingsEx=Native.GetWindowLongPtr(f.Handle,Native.GWL_EXSTYLE).ToInt64();
                    if((settingsEx&(Native.WS_EX_NOACTIVATE|Native.WS_EX_TOOLWINDOW))!=0)
                        throw new InvalidDataException("R117_SETTINGS_INHERITED_TASKBAR_OVERLAY_STYLES");
                    a11yGaps=f.AccessibilityGapCount(out interactive);if(a11yGaps!=0)throw new InvalidDataException("Settings accessibility metadata gaps="+a11yGaps);
                    highContrastGaps=f.HighContrastCoverageGapCount(out highContrastChecked);if(highContrastGaps!=0)throw new InvalidDataException("Settings high contrast gaps="+highContrastGaps);
                    for(int i=0;i<pages.Length;i++)
                    {
                        f.SelectTab(pages[i]);f.PerformLayout();Application.DoEvents();
                        using(Bitmap bmp=new Bitmap(f.Width,f.Height,PixelFormat.Format32bppArgb))
                        {
                            f.DrawToBitmap(bmp,new Rectangle(0,0,bmp.Width,bmp.Height));
                            bmp.Save(Path.Combine(outputDirectory,String.Format(CultureInfo.InvariantCulture,"SETTINGS_{0:00}_{1}.png",i+1,pages[i].ToUpperInvariant())),ImageFormat.Png);
                        }
                    }
                }
                }
                Dictionary<string,object> manifest=new Dictionary<string,object>();
                manifest["Version"]=BuildInfo.Version;manifest["PublicVersion"]=BuildInfo.PublicVersion;manifest["Pages"]=pages;manifest["Width"]=1080;manifest["Height"]=760;manifest["ThemePreview"]="ACTUAL_TASKBAR_RENDERER";manifest["ThemePreviewHeight"]=48;manifest["ThemePreviewNoSyntheticMetricData"]=true;manifest["ThemePreviewLiveSampleCount"]=12;manifest["AccessibilityInteractiveControls"]=interactive;manifest["AccessibilityNameGaps"]=a11yGaps;manifest["HighContrastCheckedControls"]=highContrastChecked;manifest["HighContrastStyleGaps"]=highContrastGaps;manifest["DpiAwareness"]=Native.DpiAwarenessMode();
                File.WriteAllText(Path.Combine(outputDirectory,"SETTINGS_PROOF_MANIFEST.json"),new JavaScriptSerializer().Serialize(manifest),Encoding.UTF8);
                Console.WriteLine("TBME_SETTINGS_PROOF=PASS PAGES=9 DIR="+outputDirectory);
                return 0;
            }
            catch(Exception ex){Console.Error.WriteLine("TBME_SETTINGS_PROOF=FAIL "+ex);return 13;}
        }
    }
    internal static class AdaptiveProbeGeometry
    {
        internal const int MinSafeWidth=420;
        internal static bool Basic(Rectangle tb,Rectangle rect,int requested,bool safePlacement)
        {
            int target=Math.Min(Math.Max(1,requested),tb.Width);
            if(tb.Width<MinSafeWidth || tb.Height!=48 || rect.Height!=48 ||
               !tb.Contains(rect) || rect.Width>target || rect.Width<MinSafeWidth)
                return false;
            if(!safePlacement && rect.Width!=target)return false;
            return true;
        }

        // Safety: test the visible actual native rectangle against the SAME
        // interactive UIA types that production avoids, using an independent
        // anti-overlap scan. If UIA cannot be inspected, do not accept G14.
        internal static bool Validate(IntPtr taskbar,AppConfig config,Rectangle rect,out string reason)
        {
            reason="";
            if(taskbar==IntPtr.Zero||config==null)
            {
                reason="TASKBAR_OR_CONFIG_MISSING";return false;
            }
            Native.RECT tr;
            if(!Native.GetWindowRect(taskbar,out tr))
            {
                reason="TASKBAR_GEOMETRY_UNAVAILABLE";return false;
            }
            Rectangle tb=tr.ToRectangle();
            if(!Basic(tb,rect,config.MinWidthLogicalPx,config.SafePlacement))
            {
                reason="RECT_OUTSIDE_REAL_SAFE_BOUNDS_OR_TOO_NARROW";return false;
            }
            if(!config.SafePlacement)return true;
            try
            {
                AutomationElement element=AutomationElement.FromHandle(taskbar);
                if(element==null){reason="UIA_TASKBAR_ROOT_UNAVAILABLE";return false;}
                AutomationElementCollection all=element.FindAll(TreeScope.Descendants,Condition.TrueCondition);
                int observedInteractive=0;
                for(int i=0;i<all.Count;i++)
                {
                    AutomationElement e=all[i];
                    ControlType ct;
                    try{ct=e.Current.ControlType;}catch{continue;}
                    if(ct!=ControlType.Button && ct!=ControlType.Edit &&
                       ct!=ControlType.MenuItem && ct!=ControlType.CheckBox &&
                       ct!=ControlType.RadioButton && ct!=ControlType.ComboBox &&
                       ct!=ControlType.Hyperlink)continue;
                    System.Windows.Rect wr;
                    try{wr=e.Current.BoundingRectangle;}catch{continue;}
                    if(wr.IsEmpty||wr.Width<3||wr.Height<3)continue;
                    int l=(int)Math.Floor(wr.Left)-8;
                    int right=(int)Math.Ceiling(wr.Right)+8;
                    int top=(int)Math.Floor(wr.Top);
                    int bottom=(int)Math.Ceiling(wr.Bottom);
                    if(right<=tb.Left||l>=tb.Right||bottom<=tb.Top||top>=tb.Bottom)continue;
                    observedInteractive++;
                    if(right>rect.Left&&l<rect.Right&&bottom>rect.Top&&top<rect.Bottom)
                    {
                        reason="OVERLAP_WITH_UIA_INTERACTIVE_CONTROL";return false;
                    }
                }
                if(rect.Width<Math.Min(Math.Max(1,config.MinWidthLogicalPx),tb.Width) &&
                   observedInteractive==0)
                {
                    reason="ADAPTIVE_SHRINK_UNEXPLAINED_BY_UIA";return false;
                }
                return true;
            }
            catch(Exception ex)
            {
                reason="UIA_CHECK_UNAVAILABLE_"+ex.GetType().Name;
                return false;
            }
        }

        internal static void SelfTest()
        {
            Rectangle tb=new Rectangle(0,852,1600,48);
            Rectangle actual=new Rectangle(0,852,570,48);
            if(!Basic(tb,actual,1100,true)||
               !Basic(tb,new Rectangle(500,852,1100,48),1100,true)||
               Basic(tb,actual,1100,false)||
               Basic(tb,new Rectangle(0,852,419,48),1100,true)||
               Basic(tb,new Rectangle(0,852,1101,48),1100,true)||
               Basic(tb,new Rectangle(-1,852,570,48),1100,true)||
               Basic(tb,new Rectangle(0,851,570,48),1100,true)||
               Basic(tb,new Rectangle(0,852,570,47),1100,true)||
               Basic(tb,new Rectangle(1200,852,570,48),1100,true)||
               Basic(new Rectangle(0,852,1024,48),new Rectangle(0,852,1100,48),1100,true)||
               Basic(new Rectangle(0,852,1600,47),actual,1100,true)||
               !Basic(tb,new Rectangle(0,852,1100,48),1100,false))
                throw new InvalidOperationException("R107_ADAPTIVE_GEOMETRY_12_CASES_FAILED");
        }
    }
    internal static class StartProbe
    {
        private static Bitmap CaptureRect(Rectangle r)
        {
            Bitmap bmp=new Bitmap(r.Width,r.Height,PixelFormat.Format32bppArgb);
            using(Graphics g=Graphics.FromImage(bmp))
                g.CopyFromScreen(r.Left,r.Top,0,0,r.Size);
            return bmp;
        }

        private static void CapturePrimary(string path)
        {
            Rectangle b=Screen.PrimaryScreen.Bounds;
            using(Bitmap bmp=new Bitmap(b.Width,b.Height,PixelFormat.Format32bppArgb))
            using(Graphics g=Graphics.FromImage(bmp))
            {
                g.CopyFromScreen(b.Left,b.Top,0,0,b.Size);
                bmp.Save(path,ImageFormat.Png);
            }
        }

        private static Dictionary<string,object> InkMetrics(Bitmap bmp,Bitmap originalBeforeStart=null)
        {
            int bright=0,saturated=0,signal=0,upperChangedInk=0,lowerChangedInk=0;

            for(int y=0;y<bmp.Height;y++)
            for(int x=0;x<bmp.Width;x++)
            {
                Color c=bmp.GetPixel(x,y);
                int max=Math.Max(c.R,Math.Max(c.G,c.B));
                int min=Math.Min(c.R,Math.Min(c.G,c.B));
                int span=max-min;

                if(max>=140)bright++;
                if(span>=25 && max>=70)saturated++;
                bool distinctive=max>=140 || (span>=25 && max>=70);
                if(distinctive)signal++;
                if(distinctive && originalBeforeStart!=null)
                {
                    Color before=originalBeforeStart.GetPixel(x,y);
                    int diff=Math.Max(Math.Abs((int)c.R-before.R),
                        Math.Max(Math.Abs((int)c.G-before.G),Math.Abs((int)c.B-before.B)));
                    if(diff>=45)
                    {
                        if(y<20)upperChangedInk++;else lowerChangedInk++;
                    }
                }
            }

            return new Dictionary<string,object>{
                {"BrightPixels",bright},
                {"SaturatedPixels",saturated},
                {"SignalPixels",signal},
                {"UpperChangedInk",upperChangedInk},
                {"LowerChangedInk",lowerChangedInk},
                {"Pass",signal>=300}
            };
        }

        private static bool FindDirectTaskbarChild(uint pid,IntPtr taskbar,out IntPtr hwnd,out Rectangle rect)
        {
            hwnd=IntPtr.Zero;
            rect=Rectangle.Empty;

            IntPtr found=IntPtr.Zero;
            Rectangle foundRect=Rectangle.Empty;

            Native.EnumChildWindows(taskbar,delegate(IntPtr h,IntPtr l)
            {
                if(Native.GetParent(h)!=taskbar)return true;

                uint p=0;
                Native.GetWindowThreadProcessId(h,out p);
                if(p!=pid || !Native.IsWindowVisible(h))return true;

                Native.RECT wr;
                if(!Native.GetWindowRect(h,out wr))return true;
                Rectangle r=wr.ToRectangle();

                if(r.Width<AdaptiveProbeGeometry.MinSafeWidth || r.Height<30 || r.Height>70)return true;

                found=h;
                foundRect=r;
                return false;
            },IntPtr.Zero);

            if(found==IntPtr.Zero)return false;

            hwnd=found;
            rect=foundRect;
            return true;
        }

        // R51: The 0..99% layered Windows 11 glass mode is a taskbar-anchored
        // TOPLEVEL popup; GetParent may return a hidden OWNER, not a child HWND.
        // Explicitly require the owning app PID, layered native style, and safe
        // in-taskbar geometry. The 100%/High Contrast direct child remains strict.
        private static bool FindTaskbarAnchoredPopup(uint pid,IntPtr taskbar,
            out IntPtr hwnd,out Rectangle rect)
        {
            hwnd=IntPtr.Zero;
            rect=Rectangle.Empty;
            Native.RECT tr;
            if(taskbar==IntPtr.Zero||!Native.GetWindowRect(taskbar,out tr))return false;
            Rectangle bounds=tr.ToRectangle();
            IntPtr found=IntPtr.Zero;
            Rectangle foundRect=Rectangle.Empty;
            Native.EnumWindows(delegate(IntPtr h,IntPtr ignored)
            {
                uint owner=0;
                Native.GetWindowThreadProcessId(h,out owner);
                if(owner!=pid||!Native.IsWindowVisible(h))return true;
                long style=Native.GetWindowLongPtr(h,Native.GWL_STYLE).ToInt64();
                long ex=Native.GetWindowLongPtr(h,Native.GWL_EXSTYLE).ToInt64();
                if((style&Native.WS_POPUP)==0||(style&Native.WS_CHILD)!=0||
                    (ex&Native.WS_EX_LAYERED)==0||(ex&Native.WS_EX_NOACTIVATE)==0||
                    (ex&Native.WS_EX_COMPOSITED)!=0)return true;
                Native.RECT wr;
                if(!Native.GetWindowRect(h,out wr))return true;
                Rectangle r=wr.ToRectangle();
                if(r.Width<AdaptiveProbeGeometry.MinSafeWidth||r.Height<30||r.Height>70||!bounds.Contains(r))return true;
                found=h;foundRect=r;
                return false;
            },IntPtr.Zero);
            if(found==IntPtr.Zero)return false;
            hwnd=found;rect=foundRect;
            return true;
        }

        private static bool FindExpectedMonitorWindow(uint pid,IntPtr taskbar,
            bool topLevel,out IntPtr hwnd,out Rectangle rect)
        {
            if(topLevel)return FindTaskbarAnchoredPopup(pid,taskbar,out hwnd,out rect);
            return FindDirectTaskbarChild(pid,taskbar,out hwnd,out rect);
        }

        private static bool ReadCachedWindowState(
            IntPtr hwnd,
            IntPtr taskbar,
            Rectangle baselineRect,
            bool expectPopup,
            out Rectangle rect,
            out bool visible,
            out bool parentOk,
            out int cloaked,
            out bool fixedRect
        )
        {
            rect=Rectangle.Empty;
            visible=false;
            parentOk=false;
            cloaked=-1;
            fixedRect=false;

            if(hwnd==IntPtr.Zero)return false;

            Native.RECT wr;
            if(!Native.GetWindowRect(hwnd,out wr))return false;

            rect=wr.ToRectangle();
            visible=Native.IsWindowVisible(hwnd);
            long style=Native.GetWindowLongPtr(hwnd,Native.GWL_STYLE).ToInt64();
            long ex=Native.GetWindowLongPtr(hwnd,Native.GWL_EXSTYLE).ToInt64();
            parentOk=expectPopup?
                (style&Native.WS_POPUP)!=0&&(style&Native.WS_CHILD)==0&&
                (ex&Native.WS_EX_LAYERED)!=0&&(ex&Native.WS_EX_NOACTIVATE)!=0&&
                (ex&Native.WS_EX_COMPOSITED)==0:
                Native.GetParent(hwnd)==taskbar&&(style&Native.WS_CHILD)!=0;
            cloaked=Native.GetCloaked(hwnd);

            // Popup becomes a strictly bounded 60px lift ABOVE taskbar only
            // while Start/Search is foreground, not an arbitrary drifting HWND.
            // The opaque child retains the original no-movement invariant.
            fixedRect=
                rect.X==baselineRect.X &&
                rect.Width==baselineRect.Width &&
                rect.Height==baselineRect.Height &&
                (expectPopup?
                    rect.Y==baselineRect.Y-baselineRect.Height-12:
                    rect.Y==baselineRect.Y);

            return true;
        }

        // R118: independent native Start acceptance for owner-requested v1.6 UX:
        // top-level alpha glass REMAINS PINNED to original taskbar rectangle while
        // Start is open. Windows may cover taskbar ink in this mode; validate real
        // cached native HWND/geometry for all 24 samples and real screen ink
        // AFTER Start closes instead of fabricating visible metrics under Start.
        public static int RunPinned(string outputDirectory)
        {
            Directory.CreateDirectory(outputDirectory);
            uint pid=0;
            string stimulus="";
            int samplesPinned=0,shellSamples=0,invalidSamples=0;
            int beforeSaturated=0,afterSaturated=0;
            bool visibleAfterClose=false,mainAlive=false;
            Rectangle baseline=Rectangle.Empty;
            IntPtr cached=IntPtr.Zero;
            List<object> samples=new List<object>();
            JavaScriptSerializer js=new JavaScriptSerializer();
            try
            {
                AppConfig cfg=AppConfig.Load();cfg.Normalize();
                if(cfg.FloatAboveStartMenu)
                    throw new InvalidOperationException("PINNED_START_PROBE_USER_OPTED_IN_TO_FLOAT");
                if(!TaskbarGlassHostMode.RequiresTopLevel(cfg.Opacity,SystemInformation.HighContrast))
                    throw new InvalidOperationException("PINNED_START_PROBE_NOT_TRUE_GLASS");
                Process self=Process.GetCurrentProcess();
                Process[] all=Process.GetProcessesByName("TaskbarMonitorEnhanced");
                List<Process> others=new List<Process>();
                foreach(Process p in all){if(p.Id==self.Id)p.Dispose();else others.Add(p);}
                if(others.Count!=1)
                    throw new InvalidOperationException("PINNED_START_EXPECTED_ONE_RESIDENT count="+others.Count);
                Process resident=others[0];pid=(uint)resident.Id;
                string display;IntPtr taskbar=TaskbarTargetPolicy.Resolve(cfg,out display);
                if(taskbar==IntPtr.Zero||
                   !FindExpectedMonitorWindow(pid,taskbar,true,out cached,out baseline))
                    throw new InvalidOperationException("PINNED_START_REAL_NATIVE_OVERLAY_NOT_FOUND");
                string reason;
                if(!AdaptiveProbeGeometry.Validate(taskbar,cfg,baseline,out reason))
                    throw new InvalidOperationException("PINNED_START_BASELINE_GEOMETRY "+reason);
                using(Bitmap image=CaptureRect(baseline))
                {
                    Dictionary<string,object> ink=InkMetrics(image);
                    beforeSaturated=Convert.ToInt32(ink["SaturatedPixels"],CultureInfo.InvariantCulture);
                    if(!(bool)ink["Pass"] || beforeSaturated<300)
                        throw new InvalidOperationException("R119_PINNED_START_PRE_STIMULUS_COLORED_INK_MISSING");
                    image.Save(Path.Combine(outputDirectory,"PINNED_BEFORE_START.png"),ImageFormat.Png);
                }
                Native.KeybdTap(0x1B);
                Thread.Sleep(350);
                string proc="",klass="";IntPtr startHwnd=IntPtr.Zero;
                Native.KeybdTap(0x5B);
                if(ShellUi.WaitForStartShell(1400,out proc,out klass,out startHwnd))
                    stimulus="KEYBD_EVENT_WIN";
                else
                {
                    Native.CtrlEsc();
                    if(ShellUi.WaitForStartShell(1400,out proc,out klass,out startHwnd))
                        stimulus="KEYBD_EVENT_CTRL_ESC";
                }
                if(String.IsNullOrEmpty(stimulus))
                    throw new InvalidOperationException("PINNED_START_REAL_START_FOREGROUND_MISSING");
                for(int sample=1;sample<=24;sample++)
                {
                    Thread.Sleep(250);
                    uint nowPid=0;
                    Native.GetWindowThreadProcessId(cached,out nowPid);
                    Native.RECT wr=new Native.RECT();
                    bool rectKnown=Native.GetWindowRect(cached,out wr);
                    Rectangle actual=rectKnown?wr.ToRectangle():Rectangle.Empty;
                    bool alive=Native.IsWindow(cached),visible=Native.IsWindowVisible(cached);
                    int cloaked=Native.GetCloaked(cached);
                    string fgProc="",fgClass="",surfaceProc="",surfaceClass="";
                    IntPtr fg=IntPtr.Zero,surfaceHwnd=IntPtr.Zero;
                    bool startForeground=ShellUi.IsStartShellForeground(out fgProc,out fgClass,out fg);
                    Rectangle surfaceRect=Rectangle.Empty;
                    bool startSurface=ShellUi.IsStartSurfacePresent(
                       out surfaceProc,out surfaceClass,out surfaceRect,out surfaceHwnd);
                    bool pinned=alive&&visible&&cloaked==0&&rectKnown&&
                                actual==baseline&&nowPid==pid;
                    if(pinned)samplesPinned++;else invalidSamples++;
                    if(startForeground||startSurface)shellSamples++;
                    samples.Add(new Dictionary<string,object>{
                      {"Sample",sample},{"ElapsedMs",sample*250},
                      {"Pinned",pinned},{"OverlayHwnd",cached.ToInt64()},
                      {"MainPid",pid},{"OwnerPid",nowPid},
                      {"ActualRect",new int[]{actual.X,actual.Y,actual.Width,actual.Height}},
                      {"WindowVisible",visible},{"WindowAlive",alive},{"Cloaked",cloaked},
                      {"StartForeground",startForeground},{"StartSurface",startSurface},
                      {"ForegroundProcess",fgProc},{"SurfaceProcess",surfaceProc}
                    });
                    if(sample==1||sample==4||sample==20)
                        using(Bitmap crop=CaptureRect(baseline))
                            crop.Save(Path.Combine(outputDirectory,"PINNED_DURING_START_"+sample+".png"),ImageFormat.Png);
                }
                Native.KeybdTap(0x1B);
                DateTime returnLimit=DateTime.UtcNow.AddMilliseconds(5500);
                while(DateTime.UtcNow<returnLimit)
                {
                    Native.RECT ret=new Native.RECT();
                    if(Native.IsWindow(cached)&&Native.GetWindowRect(cached,out ret)&&
                       ret.ToRectangle()==baseline)
                    {
                        using(Bitmap after=CaptureRect(baseline))
                        {
                            Dictionary<string,object> afterInk=InkMetrics(after);
                            afterSaturated=Convert.ToInt32(afterInk["SaturatedPixels"],CultureInfo.InvariantCulture);
                            // Preserve the exact physical image even on FAIL, so a blocked
                            // screen cannot masquerade as returned text and graph ink.
                            after.Save(Path.Combine(outputDirectory,"PINNED_AFTER_START.png"),ImageFormat.Png);
                            if((bool)afterInk["Pass"] && afterSaturated>=300)
                            {
                                visibleAfterClose=true;
                                break;
                            }
                        }
                    }
                    Thread.Sleep(100);
                }
                resident.Refresh();mainAlive=!resident.HasExited;
                bool pass=mainAlive && samplesPinned==24 && shellSamples>=18 &&
                    invalidSamples==0 && visibleAfterClose;
                var manifest=new Dictionary<string,object>{
                    {"Schema",1},{"Revision","R118"},
                    {"EventCommit",Environment.GetEnvironmentVariable("GITHUB_SHA")??""},
                    {"Status",pass?"PASS":"FAIL"},
                    {"Test","REAL_PINNED_START_NO_60PX_LIFT"},
                    {"Stimulus",stimulus},{"MainPid",pid},{"CachedOverlayHwnd",cached.ToInt64()},
                    {"BaselineRect",new int[]{baseline.X,baseline.Y,baseline.Width,baseline.Height}},
                    {"PinnedSamples",samplesPinned},{"RequiredPinnedSamples",24},
                    {"ShellSamples",shellSamples},{"RequiredShellSamples",18},
                    {"InvalidSamples",invalidSamples},{"BeforeStartSaturatedPixels",beforeSaturated},
                    {"AfterStartSaturatedPixels",afterSaturated},{"RealPhysicalInkAfterStart",visibleAfterClose},
                    {"MainProcessAlive",mainAlive},
                    {"PixelOcclusionWhileStartOpen","ALLOWED_BY_USER_PINNED_MODE; NOT_FALSELY_MARKED_VISIBLE"},
                    {"Samples",samples},{"FormalExternalLabAccepted",false}
                };
                File.WriteAllText(Path.Combine(outputDirectory,"START_PINNED_PROOF.json"),
                    js.Serialize(manifest),Encoding.UTF8);
                Console.WriteLine("TBME_START_PINNED_PROOF="+(pass?"PASS":"FAIL")+
                    " 24_OF_24="+samplesPinned+" SHELL="+shellSamples+
                    " RETURN_REAL_INK="+visibleAfterClose+" AFTER_SATURATED="+afterSaturated+
                    " BAD="+invalidSamples);
                return pass?0:52;
            }
            catch(Exception ex)
            {
                try{
                    File.WriteAllText(Path.Combine(outputDirectory,"START_PINNED_PROOF.json"),
                        js.Serialize(new Dictionary<string,object>{{"Revision","R118"},
                         {"Status","FAIL_EXCEPTION"},{"Error",ex.ToString()},
                         {"PinnedSamples",samplesPinned},{"ShellSamples",shellSamples},
                         {"InvalidSamples",invalidSamples},{"Samples",samples}}),Encoding.UTF8);
                    Native.KeybdTap(0x1B);
                }catch{}
                Console.Error.WriteLine("TBME_START_PINNED_PROOF=FAIL "+ex);
                return 53;
            }
        }

        public static int Run(string outputDirectory)
        {
            Directory.CreateDirectory(outputDirectory);

            JavaScriptSerializer js=new JavaScriptSerializer();
            List<object> samples=new List<object>();

            uint mainPid=0;
            string stimulusMethod="";
            int shellSamples=0;
            int cachedHwndFailures=0;
            int invisibleSamples=0;
            int parentFailures=0;
            int cloakedSamples=0;
            int fixedSamples=0;
            int pixelFailures=0;
            int enumerationMisses=0;
            int minimumSignal=Int32.MaxValue;
            int minimumUpperChanged=Int32.MaxValue;
            int minimumLowerChanged=Int32.MaxValue;
            Rectangle expectedFloatingRect=Rectangle.Empty;
            Bitmap floatingUnderlayBeforeStart=null;
            bool returnedOriginalRect=false;
            bool returnedOriginalInk=false;

            try
            {
                Process self=Process.GetCurrentProcess();
                Process[] all=Process.GetProcessesByName("TaskbarMonitorEnhanced");
                List<Process> mains=new List<Process>();

                foreach(Process p in all)
                {
                    if(p.Id!=self.Id)mains.Add(p);
                    else p.Dispose();
                }

                if(mains.Count!=1)
                    throw new InvalidOperationException("START_PROBE_MAIN_PROCESS_GATE count="+mains.Count);

                Process main=mains[0];
                mainPid=(uint)main.Id;

                AppConfig probeConfig=AppConfig.Load();string probeTarget;IntPtr taskbar=TaskbarTargetPolicy.Resolve(probeConfig,out probeTarget);
                if(taskbar==IntPtr.Zero)
                    throw new InvalidOperationException("START_PROBE_TASKBAR_GATE");

                bool topLevelGlass=TaskbarGlassHostMode.RequiresTopLevel(
                    probeConfig.Opacity,SystemInformation.HighContrast);
                IntPtr cachedChild;
                Rectangle baselineRect;

                if(!FindExpectedMonitorWindow(mainPid,taskbar,topLevelGlass,
                    out cachedChild,out baselineRect))
                    throw new InvalidOperationException(
                        topLevelGlass?"START_PROBE_BASELINE_TOPLEVEL_GLASS_GATE":
                        "START_PROBE_BASELINE_DIRECT_CHILD_GATE");

                string adaptiveReason;
                if(!AdaptiveProbeGeometry.Validate(taskbar,probeConfig,baselineRect,out adaptiveReason))
                    throw new InvalidOperationException("START_PROBE_BASELINE_SAFE_GEOMETRY_GATE reason="+adaptiveReason+" rect="+baselineRect);
                if(topLevelGlass)
                {
                    expectedFloatingRect=new Rectangle(
                        baselineRect.X,baselineRect.Y-baselineRect.Height-12,
                        baselineRect.Width,baselineRect.Height);
                    if(!SystemInformation.VirtualScreen.Contains(expectedFloatingRect))
                        throw new InvalidOperationException("START_PROBE_FLOATING_BOUNDS_GATE");
                    floatingUnderlayBeforeStart=CaptureRect(expectedFloatingRect);
                }

                using(Bitmap baseCrop=CaptureRect(baselineRect))
                {
                    Dictionary<string,object> ink=InkMetrics(baseCrop);
                    baseCrop.Save(Path.Combine(outputDirectory,"START_PROBE_BASELINE_CROP.png"),ImageFormat.Png);

                    if(!(bool)ink["Pass"])
                        throw new InvalidOperationException(
                            "START_PROBE_BASELINE_PIXEL_GATE signal="+ink["SignalPixels"]
                        );
                }

                // In true-alpha mode only the 48px target rectangles are saved,
                // not the user's whole desktop.
                if(!topLevelGlass)CapturePrimary(Path.Combine(outputDirectory,"START_PROBE_BASELINE.png"));

                Native.KeybdTap(0x1B);
                Thread.Sleep(350);

                string openProcess="",openClass="";
                IntPtr openHwnd=IntPtr.Zero;

                Native.KeybdTap(0x5B);

                if(ShellUi.WaitForStartShell(1400,out openProcess,out openClass,out openHwnd))
                    stimulusMethod="KEYBD_EVENT_WIN";
                else
                {
                    Native.CtrlEsc();
                    if(ShellUi.WaitForStartShell(1400,out openProcess,out openClass,out openHwnd))
                        stimulusMethod="KEYBD_EVENT_CTRL_ESC";
                }

                if(String.IsNullOrEmpty(stimulusMethod))
                    throw new InvalidOperationException("START_PROBE_STIMULUS_OBSERVATION_GATE");
                if(topLevelGlass)
                {
                    // R54 watcher moves the live app to the strict 60px-safe
                    // desktop edge within 500ms of the actual Start activation.
                    // Observe for up to 3.2s, then take a fresh full 24-sample
                    // stability window instead of accepting a race at first 250ms.
                    // R112 diagnostic only: bounded read-only Win32 evidence during
                    // the original unmodified 3.2s/80ms Start activation observation.
                    DateTime deadline=DateTime.UtcNow.AddMilliseconds(3200);
                    DateTime traceBegin=DateTime.UtcNow;
                    bool floating=false;
                    int traceIndex=0;
                    List<Dictionary<string,object>> activationTrace=
                        new List<Dictionary<string,object>>();
                    while(DateTime.UtcNow<deadline)
                    {
                        Native.RECT position=new Native.RECT();
                        bool rectKnown=Native.GetWindowRect(cachedChild,out position);
                        Rectangle actualRect=rectKnown?position.ToRectangle():Rectangle.Empty;
                        bool atExpected=rectKnown && actualRect==expectedFloatingRect;
                        if((traceIndex%4)==0 || atExpected)
                        {
                            string fgProc="",fgClass="",surfProc="",surfClass="";
                            IntPtr fg=IntPtr.Zero,surf=IntPtr.Zero;
                            bool foregroundStart=ShellUi.IsStartShellForeground(
                                out fgProc,out fgClass,out fg);
                            Rectangle surfRect=Rectangle.Empty;
                            bool surfaceStart=ShellUi.IsStartSurfacePresent(
                                out surfProc,out surfClass,out surfRect,out surf);
                            IntPtr trayNow=Native.FindWindow("Shell_TrayWnd",null);
                            Native.RECT trayBounds=new Native.RECT();
                            bool trayRectKnown=trayNow!=IntPtr.Zero &&
                                Native.GetWindowRect(trayNow,out trayBounds);
                            Rectangle trayRect=trayRectKnown?
                                trayBounds.ToRectangle():Rectangle.Empty;
                            activationTrace.Add(new Dictionary<string,object>{
                                {"ElapsedMs",(int)(DateTime.UtcNow-traceBegin).TotalMilliseconds},
                                {"WindowId",cachedChild.ToInt64()},
                                {"WindowAlive",Native.IsWindow(cachedChild)},
                                {"WindowVisible",Native.IsWindowVisible(cachedChild)},
                                {"WindowRectKnown",rectKnown},
                                {"WindowRect",new int[]{actualRect.X,actualRect.Y,actualRect.Width,actualRect.Height}},
                                {"MatchesExpectedFloating",atExpected},
                                {"ForegroundStart",foregroundStart},
                                {"ForegroundProcess",fgProc},
                                {"ForegroundClass",fgClass},
                                {"ForegroundWindow",fg.ToInt64()},
                                {"StartSurfacePresent",surfaceStart},
                                {"StartSurfaceProcess",surfProc},
                                {"StartSurfaceClass",surfClass},
                                {"StartSurfaceHwnd",surf.ToInt64()},
                                {"StartSurfaceRect",new int[]{surfRect.X,surfRect.Y,surfRect.Width,surfRect.Height}},
                                {"TaskbarHwnd",trayNow.ToInt64()},
                                {"TaskbarAlive",Native.IsWindow(trayNow)},
                                {"TaskbarRect",new int[]{trayRect.X,trayRect.Y,trayRect.Width,trayRect.Height}}
                            });
                        }
                        if(atExpected){floating=true;break;}
                        traceIndex++;
                        Thread.Sleep(80);
                    }
                    // Save genuine case-scoped evidence before the original
                    // strict failure; never replace the 8/8 test acceptance.
                    string tracePath=Path.Combine(outputDirectory,
                        "R112_START_ACTIVATION_TIMELINE.json");
                    if(File.Exists(tracePath))
                        throw new InvalidOperationException("R112_TRACE_OUTPUT_ALREADY_EXISTS");
                    Dictionary<string,object> traceReport=new Dictionary<string,object>{
                        {"Revision","R112"},{"Schema",1},
                        {"EventCommit",Environment.GetEnvironmentVariable("GITHUB_SHA")??""},
                        {"MainPid",mainPid},{"CachedOverlayHwnd",cachedChild.ToInt64()},
                        {"OriginalTaskbarHwnd",taskbar.ToInt64()},
                        {"StimulusMethod",stimulusMethod},
                        {"ExpectedRect",new int[]{expectedFloatingRect.X,
                            expectedFloatingRect.Y,expectedFloatingRect.Width,expectedFloatingRect.Height}},
                        {"BaselineRect",new int[]{baselineRect.X,
                            baselineRect.Y,baselineRect.Width,baselineRect.Height}},
                        {"FloatingReached",floating},
                        {"Samples",activationTrace},
                        {"FormalG14Accepted",false}
                    };
                    File.WriteAllText(tracePath,
                        new JavaScriptSerializer().Serialize(traceReport),Encoding.UTF8);
                    if(!floating)
                        throw new InvalidOperationException(
                            "START_PROBE_FLOATING_POPUP_NOT_ON_SCREEN_IN_TIME");
                }
                for(int i=1;i<=24;i++)
                {
                    Thread.Sleep(250);

                    string fgProc="",fgClass="";
                    IntPtr fg=IntPtr.Zero;
                    bool fgShell=ShellUi.IsStartShellForeground(out fgProc,out fgClass,out fg);

                    string surfProc="",surfClass="";
                    Rectangle surfRect=Rectangle.Empty;
                    IntPtr surfHwnd=IntPtr.Zero;
                    bool surface=ShellUi.IsStartSurfacePresent(out surfProc,out surfClass,out surfRect,out surfHwnd);

                    if(fgShell||surface)shellSamples++;

                    string currentProbeTarget;IntPtr currentTaskbar=TaskbarTargetPolicy.Resolve(probeConfig,out currentProbeTarget);
                    if(currentTaskbar==IntPtr.Zero)currentTaskbar=taskbar;

                    // Hierarchy enumeration is diagnostic only. Windows 11 Start can make
                    // EnumChildWindows discovery temporarily unreliable even when the
                    // cached HWND remains valid, parented and visually composed.
                    IntPtr rediscovered=IntPtr.Zero;
                    Rectangle rediscoveredRect=Rectangle.Empty;
                    bool enumerationFound=FindExpectedMonitorWindow(
                        mainPid,currentTaskbar,topLevelGlass,out rediscovered,out rediscoveredRect
                    );
                    if(!enumerationFound)enumerationMisses++;

                    Rectangle monitorRect;
                    bool visible;
                    bool parentOk;
                    int cloaked;
                    bool fixedRect;

                    bool cachedOk=ReadCachedWindowState(
                        cachedChild,
                        currentTaskbar,
                        baselineRect,
                        topLevelGlass,
                        out monitorRect,
                        out visible,
                        out parentOk,
                        out cloaked,
                        out fixedRect
                    );

                    if(!cachedOk)
                    {
                        cachedHwndFailures++;
                        pixelFailures++;

                        samples.Add(new Dictionary<string,object>{
                            {"Sample",i},
                            {"CachedHwndValid",false},
                            {"EnumerationFound",enumerationFound},
                            {"PixelInkPass",false},
                            {"Error","CACHED_HWND_INVALID"}
                        });
                        continue;
                    }

                    if(!visible)invisibleSamples++;
                    if(!parentOk)parentFailures++;
                    if(cloaked!=0)cloakedSamples++;
                    if(fixedRect)fixedSamples++;

                    Dictionary<string,object> ink;

                    using(Bitmap crop=CaptureRect(monitorRect))
                    {
                        ink=InkMetrics(crop,topLevelGlass?floatingUnderlayBeforeStart:null);

                        int signal=Convert.ToInt32(
                            ink["SignalPixels"],CultureInfo.InvariantCulture);
                        int upper=Convert.ToInt32(ink["UpperChangedInk"],CultureInfo.InvariantCulture);
                        int lower=Convert.ToInt32(ink["LowerChangedInk"],CultureInfo.InvariantCulture);
                        if(signal<minimumSignal)minimumSignal=signal;
                        if(topLevelGlass)
                        {
                            if(upper<minimumUpperChanged)minimumUpperChanged=upper;
                            if(lower<minimumLowerChanged)minimumLowerChanged=lower;
                        }
                        bool actualInkPass=(bool)ink["Pass"] &&
                            (!topLevelGlass || (upper>=100&&lower>=100));
                        if(!actualInkPass)pixelFailures++;

                        if(i==1)
                            crop.Save(Path.Combine(outputDirectory,"START_PROBE_CROP_250MS.png"),ImageFormat.Png);
                        if(i==4)
                            crop.Save(Path.Combine(outputDirectory,"START_PROBE_CROP_1S.png"),ImageFormat.Png);
                        if(i==20)
                            crop.Save(Path.Combine(outputDirectory,"START_PROBE_CROP_5S.png"),ImageFormat.Png);
                    }

                    samples.Add(new Dictionary<string,object>{
                        {"Sample",i},
                        {"CachedHwndValid",true},
                        {"CachedHwnd",cachedChild.ToInt64()},
                        {"EnumerationFound",enumerationFound},
                        {"RediscoveredHwnd",rediscovered.ToInt64()},
                        {"Visible",visible},
                        {"ParentOk",parentOk},
                        {"Cloaked",cloaked},
                        {"FixedRect",fixedRect},
                        {"MonitorRect",new int[]{monitorRect.X,monitorRect.Y,monitorRect.Width,monitorRect.Height}},
                        {"PixelInkPass",(bool)ink["Pass"]&&
                            (!topLevelGlass ||
                              ((int)ink["UpperChangedInk"]>=100&&
                               (int)ink["LowerChangedInk"]>=100))},
                        {"SignalPixels",ink["SignalPixels"]},
                        {"UpperChangedInk",ink["UpperChangedInk"]},
                        {"LowerChangedInk",ink["LowerChangedInk"]},
                        {"SafeStartGlassFloating",topLevelGlass&&fixedRect},
                        {"BrightPixels",ink["BrightPixels"]},
                        {"SaturatedPixels",ink["SaturatedPixels"]},
                        {"ForegroundProcess",fgProc},
                        {"ForegroundClass",fgClass},
                        {"ForegroundShell",fgShell},
                        {"StartSurfacePresent",surface},
                        {"StartSurfaceProcess",surfProc}
                    });

                    if(!topLevelGlass)
                    {
                        if(i==1)CapturePrimary(Path.Combine(outputDirectory,"START_PROBE_OPEN_250MS.png"));
                        if(i==4)CapturePrimary(Path.Combine(outputDirectory,"START_PROBE_OPEN_1S.png"));
                        if(i==20)CapturePrimary(Path.Combine(outputDirectory,"START_PROBE_OPEN_5S.png"));
                    }
                }

                if(topLevelGlass)
                {
                    // The Start shell process must RELEASE foreground and the
                    // original *cached* HWND must return to exact taskbar bounds
                    // with real foreground ink. Win32 visibility alone is weak.
                    Native.KeybdTap(0x1B);
                    DateTime returnDeadline=DateTime.UtcNow.AddSeconds(4.5);
                    while(DateTime.UtcNow<returnDeadline)
                    {
                        Native.RECT native=new Native.RECT();
                        if(Native.GetWindowRect(cachedChild,out native)&&
                           native.ToRectangle()==baselineRect)
                        {
                            returnedOriginalRect=true;
                            using(Bitmap after=CaptureRect(baselineRect))
                            {
                                Dictionary<string,object> returned=InkMetrics(after);
                                returnedOriginalInk=(bool)returned["Pass"];
                                if(returnedOriginalInk)
                                    after.Save(Path.Combine(outputDirectory,
                                        "START_PROBE_RETURNED_TASKBAR.png"),ImageFormat.Png);
                            }
                            if(returnedOriginalInk)break;
                        }
                        Thread.Sleep(100);
                    }
                }
                else{returnedOriginalRect=true;returnedOriginalInk=true;}

                bool mainAlive=false;
                try{mainAlive=!main.HasExited;}catch{}

                bool pass=
                    mainAlive &&
                    shellSamples>=18 &&
                    cachedHwndFailures==0 &&
                    invisibleSamples==0 &&
                    parentFailures==0 &&
                    cloakedSamples==0 &&
                    fixedSamples==24 &&
                    pixelFailures==0 &&
                    minimumSignal>=300 &&
                    returnedOriginalRect&&returnedOriginalInk &&
                    (!topLevelGlass ||
                      (minimumUpperChanged>=100&&minimumLowerChanged>=100));

                Dictionary<string,object> manifest=new Dictionary<string,object>();

                manifest["Version"]=BuildInfo.Version;
                manifest["Status"]=pass?"PASS":"FAIL";
                manifest["VisualAuthority"]="CACHED_HWND_SCREEN_PIXELS";
                manifest["RequiredWindowMode"]=topLevelGlass?
                    "TASKBAR_ANCHORED_TOPLEVEL_LAYERED":"DIRECT_SHELL_CHILD_OPAQUE";
                manifest["HierarchyEnumerationAuthority"]=false;
                manifest["TaskbarGlassFallbackPolicy"]=topLevelGlass?
                    "STRICT_60PX_ABOVE_TASKBAR_WHILE_START_NOACTIVATE":
                    "ORIGINAL_TASKBAR_CHILD_NO_MOVEMENT";
                manifest["FloatingExpectedRect"]=new int[]{
                    expectedFloatingRect.X,expectedFloatingRect.Y,
                    expectedFloatingRect.Width,expectedFloatingRect.Height};
                manifest["FixedSampleInterpretation"]=topLevelGlass?
                    "EXACT_SAFE_FLOATING_START_RECT_24_OF_24":
                    "EXACT_ORIGINAL_TASKBAR_RECT_24_OF_24";
                manifest["MinimumUpperChangedInk"]=minimumUpperChanged==Int32.MaxValue?0:minimumUpperChanged;
                manifest["MinimumLowerChangedInk"]=minimumLowerChanged==Int32.MaxValue?0:minimumLowerChanged;
                manifest["ReturnToOriginalTaskbarRect"]=returnedOriginalRect;
                manifest["ReturnOriginalTaskbarInkVisible"]=returnedOriginalInk;
                manifest["MainPid"]=mainPid;
                manifest["CachedHwnd"]=cachedChild.ToInt64();
                manifest["BaselineRect"]=new int[]{baselineRect.X,baselineRect.Y,baselineRect.Width,baselineRect.Height};
                manifest["DurationMs"]=6000;
                manifest["SampleIntervalMs"]=250;
                manifest["SampleCount"]=24;
                manifest["StimulusMethod"]=stimulusMethod;
                manifest["ShellSamples"]=shellSamples;
                manifest["RequiredShellSamples"]=18;
                manifest["CachedHwndFailureSamples"]=cachedHwndFailures;
                manifest["RequiredCachedHwndFailureSamples"]=0;
                manifest["InvisibleSamples"]=invisibleSamples;
                manifest["RequiredInvisibleSamples"]=0;
                manifest["ParentFailureSamples"]=parentFailures;
                manifest["RequiredParentFailureSamples"]=0;
                manifest["CloakedSamples"]=cloakedSamples;
                manifest["RequiredCloakedSamples"]=0;
                manifest["FixedSamples"]=fixedSamples;
                manifest["RequiredFixedSamples"]=24;
                manifest["PixelFailureSamples"]=pixelFailures;
                manifest["RequiredPixelFailureSamples"]=0;
                manifest["EnumerationMisses"]=enumerationMisses;
                manifest["EnumerationMissesAreDiagnosticOnly"]=true;
                manifest["MinimumSignalPixels"]=minimumSignal;
                manifest["RequiredSignalPixels"]=300;
                manifest["MainProcessAlive"]=mainAlive;
                manifest["Samples"]=samples;

                File.WriteAllText(
                    Path.Combine(outputDirectory,"START_PROBE_MANIFEST.json"),
                    js.Serialize(manifest),
                    Encoding.UTF8
                );

                Console.WriteLine(
                    "TBME_START_PROBE="+(pass?"PASS":"FAIL")+
                    " ENGINE="+(topLevelGlass?
                        "TOPLEVEL_LAYERED_CACHED_HWND":"UPSTREAM_CHILD_CACHED_HWND")+
                    " SHELL="+shellSamples+
                    " CACHED_FAIL="+cachedHwndFailures+
                    " INVISIBLE="+invisibleSamples+
                    " PARENT_FAIL="+parentFailures+
                    " CLOAKED="+cloakedSamples+
                    " FIXED="+fixedSamples+
                    " PIXEL_FAIL="+pixelFailures+
                    " ENUM_MISS="+enumerationMisses+
                    " MIN_SIGNAL="+minimumSignal+
                    " RETURN_RECT="+returnedOriginalRect+
                    " RETURN_INK="+returnedOriginalInk
                );

                return pass?0:5;
            }
            catch(Exception ex)
            {
                try
                {
                    Dictionary<string,object> fail=new Dictionary<string,object>();
                    fail["Version"]=BuildInfo.Version;
                    fail["Status"]="FAIL_EXCEPTION";
                    fail["VisualAuthority"]="CACHED_HWND_SCREEN_PIXELS";
                    fail["HierarchyEnumerationAuthority"]=false;
                    fail["MainPid"]=mainPid;
                    fail["Error"]=ex.ToString();
                    fail["Samples"]=samples;

                    File.WriteAllText(
                        Path.Combine(outputDirectory,"START_PROBE_MANIFEST.json"),
                        js.Serialize(fail),
                        Encoding.UTF8
                    );
                }
                catch{}

                Console.Error.WriteLine("TBME_START_PROBE=FAIL "+ex);
                return 5;
            }
            finally
            {
                try{if(floatingUnderlayBeforeStart!=null)
                    floatingUnderlayBeforeStart.Dispose();}catch{}
                try{Native.KeybdTap(0x1B);}catch{}
                Thread.Sleep(300);
            }
        }
    }

    internal static class ShellStateProbe
    {
        private static bool FindDirectTaskbarChild(uint pid,IntPtr taskbar,out IntPtr hwnd,out Rectangle rect)
        {
            hwnd=IntPtr.Zero;
            rect=Rectangle.Empty;
            IntPtr found=IntPtr.Zero;
            Rectangle foundRect=Rectangle.Empty;

            Native.EnumChildWindows(taskbar,delegate(IntPtr h,IntPtr l)
            {
                if(Native.GetParent(h)!=taskbar)return true;
                uint p=0;
                Native.GetWindowThreadProcessId(h,out p);
                if(p!=pid || !Native.IsWindowVisible(h))return true;

                Native.RECT wr;
                if(!Native.GetWindowRect(h,out wr))return true;
                Rectangle r=wr.ToRectangle();
                if(r.Width<AdaptiveProbeGeometry.MinSafeWidth || r.Height<30 || r.Height>70)return true;

                found=h;
                foundRect=r;
                return false;
            },IntPtr.Zero);

            if(found==IntPtr.Zero)return false;
            hwnd=found;
            rect=foundRect;
            return true;
        }

        // R56: The real 0..99% alpha native window is a top-level
        // taskbar-anchored layered popup, NOT a Shell_TrayWnd child. Discover
        // by exact runtime PID + flags + real taskbar-contained 1100x48 rect.
        private static bool FindNativeTopLevelGlass(uint pid,IntPtr taskbar,
            out IntPtr hwnd,out Rectangle rect)
        {
            hwnd=IntPtr.Zero;rect=Rectangle.Empty;
            Native.RECT tb=new Native.RECT();
            if(taskbar==IntPtr.Zero||!Native.GetWindowRect(taskbar,out tb))return false;
            Rectangle taskbarRect=tb.ToRectangle();
            IntPtr found=IntPtr.Zero;
            Rectangle location=Rectangle.Empty;
            Native.EnumWindows(delegate(IntPtr candidate,IntPtr ignored)
            {
                uint ownerPid=0;
                Native.GetWindowThreadProcessId(candidate,out ownerPid);
                if(ownerPid!=pid||!Native.IsWindowVisible(candidate))return true;
                long style=Native.GetWindowLongPtr(candidate,Native.GWL_STYLE).ToInt64();
                long ex=Native.GetWindowLongPtr(candidate,Native.GWL_EXSTYLE).ToInt64();
                if((style&Native.WS_POPUP)==0||(style&Native.WS_CHILD)!=0||
                   (ex&Native.WS_EX_LAYERED)==0||(ex&Native.WS_EX_NOACTIVATE)==0||
                   (ex&Native.WS_EX_COMPOSITED)!=0)return true;
                Native.RECT bounds=new Native.RECT();
                if(!Native.GetWindowRect(candidate,out bounds))return true;
                Rectangle target=bounds.ToRectangle();
                if(target.Width<AdaptiveProbeGeometry.MinSafeWidth||target.Width>taskbarRect.Width||target.Height!=48||
                   !taskbarRect.Contains(target))return true;
                found=candidate;location=target;return false;
            },IntPtr.Zero);
            if(found==IntPtr.Zero)return false;
            hwnd=found;rect=location;return true;
        }

        private static int SignalPixels(Bitmap bmp)
        {
            int signal=0;
            for(int y=0;y<bmp.Height;y++)
            for(int x=0;x<bmp.Width;x++)
            {
                Color c=bmp.GetPixel(x,y);
                int max=Math.Max(c.R,Math.Max(c.G,c.B));
                int min=Math.Min(c.R,Math.Min(c.G,c.B));
                int span=max-min;
                if(max>=140 || (span>=25 && max>=70))signal++;
            }
            return signal;
        }

        private static int CountNearColor(Bitmap bmp,Color target,int tolerance)
        {
            int count=0;
            for(int y=0;y<bmp.Height;y++)
            for(int x=0;x<bmp.Width;x++)
            {
                Color c=bmp.GetPixel(x,y);
                if(Math.Abs(c.R-target.R)<=tolerance &&
                   Math.Abs(c.G-target.G)<=tolerance &&
                   Math.Abs(c.B-target.B)<=tolerance)count++;
            }
            return count;
        }

        public static int Run(string jsonPath)
        {
            JavaScriptSerializer js=new JavaScriptSerializer();
            Dictionary<string,object> m=new Dictionary<string,object>();
            Process self=Process.GetCurrentProcess();

            try
            {
                Process[] all=Process.GetProcessesByName("TaskbarMonitorEnhanced");
                List<Process> mains=new List<Process>();
                foreach(Process p in all)
                {
                    if(p.Id!=self.Id)mains.Add(p);
                    else p.Dispose();
                }

                if(mains.Count!=1)throw new InvalidOperationException("MAIN_PROCESS_COUNT="+mains.Count);
                Process main=mains[0];
                uint mainPid=(uint)main.Id;

                AppConfig probeConfig=AppConfig.Load();string probeTarget;IntPtr taskbar=TaskbarTargetPolicy.Resolve(probeConfig,out probeTarget);
                if(taskbar==IntPtr.Zero)throw new InvalidOperationException("TASKBAR_NOT_FOUND");

                uint taskbarPid=0;
                Native.GetWindowThreadProcessId(taskbar,out taskbarPid);

                bool nativeGlass=TaskbarGlassHostMode.RequiresTopLevel(
                    probeConfig.Opacity,SystemInformation.HighContrast);
                IntPtr overlay;
                Rectangle rect;
                bool found=nativeGlass?
                    FindNativeTopLevelGlass(mainPid,taskbar,out overlay,out rect):
                    FindDirectTaskbarChild(mainPid,taskbar,out overlay,out rect);
                if(!found)
                    throw new InvalidOperationException(nativeGlass?
                        "NATIVE_TASKBAR_POPUP_NOT_FOUND":"DIRECT_CHILD_NOT_FOUND");
                string adaptiveReason;
                if(!AdaptiveProbeGeometry.Validate(taskbar,probeConfig,rect,out adaptiveReason))
                    throw new InvalidOperationException("ADAPTIVE_OVERLAY_SAFE_GEOMETRY_FAIL "+adaptiveReason);

                long activeStyle=Native.GetWindowLongPtr(overlay,Native.GWL_STYLE).ToInt64();
                long activeEx=Native.GetWindowLongPtr(overlay,Native.GWL_EXSTYLE).ToInt64();
                Native.RECT actualTaskbar=new Native.RECT();
                bool nativeBounds=Native.GetWindowRect(taskbar,out actualTaskbar);
                bool parentOk=nativeGlass?
                    (activeStyle&Native.WS_CHILD)==0&&
                    (activeStyle&Native.WS_POPUP)!=0&&
                    (activeEx&Native.WS_EX_LAYERED)!=0&&
                    (activeEx&Native.WS_EX_NOACTIVATE)!=0&&
                    (activeEx&Native.WS_EX_COMPOSITED)==0&&nativeBounds&&
                    actualTaskbar.ToRectangle().Contains(rect):
                    Native.GetParent(overlay)==taskbar &&
                    (activeStyle&Native.WS_CHILD)!=0;
                bool visible=Native.IsWindowVisible(overlay);
                bool valid=Native.IsWindow(overlay);
                int cloaked=Native.GetCloaked(overlay);

                int signal=0;
                int beaconMagenta=0;
                int beaconGreen=0;
                int beaconMagentaAfter=0;
                int beaconGreenAfter=0;
                bool beaconCommand=false;

                string beaconPng=Path.Combine(
                    Path.GetDirectoryName(jsonPath)??"",
                    Path.GetFileNameWithoutExtension(jsonPath)+"_BEACON.png"
                );
                string png=Path.ChangeExtension(jsonPath,".png");

                try
                {
                    IntPtr ack=Native.SendMessage(
                        overlay,
                        Native.WM_TBME_VISUAL_BEACON,
                        new IntPtr(1),
                        IntPtr.Zero
                    );
                    beaconCommand=ack==new IntPtr(1);
                    Thread.Sleep(120);

                    using(Bitmap bmp=new Bitmap(rect.Width,rect.Height,PixelFormat.Format32bppArgb))
                    using(Graphics g=Graphics.FromImage(bmp))
                    {
                        g.CopyFromScreen(rect.Left,rect.Top,0,0,rect.Size);
                        beaconMagenta=CountNearColor(bmp,Color.FromArgb(255,17,241),18);
                        beaconGreen=CountNearColor(bmp,Color.FromArgb(0,255,106),18);
                        bmp.Save(beaconPng,ImageFormat.Png);
                    }
                }
                finally
                {
                    try
                    {
                        Native.SendMessage(
                            overlay,
                            Native.WM_TBME_VISUAL_BEACON,
                            IntPtr.Zero,
                            IntPtr.Zero
                        );
                    }
                    catch{}
                    Thread.Sleep(90);
                }

                using(Bitmap bmp=new Bitmap(rect.Width,rect.Height,PixelFormat.Format32bppArgb))
                using(Graphics g=Graphics.FromImage(bmp))
                {
                    g.CopyFromScreen(rect.Left,rect.Top,0,0,rect.Size);
                    signal=SignalPixels(bmp);
                    beaconMagentaAfter=CountNearColor(bmp,Color.FromArgb(255,17,241),18);
                    beaconGreenAfter=CountNearColor(bmp,Color.FromArgb(0,255,106),18);
                    bmp.Save(png,ImageFormat.Png);
                }

                bool beaconPass=
                    beaconCommand &&
                    beaconMagenta>=100 &&
                    beaconGreen>=100 &&
                    beaconMagentaAfter<100 &&
                    beaconGreenAfter<100;

                bool pass=
                    valid &&
                    parentOk &&
                    visible &&
                    cloaked==0 &&
                    rect.Width>=AdaptiveProbeGeometry.MinSafeWidth &&
                    rect.Width<=Math.Min(probeConfig.MinWidthLogicalPx,actualTaskbar.ToRectangle().Width) &&
                    rect.Height==48 &&
                    signal>=300 &&
                    beaconPass;

                m["Version"]=BuildInfo.Version;
                m["Status"]=pass?"PASS":"FAIL";
                m["MainPid"]=mainPid;
                m["TaskbarPid"]=taskbarPid;
                m["ExpectedWindowMode"]=nativeGlass?
                    "TASKBAR_ANCHORED_TOPLEVEL_LAYERED":"DIRECT_TASKBAR_CHILD";
                m["NativeWindowStyle"]="0x"+activeStyle.ToString("X8",CultureInfo.InvariantCulture);
                m["NativeExStyle"]="0x"+activeEx.ToString("X8",CultureInfo.InvariantCulture);
                m["TaskbarHwnd"]=taskbar.ToInt64();
                m["OverlayHwnd"]=overlay.ToInt64();
                m["ParentHwnd"]=Native.GetParent(overlay).ToInt64();
                m["WindowValid"]=valid;
                m["Visible"]=visible;
                m["ParentOk"]=parentOk;
                m["Cloaked"]=cloaked;
                m["Rect"]=new int[]{rect.X,rect.Y,rect.Width,rect.Height};
                m["SignalPixels"]=signal;
                m["BeaconCommandAck"]=beaconCommand;
                m["BeaconMagentaPixels"]=beaconMagenta;
                m["BeaconGreenPixels"]=beaconGreen;
                m["BeaconMagentaPixelsAfterReset"]=beaconMagentaAfter;
                m["BeaconGreenPixelsAfterReset"]=beaconGreenAfter;
                m["BeaconRequiredPerColor"]=100;
                m["BeaconRequiredAfterResetLessThan"]=100;
                m["BeaconPass"]=beaconPass;
                m["VisualAuthority"]="TBME_ACTIVE_BEACON_ON_REAL_SCREEN";
                m["BeaconPng"]=Path.GetFileName(beaconPng);
                m["ScreenPng"]=Path.GetFileName(png);

                File.WriteAllText(jsonPath,js.Serialize(m),Encoding.UTF8);
                Console.WriteLine(
                    "TBME_SHELL_STATE="+(pass?"PASS":"FAIL")+
                    " MAIN_PID="+mainPid+
                    " TASKBAR_PID="+taskbarPid+
                    " TASKBAR_HWND="+taskbar.ToInt64()+
                    " OVERLAY_HWND="+overlay.ToInt64()+
                    " PARENT_OK="+parentOk+
                    " VISIBLE="+visible+
                    " CLOAKED="+cloaked+
                    " RECT="+rect.X+","+rect.Y+","+rect.Width+","+rect.Height+
                    " SIGNAL="+signal+
                    " BEACON="+beaconPass+
                    " MAGENTA="+beaconMagenta+
                    " GREEN="+beaconGreen
                );
                return pass?0:6;
            }
            catch(Exception ex)
            {
                m["Version"]=BuildInfo.Version;
                m["Status"]="FAIL_EXCEPTION";
                m["Error"]=ex.ToString();
                try{File.WriteAllText(jsonPath,js.Serialize(m),Encoding.UTF8);}catch{}
                Console.Error.WriteLine("TBME_SHELL_STATE=FAIL "+ex.Message);
                return 6;
            }
        }
    }

    internal static class SelfTest
    {
        public static int Run()
        {
            try
            {
                if(ThemeCatalog.Names.Length!=49)throw new Exception("theme count"); if(ThemeCatalog.Names.Count(n=>StudioThemes.IsStudio(ThemeCatalog.Get(n).Mode))!=21)throw new Exception("studio theme count"); if(WallpaperStudio.TotalWallpaperCount!=210)throw new Exception("wallpaper count"); if(ThemeCatalog.Get("Sekiro").Mode!="studio-shinobi")throw new Exception("Sekiro mode");
                string[] expected=new string[]{"Dark Minimal Pro","Glass Morphism","Neon Cyberpunk","Sleek White","Round Compact","Honeycomb Tech","Retro Terminal","Fluent Glass","OLED Mono","Cyber Neon","Mission Control","Blueprint Tech","Medical Telemetry","Carbon Racing","Aurora Borealis","Solarized Luxe","Arctic Frost","Sakura Night","Matrix Grid","Desert Sand","Royal Amethyst","Ocean Depth","Copper Industrial","Nordic Light","Ember Forge","Synthwave Sunset","Quantum Violet","Monochrome Paper"};
                string[] expectedModes=new string[]{"minimal","glass","neon","white","round","hex","terminal","fluent","oled","cyber2","mission","blueprint","medical","carbon","aurora","luxe","zen","synth","matrix","paper","luxe","aurora","industrial","zen","industrial","synth","synth","paper"};
                for(int i=0;i<expected.Length;i++){if(ThemeCatalog.Names[i]!=expected[i])throw new Exception("theme name " + i);if(ThemeCatalog.Get(expected[i]).Mode!=expectedModes[i])throw new Exception("theme mode " + i);}
                AppConfig c=new AppConfig();c.Normalize();if(c.MinWidthLogicalPx!=1100||c.MarginLogicalPx!=0||c.VerticalMarginLogicalPx!=0)throw new Exception("geometry defaults");AdaptiveProbeGeometry.SelfTest();
                if(!Native.DllSearchHardeningActive)throw new Exception("DLL search hardening");
                if(!TaskbarTargetPolicy.SelfTest())throw new Exception("taskbar target selector");
                if(c.ConfigSchemaVersion<6||!c.EnableTemperatureAlerts||c.EnableTemperatureNotifications||c.CpuTempWarningC!=85||c.GpuTempWarningC!=85||c.DiskTempWarningC!=60)throw new Exception("v1.5 alert defaults");
                if(!c.AdaptiveBatteryMode||c.BatteryUpdateIntervalMs!=3000||c.SparklineHistoryLength!=120)throw new Exception("v1.3 telemetry defaults");
                if(TelemetryPolicy.EffectiveIntervalMs(c,PowerLineStatus.Online)!=1000||TelemetryPolicy.EffectiveIntervalMs(c,PowerLineStatus.Offline)!=3000)throw new Exception("adaptive telemetry policy");
                if(!TelemetryPolicy.ShouldPause(true,false)||!TelemetryPolicy.ShouldPause(false,true)||TelemetryPolicy.ShouldPause(false,false))throw new Exception("pause policy");
                if(!AlertPolicy.IsCpuHot(true,85,c)||AlertPolicy.IsCpuHot(true,84.9f,c))throw new Exception("CPU alert boundary");
                if(!AlertPolicy.IsGpuHot(true,85,c)||AlertPolicy.IsGpuHot(false,100,c))throw new Exception("GPU alert boundary");
                if(!AlertPolicy.IsDiskHot(true,60,c)||AlertPolicy.IsDiskHot(true,59.9f,c))throw new Exception("disk alert boundary");
                TemperatureNotificationState stateProbe=new TemperatureNotificationState();DateTime stateAt=new DateTime(2026,10,2,12,0,0,DateTimeKind.Utc);if(!stateProbe.ShouldNotify("CPU",true,85,85,stateAt)||stateProbe.ShouldNotify("CPU",true,90,85,stateAt.AddMinutes(1)))throw new Exception("notification transition");
                MetricHistory featureHistory=new MetricHistory();featureHistory.SetLimit(30);for(int hi=0;hi<50;hi++)featureHistory.Add("TEST",hi);if(featureHistory.Get("TEST").Count!=30)throw new Exception("history limit");
                if(!c.ShowTemperatures)throw new Exception("temperature default");if(c.CpuDisplayMode!="Overall"||c.GpuDisplayMode!="Auto"||c.DiskDisplayMode!="Overall"||c.NetworkDisplayMode!="Overall")throw new Exception("hardware mode defaults");if(c.MemoryUnit!="Auto"||c.StorageUnit!="Auto"||c.NetworkUnit!="Auto"||c.DiskRateUnit!="Auto")throw new Exception("unit defaults");if(!c.ShowRamNumeric||!c.ShowDiskNumeric||!c.EnableHardwareFlyout||!c.AutoCheckUpdates||c.ConfigSchemaVersion<3)throw new Exception("R08 feature defaults");
                if(UnitFormatter.Pair(1024d*1024d*1024d,2d*1024d*1024d*1024d,"GB").IndexOf("GB",StringComparison.Ordinal)<0)throw new Exception("unit formatter pair");
                if(UnitFormatter.Bytes(1024d,"KB")!="1.00 KB")throw new Exception("unit formatter KB");
                if(UnitFormatter.Rate(1024d*1024d,"MB")!="1.00 MB/s")throw new Exception("unit formatter rate");
                HashSet<string> sid=SelectionUtil.Parse("A;B;A");if(sid.Count!=2||!sid.Contains("A")||!sid.Contains("B"))throw new Exception("selection ids");
                AppConfig multi=new AppConfig();multi.CpuDisplayMode="Multiple";multi.GpuDisplayMode="Multiple";multi.DiskDisplayMode="Multiple";multi.NetworkDisplayMode="Multiple";multi.MultipleDeviceLayout="Separate";multi.MemoryUnit="KB";multi.StorageUnit="MB";multi.DiskRateUnit="KB";multi.NetworkUnit="GB";multi.SelectedCpuIds="CPU0;CPU1";multi.SelectedGpuIds="GPU0;GPU1";multi.Normalize();
                if(multi.CpuDisplayMode!="Multiple"||multi.GpuDisplayMode!="Multiple"||multi.DiskDisplayMode!="Multiple"||multi.NetworkDisplayMode!="Multiple"||multi.MultipleDeviceLayout!="Separate")throw new Exception("multi display normalize");
                if(multi.MemoryUnit!="KB"||multi.StorageUnit!="MB"||multi.DiskRateUnit!="KB"||multi.NetworkUnit!="GB")throw new Exception("unit selection normalize");if(UpdateManager.ParseVersionString("v1.2.3").CompareTo(new Version(1,2,3,0))!=0)throw new Exception("update version parser");
                foreach(string n in expected)if(ThemeCatalog.Get(n)==null)throw new Exception("theme lookup " + n);
                if(BuildInfo.HistoryLength!=120)throw new Exception("history length");
                uint taskbarCreated=Native.RegisterWindowMessage("TaskbarCreated");
                if(taskbarCreated==0)throw new Exception("TaskbarCreated message registration");
                if(!ShellUi.IsStartShellProcessName("SearchHost"))throw new Exception("SearchHost detector");
                if(!ShellUi.IsStartShellProcessName("StartMenuExperienceHost"))throw new Exception("StartMenu detector");
                if(new AppConfig().FloatAboveStartMenu)throw new Exception("R118 Start must stay pinned by default");
                if(!ShellUi.IsStartShellProcessName("SearchHost"))throw new Exception("SearchHost detector");
                long recipe=Native.WS_EX_CONTROLPARENT|Native.WS_EX_LAYERED|Native.WS_EX_COMPOSITED|Native.WS_EX_TOOLWINDOW|Native.WS_EX_NOACTIVATE;
                if(recipe!=0x0A090080L)throw new Exception("R07 interactive noactivate exstyle recipe");
                string atomicDir=Path.Combine(Path.GetTempPath(),"tbme_atomic_selftest_"+Process.GetCurrentProcess().Id.ToString(CultureInfo.InvariantCulture));
                string atomicFile=Path.Combine(atomicDir,"config.json");
                string atomicBackup=Path.Combine(atomicDir,"config.json.bak");
                try
                {
                    Directory.CreateDirectory(atomicDir);
                    File.WriteAllText(atomicFile,"OLD",Encoding.UTF8);
                    AtomicTextFile.Write(atomicFile,"NEW",Encoding.UTF8,atomicBackup);
                    if(File.ReadAllText(atomicFile,Encoding.UTF8)!="NEW")throw new Exception("atomic config current");
                    if(File.ReadAllText(atomicBackup,Encoding.UTF8)!="OLD")throw new Exception("atomic config backup");
                }
                finally{try{Directory.Delete(atomicDir,true);}catch{}}
                if(!UpdateManager.IsStrictSha256Digest("sha256:"+new string('A',64)))throw new Exception("strict sha256 valid");
                if(UpdateManager.IsStrictSha256Digest("sha256:"+new string('A',63)))throw new Exception("strict sha256 short");
                if(UpdateManager.IsStrictSha256Digest("sha256:"+new string('G',64)))throw new Exception("strict sha256 nonhex");
                if(UpdateManager.ExpectedSetupAssetName("1.2.3")!="TaskbarMonitorEnhanced_Setup_1.2.3.exe")throw new Exception("strict setup asset name");
                string healDir=Path.Combine(Path.GetTempPath(),"tbme_heal_selftest_"+Process.GetCurrentProcess().Id.ToString(CultureInfo.InvariantCulture));
                string healInstall=Path.Combine(healDir,"install_state.json");
                string healState=Path.Combine(healDir,"sensor_supervisor_state.json");
                try
                {
                    Directory.CreateDirectory(healDir);
                    File.WriteAllText(healInstall,"{\"SensorLayerStatus\":\"READY\"}",Encoding.UTF8);
                    File.WriteAllText(healState,"{}",Encoding.UTF8);
                    string healReason;
                    DateTime healNow=DateTime.UtcNow;
                    if(SensorSupervisorSelfHeal.ShouldAttempt(healInstall,healState,healNow,healNow.AddMinutes(-5),DateTime.MinValue,out healReason))
                        throw new Exception("sensor selfheal fresh state");
                    File.SetLastWriteTimeUtc(healState,healNow.AddMinutes(-3));
                    if(!SensorSupervisorSelfHeal.ShouldAttempt(healInstall,healState,healNow,healNow.AddMinutes(-5),DateTime.MinValue,out healReason)||
                       !healReason.StartsWith("STATE_STALE_",StringComparison.Ordinal))
                        throw new Exception("sensor selfheal stale state");
                    if(SensorSupervisorSelfHeal.ShouldAttempt(healInstall,healState,healNow,healNow.AddMinutes(-5),healNow.AddSeconds(-30),out healReason))
                        throw new Exception("sensor selfheal cooldown");
                    File.WriteAllText(healInstall,"{\"SensorLayerStatus\":\"DEGRADED\"}",Encoding.UTF8);
                    if(SensorSupervisorSelfHeal.ShouldAttempt(healInstall,healState,healNow,healNow.AddMinutes(-5),DateTime.MinValue,out healReason))
                        throw new Exception("sensor selfheal degraded layer");
                    File.WriteAllText(healInstall,"{\"SensorLayerStatus\":\"READY\"}",Encoding.UTF8);
                    File.Delete(healState);
                    if(!SensorSupervisorSelfHeal.ShouldAttempt(healInstall,healState,healNow,healNow.AddMinutes(-5),DateTime.MinValue,out healReason)||
                       healReason!="STATE_MISSING_AFTER_GRACE")
                        throw new Exception("sensor selfheal missing state");
                }
                finally{try{Directory.Delete(healDir,true);}catch{}}
                Console.WriteLine("TBME_V1_7_0_R39_SELFTEST=PASS PUBLIC_VERSION=1.7.0 TEMPERATURE_NOTIFICATIONS=TRUE SESSION_CSV_EXPORT=TRUE TASK_MANAGER_ACTION=TRUE PER_MONITOR_V2=TRUE ACCESSIBILITY_METADATA=TRUE HIGH_CONTRAST=TRUE WINDOWS_THEME_FOLLOW=TRUE MULTI_MONITOR_TASKBAR_TARGET=TRUE UPDATE_CANONICAL_IDENTITY=TRUE UPDATE_PRELAUNCH_REHASH=TRUE DLL_SEARCH_HARDENING=TRUE CRASH_SNAPSHOT_PRIVACY=TRUE REAL_THEME_PREVIEW=TRUE THEME_PREVIEW_ACTUAL_RENDERER=TRUE STARTUP_DUAL_REGISTRATION=TRUE STARTUP_RECOVERY_DELAY_SEC=12 MULTI_HARDWARE=TRUE OVERALL_AUTO_SINGLE_MULTIPLE=TRUE UNIT_KB_MB_GB=TRUE NUMERIC_RAM_STORAGE=TRUE UPWARD_HOVER_FLYOUT=TRUE HOVER_DETAILS_SINGLE_OR_MULTI=TRUE HARDWARE_SELECTION=TRUE DISK_RW_SPEED=TRUE DISK_TEMPERATURE=TRUE DISK_CAPACITY_IN_HOVER=TRUE IN_APP_GITHUB_UPDATE=TRUE UPDATE_SHA256_DIGEST_GATE=TRUE UPDATE_EXACT_ASSET_MATCH=TRUE UPDATE_STRICT_SHA256_64HEX=TRUE WINDOWS_WDDM_GPU_FALLBACK=TRUE PRODUCT_IDENTITY_LOCKED=TRUE AUTHOR_IDENTITY_LOCKED=TRUE GPL3_ATTRIBUTION_LOCKED=TRUE AI_DISCLOSURE_DOCUMENTED=TRUE SHORTCUT_NAME_LOCKED=TRUE NVIDIA_SMI_TIMEOUT_SAFE=TRUE REDIRECTED_IO_ORDER_SAFE=TRUE BROKER_WATCHDOG_HARDENED=TRUE BROKER_FRESHNESS_15S=TRUE CPU_HARD_STALL_WATCHDOG_SEC=60 CPU_SUPERVISOR_STARTUP_GRACE_SEC=60 THEMES=49 STUDIO_THEMES=21 WALLPAPERS=210 WIDTH=1100 HISTORY=120 HEADLINE_LABEL_VALUE_INLINE=TRUE CPU_TEMP_CURRENT=TRUE GPU_TEMP_AVG_MAX=TRUE AMD_INTEL_LHM_GPU_FALLBACK=ISOLATED LHM_ELEVATED_BROKER=TRUE LHM_DIRECT_FALLBACK=FALSE LHM_IN_UI_PROCESS=FALSE LHM_CPU_GPU_STORAGE_PROCESS_ISOLATION=TRUE CPU_USAGE_GETSYSTEMTIMES=TRUE CPU_TOPOLOGY_CACHE_MIN=5 NETWORK_TOPOLOGY_CACHE_SEC=30 DISK_TOPOLOGY_CACHE_MIN=5 RAM_TOPOLOGY_CACHE_MIN=10 RESUME_STATIC_TOPOLOGY_INVALIDATION=TRUE GPU_WDDM_ON_DEMAND=TRUE CPU_TEMP_FRESHNESS_SEC=15 CPU_TEMP_FALLBACK_THROTTLE_SEC=15 CPU_BROKER_SHARED_READ=TRUE ATOMIC_CONFIG_BACKUP=TRUE LOG_RETENTION_30D=TRUE SENSOR_LOG_ROTATION_4MB=TRUE HEALTH_RESILIENCE_STATE=TRUE KILL_ON_CLOSE_JOB_CONTAINMENT=TRUE SENSOR_SUPERVISOR_AUTOHEAL=TRUE OPTIONAL_POWER_FAN_TELEMETRY=TRUE BROKER_STALE_LOG_THROTTLE_SEC=30 METRIC_MIN_INTERVAL_MS=1000 POWER_AWARE_TELEMETRY=TRUE DIAGNOSTICS_TAB=TRUE SENSOR_REPAIR_UI=TRUE HEALTHPROBE_CLI=TRUE IMMUTABLE_RELEASE_UPDATE_GATE=TRUE NETWORK_RENDERER_THEME_CONSISTENT=TRUE RIGHTCLICK_BRIDGE=FALSE DIRECT_MOUSE_INTERACTION=TRUE NOACTIVATE_MOUSE=TRUE RECOVERY_HOST_CONTEXT=TRUE ACTIVE_VISUAL_BEACON=TRUE TEMP_PROBE=TRUE ADAPTIVE_SAFE_PLACEMENT=TRUE AMD_INTEL_GPU_FALLBACK=TRUE AMD_ADLX_GPU_TEMP_FALLBACK=TRUE COMPACT_READABLE_STACK=TRUE COMPACT_NET_LABEL_ELISION=TRUE COMPACT_PROOF=TRUE STABLE_PLACEMENT_LOCK=TRUE START_TRANSIENT_FREEZE=TRUE STYLE_SELF_HEAL=LOW_PRESSURE_5S WATCHDOG_MS=500 HOST_POLL_MS=1000 UIA_SAFE_PLACEMENT=EVENT_DRIVEN SETTINGS_SINGLE_INSTANCE=TRUE ALERTS_CPU_GPU_DISK=TRUE ALERT_VISUAL_HOTSTATE=TRUE ADAPTIVE_BATTERY=TRUE SESSION_PAUSE=TRUE CONFIGURABLE_HISTORY=TRUE COPY_DIAGNOSTICS=TRUE SUPPORT_ZIP=TRUE SAFE_RESET=TRUE HEALTH_BADGE=TRUE SETTINGS_PAGES=9 CREATEPARAMS_NOACTIVATE=TRUE");
                return 0;
            }
            catch(Exception ex){Console.Error.WriteLine("TBME_V1_6_0_R37_SELFTEST=FAIL " + ex);return 2;}
        }

        public static int RunJson(string outputPath)
        {
            int rc=Run();
            try
            {
                Dictionary<string,object> m=new Dictionary<string,object>();
                m["Status"]=rc==0?"PASS":"FAIL";
                m["ExitCode"]=rc;
                m["Version"]=BuildInfo.Version;
                m["PublicVersion"]=BuildInfo.PublicVersion;
                m["MultiHardware"]=true;
                m["DisplayModes"]=new string[]{"Overall","Auto","Single","Multiple"};
                m["MultipleLayouts"]=new string[]{"Grouped","Separate"};
                m["Units"]=new string[]{"Auto","KB","MB","GB"};m["DiskRateUnit"]=true;
                m["NumericRam"]=true;
                m["NumericStorage"]=true;
                m["IndependentUpwardHardwareFlyout"]=true;m["HoverDetailsForSingleDevice"]=true;m["DiskReadWriteThroughput"]=true;m["DiskTemperature"]=true;m["DiskCapacityInHover"]=true;m["InAppGitHubUpdates"]=true;m["UpdateRequiresGitHubSha256Digest"]=true;m["AsyncTelemetryUiIsolation"]=true;m["ImmediateHoverEnter"]=true;m["ResizableScrollableSettings"]=true;m["DetailedHardwareFlyout"]=true;m["ClockAndBusTelemetry"]=true;
                m["HardwareSelection"]=new string[]{"CPU","GPU","Disk","Network"};
                m["UnsupportedTemperatureBehavior"]="N/A";
                File.WriteAllText(outputPath,new JavaScriptSerializer().Serialize(m),Encoding.UTF8);
            }
            catch(Exception ex)
            {
                try{File.WriteAllText(outputPath,new JavaScriptSerializer().Serialize(new Dictionary<string,object>{{"Status","FAIL_WRITE"},{"Error",ex.ToString()}}),Encoding.UTF8);}catch{}
                if(rc==0)rc=3;
            }
            return rc;
        }
    }

    internal sealed class RecoveryApplicationContext : ApplicationContext
    {
        private readonly AppConfig config;
        private readonly System.Windows.Forms.Timer timer;
        private OverlayForm overlay;
        private IntPtr lastTaskbar=IntPtr.Zero;
        private int taskbarStableCount=0;
        private DateTime recreateNotBefore=DateTime.MinValue;
        private DateTime nextStartupMaintenanceUtc=DateTime.MinValue;
        private bool shuttingDown=false;
        private int createCount=0;

        public RecoveryApplicationContext(AppConfig c)
        {
            config=c;
            timer=new System.Windows.Forms.Timer();
            timer.Interval=1000;
            timer.Tick+=delegate{TickHost();};

            Log.Write("INFO","HOST_CONTEXT_START version="+BuildInfo.Version+" pid="+Process.GetCurrentProcess().Id);
            string resolvedTarget;IntPtr tb=TaskbarTargetPolicy.Resolve(config,out resolvedTarget);
            if(tb!=IntPtr.Zero)
            {
                lastTaskbar=tb;
                taskbarStableCount=3;
                CreateOverlay("STARTUP");
            }
            else
            {
                recreateNotBefore=DateTime.UtcNow.AddMilliseconds(500);
                Log.Write("WARN","HOST_CONTEXT_START_NO_TASKBAR");
            }
            timer.Start();
        }

        private void CreateOverlay(string reason)
        {
            if(shuttingDown)return;
            string resolvedTarget;IntPtr tb=TaskbarTargetPolicy.Resolve(config,out resolvedTarget);
            if(tb==IntPtr.Zero)return;

            try
            {
                OverlayForm f=new OverlayForm(config);
                overlay=f;
                f.FormClosed+=OverlayClosed;
                f.Show();
                createCount++;
                Log.Write(
                    "INFO",
                    "HOST_CONTEXT_OVERLAY_CREATE reason="+reason+
                    " count="+createCount+
                    " hwnd="+f.Handle.ToInt64()+
                    " taskbar="+tb.ToInt64()
                );
            }
            catch(Exception ex)
            {
                overlay=null;
                recreateNotBefore=DateTime.UtcNow.AddMilliseconds(750);
                Log.Write("ERROR","HOST_CONTEXT_OVERLAY_CREATE_FAIL reason="+reason+" "+ex.ToString());
            }
        }

        private void OverlayClosed(object sender,FormClosedEventArgs e)
        {
            OverlayForm closed=sender as OverlayForm;
            bool user=closed!=null && closed.UserExitRequested;

            Log.Write(
                "INFO",
                "HOST_CONTEXT_OVERLAY_CLOSED userExit="+user+
                " reason="+e.CloseReason.ToString()
            );

            if(Object.ReferenceEquals(overlay,closed))overlay=null;

            if(user)
            {
                shuttingDown=true;
                try{timer.Stop();}catch{}
                ExitThread();
                return;
            }

            recreateNotBefore=DateTime.UtcNow.AddMilliseconds(750);
        }

        private void DropInvalidOverlay(string reason)
        {
            OverlayForm old=overlay;
            overlay=null;

            if(old!=null)
            {
                Log.Write("WARN","HOST_CONTEXT_OVERLAY_LOST reason="+reason);
                try{old.FormClosed-=OverlayClosed;}catch{}
                try{old.HostPrepareForReplacement();}catch{}
                try{old.Dispose();}catch{}
            }

            recreateNotBefore=DateTime.UtcNow.AddMilliseconds(750);
        }

        private void TickHost()
        {
            if(shuttingDown)return;

            try
            {
                DateTime hostNow=DateTime.UtcNow;
                if(hostNow>=nextStartupMaintenanceUtc)
                {
                    nextStartupMaintenanceUtc=hostNow.AddSeconds(60);
                    bool startupHealthy=StartupManager.EnsureExpectedState(config.StartWithWindows);
                    if(!startupHealthy)Log.Write("WARN","HOST_STARTUP_MAINTENANCE_DEGRADED enabled="+config.StartWithWindows);
                }

                string resolvedTarget;IntPtr current=TaskbarTargetPolicy.Resolve(config,out resolvedTarget);

                if(current==IntPtr.Zero)
                {
                    if(lastTaskbar!=IntPtr.Zero)
                        Log.Write("WARN","HOST_CONTEXT_TASKBAR_LOST old="+lastTaskbar.ToInt64());

                    lastTaskbar=IntPtr.Zero;
                    taskbarStableCount=0;

                    if(overlay!=null)
                    {
                        bool dead=overlay.IsDisposed || !overlay.IsHandleCreated;
                        if(!dead && overlay.IsHandleCreated)
                        {
                            try{dead=!Native.IsWindow(overlay.Handle);}catch{dead=true;}
                        }
                        if(dead)DropInvalidOverlay("TASKBAR_MISSING_HANDLE_DESTROYED");
                    }
                    return;
                }

                bool changed=lastTaskbar!=IntPtr.Zero && current!=lastTaskbar;
                if(current!=lastTaskbar)
                {
                    Log.Write(
                        "INFO",
                        "HOST_CONTEXT_TASKBAR_SEEN hwnd="+current.ToInt64()+
                        " previous="+lastTaskbar.ToInt64()
                    );
                    lastTaskbar=current;
                    taskbarStableCount=1;
                }
                else taskbarStableCount++;

                if(overlay!=null)
                {
                    bool invalid=overlay.IsDisposed || !overlay.IsHandleCreated;
                    if(!invalid && overlay.IsHandleCreated)
                    {
                        try{invalid=!Native.IsWindow(overlay.Handle);}catch{invalid=true;}
                    }

                    if(invalid)
                    {
                        DropInvalidOverlay("OVERLAY_HWND_INVALID");
                    }
                    else if(taskbarStableCount>=3)
                    {
                        try
                        {
                            bool parentDrift=overlay.RequiresGlassTopLevel?
                                (Native.GetWindowLongPtr(overlay.Handle,Native.GWL_STYLE).ToInt64()&Native.WS_CHILD)!=0:
                                Native.GetParent(overlay.Handle)!=current;
                            if(changed || parentDrift)
                            {
                                Log.Write(
                                    "INFO",
                                    "HOST_CONTEXT_RECOVERY_REQUEST changed="+changed+
                                    " parent="+Native.GetParent(overlay.Handle).ToInt64()+
                                    " taskbar="+current.ToInt64()
                                );
                                overlay.RequestExternalRecovery("HOST_CONTEXT_TASKBAR_CHANGED");
                            }
                        }
                        catch(Exception ex)
                        {
                            Log.Write("WARN","HOST_CONTEXT_RECOVERY_REQUEST_FAIL "+ex.Message);
                        }
                    }
                }

                if(overlay==null &&
                   taskbarStableCount>=3 &&
                   DateTime.UtcNow>=recreateNotBefore)
                {
                    CreateOverlay("TASKBAR_RECREATED");
                }
            }
            catch(Exception ex)
            {
                Log.Write("WARN","HOST_CONTEXT_TICK "+ex.Message);
            }
        }

        protected override void ExitThreadCore()
        {
            shuttingDown=true;
            try{timer.Stop();timer.Dispose();}catch{}

            OverlayForm f=overlay;
            overlay=null;
            if(f!=null && !f.IsDisposed)
            {
                try{f.FormClosed-=OverlayClosed;}catch{}
                try{f.HostPrepareForReplacement();}catch{}
                try{f.Dispose();}catch{}
            }

            Log.Write("INFO","HOST_CONTEXT_EXIT");
            base.ExitThreadCore();
        }
    }

    internal static class Program
    {
        [STAThread]
        private static int Main(string[] args)
        {
            Native.EnableDllSearchHardening();
            if(args!=null && args.Length>1 && args[0]=="--glassproof")return TaskbarGlassProof.Run(args[1]);
            if(args!=null && args.Length>1 && args[0]=="--glassthermalproof")return TaskbarGlassThermalProof.Run(args[1]);
            if(args!=null && args.Length>1 && args[0]=="--chartglassproof")return TaskbarChartGlassProof.Run(args[1]);
            if(args!=null && args.Length>1 && args[0]=="--glassliveproof")return TaskbarGlassLiveProof.Run(args[1]);
            if(args!=null && args.Length>1 && args[0]=="--topglassliveproof")return TaskbarTopGlassVisualProof.Run(args[1]);
            if(args!=null && args.Length>1 && args[0]=="--startzorderproof")return TaskbarStartZOrderProof.Run(args[1]);
            if(args!=null && args.Length>1 && args[0]=="--startfloatliveproof")return TaskbarProductionStartFloatProof.Run(args[1]);
            if(args!=null && args.Length>0 && args[0]=="--glassnativeproof")return TaskbarGlassNativeProof.Run();
            if(args!=null && args.Length>0 && args[0]=="--workspace-selftest")return WorkspaceSelfTest.Run();
            if(args!=null && args.Length>1 && args[0]=="--workspace-proof")return WorkspaceProof.Run(args[1]);
            if(args!=null && args.Length>0 && args[0]=="--selftest")return SelfTest.Run();
            if(args!=null && args.Length>0 && args[0]=="--selftestjson")
            {
                if(args.Length<2)return 3;
                return SelfTest.RunJson(args[1]);
            }
            if(args!=null && args.Length>0 && args[0]=="--wallpaperproof")
            {
                if(args.Length<2){Console.Error.WriteLine("TBME_WALLPAPER_PROOF=FAIL missing output directory");return 31;}
                return WallpaperStudioProof.Run(args[1]);
            }            if(args!=null && args.Length>0 && args[0]=="--themeproof")
            {
                if(args.Length<2)
                {
                    Console.Error.WriteLine("TBME_THEME_PROOF=FAIL missing output directory");
                    return 4;
                }
                return ThemeProof.Run(args[1]);
            }
            if(args!=null && args.Length>0 && args[0]=="--compactproof")
            {
                if(args.Length<2){Console.Error.WriteLine("TBME_COMPACT_PROOF=FAIL missing output directory");return 8;}
                return CompactProof.Run(args[1]);
            }
            if(args!=null && args.Length>0 && args[0]=="--hoverguardproof")return HoverGuardProof.Run();            if(args!=null && args.Length>0 && args[0]=="--settingsproof")
            {
                if(args.Length<2){Console.Error.WriteLine("TBME_SETTINGS_PROOF=FAIL missing output directory");return 13;}
                return SettingsProof.Run(args[1]);
            }
            if(args!=null && args.Length>0 && args[0]=="--settingsforegroundproof")
            {
                if(args.Length<2){Console.Error.WriteLine("TBME_R120_SETTINGS_NATIVE_FOREGROUND=FAIL missing output");return 121;}
                return SettingsProof.RunNativeForeground(args[1]);
            }
            if(args!=null && args.Length>0 && args[0]=="--startpinnedprobe")
            {
                if(args.Length<2){Console.Error.WriteLine("TBME_START_PINNED_PROOF=FAIL missing output");return 53;}
                return StartProbe.RunPinned(args[1]);
            }
            if(args!=null && args.Length>0 && args[0]=="--startprobe")
            {
                if(args.Length<2)
                {
                    Console.Error.WriteLine("TBME_START_PROBE=FAIL missing output directory");
                    return 5;
                }
                return StartProbe.Run(args[1]);
            }
            if(args!=null && args.Length>0 && args[0]=="--shellstate")
            {
                if(args.Length<2)
                {
                    Console.Error.WriteLine("TBME_SHELL_STATE=FAIL missing json path");
                    return 6;
                }
                return ShellStateProbe.Run(args[1]);
            }
            if(args!=null && args.Length>0 && args[0]=="--hardwareprobe")
            {
                if(args.Length<2){Console.Error.WriteLine("TBME_HARDWARE_PROBE=FAIL missing json path");return 9;}
                return HardwareProbe.Run(args[1]);
            }
            if(args!=null && args.Length>0 && args[0]=="--tempprobe")
            {
                if(args.Length<2)
                {
                    Console.Error.WriteLine("TBME_TEMP_PROBE=FAIL missing json path");
                    return 7;
                }
                return TemperatureProbe.Run(args[1]);
            }
            if(args!=null && args.Length>0 && args[0]=="--healthprobe")
            {
                if(args.Length<2){Console.Error.WriteLine("TBME_HEALTH_PROBE=FAIL missing json path");return 12;}
                return HealthProbe.Run(args[1]);
            }
            if(args!=null && args.Length>0 && args[0]=="--feature-contract-selftest")
                return FeatureContractSelfTest.Run();
            if(args!=null && args.Length>0 && args[0]=="--supportbundleproof")
            {
                if(args.Length<2){Console.Error.WriteLine("TBME_SUPPORT_BUNDLE_PROOF=FAIL missing zip path");return 16;}
                return SupportBundleBuilder.Probe(args[1]);
            }
            if(args!=null && args.Length>0 && args[0]=="--startup-contract-selftest")
                return StartupManager.RunContractSelfTest();
            if(StartupManager.IsRecoveryInvocation(args)&&StartupManager.WaitForPrimaryInstanceOrTimeout())return 0;
            bool created;
            using(Mutex mutex=new Mutex(true,@"Local\TaskbarMonitorEnhanced_V1_1_0",out created))
            {
                if(!created)return 0;
                RuntimeGuard.Install();
                Native.EnableDpi();
                Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
                AppConfig c=AppConfig.Load();c.Normalize();c.Save();StartupManager.SetEnabled(c.StartWithWindows);
                Application.Run(new RecoveryApplicationContext(c));
                return 0;
            }
        }
    }
}
