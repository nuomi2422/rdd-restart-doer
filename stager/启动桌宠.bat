@echo off
chcp 65001 >nul
title STAGER Desktop Pet
setlocal

REM ============================================================
REM  Start the desktop pet.  Kept for muscle memory only -- the
REM  fuller launcher lives at:
REM     rdd-selfcompile\stager-pet.bat
REM  which reports "already running" instead of spawning a second
REM  pet, and has a matching stop-stager-pet.bat.
REM
REM  ASCII-only on purpose - see stager.bat for why.
REM ============================================================

set "SLEEVE=D:\rdd\workspace\stager\pet\pet-launch.ps1"

if exist "%SLEEVE%" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SLEEVE%"
  exit /b %ERRORLEVEL%
)

REM Fallback for a stager checkout without pet-launch.ps1.
echo pet-launch.ps1 missing, falling back to the direct call...
start "" /min powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0pet\start-pet.ps1" -Size 200
exit /b 0
