@echo off
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "D:\rdd\workspace\rdd-selfcompile\scripts\presence-watchdog.ps1" -Loop -IntervalSeconds 60 -StaleMinutes 120
