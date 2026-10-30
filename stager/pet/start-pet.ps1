<#
.SYNOPSIS
    STAGER 桌面宠物 —— 点它就报「现在第几阶段、第几轮、谁在干活」。

.DESCRIPTION
    透明置顶小窗，跟踪 stager 的 state.json：
      · 阶段变了自动换表情图
      · 点一下弹气泡（阶段 / 轮次 / 轮回 / 人次 / 门禁）
      · 拖动换位置（位置记在 pet\pet-pos.json）
      · 右键：换图 / 按表情指定图片 / 打开 stage 目录 / 退出
      · 系统托盘也有一份菜单

    没有图片时画一个占位小团子，不白屏。

    .EXAMPLE
    powershell -STA -NoProfile -File start-pet.ps1
    powershell -STA -NoProfile -File start-pet.ps1 -Size 260
    powershell -STA -NoProfile -File start-pet.ps1 -ShowBubble
#>
[CmdletBinding()]
param(
    [int]    $Size   = 0,
    [int]    $X      = -1,
    [int]    $Y      = -1,
    [int]    $PollMs = 1200,
    [switch] $NoTopmost,
    [switch] $ShowBubble
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$PetDir  = $PSScriptRoot
$Root    = Split-Path $PetDir -Parent
$ImgDir  = Join-Path $PetDir 'images'
$PosFile = Join-Path $PetDir 'pet-pos.json'
$StagesF = Join-Path $Root 'core\stages.json'
$Runtime = Join-Path $Root '.stager'
$ActiveF = Join-Path $Runtime 'active.json'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing | Out-Null

# ---------------------------------------------------------------- 小工具

function Read-Json($p, $dflt) {
    if (-not $p -or -not (Test-Path -LiteralPath $p)) { return $dflt }
    try { return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $dflt }
}

function Write-Json($p, $o) {
    $tmp = "$p.tmp"
    try {
        ($o | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $p -Force
    } catch { }
}

# ---------------------------------------------------------------- 阶段定义

$Stages = Read-Json $StagesF $null
if (-not $Stages) { $Stages = @{ stages = @(); expressions = @{}; expressionOrder = @() } }
$StageList = @($Stages.stages)
$ExprOrder = @($Stages.expressionOrder)
if ($ExprOrder.Count -eq 0 -and $Stages.expressions) {
    $ExprOrder = @($Stages.expressions.PSObject.Properties | ForEach-Object { $_.Name })
}

function Get-StageDef($id) {
    foreach ($s in $StageList) { if ($s.id -eq $id) { return $s } }
    return $null
}

# ---------------------------------------------------------------- 位置 / 偏好

$Pos = Read-Json $PosFile $null
if (-not $Pos) { $Pos = [pscustomobject]@{ x = -1; y = -1; size = 200; overrides = @{} } }
if ($Pos.PSObject.Properties['overrides'] -eq $null -or -not $Pos.overrides) {
    $Pos | Add-Member -NotePropertyName overrides -NotePropertyValue ([pscustomobject]@{}) -Force
}
if ($Size -le 0)      { $Size = $(if ($Pos.size) { [int]$Pos.size } else { 200 }) }
$Size = [Math]::Max(80, [Math]::Min(600, $Size))
$Pos.size = $Size
if ($X -ge 0) { $Pos.x = $X }
if ($Y -ge 0) { $Pos.y = $Y }

$work = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
if ($Pos.x -lt 0) { $Pos.x = $work.Right  - $Size - 30 }
if ($Pos.y -lt 0) { $Pos.y = $work.Bottom - $Size - 4 }
$script:PetX = [double]$Pos.x
$script:PetY = [double]$Pos.y

# ---------------------------------------------------------------- 图片映射

$ImgFiles = @()
if (Test-Path -LiteralPath $ImgDir) {
    $ImgFiles = @(Get-ChildItem -LiteralPath $ImgDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension.ToLower() -in @('.png', '.jpg', '.jpeg', '.webp', '.gif') } |
        Sort-Object Name)
}

$ExprMap = [ordered]@{}
foreach ($e in $ExprOrder) {
    $meta = $null
    if ($Stages.expressions -and $Stages.expressions.PSObject.Properties[$e]) { $meta = $Stages.expressions.$e }
    if ($meta -and $meta.file) {
        $p = Join-Path $ImgDir $meta.file
        if (Test-Path -LiteralPath $p) { $ExprMap[$e] = $p }
    }
}
# 命名对不上就按文件名顺序配对（图片命名随意也能用）
if ($ExprOrder.Count -gt 0 -and $ImgFiles.Count -ge $ExprOrder.Count) {
    for ($i = 0; $i -lt $ExprOrder.Count; $i++) {
        if (-not $ExprMap.Contains($ExprOrder[$i])) { $ExprMap[$ExprOrder[$i]] = $ImgFiles[$i].FullName }
    }
}
if ($ImgFiles.Count -gt 0) {
    foreach ($e in $ExprOrder) {
        if (-not $ExprMap.Contains($e)) { $ExprMap[$e] = $ImgFiles[0].FullName }
    }
}
$AllImages = @($ImgFiles | ForEach-Object { $_.FullName })

$BmpCache = @{}
function Get-Bmp($path) {
    if (-not $path) { return $null }
    if ($BmpCache.ContainsKey($path)) { return $BmpCache[$path] }
    try {
        $b = New-Object System.Windows.Media.Imaging.BitmapImage
        $b.BeginInit()
        $b.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $b.UriSource = New-Object System.Uri($path)
        $b.EndInit()
        $b.Freeze()
        $BmpCache[$path] = $b
        return $b
    } catch { return $null }
}

# ---------------------------------------------------------------- XAML

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="STAGER 桌宠" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ShowActivated="False"
        ResizeMode="NoResize" SizeToContent="WidthAndHeight"
        WindowStartupLocation="Manual" FontFamily="Segoe UI, Microsoft YaHei UI">
  <Grid x:Name="RootGrid">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border x:Name="Bubble" Grid.Row="0" Visibility="Collapsed"
            Background="#F5FFFFFF" BorderBrush="#C9B8E8" BorderThickness="1"
            CornerRadius="12" Padding="12,9" Margin="6,0,6,2"
            MaxWidth="440" HorizontalAlignment="Left">
      <StackPanel>
        <TextBlock x:Name="TBTitle" FontSize="13" FontWeight="Bold" Foreground="#3A2E5A" TextWrapping="Wrap"/>
        <TextBlock x:Name="TBStage" FontSize="15" FontWeight="Bold" Foreground="#5B3FA8" Margin="0,5,0,0" TextWrapping="Wrap"/>
        <TextBlock x:Name="TBRound" FontSize="12.5" Foreground="#4A4160" Margin="0,6,0,0" TextWrapping="Wrap"/>
        <TextBlock x:Name="TBActor" FontSize="12.5" Foreground="#4A4160" Margin="0,2,0,0" TextWrapping="Wrap"/>
        <TextBlock x:Name="TBGate"  FontSize="12.5" Margin="0,2,0,0" TextWrapping="Wrap"/>
        <TextBlock x:Name="TBHint"  FontSize="11"   Foreground="#8A83A0" Margin="0,7,0,0" TextWrapping="Wrap"/>
      </StackPanel>
    </Border>

    <Grid x:Name="PetHost" Grid.Row="1" Width="200" Height="200" HorizontalAlignment="Right"
          RenderTransformOrigin="0.5,0.5">
      <Grid.RenderTransform><ScaleTransform x:Name="PetScale" ScaleX="1" ScaleY="1" /></Grid.RenderTransform>
      <!-- Image 不能有内容属性，所以 RenderTransform 挂在它外面这层 PetHost 网格上 -->
      <Image x:Name="PetImage" Stretch="Uniform" Cursor="Hand" RenderOptions.BitmapScalingMode="HighQuality" />
      <Grid x:Name="Fallback" Visibility="Collapsed">
        <Ellipse Width="150" Height="140" Fill="#F0EAFF" Stroke="#B9A6E8" StrokeThickness="2"
                 VerticalAlignment="Bottom" HorizontalAlignment="Center" Margin="0,0,0,6"/>
        <Ellipse Width="13" Height="17" Fill="#4A3A78" VerticalAlignment="Top" HorizontalAlignment="Center" Margin="-30,0,0,0"/>
        <Ellipse Width="13" Height="17" Fill="#4A3A78" VerticalAlignment="Top" HorizontalAlignment="Center" Margin="30,0,0,0"/>
        <TextBlock x:Name="FBText" FontSize="52" VerticalAlignment="Center" HorizontalAlignment="Center" Text="OK"/>
      </Grid>
    </Grid>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win = [Windows.Markup.XamlReader]::Load($reader)

$RootGrid = $win.FindName('RootGrid')
$Bubble   = $win.FindName('Bubble')
$PetHost  = $win.FindName('PetHost')
$PetImage = $win.FindName('PetImage')
$Fallback = $win.FindName('Fallback')
$FBText   = $win.FindName('FBText')
$TBTitle  = $win.FindName('TBTitle')
$TBStage  = $win.FindName('TBStage')
$TBRound  = $win.FindName('TBRound')
$TBActor  = $win.FindName('TBActor')
$TBGate   = $win.FindName('TBGate')
$TBHint   = $win.FindName('TBHint')

if ($NoTopmost) { $win.Topmost = $false }
$PetHost.Width  = $Size
$PetHost.Height = $Size
$win.Left = $script:PetX
$win.Top  = $script:PetY

# ---------------------------------------------------------------- 置顶

# WPF 的 Topmost 会被别的置顶窗口（全屏终端/游戏）压下去，
# 所以每 2 秒用 SetWindowPos 重新顶一次 —— 不闪、不抢焦点。
$script:HWND = [IntPtr]::Zero
if (-not $NoTopmost) {
    if (-not ('StagerTop' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class StagerTop {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
        int X, int Y, int cx, int cy, uint uFlags);
}
'@ -Language CSharp
    }
}

# ---------------------------------------------------------------- 状态读取

$script:Stage       = $null
$script:Expr        = 'calm'
$script:FP          = ''
$script:BubbleOn    = $false
$script:DownAt       = $null
$script:PetScale     = $null
$script:ExprNow      = $null
$script:Override    = $null
$script:PtDown      = $null
$script:Moved       = $false
$script:IdleExpr    = 'shy'
$script:WinW        = $Size + 20

function Get-StagerState {
    $id = Read-Json $ActiveF $null
    if (-not $id) { return $null }
    $st = Read-Json (Join-Path (Join-Path $Runtime 'tasks') (Join-Path $id 'state.json')) $null
    if (-not $st) { return $null }
    $man = Read-Json (Join-Path (Join-Path $Runtime 'tasks') (Join-Path $id (Join-Path 'docs' 'manifest.json'))) $null
    $n = 0
    if ($man) { $n = @($man.docs).Count }
    $st | Add-Member -NotePropertyName docCount -NotePropertyValue $n -Force
    return $st
}

function Get-GateNeed($st) {
    # 返回本阶段门禁还缺什么（@() 表示达标）
    $need = @()
    if (-not $st) { return $need }
    $s = Get-StageDef $st.stage
    if (-not $s -or -not $s.gate) { return $need }
    # 注意：@($null) 会得到「含一个 null 的数组」，直接 foreach 会凭空多出「缺  标记」
    $needDocs = @()
    if ($s.gate.docs) { $needDocs = @($s.gate.docs) | Where-Object { $_ } }
    $needCmds = @()
    if ($s.gate.cmds) { $needCmds = @($s.gate.cmds) | Where-Object { $_ } }

    $man = Read-Json (Join-Path (Join-Path $Runtime 'tasks') (Join-Path $st.id (Join-Path 'docs' 'manifest.json'))) $null
    foreach ($k in $needDocs) {
        $hit = $false
        if ($man) {
            foreach ($d in @($man.docs)) {
                if ($d.kind -eq $k -and $d.stage -eq $st.stage -and $d.round -eq $st.round -and $d.file) {
                    # 登记了但正文被删 = 不算有
                    $fp = Join-Path (Join-Path $Runtime 'tasks') (Join-Path $st.id (Join-Path 'docs' $d.file))
                    if (Test-Path -LiteralPath $fp) { $hit = $true }
                }
            }
        }
        if (-not $hit) { $need += "缺 $k 文档" }
    }
    $k2 = '{0}:{1}' -f $st.round, $st.stage
    $marks = $st.marks
    foreach ($c in $needCmds) {
        $arr = @()
        if ($marks -and $marks.PSObject.Properties[$k2]) { $arr = @($marks.$k2) }
        if ($arr -notcontains $c) { $need += "缺 $c 标记" }
    }
    return $need
}

function Get-ExprOf($st) {
    if (-not $st -or $st.status -ne 'active') { return $script:IdleExpr }
    # 门禁没过 = 叉腰生气（比阶段的默认表情更有信息量）
    $S = $Stages
    $gateFail = 'angry'
    if ($S -and $S.exprPick -and $S.exprPick.gateFail) { $gateFail = $S.exprPick.gateFail }
    if ((Get-GateNeed $st).Count -gt 0) { return $gateFail }
    $s = Get-StageDef $st.stage
    if ($s -and $s.expr) { return [string]$s.expr }
    return 'calm'
}

function Get-ImagePath($expr) {
    if ($script:Override) { return $script:Override }
    $ov = $Pos.overrides
    if ($ov -and $ov.PSObject.Properties[$expr]) {
        $p = Join-Path $ImgDir $ov.$expr
        if (Test-Path -LiteralPath $p) { return $p }
    }
    if ($ExprMap.Contains($expr)) { return $ExprMap[$expr] }
    return $null
}

function Set-Pet($expr) {
    $path = Get-ImagePath $expr
    $bmp  = Get-Bmp $path
    # ★ 2026-10-01：记下当前表情。缺这行的话定时轮询不知道用户刚手动点成哪张，
    #   下一次轮询会把它顶回阶段表情 —— 表现为「点了没反应，过一会儿自己变回去」。
    $script:ExprNow = $expr
    if ($bmp) {
        $PetImage.Source = $bmp
        $PetImage.Visibility = 'Visible'
        $Fallback.Visibility = 'Collapsed'
    } else {
        $PetImage.Source = $null
        $PetImage.Visibility = 'Collapsed'
        $Fallback.Visibility = 'Visible'
    }
    $PetHost.UpdateLayout()
}

function Layout-Win {
    # SizeToContent 让窗口自己贴合内容（气泡多宽窗口就多宽），宠物右对齐不会跑位
    $win.SizeToContent = [System.Windows.SizeToContent]::WidthAndHeight
    $win.Width  = [double]::NaN
    $win.Height = [double]::NaN
    $win.UpdateLayout()
    $win.Dispatcher.Invoke([action] { }, [System.Windows.Threading.DispatcherPriority]::Loaded)

    $winW = [double]$win.ActualWidth
    $winH = [double]$win.ActualHeight
    if ($winW -le 0) { $winW = $Size + 20 }
    if ($winH -le 0) { $winH = $Size }
    $script:WinW = $winW
    $win.Left = $script:PetX - ($winW - $Size)
    $win.Top  = $script:PetY - ($winH - $Size)     # 窗口比宠物高出来的部分全是气泡，在上面
}

function Set-Bubble($on) {
    $script:BubbleOn = $on
    if ($on) { $Bubble.Visibility = 'Visible' } else { $Bubble.Visibility = 'Collapsed' }
    $win.Dispatcher.Invoke([action] { }, [System.Windows.Threading.DispatcherPriority]::Background)
    Layout-Win
}
function Update-Bubble {
    $st = Get-StagerState
    if (-not $st) {
        $TBTitle.Text  = 'STAGER 桌宠 · 休息中'
        $TBTitle.Foreground = [System.Windows.Media.Brushes]::DimGray
        $TBStage.Text  = '💤  没有进行中的 stage'
        $TBRound.Text  = '开新活：stager start "<标题>"'
        $TBActor.Text  = '或：stager list 看历史任务'
        $TBGate.Text   = ''
        $TBHint.Text   = '点一下收起 · 右键有菜单 · Esc 收起'
        return
    }
    $TBTitle.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(58, 46, 90))
    $s = Get-StageDef $st.stage
    if (-not $s) { $s = @{ icon = '•'; name = $st.stage; brief = ''; gate = $null } }
    $idx = 0
    for ($i = 0; $i -lt $StageList.Count; $i++) { if ($StageList[$i].id -eq $st.stage) { $idx = $i } }

    $TBTitle.Text  = [string]$st.title
    $TBTitle.ToolTip = [string]$st.id
    $TBStage.Text  = '{0} {1}   ({2}/{3})' -f $s.icon, $s.name, ($idx + 1), $StageList.Count
    $TBRound.Text  = '第 {0}/{1} 轮  ·  轮回 {2} 次' -f $st.round, $st.maxRounds, ([int]$st.wrap)
    $TBActor.Text  = '人次 {0}   ·   文档 {1} 份' -f $st.actor, $st.docCount

    $need = Get-GateNeed $st
    if ($need.Count -eq 0) {
        $TBGate.Text = '门禁 ✔ 达标'
        $TBGate.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(30, 130, 70))
    } else {
        $TBGate.Text = '门禁 ✘ ' + ($need -join '  +  ')
        $TBGate.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(190, 50, 50))
    }
    $TBHint.Text = '要点：' + $s.brief
}

