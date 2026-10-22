<#
 Compilar-EXE.ps1
 Convierte LTSC-Tuner.ps1 en LTSC-Tuner.exe (doble clic, pide permisos de administrador y abre la ventana).

 Hazlo EN TU LAPTOP (Windows 10, PowerShell 5.1, con internet para bajar el modulo ps2exe):
   1. Pon en la MISMA carpeta: LTSC-Tuner.ps1 y este archivo.
   2. Abre PowerShell como Administrador en esa carpeta y ejecuta:
        powershell -NoProfile -ExecutionPolicy Bypass -File .\Compilar-EXE.ps1
   3. Se crea LTSC-Tuner.exe en la misma carpeta.

 Opciones:
   -Consola   crea una version con consola, para usar -Action Status / Apply / Undo / Clean desde la linea de comandos.

 El .exe lleva el script dentro: si cambias LTSC-Tuner.ps1 tienes que volver a compilar.
 Nota: los .exe hechos con ps2exe a veces los marca el antivirus como falso positivo; si pasa,
 usa Iniciar-LTSC-Tuner.cmd (hace lo mismo sin compilar) o agrega una exclusion para esta carpeta.
#>
param([switch]$Consola)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src  = Join-Path $here 'LTSC-Tuner.ps1'
$out  = Join-Path $here 'LTSC-Tuner.exe'
if ($Consola) { $out = Join-Path $here 'LTSC-Tuner-consola.exe' }

if (-not (Test-Path -Path $src)) { throw "No encuentro $src. Pon LTSC-Tuner.ps1 junto a este archivo." }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host 'Instalando el modulo ps2exe desde PowerShell Gallery...' -ForegroundColor Cyan
    try { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null } catch { }
    Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
}
Import-Module ps2exe

$p = @{
    inputFile    = $src
    outputFile   = $out
    requireAdmin = $true
    x64          = $true
    STA          = $true
    title        = 'LTSC-Tuner'
    product      = 'LTSC-Tuner'
    company      = 'LTSC-Tuner'
    description  = 'Ajustes de rendimiento, privacidad y seguridad para Windows 10 LTSC'
    version      = '6.0.0.0'
}
if (-not $Consola) { $p.noConsole = $true }

# Icono propio: si existe LTSC-Tuner.ico en esta carpeta (o en subcarpeta 'assets'),
# ps2exe lo incrusta en el .exe. Si no existe, se crea uno automatico sencillo
# (cuadro verde con "T") usando GDI+, para que el ejecutable se vea personalizado.
$icoCandidates = @(
    (Join-Path $here 'LTSC-Tuner.ico'),
    (Join-Path $here 'assets\LTSC-Tuner.ico')
)
$iconPath = $icoCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iconPath) {
    $iconPath = Join-Path $here 'LTSC-Tuner.ico'
    Write-Host 'No hay .ico junto al script: generando icono automatico...' -ForegroundColor Cyan
    Add-Type -AssemblyName System.Drawing
    $bmp = New-Object System.Drawing.Bitmap 256, 256
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::FromArgb(16, 163, 127))   # verde Atlas
    $font = New-Object System.Drawing.Font('Segoe UI', 150, [System.Drawing.FontStyle]::Bold)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $rect = New-Object System.Drawing.RectangleF 0, 0, 256, 256
    $g.DrawString('T', $font, [System.Drawing.Brushes]::White, $rect, $sf)
    $g.Dispose()
    # SaveGetHIcon necesita un handle; convertir bitmap a icon y guardarlo como .ico
    $hicon = $bmp.GetHicon()
    $icn = [System.Drawing.Icon]::FromHandle($hicon)
    $fs = [System.IO.File]::Create($iconPath)
    $icn.Save($fs)
    $fs.Close(); $icn.Dispose(); $bmp.Dispose()
    # limpiar el handle
    Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition '[DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);'
    [void][Win32.NativeMethods]::DestroyIcon($hicon)
}
if ($iconPath -and (Test-Path $iconPath)) { $p.icon = $iconPath }

Invoke-ps2exe @p

if (Test-Path -Path $out) { Write-Host ('Listo: ' + $out) -ForegroundColor Green }
else { Write-Host 'No se creo el .exe. Revisa los mensajes anteriores.' -ForegroundColor Red }
