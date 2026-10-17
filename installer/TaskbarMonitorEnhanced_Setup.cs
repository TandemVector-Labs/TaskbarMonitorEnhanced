using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Globalization;
using System.IO.Compression;
using System.Reflection;
using System.Security.Principal;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using System.Security.AccessControl;
using System.Threading.Tasks;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Taskbar Monitor Enhanced Setup")]
[assembly: AssemblyDescription("Installer for Taskbar Monitor Enhanced")]
[assembly: AssemblyProduct("Taskbar Monitor Enhanced")]
[assembly: AssemblyCompany("Dr. Ali-Akbar Emadeddin")]
[assembly: AssemblyCopyright("Copyright © 2026 Dr. Ali-Akbar Emadeddin")]
[assembly: AssemblyVersion("1.7.8.0")]
[assembly: AssemblyFileVersion("1.7.8.0")]
[assembly: AssemblyInformationalVersion("1.7.8+r286")]

internal static partial class SetupProgram
{
    const string Product="Taskbar Monitor Enhanced";
    const string Version="1.7.8";
    const string SensorProtocolVersion="1.1.2+r21";
    const string SensorSupervisorVersion="1.3.0+r33";
    const string Publisher="Dr. Ali-Akbar Emadeddin";
    const string AppFolder="TaskbarMonitorEnhanced";
    const string UninstallKey=@"Software\Microsoft\Windows\CurrentVersion\Uninstall\TaskbarMonitorEnhanced";
    const int CompatibleSensorStateFreshSeconds=15;

    static readonly string[] RequiredResources=new string[] {
      "Payload.TaskbarMonitorEnhanced.exe",
      "Payload.TaskbarMonitorEnhanced.exe.config",
      "Payload.TaskbarMonitorEnhanced.cs",
      "Payload.StudioThemes.cs",
      "Payload.WallpaperStudio.cs",
      "Payload.TaskbarGlass.cs",
      "Payload.WorkspaceModels.cs",
      "Payload.MonitorWorkspace.cs",
      "Payload.WorkspaceSelfTest.cs",
      "Payload.TaskbarMonitorSensorBroker.exe",
      "Payload.TaskbarMonitorSensorBroker.cs",
      "Payload.TaskbarMonitorSensorSupervisor.exe",
      "Payload.TaskbarMonitorSensorSupervisor.cs",
      "Payload.TaskbarMonitorEnhanced.ico",
      "Payload.LibreHardwareMonitor.zip",
      "Payload.TBME_Setup_Elevated_Helper.ps1",
      "Payload.LICENSE",
      "Payload.README.md",
      "Payload.AUTHORS.md",
      "Payload.COPYRIGHT_AND_ATTRIBUTION.md",
      "Payload.AI_ASSISTED_DEVELOPMENT.md",
      "Payload.THIRD_PARTY_NOTICES.md",
      "Payload.RELEASE_NOTES_v1.7.8.md",
      "Payload.UPSTREAM_REFERENCE_GPL_NOTICE.md",
      "Payload.TaskbarMonitorEnhanced_Setup.cs"
    };