function Refresh-All {
    $st = Get-StagerState
    $expr = Get-ExprOf $st
    if ($expr -ne $script:Expr) {
        $script:Expr = $expr
        $FBText.Text = $(if ($st) { $expr } else { 'zzZ' })
    }
    Set-Pet $script:Expr
    if ($script:BubbleOn) {
        Update-Bubble
        Layout-Win     # 文字变了（换行数变了）窗口尺寸会变 → 必须重新锚定，否则宠物会跑位
    }
}

# ---- Q 弹动画：0.86 → 1.12 → 0.97 → 1.0（三段衰减，像果冻）----
# 用 ScaleTransform 改 ScaleX/ScaleY；RenderTransformOrigin 已在 XAML 里设为中心。
function Invoke-PetBounce {
    if ($null -eq $script:PetScale) { return }
    $sc = $script:PetScale
    $keys = @(
        @{ ms = 0;   v = 1.00 },
        @{ ms = 55;  v = 0.84 },
        @{ ms = 115; v = 1.13 },
        @{ ms = 170; v = 0.96 },
        @{ ms = 225; v = 1.02 },
        @{ ms = 285; v = 1.00 }
    )
    foreach ($k in $keys) {
        $sc.ScaleX = $k.v
        $sc.ScaleY = $k.v
        $sc.UpdateLayout()
        Start-Sleep -Milliseconds $k.ms
    }
    $sc.ScaleX = 1.0
    $sc.ScaleY = 1.0
}

