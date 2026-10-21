<#
 LTSC-Tuner.ps1  (v5.0)
 Ajustes de rendimiento, privacidad y seguridad para Windows 10 LTSC (2019 build 17763
 o 2021 build 19044 / IoT). Pensado para Dell Latitude E5550 (i3-5010U, 12 GB RAM, SSD)
 que se usa CASI SIEMPRE CONECTADA a corriente.

 Inspirado en las ideas publicas de AtlasOS (GPLv3). Codigo propio, sin binarios externos.

 NOVEDADES v5.0 (los IDs de versiones anteriores NO cambian: tu state.json y tu Undo siguen valiendo):
   - MODO MAXIMO (-Max o boton en la ventana): recomendados + todo lo agresivo para que vuele
   - CPU idle (C-states) desactivado SOLO con corriente; con bateria sigue normal
   - SmartScreen desactivado (sistema, Explorador, IE/Edge, apps) y sin aviso de archivos descargados
   - Efectos visuales al minimo, prefetch off, compresion de memoria off, mas servicios y tareas fuera
   - Administrador de programas de inicio (boton Inicio / -Action Startup), reversible
   - Se puede compilar a .exe de doble clic (ver Compilar-EXE.ps1)

 NOVEDADES v4.0:
   - Detecta si estas conectada a corriente o con bateria y muestra la salud de la bateria
   - Plan de energia propio "LTSC-Tuner AC-DC": maximo rendimiento SOLO con corriente y
     valores moderados con bateria (Windows cambia solo segun la fuente, sin programas extra)
   - Adaptadores de red sin ahorro de energia (menos cortes de Wi-Fi)
   - Accion -Action Clean: limpia temporales, cache de Windows Update y componentes
   - Acepta Windows 10 LTSC 2019 (17763) y LTSC 2021 / IoT (19044)
   - Nuevos opcionales: tick dinamico off, kernel en RAM, menu contextual limpio

 NO desactiva: Windows Defender, Windows Update, Firewall, UAC,
               mitigaciones de CPU, Core Isolation, Secure Boot.
 (Solo REFUERZA Defender: activa la proteccion contra apps no deseadas / mineros.)
 SI desactiva (solo en MODO MAXIMO): SmartScreen y CPU idle con corriente.
 NO toca: timer resolution forzado, Bluetooth.

 Todo es reversible. Antes de cambiar algo guarda:
   C:\ProgramData\LTSC-Tuner\state.json      (valores originales, usado por Undo)
   C:\ProgramData\LTSC-Tuner\backup-FECHA\   (copias .reg de las claves tocadas)
   C:\ProgramData\LTSC-Tuner\tuner.log       (registro de lo hecho)

 USO: GUARDA este texto como LTSC-Tuner.ps1 y ejecutalo con -File.
      NO lo pegues en la consola: PowerShell corta los bloques en las lineas en blanco.
 (PowerShell como Administrador):
   powershell -NoProfile -ExecutionPolicy Bypass -File .\LTSC-Tuner.ps1 -Gui
        -> ventana con casillas (se eleva sola a administrador)
   powershell -NoProfile -ExecutionPolicy Bypass -File .\LTSC-Tuner.ps1
        -> Status: muestra que esta aplicado y que no, y el estado de la bateria. NO cambia nada.
   ... -Action Apply                      aplica los ajustes recomendados
   ... -Action Apply -IncludeOptional     aplica tambien los opcionales
   ... -Action Apply -Only svc-sysmain,visual-effects
   ... -Action Undo                       revierte todo lo aplicado
   ... -Action Clean                      limpia temporales y cache de actualizaciones
   ... -Action Apply -Max                 recomendados + MODO MAXIMO (rendimiento extremo)
   ... -Action Startup                    lista programas de inicio (con -Only "Nombre" los desactiva; -Enable los reactiva)
   ... -Yes                 no pide confirmacion
   ... -NoRestorePoint      no intenta crear punto de restauracion
   ... -ForceUserTweaks     aplica ajustes de usuario aunque la ventana de
                            administrador sea de otra cuenta (normalmente NO usar)

 Nota: los ajustes de categoria "Usuario" afectan al usuario que ejecuta el script.
 Cierra sesion y vuelve a entrar (o reinicia) para ver todos los cambios.
#>
[CmdletBinding()]
param(
    [ValidateSet('Status', 'Apply', 'Undo', 'Clean', 'Startup')]
    [string]$Action = 'Status',
    [switch]$Gui,
    [switch]$IncludeOptional,
    [switch]$Max,
    [switch]$Enable,
    [string[]]$Only,
    [switch]$Yes,
    [switch]$NoRestorePoint,
    [switch]$ForceUserTweaks
)

$ErrorActionPreference = 'Stop'
$ToolVersion = '5.0'

# ----------------------------------------------------------------------------
# Rutas, registro (log) y estado
# ----------------------------------------------------------------------------
$Root      = Join-Path $env:ProgramData 'LTSC-Tuner'
$StateFile = Join-Path $Root 'state.json'
$LogFile   = Join-Path $Root 'tuner.log'
if (-not (Test-Path -Path $Root)) { New-Item -ItemType Directory -Path $Root -Force | Out-Null }

$script:GuiLog = $null

# Si esto corre como .exe (ps2exe) sin argumentos, abre la ventana directamente.
$ProcName = ''
try { $ProcName = [Diagnostics.Process]::GetCurrentProcess().ProcessName } catch { }
$IsExe = ($ProcName -ne '') -and ($ProcName -notmatch '^(powershell|pwsh|powershell_ise)$')
if ($IsExe -and ($PSBoundParameters.Count -eq 0)) { $Gui = $true }
$script:Quiet = [bool]$Gui

function Write-Log {
    param([string]$Message, [string]$Color = 'Gray')
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -Path $LogFile -Value $line } catch { }
    if (-not $script:Quiet) { Write-Host $Message -ForegroundColor $Color }
    if ($script:GuiLog) {
        try { $script:GuiLog.AppendText($Message + "`r`n") } catch { }
    }
}

function Load-State {
    $h = @{}
    if (Test-Path -Path $StateFile) {
        $raw = Get-Content -Path $StateFile -Raw
        if ($raw -and $raw.Trim().Length -gt 0) {
            $obj = $raw | ConvertFrom-Json
            foreach ($p in $obj.PSObject.Properties) { $h[$p.Name] = $p.Value }
        }
    }
    return $h
}

function Save-State {
    param($h)
    $h | ConvertTo-Json -Depth 8 | Set-Content -Path $StateFile -Encoding UTF8
}

# ----------------------------------------------------------------------------
# Comprobaciones previas
# ----------------------------------------------------------------------------
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin  = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and $Action -ne 'Status' -and -not $Gui) {
    throw 'Ejecuta PowerShell como Administrador (clic derecho > Ejecutar como administrador).'
}

# Si la ventana de administrador es de otra cuenta distinta a la que esta usando
# el equipo, HKCU apuntaria al usuario equivocado.
function Test-UserContext {
    try {
        $console = (Get-CimInstance Win32_ComputerSystem).UserName
        if ($console -and ($console -ne $identity.Name)) { return $false }
    } catch { }
    return $true
}
$UserCtxOk = Test-UserContext

$SysLabel = 'Windows'
try {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int]$cv.CurrentBuild
    $SysLabel = '{0} (build {1})' -f $cv.ProductName, $build
    Write-Log ('Sistema: {0}, EditionID {1}' -f $SysLabel, $cv.EditionID) 'DarkCyan'
    $knownBuilds = @(17763, 19041, 19042, 19043, 19044, 19045)
    if ($knownBuilds -notcontains $build) {
        Write-Log ('AVISO: build {0}. El script esta probado para Windows 10 LTSC 2019 (17763) y LTSC 2021 (19044). Algunos ajustes pueden no aplicar.' -f $build) 'Yellow'
    }
    if ($cv.EditionID -notmatch 'EnterpriseS|IoTEnterpriseS') {
        Write-Log 'AVISO: la edicion no parece LTSC/IoT LTSC. Revisa que sea el sistema correcto antes de aplicar.' 'Yellow'
    }
} catch { }

if (-not $UserCtxOk) {
    Write-Log 'AVISO: esta ventana de administrador es de una cuenta distinta a la del usuario activo. Los ajustes de categoria Usuario se omitiran (usa -ForceUserTweaks bajo tu responsabilidad).' 'Yellow'
}

# ----------------------------------------------------------------------------
# Energia: fuente de poder y salud de la bateria
# ----------------------------------------------------------------------------
function Get-PowerInfo {
    $r = [pscustomobject]@{ HasBattery = $false; OnAC = $true; Charge = $null; Health = $null }
    $bat = @()
    try { $bat = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop) } catch { }
    if ($bat.Count -eq 0) { return $r }
    $r.HasBattery = $true
    $r.Charge = $bat[0].EstimatedChargeRemaining
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $r.OnAC = ([string][System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -eq 'Online')
    } catch {
        $st = [int]$bat[0].BatteryStatus
        $r.OnAC = ($st -ne 1)
    }
    try {
        $full = (Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1).FullChargedCapacity
        $des  = (Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryStaticData -ErrorAction Stop | Select-Object -First 1).DesignedCapacity
        if ($des -gt 0 -and $full -gt 0) { $r.Health = [int][math]::Round(100.0 * $full / $des, 0) }
    } catch { }
    return $r
}

function Write-PowerInfo {
    $p = Get-PowerInfo
    if (-not $p.HasBattery) {
        Write-Log 'Energia: no se detecta bateria (equipo conectado o bateria retirada).' 'DarkCyan'
        return $p
    }
    $src = 'CON BATERIA (descargando)'
    if ($p.OnAC) { $src = 'CONECTADA a corriente' }
    $txt = 'Energia: {0} | carga {1}%' -f $src, $p.Charge
    if ($null -ne $p.Health) { $txt += (' | salud de la bateria {0}% (capacidad actual / de diseno)' -f $p.Health) }
    Write-Log $txt 'DarkCyan'
    if ($null -ne $p.Health -and $p.Health -lt 60) {
        Write-Log 'AVISO: la bateria esta muy desgastada (<60%). Considera cambiarla; ningun ajuste de software la recupera.' 'Yellow'
    }
    return $p
}

# ----------------------------------------------------------------------------
# Utilidades de registro
# ----------------------------------------------------------------------------
function Get-RegState {
    param([string]$Path, [string]$Name)
    $r = @{ Exists = $false; Value = $null; Kind = $null }
    try {
        $k = Get-Item -Path $Path -ErrorAction Stop
        if ($k.GetValueNames() -contains $Name) {
            $r.Exists = $true
            $r.Value  = $k.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $r.Kind   = $k.GetValueKind($Name).ToString()
        }
    } catch { }
    return $r
}

