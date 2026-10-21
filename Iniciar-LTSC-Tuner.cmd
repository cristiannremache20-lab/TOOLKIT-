@echo off
rem Abre LTSC-Tuner con doble clic (pide administrador). No hace falta compilar nada.
setlocal
cd /d "%~dp0"
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0LTSC-Tuner.ps1" -Gui
