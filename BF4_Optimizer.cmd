<# : batch
@echo off
REM ---------------------------------------------------------------------------
REM  Batch/PowerShell hybrid launcher.
REM  cmd.exe runs only these few lines; to PowerShell, this whole header is a
REM  block comment. The batch part passes this file's own path to
REM  PowerShell, which then reads and runs the rest of the file.
REM  ExecutionPolicy Bypass applies to this process only; no system setting
REM  is changed.
REM ---------------------------------------------------------------------------
setlocal
set "BF4CFG_SCRIPT=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText($env:BF4CFG_SCRIPT))"
echo.
pause
exit /b
#>

# =============================================================================
#  Battlefield 4 Optimizer
#
#  Detects CPU, GPU, RAM, display refresh rate, G-Sync/FreeSync support and
#  laptop vs. desktop, then generates a tuned user.cfg and PROFSAVE_profile in
#  a "BF4_Optimized" folder next to this file. It explains where each file
#  goes and, only if you confirm, copies them into place (with backups).
#
#  Nothing on the system is modified unless you answer "Y" at the end.
# =============================================================================


# -----------------------------------------------------------------------------
# Parse-Edid
# Reads a monitor's raw EDID bytes and reports:
#   - the refresh range from the "Display Range Limits" descriptor
#   - variable refresh rate (VRR) hints: AMD FreeSync, HDMI 2.1 VRR,
#     DisplayPort Adaptive-Sync and an NVIDIA vendor block (G-Sync hint)
# EDID only describes what the monitor advertises; it cannot tell whether
# VRR is actually enabled in the driver, which is why the user confirms it.
# -----------------------------------------------------------------------------
function Parse-Edid([byte[]]$e) {
    $r = [pscustomobject]@{ Name=''; MinHz=0; MaxHz=0; FreeSync=$false; HdmiVrr=$false; DpAdaptiveSync=$false; NvidiaVsdb=$false }
    if (-not $e -or $e.Length -lt 128) { return $r }

    # Base block: the four 18-byte descriptors start at offset 54.
    # Tag 0xFD = Display Range Limits (min/max vertical refresh in Hz).
    for ($d = 54; $d -le 108; $d += 18) {
        if ($e[$d] -eq 0 -and $e[$d+1] -eq 0 -and $e[$d+3] -eq 0xFD) {
            $f = $e[$d+4]; $min = [int]$e[$d+5]; $max = [int]$e[$d+6]
            # Offset flags: bit 1 adds 255 to the max rate, bits 1+0 add 255 to both (for >255 Hz panels)
            if ($f -band 2) { $max += 255; if ($f -band 1) { $min += 255 } }
            $r.MinHz = $min; $r.MaxHz = $max
        }
    }

    # Extension blocks (byte 126 holds how many follow the base block)
    $n = [int]$e[126]
    for ($i = 1; $i -le $n; $i++) {
        $b = $i * 128
        if ($e.Length -lt $b + 128) { break }

        if ($e[$b] -eq 0x02) {
            # CTA-861 extension: walk the data block collection looking for
            # Vendor-Specific Data Blocks (tag 3) and check their IEEE OUI.
            $end = $b + [int]$e[$b+2]          # byte 2 = offset where detailed timings start
            if ($e[$b+2] -lt 4) { $end = $b + 4 }
            $p = $b + 4
            while ($p -lt $end) {
                $tag = ($e[$p] -shr 5) -band 7
                $len = $e[$p] -band 0x1F
                if ($tag -eq 3 -and $len -ge 3) {
                    $oui = [int]$e[$p+1] -bor ([int]$e[$p+2] -shl 8) -bor ([int]$e[$p+3] -shl 16)
                    if ($oui -eq 0x00001A) { $r.FreeSync = $true }      # AMD FreeSync block
                    if ($oui -eq 0x00044B) { $r.NvidiaVsdb = $true }    # NVIDIA block (G-Sync hint)
                    if ($oui -eq 0xC45DD8 -and $len -ge 11) {           # HDMI Forum block
                        # VRRmax is a 10-bit value; non-zero means HDMI VRR is supported
                        $vmax = (([int]$e[$p+10] -band 0xC0) -shl 2) -bor [int]$e[$p+11]
                        if ($vmax -gt 0) { $r.HdmiVrr = $true }
                    }
                }
                $p += $len + 1
            }
        }
        elseif ($e[$b] -eq 0x70) {
            # DisplayID extension: data blocks are [tag][revision][length][payload].
            # Tag 0x2B = Adaptive-Sync data block (DisplayPort VRR).
            $p = $b + 5; $end = $b + 5 + [int]$e[$b+2]
            while (($p + 2) -lt $end -and $p -lt ($b + 127)) {
                $tag = $e[$p]; $len = [int]$e[$p+2]
                if ($tag -eq 0x2B) { $r.DpAdaptiveSync = $true }
                if ($tag -eq 0 -and $len -eq 0) { break }   # padding reached
                $p += 3 + $len
            }
        }
    }
    $r
}

