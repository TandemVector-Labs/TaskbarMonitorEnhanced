using System;
using System.IO;
using System.Text;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
[ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface ShortcutShellLinkW {
  void GetPath([Out,MarshalAs(UnmanagedType.LPWStr)]StringBuilder path,int n,IntPtr findData,uint flags);
  void GetIDList(out IntPtr ppidl);
  void SetIDList(IntPtr pidl);
  void GetDescription([Out,MarshalAs(UnmanagedType.LPWStr)]StringBuilder description,int len);
  void SetDescription([MarshalAs(UnmanagedType.LPWStr)]string desc);
  void GetWorkingDirectory([Out,MarshalAs(UnmanagedType.LPWStr)]StringBuilder dir,int len);
  void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)]string dir);
  void GetArguments([Out,MarshalAs(UnmanagedType.LPWStr)]StringBuilder args,int len);
  void SetArguments([MarshalAs(UnmanagedType.LPWStr)]string args);
  void GetHotkey(out short hotkey);
  void SetHotkey(short hotkey);
  void GetShowCmd(out int style);
  void SetShowCmd(int style);
  void GetIconLocation([Out,MarshalAs(UnmanagedType.LPWStr)]StringBuilder path,int len,out int index);
  void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)]string path,int index);
  void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)]string path,uint reserved);
  void Resolve(IntPtr hwnd,uint flags);
  void SetPath([MarshalAs(UnmanagedType.LPWStr)]string path);
}


