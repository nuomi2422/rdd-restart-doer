@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "E:\restart developing doer\rdd-selfcompile\scripts\presence-watchdog.ps1" -Loop -IntervalSeconds 60 -StaleMinutes 10