# -----------------------------------------------------------------------------
# Get-MonitorInfo
# Lists the active monitors through WMI and reads each EDID from the registry.
# -----------------------------------------------------------------------------
function Get-MonitorInfo {
    $out = @()
    foreach ($m in @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue)) {
        if ($m.Active -eq $false) { continue }
        # Names are stored as arrays of character codes padded with zeros
        $name = (-join ($m.UserFriendlyName | Where-Object { $_ } | ForEach-Object { [char]$_ })).Trim()
        if (-not $name) { $name = (-join ($m.ManufacturerName | Where-Object { $_ } | ForEach-Object { [char]$_ })) + ' (built-in display)' }
        # WMI instance name maps to HKLM\...\Enum\DISPLAY\<id>\<instance> (minus the "_0" suffix)
        $inst = $m.InstanceName -replace '_\d+$', ''
        $edid = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Enum\$inst\Device Parameters" -ErrorAction SilentlyContinue).EDID
        $info = Parse-Edid $edid
        $info.Name = $name
        $out += $info
    }
    $out
}

# -----------------------------------------------------------------------------
# Get-MainGpu
# Picks the GPU the game will most likely run on. VRAM is read from the
# display driver's registry key because Win32_VideoController.AdapterRAM is a
# 32-bit field and caps out at 4 GB. Dedicated GPUs win over integrated ones.
# -----------------------------------------------------------------------------
function Get-MainGpu {
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    $list = @()
    foreach ($k in @(Get-ChildItem $key -ErrorAction SilentlyContinue)) {
        if ($k.PSChildName -notmatch '^\d{4}$') { continue }   # adapter subkeys are 0000, 0001, ...
        $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
        if (-not $p.DriverDesc) { continue }
        $v = $p.'HardwareInformation.qwMemorySize'             # 64-bit value (newer drivers)
        if (-not $v) {
            $m = $p.'HardwareInformation.MemorySize'           # 32-bit fallback (older drivers)
            if ($m -is [byte[]]) { $v = [BitConverter]::ToUInt32($m, 0) } elseif ($m) { $v = $m }
        }
        $list += [pscustomobject]@{ Name = $p.DriverDesc; VramGB = [math]::Round([double]$v / 1GB, 1) }
    }
    if (-not $list) {
        # Last resort if the registry could not be read
        $list = @(Get-CimInstance Win32_VideoController | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; VramGB = [math]::Round([double]$_.AdapterRAM / 1GB, 1) } })
    }
    # Ignore virtual / remote-desktop display adapters
    $list = @($list | Where-Object { $_.Name -notmatch 'Basic|Virtual|Parsec|Remote|Mirage|DisplayLink|Meta' })
    # Prefer NVIDIA/AMD/Arc, then the one with the most VRAM
    $list | Sort-Object @{ e = { if ($_.Name -match 'NVIDIA|GeForce|RTX|GTX|Radeon|AMD|Arc') { 1 } else { 0 } }; Descending = $true },
                        @{ e = 'VramGB'; Descending = $true } | Select-Object -First 1
}

