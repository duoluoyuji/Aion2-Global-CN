# 编译与打包脚本
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File build\build.ps1
#
# 前置：
#   1. 系统自带 .NET Framework 编译器（Windows 自带，无需安装 SDK）
#   2. 四份载荷已生成（英文入口 / 日文入口 × 简中 / 繁中）
#      生成方法见 docs\交接文档.md 第 4 节

$ErrorActionPreference = 'Stop'

$Root    = Split-Path $PSScriptRoot -Parent
$Base    = Split-Path $Root -Parent          # 1_文本汉化包
$Version = '0.0.1'
$OutName = "永恒之塔2_国际服简繁汉化_v$Version"
$Dist    = Join-Path $Root "dist\$OutName"
$Csc     = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'

# 四份载荷
$PayEnCn = Join-Path $Base '_work_en\out\locres_zh_CN\en\Engine.locres'
$PayEnTw = Join-Path $Base '_work_en\out\locres_zh_TW\en\Engine.locres'
$PayJaCn = Join-Path $Base '_内部工具\_out_entry\ja\zh\Engine.locres'
$PayJaTw = Join-Path $Base '_内部工具\_out_entry\ja\zh-TW\Engine.locres'

Write-Host "[1/5] 检查依赖" -ForegroundColor Cyan
if (-not (Test-Path $Csc)) { throw "找不到 csc.exe: $Csc" }
foreach ($p in @($PayEnCn, $PayEnTw, $PayJaCn, $PayJaTw)) {
    if (-not (Test-Path $p)) { throw "缺少载荷: $p" }
}

Write-Host "[2/5] 准备输出目录" -ForegroundColor Cyan
if (Test-Path $Dist) { Remove-Item $Dist -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Dist | Out-Null
foreach ($d in @("payload\en\zh", "payload\en\zh-TW", "payload\ja\zh", "payload\ja\zh-TW")) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Dist $d) | Out-Null
}

Write-Host "[3/5] 编译图形版" -ForegroundColor Cyan
& $Csc /nologo /target:winexe /optimize `
    /r:System.Windows.Forms.dll /r:System.Drawing.dll `
    "/win32manifest:$(Join-Path $Root 'src\app.manifest')" `
    "/out:$Dist\1-图形版-双击启动.exe" (Join-Path $Root 'src\Aion2CNTool.cs')
if ($LASTEXITCODE -ne 0) { throw "csc 编译失败: $LASTEXITCODE" }

Write-Host "[4/5] 复制脚本与载荷" -ForegroundColor Cyan
Copy-Item (Join-Path $Root 'src\Aion2CNTool.ps1') $Dist -Force
Copy-Item (Join-Path $Root 'src\Aion2Diag.ps1')   $Dist -Force
Copy-Item (Join-Path $Root 'src\bat\*.bat')       $Dist -Force
Copy-Item (Join-Path $Root 'docs\0-使用说明（先看这里）.txt') $Dist -Force
Copy-Item $PayEnCn (Join-Path $Dist 'payload\en\zh\Engine.locres')    -Force
Copy-Item $PayEnTw (Join-Path $Dist 'payload\en\zh-TW\Engine.locres') -Force
Copy-Item $PayJaCn (Join-Path $Dist 'payload\ja\zh\Engine.locres')    -Force
Copy-Item $PayJaTw (Join-Path $Dist 'payload\ja\zh-TW\Engine.locres') -Force

Write-Host "[5/5] 打包" -ForegroundColor Cyan
$zip = Join-Path $Root "dist\$OutName.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $Dist '*') -DestinationPath $zip -CompressionLevel Optimal

$h = (Get-FileHash $zip -Algorithm SHA256).Hash
Write-Host ""
Write-Host "完成: $zip" -ForegroundColor Green
Write-Host "大小: $((Get-Item $zip).Length) B" -ForegroundColor Green
Write-Host "SHA256: $h" -ForegroundColor Green
Write-Host "上传此 zip 作为 Release 资产即可。" -ForegroundColor Gray