    static string AppRoot { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),AppFolder); } }
    static string AppExe { get { return Path.Combine(AppRoot,"TaskbarMonitorEnhanced.exe"); } }
    static string SensorResultPath { get { return Path.Combine(AppRoot,"Logs","sensor_install_result.json"); } }
    static string MainLaunchMode="PENDING";

    sealed class SensorOutcome
    {
        public string Status="UNKNOWN";
        public string Message="Hardware sensor status is unknown.";
        public bool RebootRequired=false;
        public bool IsHealthy=false;
        public string LayerVersion="";
        public string LayerMode="";
    }

    static Stream Resource(string name)
    {
        return Assembly.GetExecutingAssembly().GetManifestResourceStream(name);
    }

    static void Extract(string resource,string path)
    {
        Stream input=Resource(resource);
        if(input==null)throw new InvalidOperationException("Missing embedded resource: "+resource);
        string parent=Path.GetDirectoryName(path);
        if(!String.IsNullOrEmpty(parent))Directory.CreateDirectory(parent);
        using(input)
        using(FileStream output=File.Create(path))
            input.CopyTo(output);
    }

    static void StopProcess(string name)
    {
        try{
            foreach(Process p in Process.GetProcessesByName(name)){
                try{p.Kill();p.WaitForExit(2500);}catch{}
                try{p.Dispose();}catch{}
            }
        }catch{}
    }

    // R293: PowerShell code is transported from this immutable, embedded PE resource
    // via an in-memory command. Never elevate a .ps1 from writable Temp.
    static string Base64Utf8Argument(string value)
    {
        if(String.IsNullOrWhiteSpace(value) || value.Length>4096)
            throw new InvalidDataException("Sensor helper argument missing or too long.");
        return Convert.ToBase64String(Encoding.UTF8.GetBytes(value));
    }

    // R295: compact only transport text, not the readable embedded .ps1 source.
    // Refuse here-strings and continuation tokens that need verbatim whitespace.
    static string CompactTrustedHelperSource(string source)
    {
        if(String.IsNullOrWhiteSpace(source) ||
           source.IndexOf("@'",StringComparison.Ordinal)>=0 ||
           source.IndexOf("@\"",StringComparison.Ordinal)>=0)
            throw new InvalidDataException("Trusted sensor helper contains unsupported multiline text.");
        StringBuilder compact=new StringBuilder();
        foreach(string raw in source.Replace("\r\n","\n").Split('\n'))
        {
            string line=raw.Trim();
            if(line.Length==0 || line.StartsWith("#",StringComparison.Ordinal))continue;
            if(line.EndsWith("`",StringComparison.Ordinal))
                throw new InvalidDataException("Trusted sensor helper cannot compact continuation lines.");
            compact.Append(line).Append('\n');
        }
        return compact.ToString();
    }

    // Compatibility-only builder for pure non-launching tests; live runas passes a fresh pipe.
    static string BuildElevatedHelperCommand(string mode,string payload,string appRoot,string user)
    {
        return BuildElevatedHelperCommandWithPipe(mode,payload,appRoot,user,
            "tbme_sensor_fixture_nonruntime","00000000000000000000000000000000");
    }
    static string BuildElevatedHelperCommandWithPipe(string mode,string payload,string appRoot,string user,
        string pipeName,string pipeNonce)
    {
        if(!Regex.IsMatch(pipeName,@"^tbme_sensor_(?:[0-9a-f]{32}|fixture_nonruntime)$") ||
           !Regex.IsMatch(pipeNonce,@"^[0-9a-f]{32}$"))
            throw new InvalidDataException("Sensor status channel parameters invalid.");
        if(mode!="Install" && mode!="Uninstall")
            throw new InvalidDataException("Unexpected elevated sensor mode.");
        string brokerHash=Sha256Resource("Payload.TaskbarMonitorSensorBroker.exe");
        string supervisorHash=Sha256Resource("Payload.TaskbarMonitorSensorSupervisor.exe");
        string backendZipHash=Sha256Resource("Payload.LibreHardwareMonitor.zip");
        if(brokerHash.Length!=64 || supervisorHash.Length!=64 || backendZipHash.Length!=64)
            throw new InvalidDataException("Protected sensor resource hash unavailable.");
        string packed;
        using(Stream resource=Resource("Payload.TBME_Setup_Elevated_Helper.ps1"))
        {
            if(resource==null)throw new InvalidDataException("Trusted embedded sensor helper missing.");
            using(StreamReader reader=new StreamReader(resource,Encoding.UTF8,true))
            {
                string source=CompactTrustedHelperSource(reader.ReadToEnd());
                byte[] textBytes=Encoding.UTF8.GetBytes(source);
                if(textBytes.Length<1000 || textBytes.Length>120000)
                    throw new InvalidDataException("Unexpected sensor helper source size.");
                using(MemoryStream buffer=new MemoryStream())
                {
                    using(GZipStream zipper=new GZipStream(buffer,CompressionMode.Compress,true))
                        zipper.Write(textBytes,0,textBytes.Length);
                    packed=Convert.ToBase64String(buffer.ToArray());
                }
            }
        }
        // Every caller-supplied parameter is separately base64-encoded as data.
        // In particular, a quoted Windows user/path cannot inject PowerShell syntax.
        string script=
          "$ErrorActionPreference='Stop'\n"+
          "$blob=[Convert]::FromBase64String('"+packed+"')\n"+
          "$ms=[IO.MemoryStream]::new($blob)\n"+
          "$gzip=[IO.Compression.GZipStream]::new($ms,[IO.Compression.CompressionMode]0)\n"+
          "$reader=[IO.StreamReader]::new($gzip)\n"+
          "try{$code=$reader.ReadToEnd()}finally{$reader.Close()}\n"+
          "function d($s){[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($s))}\n"+
          "$p=d('"+Base64Utf8Argument(payload)+"')\n"+
          "$a=d('"+Base64Utf8Argument(appRoot)+"')\n"+
          "$u=d('"+Base64Utf8Argument(user)+"')\n"+
          // These are strict [a-f0-9] + static-prefix allowlisted values, not untrusted scripts.
          "$q='"+pipeName+"'\n"+
          "$n='"+pipeNonce+"'\n"+
          "& ([ScriptBlock]::Create($code)) -Mode '"+mode+"' -PayloadDir $p -AppRoot $a -UserId $u -ExpectedBrokerSHA256 '"+brokerHash+"' -ExpectedSupervisorSHA256 '"+supervisorHash+"' -ExpectedBackendZipSHA256 '"+backendZipHash+"' -StatusPipe $q -StatusNonce $n\n";
        string encoded=Convert.ToBase64String(Encoding.Unicode.GetBytes(script));
        // Preserve the established UTF-16 EncodedCommand path when it fits.
        // Windows Process creation caps the entire command line at 32,767 chars.
        if(encoded.Length<=32000)
            return "-NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand "+encoded;
        // R304: the SAME in-memory, PE-embedded trusted helper can be transported
        // as a constant PowerShell -Command string for long profile names.
        // Variable caller input is only UTF-8/Base64 data; mode is whitelisted
        // and resource digests are SHA-256 hex. No user-controlled quote or
        // PowerShell tokens can enter this command source. Never use -File.
        if(script.IndexOf('"')>=0 || script.IndexOf('\0')>=0)
            throw new InvalidDataException("Unexpected quote or null in trusted helper bootstrap.");
        string fallback="-NoProfile -NonInteractive -WindowStyle Hidden -Command \"& { "+script+" }\"";
        // Leave margin for the executable path and OS quoting. A truly huge
        // value must still fail closed instead of truncating or using Temp.
        if(fallback.Length>30000)
            throw new InvalidDataException("Trusted sensor helper command exceeds safe limit.");
        return fallback;
    }

    // R298: runas uses ShellExecuteEx, which searches the current directory,
    // Windows and PATH for an unqualified executable. Pin the native OS host.
    static string TrustedSystemPowerShellPath()
    {
        string system=Path.GetFullPath(Environment.SystemDirectory);
        if(!Path.IsPathRooted(system) || !Directory.Exists(system))
            throw new InvalidOperationException("Trusted Windows system directory unavailable.");
        string first=Path.Combine(system,"WindowsPowerShell");
        string folder=Path.Combine(first,"v1.0");
        string exe=Path.Combine(folder,"powershell.exe");
        if(!Directory.Exists(first) || !Directory.Exists(folder) || !File.Exists(exe))
            throw new InvalidOperationException("Trusted Windows PowerShell executable missing.");
        foreach(string candidate in new string[]{system,first,folder,exe})
        {
            if((File.GetAttributes(candidate)&FileAttributes.ReparsePoint)!=0)
                throw new InvalidOperationException("Trusted PowerShell host is a reparse path.");
        }
        return exe;
    }

    // Kept separate from Process.Start so the exact runas target can be
    // inspected in disposable Windows without granting UAC or starting it.
    static ProcessStartInfo BuildElevatedSensorProcessInfo(string mode,string payload,string appRoot,string user)
    {
        return BuildElevatedSensorProcessInfoWithPipe(mode,payload,appRoot,user,
            "tbme_sensor_fixture_nonruntime","00000000000000000000000000000000");
    }
    static ProcessStartInfo BuildElevatedSensorProcessInfoWithPipe(string mode,string payload,string appRoot,string user,
        string pipeName,string pipeNonce)
    {
        ProcessStartInfo psi=new ProcessStartInfo();
        psi.FileName=TrustedSystemPowerShellPath();
        psi.WorkingDirectory=Path.GetDirectoryName(psi.FileName);
        psi.Arguments=BuildElevatedHelperCommandWithPipe(mode,payload,appRoot,user,pipeName,pipeNonce);
        psi.UseShellExecute=true;
        psi.Verb="runas";
        return psi;
    }


    // R080 (DRAFT): asInvoker Setup owns result/log persistence, not runas.
    // No user-tree mutation is performed by this object until OS child identity
    // and a one-shot authenticated pipe result have been validated.
    sealed class SensorStatusReceiver : IDisposable
    {
        const int MaxWireBytes=65000;
        [DllImport("kernel32.dll",SetLastError=true)]
        static extern bool GetNamedPipeClientProcessId(SafePipeHandle handle,out uint pid);
        readonly NamedPipeServerStream stream;
        readonly IAsyncResult connection;
        readonly string nonce;
        Task<string> greeting, frame;
        bool connected, acknowledged;
        string message;
        public readonly string Name;
        public string Nonce {get {return nonce;}}
        public bool HasResult {get {return message!=null;}}

        static string BoundedLine(Stream input,int max)
        {
            using(MemoryStream buffer=new MemoryStream())
            {
                for(int i=0;i<=max;i++)
                {
                    int b=input.ReadByte();
                    if(b<0)throw new IOException("Sensor IPC channel ended without result.");
                    if(b==10)return new UTF8Encoding(false,true).GetString(buffer.ToArray());
                    if(i==max)throw new InvalidDataException("Sensor IPC frame over limit.");
                    buffer.WriteByte((byte)b);
                }
            }
            throw new InvalidDataException("Sensor IPC frame never terminated.");
        }

        public SensorStatusReceiver()
        {
            Name="tbme_sensor_"+Guid.NewGuid().ToString("N");
            nonce=Guid.NewGuid().ToString("N");
            PipeSecurity acl=new PipeSecurity();
            acl.SetAccessRuleProtection(true,false);
            SecurityIdentifier current=WindowsIdentity.GetCurrent().User;
            if(current==null)throw new InvalidOperationException("Requesting user SID unavailable.");
            acl.AddAccessRule(new PipeAccessRule(current,PipeAccessRights.FullControl,AccessControlType.Allow));
            // R305 requires the elevated Helper's effective account SID to
            // equal this requesting user SID, including under runas / UAC.
            // A different administrator account MUST fail closed. Never allow
            // all Authenticated Users to claim the one-instance IPC slot.
            // Kernel client PID, live process/session and nonce are separately checked.
            stream=new NamedPipeServerStream(Name,PipeDirection.InOut,1,
                PipeTransmissionMode.Byte,PipeOptions.Asynchronous,4096,4096,acl);
            connection=stream.BeginWaitForConnection(null,null);
        }

        public void Poll(Process child)
        {
            if(!connected && connection.IsCompleted)
            {
                stream.EndWaitForConnection(connection);
                if(child==null || child.HasExited)
                    throw new InvalidDataException("Sensor IPC connected without a live expected child.");
                uint peer;
                if(!GetNamedPipeClientProcessId(stream.SafePipeHandle,out peer))
                    throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                if(peer!=(uint)child.Id || child.SessionId!=Process.GetCurrentProcess().SessionId)
                    throw new InvalidDataException("Sensor IPC client OS process identity mismatch.");
                connected=true;
                greeting=Task.Factory.StartNew<string>(()=>BoundedLine(stream,96));
            }
            if(connected && !acknowledged && greeting.IsCompleted)
            {
                if(!String.Equals(greeting.GetAwaiter().GetResult(),"HELLO|"+nonce,StringComparison.Ordinal))
                    throw new InvalidDataException("Sensor IPC HELLO nonce mismatch.");
                byte[] ack=Encoding.UTF8.GetBytes("ACK|"+nonce+"\n");
                stream.Write(ack,0,ack.Length);
                stream.Flush();
                acknowledged=true;
                frame=Task.Factory.StartNew<string>(()=>BoundedLine(stream,MaxWireBytes));
            }
            if(acknowledged && message==null && frame.IsCompleted)
                message=frame.GetAwaiter().GetResult();
        }

        public void PersistAsInvoker()
        {
            PersistToUserRoot(AppRoot);
        }

        // Kept internal for the exact native Windows regression to exercise
        // the *same* persistence logic on a new disposable test-owned directory.
        // The production asInvoker caller always uses its real AppRoot.

        // R090 strict, bounded JSON contract. The transport authenticates a
        // peer/process/nonce, NOT the semantic contents of its JSON message.
        // Only a flat object with all source-owned typed fields can ever be
        // stored as a normal user's sensor status.
        static void ValidateSensorStatusJson(string json)
        {
            var schema=new Dictionary<string,char>(StringComparer.Ordinal)
            {
                {"Status",'s'},{"Message",'s'},{"PawnIOStatus",'s'},
                {"PawnIOExitCode",'i'},{"RebootRequired",'b'},
                {"TaskInstalled",'b'},{"SensorHealthy",'b'},
                {"SupervisorHealthy",'b'},{"CpuTransportHealthy",'b'},
                {"GpuTransportHealthy",'b'},{"StorageTransportHealthy",'b'},
                {"CpuDataAvailable",'b'},{"Architecture",'s'},
                {"RollbackPerformed",'b'},{"RollbackSucceeded",'b'},
                {"PreviousSensorLayerPresent",'b'},{"Time",'s'},{"LogPath",'s'}
            };
            if(json==null || json.Length>10000)throw new InvalidDataException("Sensor JSON too large.");
            // No external JSON package / new assembly dependency: exact
            // PowerShell ConvertTo-Json flat schema, RFC-style JSON string
            // escaping, and nonexponential bounded field tokenization.
            const string member=@"\A\s*""(?<name>[A-Za-z][A-Za-z0-9]*)""\s*:\s*(?<value>""(?:[^""\\\u0000-\u001F]|\\(?:[""\\/bfnrt]|u[0-9a-fA-F]{4}))*""|true|false|null|-?(?:0|[1-9][0-9]*))\s*";
            int pos=0;
            Action skip=()=>{while(pos<json.Length && (json[pos]==' ' || json[pos]=='\t' || json[pos]=='\r' || json[pos]=='\n'))pos++;};
            skip();
            if(pos>=json.Length || json[pos++]!='{')throw new InvalidDataException("Sensor JSON must be an object.");
            var seen=new HashSet<string>(StringComparer.Ordinal);
            var values=new Dictionary<string,string>(StringComparer.Ordinal);
            while(true)
            {
                skip();
                Match field=Regex.Match(json.Substring(pos),member,RegexOptions.CultureInvariant,
                                        TimeSpan.FromMilliseconds(600));
                if(!field.Success)throw new InvalidDataException("Invalid sensor JSON field syntax.");
                string key=field.Groups["name"].Value;
                string value=field.Groups["value"].Value;
                char kind;
                if(!schema.TryGetValue(key,out kind) || !seen.Add(key))
                    throw new InvalidDataException("Unknown or repeated sensor JSON field.");
                bool quoted=value.Length>=2 && value[0]=='"' && value[value.Length-1]=='"';
                if(kind=='s' && !quoted)throw new InvalidDataException("Sensor string field not quoted.");
                if(kind=='b' && value!="true" && value!="false")
                    throw new InvalidDataException("Sensor boolean field invalid.");
                if(kind=='i' && value!="null")
                {
                    int number;
                    if(!Int32.TryParse(value,NumberStyles.AllowLeadingSign,CultureInfo.InvariantCulture,out number))
                        throw new InvalidDataException("Sensor numeric field invalid.");
                }
                values.Add(key,value);
                pos+=field.Length;
                skip();
                if(pos>=json.Length)throw new InvalidDataException("Truncated sensor JSON object.");
                if(json[pos]==','){pos++;continue;}
                if(json[pos]=='}'){pos++;break;}
                throw new InvalidDataException("Invalid sensor JSON object separator.");
            }
            skip();
            if(pos!=json.Length || seen.Count!=schema.Count)
                throw new InvalidDataException("Sensor JSON fields incomplete or extra data.");
            // Status is canonical, unescaped ASCII; ambiguous encodings
            // cannot silently claim a different product health state.
            string status=values["Status"];
            switch(status)
            {
                case "\"READY\"":
                    if(values["SensorHealthy"]!="true" || values["SupervisorHealthy"]!="true" ||
                       values["RebootRequired"]!="false")
                        throw new InvalidDataException("READY status contradicts sensor health.");
                    break;
                case "\"REBOOT_REQUIRED\"":
                    if(values["RebootRequired"]!="true")
                        throw new InvalidDataException("Reboot status has no reboot flag.");
                    break;
                case "\"DEGRADED\"":
                case "\"DEGRADED_DATA\"":
                case "\"DEGRADED_ROLLED_BACK\"":
                case "\"DEGRADED_ROLLBACK_FAILED\"":
                case "\"DEGRADED_OTHER_USER_SENSOR_LAYER_PRESERVED\"":
                case "\"UNAVAILABLE\"":
                case "\"UNINSTALLED\"":
                case "\"UNINSTALL_WARNING\"":
                    break;
                default:
                    throw new InvalidDataException("Unknown sensor status value.");
            }
            if(values["Message"]=="\"\"" || values["Architecture"]=="\"\"" ||
               values["Time"]=="\"\"" || values["LogPath"]=="\"\"")
                throw new InvalidDataException("Mandatory sensor metadata empty.");
            if(status=="\"DEGRADED_ROLLED_BACK\"" &&
               (values["RollbackPerformed"]!="true" || values["RollbackSucceeded"]!="true"))
                throw new InvalidDataException("Rollback success result inconsistent.");
            if(status=="\"DEGRADED_ROLLBACK_FAILED\"" && values["RollbackPerformed"]!="true")
                throw new InvalidDataException("Rollback failure status inconsistent.");
        }

        internal void PersistToUserRoot(string userRoot)
        {
            if(String.IsNullOrWhiteSpace(userRoot) || !Path.IsPathRooted(userRoot))
                throw new InvalidDataException("Sensor status destination root invalid.");
            string canonical=Path.GetFullPath(userRoot).TrimEnd(Path.DirectorySeparatorChar);
            if(canonical.Length<4)
                throw new InvalidDataException("Sensor status destination root unsafe.");
            if(message==null)throw new InvalidDataException("No verified sensor status frame.");
            string[] parts=message.Split('|');
            if(parts.Length!=4 || parts[0]!="TBME80" ||
               !String.Equals(parts[1],nonce,StringComparison.Ordinal))
                throw new InvalidDataException("Sensor IPC result schema or nonce mismatch.");
            string json=new UTF8Encoding(false,true).GetString(Convert.FromBase64String(parts[2]));
            string logs=new UTF8Encoding(false,true).GetString(Convert.FromBase64String(parts[3]));
            if(logs.Length>25000)
                throw new InvalidDataException("Sensor IPC log exceeds size limit.");
            ValidateSensorStatusJson(json);
            string logRoot=Path.Combine(canonical,"Logs");
            Directory.CreateDirectory(logRoot);
            if(logs.Length>0)
                File.AppendAllText(Path.Combine(logRoot,"sensor_install.log"),logs+"\n",Encoding.UTF8);
            File.WriteAllText(Path.Combine(logRoot,"sensor_install_result.json"),json,Encoding.UTF8);
        }

        public void Dispose() {stream.Dispose();}
    }

    // Uses exactly one OS-attested pipe client for this new UAC child. On
    // cancellation/spoof/transport fault fail closed; never ask runas to write
    // status into the calling user's reparse-mutable AppData.

    static int ElevatedHelper(string mode,string payload,string appRoot,string user,int timeoutMs)
    {
        using(SensorStatusReceiver channel=new SensorStatusReceiver())
        {
            ProcessStartInfo psi=BuildElevatedSensorProcessInfoWithPipe(
                mode,payload,appRoot,user,channel.Name,channel.Nonce);
            Process elevated=null;
            Exception launchError=null;
            using(ManualResetEvent launchFinished=new ManualResetEvent(false))
            {
                Thread launchThread=new Thread(new ThreadStart(delegate {
                    try {elevated=Process.Start(psi);}
                    catch(Exception ex) {launchError=ex;}
                    finally {try{launchFinished.Set();}catch{}}
                }));
                launchThread.IsBackground=true;
                try {launchThread.SetApartmentState(ApartmentState.STA);}catch{}
                DateTime deadline=DateTime.UtcNow.AddMilliseconds(timeoutMs);
                launchThread.Start();
                int launchBudget=Math.Min(30000,Math.Max(1000,timeoutMs));
                DateTime launchDeadline=DateTime.UtcNow.AddMilliseconds(launchBudget);
                while(!launchFinished.WaitOne(100) && DateTime.UtcNow<launchDeadline)
                    Application.DoEvents();
                if(!launchFinished.WaitOne(0))return 125;
                if(launchError!=null)
                    throw new InvalidOperationException("Could not launch protected sensor helper.",launchError);
                if(elevated==null)
                    throw new InvalidOperationException("Protected sensor helper process unavailable.");
                try
                {
                    DateTime exitSeen=DateTime.MaxValue;
                    while(DateTime.UtcNow<deadline)
                    {
                        channel.Poll(elevated);
                        if(elevated.HasExited)
                        {
                            if(channel.HasResult)break;
                            if(exitSeen==DateTime.MaxValue)
                                exitSeen=DateTime.UtcNow.AddSeconds(3);
                            if(DateTime.UtcNow>=exitSeen)break;
                        }
                        Application.DoEvents();
                        Thread.Sleep(75);
                    }
                    if(!elevated.HasExited)
                    {
                        try{elevated.Kill();}catch{}
                        return 124;
                    }
                    if(channel.HasResult)channel.PersistAsInvoker();
                    else if(elevated.ExitCode==0)
                        throw new InvalidDataException("Protected sensor helper ended without authenticated status.");
                    return elevated.ExitCode;
                }
                catch
                {
                    // Only the newly launched Helper owned by this Setup is stopped.
                    if(!elevated.HasExited){try{elevated.Kill();}catch{}}
                    throw;
                }
                finally {elevated.Dispose();}
            }
        }
    }

    static void Shortcut(string path,string target)
    {
        Shortcut(path,target,"","Live system monitor integrated into the Windows taskbar");
    }

    static void Shortcut(string path,string target,string arguments,string description)
    {
        string temp=Path.Combine(Path.GetTempPath(),"tbme_shortcut_"+Guid.NewGuid().ToString("N")+".ps1");
        string text=
          "$ErrorActionPreference='Stop'\r\n"+
          "$w=New-Object -ComObject WScript.Shell\r\n"+
          "$s=$w.CreateShortcut('"+path.Replace("'","''")+"')\r\n"+
          "$s.TargetPath='"+target.Replace("'","''")+"'\r\n"+
          "$s.Arguments='"+arguments.Replace("'","''")+"'\r\n"+
          "$s.WorkingDirectory='"+AppRoot.Replace("'","''")+"'\r\n"+
          "$s.IconLocation='"+AppExe.Replace("'","''")+",0'\r\n"+
          "$s.Description='"+description.Replace("'","''")+"'\r\n"+
          "$s.WindowStyle=1\r\n$s.Save()\r\n";
        File.WriteAllText(temp,text,Encoding.UTF8);
        try{
            ProcessStartInfo psi=new ProcessStartInfo("powershell.exe","-NoProfile -ExecutionPolicy Bypass -File \""+temp+"\"");
            psi.UseShellExecute=false;psi.CreateNoWindow=true;
            Process p=Process.Start(psi);
            if(p==null || !p.WaitForExit(15000) || p.ExitCode!=0)
                throw new InvalidOperationException("Shortcut creation failed.");
        }
        finally{try{File.Delete(temp);}catch{}}
    }

    static string Sha256File(string path)
    {
        using(SHA256 sha=SHA256.Create())
        using(FileStream fs=File.OpenRead(path))
        {
            byte[] hash=sha.ComputeHash(fs);
            StringBuilder b=new StringBuilder();
            foreach(byte x in hash)b.Append(x.ToString("X2"));
            return b.ToString();
        }
    }

    static string Sha256Resource(string resourceName)
    {
        using(Stream s=Resource(resourceName))
        {
            if(s==null)throw new InvalidOperationException("Missing embedded resource: "+resourceName);
            using(SHA256 sha=SHA256.Create())
            {
                byte[] hash=sha.ComputeHash(s);
                StringBuilder b=new StringBuilder();
                foreach(byte x in hash)b.Append(x.ToString("X2"));
                return b.ToString();
            }
        }
    }

    static void WriteBackendState(string backendRoot)
    {
        string library=Path.Combine(backendRoot,"LibreHardwareMonitorLib.dll");
        string sha=File.Exists(library)?Sha256File(library):"MISSING";
        string json="{\r\n"+
          "  \"Status\": \"READY\",\r\n"+
          "  \"Backend\": \"LibreHardwareMonitor\",\r\n"+
          "  \"Version\": \"0.9.6\",\r\n"+
          "  \"Channel\": \"STABLE_PINNED\",\r\n"+
          "  \"LibrarySHA256\": \""+sha+"\",\r\n"+
          "  \"LibraryPath\": \""+library.Replace("\\","\\\\")+"\"\r\n"+
          "}\r\n";
        File.WriteAllText(Path.Combine(AppRoot,"sensor_backend_state.json"),json,Encoding.UTF8);
    }

    static void WriteInstallState(SensorOutcome sensorOutcome)
    {
        string sensorStatus=sensorOutcome==null?"UNKNOWN":(sensorOutcome.Status??"UNKNOWN");
        string sensorVersion=sensorOutcome==null?"":(sensorOutcome.LayerVersion??"");
        string sensorMode=sensorOutcome==null?"":(sensorOutcome.LayerMode??"");
        string json="{\r\n"+
          "  \"App\": \"Taskbar Monitor Enhanced\",\r\n"+
          "  \"Version\": \"1.7.8\",\r\n"+
          "  \"PublicVersion\": \"1.7.8\",\r\n"+
          "  \"InternalRuntimeBaseline\": \"V1_1_2_R21_PRODUCTION_HARDENING\",\r\n"+
          "  \"SensorSupervisor\": \"V1_3_0_R33_STORAGE_COMPLETION_HARDENING\",\r\n"+
          "  \"SensorLayerStatus\": \""+sensorStatus.Replace("\\","\\\\").Replace("\"","\\\"")+"\",\r\n"+
          "  \"SensorLayerVersion\": \""+sensorVersion.Replace("\\","\\\\").Replace("\"","\\\"")+"\",\r\n"+
          "  \"SensorProtocolVersion\": \""+SensorProtocolVersion+"\",\r\n"+
          "  \"SensorSupervisorVersion\": \""+SensorSupervisorVersion+"\",\r\n"+
          "  \"SensorLayerMode\": \""+sensorMode.Replace("\\","\\\\").Replace("\"","\\\"")+"\",\r\n"+
          "  \"MainLaunchMode\": \""+MainLaunchMode+"\",\r\n"+
          "  \"ProductIdentity\": \"LOCKED\",\r\n"+
          "  \"ShortcutName\": \"Taskbar Monitor Enhanced\",\r\n"+
          "  \"Publisher\": \"Dr. Ali-Akbar Emadeddin\",\r\n"+
          "  \"PublisherEmail\": \"aliemad1324@gmail.com\",\r\n"+
          "  \"PublisherGitHub\": \"https://github.com/GOD13emad\",\r\n"+
          "  \"License\": \"GPL-3.0\",\r\n"+
          "  \"AiAssistedDevelopmentDisclosure\": \"DOCUMENTED\",\r\n"+
          "  \"UpstreamAttribution\": \"leandrosa81/taskbar-monitor GPL-3.0\"\r\n"+
          "}\r\n";
        File.WriteAllText(Path.Combine(AppRoot,"install_state.json"),json,Encoding.UTF8);
    }

    static string PrepareSensorPayload()
    {
        string payload=Path.Combine(Path.GetTempPath(),"tbme_setup_"+Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(payload);
        Extract("Payload.TaskbarMonitorSensorBroker.exe",Path.Combine(payload,"TaskbarMonitorSensorBroker.exe"));
        Extract("Payload.TaskbarMonitorSensorSupervisor.exe",Path.Combine(payload,"TaskbarMonitorSensorSupervisor.exe"));
        // This user-writable staging file is bound to the PE embedded ZIP hash
        // before any elevated service changes; it is deleted with this payload.
        Extract("Payload.LibreHardwareMonitor.zip",Path.Combine(payload,"LibreHardwareMonitor.zip"));
        // R297: never stage or elevate a third-party executable in user-writable
        // Temp, even if an optional private PE contains a PawnIO resource.
        // Reuse compatible preinstalled PawnIO, otherwise require separate
        // official installation with explicit owner consent.
        return payload;
    }

    static SensorOutcome ReadSensorOutcome()
    {
        SensorOutcome outcome=new SensorOutcome();
        try{
            if(!File.Exists(SensorResultPath))return outcome;
            string json=File.ReadAllText(SensorResultPath,Encoding.UTF8);
            outcome.Status=JsonString(json,"Status");
            outcome.Message=JsonString(json,"Message");
            outcome.RebootRequired=JsonBool(json,"RebootRequired");
            outcome.IsHealthy=String.Equals(outcome.Status,"READY",StringComparison.OrdinalIgnoreCase);
            if(outcome.IsHealthy)
            {
                outcome.LayerVersion=SensorSupervisorVersion;
                outcome.LayerMode="INSTALLED_CURRENT";
            }
            if(String.IsNullOrEmpty(outcome.Status))outcome.Status="UNKNOWN";
            if(String.IsNullOrEmpty(outcome.Message))outcome.Message="Hardware sensor status is unknown.";
        }catch{}
        return outcome;
    }

    static string JsonString(string json,string key)
    {
        string marker="\""+key+"\":";
        int p=json.IndexOf(marker,StringComparison.OrdinalIgnoreCase);
        if(p<0)return "";
        p+=marker.Length;
        while(p<json.Length && Char.IsWhiteSpace(json[p]))p++;
        if(p>=json.Length || json[p]!='\"')return "";
        p++;
        StringBuilder b=new StringBuilder();
        bool esc=false;
        while(p<json.Length){
            char c=json[p++];
            if(esc){
                if(c=='n')b.Append('\n');
                else if(c=='r')b.Append('\r');
                else if(c=='t')b.Append('\t');
                else b.Append(c);
                esc=false;
            }else if(c=='\\'){
                esc=true;
            }else if(c=='\"'){
                break;
            }else b.Append(c);
        }
        return b.ToString();
    }

    static bool JsonBool(string json,string key)
    {
        string marker="\""+key+"\":";
        int p=json.IndexOf(marker,StringComparison.OrdinalIgnoreCase);
        if(p<0)return false;
        p+=marker.Length;
        while(p<json.Length && Char.IsWhiteSpace(json[p]))p++;
        return p+4<=json.Length && String.Equals(json.Substring(p,4),"true",StringComparison.OrdinalIgnoreCase);
    }

    static bool TryReuseCompatibleSensorLayer(out SensorOutcome outcome)
    {
        outcome=null;
        try
        {
            string sensorRoot=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),"TaskbarMonitorEnhanced","SensorBroker");
            string broker=Path.Combine(sensorRoot,"TaskbarMonitorSensorBroker.exe");
            string supervisor=Path.Combine(sensorRoot,"TaskbarMonitorSensorSupervisor.exe");
            string statePath=Path.Combine(AppRoot,"sensor_supervisor_state.json");
            if(!File.Exists(broker)||!File.Exists(supervisor)||!File.Exists(statePath))return false;

            string brokerSha=Sha256File(broker);
            string supervisorSha=Sha256File(supervisor);
            string expectedProtocolVersion="";
            string mode="";

            string currentBrokerSha=Sha256Resource("Payload.TaskbarMonitorSensorBroker.exe");
            string currentSupervisorSha=Sha256Resource("Payload.TaskbarMonitorSensorSupervisor.exe");
            if(String.Equals(brokerSha,currentBrokerSha,StringComparison.OrdinalIgnoreCase)&&
               String.Equals(supervisorSha,currentSupervisorSha,StringComparison.OrdinalIgnoreCase))
            {
                expectedProtocolVersion=SensorProtocolVersion;
                mode="CURRENT_EXACT_R33";
            }
            else return false;

            string json;
            using(FileStream fs=new FileStream(statePath,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))
            using(StreamReader sr=new StreamReader(fs,Encoding.UTF8,true))
                json=sr.ReadToEnd();
            string tsText=JsonString(json,"TimestampUtc");
            DateTime ts;
            if(!DateTime.TryParse(tsText,CultureInfo.InvariantCulture,DateTimeStyles.AssumeUniversal|DateTimeStyles.AdjustToUniversal,out ts))
                return false;
            double age=(DateTime.UtcNow-ts).TotalSeconds;
            if(age<0||age>=CompatibleSensorStateFreshSeconds)return false;
            if(!String.Equals(JsonString(json,"BrokerVersion"),expectedProtocolVersion,StringComparison.OrdinalIgnoreCase))return false;
            if(!String.Equals(JsonString(json,"SupervisorVersion"),SensorSupervisorVersion,StringComparison.OrdinalIgnoreCase))return false;

            bool healthy=
                JsonBool(json,"ChildJobKillOnClose")&&
                JsonBool(json,"CpuJobContained")&&JsonBool(json,"GpuJobContained")&&JsonBool(json,"StorageJobContained")&&
                JsonBool(json,"CpuTransportHealthy")&&JsonBool(json,"GpuTransportHealthy")&&JsonBool(json,"StorageTransportHealthy")&&
                JsonBool(json,"CpuDataAvailable")&&JsonBool(json,"GpuDataAvailable")&&JsonBool(json,"StorageDataAvailable");
            if(!healthy)return false;

            outcome=new SensorOutcome();
            outcome.Status="READY";
            outcome.IsHealthy=true;
            outcome.RebootRequired=false;
            outcome.LayerVersion=SensorSupervisorVersion;
            outcome.LayerMode=mode;
            outcome.Message="Existing protected sensor supervisor "+SensorSupervisorVersion+" with broker protocol "+SensorProtocolVersion+" passed exact-hash and live-health gates; Setup reused it without administrator changes.";
            return true;
        }
        catch{return false;}
    }

    static SensorOutcome InstallSensorLayer()
    {
        SensorOutcome outcome=new SensorOutcome();
        string payload=null;
        try{
            Directory.CreateDirectory(Path.Combine(AppRoot,"Logs"));
            try{File.Delete(SensorResultPath);}catch{}
            payload=PrepareSensorPayload();
            string user=WindowsIdentity.GetCurrent().Name;
            int helperExit;
            try{
                helperExit=ElevatedHelper("Install",payload,AppRoot,user,110000);
            }catch(Exception ex){
                outcome.Status="DEGRADED";
                outcome.Message="The application installed successfully. The protected sensor supervisor did not report ready before Setup finished. "+ex.Message+" It will continue starting in the background; protected temperature fields may briefly show N/A.";
                return outcome;
            }

            outcome=ReadSensorOutcome();
            if(helperExit==125 && String.Equals(outcome.Status,"UNKNOWN",StringComparison.OrdinalIgnoreCase)){
                outcome.Status="DEGRADED";
                outcome.Message="The application installed successfully, but the Windows administrator-consent launch did not complete within 30 seconds. Protected CPU/GPU/storage telemetry remains degraded until Repair Hardware Sensors succeeds.";
            }else if(helperExit==124 && String.Equals(outcome.Status,"UNKNOWN",StringComparison.OrdinalIgnoreCase)){
                outcome.Status="DEGRADED";
                outcome.Message="The application installed successfully. The protected sensor step exceeded the Setup readiness window, but the supervisor will continue in the background. CPU/GPU/storage temperature fields may briefly show N/A.";
            }else if(helperExit!=0 && String.Equals(outcome.Status,"UNKNOWN",StringComparison.OrdinalIgnoreCase)){
                outcome.Status="DEGRADED";
                outcome.Message="The application installed successfully. The protected sensor helper returned exit code "+helperExit+". The monitor will continue without blocking; use Repair Hardware Sensors if protected CPU/GPU/storage telemetry remains unavailable.";
            }
            return outcome;
        }finally{
            if(payload!=null)try{Directory.Delete(payload,true);}catch{}
        }
    }

    static SensorOutcome RepairSensors()
    {
        if(!Directory.Exists(AppRoot) || !File.Exists(AppExe))
            throw new InvalidOperationException("Taskbar Monitor Enhanced is not installed.");
        return InstallSensorLayer();
    }

    static bool IsCurrentProcessElevated()
    {
        try
        {
            using(WindowsIdentity identity=WindowsIdentity.GetCurrent())
            {
                WindowsPrincipal principal=new WindowsPrincipal(identity);
                return principal.IsInRole(WindowsBuiltInRole.Administrator);
            }
        }
        catch{return false;}
    }

    static SensorOutcome Install(bool desktop,bool startup)
    {
        if(!Environment.Is64BitOperatingSystem)
            throw new InvalidOperationException("Taskbar Monitor Enhanced 1.7.8 requires 64-bit Windows.");

        // R114: prevent fresh-install code from ever overwriting an installed
        // product or user-owned files. Existing roots must use /update.
        if(Directory.Exists(AppRoot) || ExistingRegistered())
            throw new InvalidOperationException("Existing installation detected; use the guarded in-place updater.");
        StopProcess("TaskbarMonitorEnhanced");

        Directory.CreateDirectory(AppRoot);
        Directory.CreateDirectory(Path.Combine(AppRoot,"Source"));
        Directory.CreateDirectory(Path.Combine(AppRoot,"Docs"));

        Extract("Payload.TaskbarMonitorEnhanced.exe",AppExe);
        Extract("Payload.TaskbarMonitorEnhanced.exe.config",AppExe+".config");
        Extract("Payload.TaskbarMonitorEnhanced.ico",Path.Combine(AppRoot,"TaskbarMonitorEnhanced.ico"));
        // R255: avoid a redundant root source that breaks same-version maintenance.
        Extract("Payload.TaskbarMonitorEnhanced.cs",Path.Combine(AppRoot,"Source","TaskbarMonitorEnhanced.cs"));
        Extract("Payload.StudioThemes.cs",Path.Combine(AppRoot,"Source","StudioThemes.cs"));
        Extract("Payload.WallpaperStudio.cs",Path.Combine(AppRoot,"Source","WallpaperStudio.cs"));
        Extract("Payload.TaskbarGlass.cs",Path.Combine(AppRoot,"Source","TaskbarGlass.cs"));
        Extract("Payload.WorkspaceModels.cs",Path.Combine(AppRoot,"Source","WorkspaceModels.cs"));
        Extract("Payload.MonitorWorkspace.cs",Path.Combine(AppRoot,"Source","MonitorWorkspace.cs"));
        Extract("Payload.WorkspaceSelfTest.cs",Path.Combine(AppRoot,"Source","WorkspaceSelfTest.cs"));
        Extract("Payload.TaskbarMonitorSensorBroker.cs",Path.Combine(AppRoot,"Source","TaskbarMonitorSensorBroker.cs"));
        Extract("Payload.TaskbarMonitorSensorSupervisor.cs",Path.Combine(AppRoot,"Source","TaskbarMonitorSensorSupervisor.cs"));
        Extract("Payload.TaskbarMonitorEnhanced_Setup.cs",Path.Combine(AppRoot,"Source","TaskbarMonitorEnhanced_Setup.cs"));

        string[] docs=new string[]{
          "LICENSE","README.md","AUTHORS.md","COPYRIGHT_AND_ATTRIBUTION.md",
          "AI_ASSISTED_DEVELOPMENT.md","THIRD_PARTY_NOTICES.md",
          "RELEASE_NOTES_v1.7.8.md","UPSTREAM_REFERENCE_GPL_NOTICE.md"
        };
        foreach(string doc in docs)
            Extract("Payload."+doc,Path.Combine(AppRoot,"Docs",doc));

        string backendRoot=Path.Combine(AppRoot,"SensorBackend","LibreHardwareMonitor-0.9.6");
        if(Directory.Exists(backendRoot))Directory.Delete(backendRoot,true);
        Directory.CreateDirectory(backendRoot);
        string lhmZip=Path.Combine(Path.GetTempPath(),"tbme_lhm_"+Guid.NewGuid().ToString("N")+".zip");
        Extract("Payload.LibreHardwareMonitor.zip",lhmZip);
        ZipFile.ExtractToDirectory(lhmZip,backendRoot);
        try{File.Delete(lhmZip);}catch{}
        WriteBackendState(backendRoot);

        SensorOutcome sensorOutcome;
        if(!TryReuseCompatibleSensorLayer(out sensorOutcome))
            sensorOutcome=InstallSensorLayer();

        string uninstaller=Path.Combine(AppRoot,"Uninstall.exe");
        File.Copy(Application.ExecutablePath,uninstaller,true);

        string desktopLink=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),Product+".lnk");
        string startLink=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),Product+".lnk");
        string repairLink=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),Product+" - Repair Hardware Sensors.lnk");
        Shortcut(startLink,AppExe);
        Shortcut(repairLink,uninstaller,"/repair-sensors","Repair or retry Taskbar Monitor Enhanced hardware sensors");
        if(desktop)Shortcut(desktopLink,AppExe);
        else try{File.Delete(desktopLink);}catch{}

        string recoveryLink=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup),"Taskbar Monitor Enhanced Startup Recovery.lnk");
        using(RegistryKey run=Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run")){
            if(startup)run.SetValue("TaskbarMonitorEnhanced","\""+AppExe+"\"");
            else run.DeleteValue("TaskbarMonitorEnhanced",false);
        }
        if(startup)Shortcut(recoveryLink,AppExe,"--startup-recovery","Delayed recovery launcher for Taskbar Monitor Enhanced Start-with-Windows.");
        else try{File.Delete(recoveryLink);}catch{}

        using(RegistryKey key=Registry.CurrentUser.CreateSubKey(UninstallKey)){
            key.SetValue("DisplayName",Product);
            key.SetValue("DisplayVersion",Version);
            key.SetValue("Publisher",Publisher);
            key.SetValue("DisplayIcon",AppExe);
            key.SetValue("InstallLocation",AppRoot);
            key.SetValue("UninstallString","\""+uninstaller+"\" /uninstall");
            key.SetValue("QuietUninstallString","\""+uninstaller+"\" /uninstall /quiet");
            key.SetValue("NoModify",1,RegistryValueKind.DWord);
            key.SetValue("NoRepair",1,RegistryValueKind.DWord);
        }

        if(IsCurrentProcessElevated())
        {
            MainLaunchMode="SKIPPED_ELEVATED_SETUP";
        }
        else
        {
            try
            {
                Process.Start(AppExe);
                MainLaunchMode="LAUNCHED_NON_ELEVATED_SETUP";
            }
            catch
            {
                MainLaunchMode="AUTOLAUNCH_FAILED";
            }
        }
        WriteInstallState(sensorOutcome);
        return sensorOutcome;
    }

    static void Uninstall(bool quiet)
    {
        if(!quiet){
            DialogResult answer=MessageBox.Show(
              "Remove Taskbar Monitor Enhanced, its shortcuts, settings and logs?\r\n\r\nPawnIO is intentionally left installed because other hardware-monitoring applications may use it.",
              "Uninstall "+Product,MessageBoxButtons.YesNo,MessageBoxIcon.Question);
            if(answer!=DialogResult.Yes)return;
        }

        StopProcess("TaskbarMonitorEnhanced");

        string payload=Path.Combine(Path.GetTempPath(),"tbme_uninstall_"+Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(payload);
        string user=WindowsIdentity.GetCurrent().Name;

        int helperExit=ElevatedHelper("Uninstall",payload,AppRoot,user,90000);
        if(helperExit!=0)
            throw new InvalidOperationException("Protected sensor removal failed. Exit code: "+helperExit);

        try{File.Delete(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),Product+".lnk"));}catch{}
        try{File.Delete(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),Product+".lnk"));}catch{}
        try{File.Delete(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs),Product+" - Repair Hardware Sensors.lnk"));}catch{}

        using(RegistryKey run=Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run"))
            run.DeleteValue("TaskbarMonitorEnhanced",false);
        try{File.Delete(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup),"Taskbar Monitor Enhanced Startup Recovery.lnk"));}catch{}
        Registry.CurrentUser.DeleteSubKeyTree(UninstallKey,false);

        string cleanup=Path.Combine(Path.GetTempPath(),"tbme_cleanup_"+Guid.NewGuid().ToString("N")+".cmd");
        File.WriteAllText(cleanup,
          "@echo off\r\nping 127.0.0.1 -n 4 >nul\r\nrmdir /s /q \""+AppRoot+"\"\r\ndel /q \"%~f0\"\r\n",
          Encoding.ASCII);
        ProcessStartInfo psi=new ProcessStartInfo("cmd.exe","/c \""+cleanup+"\"");
        psi.UseShellExecute=false;psi.CreateNoWindow=true;
        // R108: background cmd must not inherit AppRoot as its working directory.
        // Otherwise its rmdir of AppRoot can fail although Uninstall.exe exits zero.
        psi.WorkingDirectory=Path.GetTempPath();
        Process.Start(psi);

        if(!quiet)
            MessageBox.Show(Product+" was removed.","Uninstall complete",MessageBoxButtons.OK,MessageBoxIcon.Information);
    }

    static int Verify(string path)
    {
        try{
            foreach(string resourceName in RequiredResources){
                using(Stream s=Resource(resourceName)){
                    if(s==null || s.Length==0)return 20;
                }
            }
            // R80: the installer must prove it EMBEDS the signed Main bytes.
            // Required embedded payload proof plus optional proprietary upstream driver audit.
            bool pawnBundled=false;
            using(Stream pawn=Resource("Payload.PawnIO_setup.exe")){
                if(pawn!=null){
                    if(pawn.Length==0)return 23;
                    pawnBundled=true;
                }
            }
            long embeddedMainBytes=0;
            string embeddedMainSHA256="";
            using(Stream main=Resource("Payload.TaskbarMonitorEnhanced.exe")){
                if(main==null || main.Length<1024)return 22;
                embeddedMainBytes=main.Length;
                using(SHA256 hash=SHA256.Create()){
                    embeddedMainSHA256=BitConverter.ToString(hash.ComputeHash(main)).Replace("-","");
                }
            }
            if(!String.IsNullOrEmpty(path)){
                string json="{\"Status\":\"PASS\",\"Resources\":"+(RequiredResources.Length+(pawnBundled?1:0))+
                    ",\"Version\":\"1.7.8\",\"Publisher\":\"Dr. Ali-Akbar Emadeddin\""+
                    ",\"SensorArchitecture\":\"R21_PROCESS_ISOLATED\",\"SensorUpgradePolicy\":\"EXACT_R33_SUPERVISOR_R21_PROTOCOL\""+
                    ",\"PawnIOBundled\":"+(pawnBundled?"true":"false")+",\"EmbeddedMainSHA256\":\""+embeddedMainSHA256+"\",\"EmbeddedMainBytes\":"+embeddedMainBytes+"}";
                File.WriteAllText(path,json,Encoding.UTF8);
            }
            return 0;
        }catch{return 21;}
    }

    static string Value(string[] args,string prefix)
    {
        foreach(string arg in args)
            if(arg.StartsWith(prefix,StringComparison.OrdinalIgnoreCase))
                return arg.Substring(prefix.Length);
        return "";
    }

    static bool Has(string[] args,string value)
    {
        foreach(string arg in args)
            if(String.Equals(arg,value,StringComparison.OrdinalIgnoreCase))return true;
        return false;
    }

    sealed class SetupForm:Form
    {
        CheckBox desktop,startup;
        Button install;
        ProgressBar progress;
        Label status;

        public SetupForm()
        {
            Text=Product+" Setup";
            Width=610;Height=435;StartPosition=FormStartPosition.CenterScreen;
            FormBorderStyle=FormBorderStyle.FixedDialog;MaximizeBox=false;
            Icon=Icon.ExtractAssociatedIcon(Application.ExecutablePath);

            Label title=new Label();
            title.Text=Product+"  1.7.8";
            title.Font=new Font(Font.FontFamily,18,FontStyle.Bold);
            title.Left=28;title.Top=22;title.AutoSize=true;Controls.Add(title);

            Label author=new Label();
            author.Text="Lead Developer & Maintainer: Dr. Ali-Akbar Emadeddin\r\nGPL-3.0 • AI-assisted development transparently documented";
            author.Left=31;author.Top=67;author.AutoSize=true;Controls.Add(author);

            TextBox info=new TextBox();
            info.Left=30;info.Top=116;info.Width=530;info.Height=140;
            info.Multiline=true;info.ReadOnly=true;info.ScrollBars=ScrollBars.Vertical;
            info.Text="Live CPU, RAM, disk, GPU, VRAM, network and temperature telemetry integrated into the Windows taskbar.\r\n\r\nThe main application runs without elevation. Windows requests administrator approval only for the optional protected hardware-sensor service. If protected sensors cannot be activated, installation still completes and unavailable temperature fields show N/A.\r\n\r\nSource code, GPL license, upstream attribution and third-party notices are installed with the application.";
            Controls.Add(info);

            desktop=new CheckBox();desktop.Text="Create Desktop shortcut";desktop.Checked=true;
            desktop.Left=35;desktop.Top=276;desktop.AutoSize=true;Controls.Add(desktop);

            startup=new CheckBox();startup.Text="Start with Windows";startup.Checked=true;
            startup.Left=35;startup.Top=304;startup.AutoSize=true;Controls.Add(startup);

            progress=new ProgressBar();progress.Left=35;progress.Top=337;progress.Width=370;progress.Height=18;
            progress.Style=ProgressBarStyle.Marquee;progress.Visible=false;Controls.Add(progress);

            status=new Label();status.Left=35;status.Top=362;status.Width=390;status.Text="Ready";Controls.Add(status);

            install=new Button();install.Text="Install";install.Left=460;install.Top=326;install.Width=100;install.Height=38;
            install.Click+=delegate{
                install.Enabled=false;desktop.Enabled=false;startup.Enabled=false;progress.Visible=true;
                status.Text="Installing application and protected hardware-sensor support…";
                Application.DoEvents();
                try{
                    SensorOutcome outcome=(Directory.Exists(AppRoot) || ExistingRegistered()) ? UpgradeExisting() : Install(desktop.Checked,startup.Checked);
                    progress.Visible=false;
                    status.Text="Installation completed.";
                    if(outcome.IsHealthy){
                        MessageBox.Show(Product+" 1.7.8 was installed successfully.\r\n\r\nProtected hardware sensor monitoring is active.",
                          "Setup complete",MessageBoxButtons.OK,MessageBoxIcon.Information);
                    }else{
                        string extra=outcome.RebootRequired ? "\r\n\r\nRestart Windows, then use Start Menu > Taskbar Monitor Enhanced - Repair Hardware Sensors if needed." :
                          "\r\n\r\nThe application is installed and usable. The sensor supervisor continues in the background. If protected CPU/GPU/storage telemetry is still unavailable after a short wait or restart, use Start Menu > Taskbar Monitor Enhanced - Repair Hardware Sensors.";
                        MessageBox.Show(Product+" 1.7.8 was installed successfully.\r\n\r\n"+outcome.Message+extra,
                          "Setup complete - sensor warning",MessageBoxButtons.OK,MessageBoxIcon.Warning);
                    }
                    Close();
                }catch(Exception ex){
                    progress.Visible=false;install.Enabled=true;desktop.Enabled=true;startup.Enabled=true;
                    status.Text="Installation failed.";
                    MessageBox.Show(ex.Message,"Setup failed",MessageBoxButtons.OK,MessageBoxIcon.Error);
                }
            };
            Controls.Add(install);
        }
    }

    [STAThread]
    static int Main(string[] args)
    {
        bool createdNew=false;
        using(Mutex mutex=new Mutex(true,@"Local\TaskbarMonitorEnhanced_Setup_1_3_0",out createdNew))
        {
            if(!createdNew)
            {
                if(!Has(args,"/quiet"))
                    MessageBox.Show("Another Taskbar Monitor Enhanced Setup instance is already running.","Setup already running",MessageBoxButtons.OK,MessageBoxIcon.Information);
                return 40;
            }
            return RunMain(args);
        }
    }

    // R129: diagnostic-only, strictly on short-lived GitHub-hosted Windows.
    // No user PC logging, no fallback writes, no overwrite, no installer bypass.
    static void WriteHostedUpgradeFailure(Exception ex)
    {
        try
        {
            if(Environment.GetEnvironmentVariable("GITHUB_ACTIONS")!="true" ||
               Environment.GetEnvironmentVariable("RUNNER_ENVIRONMENT")!="github-hosted" ||
               Environment.GetEnvironmentVariable("RUNNER_OS")!="Windows" ||
               !Regex.IsMatch(Environment.GetEnvironmentVariable("GITHUB_SHA")??"","^[0-9a-f]{40}$"))
                return;
            string phase=Environment.GetEnvironmentVariable("TBME_UPDATE_DIAGNOSTIC_PHASE")??"";
            if(phase!="NEGATIVE_USER_EDIT" && phase!="POSITIVE_OFFICIAL_STABLE" &&
               phase!="IDEMPOTENT" && phase!="DOWNGRADE")return;
            string temp=Environment.GetEnvironmentVariable("RUNNER_TEMP")??"";
            if(String.IsNullOrWhiteSpace(temp))return;
            string evidence=Path.Combine(Path.GetFullPath(temp),"TBME_R126_STABLE_UPDATE");
            if(!Directory.Exists(evidence))return;
            string file=Path.Combine(evidence,"R129_DIAG_"+phase+".txt");
            using(FileStream output=new FileStream(file,FileMode.CreateNew,FileAccess.Write,FileShare.None))
            using(StreamWriter writer=new StreamWriter(output,new UTF8Encoding(false)))
            {
                writer.WriteLine("R129_FAIL_CLOSED_DIAGNOSTIC");
                writer.WriteLine("TEST_PHASE="+phase);
                writer.WriteLine("GIT_SHA="+Environment.GetEnvironmentVariable("GITHUB_SHA"));
                writer.WriteLine("EXCEPTION="+ex.GetType().FullName);
                writer.WriteLine(ex.ToString().Substring(0,Math.Min(12000,ex.ToString().Length)));
                writer.Flush();
            }
        }
        catch{} // Diagnostic must never change Setup's failure/rollback behavior.
    }

    static int RunMain(string[] args)
    {
        if(Has(args,"/verify"))
            return Verify(Value(args,"/verifyfile="));

        bool quiet=Has(args,"/quiet");
        if(Has(args,"/update")){
            try{
                UpgradeExisting(); // never fresh-install; rollback journal required
                return 0;
            }catch(Exception ex){
                WriteHostedUpgradeFailure(ex);
                if(!quiet)MessageBox.Show(ex.Message,"In-place update declined",MessageBoxButtons.OK,MessageBoxIcon.Error);
                return 34;
            }
        }
        if(Has(args,"/install")){
            try{
                bool desktop=!String.Equals(Value(args,"/desktop="),"0",StringComparison.OrdinalIgnoreCase);
                bool startup=!String.Equals(Value(args,"/startup="),"0",StringComparison.OrdinalIgnoreCase);
                if(Directory.Exists(AppRoot) || ExistingRegistered()){
                    UpgradeExisting(); // maintenance route; preserve existing options
                    return 0;
                }
                Install(desktop,startup);
                return 0;
            }catch(Exception ex){
                if(!quiet)MessageBox.Show(ex.Message,"Setup failed",MessageBoxButtons.OK,MessageBoxIcon.Error);
                return 30;
            }
        }

        if(Has(args,"/repair-sensors")){
            try{
                SensorOutcome outcome=RepairSensors();
                if(!quiet){
                    MessageBoxIcon icon=outcome.IsHealthy?MessageBoxIcon.Information:MessageBoxIcon.Warning;
                    MessageBox.Show(outcome.Message+"\r\n\r\nDiagnostic log:\r\n"+Path.Combine(AppRoot,"Logs","sensor_install.log"),
                      outcome.IsHealthy?"Sensor repair complete":"Sensor repair warning",MessageBoxButtons.OK,icon);
                }
                return outcome.IsHealthy?0:10;
            }catch(Exception ex){
                if(!quiet)MessageBox.Show(ex.Message,"Sensor repair failed",MessageBoxButtons.OK,MessageBoxIcon.Error);
                return 32;
            }
        }

        if(Has(args,"/uninstall")){
            try{Uninstall(quiet);return 0;}
            catch(Exception ex){
                if(!quiet)MessageBox.Show(ex.Message,"Uninstall failed",MessageBoxButtons.OK,MessageBoxIcon.Error);
                return 31;
            }
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new SetupForm());
        return 0;
    }
}

