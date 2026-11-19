# -*- coding: utf-8 -*-
# AION 2 (Steam / PURPLE 正式版) 简繁汉化与还原工具
# 作者: B站@吃素的佩奇
# 开源主页: https://github.com/duoluoyuji/Aion2-Global-CN

param(
    [switch]$Install,
    [switch]$Restore,
    [ValidateSet('en', 'ja')][string]$Entry = 'en',
    [string]$Lang = 'zh'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch { }
# 让 PowerShell 进程声明 DPI 感知，否则 125% / 150% 缩放下界面文字会被拉伸发虚
try {
    Add-Type -Namespace Aion2Win32 -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd); [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hdc); [DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr hdc, int nIndex);'
    [void][Aion2Win32.Dpi]::SetProcessDPIAware()
    Add-Type -Namespace Aion2Win32 -Name Scroll -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowScrollBar(IntPtr hWnd, int wBar, bool bShow); [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);'
} catch { }

$ToolDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

# 两个语言入口互斥：en 与 ja 的同名 locres 同时存在时，英文会按 key 回退覆盖日文，
# 所以部署任一入口前，必须先物理移除另一个入口的文件（日志里逐条记录）。
$Entries = @{
    en = @{
        Name      = '英文入口'
        Culture   = 'English'
        Keys      = @('en', 'en-US')
        LocresRel = @(
            'Engine\Content\Localization\Engine\Platforms\Windows\en\Engine.locres',
            'Engine\Content\Localization\Engine\Platforms\Windows\en-US\Engine.locres'
        )
    }
    ja = @{
        Name      = '日文入口'
        Culture   = '日本語'
        Keys      = @('ja', 'ja-JP')
        LocresRel = @(
            'Engine\Content\Localization\Engine\Platforms\Windows\ja\Engine.locres',
            'Engine\Content\Localization\Engine\Platforms\Windows\ja-JP\Engine.locres'
        )
    }
}
if (-not $Entries.ContainsKey($Entry)) { $Entry = 'en' }
$Lang = if ($Lang -eq 'zh-TW' -or $Lang -eq 'tw' -or $Lang -eq 'cht') { 'zh-TW' } else { 'zh' }
$LangName    = if ($Lang -eq 'zh') { '简体中文' } else { '繁体中文' }
$OtherEntry  = if ($Entry -eq 'en') { 'ja' } else { 'en' }
$AllLocresRel = @($Entries['en'].LocresRel) + @($Entries['ja'].LocresRel)

$CurrentVersion = '0.0.1'
# 3393110 为 Steam 正式服 AppID，4972320 为 Steam Playtest 测试服 AppID
$AppIds         = @('3393110', '4972320')
$RemoteVersionUrl   = 'https://raw.githubusercontent.com/duoluoyuji/Aion2-Global-CN/main/version.json'
$FallbackVersionUrl = 'https://gh-proxy.com/https://raw.githubusercontent.com/duoluoyuji/Aion2-Global-CN/main/version.json'

# ==================== 客户端状态检测 ====================
function Get-Sha256([string]$Path) {
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash } catch { return '' }
}

function Get-PayloadPath([string]$EntryKey, [string]$LangKey) {
    return (Join-Path $ToolDir ("payload\{0}\{1}\Engine.locres" -f $EntryKey, $LangKey))
}

function Get-PayloadHash([string]$EntryKey, [string]$LangKey) {
    return (Get-Sha256 (Get-PayloadPath $EntryKey $LangKey))
}

# 客户端状态：分别看英文入口 / 日文入口的两组 locres 在不在、是不是本工具装的。
# 游戏本体不自带松散 locres，所以两组都不存在就是官方原版。
function Get-ClientState([string]$Root) {
    if (-not (Test-GameRoot $Root)) { return '目录无效' }

    $present = @{}
    foreach ($k in @('en', 'ja')) {
        $vals = @()
        foreach ($rel in $Entries[$k].LocresRel) {
            $p = Join-Path $Root $rel
            $vals += if (Test-Path $p) { Get-Sha256 $p } else { '' }
        }
        $present[$k] = $vals
    }
    $enHere = @($present['en'] | Where-Object { $_ }).Count -gt 0
    $jaHere = @($present['ja'] | Where-Object { $_ }).Count -gt 0
    if (-not $enHere -and -not $jaHere) { return '官方原版' }
    if ($enHere -and $jaHere) { return '异常：两个入口的文件同时存在' }

    $k = if ($enHere) { 'en' } else { 'ja' }
    $vals = $present[$k]
    foreach ($lg in @('zh', 'zh-TW')) {
        $h = Get-PayloadHash $k $lg
        if ($h -and @($vals | Where-Object { $_ -ne $h }).Count -eq 0) {
            $ln = if ($lg -eq 'zh') { '简体中文' } else { '繁体中文' }
            return ("{0} · {1}" -f $Entries[$k].Name, $ln)
        }
    }
    return '未知汉化文件'
}

# 还原 = 删掉四个入口文件。删掉即回落官方原版，不需要任何备份。
function Restore-ClientFiles([string]$Root) {
    $removed = @()
    foreach ($rel in $AllLocresRel) {
        $p = Join-Path $Root $rel
        if (Test-Path $p) {
            Set-ItemProperty -Path $p -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path $p)) { $removed += $rel }
        }
    }
    return $removed
}

function Get-ShortRel([string]$Rel) {
    return ($Rel -replace '^Engine\\Content\\Localization\\Engine\\Platforms\\Windows\\', '')
}

# 部署：先移除另一个入口的全部文件（互斥），再写入本入口的两个文件。
function Install-EntryFiles([string]$Root, [string]$EntryKey, [string]$LangKey) {
    $src = Get-PayloadPath $EntryKey $LangKey
    $other = if ($EntryKey -eq 'en') { 'ja' } else { 'en' }

    foreach ($rel in $Entries[$other].LocresRel) {
        $p = Join-Path $Root $rel
        if (Test-Path $p) {
            Set-ItemProperty -Path $p -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
            if (Test-Path $p) { throw "无法移除冲突文件（可能被占用）：$rel" }
            Write-Host ("[移除] {0}   已删除（{1}残留）" -f (Get-ShortRel $rel), $Entries[$other].Name) -ForegroundColor DarkYellow
            Write-InstallLog "移除 $Root : $rel"
        }
    }

    $hash = ''
    foreach ($rel in $Entries[$EntryKey].LocresRel) {
        $dst = Join-Path $Root $rel
        $hash = Safe-CopyFile $src $dst
        $len = (Get-Item -LiteralPath $dst).Length
        Write-Host ("[写入] {0}   {1:N0} B  OK" -f (Get-ShortRel $rel), $len) -ForegroundColor Green
    }
    return $hash
}