# ---- 点击换图：按 expressionOrder 循环 ----
# ★ 2026-10-01 修两次才对：
#   ① 原来调的是不存在的 Set-Expression（真名 Set-Pet）→ 点一下直接报错
#   ② 改成只调 Set-Pet 还是不行 —— Refresh-All 每 1.2s 会用阶段表情把它顶回去，
#      表现为「闪一下又变回去 / 看着像没反应」。
#   正解：走 $script:Override 通道。Get-ImagePath:302 会优先返回它，
#   所以 Refresh-All 也会尊重用户的选择，直到用户点「回到本阶段默认图」。
function Next-PetExpression {
    if ($ExprOrder.Count -eq 0) { return $false }
    $cur = $script:ExprNow
    if ([string]::IsNullOrEmpty($cur) -or -not ($ExprOrder -contains $cur)) { $cur = $ExprOrder[0] }
    $i = [Array]::IndexOf($ExprOrder, $cur)
    $next = $ExprOrder[($i + 1) % $ExprOrder.Count]
    # Override 存的是【图片路径】不是表情名 —— 传错类型会取不到图。
    # ★ $ExprMap 是 [ordered]@{}（OrderedDictionary），要用 .Contains() 不是 .ContainsKey()
    if ($ExprMap.Contains($next)) { $script:Override = $ExprMap[$next] }
    Set-Pet $next
    $script:ExprNow = $next
    return $true
}
# ---------------------------------------------------------------- 拖动 / 点击