// R92: one product install root, no uninstall-before-upgrade, user files unchanged.
// This partial class is compiled into the exact 1.7 Setup binary.
internal static partial class SetupProgram
{
    const string UpgradeStageName=".tbme-upgrade";
    const string UpgradeStageMarker="TBME_UPGRADE_R92_OWNED_STAGE_V1";
    const string InstalledV16="1.6.0";
    const string InstalledV170="1.7.0";
    const string InstalledV171="1.7.1";
    const string InstalledV172="1.7.2";
    const string InstalledV173="1.7.3";
    const string InstalledV174="1.7.4";
    const string InstalledV175="1.7.5";
    const string InstalledV176="1.7.6";
    const string InstalledV177="1.7.7";
    const string OfficialV177SetupSHA="395AEE56006F55FD5DCCFB52E1519088CE01A10386840D7008C6BA900136A06D";
    const string OfficialV177MainSHA="A6D4BFD00C918C0601A12D185F414E92F2B6A85927042B811537B0BC37606253";
    const string OfficialV176SetupSHA="D1FE446CC2D8274A5B63E8080FAB15767A6799B5A377584B0F7B923056E2CEE0";
    const string OfficialV176MainSHA="0FA50938D330DB02D7D66593740F51FEE5D3036C59484E5697C34DCBC55A2DF8";
    const string OfficialV175SetupSHA="8E37397F02273952B5866003FC156E152B13FC90D95D80B5DB4208046DD588EC";
    const string OfficialV175MainSHA="25E0565301963467BF290908BE965F73EDDE6BF41EC693A4FE45ED19653FBDB6";
    const string OfficialV174SetupSHA="C00F0C944E4BFBEE93989E4B5A29931D460CC0011ABDC8FDE6A498E467BCC1A1";
    const string OfficialV174MainSHA="279DF6276973D45A1F979792718E7BA1A9DB31A44C3C34E7335C7BE1503A3E3C";
    const string OfficialV173SetupSHA="9EB5C54B4AE4C36F4035F115AC87403D9238AC66AA9AFE58DC5B211311D9774B";
    const string OfficialV173MainSHA="6C8895C040D50C88AF6F6D018F9F70FB481C294B7DABCB083DB78EE35F5D8D1C";
    const string OfficialV172SetupSHA="225BCC259C392DA04F3E0157CAF22F96C4052282AAF02555E6F6E777F4CB8AF4";
    const string OfficialV172MainSHA="84D5DBF6F2E6D1D2E2B3E6D9C9DA523E564A7F5240C08D34A456D934026B829F";
    const string OfficialV171SetupSHA="ABD106630F7BAB3471CAF3F5BD4313DFCF2D61DDE1DF79E72EFE91933C8F2F89";
    const string OfficialV171MainSHA="D50A9D03190719B8385AB2F7F7DBB3129EC7EC1C77ECBD8EF7F29832AEC26420";
    const string OfficialV170SetupSHA="148827212B716238DDB270309F393140EBE3CB935CD0E80D36233220A4BE611E";
    const string OfficialV170MainSHA="B56E322826A86927999A00FB933C17979213798A68C8BB71C2176E68962E30EA";
    const string LegacyInstallerSha="F5130BC2F81383E16912454FCC62E307501885A6256E7241E674A9CF10BAC9C5";
    const string LegacyPreview1InstallerSha="9A1B4F81C07CC39E3D5A329E89EFD834A9DFDC3D7BB6CF12812AC7C300E6B104";

