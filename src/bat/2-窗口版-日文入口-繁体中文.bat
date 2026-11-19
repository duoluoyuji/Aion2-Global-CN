@echo off
chcp 936 >nul 2>&1
setlocal
cd /d "%~dp0"
title AION 2 简繁汉化 - 日文入口 · 繁体中文

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Aion2CNTool.ps1" -Install -Entry "ja" -Lang "zh-TW"
if %errorlevel% neq 0 (
    echo.
    echo 执行过程出现错误，代码: %errorlevel%
)
pause