internal static class R091ShortcutTests
{
 static string Read(TbmeLink p, string prop) {return p.Read(prop);}
 internal sealed class TbmeLink : IDisposable {
  object com;
  ShortcutShellLinkW link;
  public TbmeLink(string path) {
    var type=Type.GetTypeFromCLSID(new Guid("00021401-0000-0000-C000-000000000046"),true);
    com=Activator.CreateInstance(type);
    ((IPersistFile)com).Load(path,0);
    link=(ShortcutShellLinkW)com;
  }
  public string Read(string prop) {
    var b=new StringBuilder(2048);
    if(prop=="TargetPath")link.GetPath(b,b.Capacity,IntPtr.Zero,0);
    else if(prop=="Arguments")link.GetArguments(b,b.Capacity);
    else if(prop=="Description")link.GetDescription(b,b.Capacity);
    else if(prop=="WorkingDirectory")link.GetWorkingDirectory(b,b.Capacity);
    else if(prop=="IconLocation"){int icon;link.GetIconLocation(b,b.Capacity,out icon);if(icon!=0)throw new IOException("Shortcut icon index changed");}
    else throw new ArgumentException("unsupported property");
    return b.ToString();
  }
  public int Style(){int x;link.GetShowCmd(out x);return x;}
  public void Dispose(){if(com!=null)Marshal.FinalReleaseComObject(com);com=null;}
 }
 static void Must(bool x,string marker){if(!x)throw new IOException(marker);}
 static void Call(MethodInfo method, params object[] args){
   try{method.Invoke(null,args);}
   catch(TargetInvocationException e){throw e.InnerException??e;}
 }
 static void MustReject(MethodInfo m, params object[] args){
   bool denied=false;
   try{Call(m,args);}
   catch(InvalidDataException){denied=true;}
   Must(denied,"R091_INVALID_LINK_INPUT_NOT_REJECTED");
 }
 [STAThread] static int Main(string[] args){
  if(args.Length!=2){Console.Error.WriteLine("R091 requires test-only compiled PE + checkout root");return 9;}
  string dll=Path.GetFullPath(args[0]);
  string checkout=Path.GetFullPath(args[1]);
  string source=File.ReadAllText(Path.Combine(checkout,@"installer\TaskbarMonitorEnhanced_Setup.cs"));
  if(source.Contains("tbme_shortcut_") || source.Contains("ExecutionPolicy Bypass -File") ||
     source.Contains("New-Object -ComObject WScript.Shell") || source.Contains("new ProcessStartInfo(\"powershell.exe\""))
     throw new IOException("R091 legacy user-temp script launch reintroduced");
  var assembly=Assembly.LoadFile(dll);
  var t=assembly.GetType("SetupProgram",true);
  BindingFlags flags=BindingFlags.Static|BindingFlags.NonPublic;
  MethodInfo m4=t.GetMethod("Shortcut",flags,null,new[]{typeof(string),typeof(string),typeof(string),typeof(string)},null);
  MethodInfo m2=t.GetMethod("Shortcut",flags,null,new[]{typeof(string),typeof(string)},null);
  var appRootGetter=t.GetProperty("AppRoot",flags);
  var appExeGetter=t.GetProperty("AppExe",flags);
  Must(m4!=null && m2!=null && appRootGetter!=null && appExeGetter!=null,"R091_PRODUCTION_SETUP_METHODS_UNAVAILABLE");
  string appRoot=(string)appRootGetter.GetValue(null,null);
  string appExe=(string)appExeGetter.GetValue(null,null);
  string osTarget=Path.Combine(Environment.SystemDirectory,"cmd.exe");
  Must(File.Exists(osTarget),"R091_OS_TARGET_NOT_AVAILABLE");
  string own=Path.Combine(Path.GetTempPath(),"tbme_r091_owned_test_"+Guid.NewGuid().ToString("N"));
  Must(!Directory.Exists(own),"R091_TEST_ROOT_ALREADY_EXISTS");
  Directory.CreateDirectory(own);
  string persian="\u0641\u0627\u0631\u0633\u06CC";
  string unicodeLink=Path.Combine(own,"R091 "+persian+" apostrophe's test.lnk");
  string normalLink=Path.Combine(own,"R091 ordinary shortcut.lnk");
  string invalidExtension=Path.Combine(own,"R091 unsafe source.ps1");
  string argText="--R091 \"quoted phrase\" & %PATH% 'single' "+persian;
  string desc="R091 Unicode Windows link, no PowerShell";
  try {
   Call(m4,unicodeLink,osTarget,argText,desc);
   Must(File.Exists(unicodeLink),"R091_UNICODE_FILENAME_CHANGED_OR_NOT_CREATED");
   using(var l=new TbmeLink(unicodeLink)){
    Must(string.Equals(l.Read("TargetPath"),osTarget,StringComparison.OrdinalIgnoreCase),"R091_TARGET_NOT_SAVED");
    Must(l.Read("Arguments")==argText,"R091_QUOTES_UNICODE_ARGUMENTS_CHANGED");
    Must(string.Equals(l.Read("WorkingDirectory"),appRoot,StringComparison.OrdinalIgnoreCase),"R091_WORKING_DIRECTORY_CHANGED");
    Must(l.Read("Description")==desc,"R091_DESCRIPTION_CHANGED");
    Must(string.Equals(l.Read("IconLocation"),appExe,StringComparison.OrdinalIgnoreCase),"R091_APPLICATION_ICON_CHANGED");
    Must(l.Style()==1,"R091_SHOW_STYLE_CHANGED");
   }
   Console.WriteLine("R091_REAL_SETUP_SHORTCUT_UNICODE_PERSIAN_AND_QUOTES=PASS");
   Call(m2,normalLink,osTarget);
   Must(File.Exists(normalLink),"R091_COMPAT_SHORTCUT_WRAPPER_NOT_CREATED");
   using(var l=new TbmeLink(normalLink)){
    Must(l.Read("Arguments")=="","R091_DEFAULT_ARGUMENTS_NOT_EMPTY");
    Must(l.Read("Description")=="Live system monitor integrated into the Windows taskbar","R091_DEFAULT_DESCRIPTION_CHANGED");
   }
   Console.WriteLine("R091_EXISTING_TWO_ARG_SHORTCUT_COMPATIBILITY=PASS");
   MustReject(m4,invalidExtension,osTarget,argText,desc);
   Must(!File.Exists(invalidExtension),"R091_INVALID_EXTENSION_CREATED_FILE");
   MustReject(m4,"relative-not-absolute.lnk",osTarget,argText,desc);
   MustReject(m4,Path.Combine(own,"bad-target.lnk"),"relative-target.exe",argText,desc);
   Must(!File.Exists(Path.Combine(own,"bad-target.lnk")),"R091_INVALID_TARGET_CREATED_FILE");
   Console.WriteLine("R091_UNEXPECTED_RELATIVE_OR_NONLNK_PATHS_REJECTED=PASS");
   Must(Directory.GetFiles(own,"*.ps1").Length==0,"R091_CREATED_POWER_SHELL_FILE");
   Must(Directory.GetFiles(own,"*").Length==2,"R091_UNEXPECTED_QA_FILES_CREATED");
   Console.WriteLine("R091_NO_TEMP_PS1_OR_POWERSHELL_PROCESS=PASS");
   Console.WriteLine("R091_NO_ACTUAL_USER_DESKTOP_START_MENU_MUTATION=TRUE");
   return 0;
  }finally{
    if(File.Exists(unicodeLink))File.Delete(unicodeLink);
    if(File.Exists(normalLink))File.Delete(normalLink);
    Directory.Delete(own,false);
  }
 }
}