    // Official immutable v1.6.0 GitHub release Setup resource SHA-256, independently
    // extracted without execution. If source/docs were edited, upgrade REFUSES rather
    // than overwriting user modifications. Entire old tree is never deleted.
    static readonly string[] LegacyManagedRows=new string[] {
        "TaskbarMonitorEnhanced.exe|05F9E069C4598FDAD327A41BF1CA34A1498D022119DB81E09F4B3B091C9BA377",
        "TaskbarMonitorEnhanced.exe.config|D2E51872D93F0793C02AD07DCBF8C2802F59708C666548372A4FDDDA5C7C5E4F",
        "TaskbarMonitorEnhanced.ico|0AD07C8E5DB434EE0403FCC92557C89D6E8EDF6A61FABD285C45518DF73A8EEF",
        "TaskbarMonitorEnhanced.cs|F20BD907728537537F3A3F29F80BF4B66AF6012709311299C588F87628C52E47",
        "Source/TaskbarMonitorEnhanced.cs|F20BD907728537537F3A3F29F80BF4B66AF6012709311299C588F87628C52E47",
        "Source/StudioThemes.cs|2DF2445BF2EF0CE50591217143C4E1FBE4A94F5DEACFA9A3E1C75668E6ECAC27",
        "Source/WorkspaceModels.cs|2146D1F369A89A684F504BAB71D6686A381E79260980F7E0ACBCBAC2B3484D19",
        "Source/MonitorWorkspace.cs|DF85A8D274934C74FF4A5D18187A3437E476061AF324F8BE4AB653E252D2C902",
        "Source/WorkspaceSelfTest.cs|54F0BB8802BC98C775143D3CD1DFD607674CE08716CA4EE1DC2CE28D8A60D327",
        "Source/TaskbarMonitorSensorBroker.cs|D650CBC8861027F4A8EC3B48B71769840D2E6CB5F89DDBEBA949EE0CB6A72C0B",
        "Source/TaskbarMonitorSensorSupervisor.cs|DEDF15076D4908A96B0791AC46DAE8F773D4256D9961EE44625F701D5770C60B",
        "Source/TaskbarMonitorEnhanced_Setup.cs|0BA1CF23DE1551EE8C3AB5C37F4367FDE7AD4096E860BA42C9BBD05F0B8F3FAC",
        "Docs/LICENSE|3972DC9744F6499F0F9B2DBF76696F2AE7AD8AF9B23DDE66D6AF86C9DFB36986",
        "Docs/README.md|D58EE6631C2892F13BFAFD3C23F12C55725A3511BFF6FE32F4A56FB03FC3A472",
        "Docs/AUTHORS.md|0005B1D25E43C9CB1AF6C6428D7662F0F6E383D295CE66E5E7768ED8965BFA40",
        "Docs/COPYRIGHT_AND_ATTRIBUTION.md|503CF0194431F8FFE884014165111702061BB16B57C4BA118CE334489DBF4153",
        "Docs/AI_ASSISTED_DEVELOPMENT.md|7793264C5E9256888B069E88BD9ABAE692193CFEB6C28E21ECC8F69F3E3172EB",
        "Docs/THIRD_PARTY_NOTICES.md|41B8A30A4093B30B17802DC22A63B33342D094E78CFCE67113C3C61D3DDE3986",
        "Docs/RELEASE_NOTES_v1.6.0.md|BDC8A5D1DF5636E825F5A97AAAA2361909876EBBBC4C5EA5A614411481651B0F",
        "Docs/UPSTREAM_REFERENCE_GPL_NOTICE.md|14B86621663CDFB7A6750D9E5ABFE7BE8AA72433A56AA08382698BA09261A293",
        "Uninstall.exe|F5130BC2F81383E16912454FCC62E307501885A6256E7241E674A9CF10BAC9C5",
    };

    // Immutable published *unsigned* preview.1 can already be installed. Same Main
    // SHA does not imply that old Setup/maintenance files have been upgraded.
    static readonly string[] LegacyPreview1Rows=new string[]{
        "TaskbarMonitorEnhanced.exe|63A724981E949BA4C91F8BD44F2659F223BDFE0350A2E229CEE7B05535D4BA70",
        "TaskbarMonitorEnhanced.exe.config|D2E51872D93F0793C02AD07DCBF8C2802F59708C666548372A4FDDDA5C7C5E4F",
        "TaskbarMonitorEnhanced.ico|0AD07C8E5DB434EE0403FCC92557C89D6E8EDF6A61FABD285C45518DF73A8EEF",
        "TaskbarMonitorEnhanced.cs|9AC390DB2703EF0CE03C0EBCB7347D27C7875752B4735641DBCD31DF466AFA3D",
        "Source/TaskbarMonitorEnhanced.cs|9AC390DB2703EF0CE03C0EBCB7347D27C7875752B4735641DBCD31DF466AFA3D",
        "Source/StudioThemes.cs|7872BBDDC6DFD95FD8943CD5B714E47A9AB44D40AC15CBD8DA35F643768808CD",
        "Source/WorkspaceModels.cs|2146D1F369A89A684F504BAB71D6686A381E79260980F7E0ACBCBAC2B3484D19",
        "Source/MonitorWorkspace.cs|BA512B04F326DF09B6F9051E34D5CF0C6D24C9DC12DF03B948624DA7F5941F65",
        "Source/WorkspaceSelfTest.cs|5F2B663B2A920F4C7AF0984E0AD40CD5856B809194A8C04BB19B7080630450FF",
        "Source/TaskbarMonitorSensorBroker.cs|D650CBC8861027F4A8EC3B48B71769840D2E6CB5F89DDBEBA949EE0CB6A72C0B",
        "Source/TaskbarMonitorSensorSupervisor.cs|DEDF15076D4908A96B0791AC46DAE8F773D4256D9961EE44625F701D5770C60B",
        "Source/TaskbarMonitorEnhanced_Setup.cs|1354930D0695D4A1C18088A9D8718F407630DD0843257087236BC7796EE88E13",
        "Docs/LICENSE|3972DC9744F6499F0F9B2DBF76696F2AE7AD8AF9B23DDE66D6AF86C9DFB36986",
        "Docs/README.md|F8971E8E21590F5B868E68340F60EC019B97C01F293EF98E410F75D0DE1C8F36",
        "Docs/AUTHORS.md|0005B1D25E43C9CB1AF6C6428D7662F0F6E383D295CE66E5E7768ED8965BFA40",
        "Docs/COPYRIGHT_AND_ATTRIBUTION.md|503CF0194431F8FFE884014165111702061BB16B57C4BA118CE334489DBF4153",
        "Docs/AI_ASSISTED_DEVELOPMENT.md|7793264C5E9256888B069E88BD9ABAE692193CFEB6C28E21ECC8F69F3E3172EB",
        "Docs/THIRD_PARTY_NOTICES.md|7A8F14410B0B934447FB952E7AB0248B8D3342F88358F0F6B0D4332833D3F559",
        "Docs/UPSTREAM_REFERENCE_GPL_NOTICE.md|14B86621663CDFB7A6750D9E5ABFE7BE8AA72433A56AA08382698BA09261A293",
        "Uninstall.exe|9A1B4F81C07CC39E3D5A329E89EFD834A9DFDC3D7BB6CF12812AC7C300E6B104",
        "Source/WallpaperStudio.cs|14DF1E87A49D6D791D4B9501E757E5E2EE466BCEF9618523CF0D1FCE584E461D",
        "Source/TaskbarGlass.cs|E0BDAD9347EB91B149B99D45040F3CABF1AC6E698FD95EEB4361A416C2D65697",
        "Docs/RELEASE_NOTES_v1.7.0.md|8D329AD435B9DCA0F116683114068F3299779E7C12C8218A5E0C113CA0A04B6A",
    };

    // v1.7.0 official immutable public stable, SHA256SUMS and bundled source independently verified.
    // A direct public Stable installation has a root-level duplicate .cs file. A user
    // upgraded from v1.6 may legitimately lack it; its absence is accepted ONLY for
    // the exact verified official Stable source identity; if present it MUST hash-match.
    static readonly string[] OfficialStableV170Rows=new string[] {
        "TaskbarMonitorEnhanced.cs|B65606629A6EA1363B387064933FEED3027ED7CD5007FFDDE76BE938009267E1",
        "TaskbarMonitorEnhanced.exe|B56E322826A86927999A00FB933C17979213798A68C8BB71C2176E68962E30EA",
        "TaskbarMonitorEnhanced.exe.config|D2E51872D93F0793C02AD07DCBF8C2802F59708C666548372A4FDDDA5C7C5E4F",
        "TaskbarMonitorEnhanced.ico|0AD07C8E5DB434EE0403FCC92557C89D6E8EDF6A61FABD285C45518DF73A8EEF",
        "Source/TaskbarMonitorEnhanced.cs|B65606629A6EA1363B387064933FEED3027ED7CD5007FFDDE76BE938009267E1",
        "Source/StudioThemes.cs|7872BBDDC6DFD95FD8943CD5B714E47A9AB44D40AC15CBD8DA35F643768808CD",
        "Source/WallpaperStudio.cs|14DF1E87A49D6D791D4B9501E757E5E2EE466BCEF9618523CF0D1FCE584E461D",
        "Source/TaskbarGlass.cs|E0BDAD9347EB91B149B99D45040F3CABF1AC6E698FD95EEB4361A416C2D65697",
        "Source/WorkspaceModels.cs|2146D1F369A89A684F504BAB71D6686A381E79260980F7E0ACBCBAC2B3484D19",
        "Source/MonitorWorkspace.cs|BA512B04F326DF09B6F9051E34D5CF0C6D24C9DC12DF03B948624DA7F5941F65",
        "Source/WorkspaceSelfTest.cs|5F2B663B2A920F4C7AF0984E0AD40CD5856B809194A8C04BB19B7080630450FF",
        "Source/TaskbarMonitorSensorBroker.cs|D650CBC8861027F4A8EC3B48B71769840D2E6CB5F89DDBEBA949EE0CB6A72C0B",
        "Source/TaskbarMonitorSensorSupervisor.cs|DEDF15076D4908A96B0791AC46DAE8F773D4256D9961EE44625F701D5770C60B",
        "Source/TaskbarMonitorEnhanced_Setup.cs|FB1F970D3ECE01BB15B2EF508F7EE5FEB770BE3E7E60330D89382DA35D0D4938",
        "Docs/LICENSE|3972DC9744F6499F0F9B2DBF76696F2AE7AD8AF9B23DDE66D6AF86C9DFB36986",
        "Docs/README.md|AC63A821E287A16FFED9506A422F87E6717944CF69E66D82650C64F171BD861E",
        "Docs/AUTHORS.md|0005B1D25E43C9CB1AF6C6428D7662F0F6E383D295CE66E5E7768ED8965BFA40",
        "Docs/COPYRIGHT_AND_ATTRIBUTION.md|503CF0194431F8FFE884014165111702061BB16B57C4BA118CE334489DBF4153",
        "Docs/AI_ASSISTED_DEVELOPMENT.md|7793264C5E9256888B069E88BD9ABAE692193CFEB6C28E21ECC8F69F3E3172EB",
        "Docs/THIRD_PARTY_NOTICES.md|7A8F14410B0B934447FB952E7AB0248B8D3342F88358F0F6B0D4332833D3F559",
        "Docs/RELEASE_NOTES_v1.7.0.md|A453660F5A1CB0F654BBC7D6B7627B8E7E708FDFB3AE2F655294E60CC84426DB",
        "Docs/UPSTREAM_REFERENCE_GPL_NOTICE.md|14B86621663CDFB7A6750D9E5ABFE7BE8AA72433A56AA08382698BA09261A293",
        "Uninstall.exe|148827212B716238DDB270309F393140EBE3CB935CD0E80D36233220A4BE611E"
    };