# 读取游戏语言：Aion2 下可能有 Saved / Saved_Steam / Saved_TW 等多个配置目录。
function Get-GameCultures {
    $result = @()
    $base = Join-Path $env:LOCALAPPDATA 'Aion2'
    if (-not (Test-Path $base)) { return $result }
    foreach ($d in @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue)) {
        $ini = Join-Path $d.FullName 'Config\Windows\Engine.ini'
        if (-not (Test-Path $ini)) { continue }
        $t = Get-Content -LiteralPath $ini -Raw -ErrorAction SilentlyContinue
        if (-not $t) { continue }
        $m = [regex]::Match($t, '(?im)^\s*Culture\s*=\s*"?([^"\r\n]+)"?')
        if ($m.Success) {
            $v = $m.Groups[1].Value.Trim()
            if ($v -and ($result -notcontains $v)) { $result += $v }
        }
    }
    return $result
}

function Get-CultureText([string]$Culture) {
    switch ($Culture.ToLower()) {
        'en' { return 'English (en)' }
        'en-us' { return 'English (en-US)' }
        'ja' { return '日本語 (ja)' }
        'ja-jp' { return '日本語 (ja-JP)' }
        'ko' { return '한국어 (ko)' }
        'ko-kr' { return '한국어 (ko-KR)' }
        default { return $Culture }
    }
}

# ==================== 控制台作者署名横幅 ====================
function Show-Banner {
    Write-Host "========================================================================" -ForegroundColor Magenta
    Write-Host "         AION 2 (Steam / PURPLE 正式版) 简繁汉化工具 v$CurrentVersion" -ForegroundColor Cyan
    Write-Host "         入口: $($Entries[$Entry].Name)    文本: $LangName" -ForegroundColor Cyan
    Write-Host "         制作团队: 吃素的佩奇汉化" -ForegroundColor Gray
    Write-Host "         开源主页: https://github.com/duoluoyuji/Aion2-Global-CN" -ForegroundColor Gray
    Write-Host "         【声明】本工具完全免费分享，仅供交流学习，严禁倒卖牟利！" -ForegroundColor Red
    Write-Host "========================================================================" -ForegroundColor Magenta
    Write-Host ""
}

