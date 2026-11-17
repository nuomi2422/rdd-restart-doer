param([string]$Dir)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Drawing;
using System.Diagnostics;
using System.Windows.Forms;
using System.Threading;
using System.Runtime.InteropServices;
public class OwnedNeutral : Form {
  [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
  string dir; bool cover; public bool Blank;
  Stopwatch clock = Stopwatch.StartNew();
  protected override bool ShowWithoutActivation { get { return true; } }
  protected override CreateParams CreateParams { get { var cp=base.CreateParams; cp.ExStyle |= 0x08000000; return cp; } }
  public OwnedNeutral(string d, bool c) {
    dir=d; cover=c; DoubleBuffered=true; FormBorderStyle=FormBorderStyle.None;
    StartPosition=FormStartPosition.Manual; Location=new Point(80,80); Size=new Size(640,360);
    Text=c ? "174-OWNED-OCCLUDER-MAGENTA" : "174-OWNED-COUNTER-"+Process.GetCurrentProcess().Id;
    ShowInTaskbar=false;
  }
  protected override void OnPaint(PaintEventArgs e) {
    if (!cover && File.Exists(Path.Combine(dir,"slow"))) Thread.Sleep(280);
    if (cover) { e.Graphics.Clear(Color.Magenta); e.Graphics.DrawString("OCCLUDER ONLY",new Font("Arial",28),Brushes.Black,20,120); return; }
    if (Blank) { e.Graphics.Clear(Color.Black); return; }
    int count=(int)(clock.Elapsed.TotalMilliseconds/100);
    e.Graphics.Clear(Color.FromArgb(12,95,115));
    using(var font=new Font("Consolas",34,FontStyle.Bold)) e.Graphics.DrawString("OWNED TARGET",font,Brushes.White,10,10);
    using(var font=new Font("Consolas",48,FontStyle.Bold)) e.Graphics.DrawString(count.ToString("D6"),font,Brushes.Yellow,10,90);
    for(int bit=0;bit<16;bit++) e.Graphics.FillRectangle(((count>>bit)&1)==0?Brushes.Black:Brushes.White,10+bit*36,230,28,80);
    e.Graphics.FillEllipse(Brushes.Lime,20+(count*7)%540,175,30,30);
  }
  protected override void WndProc(ref Message m) {
    base.WndProc(ref m);
    if (!cover && m.Msg==0x0317 && File.Exists(Path.Combine(dir,"slow"))) Thread.Sleep(280);
  }
  [STAThread] public static void Run(string dir) {
    SetProcessDPIAware(); Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
    var target=new OwnedNeutral(dir,false); var occluder=new OwnedNeutral(dir,true);
    bool shown=false, sized=false, minimized=false;
    var timer=new System.Windows.Forms.Timer(); timer.Interval=50;
    Action<string> note = delegate(string text) { File.AppendAllText(Path.Combine(dir,"fixture-events.csv"),DateTime.UtcNow.ToString("o")+","+text+Environment.NewLine); };
    timer.Tick += delegate {
      if(File.Exists(Path.Combine(dir,"close"))) { note("natural-close"); timer.Stop(); occluder.Close(); target.Close(); return; }
      if(File.Exists(Path.Combine(dir,"cover")) && !shown) { occluder.TopMost=true; occluder.Show(target); shown=true; note("cover-shown-magenta-640x360"); }
      if(File.Exists(Path.Combine(dir,"resize")) && !sized) { target.Width=680; sized=true; note("target-resized"); }
      if(File.Exists(Path.Combine(dir,"minimize")) && !minimized) { target.WindowState=FormWindowState.Minimized; minimized=true; note("target-minimized"); }
      target.Blank=File.Exists(Path.Combine(dir,"blank")); target.Invalidate();
    };
    target.Shown += delegate {
      File.WriteAllText(Path.Combine(dir,"fixture.json"),"{\"pid\":"+Process.GetCurrentProcess().Id+",\"hwnd\":\""+target.Handle.ToInt64()+"\",\"title\":\""+target.Text+"\",\"occluderHwnd\":\""+occluder.Handle.ToInt64()+"\"}",new UTF8Encoding(false));
      note("target-shown"); timer.Start();
    };
    Application.Run(target); timer.Dispose(); occluder.Dispose(); target.Dispose(); note("exited");
  }
}
'@
[OwnedNeutral]::Run($Dir)