    // R155: exact immutable public v1.7.1 payload, extracted without running Setup.
    // Optional root .cs may be absent following a genuine previous in-place update.
    static readonly string[] OfficialStableV171Rows=new string[] {
        "TaskbarMonitorEnhanced.cs|8754E313DF92478D649918D82E303E48AF8FEA5FEB5B876E9820CB2679CCB06C",
        "TaskbarMonitorEnhanced.exe|D50A9D03190719B8385AB2F7F7DBB3129EC7EC1C77ECBD8EF7F29832AEC26420",
        "TaskbarMonitorEnhanced.exe.config|D2E51872D93F0793C02AD07DCBF8C2802F59708C666548372A4FDDDA5C7C5E4F",
        "TaskbarMonitorEnhanced.ico|0AD07C8E5DB434EE0403FCC92557C89D6E8EDF6A61FABD285C45518DF73A8EEF",
        "Source/TaskbarMonitorEnhanced.cs|8754E313DF92478D649918D82E303E48AF8FEA5FEB5B876E9820CB2679CCB06C",
        "Source/StudioThemes.cs|7872BBDDC6DFD95FD8943CD5B714E47A9AB44D40AC15CBD8DA35F643768808CD",
        "Source/WallpaperStudio.cs|14DF1E87A49D6D791D4B9501E757E5E2EE466BCEF9618523CF0D1FCE584E461D",
        "Source/TaskbarGlass.cs|E0BDAD9347EB91B149B99D45040F3CABF1AC6E698FD95EEB4361A416C2D65697",
        "Source/WorkspaceModels.cs|2146D1F369A89A684F504BAB71D6686A381E79260980F7E0ACBCBAC2B3484D19",
        "Source/MonitorWorkspace.cs|BA512B04F326DF09B6F9051E34D5CF0C6D24C9DC12DF03B948624DA7F5941F65",
        "Source/WorkspaceSelfTest.cs|90F177F3091DEC6FD670A085616D5635FDE8144D098EC2922DC3673C3A817B99",
        "Source/TaskbarMonitorSensorBroker.cs|D650CBC8861027F4A8EC3B48B71769840D2E6CB5F89DDBEBA949EE0CB6A72C0B",
        "Source/TaskbarMonitorSensorSupervisor.cs|DEDF15076D4908A96B0791AC46DAE8F773D4256D9961EE44625F701D5770C60B",
        "Source/TaskbarMonitorEnhanced_Setup.cs|14BE5D92B31F60B2441862AAC5B51C6B151820FE93AB82D7BCD6DE6E07AE017C",
        "Docs/LICENSE|3972DC9744F6499F0F9B2DBF76696F2AE7AD8AF9B23DDE66D6AF86C9DFB36986",
        "Docs/README.md|8B392B6F0B174C2A58F67A8B7CB9760FA4DC14291C3E0D33AAF51F42FA0295EB",
        "Docs/AUTHORS.md|0005B1D25E43C9CB1AF6C6428D7662F0F6E383D295CE66E5E7768ED8965BFA40",
        "Docs/COPYRIGHT_AND_ATTRIBUTION.md|503CF0194431F8FFE884014165111702061BB16B57C4BA118CE334489DBF4153",
        "Docs/AI_ASSISTED_DEVELOPMENT.md|7793264C5E9256888B069E88BD9ABAE692193CFEB6C28E21ECC8F69F3E3172EB",
        "Docs/THIRD_PARTY_NOTICES.md|7A8F14410B0B934447FB952E7AB0248B8D3342F88358F0F6B0D4332833D3F559",
        "Docs/RELEASE_NOTES_v1.7.1.md|BAB1450B20C2E1336E5059A1072B7F34107A5529BE397A936CBC1FDD94143D8F",
        "Docs/UPSTREAM_REFERENCE_GPL_NOTICE.md|14B86621663CDFB7A6750D9E5ABFE7BE8AA72433A56AA08382698BA09261A293",
        "Uninstall.exe|ABD106630F7BAB3471CAF3F5BD4313DFCF2D61DDE1DF79E72EFE91933C8F2F89",
    };

    // R243: exact immutable official v1.7.2 embedded Setup payload SHA-256, no owner data.
    // Root-level .cs is optional for this version; any present copy must match.
    static readonly string[] OfficialStableV172Rows=new string[] {
        "TaskbarMonitorEnhanced.cs|E43DE02A5DB89F8159408F1E1284B9311884736084D3565A5EE1B5035341B362",
        "TaskbarMonitorEnhanced.exe|84D5DBF6F2E6D1D2E2B3E6D9C9DA523E564A7F5240C08D34A456D934026B829F",
        "TaskbarMonitorEnhanced.exe.config|D2E51872D93F0793C02AD07DCBF8C2802F59708C666548372A4FDDDA5C7C5E4F",
        "TaskbarMonitorEnhanced.ico|0AD07C8E5DB434EE0403FCC92557C89D6E8EDF6A61FABD285C45518DF73A8EEF",
        "Source/TaskbarMonitorEnhanced.cs|E43DE02A5DB89F8159408F1E1284B9311884736084D3565A5EE1B5035341B362",
        "Source/StudioThemes.cs|7872BBDDC6DFD95FD8943CD5B714E47A9AB44D40AC15CBD8DA35F643768808CD",
        "Source/WallpaperStudio.cs|14DF1E87A49D6D791D4B9501E757E5E2EE466BCEF9618523CF0D1FCE584E461D",
        "Source/TaskbarGlass.cs|B71B4F1CD41A12A82DC470534563D2EA24FAAF38233D0158AC13085EF7F75ED0",
        "Source/WorkspaceModels.cs|2146D1F369A89A684F504BAB71D6686A381E79260980F7E0ACBCBAC2B3484D19",
        "Source/MonitorWorkspace.cs|BA512B04F326DF09B6F9051E34D5CF0C6D24C9DC12DF03B948624DA7F5941F65",
        "Source/WorkspaceSelfTest.cs|76C65D5A16F384B7600EB4BDEDE7551283235CA32A662A248AF6A6DE03CD5A35",
        "Source/TaskbarMonitorSensorBroker.cs|D650CBC8861027F4A8EC3B48B71769840D2E6CB5F89DDBEBA949EE0CB6A72C0B",
        "Source/TaskbarMonitorSensorSupervisor.cs|DEDF15076D4908A96B0791AC46DAE8F773D4256D9961EE44625F701D5770C60B",
        "Source/TaskbarMonitorEnhanced_Setup.cs|A3AD433D281894BB514F225ADEBA007B5F2E8641A1337BF57DE5248D2F96246A",
        "Docs/LICENSE|3972DC9744F6499F0F9B2DBF76696F2AE7AD8AF9B23DDE66D6AF86C9DFB36986",
        "Docs/README.md|FE7F6354C295B71607D14AB5D51843C2C951B2E984399FA5AA00BBF8AA4F8F0E",
        "Docs/AUTHORS.md|0005B1D25E43C9CB1AF6C6428D7662F0F6E383D295CE66E5E7768ED8965BFA40",
        "Docs/COPYRIGHT_AND_ATTRIBUTION.md|503CF0194431F8FFE884014165111702061BB16B57C4BA118CE334489DBF4153",
        "Docs/AI_ASSISTED_DEVELOPMENT.md|7793264C5E9256888B069E88BD9ABAE692193CFEB6C28E21ECC8F69F3E3172EB",
        "Docs/THIRD_PARTY_NOTICES.md|7A8F14410B0B934447FB952E7AB0248B8D3342F88358F0F6B0D4332833D3F559",
        "Docs/RELEASE_NOTES_v1.7.2.md|088EEAF5EE5200CE9686134CBD15F5C6C9436E8027E9DF1613190762911D01FA",
        "Docs/UPSTREAM_REFERENCE_GPL_NOTICE.md|14B86621663CDFB7A6750D9E5ABFE7BE8AA72433A56AA08382698BA09261A293",
        "Uninstall.exe|225BCC259C392DA04F3E0157CAF22F96C4052282AAF02555E6F6E777F4CB8AF4",
    };

    // R256: pinned immutable public v1.7.3 fresh/upgraded source; never owner data.
    // Root-level .cs may be present only if exact SHA matched.
    static readonly string[] OfficialStableV173Rows=new string[] {
        "TaskbarMonitorEnhanced.cs|5BB6F7D089251474E29ECFBCBB59653D18FA8664FD783BAB311B61D947851D32",
        "TaskbarMonitorEnhanced.exe|6C8895C040D50C88AF6F6D018F9F70FB481C294B7DABCB083DB78EE35F5D8D1C",
        "TaskbarMonitorEnhanced.exe.config|D2E51872D93F0793C02AD07DCBF8C2802F59708C666548372A4FDDDA5C7C5E4F",
        "TaskbarMonitorEnhanced.ico|0AD07C8E5DB434EE0403FCC92557C89D6E8EDF6A61FABD285C45518DF73A8EEF",
        "Source/TaskbarMonitorEnhanced.cs|5BB6F7D089251474E29ECFBCBB59653D18FA8664FD783BAB311B61D947851D32",
        "Source/StudioThemes.cs|7872BBDDC6DFD95FD8943CD5B714E47A9AB44D40AC15CBD8DA35F643768808CD",
        "Source/WallpaperStudio.cs|14DF1E87A49D6D791D4B9501E757E5E2EE466BCEF9618523CF0D1FCE584E461D",
        "Source/TaskbarGlass.cs|26B3E98C4E30361037EA35AE6326DE45C8087D8D562B7A7232D8FCF2CA589AAF",
        "Source/WorkspaceModels.cs|2146D1F369A89A684F504BAB71D6686A381E79260980F7E0ACBCBAC2B3484D19",
        "Source/MonitorWorkspace.cs|BA512B04F326DF09B6F9051E34D5CF0C6D24C9DC12DF03B948624DA7F5941F65",
        "Source/WorkspaceSelfTest.cs|F11D20C67056AC054C690C630044F717657DAB6FE26E5997EEBFF25947CF69B9",
        "Source/TaskbarMonitorSensorBroker.cs|D650CBC8861027F4A8EC3B48B71769840D2E6CB5F89DDBEBA949EE0CB6A72C0B",
        "Source/TaskbarMonitorSensorSupervisor.cs|DEDF15076D4908A96B0791AC46DAE8F773D4256D9961EE44625F701D5770C60B",
        "Source/TaskbarMonitorEnhanced_Setup.cs|25C2E5BD69BC4210757695501606942ED3ADD0C250848A2CC0B6AB4D8070578F",
        "Docs/LICENSE|3972DC9744F6499F0F9B2DBF76696F2AE7AD8AF9B23DDE66D6AF86C9DFB36986",
        "Docs/README.md|48026FC6A842A6BAEC519E04555A7291CD3DE339CBE59B9AAE635AAA1C1E8D37",
        "Docs/AUTHORS.md|0005B1D25E43C9CB1AF6C6428D7662F0F6E383D295CE66E5E7768ED8965BFA40",
        "Docs/COPYRIGHT_AND_ATTRIBUTION.md|503CF0194431F8FFE884014165111702061BB16B57C4BA118CE334489DBF4153",
        "Docs/AI_ASSISTED_DEVELOPMENT.md|7793264C5E9256888B069E88BD9ABAE692193CFEB6C28E21ECC8F69F3E3172EB",
        "Docs/THIRD_PARTY_NOTICES.md|7A8F14410B0B934447FB952E7AB0248B8D3342F88358F0F6B0D4332833D3F559",
        "Docs/RELEASE_NOTES_v1.7.3.md|CA1A8889BA56AA802BD9A2E2C0A45F885004DB5868702EBAE1076BF52C0F7683",
        "Docs/UPSTREAM_REFERENCE_GPL_NOTICE.md|14B86621663CDFB7A6750D9E5ABFE7BE8AA72433A56AA08382698BA09261A293",
        "Uninstall.exe|9EB5C54B4AE4C36F4035F115AC87403D9238AC66AA9AFE58DC5B211311D9774B",
    };

    // R265: exact 22-file immutable official 1.7.4 ancestor; no optional root source.
    static readonly string[] OfficialStableV174Rows=new string[] {
        "TaskbarMonitorEnhanced.exe|279DF6276973D45A1F979792718E7BA1A9DB31A44C3C34E7335C7BE1503A3E3C",
        "TaskbarMonitorEnhanced.exe.config|D2E51872D93F0793C02AD07DCBF8C2802F59708C666548372A4FDDDA5C7C5E4F",
        "TaskbarMonitorEnhanced.ico|0AD07C8E5DB434EE0403FCC92557C89D6E8EDF6A61FABD285C45518DF73A8EEF",
        "Source/TaskbarMonitorEnhanced.cs|24460E03A325FD3F085302EAED0DDD7511BAD71F9DE1C722EDD61408CA754CF9",
        "Source/StudioThemes.cs|7872BBDDC6DFD95FD8943CD5B714E47A9AB44D40AC15CBD8DA35F643768808CD",
        "Source/WallpaperStudio.cs|14DF1E87A49D6D791D4B9501E757E5E2EE466BCEF9618523CF0D1FCE584E461D",
        "Source/TaskbarGlass.cs|26B3E98C4E30361037EA35AE6326DE45C8087D8D562B7A7232D8FCF2CA589AAF",
        "Source/WorkspaceModels.cs|2146D1F369A89A684F504BAB71D6686A381E79260980F7E0ACBCBAC2B3484D19",
        "Source/MonitorWorkspace.cs|BA512B04F326DF09B6F9051E34D5CF0C6D24C9DC12DF03B948624DA7F5941F65",
        "Source/WorkspaceSelfTest.cs|23B946D913810FB074F2C904CFF133A44948C57724818E3250B8E21B4D519E37",
        "Source/TaskbarMonitorSensorBroker.cs|D650CBC8861027F4A8EC3B48B71769840D2E6CB5F89DDBEBA949EE0CB6A72C0B",
        "Source/TaskbarMonitorSensorSupervisor.cs|DEDF15076D4908A96B0791AC46DAE8F773D4256D9961EE44625F701D5770C60B",
        "Source/TaskbarMonitorEnhanced_Setup.cs|957B655CC028F4D68EB88A430CA4330107D7623004585601233DABD67ABED6B2",
        "Docs/LICENSE|3972DC9744F6499F0F9B2DBF76696F2AE7AD8AF9B23DDE66D6AF86C9DFB36986",
        "Docs/README.md|0D5CC4DAE08C3131DCCC095109EDEA997C757DE65E7A8BA296A2F399E5B67292",
        "Docs/AUTHORS.md|0005B1D25E43C9CB1AF6C6428D7662F0F6E383D295CE66E5E7768ED8965BFA40",
        "Docs/COPYRIGHT_AND_ATTRIBUTION.md|503CF0194431F8FFE884014165111702061BB16B57C4BA118CE334489DBF4153",
        "Docs/AI_ASSISTED_DEVELOPMENT.md|7793264C5E9256888B069E88BD9ABAE692193CFEB6C28E21ECC8F69F3E3172EB",
        "Docs/THIRD_PARTY_NOTICES.md|7A8F14410B0B934447FB952E7AB0248B8D3342F88358F0F6B0D4332833D3F559",
        "Docs/RELEASE_NOTES_v1.7.4.md|FF604D0B69C2116CD1A72C08189FCB18ACA5435894E3FECD822FE972CA996E07",
        "Docs/UPSTREAM_REFERENCE_GPL_NOTICE.md|14B86621663CDFB7A6750D9E5ABFE7BE8AA72433A56AA08382698BA09261A293",
        "Uninstall.exe|C00F0C944E4BFBEE93989E4B5A29931D460CC0011ABDC8FDE6A498E467BCC1A1",
    };

    // R273: immutable public v1.7.5, 22 exact managed files, not user config.
    static readonly string[] OfficialStableV175Rows=new string[] {
        "TaskbarMonitorEnhanced.exe|25E0565301963467BF290908BE965F73EDDE6BF41EC693A4FE45ED19653FBDB6",
        "TaskbarMonitorEnhanced.exe.config|D2E51872D93F0793C02AD07DCBF8C2802F59708C666548372A4FDDDA5C7C5E4F",
        "TaskbarMonitorEnhanced.ico|0AD07C8E5DB434EE0403FCC92557C89D6E8EDF6A61FABD285C45518DF73A8EEF",
        "Source/TaskbarMonitorEnhanced.cs|53A37483D56C20A28FB4FA4D8DC207F3B3E06E081F32B7506C8438E321EC0C9E",
        "Source/StudioThemes.cs|7872BBDDC6DFD95FD8943CD5B714E47A9AB44D40AC15CBD8DA35F643768808CD",
        "Source/WallpaperStudio.cs|14DF1E87A49D6D791D4B9501E757E5E2EE466BCEF9618523CF0D1FCE584E461D",
        "Source/TaskbarGlass.cs|26B3E98C4E30361037EA35AE6326DE45C8087D8D562B7A7232D8FCF2CA589AAF",
        "Source/WorkspaceModels.cs|2146D1F369A89A684F504BAB71D6686A381E79260980F7E0ACBCBAC2B3484D19",
        "Source/MonitorWorkspace.cs|BA512B04F326DF09B6F9051E34D5CF0C6D24C9DC12DF03B948624DA7F5941F65",
        "Source/WorkspaceSelfTest.cs|C9872DAA819E9CA7453C158F5A4CB4CAB16FB1078606EE0BAF568555DBE68E57",
        "Source/TaskbarMonitorSensorBroker.cs|D650CBC8861027F4A8EC3B48B71769840D2E6CB5F89DDBEBA949EE0CB6A72C0B",
        "Source/TaskbarMonitorSensorSupervisor.cs|DEDF15076D4908A96B0791AC46DAE8F773D4256D9961EE44625F701D5770C60B",
        "Source/TaskbarMonitorEnhanced_Setup.cs|66626A8A762ED34EDC91C7C3D03AD9889CAA5A8FEB64E973EF0EF0E08CDC8AF8",
        "Docs/LICENSE|3972DC9744F6499F0F9B2DBF76696F2AE7AD8AF9B23DDE66D6AF86C9DFB36986",
        "Docs/README.md|74955DE4D73DE9D7AD1C394187E6ACFC95013A92799D8BA9BB7DBDC5F4E7D701",
        "Docs/AUTHORS.md|0005B1D25E43C9CB1AF6C6428D7662F0F6E383D295CE66E5E7768ED8965BFA40",
        "Docs/COPYRIGHT_AND_ATTRIBUTION.md|503CF0194431F8FFE884014165111702061BB16B57C4BA118CE334489DBF4153",
        "Docs/AI_ASSISTED_DEVELOPMENT.md|7793264C5E9256888B069E88BD9ABAE692193CFEB6C28E21ECC8F69F3E3172EB",
        "Docs/THIRD_PARTY_NOTICES.md|7A8F14410B0B934447FB952E7AB0248B8D3342F88358F0F6B0D4332833D3F559",
        "Docs/RELEASE_NOTES_v1.7.5.md|AD3642ABD89BA1C31B2EEA83847FC3ED8861AEBFF9E664B5169A287601AAA16A",
        "Docs/UPSTREAM_REFERENCE_GPL_NOTICE.md|14B86621663CDFB7A6750D9E5ABFE7BE8AA72433A56AA08382698BA09261A293",
        "Uninstall.exe|8E37397F02273952B5866003FC156E152B13FC90D95D80B5DB4208046DD588EC",
    };