# -----------------------------------------------------------------------------
# Find-Bf4
# Looks for the folder that contains bf4.exe: this script's folder first,
# then Origin/EA app and Steam registry entries, then common default paths.
# -----------------------------------------------------------------------------
function Find-Bf4([string]$scriptDir) {
    $c = @($scriptDir)
    # Origin / EA app
    foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\EA Games\Battlefield 4', 'HKLM:\SOFTWARE\EA Games\Battlefield 4') {
        $c += (Get-ItemProperty $k -ErrorAction SilentlyContinue).'Install Dir'
    }
    # Steam (app ID 1238860)
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 1238860',
                   'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 1238860') {
        $c += (Get-ItemProperty $k -ErrorAction SilentlyContinue).InstallLocation
    }
    # Default install locations
    $c += "${env:ProgramFiles(x86)}\Origin Games\Battlefield 4",
          "$env:ProgramFiles\EA Games\Battlefield 4",
          "${env:ProgramFiles(x86)}\Steam\steamapps\common\Battlefield 4"
    foreach ($d in $c) {
        if ($d -and (Test-Path -LiteralPath (Join-Path $d 'bf4.exe'))) { return (Resolve-Path -LiteralPath $d).Path }
    }
    $null
}

# -----------------------------------------------------------------------------
# Test-Write
# Returns $true if the current user can create files in the given folder
# (Program Files usually requires administrator rights).
# -----------------------------------------------------------------------------
function Test-Write([string]$dir) {
    try {
        $t = Join-Path $dir ".wtest_$PID"
        [IO.File]::WriteAllText($t, 'x'); Remove-Item -LiteralPath $t -Force
        $true
    } catch { $false }
}

# -----------------------------------------------------------------------------
# Get-GpuTier
# Maps the GPU MODEL to a graphics tier based on real-world BF4 performance
# (VRAM alone is misleading, e.g. a 4 GB GT 1030 is still a very slow card).
#   1 = Low, 2 = Medium, 3 = High
# Rules are evaluated top to bottom; the first match wins, so exceptions are
# listed before the broader patterns. Unknown models fall back to VRAM.
# -----------------------------------------------------------------------------
function Get-GpuTier($gpu) {
    $n = "$($gpu.Name)" -replace '\s+', ' '
    $rules = @(
        # --- Integrated graphics ---
        @{ T = 1; R = 'Intel.*(UHD|HD Graphics|Iris)' }
        @{ T = 1; R = 'Radeon\(TM\) Graphics|Radeon Graphics\s*$|Vega \d+ Graphics|Radeon \d{3}M\b' }
        # --- NVIDIA (exceptions first, then general rules) ---
        @{ T = 3; R = 'GTX 1660 (Ti|SUPER)' }
        @{ T = 3; R = 'GTX (1070|1080|980 Ti)|TITAN' }
        @{ T = 2; R = 'RTX (2050|3050)' }
        @{ T = 3; R = 'RTX' }                                      # every other RTX card
        @{ T = 2; R = 'GTX (970|980|1060|1650|1660)\b' }
        @{ T = 1; R = 'GTX (1630|1050|9[56]0|7\d0|6\d0)|GeForce (GT|MX) ?\d' }
        # --- AMD ---
        @{ T = 3; R = 'RX (5700|6[6-9]\d\d|7\d{3}|9\d{3})|Vega (56|64)|Radeon VII' }
        @{ T = 2; R = 'RX (470|480|570|580|590|5500|5600|6500)' }
        @{ T = 1; R = 'RX (460|550|560|6300|6400)|Radeon (R[579]|HD) ' }
        # --- Intel Arc (driver names include "(TM)") ---
        @{ T = 3; R = 'Arc(\(TM\))? (A7\d0|B\d{3})' }
        @{ T = 1; R = 'Arc(\(TM\))? A[35]\d0M|Arc(\(TM\))? Graphics' }   # laptop / integrated Arc
        @{ T = 2; R = 'Arc(\(TM\))? A[35]\d0' }
    )
    foreach ($r in $rules) {
        if ($n -match $r.R) { return [pscustomobject]@{ Tier = $r.T; Source = 'GPU model' } }
    }
    # Unknown model: fall back to VRAM size
    $t = if ($gpu.VramGB -lt 4) { 1 } elseif ($gpu.VramGB -lt 8) { 2 } else { 3 }
    [pscustomobject]@{ Tier = $t; Source = 'VRAM (model not recognized)' }
}

