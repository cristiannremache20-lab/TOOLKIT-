# Como generar y usar LTSC-Tuner.exe (v6.0)

## 1. Bajar los archivos a tu Dell Latitude E5550
En la laptop (Windows 10 LTSC IoT 2021), abre el navegador en esta repo y descarga
los 3 archivos de esta carpeta (boton **Code > Download ZIP**, o clic en cada archivo
y despues en el icono de descarga):

- `LTSC-Tuner.ps1`   (el programa, v6.0)
- `Compilar-EXE.ps1` (el compilador a .exe)
- `Iniciar-LTSC-Tuner.cmd` (alternativa sin compilar)

Pon los 3 en una misma carpeta, por ejemplo `C:\LTSC-Tuner`.

## 2. Compilar el ejecutable (se hace UNA sola vez)
1. Clic derecho en el menu Inicio > **Windows PowerShell (Administrador)**
   (o busca "powershell", clic derecho > Ejecutar como administrador).
2. Entra a la carpeta:
   ```powershell
   cd C:\LTSC-Tuner
   ```
3. Si es la primera vez, permite scripts en esa sesion:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass -Force
   ```
4. Compila:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\Compilar-EXE.ps1
   ```
   - Se instala solo el modulo `ps2exe` (necesita internet la primera vez).
   - Genera **`LTSC-Tuner.exe`** (ventana grafica, doble clic, pide admin solo).
   - Genera **`LTSC-Tuner.ico`** automaticamente si no hay uno (puedes poner tu
     propio `LTSC-Tuner.ico` en la carpeta antes de compilar para usarlo).
   - Opcional: `.\Compilar-EXE.ps1 -Consola` crea `LTSC-Tuner-consola.exe` para
     usarlo por linea de comandos (`LTSC-Tuner-consola.exe -Action Apply -Max -Yes`).

## 3. Ejecutarlo
- Doble clic en **`LTSC-Tuner.exe`** > acepta "Si" en el aviso de administrador.
- Se abre la ventana con todos los ajustes (columnas: categoria, riesgo, rama de
  Atlas OS aplicada, estado). Botones:
  - **Aplicar marcados** / **Recomendados** / **MODO MAXIMO**
  - **Revertir marcados** (Undo; los valores originales estan en
    `C:\ProgramData\LTSC-Tuner\state.json`)
  - **Limpieza** (temporales + cache Windows Update + DISM)
  - **Inicio** (programas de arranque)
  - **Optimizar (NGEN+TRIM)** (nuevo v6.0, inspirado en script-ngen.yml de Atlas:
    optimiza .NET, fuerza TRIM del SSD y verifica integridad con SFC)
- Despues de aplicar, **reinicia** para que todos los cambios surtan efecto.

## 4. Si el antivirus marca el .exe
Los .exe hechos con ps2exe a veces dan falso positivo. Opciones:
- Agrega la carpeta `C:\LTSC-Tuner` a las exclusiones de Windows Security >
  Proteccion contra virus > Administracion > Exclusiones.
- O usa directamente `Iniciar-LTSC-Tuner.cmd` (hace exactamente lo mismo sin compilar).

## 5. Resumen de v6.0 (basada tweak por tweak en el playbook oficial de Atlas OS)
Rendimiento/latencia (Win32PrioritySeparation 38, MMCSS), FTH off, apagado rapido,
privacidad/telemetria completa (rutas reales de Atlas), Explorer QoL, red
(RestrictAnonymous, sin throttling SMB), Win+X con CMD, Storage Sense, LongPaths,
plan AC-DC, modo Maximo reversible. NO desinstala apps ni componentes de Windows
(a diferencia de Atlas) y todo tiene Undo.