    // Official immutable v1.7.6 predecessor: exact 22 managed paths and SHA.
    static readonly string[] OfficialStableV176Rows=new string[] {
        "TaskbarMonitorEnhanced.exe|0FA50938D330DB02D7D66593740F51FEE5D3036C59484E5697C34DCBC55A2DF8",
        "TaskbarMonitorEnhanced.exe.config|D2E51872D93F0793C02AD07DCBF8C2802F59708C666548372A4FDDDA5C7C5E4F",
        "TaskbarMonitorEnhanced.ico|0AD07C8E5DB434EE0403FCC92557C89D6E8EDF6A61FABD285C45518DF73A8EEF",
        "Source/TaskbarMonitorEnhanced.cs|086B21052E050B56B753634918D5279C1CAFE4918FE8F2D4FB6F4DC05CF040D5",
        "Source/StudioThemes.cs|7872BBDDC6DFD95FD8943CD5B714E47A9AB44D40AC15CBD8DA35F643768808CD",
        "Source/WallpaperStudio.cs|14DF1E87A49D6D791D4B9501E757E5E2EE466BCEF9618523CF0D1FCE584E461D",
        "Source/TaskbarGlass.cs|396AD7DA39674099999ADB4A9C98458A876A8DE5BFABB1DC640EE46BC2F63306",
        "Source/WorkspaceModels.cs|2146D1F369A89A684F504BAB71D6686A381E79260980F7E0ACBCBAC2B3484D19",
        "Source/MonitorWorkspace.cs|BA512B04F326DF09B6F9051E34D5CF0C6D24C9DC12DF03B948624DA7F5941F65",
        "Source/WorkspaceSelfTest.cs|2A3C0152CB8727B8F5AD281AAAA730F12C8D6CBC667866C751C3B866026563B1",
        "Source/TaskbarMonitorSensorBroker.cs|D650CBC8861027F4A8EC3B48B71769840D2E6CB5F89DDBEBA949EE0CB6A72C0B",
        "Source/TaskbarMonitorSensorSupervisor.cs|DEDF15076D4908A96B0791AC46DAE8F773D4256D9961EE44625F701D5770C60B",
        "Source/TaskbarMonitorEnhanced_Setup.cs|EFC7104361C855FBE40A673A7CFBD868AAFE663ADC4F465D80A69E8D0E771F7C",
        "Docs/LICENSE|3972DC9744F6499F0F9B2DBF76696F2AE7AD8AF9B23DDE66D6AF86C9DFB36986",
        "Docs/README.md|9CCB3096C6697429527A24E0E2105E5CD7E6B76CEB39B70C8169570D8D796675",
        "Docs/AUTHORS.md|0005B1D25E43C9CB1AF6C6428D7662F0F6E383D295CE66E5E7768ED8965BFA40",
        "Docs/COPYRIGHT_AND_ATTRIBUTION.md|503CF0194431F8FFE884014165111702061BB16B57C4BA118CE334489DBF4153",
        "Docs/AI_ASSISTED_DEVELOPMENT.md|7793264C5E9256888B069E88BD9ABAE692193CFEB6C28E21ECC8F69F3E3172EB",
        "Docs/THIRD_PARTY_NOTICES.md|7A8F14410B0B934447FB952E7AB0248B8D3342F88358F0F6B0D4332833D3F559",
        "Docs/RELEASE_NOTES_v1.7.6.md|D8CF4A1F6596A043E4718E787D0098E4A10ED2D996CEF8766FC268DB72E620E7",
        "Docs/UPSTREAM_REFERENCE_GPL_NOTICE.md|14B86621663CDFB7A6750D9E5ABFE7BE8AA72433A56AA08382698BA09261A293",
        "Uninstall.exe|D1FE446CC2D8274A5B63E8080FAB15767A6799B5A377584B0F7B923056E2CEE0",
    };

    // Published immutable official v1.7.7 managed identities, exact 22 files.
    static readonly string[] OfficialStableV177Rows=new string[] {
        "TaskbarMonitorEnhanced.exe|A6D4BFD00C918C0601A12D185F414E92F2B6A85927042B811537B0BC37606253",
        "TaskbarMonitorEnhanced.exe.config|D2E51872D93F0793C02AD07DCBF8C2802F59708C666548372A4FDDDA5C7C5E4F",
        "TaskbarMonitorEnhanced.ico|0AD07C8E5DB434EE0403FCC92557C89D6E8EDF6A61FABD285C45518DF73A8EEF",
        "Source/TaskbarMonitorEnhanced.cs|B95546C73093486D54395FBEE891002A49913F9234713C16A11DCAC23EDFD962",
        "Source/StudioThemes.cs|7872BBDDC6DFD95FD8943CD5B714E47A9AB44D40AC15CBD8DA35F643768808CD",
        "Source/WallpaperStudio.cs|14DF1E87A49D6D791D4B9501E757E5E2EE466BCEF9618523CF0D1FCE584E461D",
        "Source/TaskbarGlass.cs|396AD7DA39674099999ADB4A9C98458A876A8DE5BFABB1DC640EE46BC2F63306",
        "Source/WorkspaceModels.cs|2146D1F369A89A684F504BAB71D6686A381E79260980F7E0ACBCBAC2B3484D19",
        "Source/MonitorWorkspace.cs|BA512B04F326DF09B6F9051E34D5CF0C6D24C9DC12DF03B948624DA7F5941F65",
        "Source/WorkspaceSelfTest.cs|7D1B3A1FA0A46CAC47D0063E2ED7929C5299F2DE0FD394BD6C82E53B72590FA5",
        "Source/TaskbarMonitorSensorBroker.cs|D650CBC8861027F4A8EC3B48B71769840D2E6CB5F89DDBEBA949EE0CB6A72C0B",
        "Source/TaskbarMonitorSensorSupervisor.cs|DEDF15076D4908A96B0791AC46DAE8F773D4256D9961EE44625F701D5770C60B",
        "Source/TaskbarMonitorEnhanced_Setup.cs|65284119FE8759314BDDD3309837B2377AB6682BE98DF3995363908822A4CA38",
        "Docs/LICENSE|3972DC9744F6499F0F9B2DBF76696F2AE7AD8AF9B23DDE66D6AF86C9DFB36986",
        "Docs/README.md|F136012748AD1D1560EC5D5342D2D1228E5A90EE59B094ECA0E8D3CCAB51A63F",
        "Docs/AUTHORS.md|0005B1D25E43C9CB1AF6C6428D7662F0F6E383D295CE66E5E7768ED8965BFA40",
        "Docs/COPYRIGHT_AND_ATTRIBUTION.md|503CF0194431F8FFE884014165111702061BB16B57C4BA118CE334489DBF4153",
        "Docs/AI_ASSISTED_DEVELOPMENT.md|7793264C5E9256888B069E88BD9ABAE692193CFEB6C28E21ECC8F69F3E3172EB",
        "Docs/THIRD_PARTY_NOTICES.md|7A8F14410B0B934447FB952E7AB0248B8D3342F88358F0F6B0D4332833D3F559",
        "Docs/RELEASE_NOTES_v1.7.7.md|74FDDEBDDE733F1F0E2BE2C84824E4784D4CC244094660199094DA5550091A83",
        "Docs/UPSTREAM_REFERENCE_GPL_NOTICE.md|14B86621663CDFB7A6750D9E5ABFE7BE8AA72433A56AA08382698BA09261A293",
        "Uninstall.exe|395AEE56006F55FD5DCCFB52E1519088CE01A10386840D7008C6BA900136A06D",
    };

    sealed class UpgradeTarget
    {
        internal readonly string Rel;
        internal readonly string ResourceName; // special @SELF or @INSTALLSTATE, null means removal
        internal UpgradeTarget(string rel,string resource){Rel=rel;ResourceName=resource;}
    }

    static readonly UpgradeTarget[] UpgradeTargets=new UpgradeTarget[]{
        new UpgradeTarget("TaskbarMonitorEnhanced.exe","Payload.TaskbarMonitorEnhanced.exe"),
        new UpgradeTarget("TaskbarMonitorEnhanced.exe.config","Payload.TaskbarMonitorEnhanced.exe.config"),
        new UpgradeTarget("TaskbarMonitorEnhanced.ico","Payload.TaskbarMonitorEnhanced.ico"),
        new UpgradeTarget("Source/TaskbarMonitorEnhanced.cs","Payload.TaskbarMonitorEnhanced.cs"),
        new UpgradeTarget("Source/StudioThemes.cs","Payload.StudioThemes.cs"),
        new UpgradeTarget("Source/WallpaperStudio.cs","Payload.WallpaperStudio.cs"),
        new UpgradeTarget("Source/TaskbarGlass.cs","Payload.TaskbarGlass.cs"),
        new UpgradeTarget("Source/WorkspaceModels.cs","Payload.WorkspaceModels.cs"),
        new UpgradeTarget("Source/MonitorWorkspace.cs","Payload.MonitorWorkspace.cs"),
        new UpgradeTarget("Source/WorkspaceSelfTest.cs","Payload.WorkspaceSelfTest.cs"),
        new UpgradeTarget("Source/TaskbarMonitorSensorBroker.cs","Payload.TaskbarMonitorSensorBroker.cs"),
        new UpgradeTarget("Source/TaskbarMonitorSensorSupervisor.cs","Payload.TaskbarMonitorSensorSupervisor.cs"),
        new UpgradeTarget("Source/TaskbarMonitorEnhanced_Setup.cs","Payload.TaskbarMonitorEnhanced_Setup.cs"),
        new UpgradeTarget("Docs/LICENSE","Payload.LICENSE"),
        new UpgradeTarget("Docs/README.md","Payload.README.md"),
        new UpgradeTarget("Docs/AUTHORS.md","Payload.AUTHORS.md"),
        new UpgradeTarget("Docs/COPYRIGHT_AND_ATTRIBUTION.md","Payload.COPYRIGHT_AND_ATTRIBUTION.md"),
        new UpgradeTarget("Docs/AI_ASSISTED_DEVELOPMENT.md","Payload.AI_ASSISTED_DEVELOPMENT.md"),
        new UpgradeTarget("Docs/THIRD_PARTY_NOTICES.md","Payload.THIRD_PARTY_NOTICES.md"),
        new UpgradeTarget("Docs/RELEASE_NOTES_v1.7.8.md","Payload.RELEASE_NOTES_v1.7.8.md"),
        new UpgradeTarget("Docs/UPSTREAM_REFERENCE_GPL_NOTICE.md","Payload.UPSTREAM_REFERENCE_GPL_NOTICE.md"),
        new UpgradeTarget("Uninstall.exe","@SELF"),
        new UpgradeTarget("install_state.json","@INSTALLSTATE"),
        new UpgradeTarget("TaskbarMonitorEnhanced.cs",null), // redundant v1.6 root duplicate
        new UpgradeTarget("Docs/RELEASE_NOTES_v1.6.0.md",null), // superseded v1.6 official file
        new UpgradeTarget("Docs/RELEASE_NOTES_v1.7.0.md",null), // exact historical managed note only
        new UpgradeTarget("Docs/RELEASE_NOTES_v1.7.1.md",null),
        new UpgradeTarget("Docs/RELEASE_NOTES_v1.7.2.md",null),
        new UpgradeTarget("Docs/RELEASE_NOTES_v1.7.3.md",null),
        new UpgradeTarget("Docs/RELEASE_NOTES_v1.7.4.md",null),
        new UpgradeTarget("Docs/RELEASE_NOTES_v1.7.5.md",null),
        new UpgradeTarget("Docs/RELEASE_NOTES_v1.7.6.md",null),
        new UpgradeTarget("Docs/RELEASE_NOTES_v1.7.7.md",null) // previous version, guarded byte-for-byte
    };