# -----------------------------------------------------------------------------
# Get-ProfileSettings
# Returns the PROFSAVE_profile graphics values for a tier. The preset favors
# visibility and frame rate (competitive play) over eye candy.
#   Quality values: 0 = Low, 1 = Medium, 2 = High, 3 = Ultra
#   AnisotropicFilter: 0 = 1x, 1 = 2x, 2 = 4x, 3 = 8x, 4 = 16x
# -----------------------------------------------------------------------------
function Get-ProfileSettings([int]$tier, [int]$threads) {
    # Shared by every tier
    $common = [ordered]@{
        'GstRender.OverallGraphicsQuality'  = '4'          # 4 = Custom preset
        'GstRender.AmbientOcclusion'        = '0'          # SSAO/HBAO off: expensive, no gameplay value
        'GstRender.AntiAliasingDeferred'    = '0'          # MSAA off: very costly in BF4's deferred renderer
        'GstRender.Enlighten'               = '0'          # dynamic global illumination off
        'GstRender.MotionBlur'              = '0.000000'
        'GstRender.MotionBlurEnabled'       = '0'
        'GstRender.PostProcessQuality'      = '0'          # less bloom/haze: enemies are easier to spot
        'GstRender.TransparentShadows'      = '0'
        'GstRender.UndergrowthQuality'      = '0'          # less grass hiding prone enemies
        'GstRender.VSyncEnabled'            = '0'          # V-Sync handled by the driver (or off)
        'GstRender.WeaponDOF'               = '0'          # no blur around the weapon when aiming
        'GstInput.HeadtrackingEnabled'      = '0'
        'GstInput.SpeechRecognitionEnabled' = '0'
    }
    switch ($tier) {
        # High: detail that improves target recognition stays on Ultra; supersampling replaces AA
        3 { $t = [ordered]@{
                'GstRender.TextureQuality'    = '3'
                'GstRender.MeshQuality'       = '3'
                'GstRender.TerrainQuality'    = '3'
                'GstRender.TextureFiltering'  = '3'
                'GstRender.AnisotropicFilter' = '4'
                'GstRender.EffectsQuality'    = '1'   # thinner smoke and explosions
                'GstRender.LightingQuality'   = '1'   # less sun glare
                'GstRender.ShadowQuality'     = '1'
                'GstRender.AntiAliasingPost'  = '0'
                'GstRender.ResolutionScale'   = '1.250000' } }   # render at 125% for a sharper image
        # Medium
        2 { $t = [ordered]@{
                'GstRender.TextureQuality'    = '2'
                'GstRender.MeshQuality'       = '2'
                'GstRender.TerrainQuality'    = '2'
                'GstRender.TextureFiltering'  = '2'
                'GstRender.AnisotropicFilter' = '4'
                'GstRender.EffectsQuality'    = '1'
                'GstRender.LightingQuality'   = '1'
                'GstRender.ShadowQuality'     = '1'
                'GstRender.AntiAliasingPost'  = '1'   # cheap FXAA to soften jagged edges
                'GstRender.ResolutionScale'   = '1.000000' } }
        # Low
        default { $t = [ordered]@{
                'GstRender.TextureQuality'    = '1'
                'GstRender.MeshQuality'       = '1'
                'GstRender.TerrainQuality'    = '1'
                'GstRender.TextureFiltering'  = '1'
                'GstRender.AnisotropicFilter' = '2'
                'GstRender.EffectsQuality'    = '0'
                'GstRender.LightingQuality'   = '0'
                'GstRender.ShadowQuality'     = '0'
                'GstRender.AntiAliasingPost'  = '1'
                'GstRender.ResolutionScale'   = '1.000000' } }
    }
    foreach ($k in $t.Keys) { $common[$k] = $t[$k] }

    # Weak CPU: mesh and terrain detail add draw calls, which load the CPU
    if ($threads -le 4) {
        if ([int]$common['GstRender.MeshQuality'] -gt 1)    { $common['GstRender.MeshQuality'] = '1' }
        if ([int]$common['GstRender.TerrainQuality'] -gt 1) { $common['GstRender.TerrainQuality'] = '1' }
    }
    $common
}