$RootGrid.Add_MouseLeftButtonDown({
    param($sender, $e)
    $script:PtDown = $e.GetPosition($win)
    $script:DownAt = Get-Date
    $script:Moved = $false
})
$RootGrid.Add_MouseMove({
    param($sender, $e)
    if ($e.LeftButton -ne [System.Windows.Input.MouseButtonState]::Pressed) { return }
    if ($null -eq $script:PtDown) { return }
    $p = $e.GetPosition($win)
    if ([Math]::Abs($p.X - $script:PtDown.X) -gt 4 -or [Math]::Abs($p.Y - $script:PtDown.Y) -gt 4) {
        $script:Moved = $true
        $win.DragMove()
        $script:PtDown = $null
        # 重新量一次，别拿拖动前的旧尺寸换算（codex 指出这里会写错坐标）
        $winW = [double]$win.ActualWidth; if ($winW -le 0) { $winW = $script:WinW }
        $winH = [double]$win.ActualHeight; if ($winH -le 0) { $winH = $Size }
        $script:WinW = $winW
        $script:PetX = $win.Left + ($winW - $Size)
        $script:PetY = $win.Top + ($winH - $Size)
        $Pos.x = $script:PetX
        $Pos.y = $script:PetY
        Write-Json $PosFile $Pos
    }
})
$RootGrid.Add_MouseLeftButtonUp({
    param($sender, $e)
    if ($script:Moved) { $script:Moved = $false; return }
    # 消抖：拦的是「连点两次」，量的是【距上一次点击】不是「按下到抬起」。
    # ★ 2026-10-01 修：原来写成 (按下→抬起) < 250ms 就 return，
    #   而正常点击按下到抬起只有 50~150ms → 所有正常点击全被挡掉，表现为「点了没反应」。
    $now = Get-Date
    if ($script:LastClickAt -and ($now - $script:LastClickAt).TotalMilliseconds -lt 300) { return }
    $script:LastClickAt = $now
    # ★ 先 Q 弹，动画跑完再切图 —— 这样是「弹一下然后变」，
    #   而不是「突然变 + 抖一下」（后者就是你说的漂移感）
    Invoke-PetBounce
    $null = Next-PetExpression
    # 气泡照旧（换完图仍然能看状态）
    if ($script:BubbleOn) { Set-Bubble $false } else { Update-Bubble; Set-Bubble $true }
})
$win.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::Escape) { Set-Bubble $false }
})

