<# : batch
@echo off
REM ---------------------------------------------------------------------------
REM  Battlefield 4 Optimizer - batch/PowerShell hybrid launcher.
REM  cmd.exe runs only these few lines; to PowerShell, this whole header is a
REM  block comment. The batch part passes this file's own path to
REM  Windows PowerShell, which then reads and runs the rest of the file.
REM  ExecutionPolicy Bypass applies to this process only; no system setting
REM  is changed. Sysnative is used when this is started from a 32-bit
REM  process, so the 64-bit PowerShell and registry view are always used.
REM ---------------------------------------------------------------------------
setlocal
set "BF4CFG_SCRIPT=%~f0"
set "BF4CFG_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "BF4CFG_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%BF4CFG_PS%" set "BF4CFG_PS=powershell"
"%BF4CFG_PS%" -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText($env:BF4CFG_SCRIPT))"
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
#  Backups can be restored by running the script again and choosing "Undo".
#
#  Nothing on the system is modified unless you answer "Y" at the end.
# =============================================================================

$AppVersion = '1.1.0'

# Latin-1 maps every byte to one character and back, so files read and
# written with it keep any non-ASCII byte exactly as it was.
$Latin1 = [Text.Encoding]::GetEncoding(28591)


# -----------------------------------------------------------------------------
# Parse-Edid
# Reads a monitor's raw EDID bytes and reports:
#   - the refresh range from the "Display Range Limits" descriptor
#   - variable refresh rate (VRR) hints: AMD FreeSync, HDMI 2.1 VRR,
#     DisplayPort Adaptive-Sync, a VRR-style range descriptor and an NVIDIA
#     vendor block (G-Sync hint)
# EDID only describes what the monitor advertises; it cannot tell whether
# VRR is actually enabled in the driver, which is why the user confirms it.
# -----------------------------------------------------------------------------
function Parse-Edid([byte[]]$e) {
    $r = [pscustomobject]@{ Name=''; MinHz=0; MaxHz=0; FreeSync=$false; HdmiVrr=$false; DpAdaptiveSync=$false; RangeVrr=$false; NvidiaVsdb=$false }
    if (-not $e -or $e.Length -lt 128) { return $r }

    # EDID 1.4: byte 24 bit 0 = continuous frequency (in 1.3 that bit meant something else)
    $continuous = $e[18] -eq 1 -and $e[19] -ge 4 -and ($e[24] -band 1)

    # Base block: the four 18-byte descriptors start at offset 54.
    # Tag 0xFD = Display Range Limits (min/max vertical refresh in Hz).
    for ($d = 54; $d -le 108; $d += 18) {
        if ($e[$d] -eq 0 -and $e[$d+1] -eq 0 -and $e[$d+3] -eq 0xFD) {
            $f = $e[$d+4]; $min = [int]$e[$d+5]; $max = [int]$e[$d+6]
            # Offset flags: bit 1 adds 255 to the max rate, bits 1+0 add 255 to both (for >255 Hz panels)
            if ($f -band 2) { $max += 255; if ($f -band 1) { $min += 255 } }
            $r.MinHz = $min; $r.MaxHz = $max
            # Most DisplayPort FreeSync / G-Sync Compatible monitors only advertise
            # VRR through this descriptor: "range limits only" (byte 10 = 1) on a
            # continuous-frequency display with a wide range. The 1.8x ratio keeps
            # ordinary 60 Hz panels (e.g. 50-75 Hz, 56-76 Hz) out. It is a hint.
            if ($continuous -and $e[$d+10] -eq 1 -and $min -gt 0 -and $max -ge ($min * 1.8)) { $r.RangeVrr = $true }
        }
    }

    # Extension blocks (byte 126 holds how many follow the base block)
    $n = [int]$e[126]
    for ($i = 1; $i -le $n; $i++) {
        $b = $i * 128
        if ($e.Length -lt $b + 128) { break }

        if ($e[$b] -eq 0x02) {
            # CTA-861 extension: walk the data block collection.
            $end = $b + [int]$e[$b+2]          # byte 2 = offset where detailed timings start
            if ($e[$b+2] -lt 4) { $end = $b + 4 }
            $p = $b + 4
            while ($p -lt $end) {
                $tag = ($e[$p] -shr 5) -band 7
                $len = $e[$p] -band 0x1F
                $oui = -1
                if ($tag -eq 3 -and $len -ge 3) {
                    # Vendor-Specific Data Block: the IEEE OUI identifies the vendor
                    $oui = [int]$e[$p+1] -bor ([int]$e[$p+2] -shl 8) -bor ([int]$e[$p+3] -shl 16)
                    if ($oui -eq 0x00001A) { $r.FreeSync = $true }      # AMD FreeSync block
                    if ($oui -eq 0x00044B) { $r.NvidiaVsdb = $true }    # NVIDIA block (G-Sync hint)
                }
                # HDMI Forum block: HF-VSDB (tag 3, OUI C4-5D-D8) or HF-SCDB
                # (tag 7, extended tag 0x79). Both use the same byte layout:
                # byte 9 bits 7:6 = VRRmax bits 9:8, byte 10 = VRRmax bits 7:0.
                $hf = ($oui -eq 0xC45DD8) -or ($tag -eq 7 -and $len -ge 1 -and $e[$p+1] -eq 0x79)
                if ($hf -and $len -ge 10) {
                    $vmax = (([int]$e[$p+9] -band 0xC0) -shl 2) -bor [int]$e[$p+10]
                    if ($vmax -gt 0) { $r.HdmiVrr = $true }
                }
                $p += $len + 1
            }
        }
        elseif ($e[$b] -eq 0x70) {
            # DisplayID extension: data blocks are [tag][revision][length][payload].
            # Tag 0x2B = Adaptive-Sync data block (DisplayID 2.1, DisplayPort VRR).
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
        $edid = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Enum\$inst\Device Parameters" -ErrorAction SilentlyContinue).EDID
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
    foreach ($k in @(Get-ChildItem -LiteralPath $key -ErrorAction SilentlyContinue)) {
        if ($k.PSChildName -notmatch '^\d{4}$') { continue }   # adapter subkeys are 0000, 0001, ...
        $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
        if (-not $p.DriverDesc) { continue }
        $v = $p.'HardwareInformation.qwMemorySize'             # 64-bit value (newer drivers)
        if (-not $v) {
            $m = $p.'HardwareInformation.MemorySize'           # 32-bit fallback (older drivers)
            if ($m -is [byte[]]) { if ($m.Length -ge 4) { $v = [BitConverter]::ToUInt32($m, 0) } }
            elseif ($m) { $v = $m }
        }
        $list += [pscustomobject]@{ Name = $p.DriverDesc; VramGB = [math]::Round([double]$v / 1GB, 1) }
    }

    # The class key can keep entries for cards that were removed long ago:
    # keep only adapters Windows currently reports (unless that leaves none)
    $present = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
    $live = @($list | Where-Object { $present.Name -contains $_.Name })
    if ($live) { $list = $live }

    if (-not $list) {
        # Last resort if the registry could not be read
        $list = @($present | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; VramGB = [math]::Round([double]$_.AdapterRAM / 1GB, 1) } })
    }
    # Ignore virtual / remote-desktop display adapters
    $list = @($list | Where-Object { $_.Name -notmatch 'Basic|Virtual|Parsec|Remote|Mirage|DisplayLink|Meta' })
    # Prefer NVIDIA/AMD/Arc, then the one with the most VRAM
    $list | Sort-Object @{ e = { if ($_.Name -match 'NVIDIA|GeForce|RTX|GTX|Radeon|AMD|Arc') { 1 } else { 0 } }; Descending = $true },
                        @{ e = 'VramGB'; Descending = $true } | Select-Object -First 1
}