# -----------------------------------------------------------------------------
# Build-Profile
# Writes a new PROFSAVE_profile to $outPath. If the user already has a
# profile, it is used as the base so keybinds, mouse sensitivity, FOV, audio
# and resolution are preserved; only the keys in $settings are replaced.
# Without an existing profile, a graphics-only profile is created and the
# game fills in its own defaults for everything else.
# -----------------------------------------------------------------------------
function Build-Profile([string]$srcPath, $settings, [string]$outPath) {
    $lines = if ($srcPath -and (Test-Path -LiteralPath $srcPath)) { [IO.File]::ReadAllLines($srcPath) } else { @() }
    $seen = @{}; $changes = @(); $out = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lines) {
        # Each line is "Key Value"; \s+ also tolerates stray double spaces
        if ($l -match '^(\S+)\s+(.*)$' -and $settings.Contains($Matches[1])) {
            $k = $Matches[1]; $old = $Matches[2].Trim(); $new = $settings[$k]
            $seen[$k] = $true
            if ($old -ne $new) { $changes += ("{0}: {1} -> {2}" -f $k, $old, $new) }
            $out.Add("$k $new")
        } else {
            $out.Add($l)    # every other line is copied untouched
        }
    }
    # Append any tuned key that was missing from the original profile
    foreach ($k in $settings.Keys) {
        if (-not $seen[$k]) {
            $out.Add("$k $($settings[$k])")
            if ($lines.Count) { $changes += ("{0}: (new) -> {1}" -f $k, $settings[$k]) }
        }
    }
    # ASCII + CRLF line endings, same as the files the game writes
    [IO.File]::WriteAllLines($outPath, $out.ToArray(), [Text.Encoding]::ASCII)
    [pscustomobject]@{ Changes = $changes; Lines = $lines; FromExisting = [bool]$lines.Count }
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
function Main {
    $ErrorActionPreference = 'SilentlyContinue'
    $script    = $env:BF4CFG_SCRIPT
    $scriptDir = Split-Path -Parent $script

    # Everything printed through Say is also saved to README.txt in the output folder
    $log = New-Object System.Collections.Generic.List[string]
    function Say([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c; $log.Add($t) }

    Say ''
    Say '=== Battlefield 4 Optimizer (user.cfg + PROFSAVE_profile) ===' 'Cyan'
    Say ("Generated on {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm')) 'DarkGray'
    Say ''

    # --- Output folder: next to this script, or on the Desktop if that is read-only ---
    $outDir = Join-Path $scriptDir 'BF4_Optimized'
    [void](New-Item -ItemType Directory -Path $outDir -Force)
    if (-not (Test-Write $outDir)) {
        $outDir = Join-Path ([Environment]::GetFolderPath('Desktop')) 'BF4_Optimized'
        [void](New-Item -ItemType Directory -Path $outDir -Force)
    }

    # --- Hardware detection ---
    $cpus    = @(Get-CimInstance Win32_Processor)
    $cpuName = "$($cpus[0].Name)".Trim()
    $cores   = ($cpus | Measure-Object NumberOfCores -Sum).Sum              # summed for multi-socket systems
    $threads = ($cpus | Measure-Object NumberOfLogicalProcessors -Sum).Sum
    $ramGB   = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    $gpu     = Get-MainGpu
    # Highest current refresh rate reported by any adapter (covers hybrid-graphics laptops)
    $hz      = [int](@(Get-CimInstance Win32_VideoController) | Measure-Object CurrentRefreshRate -Maximum).Maximum
    $mons    = @(Get-MonitorInfo)
    # Laptop = has a battery or a portable chassis type
    $chassis = @((Get-CimInstance Win32_SystemEnclosure).ChassisTypes)
    $isLaptop = [bool](Get-CimInstance Win32_Battery) -or [bool]($chassis | Where-Object { $_ -in 8,9,10,11,12,14,18,21,31,32 })

    Say '--- Hardware ---' 'Cyan'
    Say ("CPU      : {0}  ({1} cores / {2} threads)" -f $cpuName, $cores, $threads)
    Say ("RAM      : {0} GB" -f $ramGB)
    Say ("GPU      : {0}  ({1} GB VRAM)" -f $gpu.Name, $gpu.VramGB)
    Say ("System   : {0}" -f $(if ($isLaptop) { 'Laptop' } else { 'Desktop' }))
    Say ("Display  : {0} Hz (current Windows refresh rate)" -f $hz)
    foreach ($m in $mons) {
        $tags = @()
        if ($m.FreeSync)       { $tags += 'FreeSync' }
        if ($m.HdmiVrr)        { $tags += 'HDMI VRR' }
        if ($m.DpAdaptiveSync) { $tags += 'DP Adaptive-Sync' }
        if ($m.NvidiaVsdb)     { $tags += 'G-Sync (hint)' }
        $range  = if ($m.MaxHz) { " | EDID range {0}-{1} Hz" -f $m.MinHz, $m.MaxHz } else { '' }
        $vrrTxt = if ($tags) { $tags -join ', ' } else { 'no VRR advertised in EDID' }
        Say ("Monitor  : {0}{1} | {2}" -f $m.Name, $range, $vrrTxt)
    }

    # Warn if Windows is running the monitor below its maximum refresh rate
    $edidMax = ($mons | Measure-Object MaxHz -Maximum).Maximum
    if ($edidMax -and $hz -and ($hz + 5) -lt $edidMax) {
        Say ("WARNING: the monitor supports up to {0} Hz but Windows is set to {1} Hz. Change it in Settings > Display > Advanced display." -f $edidMax, $hz) 'Yellow'
    }
    if (-not $hz -or $hz -lt 30) {
        $hz = [int](Read-Host 'Could not read the refresh rate. How many Hz is your display?')
        if ($hz -lt 30) { $hz = 60 }
    }

    # --- VRR: EDID detection, then user confirmation (the driver state can't be read) ---
    $vrrDetected = [bool]($mons | Where-Object { $_.FreeSync -or $_.HdmiVrr -or $_.DpAdaptiveSync -or $_.NvidiaVsdb })
    $def = if ($vrrDetected) { 'Y' } else { 'N' }
    Write-Host ''
    Write-Host ("G-Sync/FreeSync detected: {0}" -f $(if ($vrrDetected) { 'YES' } else { 'NO' })) -ForegroundColor Cyan
    $ans = Read-Host "Is G-Sync/FreeSync ENABLED in your graphics driver? [Y/N] (Enter = $def)"
    if (-not $ans) { $ans = $def }
    $vrr = $ans -match '^[yYsS]'
    Say ("G-Sync/FreeSync: {0}" -f $(if ($vrr) { 'enabled' } else { 'disabled' }))

    # --- user.cfg: frame cap and render queue ---
    $gt   = Get-GpuTier $gpu
    $tier = $gt.Tier
    $strong = $tier -ge 3 -and $threads -ge 8
    if ($vrr) {
        # Capping slightly below refresh keeps every frame inside the VRR window,
        # avoiding the jump to V-Sync latency or tearing at the top of the range
        $cap = $hz - 3
        $why = "VRR enabled: 3 FPS below $hz Hz so frames always stay inside the G-Sync/FreeSync range"
    } elseif ($isLaptop -or -not $strong) {
        # Matching refresh keeps frame times even and laptop temperatures in check
        $cap = $hz
        $why = "no VRR: matches the display refresh rate (stable frame times and temperatures)"
    } else {
        # Without VRR, rendering above refresh lowers input latency on a strong desktop
        $cap = [math]::Min($hz * 2, 300)
        $why = "no VRR, strong desktop: FPS above refresh rate lowers input latency"
    }
    # A 1-frame queue gives the lowest input lag; very weak CPUs stutter with it, so they get 2
    $ral = if ($threads -le 4) { 2 } else { 1 }
    $ralWhy = if ($ral -eq 2) { '4 threads or fewer: a 2-frame queue avoids FPS drops' } else { '1-frame queue = lowest input lag' }
    $cfg = @(
        'PerfOverlay.DrawFps 1',                 # on-screen FPS counter
        "GameTime.MaxVariableFps $cap",          # frame rate cap
        "RenderDevice.RenderAheadLimit $ral",    # frames the CPU may queue ahead of the GPU
        'RenderDevice.TripleBufferingEnable 0',
        'RenderDevice.VSyncEnable 0',
        'WorldRender.MotionBlurEnable 0'
    )
    $outCfg = Join-Path $outDir 'user.cfg'
    [IO.File]::WriteAllLines($outCfg, $cfg, [Text.Encoding]::ASCII)

    Say ''
    Say '--- user.cfg ---' 'Green'
    $cfg | ForEach-Object { Say "  $_" }
    Say "FPS cap      : $cap  -> $why"
    Say "Render queue : $ral  -> $ralWhy"

    # --- PROFSAVE_profile: graphics tier applied on top of the current profile ---
    $docs     = [Environment]::GetFolderPath('MyDocuments')   # also resolves OneDrive-redirected Documents
    $profDir  = Join-Path $docs 'Battlefield 4\settings'
    $profPath = Join-Path $profDir 'PROFSAVE_profile'
    $outProf  = Join-Path $outDir 'PROFSAVE_profile'
    $tierTxt  = @{ 1 = 'LOW'; 2 = 'MEDIUM'; 3 = 'HIGH' }[$tier]

    Say ''
    Say '--- PROFSAVE_profile ---' 'Green'
    Say "Graphics tier: $tierTxt  (based on: $($gt.Source))"
    if ($threads -le 4) { Say '4 threads or fewer: mesh and terrain quality capped at Medium.' }
    $res = Build-Profile $profPath (Get-ProfileSettings $tier $threads) $outProf
    if ($res.FromExisting) {
        Say 'Based on your current profile: keybinds, mouse, FOV, audio and resolution are preserved.'
        if ($res.Changes.Count) { Say 'Changes:'; $res.Changes | ForEach-Object { Say "  $_" } }
        else { Say 'Your current profile was already optimized; the generated file is identical.' }
        # Warn if the in-game refresh rate is lower than the display's
        $fr = $res.Lines | Where-Object { $_ -match '^GstRender\.FullscreenRefreshRate\s' } | Select-Object -First 1
        if ($fr -and $fr -match '([\d.]+)\s*$' -and [double]$Matches[1] -gt 0 -and [double]$Matches[1] -lt ($hz - 1)) {
            Say ("WARNING: the game is set to {0:N0} Hz but the display supports {1} Hz. Select {1} Hz in Options > Video." -f [double]$Matches[1], $hz) 'Yellow'
        }
    } else {
        Say 'No BF4 profile found on this PC: a graphics-only profile was created.' 'Yellow'
        Say 'Keybinds, mouse and resolution will use the game defaults.' 'Yellow'
    }

    # --- Where to put each file ---
    $gameDir = Find-Bf4 $scriptDir
    Say ''
    Say '=== WHERE TO APPLY ===' 'Cyan'
    Say "Generated files: $outDir"
    Say ''
    Say '1) user.cfg  ->  game install folder (the one that contains bf4.exe)'
    if ($gameDir) {
        Say "   Detected: $gameDir" 'Green'
    } else {
        Say '   Not detected. Common locations:' 'Yellow'
        Say '     C:\Program Files (x86)\Origin Games\Battlefield 4'
        Say '     C:\Program Files\EA Games\Battlefield 4'
        Say '     C:\Program Files (x86)\Steam\steamapps\common\Battlefield 4'
        Say '   (EA app / Steam: right-click the game > View files / Browse local files)'
    }
    Say ''
    Say '2) PROFSAVE_profile  ->  settings folder in Documents'
    Say "   $profDir" $(if (Test-Path -LiteralPath $profDir) { 'Green' } else { 'Yellow' })
    Say '   Copy it with the game CLOSED (BF4 rewrites this file when it exits).'
    Say '   Changing video options in-game later will overwrite these values.'
    Say ''
    Say '3) Graphics driver settings for bf4.exe:'
    if ($vrr -and $gpu.Name -match 'NVIDIA|GeForce|RTX|GTX') {
        Say '   - G-Sync on + V-Sync ON in the NVIDIA Control Panel (keep it off in-game)'
        Say '   - Low Latency Mode: On'
    } elseif ($vrr) {
        Say '   - FreeSync on; Wait for Vertical Refresh "Always on" in AMD Adrenalin (keep it off in-game)'
        Say '   - Radeon Anti-Lag: on'
    } else {
        Say '   - V-Sync off; Low Latency Mode On (NVIDIA) or Anti-Lag (AMD)'
    }
    Say '   - Power management: prefer maximum performance'

    # Save the full report next to the generated files
    [IO.File]::WriteAllLines((Join-Path $outDir 'README.txt'), $log.ToArray(), [Text.Encoding]::ASCII)

    # --- Optional: copy the files into place (default is No) ---
    Write-Host ''
    $ap = Read-Host 'Copy the files to those locations now? [Y/N] (Enter = N)'
    if ($ap -match '^[yYsS]') {
        # BF4 saves PROFSAVE_profile on exit, which would undo the changes
        while (Get-Process -Name bf4, bf4_x86 -ErrorAction SilentlyContinue) {
            Write-Host 'Battlefield 4 is running. Close the game and press Enter.' -ForegroundColor Yellow
            [void](Read-Host)
        }
        $stamp = Get-Date -Format yyyyMMdd_HHmmss

        # PROFSAVE_profile lives in Documents, so no admin rights are needed
        try {
            [void](New-Item -ItemType Directory -Path $profDir -Force)
            if (Test-Path -LiteralPath $profPath) { Copy-Item -LiteralPath $profPath -Destination "$profPath.bak_$stamp" -Force }
            Copy-Item -LiteralPath $outProf -Destination $profPath -Force -ErrorAction Stop
            Write-Host "PROFSAVE_profile applied (previous file saved as PROFSAVE_profile.bak_$stamp)" -ForegroundColor Green
        } catch { Write-Host "ERROR applying PROFSAVE_profile: $($_.Exception.Message)" -ForegroundColor Red }

        # user.cfg goes into the game folder, which may require admin rights
        if (-not $gameDir) {
            Write-Host 'user.cfg: game folder not detected. Copy it manually.' -ForegroundColor Yellow
        } else {
            $dst = Join-Path $gameDir 'user.cfg'
            if (Test-Write $gameDir) {
                if (Test-Path -LiteralPath $dst) { Copy-Item -LiteralPath $dst -Destination "$dst.bak_$stamp" -Force }
                Copy-Item -LiteralPath $outCfg -Destination $dst -Force
                Write-Host "user.cfg applied to $gameDir" -ForegroundColor Green
            } else {
                # Elevate only the copy itself, not the whole script (one UAC prompt)
                Write-Host 'The game folder requires administrator rights; Windows will ask for permission.' -ForegroundColor Yellow
                $q = { param($x) $x -replace "'", "''" }                 # escape single quotes in paths
                $dstQ = & $q $dst; $cfgQ = & $q $outCfg
                $cmd = "if (Test-Path -LiteralPath '$dstQ') { Copy-Item -LiteralPath '$dstQ' -Destination '$dstQ.bak_$stamp' -Force }; Copy-Item -LiteralPath '$cfgQ' -Destination '$dstQ' -Force"
                try {
                    $p = Start-Process powershell -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop `
                         -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $cmd
                    if (Test-Path -LiteralPath $dst) { Write-Host "user.cfg applied to $gameDir" -ForegroundColor Green }
                } catch {
                    Write-Host 'Permission denied. Copy user.cfg manually.' -ForegroundColor Yellow
                }
            }
        }
    } else {
        Write-Host 'Nothing was changed. Copy the files manually using the instructions above (also in README.txt).' -ForegroundColor Cyan
    }

    # Open the output folder in File Explorer
    Start-Process explorer.exe -ArgumentList "`"$outDir`""
}

Main