# ---------------------------------------------------------------- 右键菜单

function Open-BossDashboard {
    Start-Process 'http://127.0.0.1:8891/#boss'
}

$menu = New-Object System.Windows.Controls.ContextMenu

function Add-Mi($header, $block) {
    $mi = New-Object System.Windows.Controls.MenuItem
    $mi.Header = $header
    $mi.Add_Click($block)
    $menu.Items.Add($mi) | Out-Null
    return $mi
}
function Add-Sep {
    $s = New-Object System.Windows.Controls.Separator
    $menu.Items.Add($s) | Out-Null
}

$null = Add-Mi '📋 报一下现在什么情况' { Update-Bubble; Set-Bubble $true }
$null = Add-Mi '🔄 刷新'                 { Refresh-All }
Add-Sep
$null = Add-Mi '🎲 随机换一张图' {
    if ($AllImages.Count -eq 0) { return }
    $script:Override = @($AllImages | Get-Random)[0]
    Set-Pet $script:Expr
}
$null = Add-Mi '♻️ 回到本阶段默认图' { $script:Override = $null; Set-Pet $script:Expr }

$exprMenu = New-Object System.Windows.Controls.MenuItem
$exprMenu.Header = '🎨 按表情指定图片'
if ($ExprOrder.Count -eq 0) {
    $mm = New-Object System.Windows.Controls.MenuItem
    $mm.Header = '(core\stages.json 里没配 expressionOrder)'
    $mm.IsEnabled = $false
    $exprMenu.Items.Add($mm) | Out-Null
}
foreach ($e in $ExprOrder) {
    $mm = New-Object System.Windows.Controls.MenuItem
    $mm.Header = [string]$e
    $mm.IsCheckable = $true
    $mm.IsChecked = ($script:Override -eq $ExprMap[$e])
    $mm.Add_Click({
        param($sender, $e2)
        $name = [string]$sender.Header
        if ($ExprMap.Contains($name)) {
            $script:Override = $null
            $ov = $Pos.overrides
            $ov | Add-Member -NotePropertyName $name -NotePropertyValue ([System.IO.Path]::GetFileName($ExprMap[$name])) -Force
            Write-Json $PosFile $Pos
            Set-Pet $script:Expr
        }
    })
    $exprMenu.Items.Add($mm) | Out-Null
}
$menu.Items.Add($exprMenu) | Out-Null