# -----------------------------------------------------------------------------
# Get-GpuVendor
# Used for the driver advice at the end of the report.
# -----------------------------------------------------------------------------
function Get-GpuVendor([string]$name) {
    switch -Regex ($name) {
        'NVIDIA|GeForce|Quadro' { return 'NVIDIA' }
        'AMD|Radeon'            { return 'AMD' }
        'Intel|Arc'             { return 'Intel' }
    }
    'Other'
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
        $c += (Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue).'Install Dir'
    }
    # Steam (app ID 1238860)
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 1238860',
                   'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 1238860') {
        $c += (Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue).InstallLocation
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
# Elevation helpers
# Only individual file operations are elevated (one UAC prompt each), never
# the whole script. The command is passed Base64-encoded, so paths with
# spaces, quotes or accents survive intact, and it stops at the first error
# so a failed backup never leads to an overwrite.
# -----------------------------------------------------------------------------
function ConvertTo-PsLiteral([string]$s) {
    # Escape for a single-quoted PowerShell string (typographic quotes count too)
    $s -replace '([''\u2018\u2019\u201A\u201B])', '$1$1'
}

function Invoke-Elevated([string]$cmd) {
    $exe = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $exe)) { $exe = 'powershell' }
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("`$ErrorActionPreference = 'Stop'; $cmd"))
    try {
        Start-Process -FilePath $exe -Verb RunAs -Wait -WindowStyle Hidden -ErrorAction Stop `
            -ArgumentList "-NoProfile -NonInteractive -EncodedCommand $enc"
        $true
    } catch { $false }   # UAC prompt declined
}

function Test-SameFile([string]$a, [string]$b) {
    (Test-Path -LiteralPath $a) -and (Test-Path -LiteralPath $b) -and
    ((Get-FileHash -LiteralPath $a).Hash -eq (Get-FileHash -LiteralPath $b).Hash)
}

# -----------------------------------------------------------------------------
# Install-File
# Copies $src over $dst after saving the current $dst as "<name>.bak_<stamp>".
# If $dst did not exist, an EMPTY backup is written as a marker, so "Undo"
# knows to delete the file instead of restoring it.
# Returns 'ok', 'denied' (UAC declined) or 'error'. Success is verified by
# comparing file hashes, not just by checking that the file exists.
# -----------------------------------------------------------------------------
function Install-File([string]$src, [string]$dst, [string]$stamp) {
    $dir = Split-Path -Parent $dst
    $bak = "$dst.bak_$stamp"
    try {
        if (Test-Write $dir) {
            if (Test-Path -LiteralPath $dst) { Copy-Item -LiteralPath $dst -Destination $bak -Force -ErrorAction Stop }
            else { [IO.File]::WriteAllBytes($bak, [byte[]]@()) }
            Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop
        } else {
            $s = ConvertTo-PsLiteral $src; $d = ConvertTo-PsLiteral $dst; $k = ConvertTo-PsLiteral $bak
            $cmd = "if (Test-Path -LiteralPath '$d') { Copy-Item -LiteralPath '$d' -Destination '$k' -Force } " +
                   "else { [IO.File]::WriteAllBytes('$k', [byte[]]@()) }; " +
                   "Copy-Item -LiteralPath '$s' -Destination '$d' -Force"
            if (-not (Invoke-Elevated $cmd)) { return 'denied' }
        }
    } catch { return 'error' }
    if (Test-SameFile $src $dst) { 'ok' } else { 'error' }
}

# -----------------------------------------------------------------------------
# Get-LatestBackup / Restore-File
# Backups work as a stack: each "Undo" restores the newest backup of a file
# and removes it, so running "Undo" again goes one step further back.
# Restore-File returns 'restored', 'removed', 'none', 'denied' or 'error'.
# -----------------------------------------------------------------------------
function Get-LatestBackup([string]$path) {
    if (-not $path) { return $null }
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { return $null }
    Get-ChildItem -LiteralPath $dir -Filter ((Split-Path -Leaf $path) + '.bak_*') -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
}

function Restore-File([string]$path) {
    $bak = Get-LatestBackup $path
    if (-not $bak) { return 'none' }
    $empty = $bak.Length -eq 0          # marker: the file did not exist before
    $hash  = if (-not $empty) { (Get-FileHash -LiteralPath $bak.FullName).Hash }
    try {
        if (Test-Write (Split-Path -Parent $path)) {
            if ($empty) { if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction Stop } }
            else { Copy-Item -LiteralPath $bak.FullName -Destination $path -Force -ErrorAction Stop }
            Remove-Item -LiteralPath $bak.FullName -Force -ErrorAction Stop
        } else {
            $p = ConvertTo-PsLiteral $path; $k = ConvertTo-PsLiteral $bak.FullName
            $cmd = if ($empty) { "if (Test-Path -LiteralPath '$p') { Remove-Item -LiteralPath '$p' -Force }; Remove-Item -LiteralPath '$k' -Force" }
                   else        { "Copy-Item -LiteralPath '$k' -Destination '$p' -Force; Remove-Item -LiteralPath '$k' -Force" }
            if (-not (Invoke-Elevated $cmd)) { return 'denied' }
        }
    } catch { return 'error' }
    if ($empty) {
        if (Test-Path -LiteralPath $path) { 'error' } else { 'removed' }
    } elseif ((Test-Path -LiteralPath $path) -and (Get-FileHash -LiteralPath $path).Hash -eq $hash) {
        'restored'
    } else { 'error' }
}

# -----------------------------------------------------------------------------
# Wait-GameClosed
# BF4 saves PROFSAVE_profile when it exits, which would undo any change.
# -----------------------------------------------------------------------------
function Wait-GameClosed {
    while (Get-Process -Name bf4, bf4_x86 -ErrorAction SilentlyContinue) {
        Write-Host 'Battlefield 4 is running. Close the game and press Enter.' -ForegroundColor Yellow
        [void](Read-Host)
    }
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
    if (-not $gpu) { return [pscustomobject]@{ Tier = 1; Source = 'GPU not detected' } }
    $n = "$($gpu.Name)" -replace '\s+', ' '
    $rules = @(
        # --- Integrated graphics ---
        @{ T = 1; R = 'Intel.*(UHD|HD Graphics|Iris)' }
        @{ T = 3; R = 'Radeon(\(TM\))? 80[456]0S' }                               # Strix Halo
        @{ T = 2; R = 'Radeon(\(TM\))? (680|7[68]0|8[689]0)M\b' }                 # RDNA 2/3/3.5 iGPUs
        @{ T = 1; R = 'Radeon\(TM\) Graphics|Radeon Graphics\s*$|Vega \d+ Graphics|Radeon(\(TM\))? \d{3}M\b' }
        # --- NVIDIA (exceptions first, then general rules) ---
        @{ T = 3; R = 'GTX 1660 (Ti|SUPER)' }
        @{ T = 3; R = 'GTX (1070|1080|980 Ti)|TITAN' }
        @{ T = 2; R = 'RTX (2050|3050)' }
        @{ T = 3; R = 'RTX' }                                                    # every other RTX card
        @{ T = 2; R = 'GTX (970|980|1060|1650|1660)M?\b' }                       # M = laptop GTX 900 series
        @{ T = 1; R = 'GTX (1630|1050|9[56]\d|7\d0|6\d0)|GeForce (GT|MX) ?\d' }
        # --- AMD ---
        @{ T = 3; R = 'RX (5700|6[6-9]\d\d|7\d{3}|9\d{3})|Vega (56|64)|Radeon VII' }
        @{ T = 2; R = 'RX (470|480|570|580|590|5500|5600|6500)' }
        @{ T = 1; R = 'RX (460|550|560|6300|6400)|Radeon (R[579]|HD) ' }
        # --- Intel Arc (driver names include "(TM)") ---
        @{ T = 3; R = 'Arc(\(TM\))? (A7\d0|B\d{3})' }
        @{ T = 1; R = 'Arc(\(TM\))? A[35]\d0M|Arc(\(TM\))? Graphics' }           # laptop / integrated Arc
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
        'GstRender.OverallGraphicsQuality'  = '4'          # Custom preset (value as written by the game for "Custom")
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
# Test-SameValue
# "4" and "4.000000" are the same setting; the game writes many values as
# floats. PowerShell's -as conversion is culture-invariant ("." decimals).
# -----------------------------------------------------------------------------
function Test-SameValue([string]$a, [string]$b) {
    $x = $a -as [double]; $y = $b -as [double]
    if ($null -ne $x -and $null -ne $y) { return $x -eq $y }
    $a -eq $b
}

# -----------------------------------------------------------------------------
# Build-Profile
# Writes a new PROFSAVE_profile to $outPath. If the user already has a
# profile, it is used as the base so keybinds, mouse sensitivity, FOV, audio
# and resolution are preserved; only the keys in $settings are replaced.
# Without an existing profile, a graphics-only profile is created and the
# game fills in its own defaults for everything else.
# BF4 writes the file with LF line endings, so the original line ending and
# final newline are detected and kept: unchanged lines stay byte-identical.
# -----------------------------------------------------------------------------
function Build-Profile([string]$srcPath, $settings, [string]$outPath) {
    $raw   = if ($srcPath -and (Test-Path -LiteralPath $srcPath)) { [IO.File]::ReadAllText($srcPath, $Latin1) } else { '' }
    $nl    = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
    $endNl = $raw.EndsWith("`n") -or -not $raw
    $body  = $raw -replace '\r?\n\z', ''
    $lines = @(if ($body.Length) { $body -split '\r?\n' })
    $seen = @{}; $changes = @(); $added = @(); $out = New-Object System.Collections.Generic.List[string]
    $inv = [Globalization.CultureInfo]::InvariantCulture
    foreach ($l in $lines) {
        # Each line is "Key Value"; \s+ also tolerates stray double spaces
        if ($l -match '^(\S+)\s+(.*)$' -and $settings.Contains($Matches[1])) {
            $k = $Matches[1]; $old = $Matches[2].Trim(); $new = $settings[$k]
            $seen[$k] = $true
            if (Test-SameValue $old $new) {
                $out.Add($l)    # already at the tuned value: keep the line exactly as the game wrote it
            } else {
                # Match the game's number format: an integer replacing a float is written as a float
                if ($old -match '^-?\d+\.\d+$' -and $new -match '^-?\d+$') { $new = ([double]$new).ToString('F6', $inv) }
                $changes += ("{0}: {1} -> {2}" -f $k, $old, $new)
                $out.Add("$k $new")
            }
        } else {
            $out.Add($l)    # every other line is copied untouched
        }
    }
    # Append any tuned key that was missing from the original profile
    foreach ($k in $settings.Keys) {
        if (-not $seen[$k]) {
            $out.Add("$k $($settings[$k])")
            if ($lines.Count) { $added += ("{0} {1}" -f $k, $settings[$k]) }
        }
    }
    $text = ($out.ToArray() -join $nl) + $(if ($endNl) { $nl } else { '' })
    [IO.File]::WriteAllText($outPath, $text, $Latin1)
    [pscustomobject]@{ Changes = $changes; Added = $added; Lines = $lines; FromExisting = [bool]$lines.Count }
}

