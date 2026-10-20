<#
    找桌宠窗口并强制显示/置顶/居中
    （写在 .ps1 里，避开 PS 引号地狱）
#>
Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Win {
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

Add-Type -AssemblyName System.Windows.Forms

$found = New-Object System.Collections.ArrayList
$cb = [Win+EnumProc]{
  param($h, $p)
  $pp = 0
  [void][Win]::GetWindowThreadProcessId($h, [ref]$pp)
  $proc = Get-Process -Id $pp -ErrorAction SilentlyContinue
  if(-not $proc){ return $true }
  if($proc.ProcessName -ne 'powershell'){ return $true }
  $cl = New-Object System.Text.StringBuilder 256
  [void][Win]::GetClassName($h, $cl, 256)
  $tb = New-Object System.Text.StringBuilder 256
  [void][Win]::GetWindowText($h, $tb, 256)
  $cls = $cl.ToString(); $title = $tb.ToString()
  if($cls -match 'HwndWrapper|STAGER|PET' -or $title -match 'STAGER|桌宠|Pet'){
    $r = New-Object Win+RECT
    [void][Win]::GetWindowRect($h, [ref]$r)
    [void]$found.Add([pscustomobject]@{
      H=$h; Pid=$pp; Class=$cls; Title=$title
      X=$r.Left; Y=$r.Top; W=($r.Right-$r.Left); H2=($r.Bottom-$r.Top)
      Visible=[Win]::IsWindowVisible($h)
    })
  }
  return $true
}
[void][Win]::EnumWindows($cb, [IntPtr]::Zero)

if($found.Count -eq 0){
  Write-Output 'NOTFOUND'
  exit 1
}

Write-Output "FOUND $($found.Count)"
$found | ForEach-Object {
  Write-Output "  pid=$($_.Pid) cls=$($_.Class) title=[$($_.Title)] xy=($($_.X),$($_.Y)) size=$($_.W)x$($_.H2) vis=$($_.Visible)"
}

$t = $found | Sort-Object { $_.W * $_.H2 } -Descending | Select-Object -First 1
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$cx = [int](($wa.Width - $t.W) / 2)
$cy = [int](($wa.Height - $t.H2) / 2)
[void][Win]::ShowWindow($t.H, 4)                 # SW_SHOWNOACTIVATE：显示但不抢焦点
[void][Win]::SetWindowPos($t.H, [IntPtr](-1), $cx, $cy, $t.W, $t.H2, 0x0001)
Write-Output "MOVED pid=$($t.Pid) to ($cx,$cy) size=$($t.W)x$($t.H2) vis=$([Win]::IsWindowVisible($t.H))"