Add-Sep
$null = Add-Mi '📂 打开 stage 目录' {
    $id = Read-Json $ActiveF $null
    if ($id) { Start-Process explorer.exe (Join-Path (Join-Path $Runtime 'tasks') $id) }
    else { Start-Process explorer.exe $Runtime }
}
$null = Add-Mi '💻 打开 cmd 敲 stager' {
    Start-Process cmd.exe -ArgumentList '/k', ('chcp 65001 && cd /d "' + $Root + '"')
}
Add-Sep
$null = Add-Mi '❌ 退出桌宠' { $win.Close() }

$RootGrid.ContextMenu = $menu

# ---------------------------------------------------------------- 托盘

$tray = $null
try {
    $tray = New-Object System.Windows.Forms.NotifyIcon
    $tray.Text = 'STAGER 桌宠'
    $tray.Icon = [System.Drawing.SystemIcons]::Information
    $trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $null = $trayMenu.Items.Add('报状态', { Update-Bubble; Set-Bubble $true })
    $null = $trayMenu.Items.Add('打开老板台', { Open-BossDashboard })
    $null = $trayMenu.Items.Add('刷新', { Refresh-All })
    $null = $trayMenu.Items.Add('退出', { $win.Close() })
    $tray.ContextMenuStrip = $trayMenu
    $tray.Visible = $true
    $tray.Add_DoubleClick({ Update-Bubble; Set-Bubble $true })
} catch { $tray = $null }