# ==================== 在线版本检测与自动更新提醒 ====================
function Check-Update {
    Write-Host "[1/6] 检查更新 ................" -ForegroundColor DarkGray
    $remoteJson = $null
    $urls = @($RemoteVersionUrl, $FallbackVersionUrl)
    try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]3072 } catch {}
    
    foreach ($u in $urls) {
        try {
            $req = [System.Net.HttpWebRequest]::Create($u)
            $req.Timeout = 3000
            $req.UserAgent = "Aion2CNTool"
            $resp = $req.GetResponse()
            $sr = New-Object System.IO.StreamReader($resp.GetResponseStream(), [System.Text.Encoding]::UTF8)
            $txt = $sr.ReadToEnd()
            $sr.Close()
            $resp.Close()
            if ($txt) {
                $remoteJson = ConvertFrom-Json $txt
                break
            }
        } catch {}
    }

    if ($remoteJson) {
        $shouldUpdate = $false
        try {
            $rv = [System.Version]$remoteJson.version
            $lv = [System.Version]$CurrentVersion
            # 只接受同主版本号的更新（v0.x）：旧仓库里的 v2.x 属于另一套英文入口包，不能当成新版本
            if ($rv.Major -eq $lv.Major -and $rv -gt $lv) { $shouldUpdate = $true }
        } catch {}

        if ($shouldUpdate) {
            Write-Host ">>> 发现新版本: v$($remoteJson.version)！" -ForegroundColor Yellow
            $tip = "发现 AION 2 汉化工具最新版本：v$($remoteJson.version)`n`n公告内容：`n$($remoteJson.announcement)`n`n是否立即打开下载页面？"
            $box = [System.Windows.Forms.MessageBox]::Show($tip, "版本更新提示 - B站@吃素的佩奇", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
            if ($box -eq [System.Windows.Forms.DialogResult]::Yes) {
                try {
                    Start-Process "https://github.com/duoluoyuji/Aion2-Global-CN/releases"
                } catch {
                    try {
                        [System.Diagnostics.Process]::Start((New-Object System.Diagnostics.ProcessStartInfo("https://github.com/duoluoyuji/Aion2-Global-CN/releases") -Property @{UseShellExecute=$true}))
                    } catch {}
                }
            }
        } else {
            Write-Host "-> 暂无适用于 v$CurrentVersion 的更新。" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "-> 网络检测超时，使用离线模式继续运行。" -ForegroundColor DarkGray
    }
}

# ==================== 路径识别（不依赖任何固定盘符） ====================
function Test-GameRoot([string]$p) {
    if (-not $p) { return $false }
    if (Test-Path (Join-Path $p 'Aion2\Content\Paks')) { return $true }
    return $false
}

# 把用户选中的目录纠正成真正的游戏根目录（兼容选到 Aion2 子目录、common、steamapps）
function Resolve-GameRoot([string]$sel) {
    if (-not $sel) { return $null }
    $sel = $sel.TrimEnd('\', '/')
    if ((Split-Path $sel -Leaf) -eq 'steamapps') { $sel = Join-Path $sel 'common' }
    $cands = @($sel)
    $p1 = Split-Path $sel -Parent
    if ($p1) { $cands += $p1 }
    $p2 = Split-Path $p1 -Parent
    if ($p2) { $cands += $p2 }
    foreach ($c in $cands) {
        if (Test-GameRoot $c) { return $c }
        if (Test-Path $c) {
            $subs = @(Get-ChildItem -LiteralPath $c -Directory -ErrorAction SilentlyContinue | Where-Object { Test-GameRoot $_.FullName })
            if ($subs.Count -eq 1) { return $subs[0].FullName }
        }
    }
    return $null
}

# ==================== 扫描全盘所有已安装的 AION 2 版本 ====================
function Get-AllGameRoots {
    $detected = @()
    $fixedDrives = (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -ne $null -and $_.Root }).Root
    
    # ---------------- 1. 扫描 Steam 游戏库 ----------------
    $steamRoots = @()
    foreach ($d in $fixedDrives) {
        $candidates = @(
            (Join-Path $d 'SteamLibrary\steamapps'),
            (Join-Path $d 'steamapps'),
            (Join-Path $d 'Program Files (x86)\Steam\steamapps'),
            (Join-Path $d 'Program Files\Steam\steamapps'),
            (Join-Path $d 'Steam\steamapps')
        )
        foreach ($c in $candidates) {
            if (Test-Path $c) { $steamRoots += $c }
        }
    }
    
    try {
        $reg = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue
        if ($reg -and $reg.SteamPath) {
            $regApps = Join-Path $reg.SteamPath 'steamapps'
            if (Test-Path $regApps) { $steamRoots += $regApps }
        }
    } catch {}

    # 1.1 读取 Steam 库清单 libraryfolders.vdf，兼容「自定义名字/其它盘」的游戏库
    $vdfFiles = @()
    foreach ($sr in $steamRoots) {
        $vdfFiles += (Join-Path (Split-Path $sr -Parent) 'config\libraryfolders.vdf')
    }
    try {
        $reg2 = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue
        if ($reg2 -and $reg2.SteamPath) {
            $sp = $reg2.SteamPath.ToString().Replace('/', '\')
            $vdfFiles += (Join-Path $sp 'config\libraryfolders.vdf')
        }
    } catch {}
    foreach ($v in ($vdfFiles | Select-Object -Unique)) {
        if (Test-Path $v) {
            try {
                $vt = [System.IO.File]::ReadAllText($v)
                foreach ($m in [regex]::Matches($vt, '"path"\s+"([^"]+)"')) {
                    $libPath = $m.Groups[1].Value.Replace('\\', '\')
                    $sa = Join-Path $libPath 'steamapps'
                    if (Test-Path $sa) { $steamRoots += $sa }
                }
            } catch {}
        }
    }

    $steamRoots = $steamRoots | Select-Object -Unique

    foreach ($r in $steamRoots) {
        foreach ($aid in $AppIds) {
            $acf = Join-Path $r "appmanifest_$aid.acf"
            if (Test-Path $acf) {
                try {
                    $txt = Get-Content $acf -Raw -ErrorAction SilentlyContinue
                    if ($txt -match '"installdir"\s+"([^"]+)"') {
                        $gameAbs = Join-Path (Join-Path $r 'common') $matches[1]
                        if (Test-GameRoot $gameAbs) {
                            $label = if ($aid -eq '3393110') { "Steam 国际正式版" } else { "Steam 测试服版" }
                            if (-not ($detected | Where-Object { $_.Path.ToLower() -eq $gameAbs.ToLower() })) {
                                $detected += [PSCustomObject]@{
                                    Platform = $label
                                    Path     = $gameAbs
                                    Type     = "Steam"
                                }
                            }
                        }
                    }
                } catch {}
            }
        }

        $common = Join-Path $r 'common'
        if (Test-Path $common) {
            $hits = Get-ChildItem $common -Directory -ErrorAction SilentlyContinue | Where-Object {
                Test-GameRoot $_.FullName
            }
            foreach ($h in $hits) {
                if (-not ($detected | Where-Object { $_.Path.ToLower() -eq $h.FullName.ToLower() })) {
                    $detected += [PSCustomObject]@{
                        Platform = "Steam 游戏库 ($($h.Name))"
                        Path     = $h.FullName
                        Type     = "Steam"
                    }
                }
            }
        }
    }

    # ---------------- 2. 三重增强：扫描 NCSoft PURPLE (紫P) 客户端 ----------------
    # 增强 1：从 plaync 官方注册表枚举 BaseDir
    $playncRegKeys = @(
        "HKLM:\SOFTWARE\plaync",
        "HKLM:\SOFTWARE\WOW6432Node\plaync",
        "HKCU:\SOFTWARE\plaync"
    )
    foreach ($rk in $playncRegKeys) {
        try {
            if (Test-Path $rk) {
                $subKeys = Get-ChildItem -Path $rk -ErrorAction SilentlyContinue
                foreach ($sk in $subKeys) {
                    $props = Get-ItemProperty -Path $sk.PSPath -ErrorAction SilentlyContinue
                    if ($props -and $props.BaseDir) {
                        $bPath = $props.BaseDir.ToString().TrimEnd('\')
                        if (Test-GameRoot $bPath) {
                            if (-not ($detected | Where-Object { $_.Path.ToLower() -eq $bPath.ToLower() })) {
                                $detected += [PSCustomObject]@{
                                    Platform = "NCSoft PURPLE 国际服 (注册表定位)"
                                    Path     = $bPath
                                    Type     = "PURPLE"
                                }
                            }
                        }
                    }
                }
            }
        } catch {}
    }

    # 增强 2：从 Windows 软件卸载列表中精确匹配 AION 2 / PURPLE 安装目录
    $uninstallRegKeys = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($uk in $uninstallRegKeys) {
        try {
            if (Test-Path $uk) {
                $subKeys = Get-ChildItem -Path $uk -ErrorAction SilentlyContinue
                foreach ($sk in $subKeys) {
                    $props = Get-ItemProperty -Path $sk.PSPath -ErrorAction SilentlyContinue
                    if ($props) {
                        $dName = $props.DisplayName
                        $iLoc = $props.InstallLocation
                        if ($dName -and ($dName -like "*AION*" -or $dName -like "*Purple*") -and $iLoc) {
                            $cleanLoc = $iLoc.ToString().TrimEnd('\')
                            if (Test-GameRoot $cleanLoc) {
                                if (-not ($detected | Where-Object { $_.Path.ToLower() -eq $cleanLoc.ToLower() })) {
                                    $detected += [PSCustomObject]@{
                                        Platform = "NCSoft PURPLE 国际服 (系统识别)"
                                        Path     = $cleanLoc
                                        Type     = "PURPLE"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch {}
    }

    # 增强 3：全盘常见默认路径深度匹配池
    foreach ($d in $fixedDrives) {
        $purpleCandidates = @(
            (Join-Path $d 'AION 2'),
            (Join-Path $d 'Aion2'),
            (Join-Path $d 'Games\AION 2'),
            (Join-Path $d 'Games\Aion2'),
            (Join-Path $d 'PurpleGames\AION 2'),
            (Join-Path $d 'PurpleGames\Aion2'),
            (Join-Path $d 'Purple\Games\AION 2'),
            (Join-Path $d 'NC\AION 2'),
            (Join-Path $d 'NCSOFT\AION 2'),
            (Join-Path $d 'NCSOFT\Purple\Games\AION 2'),
            (Join-Path $d 'Program Files\NCSOFT\Purple\AION 2'),
            (Join-Path $d 'Program Files (x86)\NCSOFT\Purple\AION 2')
        )
        foreach ($pc in $purpleCandidates) {
            if (Test-GameRoot $pc) {
                if (-not ($detected | Where-Object { $_.Path.ToLower() -eq $pc.ToLower() })) {
                    $detected += [PSCustomObject]@{
                        Platform = "NCSoft PURPLE 国际服 (磁盘扫描)"
                        Path     = $pc
                        Type     = "PURPLE"
                    }
                }
            }
        }
    }

    # ---------------- 3. 兜底：每个盘浅层看两层目录，兼容任意自定义安装位置 ----------------
    $skipNames = @('Windows', '$Recycle.Bin', 'System Volume Information', 'Config.Msi', 'Recovery', 'PerfLogs', 'AppData')
    foreach ($d in $fixedDrives) {
        $tops = @()
        try { $tops = @(Get-ChildItem -LiteralPath $d -Directory -ErrorAction SilentlyContinue) } catch { continue }
        foreach ($t in $tops) {
            if ($skipNames -contains $t.Name) { continue }
            if (Test-GameRoot $t.FullName) {
                if (-not ($detected | Where-Object { $_.Path.ToLower() -eq $t.FullName.ToLower() })) {
                    $detected += [PSCustomObject]@{
                        Platform = "磁盘扫描 ($($t.Name))"
                        Path     = $t.FullName
                        Type     = "Local"
                    }
                }
                continue
            }
            try {
                foreach ($g in @(Get-ChildItem -LiteralPath $t.FullName -Directory -ErrorAction SilentlyContinue)) {
                    if (Test-GameRoot $g.FullName) {
                        if (-not ($detected | Where-Object { $_.Path.ToLower() -eq $g.FullName.ToLower() })) {
                            $detected += [PSCustomObject]@{
                                Platform = "磁盘扫描 ($($t.Name)\$($g.Name))"
                                Path     = $g.FullName
                                Type     = "Local"
                            }
                        }
                    }
                }
            } catch {}
        }
    }

    return $detected
}

# 手动选择游戏目录保底
function Select-GameFolder {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "未自动检测到游戏安装位置。请选择游戏目录（选 AION 2、Aion2、common 或 steamapps 都可以，工具会自动纠正）："
    $dlg.ShowNewFolderButton = $false
    if ($dlg.ShowDialog() -eq 'OK') {
        $root = Resolve-GameRoot $dlg.SelectedPath
        if ($root) {
            return $root
        } else {
            [System.Windows.Forms.MessageBox]::Show("所选目录里没有 Aion2\Content\Paks，不是 AION 2 游戏目录。`n`n最简单的办法：Steam 里右键游戏 → 管理 → 浏览本地文件，复制地址栏里的路径，再在本窗口选择它。", "路径不正确 - B站@吃素的佩奇", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            return $null
        }
    }
    return $null
}

# ==================== 智能版本决策与多版本选择窗口 ====================
function Select-TargetGameRoots {
    param([string]$ActionName = "汉化")

    $all = @(Get-AllGameRoots)

    # 场景 0: 全盘未搜到任何版本 -> 弹窗手动选择
    if ($all.Count -eq 0) {
        Write-Host "未能自动定位到游戏安装路径，请在弹出的窗口中手动指定..." -ForegroundColor Yellow
        $manual = Select-GameFolder
        if ($manual) {
            return @($manual)
        }
        return @()
    }

    # 场景 1: 只检测到 1 个版本 -> 直接自动采用，无需用户费神多点一次
    if ($all.Count -eq 1) {
        Write-Host "-> 检测到唯一安装版本: $($all[0].Platform) [$($all[0].Path)]" -ForegroundColor Green
        return @($all[0].Path)
    }

    # 场景 2: 检测到 2 个或以上不同版本 (例如同时存在 Steam 与 PURPLE) -> 弹出交互窗口让用户勾选
    Write-Host ">>> 检测到电脑中安装了多个不同版本的 AION 2 ($($all.Count) 个)，正在弹出选择窗口..." -ForegroundColor Cyan

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "AION 2 游戏版本选择 - B站@吃素的佩奇"
    $formHeight = 310 + ($all.Count * 45)
    $form.Size = New-Object System.Drawing.Size(650, $formHeight)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 28)
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)

    # 顶部横幅
    $banner = New-Object System.Windows.Forms.Panel
    $banner.Dock = 'Top'
    $banner.Height = 70
    $banner.BackColor = [System.Drawing.Color]::FromArgb(35, 35, 45)
    $form.Controls.Add($banner)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "检测到多个游戏版本，请选择要【$ActionName】的目标："
    $title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 12, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(100, 200, 255)
    $title.Location = New-Object System.Drawing.Point(20, 14)
    $title.AutoSize = $true
    $banner.Controls.Add($title)

    $subtitle = New-Object System.Windows.Forms.Label
    $subtitle.Text = "您可以在下方选择其中一个版本，或选择「同时处理全部版本」"
    $subtitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $subtitle.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 190)
    $subtitle.Location = New-Object System.Drawing.Point(22, 42)
    $subtitle.AutoSize = $true
    $banner.Controls.Add($subtitle)

    # 中部列表单选区
    $body = New-Object System.Windows.Forms.Panel
    $body.Dock = 'Fill'
    $body.Padding = New-Object System.Windows.Forms.Padding(25, 15, 25, 10)
    $form.Controls.Add($body)
    $form.Controls.SetChildIndex($body, 0)

    $radioList = @()
    $y = 15

    for ($i = 0; $i -lt $all.Count; $i++) {
        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Text = "$($all[$i].Platform)  |  $($all[$i].Path)"
        $rb.Location = New-Object System.Drawing.Point(25, $y)
        $rb.Size = New-Object System.Drawing.Size(580, 36)
        $rb.ForeColor = [System.Drawing.Color]::FromArgb(235, 235, 240)
        $rb.Tag = @($all[$i].Path)
        if ($i -eq 0) { $rb.Checked = $true } # 默认高亮排在第一顺位的版本
        $body.Controls.Add($rb)
        $radioList += $rb
        $y += 42
    }

    # 选项：同时处理全部版本 (两端均生效)
    $rbAll = New-Object System.Windows.Forms.RadioButton
    $rbAll.Text = "★ 同时${ActionName}以上全部版本 (推荐，两端都享受中文)"
    $rbAll.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
    $rbAll.Location = New-Object System.Drawing.Point(25, $y)
    $rbAll.Size = New-Object System.Drawing.Size(580, 36)
    $rbAll.ForeColor = [System.Drawing.Color]::FromArgb(255, 215, 0)
    $allPaths = @($all | ForEach-Object { $_.Path })
    $rbAll.Tag = $allPaths
    $body.Controls.Add($rbAll)
    $radioList += $rbAll

    # 底部按钮栏
    $btnRow = New-Object System.Windows.Forms.Panel
    $btnRow.Dock = 'Bottom'
    $btnRow.Height = 60
    $btnRow.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 36)
    $form.Controls.Add($btnRow)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "确认执行"
    $btnOk.DialogResult = 'OK'
    $btnOk.BackColor = [System.Drawing.Color]::FromArgb(70, 130, 180)
    $btnOk.ForeColor = [System.Drawing.Color]::White
    $btnOk.FlatStyle = 'Flat'
    $btnOk.Location = New-Object System.Drawing.Point(390, 14)
    $btnOk.Size = New-Object System.Drawing.Size(110, 32)
    $btnRow.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "取消"
    $btnCancel.DialogResult = 'Cancel'
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 70)
    $btnCancel.ForeColor = [System.Drawing.Color]::White
    $btnCancel.FlatStyle = 'Flat'
    $btnCancel.Location = New-Object System.Drawing.Point(515, 14)
    $btnCancel.Size = New-Object System.Drawing.Size(95, 32)
    $btnRow.Controls.Add($btnCancel)

    $form.AcceptButton = $btnOk
    $form.CancelButton = $btnCancel

    $dialogRes = $form.ShowDialog()
    if ($dialogRes -eq 'OK') {
        foreach ($rb in $radioList) {
            if ($rb.Checked) {
                return $rb.Tag
            }
        }
    }

    Write-Host "用户已取消版本选择。" -ForegroundColor Yellow
    return @()
}

# ==================== 专属定制免责声明弹窗 ====================
function Scale-UiTree([System.Windows.Forms.Control]$parent, [double]$s) {
    foreach ($c in $parent.Controls) {
        if ($c.Dock -eq 'Top' -or $c.Dock -eq 'Bottom') {
            $c.Height = [int][Math]::Round($c.Height * $s)
        } elseif ($c.Dock -eq 'Left' -or $c.Dock -eq 'Right') {
            $c.Width = [int][Math]::Round($c.Width * $s)
        } elseif ($c.Dock -eq 'None') {
            $c.Location = New-Object System.Drawing.Point([int][Math]::Round($c.Left * $s), [int][Math]::Round($c.Top * $s))
            $c.Size = New-Object System.Drawing.Size([int][Math]::Round($c.Width * $s), [int][Math]::Round($c.Height * $s))
        }
        $f = $c.Font
        $c.Font = New-Object System.Drawing.Font($f.FontFamily, [single]($f.Size * $s), $f.Style)
        # 按钮文字放大后可能超出原宽度，按需要加宽，避免文字被截断
        if ($c -is [System.Windows.Forms.Button]) {
            $need = $c.PreferredSize.Width + 10
            if ($need -gt $c.Width) { $c.Width = $need }
        }
        # 标签完全交给系统按文字定尺寸，不做任何高度估算，杜绝被裁
        if ($c -is [System.Windows.Forms.Label]) {
            $c.AutoSize = $true
            $c.Padding = New-Object System.Windows.Forms.Padding(0)
        }
        Scale-UiTree $c $s
        # 停靠面板按子控件实际占用增高，确保文字不会超出面板底部
        if (($c.Dock -eq 'Top' -or $c.Dock -eq 'Bottom') -and $c.Controls.Count -gt 0) {
            $need = 0
            foreach ($k in $c.Controls) {
                if (($k.Top + $k.Height) -gt $need) { $need = $k.Top + $k.Height }
            }
            $need = $need + 12
            if ($need -gt $c.Height) { $c.Height = $need }
        }
    }
}

function Show-Disclaimer {
    $form = New-Object System.Windows.Forms.Form
    $form.AutoScaleMode = 'None'
    $form.Text = "AION 2 正式版汉化工具 - 制作: B站@吃素的佩奇"
    $form.Size = New-Object System.Drawing.Size(600, 540)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.BackColor = [System.Drawing.Color]::FromArgb(24,24,28)

    # 顶部横幅
    $banner = New-Object System.Windows.Forms.Panel
    $banner.Dock = 'Top'
    $banner.Height = 84
    $banner.BackColor = [System.Drawing.Color]::FromArgb(35,35,45)
    $form.Controls.Add($banner)

    $icon = New-Object System.Windows.Forms.Label
    $icon.Text = '!'
    $icon.Font = New-Object System.Drawing.Font('Arial', 24, [System.Drawing.FontStyle]::Bold)
    $icon.ForeColor = [System.Drawing.Color]::FromArgb(255,165,0)
    $icon.Location = New-Object System.Drawing.Point(16,12)
    $icon.Size = New-Object System.Drawing.Size(36,40)
    $icon.TextAlign = 'MiddleCenter'
    $banner.Controls.Add($icon)

    $title = New-Object System.Windows.Forms.Label
    $title.Text = '重要操作风险说明'
    $title.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 15, [System.Drawing.FontStyle]::Bold)
    $title.ForeColor = [System.Drawing.Color]::FromArgb(255,165,0)
    $title.Location = New-Object System.Drawing.Point(58,14)
    $title.AutoSize = $true
    $banner.Controls.Add($title)

    $sub = New-Object System.Windows.Forms.Label
    $sub.Text = "即将执行：$($Entries[$Entry].Name) · $LangName"
    $sub.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $sub.ForeColor = [System.Drawing.Color]::FromArgb(180,180,190)
    $sub.Location = New-Object System.Drawing.Point(60,48)
    $sub.AutoSize = $true
    $banner.Controls.Add($sub)

    # 中部说明文字区：只读多行文本框，内容再多也只会出现滚动条，不会被截断
    $body = New-Object System.Windows.Forms.Panel
    $body.Dock = 'Fill'
    $body.BackColor = [System.Drawing.Color]::FromArgb(28,28,34)
    $body.Padding = New-Object System.Windows.Forms.Padding(18,10,18,6)
    $form.Controls.Add($body)
    $form.Controls.SetChildIndex($body, 0)

    # 说明文字：不显示滚动条，用滚轮阅读；读到底部后倒数 3 秒才解锁勾选
    $state = @{ read = $false; unlocked = $false; n = 3 }

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Multiline = $true
    $txt.ReadOnly = $true
    $txt.ScrollBars = 'Vertical'
    $txt.WordWrap = $true
    $txt.Dock = 'Fill'
    $txt.BorderStyle = 'FixedSingle'
    $txt.TabStop = $false
    $txt.BackColor = [System.Drawing.Color]::FromArgb(20,20,26)
    $txt.ForeColor = [System.Drawing.Color]::FromArgb(220,220,225)
    $txt.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
    $txt.Text = "英文入口对应游戏语言 English，日文入口对应 日本語；两个入口互斥，安装时会先移除另一个入口的文件。`r`n`r`n执行汉化安装或还原前，请务必确保已完全退出 永恒之塔2 游戏进程。`r`n`r`n本工具完全免费分享，仅供交流学习，严禁任何形式的倒卖牟利。`r`n`r`n任何对游戏客户端的修改行为均可能存在不可预知的风险（包括但不限于游戏运行异常或账号封禁风险）。请使用者自行评估。"
    $body.Controls.Add($txt)

    $hint = New-Object System.Windows.Forms.Label
    $hint.Text = '↓ 请向下滚动阅读本条说明，读到底部后 3 秒解锁勾选'
    $hint.Dock = 'Bottom'
    $hint.Height = 26
    $hint.TextAlign = 'MiddleLeft'
    $hint.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
    $hint.ForeColor = [System.Drawing.Color]::FromArgb(255,165,0)
    $body.Controls.Add($hint)

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 1000
    $timer.Add_Tick({
        $state.n = $state.n - 1
        if ($state.n -gt 0) {
            $hint.Text = "已阅读到底部，$($state.n) 秒后可勾选…"
        } else {
            $timer.Stop()
            $state.unlocked = $true
            $chk.Enabled = $true
            $hint.Text = '阅读完成，现在可以勾选下方协议。'
            $hint.ForeColor = [System.Drawing.Color]::FromArgb(120,220,140)
        }
    })

    $checkBottom = {
        if ($state.read -or $state.unlocked) { return }
        if ($txt.TextLength -le 0) { return }
        $lastLine = $txt.GetLineFromCharIndex($txt.TextLength - 1)
        $lineStart = $txt.GetFirstCharIndexFromLine($lastLine)
        $idx = $txt.GetCharIndexFromPosition((New-Object System.Drawing.Point(3, ($txt.ClientSize.Height - 3))))
        if ($idx -ge $lineStart) {
            $state.read = $true
            $state.n = 3
            $hint.Text = '已阅读到底部，3 秒后可勾选…'
            $timer.Start()
        }
    }

    $txt.Add_MouseUp({ & $checkBottom })
    # 滚动条已隐藏，自己处理滚轮（每格 2 行）
    $txt.Add_MouseWheel({
        $ev = $args[1]
        if ($ev -is [System.Windows.Forms.HandledMouseEventArgs]) { $ev.Handled = $true }
        if ($ev.Delta -gt 0) { [void][Aion2Win32.Scroll]::SendMessage($txt.Handle, 0x00B6, [IntPtr]::Zero, [IntPtr](-2)) }
        else { [void][Aion2Win32.Scroll]::SendMessage($txt.Handle, 0x00B6, [IntPtr]::Zero, [IntPtr]2) }
        & $checkBottom
    })
    $txt.Add_KeyUp({ & $checkBottom })

    # 兜底轮询：滚轮 / 键盘滚动都会在 300ms 内被检测到
    $poll = New-Object System.Windows.Forms.Timer
    $poll.Interval = 300
    $poll.Add_Tick({ if ($state.unlocked -or $state.read) { $poll.Stop() } else { & $checkBottom } })

    # 底部勾选确认栏
    $checkRow = New-Object System.Windows.Forms.Panel
    $checkRow.Dock = 'Bottom'
    $checkRow.Height = 56
    $checkRow.BackColor = [System.Drawing.Color]::FromArgb(20,20,26)
    $form.Controls.Add($checkRow)

    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = '我已知晓并自愿承担汉化修改可能带来的一切风险'
    $chk.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
    $chk.ForeColor = [System.Drawing.Color]::FromArgb(200,200,205)
    $chk.Location = New-Object System.Drawing.Point(18,16)
    $chk.AutoSize = $true
    $chk.Enabled = $false
    $checkRow.Controls.Add($chk)

    # 按钮栏
    $btnRow = New-Object System.Windows.Forms.Panel
    $btnRow.Dock = 'Bottom'
    $btnRow.Height = 64
    $btnRow.BackColor = [System.Drawing.Color]::FromArgb(32,32,38)
    $form.Controls.Add($btnRow)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = '取消退出'
    $btnCancel.BackColor = [System.Drawing.Color]::FromArgb(55,55,62)
    $btnCancel.ForeColor = [System.Drawing.Color]::FromArgb(200,200,200)
    $btnCancel.FlatStyle = 'Flat'
    $btnCancel.Location = New-Object System.Drawing.Point(20,15)
    $btnCancel.Size = New-Object System.Drawing.Size(100,34)
    $btnRow.Controls.Add($btnCancel)

    $btnBili = New-Object System.Windows.Forms.Button
    $btnBili.Text = '作者B站主页'
    $btnBili.BackColor = [System.Drawing.Color]::FromArgb(45,85,125)
    $btnBili.ForeColor = [System.Drawing.Color]::White
    $btnBili.FlatStyle = 'Flat'
    $btnBili.Location = New-Object System.Drawing.Point(150,15)
    $btnBili.Size = New-Object System.Drawing.Size(110,34)
    $btnBili.Add_Click({ [System.Diagnostics.Process]::Start("https://space.bilibili.com/3379443") })
    $btnRow.Controls.Add($btnBili)

    $btnGo = New-Object System.Windows.Forms.Button
    $btnGo.Text = '已了解，继续'
    $btnGo.BackColor = [System.Drawing.Color]::FromArgb(90,70,200)
    $btnGo.ForeColor = [System.Drawing.Color]::White
    $btnGo.FlatStyle = 'Flat'
    $btnGo.Location = New-Object System.Drawing.Point(410,15)
    $btnGo.Size = New-Object System.Drawing.Size(130,34)
    $btnGo.Enabled = $false
    $btnRow.Controls.Add($btnGo)

    $btnGo.Add_Click({ $form.DialogResult = 'OK'; $form.Close() })
    $btnCancel.Add_Click({ $form.DialogResult = 'Cancel'; $form.Close() })
    $chk.Add_CheckedChanged({ $btnGo.Enabled = $chk.Checked })

    # 按系统 DPI 等比放大，避免 125%/150% 下文字被截断
    $s = 1.0
    try {
        $hdc = [Aion2Win32.Dpi]::GetDC([IntPtr]::Zero)
        $dpi = [Aion2Win32.Dpi]::GetDeviceCaps($hdc, 88)
        [void][Aion2Win32.Dpi]::ReleaseDC([IntPtr]::Zero, $hdc)
        if ($dpi -gt 96) { $s = $dpi / 96.0 }
    } catch { }
    if ($env:AION2_DPI) {
        $v = 0.0
        if ([double]::TryParse($env:AION2_DPI, [ref]$v) -and $v -gt 0.5 -and $v -lt 3) { $s = $v }
    }
    if ($s -ne 1.0) {
        $form.ClientSize = New-Object System.Drawing.Size([int][Math]::Round($form.ClientSize.Width * $s), [int][Math]::Round($form.ClientSize.Height * $s))
    }
    # 即使不缩放也跑一遍，统一把标签改成自适应高度、按子控件撑开面板
    Scale-UiTree $form $s

    # 横幅内文字按实际高度重新排布：标题在下、副标题紧贴标题底部，横幅高度按内容撑开
    $sub.Top = $title.Top + $title.Height + 2
    $needH = $sub.Top + $sub.Height + 12
    if (($icon.Top + $icon.Height + 12) -gt $needH) { $needH = $icon.Top + $icon.Height + 12 }
    if ($needH -gt $banner.Height) { $banner.Height = $needH }

    $form.AcceptButton = $btnGo
    $form.CancelButton = $btnCancel
    $form.Add_Shown({
        # 只读文本框获得焦点时会被系统全选，出现整片高亮，这里主动清掉并移走焦点
        $txt.SelectionLength = 0
        $form.ActiveControl = $btnCancel
        # 有滚动条才能滚轮滚动，但把滚动条隐藏掉
        try { [void][Aion2Win32.Scroll]::ShowScrollBar($txt.Handle, 1, $false) } catch { }
        & $checkBottom
        $poll.Start()
    })
    return $form.ShowDialog()
}

# ==================== 主流程 ====================
Show-Banner


# ==================== 安全文件操作（防只读属性与文件锁） ====================
function Safe-CopyFile($src, $dst) {
    # 全新客户端里没有 Localization 目录，必须先建出来，否则会报“未能找到路径的一部分”
    $dstDir = Split-Path $dst -Parent
    if ($dstDir -and -not (Test-Path $dstDir)) {
        New-Item -ItemType Directory -Path $dstDir -Force | Out-Null
    }
    if (Test-Path $dst) {
        Set-ItemProperty -Path $dst -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
    }
    $tmp = "$dst.new"
    $old = "$dst.old"
    if (Test-Path $tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    Copy-Item $src $tmp -Force
    $srcHash = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
    $tmpHash = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash
    if ($srcHash -ne $tmpHash) {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        throw "文件复制不完整（可能被杀毒软件拦截或磁盘错误）：$dst"
    }
    if (Test-Path $old) { Remove-Item $old -Force -ErrorAction SilentlyContinue }
    if (Test-Path $dst) { Move-Item $dst $old -Force }
    try {
        Move-Item $tmp $dst -Force
    } catch {
        if (Test-Path $old) { Move-Item $old $dst -Force -ErrorAction SilentlyContinue }
        throw "替换文件失败（文件可能被占用）：$dst"
    }
    if (Test-Path $old) { Remove-Item $old -Force -ErrorAction SilentlyContinue }
    return $srcHash
}

function Write-InstallLog($msg) {
    try {
        $log = Join-Path $ToolDir '汉化日志.txt'
        $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "  " + $msg
        Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    } catch { }
}

function Safe-RemoveDirectory($dir) {
    if (Test-Path $dir) {
        Get-ChildItem -Path $dir -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            Set-ItemProperty -Path $_.FullName -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
        }
        Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Stop-ConflictProcesses {
    $names = @('Aion2', 'Aion2-Win64-Shipping', 'NCLauncher', 'NCLauncher2', 'Purple', 'PurpleApp')
    while ($true) {
        $running = @(Get-Process -Name $names -ErrorAction SilentlyContinue)
        if ($running.Count -eq 0) {
            Write-Host "-> 未检测到游戏或启动器进程，继续。" -ForegroundColor Green
            return
        }
        foreach ($p in $running) {
            Write-Host ("-> 正在运行：" + $p.ProcessName) -ForegroundColor Yellow
        }
        $listText = (($running | ForEach-Object { "  " + $_.ProcessName }) -join "`r`n")
        $msg = "检测到游戏或启动器正在运行，文件被占用时无法替换：`r`n`r`n$listText`r`n`r`n请完全退出游戏和启动器后，点击「重试」。"
        $r = [System.Windows.Forms.MessageBox]::Show($msg, "请先退出游戏", [System.Windows.Forms.MessageBoxButtons]::RetryCancel, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($r -ne [System.Windows.Forms.DialogResult]::Retry) {
            Write-Host "用户选择取消，操作已终止。" -ForegroundColor Yellow
            exit 0
        }
    }
}

if ($Install) {
    $res = Show-Disclaimer    if ($res -ne 'OK') {
        Write-Host "用户已取消操作。" -ForegroundColor Yellow
        exit 0
    }

    Check-Update

    Write-Host "[2/6] 检查冲突进程 ............" -ForegroundColor Cyan
    Stop-ConflictProcesses

    Write-Host "[3/6] 扫描客户端 .............." -ForegroundColor Cyan
    $selectedRoots = @(Select-TargetGameRoots -ActionName "安装汉化")
    if ($selectedRoots.Count -eq 0) {
        Write-Host "未选择有效游戏目录，操作已终止。" -ForegroundColor Red
        exit 1
    }

    # 安装前自检：payload\<入口>\<文本>\Engine.locres 必须是完整文件（约 15 MB）
    $srcLocres = Get-PayloadPath $Entry $Lang
    if (-not (Test-Path $srcLocres) -or (Get-Item $srcLocres).Length -lt 1000000) {
        $msg = "安装包不完整，找不到有效的 Engine.locres：`n`n$srcLocres`n`n请重新解压压缩包（不要在压缩软件里直接运行），并检查杀毒软件是否拦截。"
        Write-Host $msg -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show($msg, "安装包不完整", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        exit 1
    }

    Write-Host "[4/6] 读取游戏语言 ............" -ForegroundColor Cyan
    $cultures = @(Get-GameCultures)
    $langMismatch = $false
    if ($cultures.Count -eq 0) {
        Write-Host "-> 未读取到游戏语言配置（游戏可能还没启动过），跳过语言校验。" -ForegroundColor DarkGray
    } else {
        $cText = ($cultures | ForEach-Object { Get-CultureText $_ }) -join ' / '
        Write-Host "-> 游戏当前语言: $cText" -ForegroundColor Cyan
        $matched = $false
        foreach ($c in $cultures) {
            if ($Entries[$Entry].Keys -contains $c.ToLower()) { $matched = $true }
        }
        if (-not $matched) {
            $langMismatch = $true
            Write-Host "-> 注意：所选 $($Entries[$Entry].Name) 与游戏语言不一致。" -ForegroundColor Yellow
            $tip = ("检测到游戏当前语言为「{0}」，但你选择的是「{1}」。`n`n本工具不会修改游戏的语言设置。" +
                    "安装后请先把游戏内语言改为「{2}」并完全退出游戏，汉化才会显示。`n`n是否仍然继续安装？") -f $cText, $Entries[$Entry].Name, $Entries[$Entry].Culture
            $r = [System.Windows.Forms.MessageBox]::Show($tip, '语言与入口不一致', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
            if ($r -ne [System.Windows.Forms.DialogResult]::Yes) {
                Write-Host "用户已取消操作。" -ForegroundColor Yellow
                exit 0
            }
        }
    }

    Write-Host "[5/6] 检测当前汉化状态 ........" -ForegroundColor Cyan
    foreach ($gameRoot in $selectedRoots) {
        $clientState = Get-ClientState $gameRoot
        Write-Host "-> $clientState   [$gameRoot]" -ForegroundColor Cyan
        if ($clientState -eq '目录无效') {
            Write-Host "-> 不是有效的 AION 2 目录，已中止安装。" -ForegroundColor Red
            [System.Windows.Forms.MessageBox]::Show("不是有效的 AION 2 游戏目录：`n$gameRoot`n`n请在 Steam / PURPLE 中校验游戏文件完整性后再安装。", "客户端目录无效", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            exit 1
        }
    }

    Write-Host "[6/6] 部署 $($Entries[$Entry].Name) · $LangName ..." -ForegroundColor Cyan
    $processedCount = 0
    foreach ($gameRoot in $selectedRoots) {
        $processedCount++
        Write-Host ""
        Write-Host "========================================================================" -ForegroundColor DarkCyan
        Write-Host ">>> 正在处理目标游戏目录 [$processedCount/$($selectedRoots.Count)]: $gameRoot" -ForegroundColor Green
        Write-Host "========================================================================" -ForegroundColor DarkCyan

        try {
            $hash = Install-EntryFiles $gameRoot $Entry $Lang
            $liveLocres = Join-Path $gameRoot $Entries[$Entry].LocresRel[0]
            if (-not (Test-Path $liveLocres)) { throw "汉化文件安装后不存在：$liveLocres" }
            if ((Get-Item $liveLocres).Length -ne (Get-Item $srcLocres).Length) { throw "汉化文件安装后大小不一致：$liveLocres" }
            Write-InstallLog "安装 $gameRoot : $($Entries[$Entry].Name) · $LangName  $hash (大小 $((Get-Item $liveLocres).Length))"
            Write-Host "-> 该目录部署完成！" -ForegroundColor Green
        } catch {
            Write-InstallLog "安装失败 $gameRoot : $($_.Exception.Message)"
            $restored = @(Restore-ClientFiles $gameRoot)
            $logPath = Join-Path $ToolDir '汉化日志.txt'
            if ($restored.Count -gt 0) {
                Write-Host "-> 安装失败，已自动清理汉化文件（游戏回落官方原版）。" -ForegroundColor Yellow
                $tip = '已自动清理汉化文件，游戏已回落官方原版，可以直接正常进入游戏。'
            } else {
                Write-Host "-> 安装失败，请在 Steam / PURPLE 校验游戏完整性。" -ForegroundColor Red
                $tip = '请在 Steam / PURPLE 校验游戏完整性后再试。'
            }
            $msg = "汉化没有安装成功。`n`n原因：$($_.Exception.Message)`n`n$tip`n`n日志文件：`n$logPath`n`n请把这个「汉化日志.txt」发给作者。"
            [System.Windows.Forms.MessageBox]::Show($msg, '汉化失败', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            throw
        }
    }

    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Green
    Write-Host ">>> $($Entries[$Entry].Name) · $LangName 部署完成 (共 $processedCount 个客户端)" -ForegroundColor Green
    Write-Host ">>> 游戏未在运行，现在直接启动游戏即可。" -ForegroundColor Yellow
    Write-Host ">>> 想还原：运行「3-窗口版-还原官方.bat」，或图形版点「一键还原」。" -ForegroundColor Yellow
    Write-Host ">>> 制作团队：吃素的佩奇汉化 | 欢迎关注获取最新汉化动态！" -ForegroundColor Magenta
    Write-Host "========================================================================" -ForegroundColor Green
    $doneMsg = "安装完成：$($Entries[$Entry].Name) · $LangName`n共处理 $processedCount 个客户端。`n游戏未在运行，现在直接启动游戏即可。"
    if ($langMismatch) {
        $doneMsg += "`n`n注意：请先把游戏内语言改为「$($Entries[$Entry].Culture)」，否则看不到中文。"
    }
    [System.Windows.Forms.MessageBox]::Show($doneMsg, "安装完成 - 吃素的佩奇汉化", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}
elseif ($Restore) {
    Write-Host "[1/3] 扫描客户端 .............." -ForegroundColor Cyan
    $selectedRoots = @(Select-TargetGameRoots -ActionName "还原官方原版")
    if ($selectedRoots.Count -eq 0) {
        Write-Host "未选择有效游戏目录，操作已终止。" -ForegroundColor Red
        exit 1
    }

    Write-Host "[2/3] 检查冲突进程 ............" -ForegroundColor Cyan
    Stop-ConflictProcesses

    Write-Host "[3/3] 删除汉化文件 ............" -ForegroundColor Cyan
    $processedCount = 0
    $restoredTotal = 0
    foreach ($gameRoot in $selectedRoots) {
        $processedCount++
        Write-Host ""
        Write-Host "========================================================================" -ForegroundColor DarkCyan
        Write-Host ">>> 正在还原目标游戏目录 [$processedCount/$($selectedRoots.Count)]: $gameRoot" -ForegroundColor Green
        Write-Host "========================================================================" -ForegroundColor DarkCyan

        $removed = @(Restore-ClientFiles $gameRoot)
        foreach ($rel in $removed) {
            Write-Host ("[移除] {0}   已删除" -f (Get-ShortRel $rel)) -ForegroundColor DarkYellow
            Write-InstallLog "移除 $gameRoot : $rel"
        }
        if ($removed.Count -gt 0) {
            $restoredTotal++
            Write-Host "-> 已删除汉化文件，该客户端回落为官方原版。" -ForegroundColor Green
        } else {
            Write-Host "-> 没有发现汉化文件，该客户端本来就是官方原版。" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    if ($restoredTotal -gt 0) {
        Write-Host "========================================================================" -ForegroundColor Green
        Write-Host ">>> 已还原为官方原版 (共处理 $restoredTotal 个客户端)！" -ForegroundColor Green
        Write-Host "========================================================================" -ForegroundColor Green
        [System.Windows.Forms.MessageBox]::Show("已还原为官方原版 (共处理 $restoredTotal 个客户端)！`n游戏未在运行，现在直接启动游戏即可。`n`n制作团队：吃素的佩奇汉化", "还原成功", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } else {
        Write-Host "========================================================================" -ForegroundColor Yellow
        Write-Host ">>> 没有发现汉化文件，这些客户端本来就是官方原版。" -ForegroundColor Yellow
        Write-Host "========================================================================" -ForegroundColor Yellow
        [System.Windows.Forms.MessageBox]::Show("没有发现汉化文件，未做任何改动。`n这些客户端本来就是官方原版。", "无需还原", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
}