# -----------------------------------------------------------------------------
# Build-UserCfg
# Writes user.cfg to $outPath. Lines from an existing user.cfg are kept,
# except the commands this script manages, which are replaced.
# Returns how many of the user's own lines were kept.
# -----------------------------------------------------------------------------
function Build-UserCfg([string]$srcPath, [string[]]$cfg, [string]$outPath) {
    $managed = @($cfg | ForEach-Object { ($_ -split '\s+')[0] })
    $kept = @()
    if ($srcPath -and (Test-Path -LiteralPath $srcPath)) {
        $kept = @([IO.File]::ReadAllLines($srcPath, $Latin1) | Where-Object {
            $_.Trim() -and (($_.Trim() -split '\s+')[0] -notin $managed) })
    }
    [IO.File]::WriteAllLines($outPath, [string[]]($kept + $cfg), $Latin1)
    $kept.Count
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
function Main {
    $script    = $env:BF4CFG_SCRIPT
    $scriptDir = Split-Path -Parent $script

    # Everything printed through Say is also saved to README.txt in the output folder
    $log = New-Object System.Collections.Generic.List[string]
    function Say([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c; $log.Add($t) }

    Say ''
    Say "=== Battlefield 4 Optimizer v$AppVersion (user.cfg + PROFSAVE_profile) ===" 'Cyan'
    Say ("Generated on {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm')) 'DarkGray'
    Say ''

    # --- Locations ---
    $docs        = [Environment]::GetFolderPath('MyDocuments')   # also resolves OneDrive-redirected Documents
    if (-not $docs) { $docs = Join-Path $env:USERPROFILE 'Documents' }   # broken shell-folder registry entry
    $profDir     = Join-Path $docs 'Battlefield 4\settings'
    $profPath    = Join-Path $profDir 'PROFSAVE_profile'
    $gameDir     = Find-Bf4 $scriptDir
    $userCfgPath = if ($gameDir) { Join-Path $gameDir 'user.cfg' } else { $null }

    # --- Undo menu, shown only when backups from a previous run exist ---
    if ((Get-LatestBackup $profPath) -or (Get-LatestBackup $userCfgPath)) {
        Write-Host 'Backups from a previous run were found.' -ForegroundColor Cyan
        Write-Host '  1) Generate optimized settings'
        Write-Host '  2) Undo the last apply (restore the previous files)'
        if ((Read-Host 'Choose [1/2] (Enter = 1)') -eq '2') {
            Wait-GameClosed
            foreach ($f in @($profPath, $userCfgPath)) {
                if (-not $f) { continue }
                $name = Split-Path -Leaf $f
                switch (Restore-File $f) {
                    'restored' { Write-Host "$name restored from backup." -ForegroundColor Green }
                    'removed'  { Write-Host "$name removed (it did not exist before the optimizer)." -ForegroundColor Green }
                    'none'     { Write-Host "$name has no backup; left unchanged." -ForegroundColor DarkGray }
                    'denied'   { Write-Host "$name not restored: administrator permission was declined." -ForegroundColor Yellow }
                    default    { Write-Host "$name could not be restored. The .bak_ files are in $(Split-Path -Parent $f)" -ForegroundColor Red }
                }
            }
            return
        }
        Write-Host ''
    }

    # --- Output folder: next to this script, or on the Desktop if that is read-only ---
    $outDir = Join-Path $scriptDir 'BF4_Optimized'
    [void](New-Item -ItemType Directory -Path $outDir -Force -ErrorAction SilentlyContinue)
    if (-not (Test-Write $outDir)) {
        $outDir = Join-Path ([Environment]::GetFolderPath('Desktop')) 'BF4_Optimized'
        [void](New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop)
    }

    # --- Hardware detection ---
    $cpus    = @(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue)
    $cpuName = "$($cpus[0].Name)".Trim()
    $cores   = ($cpus | Measure-Object NumberOfCores -Sum).Sum              # summed for multi-socket systems
    $threads = ($cpus | Measure-Object NumberOfLogicalProcessors -Sum).Sum
    $ramGB   = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1GB)
    $gpu     = Get-MainGpu
    # Highest current refresh rate reported by any adapter (covers hybrid-graphics laptops)
    $hz      = [int](@(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue) | Measure-Object CurrentRefreshRate -Maximum).Maximum
    $mons    = @(Get-MonitorInfo)

    # Laptop = portable chassis type. The battery check is only a fallback for
    # an unknown chassis, because desktops with a USB-connected UPS also report one.
    $chassis  = @((Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes)
    $isLaptop = [bool]($chassis | Where-Object { $_ -in 8,9,10,14,30,31,32 })
    if (-not $isLaptop -and -not ($chassis | Where-Object { $_ -notin 1,2 })) {
        $isLaptop = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    }

    Say '--- Hardware ---' 'Cyan'
    Say ("CPU      : {0}  ({1} cores / {2} threads)" -f $cpuName, $cores, $threads)
    Say ("RAM      : {0} GB" -f $ramGB)
    if ($gpu) { Say ("GPU      : {0}  ({1} GB VRAM)" -f $gpu.Name, $gpu.VramGB) }
    else      { Say 'GPU      : NOT DETECTED - the Low preset will be used' 'Yellow' }
    Say ("System   : {0}" -f $(if ($isLaptop) { 'Laptop' } else { 'Desktop' }))
    Say ("Display  : {0} Hz (current Windows refresh rate)" -f $hz)
    foreach ($m in $mons) {
        $tags = @()
        if ($m.FreeSync)       { $tags += 'FreeSync' }
        if ($m.HdmiVrr)        { $tags += 'HDMI VRR' }
        if ($m.DpAdaptiveSync) { $tags += 'DP Adaptive-Sync' }
        if ($m.RangeVrr)       { $tags += 'VRR range (hint)' }
        if ($m.NvidiaVsdb)     { $tags += 'G-Sync (hint)' }
        $range  = if ($m.MaxHz) { " | EDID range {0}-{1} Hz" -f $m.MinHz, $m.MaxHz } else { '' }
        $vrrTxt = if ($tags) { $tags -join ', ' } else { 'no VRR advertised in EDID' }
        Say ("Monitor  : {0}{1} | {2}" -f $m.Name, $range, $vrrTxt)
    }

    # Warn if Windows runs the monitor below its maximum refresh rate. Only
    # reliable with one display: with several, the Hz cannot be matched to a monitor.
    if ($mons.Count -eq 1 -and $mons[0].MaxHz -and $hz -and ($hz + 5) -lt $mons[0].MaxHz) {
        Say ("WARNING: the monitor supports up to {0} Hz but Windows is set to {1} Hz. Change it in Settings > Display > Advanced display." -f $mons[0].MaxHz, $hz) 'Yellow'
    }
    if (-not $hz -or $hz -lt 30) {
        $hz = ((Read-Host 'Could not read the refresh rate. How many Hz is your display?') -replace '\D', '') -as [int]
        if ($hz -lt 30) { $hz = 60 }
    } elseif ($mons.Count -gt 1) {
        $v = ((Read-Host "Several displays found. Refresh rate (Hz) of the one you play on? (Enter = $hz)") -replace '\D', '') -as [int]
        if ($v -ge 30) { $hz = $v }
        Say ("Display used for the FPS cap: {0} Hz" -f $hz)
    }

    # In exclusive fullscreen BF4 switches the display to its own refresh rate,
    # which can be higher than the Windows desktop rate (laptops often run the
    # desktop at 60 Hz). The FPS cap then follows the rate the game really uses.
    # Only with one display, and never above what the monitor advertises.
    if ($mons.Count -le 1 -and (Test-Path -LiteralPath $profPath)) {
        $pl   = [IO.File]::ReadAllLines($profPath, $Latin1)
        $fsOn = [bool]($pl | Where-Object { $_ -match '^GstRender\.FullscreenEnabled\s+1\s*$' })
        $fs   = $pl | Where-Object { $_ -match '^GstRender\.FullscreenRefreshRate\s' } | Select-Object -First 1
        $fsHz = if ($fs -match '([\d.]+)\s*$') { [int][math]::Round(($Matches[1] -as [double])) } else { 0 }
        $fits = -not $mons.Count -or -not $mons[0].MaxHz -or $fsHz -le ($mons[0].MaxHz + 1)
        if ($fsOn -and $fsHz -gt ($hz + 1) -and $fits) {
            Say ("Game fullscreen: {0} Hz (Windows desktop: {1} Hz); {0} Hz is used for the FPS cap." -f $fsHz, $hz)
            $hz = $fsHz
        }
    }

    # --- VRR: EDID detection, then user confirmation (the driver state can't be read) ---
    $vrrDetected = [bool]($mons | Where-Object { $_.FreeSync -or $_.HdmiVrr -or $_.DpAdaptiveSync -or $_.RangeVrr -or $_.NvidiaVsdb })
    $def = if ($vrrDetected) { 'Y' } else { 'N' }
    Write-Host ''
    Write-Host ("G-Sync/FreeSync detected: {0}" -f $(if ($vrrDetected) { 'YES' } else { 'NO' })) -ForegroundColor Cyan
    $ans = Read-Host "Is G-Sync/FreeSync ENABLED in your graphics driver? [Y/N] (Enter = $def)"
    if (-not $ans) { $ans = $def }
    $vrr = $ans -match '^[yYsS]'
    Say ("G-Sync/FreeSync: {0}" -f $(if ($vrr) { 'enabled' } else { 'disabled' }))

    # --- user.cfg: frame cap and render queue ---
    $gt     = Get-GpuTier $gpu
    $tier   = $gt.Tier
    $strong = $tier -ge 3 -and $threads -ge 8
    if ($vrr) {
        # Capping below refresh keeps every frame inside the VRR window. The gap
        # grows with refresh rate (frame-time variance matters more at high Hz):
        # 60 -> 57, 144 -> 138, 165 -> 157, 240 -> 224
        $gap = [math]::Max(3, [int][math]::Ceiling($hz * $hz / 3600))
        $cap = $hz - $gap
        $why = "VRR enabled: $gap FPS below $hz Hz so frames always stay inside the G-Sync/FreeSync range"
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
    $keptCfg = Build-UserCfg $userCfgPath $cfg $outCfg

    Say ''
    Say '--- user.cfg ---' 'Green'
    $cfg | ForEach-Object { Say "  $_" }
    if ($keptCfg) { Say ("Kept {0} line(s) from your existing user.cfg." -f $keptCfg) }
    Say "FPS cap      : $cap  -> $why"
    Say "Render queue : $ral  -> $ralWhy"

    # --- PROFSAVE_profile: graphics tier applied on top of the current profile ---
    $outProf = Join-Path $outDir 'PROFSAVE_profile'
    $tierTxt = @{ 1 = 'LOW'; 2 = 'MEDIUM'; 3 = 'HIGH' }[$tier]

    Say ''
    Say '--- PROFSAVE_profile ---' 'Green'
    Say "Graphics tier: $tierTxt  (based on: $($gt.Source))"
    if ($threads -le 4) { Say '4 threads or fewer: mesh and terrain quality capped at Medium.' }
    $res = Build-Profile $profPath (Get-ProfileSettings $tier $threads) $outProf
    if ($res.FromExisting) {
        Say 'Based on your current profile: keybinds, mouse, FOV, audio and resolution are preserved.'
        if ($res.Changes.Count) { Say 'Changes:'; $res.Changes | ForEach-Object { Say "  $_" } }
        if ($res.Added.Count)   { Say 'Added (not present in your current profile):'; $res.Added | ForEach-Object { Say "  $_" } }
        if (-not $res.Changes.Count -and -not $res.Added.Count) {
            Say 'Your current profile was already optimized; the generated file is identical.'
        }
        # Warn if the in-game refresh rate is lower than the display's
        $fr = $res.Lines | Where-Object { $_ -match '^GstRender\.FullscreenRefreshRate\s' } | Select-Object -First 1
        $frHz = if ($fr -match '([\d.]+)\s*$') { $Matches[1] -as [double] } else { $null }
        if ($frHz -gt 0 -and $frHz -lt ($hz - 1)) {
            Say ("WARNING: the game is set to {0:N0} Hz but the display supports {1} Hz. Select {1} Hz in Options > Video." -f $frHz, $hz) 'Yellow'
        }
    } else {
        Say 'No BF4 profile found on this PC: a graphics-only profile was created.' 'Yellow'
        Say 'Keybinds, mouse and resolution will use the game defaults.' 'Yellow'
    }

    # --- Where to put each file ---
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
    switch (Get-GpuVendor $gpu.Name) {
        'NVIDIA' {
            if ($vrr) { Say '   - NVIDIA Control Panel: G-Sync on + V-Sync ON (keep V-Sync off in-game)' }
            else      { Say '   - NVIDIA Control Panel: V-Sync off' }
            Say '   - Low Latency Mode: On'
        }
        'AMD' {
            if ($vrr) { Say '   - AMD Adrenalin: FreeSync on + Wait for Vertical Refresh "Always on" (keep V-Sync off in-game)' }
            else      { Say '   - AMD Adrenalin: Wait for Vertical Refresh off' }
            Say '   - Radeon Anti-Lag: on'
        }
        'Intel' {
            if ($vrr) { Say '   - Intel Graphics Software / Arc Control: Adaptive Sync on (keep V-Sync off in-game)' }
            else      { Say '   - Intel Graphics Software / Arc Control: V-Sync off' }
            Say '   - Low Latency: on (if your driver offers it)'
        }
        default { Say '   - V-Sync off in the driver; turn on its low-latency option if it has one' }
    }
    Say '   - Power management: prefer maximum performance'

    # Save the full report next to the generated files (UTF-8 keeps accented paths readable)
    [IO.File]::WriteAllLines((Join-Path $outDir 'README.txt'), $log.ToArray(), (New-Object System.Text.UTF8Encoding $true))

    # --- Optional: copy the files into place (default is No) ---
    Write-Host ''
    $ap = Read-Host 'Copy the files to those locations now? [Y/N] (Enter = N)'
    if ($ap -match '^[yYsS]') {
        Wait-GameClosed
        $stamp = Get-Date -Format yyyyMMdd_HHmmss

        # PROFSAVE_profile lives in Documents, so no admin rights are needed
        [void](New-Item -ItemType Directory -Path $profDir -Force -ErrorAction SilentlyContinue)
        if ((Install-File $outProf $profPath $stamp) -eq 'ok') {
            Write-Host "PROFSAVE_profile applied (previous file saved as PROFSAVE_profile.bak_$stamp)" -ForegroundColor Green
        } else {
            Write-Host "ERROR: PROFSAVE_profile could not be applied. Copy it manually to $profDir" -ForegroundColor Red
        }

        # user.cfg goes into the game folder, which may require admin rights
        if (-not $gameDir) {
            Write-Host 'user.cfg: game folder not detected. Copy it manually.' -ForegroundColor Yellow
        } else {
            if (-not (Test-Write $gameDir)) {
                Write-Host 'The game folder requires administrator rights; Windows will ask for permission.' -ForegroundColor Yellow
            }
            switch (Install-File $outCfg $userCfgPath $stamp) {
                'ok'     { Write-Host "user.cfg applied to $gameDir (previous file saved as user.cfg.bak_$stamp)" -ForegroundColor Green }
                'denied' { Write-Host 'Permission declined. Copy user.cfg manually.' -ForegroundColor Yellow }
                default  { Write-Host 'ERROR: user.cfg could not be applied (an antivirus or Controlled Folder Access may be blocking the game folder). Copy it manually.' -ForegroundColor Red }
            }
        }
        Write-Host 'To undo, run this script again and choose "Undo".' -ForegroundColor DarkGray
    } else {
        Write-Host 'Nothing was changed. Copy the files manually using the instructions above (also in README.txt).' -ForegroundColor Cyan
    }

    # Open the output folder in File Explorer
    Start-Process explorer.exe -ArgumentList "`"$outDir`""
}

# Any unexpected error is shown instead of silently producing wrong files
try {
    Main
} catch {
    Write-Host ''
    Write-Host ("UNEXPECTED ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host ("Line {0}: {1}" -f $_.InvocationInfo.ScriptLineNumber, "$($_.InvocationInfo.Line)".Trim()) -ForegroundColor DarkGray
    Write-Host 'Please report this on GitHub together with the text above.' -ForegroundColor DarkGray
}