# ---------------------------------------------------------------- 轮询

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds($PollMs)
$timer.Add_Tick({
    $st = Get-StagerState
    # 指纹必须含 docRev/updatedAt —— 只看阶段的话，put 了新文档气泡还一直说"缺文档"
    $fp = 'idle'
    if ($st) { $fp = '{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}' -f $st.id, $st.stage, $st.round, $st.wrap, $st.actor, $st.status, $st.updatedAt, $st.docRev }
    if ($fp -eq $script:FP) { return }
    $script:FP = $fp
    Refresh-All
})
$timer.Start()

$topTimer = $null
if (-not $NoTopmost) {
    $topTimer = New-Object System.Windows.Threading.DispatcherTimer
    $topTimer.Interval = [TimeSpan]::FromSeconds(2)
    $topTimer.Add_Tick({
        if ($script:HWND -ne [IntPtr]::Zero) {
            $SWP_NOSIZE = 0x0001; $SWP_NOMOVE = 0x0002; $SWP_NOACTIVATE = 0x0010
            [void][StagerTop]::SetWindowPos($script:HWND, [IntPtr](-1), 0, 0, 0, 0,
                ($SWP_NOSIZE -bor $SWP_NOMOVE -bor $SWP_NOACTIVATE))
        }
    })
}

# ---------------------------------------------------------------- 启动

Set-Pet $script:Expr
$win.Show()
if (-not $NoTopmost) {
    $script:HWND = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
    $topTimer.Start()
    $win.Dispatcher.Invoke([action] { }, [System.Windows.Threading.DispatcherPriority]::Background)
    $topTimer.Stop(); $topTimer.Start()
}
$win.Dispatcher.Invoke([action] { }, [System.Windows.Threading.DispatcherPriority]::Background)
Layout-Win
Refresh-All

if ($ShowBubble) { Update-Bubble; Set-Bubble $true }

$win.Add_Closed({
    $timer.Stop()
    if ($topTimer) { $topTimer.Stop() }
    $Pos.x = $script:PetX
    $Pos.y = $script:PetY
    $Pos.size = $Size
    Write-Json $PosFile $Pos
    if ($tray) { $tray.Visible = $false; $tray.Dispose() }
})

[System.Windows.Threading.Dispatcher]::Run()