    static string UpgradeHash(string path)
    {
        using(SHA256 sha=SHA256.Create())
        using(FileStream f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read))
            return BitConverter.ToString(sha.ComputeHash(f)).Replace("-","");
    }

    static string UpgradeHash(byte[] bytes)
    {
        using(SHA256 sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-","");
    }

    static Dictionary<string,string> LegacyExpected(string version,string channel)
    {
        string[] rows;
        string expectedSetup;
        int count;
        if(version==InstalledV16 && channel=="OFFICIAL_V16")
        { rows=LegacyManagedRows; expectedSetup=LegacyInstallerSha; count=21; }
        else if(version==InstalledV170 && channel=="OFFICIAL_STABLE_V170")
        { rows=OfficialStableV170Rows; expectedSetup=OfficialV170SetupSHA; count=23; }
        else if(version==InstalledV171 && channel=="OFFICIAL_STABLE_V171")
        { rows=OfficialStableV171Rows; expectedSetup=OfficialV171SetupSHA; count=23; }
        else if(version==InstalledV172 && channel=="OFFICIAL_STABLE_V172")
        { rows=OfficialStableV172Rows; expectedSetup=OfficialV172SetupSHA; count=23; }
        else if(version==InstalledV173 && channel=="OFFICIAL_STABLE_V173")
        { rows=OfficialStableV173Rows; expectedSetup=OfficialV173SetupSHA; count=23; }
        else if(version==InstalledV177 && channel=="OFFICIAL_STABLE_V177")
        { rows=OfficialStableV177Rows; expectedSetup=OfficialV177SetupSHA; count=22; }
        else if(version==InstalledV176 && channel=="OFFICIAL_STABLE_V176")
        { rows=OfficialStableV176Rows; expectedSetup=OfficialV176SetupSHA; count=22; }
        else if(version==InstalledV175 && channel=="OFFICIAL_STABLE_V175")
        { rows=OfficialStableV175Rows; expectedSetup=OfficialV175SetupSHA; count=22; }
        else if(version==InstalledV174 && channel=="OFFICIAL_STABLE_V174")
        { rows=OfficialStableV174Rows; expectedSetup=OfficialV174SetupSHA; count=22; }
        else if(version==InstalledV170 && channel=="PREVIEW1")
        { rows=LegacyPreview1Rows; expectedSetup=LegacyPreview1InstallerSha; count=23; }
        else throw new InvalidDataException("Unsupported exact prior source identity; no downgrade/second root.");
        Dictionary<string,string> expected=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        foreach(string line in rows){
            string[] parts=line.Split('|');
            if(parts.Length!=2 || !Regex.IsMatch(parts[1],"^[0-9A-F]{64}$") || expected.ContainsKey(parts[0]))
                throw new InvalidDataException("Pinned prior stable file inventory malformed.");
            expected.Add(parts[0],parts[1]);
        }
        if(expected.Count!=count || expected["Uninstall.exe"]!=expectedSetup)
            throw new InvalidDataException("Pinned prior official resource/Setup SHA changed.");
        return expected;
    }

    static string UPath(string relative)
    {
        if(String.IsNullOrWhiteSpace(relative) || Path.IsPathRooted(relative) ||
           relative.Contains("..") || relative.Contains(":") || relative.StartsWith("/") ||
           relative.StartsWith("\\"))
            throw new InvalidDataException("Upgrade refused unsafe resource path.");
        string path=Path.GetFullPath(Path.Combine(AppRoot,relative.Replace('/',Path.DirectorySeparatorChar)));
        string root=Path.GetFullPath(AppRoot).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
        if(!path.StartsWith(root,StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Upgrade refused path outside canonical app root.");
        // Path.GetFullPath is lexical only; reject junctions/links before any live I/O.
        CheckNoReparse(path);
        return path;
    }

    static void CheckNoReparse(string path)
    {
        string root=Path.GetFullPath(AppRoot);
        string current=Path.GetFullPath(path);
        while(!String.IsNullOrEmpty(current)){
            // File.Exists can hide inaccessible or dangling reparse paths.
            // Only genuinely absent components may be skipped; all other I/O
            // errors must fail closed before a rollback/write/delete.
            try{
                if((File.GetAttributes(current)&FileAttributes.ReparsePoint)!=0)
                    throw new IOException("Upgrade refuses an app component symlink/junction: "+current);
            }catch(FileNotFoundException){}catch(DirectoryNotFoundException){}
            if(String.Equals(current,root,StringComparison.OrdinalIgnoreCase))break;
            current=Path.GetDirectoryName(current);
        }
    }

    static bool ExistingRegistered()
    {
        using(RegistryKey key=Registry.CurrentUser.OpenSubKey(UninstallKey,false))
            return key!=null;
    }

    static void CheckSingleCanonicalRoot()
    {
        if(!Directory.Exists(AppRoot)||!File.Exists(AppExe))
            throw new InvalidOperationException("Existing installation is partial; will not create a second copy.");
        CheckNoReparse(AppRoot);
        using(RegistryKey key=Registry.CurrentUser.OpenSubKey(UninstallKey,false)){
            if(key==null || !String.Equals(Convert.ToString(key.GetValue("DisplayName")),Product,StringComparison.Ordinal) ||
               !String.Equals(Path.GetFullPath(Convert.ToString(key.GetValue("InstallLocation"))),Path.GetFullPath(AppRoot),StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Installer registration does not identify the canonical per-user root; refusing to create another installation.");
        }
        string[] machineRoots=new string[]{
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),AppFolder),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),AppFolder)
        };
        foreach(string root in machineRoots){
            if(!String.IsNullOrWhiteSpace(root) && File.Exists(Path.Combine(root,"TaskbarMonitorEnhanced.exe")))
                throw new InvalidOperationException("Conflicting Program Files product detected. Choose one canonical install before update.");
        }
        foreach(UpgradeTarget target in UpgradeTargets)CheckNoReparse(UPath(target.Rel));
        foreach(string name in new string[]{"config.json","config.json.bak","sensor_backend_state.json","Logs","Backups","Updates","Validation","Source","Docs"})
            CheckNoReparse(UPath(name));
    }

    static string CurrentInstalledVersion()
    {
        string statePath=UPath("install_state.json");
        if(!File.Exists(statePath))throw new InvalidOperationException("Existing install_state missing; preserve data and refuse ambiguous upgrade.");
        string source=File.ReadAllText(statePath,Encoding.UTF8);
        if(!Regex.IsMatch(source,"\\\"ProductIdentity\\\"\\s*:\\s*\\\"LOCKED\\\""))
            throw new InvalidDataException("Installed product identity is unknown.");
        Match m=Regex.Match(source,"\\\"Version\\\"\\s*:\\s*\\\"(?<v>[0-9.]+)\\\"");
        Match pub=Regex.Match(source,"\\\"PublicVersion\\\"\\s*:\\s*\\\"(?<v>[0-9.]+)\\\"");
        if(!m.Success || !pub.Success || m.Groups["v"].Value!=pub.Groups["v"].Value)
            throw new InvalidDataException("Installed version fields disagree.");
        return m.Groups["v"].Value;
    }

    static string ReplaceStateVersion(string state,string field,string previous)
    {
        string rx="(\\\""+Regex.Escape(field)+"\\\"\\s*:\\s*\\\")"+
            Regex.Escape(previous)+"(\\\")";
        if(Regex.Matches(state,rx).Count!=1)
            throw new InvalidDataException("Old version field ambiguous: "+field);
        return Regex.Replace(state,rx,delegate(Match m){return m.Groups[1].Value+Version+m.Groups[2].Value;});
    }
    static string NewInstallState(string source)
    {
        Match installed=Regex.Match(source,"\\\"Version\\\"\\s*:\\s*\\\"(?<v>[0-9.]+)\\\"");
        Match pub=Regex.Match(source,"\\\"PublicVersion\\\"\\s*:\\s*\\\"(?<v>[0-9.]+)\\\"");
        if(!installed.Success || !pub.Success || installed.Groups["v"].Value!=pub.Groups["v"].Value)
            throw new InvalidDataException("Old install state Version/PublicVersion mismatch.");
        string prior=installed.Groups["v"].Value;
        if(prior==Version)return source;
        if(prior!=InstalledV16 && prior!=InstalledV170 && prior!=InstalledV171 && prior!=InstalledV172 && prior!=InstalledV173 && prior!=InstalledV174 && prior!=InstalledV175 && prior!=InstalledV176 && prior!=InstalledV177)
            throw new InvalidDataException("Prior install state version not a pinned officially allowed ancestor.");
        string next=ReplaceStateVersion(source,"Version",prior);
        next=ReplaceStateVersion(next,"PublicVersion",prior);
        return next;
    }

    static Dictionary<string,byte[]> PrepareNewBytes(string previousState)
    {
        Dictionary<string,byte[]> fresh=new Dictionary<string,byte[]>(StringComparer.OrdinalIgnoreCase);
        foreach(UpgradeTarget t in UpgradeTargets){
            if(t.ResourceName==null)continue;
            byte[] bytes;
            if(t.ResourceName=="@SELF")bytes=File.ReadAllBytes(System.Windows.Forms.Application.ExecutablePath);
            else if(t.ResourceName=="@INSTALLSTATE")bytes=new UTF8Encoding(false).GetBytes(NewInstallState(previousState));
            else{
                using(Stream stream=Resource(t.ResourceName)){
                    if(stream==null || stream.Length==0)throw new InvalidDataException("Missing upgrade payload "+t.ResourceName);
                    using(MemoryStream ms=new MemoryStream()){
                        stream.CopyTo(ms);bytes=ms.ToArray();
                    }
                }
            }
            if(bytes.Length<1 || fresh.ContainsKey(t.Rel))throw new InvalidDataException("Duplicate/empty payload "+t.Rel);
            fresh.Add(t.Rel,bytes);
        }
        if(fresh.Count!=UpgradeTargets.Length-10)
            throw new InvalidDataException("Upgrade static target map is invalid.");
        return fresh;
    }

    static bool IsOptionalStableLegacyRoot(string rel,string channel)
    {
        // Only one SHA-pinned historical Stable file may be absent. Any present
        // occurrence still requires the exact immutable published source hash.
        return (channel=="OFFICIAL_STABLE_V170" || channel=="OFFICIAL_STABLE_V171" || channel=="OFFICIAL_STABLE_V172" || channel=="OFFICIAL_STABLE_V173") &&
               String.Equals(rel,"TaskbarMonitorEnhanced.cs",StringComparison.Ordinal);
    }

    static void VerifyLegacyFiles(Dictionary<string,string> legacy,string channel)
    {
        foreach(KeyValuePair<string,string> item in legacy){
            string path=UPath(item.Key);
            if(!File.Exists(path) && IsOptionalStableLegacyRoot(item.Key,channel))
                continue;
            if(!File.Exists(path) || !String.Equals(UpgradeHash(path),item.Value,StringComparison.Ordinal))
                throw new InvalidOperationException("Protected/edited/missing old program component "+item.Key+"; NO files changed. Preserve user changes and request review.");
        }
    }

    static void EnsureAppNotRunning()
    {
        foreach(Process p in Process.GetProcessesByName("TaskbarMonitorEnhanced")){
            try{
                if(!p.HasExited)
                    throw new InvalidOperationException("Close Taskbar Monitor Enhanced normally before upgrade; updater will not force-kill unsaved data.");
            }finally{p.Dispose();}
        }
    }

    static string UpgradeRoot {get{return Path.Combine(AppRoot,UpgradeStageName);}}
    static string RetiredUpgradeRoot {get{return Path.Combine(AppRoot,UpgradeStageName+"-retired");}}
    static string Stage(string part,string rel)
    {
        if(part!="new" && part!="old")throw new InvalidDataException("Unexpected stage area.");
        if(String.IsNullOrWhiteSpace(rel) || Path.IsPathRooted(rel) || rel.Contains("..") ||
           rel.Contains(":") || rel.StartsWith("/") || rel.StartsWith("\\"))
            throw new InvalidDataException("Upgrade refused unsafe staged resource path.");
        string path=Path.GetFullPath(Path.Combine(UpgradeRoot,part,rel.Replace('/',Path.DirectorySeparatorChar)));
        string root=Path.GetFullPath(UpgradeRoot).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
        if(!path.StartsWith(root,StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Upgrade refused stage escape.");
        CheckNoReparse(path);
        return path;
    }

    static void WritePhase(string phase)
    {
        string path=Path.Combine(UpgradeRoot,"phase.txt");
        string tmp=Path.Combine(UpgradeRoot,"phase.tmp");
        File.WriteAllText(tmp,UpgradeStageMarker+"|"+phase,Encoding.ASCII);
        if(File.Exists(path))File.Replace(tmp,path,null);
        else File.Move(tmp,path);
    }

    static string GetPhase()
    {
        string marker=Path.Combine(UpgradeRoot,"owner.txt");
        string phase=Path.Combine(UpgradeRoot,"phase.txt");
        if(!File.Exists(marker)||File.ReadAllText(marker)!=UpgradeStageMarker || !File.Exists(phase))
            throw new InvalidOperationException("Unrecognized incomplete upgrade stage; DO NOT delete. Manual recovery required.");
        string raw=File.ReadAllText(phase,Encoding.ASCII);
        if(!raw.StartsWith(UpgradeStageMarker+"|",StringComparison.Ordinal))
            throw new InvalidDataException("Upgrade phase identity mismatch.");
        return raw.Substring(UpgradeStageMarker.Length+1);
    }

    static void StageNewManaged(Dictionary<string,byte[]> fresh, Dictionary<string,string> legacy, string stateSource,string previousVersion,string channel)
    {
        // Regression guard: validate ALL target paths before the first stage
        // directory/write. Previously a late unknown file could leave an owner-
        // marked but unindexed stage, and rollback then masked the real cause.
        foreach(UpgradeTarget target in UpgradeTargets)
        {
            string live=UPath(target.Rel);
            if(File.Exists(live))
            {
                if(target.Rel!="install_state.json" &&
                   (!legacy.ContainsKey(target.Rel) ||
                    UpgradeHash(live)!=legacy[target.Rel]))
                    throw new InvalidDataException("Pre-stage managed component changed; NO STAGE created: "+target.Rel);
            }
            else if(legacy.ContainsKey(target.Rel) &&
                    !IsOptionalStableLegacyRoot(target.Rel,channel))
                throw new InvalidDataException("Pre-stage required official component missing; NO STAGE created: "+target.Rel);
        }
        Directory.CreateDirectory(UpgradeRoot);
        File.WriteAllText(Path.Combine(UpgradeRoot,"owner.txt"),UpgradeStageMarker,Encoding.ASCII);
        List<string> lines=new List<string>();
        foreach(UpgradeTarget target in UpgradeTargets){
            string current=UPath(target.Rel);
            string prior=Stage("old",target.Rel);
            string previous="-";
            if(File.Exists(current)){
                // All prior managed components except install_state must be byte-identical
                // to the official signed-off v1.6 resource before replacement/deletion.
                if(target.Rel!="install_state.json"){
                    if(!legacy.ContainsKey(target.Rel) || UpgradeHash(current)!=legacy[target.Rel])
                        throw new InvalidDataException("Unknown previous managed file; stop "+target.Rel);
                }
                previous=UpgradeHash(current);
                Directory.CreateDirectory(Path.GetDirectoryName(prior));
                File.Copy(current,prior,false);
                if(UpgradeHash(prior)!=previous)throw new IOException("Backup SHA mismatch "+target.Rel);
            }else if(legacy.ContainsKey(target.Rel) &&
                     !IsOptionalStableLegacyRoot(target.Rel,channel))
                throw new InvalidDataException("Expected old file is missing "+target.Rel);
            string newSha= fresh.ContainsKey(target.Rel)?UpgradeHash(fresh[target.Rel]):"-";
            lines.Add(target.Rel+"|"+previous+"|"+newSha);
            if(fresh.ContainsKey(target.Rel)){
                string dest=Stage("new",target.Rel);
                Directory.CreateDirectory(Path.GetDirectoryName(dest));
                File.WriteAllBytes(dest,fresh[target.Rel]);
                if(UpgradeHash(dest)!=newSha)throw new IOException("Staged payload SHA mismatch "+target.Rel);
            }
        }
        File.WriteAllText(Path.Combine(UpgradeRoot,"index.txt"),String.Join("\n",lines.ToArray()),Encoding.ASCII);
        if(previousVersion!=InstalledV16 && previousVersion!=InstalledV170 && previousVersion!=InstalledV171 && previousVersion!=InstalledV172 && previousVersion!=InstalledV173 && previousVersion!=InstalledV174 && previousVersion!=InstalledV175 && previousVersion!=InstalledV176 && previousVersion!=InstalledV177 && previousVersion!=Version)throw new InvalidDataException("Invalid previous version for journal.");
        File.WriteAllText(Path.Combine(UpgradeRoot,"previous_version.txt"),previousVersion,Encoding.ASCII);
        WritePhase("PREPARED");
    }

    sealed class StageEntry{
        internal string Rel,Previous,Next;
        internal StageEntry(string rel,string oldSha,string nextSha){Rel=rel;Previous=oldSha;Next=nextSha;}
    }

    static List<StageEntry> ReadStageIndex()
    {
        string index=Path.Combine(UpgradeRoot,"index.txt");
        if(!File.Exists(index))throw new InvalidOperationException("Upgrade journal index absent; no blind cleanup.");
        string[] lines=File.ReadAllText(index,Encoding.ASCII).Split(new char[]{'\n'},StringSplitOptions.None);
        if(lines.Length!=UpgradeTargets.Length)throw new InvalidDataException("Upgrade journal expected rows missing.");
        List<StageEntry> parsed=new List<StageEntry>();
        for(int i=0;i<lines.Length;i++){
            string[] parts=lines[i].Split('|');
            if(parts.Length!=3 || parts[0]!=UpgradeTargets[i].Rel ||
              (parts[1]!="-" && !Regex.IsMatch(parts[1],"^[0-9A-F]{64}$")) ||
              (parts[2]!="-" && !Regex.IsMatch(parts[2],"^[0-9A-F]{64}$")))
                throw new InvalidDataException("Upgrade journal path or digest modified.");
            // Convert the validated on-disk label back to the compiled-in target before filesystem use.
            parsed.Add(new StageEntry(UpgradeTargets[i].Rel,parts[1],parts[2]));
        }
        return parsed;
    }

    // R299: do not recursively delete a user-writable upgrade journal. A
    // junction inserted after the preflight must not turn cleanup into a
    // recursive deletion of unrelated user files.
    static void CleanOwnedStage(List<StageEntry> rows)
    {
        string root=Path.GetFullPath(UpgradeRoot).TrimEnd(Path.DirectorySeparatorChar);
        string prefix=root+Path.DirectorySeparatorChar;
        CheckNoReparse(root);
        string retired=Path.GetFullPath(RetiredUpgradeRoot);
        CheckNoReparse(retired);
        if(Directory.Exists(retired) || File.Exists(retired))
            throw new IOException("Prior retired upgrade journal must be recovered first.");
        HashSet<string> knownFiles=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(string filename in new string[]{"owner.txt","phase.txt","index.txt","phase.tmp","previous_version.txt"})
            knownFiles.Add(Path.GetFullPath(Path.Combine(root,filename)));
        foreach(StageEntry r in rows){
            knownFiles.Add(Path.GetFullPath(Stage("old",r.Rel)));
            knownFiles.Add(Path.GetFullPath(Stage("new",r.Rel)));
        }
        HashSet<string> knownDirs=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        knownDirs.Add(root);
        foreach(string filename in knownFiles){
            if(!filename.StartsWith(prefix,StringComparison.OrdinalIgnoreCase))
                throw new IOException("Upgrade cleanup path escaped canonical stage.");
            string directory=Path.GetDirectoryName(filename);
            while(!String.Equals(directory,root,StringComparison.OrdinalIgnoreCase)){
                if(String.IsNullOrEmpty(directory) || !directory.StartsWith(prefix,StringComparison.OrdinalIgnoreCase))
                    throw new IOException("Upgrade cleanup directory escaped canonical stage.");
                knownDirs.Add(directory);
                directory=Path.GetDirectoryName(directory);
            }
        }
        // Enumerate one directory at a time: reject unexpected empty dirs as
        // well as files and reparse entries BEFORE deleting any known member.
        List<string> pending=new List<string>();pending.Add(root);
        while(pending.Count>0){
            string directory=pending[pending.Count-1];pending.RemoveAt(pending.Count-1);
            CheckNoReparse(directory);
            foreach(string entry in Directory.GetFileSystemEntries(directory)){
                string full=Path.GetFullPath(entry);
                if(!full.StartsWith(prefix,StringComparison.OrdinalIgnoreCase))
                    throw new IOException("Upgrade cleanup observed path escape.");
                FileAttributes attributes=File.GetAttributes(full);
                if((attributes&FileAttributes.ReparsePoint)!=0)
                    throw new IOException("Upgrade cleanup refuses reparse member: "+full);
                if((attributes&FileAttributes.Directory)!=0){
                    if(!knownDirs.Contains(full))
                        throw new IOException("Unknown directory inside update stage; leave stage intact: "+full);
                    pending.Add(full);
                }else if(!knownFiles.Contains(full)){
                    throw new IOException("Unknown file inside update stage; leave stage intact: "+full);
                }
            }
        }
        // Unlink only exact known files; remove directories with recursive=false.
        // Keep owner/index/phase markers until descendants have been removed.
        string[] metadata=new string[]{"phase.tmp","previous_version.txt","index.txt","phase.txt","owner.txt"};
        HashSet<string> metadataPaths=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach(string name in metadata)metadataPaths.Add(Path.Combine(root,name));
        foreach(string filename in knownFiles){
            if(metadataPaths.Contains(filename))continue;
            CheckNoReparse(filename);
            if(File.Exists(filename))File.Delete(filename);
        }
        List<string> directories=knownDirs.Where(d=>!String.Equals(d,root,StringComparison.OrdinalIgnoreCase)).ToList();
        directories.Sort(delegate(string a,string b){
            int c=b.Length.CompareTo(a.Length);
            return c!=0?c:StringComparer.OrdinalIgnoreCase.Compare(a,b);
        });
        foreach(string directory in directories){
            CheckNoReparse(directory);
            if(Directory.Exists(directory))Directory.Delete(directory,false);
        }
        // Keep index, phase, prior-version and ownership metadata in the
        // active journal until a same-parent move retires that whole journal.
        // Interruption before the move resumes original recovery; after it
        // only a fixed, bounded metadata tombstone remains.
        CheckNoReparse(root);
        CheckNoReparse(retired);
        Directory.Move(root,retired);
        FinishRetiredUpgradeStageIfAny();
    }

    // R300: retryable, nonrecursive cleanup of exact retired metadata only.
    static void FinishRetiredUpgradeStageIfAny()
    {
        string root=Path.GetFullPath(RetiredUpgradeRoot);
        CheckNoReparse(root);
        if(File.Exists(root))
            throw new IOException("Retired upgrade path is not a directory.");
        if(!Directory.Exists(root))return;
        string owner=Path.Combine(root,"owner.txt");
        string[] metadata=new string[]{"phase.tmp","previous_version.txt","index.txt","phase.txt","owner.txt"};
        HashSet<string> names=new HashSet<string>(metadata,StringComparer.OrdinalIgnoreCase);
        string[] entries=Directory.GetFileSystemEntries(root);
        foreach(string entry in entries){
            string full=Path.GetFullPath(entry);
            if(!String.Equals(Path.GetDirectoryName(full),root,StringComparison.OrdinalIgnoreCase) ||
               !names.Contains(Path.GetFileName(full)))
                throw new IOException("Unknown retired upgrade member; preserve for review: "+full);
            CheckNoReparse(full);
            FileAttributes attributes=File.GetAttributes(full);
            if((attributes&(FileAttributes.Directory|FileAttributes.ReparsePoint))!=0)
                throw new IOException("Retired upgrade member is not an ordinary file: "+full);
        }
        // Owner is last; if it is absent, only an empty directory is safe.
        if(File.Exists(owner)){
            if(File.ReadAllText(owner,Encoding.ASCII)!=UpgradeStageMarker)
                throw new IOException("Retired upgrade ownership marker mismatch.");
        }else if(entries.Length!=0)
            throw new IOException("Retired upgrade journal lost its ownership marker.");
        foreach(string name in metadata){
            string file=Path.Combine(root,name);
            CheckNoReparse(file);
            if(File.Exists(file))File.Delete(file);
        }
        CheckNoReparse(root);
        Directory.Delete(root,false);
    }

    static void RestoreInterruptedUpgrade(List<StageEntry> rows)
    {
        string priorVersionPath=Path.Combine(UpgradeRoot,"previous_version.txt");
        if(!File.Exists(priorVersionPath))throw new IOException("Previous upgrade version missing; retain stage.");
        string priorVersion=File.ReadAllText(priorVersionPath,Encoding.ASCII);
        if(priorVersion!=InstalledV16 && priorVersion!=InstalledV170 && priorVersion!=InstalledV171 && priorVersion!=InstalledV172 && priorVersion!=InstalledV173 && priorVersion!=InstalledV174 && priorVersion!=InstalledV175 && priorVersion!=InstalledV176 && priorVersion!=InstalledV177 && priorVersion!=Version)throw new IOException("Unknown previous version; retain stage.");
        // R284: an interrupted File.Copy(old, old/rel.restore, false) can
        // leave only a partial updater-owned scratch. A retry must recreate
        // only these exact scratch paths AFTER owner/index verification.
        // Unknown files and reparse paths remain rejected.
        foreach(StageEntry row in rows){
            if(row.Previous=="-")continue;
            string scratch=Stage("old",row.Rel+".restore");
            if(File.Exists(scratch)){
                CheckNoReparse(scratch);
                File.Delete(scratch);
            }
        }
        // This works after a mid-commit process kill: exact old snapshots are persisted
        // on the same volume, and new-only files are removed only if their SHA is known.
        for(int i=rows.Count-1;i>=0;i--){
            StageEntry r=rows[i];
            string live=UPath(r.Rel);
            if(r.Previous!="-"){
                string old=Stage("old",r.Rel);
                if(!File.Exists(old)||UpgradeHash(old)!=r.Previous)
                    throw new IOException("Previous version backup missing/corrupt; manual recovery required: "+r.Rel);
                if(File.Exists(live)){
                    string currentSha=UpgradeHash(live);
                    if(currentSha!=r.Previous && currentSha!=r.Next)
                        throw new IOException("Unexpected concurrent edit; refuse rollback over user change "+r.Rel);
                    if(currentSha==r.Previous)continue;
                    string rehydrate=Stage("old",r.Rel+".restore");
                    File.Copy(old,rehydrate,false);
                    File.Replace(rehydrate,live,null);
                }else{
                    Directory.CreateDirectory(Path.GetDirectoryName(live));
                    File.Copy(old,live,false);
                }
                if(UpgradeHash(live)!=r.Previous)throw new IOException("Rollback hash failed "+r.Rel);
            }else if(File.Exists(live)){
                if(r.Next=="-" || UpgradeHash(live)!=r.Next)
                    throw new IOException("Unexpected newly created file during rollback "+r.Rel);
                File.Delete(live);
            }
        }
        using(RegistryKey key=Registry.CurrentUser.OpenSubKey(UninstallKey,true)){
            if(key==null)throw new IOException("Upgrade rollback cannot restore uninstall registration.");
            key.SetValue("DisplayVersion",priorVersion);
        }
        foreach(StageEntry r in rows){
            if(r.Previous=="-" && File.Exists(UPath(r.Rel)))throw new IOException("Rollback unexpected file "+r.Rel);
            if(r.Previous!="-" && (!File.Exists(UPath(r.Rel)) || UpgradeHash(UPath(r.Rel))!=r.Previous))
                throw new IOException("Rollback previous version SHA mismatch "+r.Rel);
        }
    }

    // R301: COMMITTING rollback needs a separate durable success marker.
    // Otherwise a crash during backup cleanup makes the next COMMITTING
    // replay require already-deleted old snapshots. ROLLED_BACK is written
    // only after the old live file hashes and HKCU version have been restored.
    static void VerifyRolledBackUpgrade(List<StageEntry> rows)
    {
        string versionPath=Path.Combine(UpgradeRoot,"previous_version.txt");
        CheckNoReparse(versionPath);
        if(!File.Exists(versionPath))
            throw new IOException("Rolled-back upgrade version missing; retain stage.");
        string oldVersion=File.ReadAllText(versionPath,Encoding.ASCII);
        if(oldVersion!=InstalledV16 && oldVersion!=InstalledV170 &&
           oldVersion!=InstalledV171 && oldVersion!=InstalledV172 &&
           oldVersion!=InstalledV173 && oldVersion!=InstalledV174 &&
           oldVersion!=InstalledV175 && oldVersion!=InstalledV176 &&
           oldVersion!=InstalledV177 && oldVersion!=Version)
            throw new IOException("Rolled-back upgrade version is not pinned.");
        using(RegistryKey key=Registry.CurrentUser.OpenSubKey(UninstallKey,false)){
            if(key==null || !String.Equals(Convert.ToString(key.GetValue("DisplayVersion")),
                                            oldVersion,StringComparison.Ordinal))
                throw new IOException("Rolled-back uninstall registration mismatch.");
        }
        foreach(StageEntry row in rows){
            string live=UPath(row.Rel);
            if(row.Previous=="-"){
                if(File.Exists(live))
                    throw new IOException("Rolled-back new component unexpectedly remains: "+row.Rel);
            }else if(!File.Exists(live) || UpgradeHash(live)!=row.Previous){
                throw new IOException("Rolled-back previous SHA mismatch: "+row.Rel);
            }
        }
    }

    static void RecoverUpgradeStageIfAny()
    {
        FinishRetiredUpgradeStageIfAny();
        if(!Directory.Exists(UpgradeRoot))return;
        CheckNoReparse(UpgradeRoot);
        // Interrupted journals are writable in the user's AppData. Before
        // reading them or mutating ANY managed file, reject their descendant
        // links, including link-shaped phase/index files and stage subtrees.
        foreach(string name in new string[]{"owner.txt","phase.txt","phase.tmp",
                  "index.txt","previous_version.txt","old","new"})
            CheckNoReparse(Path.Combine(UpgradeRoot,name));
        string phase=GetPhase();
        List<StageEntry> rows=ReadStageIndex();
        foreach(StageEntry r in rows){
            UPath(r.Rel);
            Stage("old",r.Rel);
            Stage("new",r.Rel);
            if(r.Previous!="-")Stage("old",r.Rel+".restore");
        }
        if(phase=="PREPARED"){
            // No managed target is modified before COMMITTING is durably written.
            CleanOwnedStage(rows);return;
        }
        if(phase=="COMMITTING"){
            RestoreInterruptedUpgrade(rows);
            WritePhase("ROLLED_BACK");
            CleanOwnedStage(rows);return;
        }
        if(phase=="ROLLED_BACK"){
            // A previous rollback already succeeded; its old snapshots may
            // have been removed before process death. Verify the exact live
            // old version rather than attempting to consume them again.
            VerifyRolledBackUpgrade(rows);
            CleanOwnedStage(rows);return;
        }
        if(phase=="COMMITTED"){
            foreach(StageEntry r in rows){
                string live=UPath(r.Rel);
                if(r.Next=="-" && File.Exists(live))throw new IOException("Committed removal not applied "+r.Rel);
                if(r.Next!="-" && (!File.Exists(live)||UpgradeHash(live)!=r.Next))
                    throw new IOException("Committed upgraded file no longer matches "+r.Rel);
            }
            CleanOwnedStage(rows);return;
        }
        throw new InvalidDataException("Unexpected upgrade phase; stage preserved.");
    }

    static SensorOutcome ExistingSensorOutcome()
    {
        SensorOutcome outcome=new SensorOutcome();
        string state=File.ReadAllText(UPath("install_state.json"),Encoding.UTF8);
        Match status=Regex.Match(state,"\\\"SensorLayerStatus\\\"\\s*:\\s*\\\"([^\\\"]*)\\\"");
        Match mode=Regex.Match(state,"\\\"SensorLayerMode\\\"\\s*:\\s*\\\"([^\\\"]*)\\\"");
        outcome.Status=status.Success?status.Groups[1].Value:"UNKNOWN";
        outcome.LayerMode=mode.Success?mode.Groups[1].Value:"UNKNOWN";
        outcome.IsHealthy=String.Equals(outcome.Status,"READY",StringComparison.OrdinalIgnoreCase);
        outcome.Message="Existing settings, data and sensor services have been preserved by the in-place upgrade.";
        return outcome;
    }

    static SensorOutcome UpgradeExisting()
    {
        if(!Directory.Exists(AppRoot))throw new InvalidOperationException("Canonical user app root missing; /update cannot create a second installation.");
        CheckNoReparse(AppRoot);
        // Recovery must run before AppExe identity checks: an interrupted file swap
        // can temporarily leave the main EXE absent while the exact backup is intact.
        RecoverUpgradeStageIfAny();
        CheckSingleCanonicalRoot();
        string installed=CurrentInstalledVersion();
        string newSha=Sha256Resource("Payload.TaskbarMonitorEnhanced.exe");
        if(installed!=InstalledV16 && installed!=InstalledV170 && installed!=InstalledV171 && installed!=InstalledV172 && installed!=InstalledV173 && installed!=InstalledV174 && installed!=InstalledV175 && installed!=InstalledV176 && installed!=InstalledV177 && installed!=Version)
            throw new InvalidOperationException("Only SHA-pinned official v1.6/v1.7.0/v1.7.1/v1.7.2/v1.7.3/v1.7.4/v1.7.5/v1.7.6/v1.7.7 may upgrade in place.");
        string channel="OFFICIAL_V16";
        string currentMainSHA=UpgradeHash(AppExe);
        string installedSetup=UPath("Uninstall.exe");
        if(!File.Exists(installedSetup))throw new InvalidDataException("Maintenance executable missing.");
        string oldSetupSHA=UpgradeHash(installedSetup);
        string newSetupSHA=UpgradeHash(System.Windows.Forms.Application.ExecutablePath);
        if(installed==Version)
        {
            // Idempotence is TWO exact binaries, never just the same semver or Main SHA.
            if(currentMainSHA==newSha && oldSetupSHA==newSetupSHA &&
               !File.Exists(UPath("TaskbarMonitorEnhanced.cs")) &&
               !File.Exists(UPath("Docs/RELEASE_NOTES_v1.6.0.md")) &&
                !File.Exists(UPath("Docs/RELEASE_NOTES_v1.7.0.md")) &&
                !File.Exists(UPath("Docs/RELEASE_NOTES_v1.7.1.md")) &&
                 !File.Exists(UPath("Docs/RELEASE_NOTES_v1.7.2.md")) &&
                 !File.Exists(UPath("Docs/RELEASE_NOTES_v1.7.3.md")) &&
                  !File.Exists(UPath("Docs/RELEASE_NOTES_v1.7.4.md")) &&
                  !File.Exists(UPath("Docs/RELEASE_NOTES_v1.7.5.md")) &&
                  !File.Exists(UPath("Docs/RELEASE_NOTES_v1.7.6.md")) &&
                  !File.Exists(UPath("Docs/RELEASE_NOTES_v1.7.7.md")))
                return ExistingSensorOutcome();
            throw new InvalidOperationException("Unknown current-version maintenance revision; no files changed.");
        }
        if(installed==InstalledV170)
        {
            if(currentMainSHA==OfficialV170MainSHA && oldSetupSHA==OfficialV170SetupSHA)
                channel="OFFICIAL_STABLE_V170";
            else if(currentMainSHA==LegacyPreview1Rows[0].Split('|')[1] &&
                    oldSetupSHA==LegacyPreview1InstallerSha)
                channel="PREVIEW1";
            else throw new InvalidOperationException("Unknown v1.7.0 source/Setup identity; refuse before any mutation.");
        }

        if(installed==InstalledV171)
        {
            if(currentMainSHA!=OfficialV171MainSHA || oldSetupSHA!=OfficialV171SetupSHA)
                throw new InvalidOperationException("Unknown v1.7.1 source/Setup identity; refuse before any mutation.");
            channel="OFFICIAL_STABLE_V171";
        }
        if(installed==InstalledV172)
        {
            if(currentMainSHA!=OfficialV172MainSHA || oldSetupSHA!=OfficialV172SetupSHA)
                throw new InvalidOperationException("Unknown official v1.7.2 source/Setup identity; refuse before any mutation.");
            channel="OFFICIAL_STABLE_V172";
        }
        if(installed==InstalledV173)
        {
            if(currentMainSHA!=OfficialV173MainSHA || oldSetupSHA!=OfficialV173SetupSHA)
                throw new InvalidOperationException("Unknown official v1.7.3 source/Setup identity; refuse before any mutation.");
            channel="OFFICIAL_STABLE_V173";
        }
        if(installed==InstalledV174)
        {
            if(currentMainSHA!=OfficialV174MainSHA || oldSetupSHA!=OfficialV174SetupSHA)
                throw new InvalidOperationException("Unknown official v1.7.4 source/Setup identity; refuse before any mutation.");
            channel="OFFICIAL_STABLE_V174";
        }

        if(installed==InstalledV177)
        {
            if(currentMainSHA!=OfficialV177MainSHA || oldSetupSHA!=OfficialV177SetupSHA)
                throw new InvalidOperationException("Unknown official v1.7.7 Main/Setup identity; NO mutation.");
            channel="OFFICIAL_STABLE_V177";
        }

        if(installed==InstalledV176)
        {
            if(currentMainSHA!=OfficialV176MainSHA || oldSetupSHA!=OfficialV176SetupSHA)
                throw new InvalidOperationException("Unknown official v1.7.6 Main/Setup identity; NO mutation.");
            channel="OFFICIAL_STABLE_V176";
        }

        if(installed==InstalledV175)
        {
            if(currentMainSHA!=OfficialV175MainSHA || oldSetupSHA!=OfficialV175SetupSHA)
                throw new InvalidOperationException("Unknown official v1.7.5 Main/Setup identity; NO mutation.");
            channel="OFFICIAL_STABLE_V175";
        }

        // No force-kill; the owner must close their currently running app normally.
        EnsureAppNotRunning();
        Dictionary<string,string> official=LegacyExpected(installed,channel);
        VerifyLegacyFiles(official,channel);
        string stateSource=File.ReadAllText(UPath("install_state.json"),Encoding.UTF8);
        string configPath=UPath("config.json");
        string configBackupPath=UPath("config.json.bak");
        string configSha=File.Exists(configPath)?UpgradeHash(configPath):"-";
        string configBackupSha=File.Exists(configBackupPath)?UpgradeHash(configBackupPath):"-";
        string backendPath=UPath("SensorBackend/LibreHardwareMonitor-0.9.6/LibreHardwareMonitorLib.dll");
        if(!File.Exists(backendPath))throw new InvalidOperationException("Sensor backend library is missing; refusing to destroy existing sensor state.");
        string backendSha=UpgradeHash(backendPath);
        string startupPath=@"Software\Microsoft\Windows\CurrentVersion\Run";
        string oldStartup;
        using(RegistryKey k=Registry.CurrentUser.OpenSubKey(startupPath,false))
            oldStartup=k==null?null:Convert.ToString(k.GetValue("TaskbarMonitorEnhanced"));
        string oldDisplay;
        using(RegistryKey k=Registry.CurrentUser.OpenSubKey(UninstallKey,false)){
            oldDisplay=Convert.ToString(k.GetValue("DisplayVersion"));
            if(!String.Equals(oldDisplay,installed,StringComparison.Ordinal))
                throw new InvalidOperationException("Installed registry Version does not match the SHA-verified existing product version.");
        }
        Dictionary<string,byte[]> fresh=PrepareNewBytes(stateSource);
        if(Directory.Exists(UpgradeRoot))throw new IOException("Upgrade journal is not clear; no changes made.");
        List<StageEntry> entries=null;
        try{
            StageNewManaged(fresh,official,stateSource,installed,channel);
            entries=ReadStageIndex();
            WritePhase("COMMITTING"); // persisted before first managed mutation
            int step=0;
            foreach(StageEntry r in entries){
                string live=UPath(r.Rel);
                if(r.Next=="-"){
                    if(File.Exists(live))File.Delete(live);
                }else{
                    string newer=Stage("new",r.Rel);
                    if(!File.Exists(newer)||UpgradeHash(newer)!=r.Next)
                        throw new IOException("Staged replacement became untrusted "+r.Rel);
                    Directory.CreateDirectory(Path.GetDirectoryName(live));
                    if(File.Exists(live))File.Replace(newer,live,null);
                    else File.Move(newer,live);
                    if(UpgradeHash(live)!=r.Next)
                        throw new IOException("Managed component failed post-commit hash "+r.Rel);
                }
                step++;
            }
            using(RegistryKey key=Registry.CurrentUser.OpenSubKey(UninstallKey,true)){
                if(key==null)throw new IOException("Uninstall registration absent after file swap.");
                key.SetValue("DisplayVersion",Version);
            }
            if((File.Exists(configPath)?UpgradeHash(configPath):"-")!=configSha ||
               (File.Exists(configBackupPath)?UpgradeHash(configBackupPath):"-")!=configBackupSha ||
               UpgradeHash(backendPath)!=backendSha)
                throw new IOException("Protected user config or unchanged sensor library SHA altered during upgrade.");
            string newStartup;
            using(RegistryKey k=Registry.CurrentUser.OpenSubKey(startupPath,false))
                newStartup=k==null?null:Convert.ToString(k.GetValue("TaskbarMonitorEnhanced"));
            if(!String.Equals(newStartup,oldStartup,StringComparison.Ordinal))
                throw new IOException("Startup preference changed during in-place update.");
            if(CurrentInstalledVersion()!=Version || UpgradeHash(AppExe)!=newSha ||
               Directory.Exists(Path.Combine(AppRoot,UpgradeStageName,"second-install")))
                throw new IOException("In-place upgrade did not produce the exact target app and version.");
            WritePhase("COMMITTED");
            CleanOwnedStage(entries);
            return ExistingSensorOutcome();
        }catch(Exception firstFailure){
            if(Directory.Exists(UpgradeRoot)){
                try{RecoverUpgradeStageIfAny();}
                catch(Exception rollback){
                    // Preserve first observed cause and rollback exception together;
                    // never delete an unrecognized or incomplete transaction journal.
                    throw new IOException("Upgrade failed; rollback UNRESOLVED. Preserve stage and do not uninstall. FIRST="+
                        firstFailure.GetType().FullName+": "+firstFailure.Message+
                        "; ROLLBACK="+rollback.GetType().FullName+": "+rollback.Message,
                        new AggregateException(firstFailure,rollback));
                }
            }
            throw;
        }
    }
}
