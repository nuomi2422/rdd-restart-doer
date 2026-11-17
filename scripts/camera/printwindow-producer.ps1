# Thin persistent PrintWindow producer, reusing capture-win.ps1 flags=2 / DWM / blank rejection.
# stdout is raw BGRA ONLY. Diagnostics are stderr; no PNG frame spool, desktop fallback or focus API.
param([int]$TargetPid, [string]$HwndText, [string]$ExactTitle, [int]$Fps,
      [double]$Seconds, [string]$StopFile, [string]$RunDir)
$ErrorActionPreference = 'Stop'
try {
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Drawing;
using System.Drawing.Imaging;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Threading;
public class PrintWindowStream {
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern bool IsHungAppWindow(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder text, int n);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out Rect r);
  [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr h, int a, out Rect r, int size);
  [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
  static CultureInfo C = CultureInfo.InvariantCulture;
  static string N(double n) { return n.ToString("F3", C); }
  static string Q(string s) { return "\"" + (s ?? "").Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "\\r").Replace("\n", "\\n") + "\""; }
  static string Iso(DateTime d) { return d.ToString("o", C); }
  static Rect Check(IntPtr h, int pid, string title, bool dwm, int w, int ht) {
    uint actual;
    if (!IsWindow(h) || GetWindowThreadProcessId(h, out actual) == 0 || actual != (uint)pid) throw new Exception("sourceinvalid: HWND/PID no longer matches");
    StringBuilder text = new StringBuilder(32768); GetWindowText(h, text, text.Capacity);
    if (text.ToString() != title) throw new Exception("sourceinvalid: exact title changed");
    if (!IsWindowVisible(h) || IsIconic(h)) throw new Exception("sourceinvalid: hidden/minimized");
    if (IsHungAppWindow(h)) throw new Exception("sourceinvalid: target hung before PrintWindow");
    Rect r;
    if (dwm) { if (DwmGetWindowAttribute(h, 9, out r, 16) != 0) throw new Exception("sourceinvalid: DWM bounds unavailable"); }
    else if (!GetWindowRect(h, out r)) throw new Exception("sourceinvalid: bounds unavailable");
    int rw = r.Right-r.Left, rh = r.Bottom-r.Top;
    if (rw < 200 || rh < 200 || rw > 7680 || rh > 4320) throw new Exception("sourceinvalid: dimensions out of bounds");
    if (w != 0 && (rw != w || rh != ht)) throw new Exception("sourceinvalid: dimensions changed");
    return r;
  }
  static void Pixels(Bitmap bmp, Graphics g, IntPtr hwnd, byte[] data) {
    g.Clear(Color.Black);
    IntPtr dc = g.GetHdc(); bool ok;
    try { ok = PrintWindow(hwnd, dc, 2); } finally { g.ReleaseHdc(dc); }
    if (!ok) throw new Exception("PrintWindow returned false");
    BitmapData bits = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
    try {
      for (int y = 0; y < bmp.Height; y++) Marshal.Copy(IntPtr.Add(bits.Scan0, y * bits.Stride), data, y * bmp.Width * 4, bmp.Width * 4);
    } finally { bmp.UnlockBits(bits); }
    bool uniform = true;
    for (int y = 0; y < bmp.Height && uniform; y += Math.Max(1, bmp.Height/20))
      for (int x = 0; x < bmp.Width; x += Math.Max(1, bmp.Width/20)) {
        int i = (y * bmp.Width + x) * 4;
        if (data[i] != data[0] || data[i+1] != data[1] || data[i+2] != data[2]) { uniform = false; break; }
      }
    if (uniform) throw new Exception("blank: uniform PrintWindow frame rejected");
  }
  static long frames, samples, heldFrames, identicalSamples, lateSamples, lateFrames;
  static double maxCaptureMs, maxWriteMs, maxLagMs;
  static long lastOutputSample = -1;
  static void Emit(Stream output, StreamWriter csv, byte[] bytes, long sample, string utc, double start, double complete,
                   string hash, int fps, Stopwatch wall, string kind) {
    double pts = frames * 1000.0 / fps, before = wall.Elapsed.TotalMilliseconds;
    output.Write(bytes, 0, bytes.Length);
    double after = wall.Elapsed.TotalMilliseconds, lag = Math.Max(0, before - pts);
    maxWriteMs = Math.Max(maxWriteMs, after-before); maxLagMs = Math.Max(maxLagMs, lag);
    bool held = sample == lastOutputSample;
    if (held) heldFrames++;
    if (lag > 1000.0/fps) lateFrames++;
    csv.WriteLine(frames + "," + N(pts) + "," + sample + "," + utc + "," + N(start) + "," + N(complete) + "," + N(before) + "," + N(after) + "," + (held ? "1" : "0") + "," + N(lag) + "," + hash + "," + kind);
    lastOutputSample = sample; frames++;
  }
  public static int Run(int pid, string hwndText, string title, int fps, double seconds, string stop, string dir) {
    string error = null, reason = "duration", originUtc = null, endUtc = null;
    double endMs = 0; int w = 0, ht = 0; bool dwm = false;
    Stopwatch wall = new Stopwatch();
    StreamWriter csv = null; Bitmap bmp = null; Graphics g = null; Stream output = null;
    try {
      if (fps < 1 || fps > 30 || seconds < 1 || seconds > 10800) throw new Exception("invalid bounded duration/fps");
      if (File.Exists(stop)) throw new Exception("stop file already exists");
      long handle = hwndText.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? Convert.ToInt64(hwndText.Substring(2), 16) : long.Parse(hwndText, C);
      IntPtr hwnd = new IntPtr(handle);
      SetProcessDPIAware();
      Rect initial; dwm = DwmGetWindowAttribute(hwnd, 9, out initial, 16) == 0;
      initial = Check(hwnd, pid, title, dwm, 0, 0); w = initial.Right-initial.Left; ht = initial.Bottom-initial.Top;
      csv = new StreamWriter(Path.Combine(dir, "frames.csv"), false, new UTF8Encoding(false)); csv.AutoFlush = true;
      csv.WriteLine("frame,media_ms,sample,sample_utc,capture_start_mono_ms,capture_complete_mono_ms,write_start_mono_ms,write_complete_mono_ms,held_previous,late_ms,sha256,kind");
      bmp = new Bitmap(w, ht, PixelFormat.Format32bppArgb); g = Graphics.FromImage(bmp);
      byte[] next = new byte[w*ht*4], last = new byte[w*ht*4];
      string lastHash = null, lastUtc = null; double lastStart = 0, lastComplete = 0;
      output = Console.OpenStandardOutput();
      Console.Error.WriteLine("{\"event\":\"ready\",\"width\":" + w + ",\"height\":" + ht + ",\"pid\":" + pid + ",\"hwnd\":" + Q(hwndText) + ",\"title\":" + Q(title) + ",\"dwm\":" + (dwm ? "true" : "false") + "}");
      originUtc = Iso(DateTime.UtcNow); wall.Start(); double period = 1000.0/fps, limit = seconds*1000;
      using (SHA256 sha = SHA256.Create()) {
        while (true) {
          double elapsed = wall.Elapsed.TotalMilliseconds;
          if (File.Exists(stop) || elapsed >= limit) {
            reason = File.Exists(stop) ? "stop-file" : "duration"; endMs = elapsed; break;
          }
          double due = frames * period;
          if (elapsed < due) { Thread.Sleep((int)Math.Min(20, Math.Max(1, due-elapsed))); continue; }
          Check(hwnd, pid, title, dwm, w, ht);
          double start = wall.Elapsed.TotalMilliseconds; string utc = Iso(DateTime.UtcNow);
          Pixels(bmp, g, hwnd, next);
          Check(hwnd, pid, title, dwm, w, ht); // reject a resized/invalid capture before emitting it
          double complete = wall.Elapsed.TotalMilliseconds;
          string hash = BitConverter.ToString(sha.ComputeHash(next)).Replace("-", "").ToLowerInvariant();
          maxCaptureMs = Math.Max(maxCaptureMs, complete-start);
          if (complete-start > period || start-due > period) lateSamples++;
          if (lastHash != null && hash == lastHash) identicalSamples++;
          // Emit the new sample at the latest elapsed CFR slot. Older missed slots hold
          // the previous sample; the very first capture is explicitly initial-backfill.
          long latest = (long)Math.Floor(Math.Min(complete, limit-0.001)/period);
          while (frames < latest) {
            if (lastHash == null) Emit(output, csv, next, samples, utc, start, complete, hash, fps, wall, "initial-backfill");
            else Emit(output, csv, last, samples-1, lastUtc, lastStart, lastComplete, lastHash, fps, wall, "hold-capture-late");
          }
          byte[] swap = last; last = next; next = swap;
          lastHash = hash; lastUtc = utc; lastStart = start; lastComplete = complete; samples++;
          if (frames*period < limit) Emit(output, csv, last, samples-1, lastUtc, lastStart, lastComplete, lastHash, fps, wall, "sample");
        }
      }
      if (lastHash == null) throw new Exception("no valid frames before stop");
      // Tail rounding is explicit; media duration = ceil(actual capture wall time * fps) / fps.
      while (frames*1000.0/fps < endMs) Emit(output, csv, last, samples-1, lastUtc, lastStart, lastComplete, lastHash, fps, wall, "tail-hold");
      output.Flush();
    } catch (Exception ex) {
      error = ex.Message; reason = "failure"; endMs = wall.Elapsed.TotalMilliseconds;
    } finally {
      endUtc = Iso(DateTime.UtcNow);
      if (csv != null) csv.Dispose(); if (g != null) g.Dispose(); if (bmp != null) bmp.Dispose();
      // EOF is the only ffmpeg stop control in this mode, including source failures.
      if (output != null) output.Dispose();
      string json = "{\"ok\":" + (error == null ? "true" : "false") + ",\"reason\":" + Q(reason) + ",\"error\":" + (error == null ? "null" : Q(error)) +
        ",\"originUtc\":" + (originUtc == null ? "null" : Q(originUtc)) + ",\"finishedUtc\":" + Q(endUtc) +
        ",\"wallDurationMs\":" + N(endMs) + ",\"mediaDurationMs\":" + N(frames*1000.0/fps) + ",\"frames\":" + frames + ",\"captureSamples\":" + samples +
        ",\"distinctAdjacentSamples\":" + (samples-identicalSamples) + ",\"identicalAdjacentSamples\":" + identicalSamples + ",\"heldFrames\":" + heldFrames +
        ",\"lateSamples\":" + lateSamples + ",\"lateFrames\":" + lateFrames + ",\"maxCaptureMs\":" + N(maxCaptureMs) + ",\"maxWriteMs\":" + N(maxWriteMs) +
        ",\"maxLagMs\":" + N(maxLagMs) + ",\"width\":" + w + ",\"height\":" + ht + ",\"fps\":" + fps + "}";
      File.WriteAllText(Path.Combine(dir, "producer-terminal.json"), json, new UTF8Encoding(false));
      Console.Error.WriteLine(json);
    }
    return error == null ? 0 : 2;
  }
}
'@
exit [PrintWindowStream]::Run($TargetPid, $HwndText, $ExactTitle, $Fps, $Seconds, $StopFile, $RunDir)
} catch {
  [Console]::Error.WriteLine($_.Exception.ToString())
  exit 2
}