function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Kind)
    if (-not (Test-Path -Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    if ($Kind -eq 'DWord') { $Value = [int]$Value }
    if ($Kind -eq 'Binary') { $Value = [byte[]]$Value }
    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Kind -Force | Out-Null
}

function ConvertTo-CmpString {
    param($v)
    if ($v -is [array]) { return (($v | ForEach-Object { [string]$_ }) -join ',') }
    return [string]$v
}

function Remove-Reg {
    param([string]$Path, [string]$Name)
    Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
}

# ----------------------------------------------------------------------------
# Utilidades de servicios y tareas
# ----------------------------------------------------------------------------
function Get-SvcState {
    param([string]$Name)
    $p = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    if (-not (Test-Path -Path $p)) { return $null }
    $k = Get-Item -Path $p
    return @{ Start = $k.GetValue('Start', $null); Delayed = $k.GetValue('DelayedAutostart', $null) }
}

function Get-TaskObj {
    param([string]$Spec)
    $parts = $Spec.Split('|')
    return (Get-ScheduledTask -TaskPath $parts[0] -TaskName $parts[1] -ErrorAction SilentlyContinue)
}

# ----------------------------------------------------------------------------
# Utilidades de planes de energia (powercfg)
# ----------------------------------------------------------------------------
$PlanName   = 'LTSC-Tuner AC-DC'
$GuidRegex  = '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'
$PlanHigh   = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$PlanBal    = '381b4222-f694-41f0-9685-3693f8dc9163'

function Get-PlanGuid {
    param([string]$Name)
    $o = (cmd /c "powercfg /list 2>nul") | Out-String
    foreach ($line in ($o -split "`r?`n")) {
        if ($line -match '([0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})\s+\((.+?)\)') {
            if ($Matches[3] -eq $Name) { return $Matches[1] }
        }
    }
    return $null
}

function Get-ActivePlanGuid {
    $o = (cmd /c "powercfg /getactivescheme 2>nul") | Out-String
    $m = [regex]::Match($o, $GuidRegex)
    if ($m.Success) { return $m.Value }
    return $null
}

function Set-PlanValue {
    param([string]$Plan, [string]$Sub, [string]$Setting, $Ac, $Dc)
    if ($null -ne $Ac) { cmd /c ('powercfg /setacvalueindex {0} {1} {2} {3} >nul 2>&1' -f $Plan, $Sub, $Setting, $Ac) }
    if ($null -ne $Dc) { cmd /c ('powercfg /setdcvalueindex {0} {1} {2} {3} >nul 2>&1' -f $Plan, $Sub, $Setting, $Dc) }
}

function Ensure-Plan {
    $g = Get-PlanGuid $PlanName
    if ($g) { return $g }
    $o = (cmd /c ('powercfg /duplicatescheme {0} 2>nul' -f $PlanHigh)) | Out-String
    $m = [regex]::Match($o, $GuidRegex)
    if (-not $m.Success) {
        $o = (cmd /c ('powercfg /duplicatescheme {0} 2>nul' -f $PlanBal)) | Out-String
        $m = [regex]::Match($o, $GuidRegex)
    }
    if (-not $m.Success) { throw 'No se pudo crear el plan de energia propio.' }
    cmd /c ('powercfg /changename {0} "{1}" "Creado por LTSC-Tuner" >nul 2>&1' -f $m.Value, $PlanName)
    return $m.Value
}

function Get-PlanIdleDisable {
    param([string]$Plan)
    $o = (cmd /c ('powercfg /query {0} 54533251-82be-4824-96c1-47b60b740d00 5d76a2ca-e8c0-402f-a133-2158492d58ad 2>nul' -f $Plan)) | Out-String
    $h = [regex]::Matches($o, '0x[0-9a-fA-F]{8}')
    if ($h.Count -lt 2) { return $null }
    return @{
        Ac = [Convert]::ToInt32($h[$h.Count - 2].Value.Substring(2), 16)
        Dc = [Convert]::ToInt32($h[$h.Count - 1].Value.Substring(2), 16)
    }
}

# ----------------------------------------------------------------------------
# Catalogo de ajustes
# ----------------------------------------------------------------------------
$Tweaks = New-Object System.Collections.ArrayList

function New-Entry {
    param([string]$Path, [string]$Name, $Value, [string]$Kind = 'DWord')
    return @{ Path = $Path; Name = $Name; Value = $Value; Kind = $Kind }
}

function Add-Reg {
    param([string]$Id, [string]$Cat, [string]$Risk, [string]$Desc, $Entries, [bool]$Optional = $false)
    $uses = $false
    foreach ($e in @($Entries)) { if ($e.Path -like 'HKCU:*') { $uses = $true } }
    [void]$Tweaks.Add([pscustomobject]@{
        Id = $Id; Type = 'Reg'; Cat = $Cat; Risk = $Risk; Desc = $Desc; Optional = $Optional
        Entries = @($Entries); UsesHkcu = $uses
    })
}

function Add-Svc {
    param([string]$Id, [string]$Cat, [string]$Risk, [string]$Desc, [string[]]$Names, [string]$Target = 'Disabled', [bool]$Optional = $false)
    $startValue = 4
    if ($Target -eq 'Manual') { $startValue = 3 }
    [void]$Tweaks.Add([pscustomobject]@{
        Id = $Id; Type = 'Svc'; Cat = $Cat; Risk = $Risk; Desc = $Desc; Optional = $Optional
        Names = $Names; StartName = $Target; StartValue = $startValue; UsesHkcu = $false
    })
}

function Add-Task {
    param([string]$Id, [string]$Cat, [string]$Risk, [string]$Desc, [string[]]$Tasks, [bool]$Optional = $false)
    [void]$Tweaks.Add([pscustomobject]@{
        Id = $Id; Type = 'Task'; Cat = $Cat; Risk = $Risk; Desc = $Desc; Optional = $Optional
        Tasks = $Tasks; UsesHkcu = $false
    })
}

function Add-Custom {
    param([string]$Id, [string]$Cat, [string]$Risk, [string]$Desc, [scriptblock]$Test, [scriptblock]$Capture, [scriptblock]$Apply, [scriptblock]$Restore, [bool]$Optional = $false)
    [void]$Tweaks.Add([pscustomobject]@{
        Id = $Id; Type = 'Custom'; Cat = $Cat; Risk = $Risk; Desc = $Desc; Optional = $Optional
        Test = $Test; Capture = $Capture; Apply = $Apply; Restore = $Restore; UsesHkcu = $false
    })
}

$POL = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows'
$DEF = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender'
$CDM = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$ADV = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

# ============================================================================
#  A) AJUSTES DE LA v2.0 (IDs sin cambios, para no romper state.json / Undo)
# ============================================================================

# ---- Privacidad / telemetria (maquina) ----
Add-Reg 'telemetria-politica' 'Privacidad' 'Bajo' 'Telemetria al minimo (nivel Security) y sin avisos de feedback' @(
    (New-Entry "$POL\DataCollection" 'AllowTelemetry' 0),
    (New-Entry "$POL\DataCollection" 'DoNotShowFeedbackNotifications' 1)
)
Add-Reg 'ceip-inventario' 'Privacidad' 'Bajo' 'Desactiva CEIP, telemetria de aplicaciones e inventario' @(
    (New-Entry 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0),
    (New-Entry "$POL\AppCompat" 'AITEnable' 0),
    (New-Entry "$POL\AppCompat" 'DisableInventory' 1)
)
Add-Reg 'id-publicidad' 'Privacidad' 'Bajo' 'Desactiva el ID de publicidad' @(
    (New-Entry "$POL\AdvertisingInfo" 'DisabledByGroupPolicy' 1)
)
Add-Reg 'historial-actividad' 'Privacidad' 'Bajo' 'Desactiva el historial de actividad (Timeline)' @(
    (New-Entry "$POL\System" 'EnableActivityFeed' 0),
    (New-Entry "$POL\System" 'PublishUserActivities' 0),
    (New-Entry "$POL\System" 'UploadUserActivities' 0)
)
Add-Reg 'reporte-errores' 'Privacidad' 'Bajo' 'Desactiva el envio de reportes de error a Microsoft' @(
    (New-Entry "$POL\Windows Error Reporting" 'Disabled' 1)
)
Add-Reg 'sugerencias-maquina' 'Privacidad' 'Bajo' 'Sin funciones de consumidor, Spotlight ni sugerencias' @(
    (New-Entry "$POL\CloudContent" 'DisableWindowsConsumerFeatures' 1),
    (New-Entry "$POL\CloudContent" 'DisableWindowsSpotlightFeatures' 1),
    (New-Entry "$POL\CloudContent" 'DisableSoftLanding' 1)
)
Add-Reg 'busqueda-web' 'Privacidad' 'Bajo' 'El menu Inicio no busca en internet ni usa Cortana' @(
    (New-Entry "$POL\Windows Search" 'DisableWebSearch' 1),
    (New-Entry "$POL\Windows Search" 'ConnectedSearchUseWeb' 0),
    (New-Entry "$POL\Windows Search" 'AllowCortana' 0)
)
Add-Reg 'onedrive-politica' 'Privacidad' 'Bajo' 'Desactiva la sincronizacion de OneDrive (no lo desinstala)' @(
    (New-Entry "$POL\OneDrive" 'DisableFileSyncNGSC' 1)
)
Add-Reg 'delivery-optimization' 'Rendimiento' 'Bajo' 'Las actualizaciones no se comparten con otros PCs (solo HTTP)' @(
    (New-Entry "$POL\DeliveryOptimization" 'DODownloadMode' 0)
)
Add-Reg 'game-dvr' 'Rendimiento' 'Bajo' 'Desactiva Game DVR / grabacion en segundo plano' @(
    (New-Entry "$POL\GameDVR" 'AllowGameDVR' 0),
    (New-Entry 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0)
)

# ---- Seguridad (refuerzos; no desactivan nada) ----
Add-Reg 'defender-pua' 'Seguridad' 'Bajo' 'Defender bloquea apps no deseadas (mineros, adware). Refuerza, no debilita' @(
    (New-Entry "$DEF" 'PUAProtection' 1)
)
Add-Reg 'autorun-off' 'Seguridad' 'Bajo' 'Desactiva AutoRun/AutoPlay en unidades (USB) contra infecciones' @(
    (New-Entry 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun' 255),
    (New-Entry 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoAutorun' 1)
)
Add-Reg 'smb1-off' 'Seguridad' 'Bajo' 'Desactiva SMBv1 en el servidor (protocolo antiguo e inseguro)' @(
    (New-Entry 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'SMB1' 0)
)
Add-Reg 'asistencia-remota-off' 'Seguridad' 'Bajo' 'Desactiva la Asistencia remota de Windows' @(
    (New-Entry 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0),
    (New-Entry 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowFullControl' 0)
)

# ---- Usuario ----
Add-Reg 'sugerencias-usuario' 'Usuario' 'Bajo' 'Sin apps sugeridas, anuncios ni contenido promocionado en Inicio' @(
    (New-Entry $CDM 'SilentInstalledAppsEnabled' 0),
    (New-Entry $CDM 'SystemPaneSuggestionsEnabled' 0),
    (New-Entry $CDM 'SoftLandingEnabled' 0),
    (New-Entry $CDM 'OemPreInstalledAppsEnabled' 0),
    (New-Entry $CDM 'PreInstalledAppsEnabled' 0),
    (New-Entry $CDM 'ContentDeliveryAllowed' 0),
    (New-Entry $CDM 'SubscribedContent-338388Enabled' 0),
    (New-Entry $CDM 'SubscribedContent-338389Enabled' 0),
    (New-Entry $CDM 'SubscribedContent-353694Enabled' 0),
    (New-Entry $CDM 'SubscribedContent-353696Enabled' 0)
)
Add-Reg 'visual-effects' 'Usuario' 'Bajo' 'Sin transparencia ni animaciones (alivia la HD Graphics 5500)' @(
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0),
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0),
    (New-Entry 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '100' 'String'),
    (New-Entry 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String')
)
Add-Reg 'explorer-seguro' 'Usuario' 'Bajo' 'Muestra extensiones de archivo (detecta malware) y abre en Este equipo' @(
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' 0),
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'LaunchTo' 1)
)

# ---- Servicios ----
Add-Svc 'svc-telemetria' 'Servicios' 'Bajo' 'Desactiva DiagTrack y dmwappushservice (telemetria)' @('DiagTrack', 'dmwappushservice')
Add-Svc 'svc-mapas' 'Servicios' 'Bajo' 'Desactiva Mapas descargados (MapsBroker)' @('MapsBroker')
Add-Svc 'svc-xbox' 'Servicios' 'Bajo' 'Desactiva servicios de Xbox (si existen en la imagen)' @('XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc')
Add-Svc 'svc-retaildemo' 'Servicios' 'Bajo' 'Desactiva el servicio de demo de tienda' @('RetailDemo')
Add-Svc 'svc-sysmain' 'Rendimiento' 'Bajo' 'Desactiva SysMain (Superfetch): innecesario con SSD' @('SysMain')

# ---- Tareas programadas de telemetria ----
Add-Task 'tareas-telemetria' 'Privacidad' 'Bajo' 'Desactiva tareas de telemetria (Appraiser, CEIP, feedback)' @(
    '\Microsoft\Windows\Application Experience\|Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\|ProgramDataUpdater',
    '\Microsoft\Windows\Customer Experience Improvement Program\|Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\|UsbCeip',
    '\Microsoft\Windows\Customer Experience Improvement Program\|KernelCeipTask',
    '\Microsoft\Windows\Feedback\Siuf\|DmClient',
    '\Microsoft\Windows\Feedback\Siuf\|DmClientOnScenarioDownload',
    '\Microsoft\Windows\Windows Error Reporting\|QueueReporting'
)

# ---- OPCIONALES v2.0 ----
Add-Svc 'svc-busqueda' 'Servicios' 'Medio' 'OPCIONAL: desactiva el indexado de busqueda (WSearch); la busqueda sera mas lenta' @('WSearch') 'Disabled' $true
Add-Svc 'svc-impresion' 'Servicios' 'Medio' 'OPCIONAL: desactiva el servicio de impresion (Spooler). No imprimiras' @('Spooler') 'Disabled' $true
Add-Reg 'segundo-plano' 'Rendimiento' 'Medio' 'OPCIONAL: las apps UWP no corren en segundo plano' @(
    (New-Entry "$POL\AppPrivacy" 'LetAppsRunInBackground' 2)
) $true
Add-Reg 'inicio-rapido-off' 'Rendimiento' 'Bajo' 'OPCIONAL: desactiva el inicio rapido (apagados completos, menos problemas de drivers)' @(
    (New-Entry 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0)
) $true
Add-Reg 'sin-drivers-wu' 'Rendimiento' 'Medio' 'OPCIONAL: Windows Update no instala drivers (usa los de Dell)' @(
    (New-Entry "$POL\WindowsUpdate" 'ExcludeWUDriversInQualityUpdate' 1)
) $true
Add-Reg 'llmnr-off' 'Seguridad' 'Medio' 'OPCIONAL: desactiva LLMNR (resolucion de nombres local; puede afectar redes caseras)' @(
    (New-Entry 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast' 0)
) $true

Add-Custom 'hibernacion-off' 'Rendimiento' 'Medio' 'OPCIONAL: desactiva hibernacion (libera ~5 GB, pierdes hibernar)' `
    { (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power').HibernateEnabled -eq 0 } `
    { [string](Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power').HibernateEnabled } `
    { cmd /c "powercfg /h off >nul 2>&1" } `
    { param($data) if ($data -eq '1') { cmd /c "powercfg /h on >nul 2>&1" } } `
    $true

Add-Custom 'plan-alto-rendimiento' 'Rendimiento' 'Medio' 'OPCIONAL: plan Alto rendimiento fijo (si usas energia-ac-dc ya no hace falta)' `
    {
        $o = (cmd /c "powercfg /getactivescheme 2>nul") | Out-String
        $o -match '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    } `
    {
        $o = (cmd /c "powercfg /getactivescheme 2>nul") | Out-String
        $m = [regex]::Match($o, '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}')
        if ($m.Success) { $m.Value } else { '' }
    } `
    {
        $g = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        cmd /c "powercfg /setactive $g >nul 2>&1"
        if ($LASTEXITCODE -ne 0) {
            $o = (cmd /c "powercfg /duplicatescheme $g 2>nul") | Out-String
            $m = [regex]::Match($o, '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}')
            if ($m.Success) { cmd /c ("powercfg /setactive " + $m.Value + " >nul 2>&1") }
        }
    } `
    {
        param($data)
        if ($data) { cmd /c ("powercfg /setactive " + $data + " >nul 2>&1") }
    } `
    $true

# ============================================================================
#  B) AJUSTES DE LA v3.0 (IDs sin cambios)
# ============================================================================

Add-Reg 'telemetria-extra' 'Privacidad' 'Bajo' 'Menos registros de diagnostico, sin nombre de equipo en telemetria ni descargas OneSettings' @(
    (New-Entry "$POL\DataCollection" 'LimitDiagnosticLogCollection' 1),
    (New-Entry "$POL\DataCollection" 'DisableOneSettingsDownloads' 1),
    (New-Entry "$POL\DataCollection" 'AllowDeviceNameInTelemetry' 0),
    (New-Entry "$POL\DataCollection" 'DisableTelemetryOptInChangeNotification' 1),
    (New-Entry "$POL\DataCollection" 'LimitEnhancedDiagnosticDataWindowsAnalytics' 1)
)
Add-Reg 'mrt-informes' 'Privacidad' 'Bajo' 'La herramienta de eliminacion de malware (MRT) no envia informes a Microsoft' @(
    (New-Entry 'HKLM:\SOFTWARE\Policies\Microsoft\MRT' 'DontReportInfectionInformation' 1)
)
Add-Reg 'privacidad-extra' 'Privacidad' 'Bajo' 'Sin contenido optimizado en la nube, experiencias a medida, portapapeles entre dispositivos ni datos de escritura a mano' @(
    (New-Entry "$POL\CloudContent" 'DisableCloudOptimizedContent' 1),
    (New-Entry "$POL\CloudContent" 'DisableTailoredExperiencesWithDiagnosticData' 1),
    (New-Entry "$POL\System" 'AllowCrossDeviceClipboard' 0),
    (New-Entry "$POL\TabletPC" 'PreventHandwritingDataSharing' 1),
    (New-Entry "$POL\HandwritingErrorReports" 'PreventHandwritingErrorReports' 1),
    (New-Entry "$POL\Windows Search" 'AllowSearchToUseLocation' 0)
)
Add-Reg 'feeds-off' 'Privacidad' 'Bajo' 'Desactiva Noticias e intereses / Feeds por politica (por si una actualizacion los trae)' @(
    (New-Entry "$POL\Windows Feeds" 'EnableFeeds' 0)
)
Add-Reg 'ubicacion-off' 'Privacidad' 'Medio' 'OPCIONAL: desactiva la ubicacion en todo el sistema (clima y mapas no sabran donde estas)' @(
    (New-Entry "$POL\LocationAndSensors" 'DisableLocation' 1)
) $true

Add-Task 'tareas-telemetria-extra' 'Privacidad' 'Bajo' 'Desactiva mas tareas de diagnostico (disco, red, arranque de apps, Mapas, sincronizacion)' @(
    '\Microsoft\Windows\Application Experience\|StartupAppTask',
    '\Microsoft\Windows\Autochk\|Proxy',
    '\Microsoft\Windows\DiskDiagnostic\|Microsoft-Windows-DiskDiagnosticDataCollector',
    '\Microsoft\Windows\NetTrace\|GatherNetworkInfo',
    '\Microsoft\Windows\Maps\|MapsToastTask',
    '\Microsoft\Windows\Maps\|MapsUpdateTask',
    '\Microsoft\Windows\SettingSync\|BackgroundUploadTask'
)

Add-Reg 'privacidad-usuario' 'Usuario' 'Bajo' 'Sin ID de publicidad por usuario, sin seguimiento de apps ni recopilacion de escritura' @(
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0),
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0),
    (New-Entry 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1),
    (New-Entry $ADV 'Start_TrackProgs' 0),
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1),
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1),
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0),
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0)
)
Add-Reg 'sugerencias-usuario-extra' 'Usuario' 'Bajo' 'Sin consejos en pantalla de bloqueo, avisos de OneDrive ni "termina de configurar tu equipo"' @(
    (New-Entry $CDM 'RotatingLockScreenEnabled' 0),
    (New-Entry $CDM 'RotatingLockScreenOverlayEnabled' 0),
    (New-Entry $CDM 'FeatureManagementEnabled' 0),
    (New-Entry $CDM 'PreInstalledAppsEverEnabled' 0),
    (New-Entry $CDM 'SubscribedContent-310093Enabled' 0),
    (New-Entry $CDM 'SubscribedContent-338387Enabled' 0),
    (New-Entry $CDM 'SubscribedContent-338393Enabled' 0),
    (New-Entry $CDM 'SubscribedContent-353698Enabled' 0),
    (New-Entry $CDM 'SubscribedContent-88000326Enabled' 0),
    (New-Entry $ADV 'ShowSyncProviderNotifications' 0),
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0)
)
Add-Reg 'inicio-apps-rapido' 'Usuario' 'Bajo' 'Las apps de inicio arrancan sin el retraso artificial de Windows (sesion mas rapida)' @(
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0)
)
Add-Reg 'barra-tareas-limpia' 'Usuario' 'Bajo' 'OPCIONAL: busqueda como icono, sin boton Vista de tareas ni Contactos en la barra' @(
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 1),
    (New-Entry $ADV 'ShowTaskViewButton' 0),
    (New-Entry "$ADV\People" 'PeopleBand' 0)
) $true
Add-Reg 'sticky-keys-off' 'Usuario' 'Bajo' 'OPCIONAL: sin ventanas emergentes de Teclas especiales / Filtro (no uses si necesitas accesibilidad)' @(
    (New-Entry 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String'),
    (New-Entry 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags' '122' 'String'),
    (New-Entry 'HKCU:\Control Panel\Accessibility\ToggleKeys' 'Flags' '58' 'String')
) $true

Add-Reg 'defender-cpu-suave' 'Rendimiento' 'Bajo' 'Los escaneos de Defender usan poca CPU y baja prioridad (el i3 de 2 nucleos no se arrastra). Misma proteccion' @(
    (New-Entry "$DEF\Scan" 'AvgCPULoadFactor' 20),
    (New-Entry "$DEF\Scan" 'LowCpuPriority' 1)
)

Add-Reg 'wu-sin-reinicio-forzado' 'Usabilidad' 'Bajo' 'Windows Update sigue instalando, pero no reinicia solo con tu sesion abierta' @(
    (New-Entry "$POL\WindowsUpdate\AU" 'NoAutoRebootWithLoggedOnUsers' 1)
)

Add-Svc 'svc-extra' 'Servicios' 'Bajo' 'Desactiva servicios que casi nadie usa (Diag Hub, DLNA de WMP, Registro remoto, WerSvc, Realidad mixta, Telefono, Control parental, NFC pagos)' @(
    'diagnosticshub.standardcollector.service', 'WMPNetworkSvc', 'RemoteRegistry', 'WerSvc',
    'SharedRealitySvc', 'PhoneSvc', 'WpcMonSvc', 'SEMgrSvc', 'WalletService'
)
Add-Svc 'svc-descubrimiento' 'Servicios' 'Medio' 'OPCIONAL: desactiva SSDP, UPnP y LLTD (menos puertos abiertos; no veras Chromecast/DLNA/mapa de red)' @('SSDPSRV', 'upnphost', 'lltdsvc') 'Disabled' $true

Add-Reg 'wdigest-off' 'Seguridad' 'Bajo' 'WDigest no guarda contrasenas en texto claro en memoria (ya es el valor por defecto; lo fija)' @(
    (New-Entry 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' 'UseLogonCredential' 0)
)
Add-Reg 'dotnet-tls12' 'Seguridad' 'Bajo' 'Las apps .NET 4 usan TLS 1.2 o superior por defecto (evita conexiones debiles)' @(
    (New-Entry 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319' 'SchUseStrongCrypto' 1),
    (New-Entry 'HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319' 'SystemDefaultTlsVersions' 1),
    (New-Entry 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319' 'SchUseStrongCrypto' 1),
    (New-Entry 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\.NETFramework\v4.0.30319' 'SystemDefaultTlsVersions' 1)
)

Add-Custom 'powershell-v2-off' 'Seguridad' 'Bajo' 'Desactiva PowerShell 2.0 (version antigua que se usa para esquivar AMSI y los registros). Tarda unos segundos' `
    { (Get-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -ErrorAction Stop).State -ne 'Enabled' } `
    { [string](Get-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -ErrorAction Stop).State } `
    { Disable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -NoRestart -ErrorAction Stop | Out-Null } `
    { param($data) if ($data -eq 'Enabled') { Enable-WindowsOptionalFeature -Online -FeatureName MicrosoftWindowsPowerShellV2Root -NoRestart -ErrorAction Stop | Out-Null } }

$tlsEntries = @()
foreach ($ver in @('TLS 1.0', 'TLS 1.1')) {
    foreach ($side in @('Client', 'Server')) {
        $tp = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$ver\$side"
        $tlsEntries += (New-Entry $tp 'Enabled' 0)
        $tlsEntries += (New-Entry $tp 'DisabledByDefault' 1)
    }
}
Add-Reg 'tls-viejo-off' 'Seguridad' 'Medio' 'OPCIONAL: desactiva TLS 1.0 y 1.1 (puede romper sitios o programas muy antiguos)' $tlsEntries $true

Add-Reg 'ntlmv2-solo' 'Seguridad' 'Medio' 'OPCIONAL: solo NTLMv2 (puede fallar con NAS o equipos antiguos en la red)' @(
    (New-Entry 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'LmCompatibilityLevel' 5)
) $true
Add-Reg 'lsa-protegido' 'Seguridad' 'Medio' 'OPCIONAL: LSASS como proceso protegido (frena robo de credenciales; un driver viejo podria dejar de cargar)' @(
    (New-Entry 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' 'RunAsPPL' 1)
) $true
Add-Reg 'rdp-off' 'Seguridad' 'Bajo' 'OPCIONAL: bloquea Escritorio remoto (RDP) entrante. Solo si nunca lo usas' @(
    (New-Entry 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 1)
) $true
Add-Reg 'wsh-off' 'Seguridad' 'Medio' 'OPCIONAL: desactiva Windows Script Host (.vbs/.js); vector comun de malware, pero rompe scripts legados' @(
    (New-Entry 'HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings' 'Enabled' 0)
) $true
Add-Reg 'defender-red' 'Seguridad' 'Bajo' 'OPCIONAL: Proteccion de red de Defender (bloquea conexiones a sitios maliciosos). Refuerza' @(
    (New-Entry "$DEF\Windows Defender Exploit Guard\Network Protection" 'EnableNetworkProtection' 1)
) $true

Add-Custom 'netbios-off' 'Seguridad' 'Medio' 'OPCIONAL: NetBIOS sobre TCP/IP apagado en los adaptadores actuales (puede afectar nombres de equipos en redes caseras)' `
    {
        $ifs = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' | Where-Object { $_.PSChildName -like 'Tcpip_*' })
        if ($ifs.Count -eq 0) { throw 'sin interfaces' }
        $bad = @($ifs | Where-Object { [int]$_.GetValue('NetbiosOptions', 0) -ne 2 })
        $bad.Count -eq 0
    } `
    {
        $ifs = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' | Where-Object { $_.PSChildName -like 'Tcpip_*' })
        (@($ifs | ForEach-Object { '{0}={1}' -f $_.PSChildName, [int]$_.GetValue('NetbiosOptions', 0) })) -join ';'
    } `
    {
        $ifs = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' | Where-Object { $_.PSChildName -like 'Tcpip_*' })
        foreach ($i in $ifs) { Set-ItemProperty -Path $i.PSPath -Name 'NetbiosOptions' -Value 2 -Type DWord }
    } `
    {
        param($data)
        foreach ($pair in ([string]$data).Split(';')) {
            if (-not $pair) { continue }
            $kv = $pair.Split('=')
            $p = 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces\' + $kv[0]
            if (Test-Path -Path $p) { Set-ItemProperty -Path $p -Name 'NetbiosOptions' -Value ([int]$kv[1]) -Type DWord }
        }
    } `
    $true

Add-Custom 'ntfs-lastaccess-off' 'Rendimiento' 'Bajo' 'OPCIONAL: NTFS deja de anotar la hora de ultimo acceso (menos escrituras al SSD; ganancia pequena)' `
    {
        $o = (cmd /c "fsutil behavior query disablelastaccess 2>nul") | Out-String
        $m = [regex]::Match($o, '=\s*(\d)')
        $m.Success -and (@('1', '3') -contains $m.Groups[1].Value)
    } `
    {
        $o = (cmd /c "fsutil behavior query disablelastaccess 2>nul") | Out-String
        $m = [regex]::Match($o, '=\s*(\d)')
        if ($m.Success) { $m.Groups[1].Value } else { '2' }
    } `
    { cmd /c "fsutil behavior set disablelastaccess 1 >nul 2>&1" } `
    { param($data) if ($data -match '^\d$') { cmd /c ("fsutil behavior set disablelastaccess " + $data + " >nul 2>&1") } } `
    $true

$RamKB = 0
try {
    $cap = [uint64]0
    foreach ($m in @(Get-CimInstance Win32_PhysicalMemory)) { $cap += [uint64]$m.Capacity }
    $tot = [uint64](Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    $RamKB = [int][math]::Floor([math]::Max([double]$cap, [double]$tot) / 1KB)
} catch { }
if ($RamKB -gt 0) {
    Add-Reg 'svchost-unido' 'Rendimiento' 'Medio' 'OPCIONAL: menos procesos svchost (ahorra unas decenas de MB; si un servicio falla puede arrastrar a otros)' @(
        (New-Entry 'HKLM:\SYSTEM\CurrentControlSet\Control' 'SvcHostSplitThresholdInKB' $RamKB)
    ) $true
}

# ============================================================================
#  C) NOVEDADES v4.0 (IDs nuevos): equipo casi siempre conectado a corriente
# ============================================================================

# Plan de energia propio: rendimiento con corriente, valores moderados con bateria.
# Windows aplica solo la columna AC o DC segun la fuente; no hace falta ningun programa residente.
Add-Custom 'energia-ac-dc' 'Energia' 'Bajo' 'Plan propio: con corriente = maxima respuesta (CPU 100%, sin suspender USB/PCIe/Wi-Fi); con bateria = ahorro moderado' `
    {
        $g = Get-PlanGuid $PlanName
        $a = Get-ActivePlanGuid
        [bool]($g -and $a -and ($g -ieq $a))
    } `
    {
        $a = Get-ActivePlanGuid
        if ($a) { $a } else { '' }
    } `
    {
        $g = Get-PlanGuid $PlanName
        if (-not $g) {
            $o = (cmd /c ('powercfg /duplicatescheme {0} 2>nul' -f $PlanHigh)) | Out-String
            $m = [regex]::Match($o, $GuidRegex)
            if (-not $m.Success) {
                $o = (cmd /c ('powercfg /duplicatescheme {0} 2>nul' -f $PlanBal)) | Out-String
                $m = [regex]::Match($o, $GuidRegex)
            }
            if (-not $m.Success) { throw 'No se pudo crear el plan de energia propio.' }
            $g = $m.Value
            cmd /c ('powercfg /changename {0} "{1}" "Creado por LTSC-Tuner: rendimiento con corriente, ahorro moderado con bateria" >nul 2>&1' -f $g, $PlanName)
        }
        $proc = '54533251-82be-4824-96c1-47b60b740d00'
        Set-PlanValue $g $proc '893dee8e-2bef-41e0-89c6-b55d0929964c' 100 5      # CPU minima
        Set-PlanValue $g $proc 'bc5038f7-23e0-4960-96da-33abaf5935ec' 100 100    # CPU maxima
        Set-PlanValue $g $proc 'be337238-0d82-4146-a960-4f3749d470c7' 2 3        # modo boost
        Set-PlanValue $g $proc '0cc5b647-c1df-4637-891a-dec35c318583' 100 $null  # sin estacionar nucleos con corriente
        Set-PlanValue $g $proc '94d3a615-a899-4ac5-ae2b-e4d8f634367f' 1 0        # enfriamiento: activo con corriente
        Set-PlanValue $g '0012ee47-9041-4b5d-9b77-535fba8b1442' '6738e2c4-e8a5-4a42-b16a-e040e769756e' 0 1200  # disco nunca se apaga con corriente
        Set-PlanValue $g '2a737441-1930-4402-8d77-b2bebba308a3' '48e6b7a6-50f5-4782-a5d4-53bb8f07e226' 0 1      # suspension selectiva USB
        Set-PlanValue $g '501a4d13-42af-4429-9fd1-a8218c268e20' 'ee12f906-d277-404b-b6da-e5fa1a576df5' 0 1      # ahorro de enlace PCIe
        Set-PlanValue $g '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1' '12bbebe6-58d6-4636-95bb-3217ef867c1a' 0 2      # Wi-Fi: maximo rendimiento / medio
        Set-PlanValue $g '44f3beca-a7c0-460e-9df2-bb8b99e0cba6' '3619c3f2-afb2-4afc-b0e9-e7fef372de36' 2 1      # Intel Graphics: maximo rendimiento con corriente
        cmd /c ('powercfg /setactive {0} >nul 2>&1' -f $g)
    } `
    {
        param($data)
        $target = [string]$data
        $ours = Get-PlanGuid $PlanName
        if (-not $target -or ($ours -and ($target -ieq $ours))) { $target = $PlanBal }
        cmd /c ('powercfg /setactive {0} >nul 2>&1' -f $target)
        if ($LASTEXITCODE -ne 0) { cmd /c ('powercfg /setactive {0} >nul 2>&1' -f $PlanBal) }
        if ($ours) { cmd /c ('powercfg /delete {0} >nul 2>&1' -f $ours) }
    }

# Los adaptadores de red no se apagan para ahorrar energia (evita cortes de Wi-Fi/Ethernet)
Add-Custom 'nic-sin-ahorro' 'Energia' 'Bajo' 'Wi-Fi y Ethernet nunca se apagan para ahorrar energia (menos desconexiones). Windows lo permite por adaptador' `
    {
        $bad = 0
        foreach ($n in @(Get-NetAdapter -Physical -ErrorAction Stop)) {
            $pm = Get-NetAdapterPowerManagement -Name $n.Name -ErrorAction SilentlyContinue
            if ($pm -and ([string]$pm.AllowComputerToTurnOffDevice -eq 'Enabled')) { $bad++ }
        }
        $bad -eq 0
    } `
    {
        $parts = @()
        foreach ($n in @(Get-NetAdapter -Physical -ErrorAction Stop)) {
            $pm = Get-NetAdapterPowerManagement -Name $n.Name -ErrorAction SilentlyContinue
            if ($pm) { $parts += ('{0}={1}' -f $n.Name, [string]$pm.AllowComputerToTurnOffDevice) }
        }
        $parts -join '|'
    } `
    {
        foreach ($n in @(Get-NetAdapter -Physical -ErrorAction Stop)) {
            $pm = Get-NetAdapterPowerManagement -Name $n.Name -ErrorAction SilentlyContinue
            if ($pm -and ([string]$pm.AllowComputerToTurnOffDevice -eq 'Enabled')) {
                try { Set-NetAdapterPowerManagement -Name $n.Name -AllowComputerToTurnOffDevice Disabled -ErrorAction Stop }
                catch { }
            }
        }
    } `
    {
        param($data)
        foreach ($pair in ([string]$data).Split('|')) {
            if (-not $pair) { continue }
            $kv = $pair.Split('=')
            if ($kv.Count -ge 2 -and $kv[1] -eq 'Enabled') {
                try { Set-NetAdapterPowerManagement -Name $kv[0] -AllowComputerToTurnOffDevice Enabled -ErrorAction Stop } catch { }
            }
        }
    }

# Servicios que pasan a Manual (siguen funcionando cuando Windows los necesita)
Add-Svc 'svc-manual' 'Servicios' 'Bajo' 'Pasa a Manual Delivery Optimization (DoSvc) y Seguimiento de vinculos (TrkWks): arrancan solo si hacen falta' @('DoSvc', 'TrkWks') 'Manual'

# Opcionales nuevos
Add-Reg 'kernel-en-ram' 'Rendimiento' 'Bajo' 'OPCIONAL: el nucleo y los drivers no se paginan a disco (con 12 GB de RAM es seguro; ganancia pequena)' @(
    (New-Entry 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive' 1)
) $true

Add-Custom 'timer-dynamictick-off' 'Rendimiento' 'Medio' 'OPCIONAL: sin tick dinamico (temporizador estable, algo menos de latencia; mas consumo y calor). Si usas BitLocker, suspendelo antes' `
    {
        $o = (cmd /c "bcdedit /enum {current} 2>nul") | Out-String
        $o -match '(?im)^\s*disabledynamictick\s+(Yes|S\S|True)'
    } `
    {
        $o = (cmd /c "bcdedit /enum {current} 2>nul") | Out-String
        $m = [regex]::Match($o, '(?im)^\s*disabledynamictick\s+(\S+)')
        if (-not $m.Success) { 'absent' }
        elseif ($m.Groups[1].Value -match '^(Yes|S\S|True)$') { 'yes' }
        else { 'no' }
    } `
    { cmd /c "bcdedit /set disabledynamictick yes >nul 2>&1" } `
    {
        param($data)
        if ($data -eq 'yes') { cmd /c "bcdedit /set disabledynamictick yes >nul 2>&1" }
        elseif ($data -eq 'no') { cmd /c "bcdedit /set disabledynamictick no >nul 2>&1" }
        else { cmd /c "bcdedit /deletevalue disabledynamictick >nul 2>&1" }
    } `
    $true

$blk = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked'
Add-Reg 'menu-contextual-limpio' 'Usabilidad' 'Bajo' 'OPCIONAL: quita "Enviar a dispositivo", "Compartir" y "Dar acceso a" del menu contextual (reinicia el Explorador)' @(
    (New-Entry $blk '{7AD84985-87B4-4a16-BE58-8B72A5B390F7}' '' 'String'),
    (New-Entry $blk '{e2bf9676-5f8f-435c-97eb-11607a5bedf7}' '' 'String'),
    (New-Entry $blk '{f81e9010-6ea4-11ce-a7ff-00aa003ca9f6}' '' 'String')
) $true

# ============================================================================
#  D) NOVEDADES v5.0 (IDs nuevos): MODO MAXIMO y mantenimiento
# ============================================================================

# Tareas de mantenimiento/diagnostico que consumen CPU y disco sin aportar
Add-Task 'tareas-mantenimiento' 'Rendimiento' 'Bajo' 'Desactiva tareas de diagnostico y mantenimiento innecesarias (energia, chkdsk proactivo, WDI, SysMain, Work Folders, voz, ubicacion)' @(
    '\Microsoft\Windows\Power Efficiency Diagnostics\|AnalyzeSystem',
    '\Microsoft\Windows\Diagnosis\|Scheduled',
    '\Microsoft\Windows\Chkdsk\|ProactiveScan',
    '\Microsoft\Windows\Shell\|FamilySafetyMonitor',
    '\Microsoft\Windows\Shell\|FamilySafetyRefreshTask',
    '\Microsoft\Windows\Windows Media Sharing\|UpdateLibrary',
    '\Microsoft\Windows\WDI\|ResolutionHost',
    '\Microsoft\Windows\Sysmain\|ResPriStaticDbSync',
    '\Microsoft\Windows\Sysmain\|WsSwapAssessmentTask',
    '\Microsoft\Windows\DUSM\|dusmtask',
    '\Microsoft\Windows\Work Folders\|Work Folders Logon Synchronization',
    '\Microsoft\Windows\Work Folders\|Work Folders Maintenance Work',
    '\Microsoft\Windows\Location\|Notifications',
    '\Microsoft\Windows\Location\|WindowsActionDialog',
    '\Microsoft\Windows\Speech\|SpeechModelDownloadTask',
    '\Microsoft\Windows\Mobile Broadband Accounts\|MNO Metadata Parser',
    '\Microsoft\Windows\RetailDemo\|CleanupOfflineContent'
)

# ---- MODO MAXIMO ----
# CPU idle (C-states) apagado SOLO con corriente (DC = 0 mantiene el reposo normal con bateria)
Add-Custom 'cpu-idle-off' 'Energia' 'Alto' 'MAX: con corriente la CPU nunca entra en reposo (C-states off). Respuesta inmediata, pero MUCHO mas calor/ruido; con bateria sigue normal' `
    {
        $g = Get-PlanGuid $PlanName
        if (-not $g) { return $false }
        $v = Get-PlanIdleDisable $g
        [bool]($v -and ($v.Ac -eq 1))
    } `
    { '' } `
    {
        $g = Ensure-Plan
        $proc = '54533251-82be-4824-96c1-47b60b740d00'
        Set-PlanValue $g $proc '5d76a2ca-e8c0-402f-a133-2158492d58ad' 1 0
        Set-PlanValue $g $proc '94d3a615-a899-4ac5-ae2b-e4d8f634367f' 1 0
        cmd /c ('powercfg /setactive {0} >nul 2>&1' -f $g)
    } `
    {
        param($data)
        $g = Get-PlanGuid $PlanName
        if ($g) { Set-PlanValue $g '54533251-82be-4824-96c1-47b60b740d00' '5d76a2ca-e8c0-402f-a133-2158492d58ad' 0 0 }
    } `
    $true

# SmartScreen fuera (sistema, Explorador, IE/Edge, apps de la tienda). Defender sigue escaneando.
Add-Reg 'smartscreen-off' 'Seguridad' 'Alto' 'MAX: desactiva SmartScreen (Explorador, IE/Edge, apps). Defender sigue activo; ya no habra aviso de descargas desconocidas' @(
    (New-Entry "$POL\System" 'EnableSmartScreen' 0),
    (New-Entry 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' 'SmartScreenEnabled' 'Off' 'String'),
    (New-Entry 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'SmartScreenEnabled' 0),
    (New-Entry 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'SmartScreenPuaEnabled' 0),
    (New-Entry 'HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\PhishingFilter' 'EnabledV9' 0),
    (New-Entry 'HKLM:\SOFTWARE\Policies\Microsoft\Internet Explorer\PhishingFilter' 'EnabledV9' 0),
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost' 'EnableWebContentEvaluation' 0),
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppHost' 'PreventOverride' 0)
) $true

Add-Reg 'adjuntos-sin-aviso' 'Seguridad' 'Alto' 'MAX: no marca los archivos descargados (sin "Abrir archivo - Advertencia de seguridad" ni bloqueo de Internet)' @(
    (New-Entry 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Attachments' 'SaveZoneInformation' 1),
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Attachments' 'SaveZoneInformation' 1)
) $true

Add-Svc 'svc-max' 'Servicios' 'Medio' 'MAX: desactiva mas servicios que no usas (WebClient, WinRM, Insider, Work Folders, tarjetas inteligentes, escaner, iSCSI, P2P, hotspot, AllJoyn...)' @(
    'AJRouter', 'ALG', 'CscService', 'fhsvc', 'icssvc', 'MSiSCSI', 'p2pimsvc', 'p2psvc', 'PNRPAutoReg', 'PNRPsvc',
    'RpcLocator', 'SCardSvr', 'ScDeviceEnum', 'SCPolicySvc', 'SNMPTRAP', 'stisvc', 'TapiSrv', 'WebClient',
    'WFDSConMgrSvc', 'WinRM', 'wisvc', 'workfolderssvc'
) 'Disabled' $true

Add-Reg 'efectos-max' 'Usuario' 'Bajo' 'MAX: efectos visuales al minimo ("Ajustar para obtener el mejor rendimiento"). La interfaz se ve mas simple. Cierra sesion para verlo' @(
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2),
    (New-Entry 'HKCU:\Control Panel\Desktop' 'UserPreferencesMask' ([byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00)) 'Binary'),
    (New-Entry 'HKCU:\Control Panel\Desktop' 'DragFullWindows' '0' 'String'),
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ListviewShadow' 0),
    (New-Entry 'HKCU:\SOFTWARE\Microsoft\Windows\DWM' 'EnableAeroPeek' 0)
) $true

Add-Reg 'prefetch-off' 'Rendimiento' 'Bajo' 'MAX: sin Prefetch/Superfetch (innecesario con SSD; menos escrituras y menos trabajo en segundo plano)' @(
    (New-Entry 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' 'EnablePrefetcher' 0),
    (New-Entry 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters' 'EnableSuperfetch' 0)
) $true

Add-Custom 'compresion-memoria-off' 'Rendimiento' 'Medio' 'MAX: desactiva la compresion de memoria (ahorra CPU en un i3 de 2 nucleos; con 12 GB de RAM sobra memoria). Requiere reiniciar' `
    { -not (Get-MMAgent -ErrorAction Stop).MemoryCompression } `
    { [string](Get-MMAgent -ErrorAction Stop).MemoryCompression } `
    { Disable-MMAgent -MemoryCompression -ErrorAction Stop } `
    { param($data) if ($data -eq 'True') { Enable-MMAgent -MemoryCompression -ErrorAction Stop } } `
    $true

# Que ajustes entran en el MODO MAXIMO (ademas de los recomendados)
$MaxIds = @(
    'cpu-idle-off', 'smartscreen-off', 'adjuntos-sin-aviso', 'svc-max', 'efectos-max', 'prefetch-off',
    'compresion-memoria-off', 'timer-dynamictick-off', 'kernel-en-ram', 'ntfs-lastaccess-off',
    'svc-busqueda', 'segundo-plano', 'svchost-unido', 'ubicacion-off'
)
foreach ($tw in $Tweaks) {
    $tw | Add-Member -NotePropertyName Max -NotePropertyValue ($MaxIds -contains $tw.Id) -Force
    if ($tw.Max) { $tw.Optional = $true }
}

# ----------------------------------------------------------------------------
# Estado de cada ajuste
# ----------------------------------------------------------------------------
function Get-TweakStatus {
    param($t)
    switch ($t.Type) {
        'Reg' {
            $ok = 0
            foreach ($e in $t.Entries) {
                $cur = Get-RegState $e.Path $e.Name
                if ($cur.Exists -and ((ConvertTo-CmpString $cur.Value) -eq (ConvertTo-CmpString $e.Value))) { $ok++ }
            }
            if ($ok -eq $t.Entries.Count) { return 'Aplicado' }
            if ($ok -eq 0) { return 'No aplicado' }
            return 'Parcial'
        }
        'Svc' {
            $present = 0; $ok = 0
            foreach ($n in $t.Names) {
                $s = Get-SvcState $n
                if ($null -eq $s) { continue }
                $present++
                if ([int]$s.Start -eq $t.StartValue) { $ok++ }
            }
            if ($present -eq 0) { return 'No disponible' }
            if ($ok -eq $present) { return 'Aplicado' }
            if ($ok -eq 0) { return 'No aplicado' }
            return 'Parcial'
        }
        'Task' {
            $present = 0; $ok = 0
            foreach ($spec in $t.Tasks) {
                $o = Get-TaskObj $spec
                if ($null -eq $o) { continue }
                $present++
                if ([string]$o.State -eq 'Disabled') { $ok++ }
            }
            if ($present -eq 0) { return 'No disponible' }
            if ($ok -eq $present) { return 'Aplicado' }
            if ($ok -eq 0) { return 'No aplicado' }
            return 'Parcial'
        }
        'Custom' {
            try { if (& $t.Test) { return 'Aplicado' } else { return 'No aplicado' } }
            catch { return 'No disponible' }
        }
    }
    return 'Desconocido'
}

function Show-Table {
    param($list)
    $cnt = @{ 'Aplicado' = 0; 'No aplicado' = 0; 'Parcial' = 0; 'No disponible' = 0 }
    Write-Host ''
    Write-Host ('{0,-26} {1,-12} {2,-6} {3,-4} {4,-13} {5}' -f 'ID', 'Categoria', 'Riesgo', 'Opc', 'Estado', 'Descripcion')
    Write-Host ('-' * 120)
    foreach ($t in $list) {
        $st = Get-TweakStatus $t
        if ($cnt.ContainsKey($st)) { $cnt[$st]++ }
        $color = 'DarkGray'
        switch ($st) {
            'Aplicado'    { $color = 'Green' }
            'No aplicado' { $color = 'Gray' }
            'Parcial'     { $color = 'Yellow' }
        }
        $opc = 'No'
        if ($t.Optional) { $opc = 'Si' }
        if ($t.Max) { $opc = 'MAX' }
        Write-Host ('{0,-26} {1,-12} {2,-6} {3,-4} {4,-13} {5}' -f $t.Id, $t.Cat, $t.Risk, $opc, $st, $t.Desc) -ForegroundColor $color
    }
    Write-Host ''
    Write-Host ('Resumen: {0} aplicados | {1} no aplicados | {2} parciales | {3} no disponibles' -f $cnt['Aplicado'], $cnt['No aplicado'], $cnt['Parcial'], $cnt['No disponible'])
    Write-Host ''
}

# ----------------------------------------------------------------------------
# Aplicar y revertir un ajuste
# ----------------------------------------------------------------------------
function Apply-Tweak {
    param($t)
    $already = $state.ContainsKey($t.Id)

    switch ($t.Type) {
        'Reg' {
            if (-not $already) {
                $items = @()
                foreach ($e in $t.Entries) {
                    $p = Get-RegState $e.Path $e.Name
                    $items += @{ Path = $e.Path; Name = $e.Name; Existed = $p.Exists; Value = $p.Value; Kind = $p.Kind }
                }
                $state[$t.Id] = @{ Items = $items }
                Save-State $state
            }
            foreach ($e in $t.Entries) { Set-Reg $e.Path $e.Name $e.Value $e.Kind }
        }
        'Svc' {
            if (-not $already) {
                $items = @()
                foreach ($n in $t.Names) {
                    $s = Get-SvcState $n
                    if ($null -ne $s) { $items += @{ Name = $n; Start = $s.Start; Delayed = $s.Delayed } }
                }
                $state[$t.Id] = @{ Items = $items }
                Save-State $state
            }
            foreach ($n in $t.Names) {
                if ($null -eq (Get-SvcState $n)) { continue }
                try { Set-Service -Name $n -StartupType $t.StartName }
                catch { Write-Log ('   aviso: no se pudo cambiar {0}: {1}' -f $n, $_.Exception.Message) 'Yellow' }
            }
        }
        'Task' {
            if (-not $already) {
                $items = @()
                foreach ($spec in $t.Tasks) {
                    $o = Get-TaskObj $spec
                    if ($null -ne $o) { $items += @{ Spec = $spec; Enabled = ([string]$o.State -ne 'Disabled') } }
                }
                $state[$t.Id] = @{ Items = $items }
                Save-State $state
            }
            foreach ($spec in $t.Tasks) {
                $o = Get-TaskObj $spec
                if ($null -eq $o) { continue }
                try { Disable-ScheduledTask -TaskPath $o.TaskPath -TaskName $o.TaskName | Out-Null }
                catch { Write-Log ('   aviso: no se pudo desactivar la tarea {0}: {1}' -f $spec, $_.Exception.Message) 'Yellow' }
            }
        }
        'Custom' {
            if (-not $already) {
                $data = & $t.Capture
                $state[$t.Id] = @{ Items = @( @{ Data = [string]$data } ) }
                Save-State $state
            }
            & $t.Apply
        }
    }
}

function Undo-Tweak {
    param($t, $rec)
    $items = @($rec.Items)
    switch ($t.Type) {
        'Reg' {
            foreach ($it in $items) {
                if ($it.Existed) { Set-Reg $it.Path $it.Name $it.Value $it.Kind }
                else { Remove-Reg $it.Path $it.Name }
            }
        }
        'Svc' {
            foreach ($it in $items) {
                $p = "HKLM:\SYSTEM\CurrentControlSet\Services\$($it.Name)"
                try {
                    Set-Reg $p 'Start' $it.Start 'DWord'
                    if ($null -ne $it.Delayed) { Set-Reg $p 'DelayedAutostart' $it.Delayed 'DWord' }
                    else { Remove-Reg $p 'DelayedAutostart' }
                }
                catch {
                    $map = @{ 2 = 'Automatic'; 3 = 'Manual'; 4 = 'Disabled' }
                    Set-Service -Name $it.Name -StartupType $map[[int]$it.Start]
                }
            }
        }
        'Task' {
            foreach ($it in $items) {
                if ($it.Enabled) {
                    $o = Get-TaskObj $it.Spec
                    if ($null -ne $o) { Enable-ScheduledTask -TaskPath $o.TaskPath -TaskName $o.TaskName | Out-Null }
                }
            }
        }
        'Custom' {
            foreach ($it in $items) { & $t.Restore $it.Data }
        }
    }
}

# ----------------------------------------------------------------------------
# Seguridad extra: copia .reg, punto de restauracion, filtro de contexto
# ----------------------------------------------------------------------------
function Backup-RegKeys {
    param($list)
    try {
        $dir = Join-Path $Root ('backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $keys = @{}
        foreach ($t in $list) {
            if ($t.Type -eq 'Reg') { foreach ($e in $t.Entries) { $keys[$e.Path] = $true } }
        }
        $i = 0
        foreach ($k in @($keys.Keys)) {
            if (-not (Test-Path -Path $k)) { continue }
            $native = $k -replace '^HKLM:\\', 'HKLM\' -replace '^HKCU:\\', 'HKCU\'
            $i++
            $file = Join-Path $dir ('{0:D2}.reg' -f $i)
            cmd /c ('reg export "{0}" "{1}" /y >nul 2>&1' -f $native, $file)
        }
        Write-Log ('Copia de seguridad del registro ({0} claves) en: {1}' -f $i, $dir) 'DarkCyan'
    }
    catch {
        Write-Log ('No se pudo hacer la copia .reg (se continua): ' + $_.Exception.Message) 'Yellow'
    }
}

function New-SafePoint {
    try {
        Enable-ComputerRestore -Drive ($env:SystemDrive + '\') -ErrorAction Stop
        Checkpoint-Computer -Description 'LTSC-Tuner (antes de aplicar)' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
        Write-Log 'Punto de restauracion creado.' 'Green'
    }
    catch {
        Write-Log ('No se pudo crear punto de restauracion (se continua; el estado queda guardado para Undo): ' + $_.Exception.Message) 'Yellow'
    }
}

function Select-Applicable {
    param($list)
    foreach ($t in $list) {
        if ($t.UsesHkcu -and (-not $UserCtxOk) -and (-not $ForceUserTweaks)) {
            Write-Log ("   omitido '{0}': cambia ajustes de usuario y esta ventana de administrador no es de tu usuario." -f $t.Id) 'Yellow'
            continue
        }
        $t
    }
}

function Invoke-ApplyList {
    param($list)
    $list = @(Select-Applicable $list)
    if ($list.Count -eq 0) { Write-Log 'Nada que aplicar.' 'Yellow'; return }
    Write-Log ('--- LTSC-Tuner v{0}: aplicando {1} ajustes ---' -f $ToolVersion, $list.Count) 'Cyan'
    Backup-RegKeys $list
    if (-not $NoRestorePoint) { New-SafePoint }
    $ok = 0; $fail = 0
    foreach ($t in $list) {
        try { Apply-Tweak $t; Write-Log ('[OK]    ' + $t.Id) 'Green'; $ok++ }
        catch { Write-Log ('[ERROR] {0}: {1}' -f $t.Id, $_.Exception.Message) 'Red'; $fail++ }
    }
    Write-Log ('Listo. Correctos: {0}  Con error: {1}' -f $ok, $fail) 'Cyan'
    Write-Log 'Reinicia el equipo para que todos los cambios surtan efecto.' 'Cyan'
}

function Invoke-UndoList {
    param($list)
    $list = @(Select-Applicable $list)
    if ($list.Count -eq 0) { Write-Log 'Nada que revertir.' 'Yellow'; return }
    Write-Log ('--- LTSC-Tuner v{0}: revirtiendo {1} ajustes ---' -f $ToolVersion, $list.Count) 'Cyan'
    $ok = 0; $fail = 0
    foreach ($t in $list) {
        try {
            Undo-Tweak $t $state[$t.Id]
            $state.Remove($t.Id)
            Save-State $state
            Write-Log ('[REVERTIDO] ' + $t.Id) 'Green'
            $ok++
        }
        catch { Write-Log ('[ERROR] {0}: {1}' -f $t.Id, $_.Exception.Message) 'Red'; $fail++ }
    }
    Write-Log ('Listo. Revertidos: {0}  Con error: {1}' -f $ok, $fail) 'Cyan'
    Write-Log 'Reinicia el equipo para completar la reversion.' 'Cyan'
}

# ----------------------------------------------------------------------------
# Limpieza (no es un ajuste: borra archivos temporales; no toca tus documentos)
# ----------------------------------------------------------------------------
function Get-FolderSize {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [int64]0 }
    $s = (Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue |
          Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum
    if ($s) { return [int64]$s }
    return [int64]0
}

function Clear-FolderContents {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    foreach ($item in @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)) {
        try { Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop } catch { }
    }
}

function Invoke-Clean {
    $drive = [IO.DriveInfo]($env:SystemDrive + '\')
    $free0 = $drive.AvailableFreeSpace
    Write-Log ('--- LTSC-Tuner v{0}: limpieza ---' -f $ToolVersion) 'Cyan'

    $targets = @(
        $env:TEMP,
        (Join-Path $env:SystemRoot 'Temp'),
        (Join-Path $env:SystemRoot 'Minidump'),
        (Join-Path $env:LOCALAPPDATA 'CrashDumps'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'),
        (Join-Path $env:SystemRoot 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache')
    )
    foreach ($p in $targets) {
        $before = Get-FolderSize $p
        Clear-FolderContents $p
        Write-Log ('   {0}: ~{1} MB' -f $p, [math]::Round($before / 1MB, 0)) 'Gray'
    }

    # Cache de descargas de Windows Update (se vuelve a crear sola)
    $svcs = @('wuauserv', 'bits')
    $was = @{}
    foreach ($s in $svcs) {
        $o = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($o) { $was[$s] = ($o.Status -eq 'Running') }
    }
    foreach ($s in $svcs) { if ($was[$s]) { try { Stop-Service -Name $s -Force -ErrorAction Stop } catch { } } }
    $wu = Join-Path $env:SystemRoot 'SoftwareDistribution\Download'
    $before = Get-FolderSize $wu
    Clear-FolderContents $wu
    Write-Log ('   {0}: ~{1} MB' -f $wu, [math]::Round($before / 1MB, 0)) 'Gray'
    foreach ($s in $svcs) { if ($was[$s]) { try { Start-Service -Name $s -ErrorAction Stop } catch { } } }

    Write-Log 'Limpiando componentes de Windows (DISM StartComponentCleanup). Puede tardar varios minutos...' 'Gray'
    cmd /c "dism /online /Cleanup-Image /StartComponentCleanup /NoRestart >nul 2>&1"

    $free1 = ([IO.DriveInfo]($env:SystemDrive + '\')).AvailableFreeSpace
    $gain = [math]::Round(($free1 - $free0) / 1MB, 0)
    Write-Log ('Listo. Espacio liberado aproximado: {0} MB (la papelera no se vacia).' -f $gain) 'Cyan'
}

# ----------------------------------------------------------------------------
# Programas de inicio (se desactivan igual que en el Administrador de tareas; reversible)
# ----------------------------------------------------------------------------
function New-StartupObj {
    param([string]$Name, [string]$Cmd, [string]$Src, [string]$Appr)
    $enabled = $true
    $kk = Get-Item -Path $Appr -ErrorAction SilentlyContinue
    if ($kk) {
        $b = $kk.GetValue($Name)
        if (($b -is [byte[]]) -and ($b.Length -gt 0) -and (($b[0] -band 1) -eq 1)) { $enabled = $false }
    }
    return [pscustomobject]@{ Name = $Name; Command = $Cmd; Source = $Src; Approved = $Appr; Enabled = $enabled }
}

function Get-StartupItems {
    $ap = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $items = @()
    $runKeys = @(
        @{ Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Appr = "HKCU:\$ap\Run"; Src = 'Run (usuario)' },
        @{ Key = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Appr = "HKLM:\$ap\Run"; Src = 'Run (equipo)' },
        @{ Key = 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Run'; Appr = "HKLM:\$ap\Run32"; Src = 'Run 32 bits (equipo)' }
    )
    foreach ($rk in $runKeys) {
        if (-not (Test-Path -Path $rk.Key)) { continue }
        $k = Get-Item -Path $rk.Key
        foreach ($n in $k.GetValueNames()) {
            if (-not $n) { continue }
            $items += New-StartupObj $n ([string]$k.GetValue($n)) $rk.Src $rk.Appr
        }
    }
    $folders = @(
        @{ Dir = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'); Appr = "HKCU:\$ap\StartupFolder"; Src = 'Carpeta Inicio (usuario)' },
        @{ Dir = (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup'); Appr = "HKLM:\$ap\StartupFolder"; Src = 'Carpeta Inicio (equipo)' }
    )
    foreach ($f in $folders) {
        if (-not (Test-Path -LiteralPath $f.Dir)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $f.Dir -File -Force -ErrorAction SilentlyContinue)) {
            if ($file.Name -ieq 'desktop.ini') { continue }
            $items += New-StartupObj $file.Name $file.FullName $f.Src $f.Appr
        }
    }
    return $items
}

function Set-StartupItem {
    param($Item, [bool]$On)
    if (-not (Test-Path -Path $Item.Approved)) { New-Item -Path $Item.Approved -Force | Out-Null }
    $b = New-Object byte[] 12
    if ($On) { $b[0] = 2 } else { $b[0] = 3 }
    New-ItemProperty -Path $Item.Approved -Name $Item.Name -Value $b -PropertyType Binary -Force | Out-Null
}

function Show-StartupGui {
    $items = @(Get-StartupItems)
    $script:StartForm = New-Object System.Windows.Forms.Form
    $f = $script:StartForm
    $f.Text = 'Programas de inicio - desmarca los que NO quieres al encender'
    $f.Size = New-Object System.Drawing.Size(1000, 520)
    $f.StartPosition = 'CenterParent'

    $script:StartLv = New-Object System.Windows.Forms.ListView
    $script:StartLv.View = 'Details'
    $script:StartLv.CheckBoxes = $true
    $script:StartLv.FullRowSelect = $true
    $script:StartLv.GridLines = $true
    $script:StartLv.Location = New-Object System.Drawing.Point(10, 10)
    $script:StartLv.Size = New-Object System.Drawing.Size(965, 410)
    $script:StartLv.Anchor = 'Top,Bottom,Left,Right'
    [void]$script:StartLv.Columns.Add('Programa', 230)
    [void]$script:StartLv.Columns.Add('Origen', 160)
    [void]$script:StartLv.Columns.Add('Comando', 550)
    foreach ($it in $items) {
        $li = New-Object System.Windows.Forms.ListViewItem($it.Name)
        [void]$li.SubItems.Add($it.Source)
        [void]$li.SubItems.Add($it.Command)
        $li.Checked = $it.Enabled
        $li.Tag = $it
        [void]$script:StartLv.Items.Add($li)
    }
    $f.Controls.Add($script:StartLv)

    $bSave = New-Object System.Windows.Forms.Button
    $bSave.Text = 'Guardar cambios'
    $bSave.Location = New-Object System.Drawing.Point(10, 430)
    $bSave.Size = New-Object System.Drawing.Size(160, 32)
    $bSave.Anchor = 'Bottom,Left'
    $f.Controls.Add($bSave)

    $bClose = New-Object System.Windows.Forms.Button
    $bClose.Text = 'Cerrar'
    $bClose.Location = New-Object System.Drawing.Point(815, 430)
    $bClose.Size = New-Object System.Drawing.Size(160, 32)
    $bClose.Anchor = 'Bottom,Right'
    $f.Controls.Add($bClose)

    $bSave.Add_Click({
        $n = 0
        foreach ($li in $script:StartLv.Items) {
            $it = $li.Tag
            if ($li.Checked -ne $it.Enabled) {
                try {
                    Set-StartupItem $it $li.Checked
                    $it.Enabled = $li.Checked
                    $estado = 'desactivado'
                    if ($li.Checked) { $estado = 'activado' }
                    Write-Log ('[INICIO] {0}: {1}' -f $it.Name, $estado) 'Green'
                    $n++
                }
                catch { Write-Log ('[ERROR] inicio {0}: {1}' -f $it.Name, $_.Exception.Message) 'Red' }
            }
        }
        [void][System.Windows.Forms.MessageBox]::Show(('{0} cambios guardados. Se notan en el proximo inicio de sesion.' -f $n), 'LTSC-Tuner')
    })
    $bClose.Add_Click({ $script:StartForm.Close() })
    [void]$f.ShowDialog()
}

# ----------------------------------------------------------------------------
# Ventana grafica
# ----------------------------------------------------------------------------
function Refresh-Gui {
    $script:Lv.Items.Clear()
    foreach ($t in $Tweaks) {
        $st = Get-TweakStatus $t
        $opc = 'No'
        if ($t.Optional) { $opc = 'Si' }
        if ($t.Max) { $opc = 'MAX' }
        $item = New-Object System.Windows.Forms.ListViewItem($t.Id)
        [void]$item.SubItems.Add($t.Cat)
        [void]$item.SubItems.Add($t.Risk)
        [void]$item.SubItems.Add($opc)
        [void]$item.SubItems.Add($st)
        [void]$item.SubItems.Add($t.Desc)
        $item.Tag = $t.Id
        if ($st -eq 'Aplicado') { $item.ForeColor = [System.Drawing.Color]::Green }
        elseif ($st -eq 'Parcial') { $item.ForeColor = [System.Drawing.Color]::DarkOrange }
        elseif ($st -eq 'No disponible') { $item.ForeColor = [System.Drawing.Color]::Gray }
        $item.Checked = ((-not $t.Optional) -and ($st -ne 'Aplicado') -and ($st -ne 'No disponible'))
        [void]$script:Lv.Items.Add($item)
    }
}

function Get-CheckedTweaks {
    $ids = @()
    foreach ($it in $script:Lv.CheckedItems) { $ids += [string]$it.Tag }
    return @($Tweaks | Where-Object { $ids -contains $_.Id })
}

function Update-GuiPowerLabel {
    $p = Get-PowerInfo
    if (-not $p.HasBattery) { $script:LblPower.Text = 'Energia: sin bateria detectada (equipo conectado).'; return }
    $src = 'CON BATERIA'
    if ($p.OnAC) { $src = 'CONECTADA a corriente' }
    $txt = 'Energia: {0} | carga {1}%' -f $src, $p.Charge
    if ($null -ne $p.Health) { $txt += (' | salud de la bateria {0}%' -f $p.Health) }
    $script:LblPower.Text = $txt
}

function Show-Gui {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $script:Form = New-Object System.Windows.Forms.Form
    $script:Form.Text = 'LTSC-Tuner v' + $ToolVersion + ' - ' + $SysLabel
    $script:Form.Size = New-Object System.Drawing.Size(1180, 790)
    $script:Form.StartPosition = 'CenterScreen'

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = 'Marca los ajustes y pulsa Aplicar. Los opcionales vienen sin marcar. Todo se puede revertir con "Revertir marcados".'
    $lbl.Location = New-Object System.Drawing.Point(10, 8)
    $lbl.Size = New-Object System.Drawing.Size(1140, 20)
    $script:Form.Controls.Add($lbl)

    $script:LblPower = New-Object System.Windows.Forms.Label
    $script:LblPower.Location = New-Object System.Drawing.Point(10, 28)
    $script:LblPower.Size = New-Object System.Drawing.Size(1140, 20)
    $script:LblPower.ForeColor = [System.Drawing.Color]::DarkCyan
    $script:Form.Controls.Add($script:LblPower)

    $script:Lv = New-Object System.Windows.Forms.ListView
    $script:Lv.View = 'Details'
    $script:Lv.CheckBoxes = $true
    $script:Lv.FullRowSelect = $true
    $script:Lv.GridLines = $true
    $script:Lv.Location = New-Object System.Drawing.Point(10, 52)
    $script:Lv.Size = New-Object System.Drawing.Size(1145, 420)
    $script:Lv.Anchor = 'Top,Left,Right'
    [void]$script:Lv.Columns.Add('Ajuste', 170)
    [void]$script:Lv.Columns.Add('Categoria', 90)
    [void]$script:Lv.Columns.Add('Riesgo', 60)
    [void]$script:Lv.Columns.Add('Opc.', 40)
    [void]$script:Lv.Columns.Add('Estado', 95)
    [void]$script:Lv.Columns.Add('Descripcion', 660)
    $script:Form.Controls.Add($script:Lv)

    $btnApply = New-Object System.Windows.Forms.Button
    $btnApply.Text = 'Aplicar marcados'
    $btnApply.Location = New-Object System.Drawing.Point(10, 482)
    $btnApply.Size = New-Object System.Drawing.Size(135, 32)
    $script:Form.Controls.Add($btnApply)

    $btnUndo = New-Object System.Windows.Forms.Button
    $btnUndo.Text = 'Revertir marcados'
    $btnUndo.Location = New-Object System.Drawing.Point(150, 482)
    $btnUndo.Size = New-Object System.Drawing.Size(135, 32)
    $script:Form.Controls.Add($btnUndo)

    $btnRec = New-Object System.Windows.Forms.Button
    $btnRec.Text = 'Marcar recomendados'
    $btnRec.Location = New-Object System.Drawing.Point(290, 482)
    $btnRec.Size = New-Object System.Drawing.Size(135, 32)
    $script:Form.Controls.Add($btnRec)

    $btnRefresh = New-Object System.Windows.Forms.Button
    $btnRefresh.Text = 'Actualizar estado'
    $btnRefresh.Location = New-Object System.Drawing.Point(570, 482)
    $btnRefresh.Size = New-Object System.Drawing.Size(135, 32)
    $script:Form.Controls.Add($btnRefresh)

    $btnClean = New-Object System.Windows.Forms.Button
    $btnClean.Text = 'Limpieza'
    $btnClean.Location = New-Object System.Drawing.Point(710, 482)
    $btnClean.Size = New-Object System.Drawing.Size(135, 32)
    $script:Form.Controls.Add($btnClean)

    $btnMax = New-Object System.Windows.Forms.Button
    $btnMax.Text = 'MODO MAXIMO'
    $btnMax.Location = New-Object System.Drawing.Point(430, 482)
    $btnMax.Size = New-Object System.Drawing.Size(135, 32)
    $btnMax.ForeColor = [System.Drawing.Color]::DarkRed
    $script:Form.Controls.Add($btnMax)

    $btnStartup = New-Object System.Windows.Forms.Button
    $btnStartup.Text = 'Inicio'
    $btnStartup.Location = New-Object System.Drawing.Point(850, 482)
    $btnStartup.Size = New-Object System.Drawing.Size(135, 32)
    $script:Form.Controls.Add($btnStartup)

    $btnClose = New-Object System.Windows.Forms.Button
    $btnClose.Text = 'Cerrar'
    $btnClose.Location = New-Object System.Drawing.Point(1020, 482)
    $btnClose.Size = New-Object System.Drawing.Size(135, 32)
    $btnClose.Anchor = 'Top,Right'
    $script:Form.Controls.Add($btnClose)

    $script:GuiLog = New-Object System.Windows.Forms.TextBox
    $script:GuiLog.Multiline = $true
    $script:GuiLog.ReadOnly = $true
    $script:GuiLog.ScrollBars = 'Vertical'
    $script:GuiLog.Font = New-Object System.Drawing.Font('Consolas', 9)
    $script:GuiLog.Location = New-Object System.Drawing.Point(10, 524)
    $script:GuiLog.Size = New-Object System.Drawing.Size(1145, 215)
    $script:GuiLog.Anchor = 'Top,Bottom,Left,Right'
    $script:Form.Controls.Add($script:GuiLog)

    $btnApply.Add_Click({
        try {
            $sel = @(Get-CheckedTweaks)
            if ($sel.Count -eq 0) { [void][System.Windows.Forms.MessageBox]::Show('No marcaste ningun ajuste.', 'LTSC-Tuner'); return }
            $r = [System.Windows.Forms.MessageBox]::Show(('Se aplicaran {0} ajustes. Continuar?' -f $sel.Count), 'LTSC-Tuner', 'YesNo', 'Question')
            if ($r -ne 'Yes') { return }
            $script:Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
            Invoke-ApplyList $sel
            Refresh-Gui
        }
        catch { [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'LTSC-Tuner - error') }
        finally { $script:Form.Cursor = [System.Windows.Forms.Cursors]::Default }
    })

    $btnUndo.Add_Click({
        try {
            $sel = @(Get-CheckedTweaks | Where-Object { $state.ContainsKey($_.Id) })
            if ($sel.Count -eq 0) { [void][System.Windows.Forms.MessageBox]::Show('Ninguno de los ajustes marcados fue aplicado con esta herramienta.', 'LTSC-Tuner'); return }
            $r = [System.Windows.Forms.MessageBox]::Show(('Se revertiran {0} ajustes. Continuar?' -f $sel.Count), 'LTSC-Tuner', 'YesNo', 'Question')
            if ($r -ne 'Yes') { return }
            $script:Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
            Invoke-UndoList $sel
            Refresh-Gui
        }
        catch { [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'LTSC-Tuner - error') }
        finally { $script:Form.Cursor = [System.Windows.Forms.Cursors]::Default }
    })

    $btnRec.Add_Click({
        foreach ($item in $script:Lv.Items) {
            $t = $Tweaks | Where-Object { $_.Id -eq [string]$item.Tag } | Select-Object -First 1
            $st = $item.SubItems[4].Text
            $item.Checked = ((-not $t.Optional) -and ($st -ne 'Aplicado') -and ($st -ne 'No disponible'))
        }
    })

    $btnMax.Add_Click({
        foreach ($item in $script:Lv.Items) {
            $t = $Tweaks | Where-Object { $_.Id -eq [string]$item.Tag } | Select-Object -First 1
            $st = $item.SubItems[4].Text
            $item.Checked = (((-not $t.Optional) -or $t.Max) -and ($st -ne 'Aplicado') -and ($st -ne 'No disponible'))
        }
        Write-Log 'MODO MAXIMO marcado: incluye CPU idle off (solo con corriente) y SmartScreen off. Revisa y pulsa Aplicar.' 'Yellow'
    })

    $btnStartup.Add_Click({ Show-StartupGui })

    $btnClean.Add_Click({
        try {
            $r = [System.Windows.Forms.MessageBox]::Show('Se borraran temporales, cache de Windows Update y se limpiaran componentes (tarda varios minutos). No toca tus documentos. Continuar?', 'LTSC-Tuner', 'YesNo', 'Question')
            if ($r -ne 'Yes') { return }
            $script:Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
            Invoke-Clean
        }
        catch { [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'LTSC-Tuner - error') }
        finally { $script:Form.Cursor = [System.Windows.Forms.Cursors]::Default }
    })

    $btnRefresh.Add_Click({ Refresh-Gui; Update-GuiPowerLabel })
    $btnClose.Add_Click({ $script:Form.Close() })

    Refresh-Gui
    Update-GuiPowerLabel
    Write-Log 'Ventana lista. Los registros tambien se guardan en C:\ProgramData\LTSC-Tuner\tuner.log' 'DarkCyan'
    [void]$script:Form.ShowDialog()
}

# ----------------------------------------------------------------------------
# Programa principal
# ----------------------------------------------------------------------------
$state = Load-State

if ($Gui) {
    if (-not $isAdmin) {
        if ($IsExe) {
            $self = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
            Start-Process -FilePath $self -Verb RunAs
        }
        else {
            $argList = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Gui' -f $PSCommandPath
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList
        }
        return
    }
    Show-Gui
    return
}

if ($Only -and ($Action -ne 'Startup')) {
    foreach ($id in $Only) {
        if (-not ($Tweaks | Where-Object { $_.Id -eq $id })) { Write-Log ("AVISO: el ajuste '{0}' no existe." -f $id) 'Yellow' }
    }
}

switch ($Action) {

    'Status' {
        [void](Write-PowerInfo)
        Show-Table $Tweaks
        Write-Host 'Para la ventana con casillas: -Gui' -ForegroundColor Cyan
        Write-Host 'Para aplicar:  -Action Apply   (agrega -IncludeOptional para los opcionales)' -ForegroundColor Cyan
        Write-Host 'Para revertir: -Action Undo' -ForegroundColor Cyan
        Write-Host 'Para limpiar:  -Action Clean' -ForegroundColor Cyan
        Write-Host 'Para todo al maximo: -Action Apply -Max   (columna Opc = MAX)' -ForegroundColor Cyan
        Write-Host 'Programas de inicio: -Action Startup' -ForegroundColor Cyan
        Write-Host ''
        Write-Host 'PROTEGER LA BATERIA (Windows no puede limitar la carga por si solo):' -ForegroundColor DarkCyan
        Write-Host '  Entra al BIOS (F2 al encender) > Power Management / Battery y busca "Primary Battery Charge Configuration"' -ForegroundColor DarkCyan
        Write-Host '  (modo "Primarily AC Use" o un limite personalizado de carga). Segun Dell, las opciones varian por modelo;' -ForegroundColor DarkCyan
        Write-Host '  si tu BIOS no la trae, mira si Dell Command | Power Manager esta disponible para tu equipo.' -ForegroundColor DarkCyan
        Write-Host '  El calor tambien desgasta la bateria: manten los ventiladores limpios y evita usarla sobre superficies blandas.' -ForegroundColor DarkCyan
        try {
            if ($isAdmin) {
                $trim = (cmd /c "fsutil behavior query DisableDeleteNotify 2>nul") | Out-String
                Write-Host ('TRIM (SSD): ' + $trim.Trim()) -ForegroundColor DarkCyan
                Write-Host '  (DisableDeleteNotify = 0 significa que TRIM esta activo; es lo correcto para tu SSD)' -ForegroundColor DarkCyan
            }
        } catch { }
    }

    'Apply' {
        $sel = @($Tweaks | Where-Object {
            if ($Only) { $Only -contains $_.Id } else { $IncludeOptional -or (-not $_.Optional) -or ($Max -and $_.Max) }
        })
        if ($sel.Count -eq 0) { Write-Log 'No hay ajustes que aplicar.' 'Yellow'; break }

        [void](Write-PowerInfo)
        Show-Table $sel
        if (-not $Yes) {
            $ans = Read-Host ('Se aplicaran {0} ajustes. Escribe SI para continuar' -f $sel.Count)
            if ($ans -ne 'SI') { Write-Log 'Cancelado por el usuario.' 'Yellow'; break }
        }
        Invoke-ApplyList $sel
    }

    'Undo' {
        $sel = @($Tweaks | Where-Object {
            $state.ContainsKey($_.Id) -and ((-not $Only) -or ($Only -contains $_.Id))
        })
        if ($sel.Count -eq 0) { Write-Log 'No hay nada que revertir (no se aplico ningun ajuste).' 'Yellow'; break }

        Write-Host ''
        Write-Host ('Se revertiran {0} ajustes:' -f $sel.Count)
        foreach ($t in $sel) { Write-Host ('  - ' + $t.Id) }
        if (-not $Yes) {
            $ans = Read-Host 'Escribe SI para continuar'
            if ($ans -ne 'SI') { Write-Log 'Cancelado por el usuario.' 'Yellow'; break }
        }
        Invoke-UndoList $sel
    }

    'Startup' {
        $list = @(Get-StartupItems)
        if (-not $Only) {
            Write-Host ''
            Write-Host ('{0,-34} {1,-10} {2,-24} {3}' -f 'Programa', 'Estado', 'Origen', 'Comando')
            Write-Host ('-' * 120)
            foreach ($it in $list) {
                $e = 'Desactivado'; $c = 'DarkGray'
                if ($it.Enabled) { $e = 'Activo'; $c = 'Green' }
                Write-Host ('{0,-34} {1,-10} {2,-24} {3}' -f $it.Name, $e, $it.Source, $it.Command) -ForegroundColor $c
            }
            Write-Host ''
            Write-Host 'Para desactivar: -Action Startup -Only "Nombre1","Nombre2"   (con -Enable los vuelve a activar)' -ForegroundColor Cyan
            break
        }
        $sel = @($list | Where-Object { $Only -contains $_.Name })
        if ($sel.Count -eq 0) { Write-Log 'Ningun programa de inicio coincide con esos nombres.' 'Yellow'; break }
        foreach ($it in $sel) {
            Set-StartupItem $it ([bool]$Enable)
            $estado = 'desactivado'
            if ($Enable) { $estado = 'activado' }
            Write-Log ('[INICIO] {0}: {1}' -f $it.Name, $estado) 'Green'
        }
    }

    'Clean' {
        Write-Host ''
        Write-Host 'Se borraran temporales, cache de Windows Update y se limpiaran componentes de Windows (DISM, varios minutos).'
        Write-Host 'No toca tus documentos ni vacia la papelera. Windows Update vuelve a descargar lo que necesite.'
        if (-not $Yes) {
            $ans = Read-Host 'Escribe SI para continuar'
            if ($ans -ne 'SI') { Write-Log 'Cancelado por el usuario.' 'Yellow'; break }
        }
        Invoke-Clean
    }
}
