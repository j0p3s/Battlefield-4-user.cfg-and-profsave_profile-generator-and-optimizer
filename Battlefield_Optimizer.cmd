<# : batch
@echo off
REM ---------------------------------------------------------------------------
REM  Battlefield Optimizer - batch/PowerShell hybrid launcher.
REM  cmd.exe runs only these few lines; to PowerShell, this whole header is a
REM  block comment. The batch part passes this file's own path to
REM  Windows PowerShell, which then reads and runs the rest of the file.
REM  ExecutionPolicy Bypass applies to this process only; no system setting
REM  is changed. Sysnative is used when this is started from a 32-bit
REM  process, so the 64-bit PowerShell and registry view are always used.
REM ---------------------------------------------------------------------------
setlocal
set "BFCFG_SCRIPT=%~f0"
set "BFCFG_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "BFCFG_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%BFCFG_PS%" set "BFCFG_PS=powershell"
"%BFCFG_PS%" -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText($env:BFCFG_SCRIPT))"
echo.
pause
exit /b
#>

# =============================================================================
#  Battlefield Optimizer
#
#  One script for Battlefield 4, Battlefield 1, Battlefield V and Battlefield 6.
#  Pick a game from the menu; the script detects CPU, GPU, VRAM, RAM, display
#  refresh rate, G-Sync/FreeSync support and laptop vs. desktop, then
#  generates a tuned user.cfg and PROFSAVE_profile for that game in a
#  "<game>_Optimized" folder next to this file. It explains where each file
#  goes and, only if you confirm, copies them into place (with backups).
#  Backups can be restored by running the script again and choosing "Undo".
#
#  Each game keeps its own tuning rules (GPU tiers, graphics values, FPS cap
#  and user.cfg contents); only the shared plumbing is common.
#  Nothing on the system is modified unless you answer "Y" at the end.
# =============================================================================

$AppVersion = '2.0.0'

# Latin-1 maps every byte to one character and back, so files read and
# written with it keep any non-ASCII byte exactly as it was.
$Latin1 = [Text.Encoding]::GetEncoding(28591)
$Invariant = [Globalization.CultureInfo]::InvariantCulture


# =============================================================================
#  GAME DEFINITIONS
#  Everything that differs between games, apart from the tuning functions
#  further down (Get-GpuTier*, Get-ProfileSettings*).
#    Procs        process names checked before files are copied
#    RegName      EA app / Origin registry key name
#    SteamId      Steam app ID (uninstall registry key)
#    Defaults     absolute install folders to try (BF4, BF1)
#    DriveRel     install folders tried on every fixed drive (BF V, BF6)
#    ProfileMode  'fixed'  = Documents\<game>\settings\PROFSAVE_profile
#                 'search' = that folder or a launcher subfolder (steam/ea/epic)
#    NeedProfile  $true: no profile is generated when the game never ran,
#                 because one built from scratch would wipe HUD/audio/keybinds
#    Eol          'keep' = keep the profile's own line endings
#                 'crlf' = write Windows line endings (BF1)
# =============================================================================
$Games = [ordered]@{
    '1' = @{
        Id = 'bf4'; Name = 'Battlefield 4'; Short = 'BF4'; Exe = 'bf4.exe'
        Procs = @('bf4', 'bf4_x86'); RegName = 'Battlefield 4'; SteamId = 1238860
        Defaults = @("${env:ProgramFiles(x86)}\Origin Games\Battlefield 4",
                     "$env:ProgramFiles\EA Games\Battlefield 4",
                     "${env:ProgramFiles(x86)}\Steam\steamapps\common\Battlefield 4")
        DriveRel = @()
        ProfileMode = 'fixed'; NeedProfile = $false; Eol = 'keep'
        ShowPaths = @('C:\Program Files (x86)\Origin Games\Battlefield 4',
                      'C:\Program Files\EA Games\Battlefield 4',
                      'C:\Program Files (x86)\Steam\steamapps\common\Battlefield 4')
        FolderHint = '(EA app / Steam: right-click the game > View files / Browse local files)'
    }
    '2' = @{
        Id = 'bf1'; Name = 'Battlefield 1'; Short = 'BF1'; Exe = 'bf1.exe'
        Procs = @('bf1'); RegName = 'Battlefield 1'; SteamId = 1238840
        Defaults = @("${env:ProgramFiles(x86)}\Origin Games\Battlefield 1",
                     "$env:ProgramFiles\EA Games\Battlefield 1",
                     "${env:ProgramFiles(x86)}\Steam\steamapps\common\Battlefield 1")
        DriveRel = @()
        ProfileMode = 'fixed'; NeedProfile = $false; Eol = 'crlf'
        ShowPaths = @('C:\Program Files (x86)\Origin Games\Battlefield 1',
                      'C:\Program Files\EA Games\Battlefield 1',
                      'C:\Program Files (x86)\Steam\steamapps\common\Battlefield 1')
        FolderHint = '(EA app / Steam: right-click the game > View files / Browse local files)'
    }
    '3' = @{
        Id = 'bfv'; Name = 'Battlefield V'; Short = 'BFV'; Exe = 'bfv.exe'
        Procs = @('bfv'); RegName = 'Battlefield V'; SteamId = 1238810
        Defaults = @()
        DriveRel = @('Program Files\EA Games\Battlefield V', 'EA Games\Battlefield V',
                     'Program Files (x86)\Steam\steamapps\common\Battlefield V', 'SteamLibrary\steamapps\common\Battlefield V',
                     'Steam\steamapps\common\Battlefield V', 'Program Files (x86)\Origin Games\Battlefield V',
                     'Origin Games\Battlefield V', 'Program Files\Epic Games\Battlefield V')
        ProfileMode = 'search'; NeedProfile = $true; Eol = 'keep'
        ShowPaths = @('C:\Program Files (x86)\Origin Games\Battlefield V',
                      'C:\Program Files\EA Games\Battlefield V',
                      'C:\Program Files (x86)\Steam\steamapps\common\Battlefield V')
        FolderHint = '(EA app: Manage > View properties > Open folder / Steam: Manage > Browse local files)'
    }
    '4' = @{
        Id = 'bf6'; Name = 'Battlefield 6'; Short = 'BF6'; Exe = 'bf6.exe'
        Procs = @('bf6', 'bf6event'); RegName = 'Battlefield 6'; SteamId = 2807960
        Defaults = @()
        DriveRel = @('Program Files\EA Games\Battlefield 6', 'EA Games\Battlefield 6',
                     'Program Files (x86)\Steam\steamapps\common\Battlefield 6', 'SteamLibrary\steamapps\common\Battlefield 6',
                     'Steam\steamapps\common\Battlefield 6', 'Program Files\Epic Games\Battlefield6',
                     'Program Files\Epic Games\Battlefield 6', 'Epic Games\Battlefield6')
        ProfileMode = 'search'; NeedProfile = $true; Eol = 'keep'
        ShowPaths = @('C:\Program Files\EA Games\Battlefield 6',
                      'C:\Program Files (x86)\Steam\steamapps\common\Battlefield 6')
        FolderHint = '(EA app: Manage > View properties > Open folder / Steam: Manage > Browse local files)'
    }
}


# =============================================================================
#  SHARED: HARDWARE DETECTION
# =============================================================================

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
# VramExact is $false when only the capped WMI value was available.
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
        $list += [pscustomobject]@{ Name = $p.DriverDesc; VramGB = [math]::Round([double]$v / 1GB, 1); VramExact = $true }
    }

    # The class key can keep entries for cards that were removed long ago:
    # keep only adapters Windows currently reports (unless that leaves none)
    $present = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
    $live = @($list | Where-Object { $present.Name -contains $_.Name })
    if ($live) { $list = $live }

    if (-not $list) {
        # Last resort if the registry could not be read
        # (AdapterRAM is 32-bit: it saturates at 4 GB, so a full 4 GB only means "4 GB or more")
        $list = @($present | ForEach-Object {
            [pscustomobject]@{ Name = $_.Name; VramGB = [math]::Round([double]$_.AdapterRAM / 1GB, 1)
                               VramExact = ([double]$_.AdapterRAM -lt (4GB - 16MB)) } })
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
# Get-Hardware
# Detects the hardware once per session; every game reuses the result.
# -----------------------------------------------------------------------------
function Get-Hardware {
    $cpus    = @(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue)
    $hw = [pscustomobject]@{
        CpuName  = "$($cpus[0].Name)".Trim()
        Cores    = [int]($cpus | Measure-Object NumberOfCores -Sum).Sum              # summed for multi-socket systems
        Threads  = [int]($cpus | Measure-Object NumberOfLogicalProcessors -Sum).Sum
        RamGB    = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1GB)
        Gpu      = Get-MainGpu
        # Highest current refresh rate reported by any adapter (covers hybrid-graphics laptops)
        Hz       = [int](@(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue) | Measure-Object CurrentRefreshRate -Maximum).Maximum
        Mons     = @(Get-MonitorInfo)
        IsLaptop = $false
        # Answers to the display questions, asked once and reused for every game
        HzAnswer  = $null
        VrrAnswer = $null
    }
    # Laptop = portable chassis type. The battery check is only a fallback for
    # an unknown chassis, because desktops with a USB-connected UPS also report one.
    $chassis = @((Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes)
    $hw.IsLaptop = [bool]($chassis | Where-Object { $_ -in 8,9,10,14,30,31,32 })
    if (-not $hw.IsLaptop -and -not ($chassis | Where-Object { $_ -notin 1,2 })) {
        $hw.IsLaptop = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    }
    $hw
}


# =============================================================================
#  SHARED: GAME AND FILE LOCATIONS
# =============================================================================

# -----------------------------------------------------------------------------
# Find-Game
# Looks for the folder that contains the game's .exe: this script's folder
# first, then EA app/Origin and Steam registry entries, then the default
# install folders (and, for BF V and BF6, the usual library folders on every
# fixed drive, since EA app, Steam and Epic libraries are often on D:, E:...).
# -----------------------------------------------------------------------------
function Find-Game($g, [string]$scriptDir) {
    $c = @($scriptDir)
    # Origin / EA app
    foreach ($k in "HKLM:\SOFTWARE\WOW6432Node\EA Games\$($g.RegName)", "HKLM:\SOFTWARE\EA Games\$($g.RegName)") {
        $c += (Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue).'Install Dir'
    }
    # Steam
    foreach ($k in "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App $($g.SteamId)",
                   "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App $($g.SteamId)") {
        $c += (Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue).InstallLocation
    }
    # Default install locations
    $c += $g.Defaults
    if ($g.DriveRel.Count) {
        foreach ($drv in @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady })) {
            foreach ($r in $g.DriveRel) { $c += Join-Path $drv.RootDirectory.FullName $r }
        }
    }
    foreach ($d in $c) {
        if ($d -and (Test-Path -LiteralPath (Join-Path $d $g.Exe))) { return (Resolve-Path -LiteralPath $d).Path }
    }
    $null
}

# -----------------------------------------------------------------------------
# Find-GameProfile
# BF V and BF6 keep PROFSAVE_profile either directly in Documents\<game>\settings
# or in a per-launcher subfolder (steam, ea, epic). The subfolder that matches
# where the game is installed wins; otherwise the most recently saved profile.
# Returns $null when the game has never been started on this PC.
# -----------------------------------------------------------------------------
function Find-GameProfile([string]$settingsDir, [string]$gameDir) {
    if (-not (Test-Path -LiteralPath $settingsDir)) { return $null }
    $cand = @(Join-Path $settingsDir 'PROFSAVE_profile') +
            @(Get-ChildItem -LiteralPath $settingsDir -Directory -ErrorAction SilentlyContinue |
              ForEach-Object { Join-Path $_.FullName 'PROFSAVE_profile' })
    $found = @($cand | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | ForEach-Object { Get-Item -LiteralPath $_ })
    if (-not $found) { return $null }
    $pref = if ($gameDir -match 'steamapps') { 'steam' } elseif ($gameDir -match 'Epic Games') { 'epic' } elseif ($gameDir) { 'ea' } else { '' }
    $match = @($found | Where-Object { $pref -and $_.Directory.Name -eq $pref })
    if ($match) { return $match[0].FullName }
    ($found | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
}

# -----------------------------------------------------------------------------
# Get-DocsFolder
# Documents folder, also when it is redirected to OneDrive.
# -----------------------------------------------------------------------------
function Get-DocsFolder {
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs) { $docs = Join-Path $env:USERPROFILE 'Documents' }   # broken shell-folder registry entry
    $docs
}

# -----------------------------------------------------------------------------
# Get-GameLocations
# Game folder, settings folder, PROFSAVE_profile and user.cfg paths.
# ProfPath is $null for BF V / BF6 when the game never ran on this PC.
# -----------------------------------------------------------------------------
function Get-GameLocations($g, [string]$scriptDir) {
    $settingsDir = Join-Path (Get-DocsFolder) "$($g.Name)\settings"
    $gameDir     = Find-Game $g $scriptDir
    $profPath    = if ($g.ProfileMode -eq 'fixed') { Join-Path $settingsDir 'PROFSAVE_profile' }
                   else { Find-GameProfile $settingsDir $gameDir }
    [pscustomobject]@{
        SettingsDir = $settingsDir
        GameDir     = $gameDir
        ProfPath    = $profPath
        UserCfgPath = if ($gameDir) { Join-Path $gameDir 'user.cfg' } else { $null }
    }
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


# =============================================================================
#  SHARED: INSTALL, BACKUP AND UNDO
# =============================================================================

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
# Every game saves PROFSAVE_profile when it exits, which would undo any change.
# -----------------------------------------------------------------------------
function Wait-GameClosed($g) {
    while (Get-Process -Name $g.Procs -ErrorAction SilentlyContinue) {
        Write-Host "$($g.Name) is running. Close the game and press Enter." -ForegroundColor Yellow
        [void](Read-Host)
    }
}


# =============================================================================
#  SHARED: FILE BUILDERS
# =============================================================================

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
# profile, it is used as the base so keybinds, mouse sensitivity, FOV, HUD,
# audio and resolution are preserved; only the keys in $settings are replaced.
# Without an existing profile (BF4, BF1), a graphics-only profile is created
# and the game fills in its own defaults for everything else.
#   $eol 'keep': the original line ending and final newline are kept, so
#                unchanged lines stay byte-identical (BF4, BF V, BF6)
#   $eol 'crlf': Windows line endings, as BF1 writes them
# -----------------------------------------------------------------------------
function Build-Profile([string]$srcPath, $settings, [string]$outPath, [string]$eol = 'keep') {
    $exists = $srcPath -and (Test-Path -LiteralPath $srcPath)
    if ($eol -eq 'crlf') {
        $lines = @(if ($exists) { [IO.File]::ReadAllLines($srcPath, $Latin1) })
    } else {
        $raw   = if ($exists) { [IO.File]::ReadAllText($srcPath, $Latin1) } else { '' }
        $nl    = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
        $endNl = $raw.EndsWith("`n") -or -not $raw
        $body  = $raw -replace '\r?\n\z', ''
        $lines = @(if ($body.Length) { $body -split '\r?\n' })
    }

    $seen = @{}; $changes = @(); $added = @(); $out = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lines) {
        # Each line is "Key Value"; \s+ also tolerates stray double spaces
        if ($l -match '^(\S+)\s+(.*)$' -and $settings.Contains($Matches[1])) {
            $k = $Matches[1]; $old = $Matches[2].Trim(); $new = $settings[$k]
            $seen[$k] = $true
            if (Test-SameValue $old $new) {
                $out.Add($l)    # already at the tuned value: keep the line exactly as the game wrote it
            } else {
                # Match the game's number format: an integer replacing a float is written as a float
                if ($old -match '^-?\d+\.\d+$' -and $new -match '^-?\d+$') { $new = ([double]$new).ToString('F6', $Invariant) }
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
    if ($eol -eq 'crlf') {
        [IO.File]::WriteAllLines($outPath, $out.ToArray(), $Latin1)
    } else {
        $text = ($out.ToArray() -join $nl) + $(if ($endNl) { $nl } else { '' })
        [IO.File]::WriteAllText($outPath, $text, $Latin1)
    }
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


# =============================================================================
#  PER-GAME TUNING: GPU TIERS
# =============================================================================

# -----------------------------------------------------------------------------
# Get-GpuTierClassic  (Battlefield 4, Battlefield 1, Battlefield V)
# Maps the GPU MODEL to a graphics tier based on real-world performance in
# these games (VRAM alone is misleading, e.g. a 4 GB GT 1030 is still a very
# slow card).
#   1 = Low, 2 = Medium, 3 = High
# Rules are evaluated top to bottom; the first match wins, so exceptions are
# listed before the broader patterns. Unknown models fall back to VRAM.
# -----------------------------------------------------------------------------
function Get-GpuTierClassic($gpu) {
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
# Get-GpuTierBf6
# Maps the GPU MODEL to a graphics tier for BF6, which is far heavier than
# the older games. Anchored on the official specs: minimum (1080p ~30 FPS low)
# is RTX 2060 / RX 5600 XT / Arc A380, recommended (1440p 60 FPS high) is
# RTX 3060 Ti / RX 6700 XT / Arc B580.
#   1 = Low     minimum-spec class and below
#   2 = Medium  between minimum and recommended
#   3 = High    recommended class and above
# -----------------------------------------------------------------------------
function Get-GpuTierBf6($gpu) {
    if (-not $gpu) { return [pscustomobject]@{ Tier = 1; Source = 'GPU not detected' } }
    $n = "$($gpu.Name)" -replace '\s+', ' '
    $rules = @(
        # --- Integrated graphics ---
        @{ T = 2; R = 'Radeon(\(TM\))? 80[456]0S' }                               # Strix Halo
        @{ T = 1; R = 'Intel.*(UHD|HD Graphics|Iris)' }
        @{ T = 1; R = 'Radeon\(TM\) Graphics|Radeon Graphics\s*$|Vega \d+ Graphics|Radeon(\(TM\))? \d{3}M\b' }
        # --- NVIDIA (exceptions first, then general rules) ---
        @{ T = 3; R = 'RTX 3060 Ti|RTX 4060(?! Laptop)' }                        # desktop 3060 Ti, 4060, 4060 Ti
        @{ T = 1; R = 'RTX (2050|3050)|RTX 2060(?! SUPER)' }
        @{ T = 2; R = 'RTX (2060|2070|3060|4050|4060|5050)' }                    # incl. laptop 4050/4060
        @{ T = 3; R = 'RTX' }                                                    # 2080 and up, 3070 and up, 40/50 series
        @{ T = 2; R = 'GTX 1080 Ti|TITAN (Xp|V)\b' }
        @{ T = 1; R = 'GTX|GeForce (GT|MX) ?\d' }
        # --- AMD (laptop chips first) ---
        @{ T = 2; R = 'RX (6[678]00S|7[67]00S|6600M|76\d\dM)' }
        @{ T = 3; R = 'RX (6[7-9]\d\d|7[7-9]\d\d|9\d{3})' }                     # 6700 XT+, 7700 XT+, 9000 series
        @{ T = 2; R = 'RX (5700|66\d\d|76\d\d)|Radeon VII' }
        @{ T = 1; R = 'RX \d{3,4}|Vega (56|64)|Radeon (R[579]|HD) ' }
        # --- Intel Arc (driver names include "(TM)") ---
        @{ T = 3; R = 'Arc(\(TM\))? B580' }
        @{ T = 2; R = 'Arc(\(TM\))? (A7[57]0|A580|B570)' }
        @{ T = 1; R = 'Arc' }                                                    # A3x0, laptop A5x0M, integrated Arc
    )
    foreach ($r in $rules) {
        if ($n -match $r.R) { return [pscustomobject]@{ Tier = $r.T; Source = 'GPU model' } }
    }
    # Unknown model: fall back to VRAM size (BF6 asks for 6 GB minimum, 8 GB recommended)
    $t = if ($gpu.VramGB -lt 6) { 1 } elseif ($gpu.VramGB -lt 10) { 2 } else { 3 }
    [pscustomobject]@{ Tier = $t; Source = 'VRAM (model not recognized)' }
}


# =============================================================================
#  PER-GAME TUNING: PROFSAVE_profile VALUES
#  The presets favor visibility and frame rate (competitive play) over eye candy.
#    Quality values: 0 = Low, 1 = Medium, 2 = High, 3 = Ultra
#    AnisotropicFilter: 0 = 1x, 1 = 2x, 2 = 4x, 3 = 8x, 4 = 16x
# =============================================================================

# -----------------------------------------------------------------------------
# Get-ProfileSettingsBf4
# -----------------------------------------------------------------------------
function Get-ProfileSettingsBf4([int]$tier, [int]$threads) {
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
# Get-ProfileSettingsBf1
#   AntiAliasingPost: 0 = Off, 1 = FXAA Medium, 2 = FXAA High, 3 = TAA
# -----------------------------------------------------------------------------
function Get-ProfileSettingsBf1([int]$tier, [int]$threads) {
    # Shared by every tier
    $common = [ordered]@{
        'GstRender.OverallGraphicsQuality'  = '4'          # Custom preset (value as written by the game for "Custom")
        'GstRender.Dx12Enabled'             = '0'          # DX11: BF1's DX12 path is known for stutter
        'GstRender.Dx12AutoDetect'          = '0'          # don't let the game switch back to DX12
        'GstRender.AmbientOcclusion'        = '0'          # SSAO/HBAO off: expensive, no gameplay value
        'GstRender.AntiAliasingDeferred'    = '0'          # deferred MSAA off: very costly
        'GstRender.Enlighten'               = '0'          # dynamic global illumination off
        'GstRender.MotionBlur'              = '0.000000'
        'GstRender.MotionBlurEnabled'       = '0'
        'GstRender.ChromaticAberration'     = '0'          # color fringing at screen edges
        'GstRender.FilmGrain'               = '0'          # noise overlay
        'GstRender.LensDistortion'          = '0'          # warps the image edges
        'GstRender.PostProcessQuality'      = '0'          # less bloom/haze: enemies are easier to spot
        'GstRender.TransparentShadows'      = '0'
        'GstRender.UndergrowthQuality'      = '0'          # less grass hiding prone enemies
        'GstRender.VSyncEnabled'            = '0'          # V-Sync handled by the driver (or off)
        'GstRender.WeaponDOF'               = '0'          # no blur around the weapon when aiming
        'GstRender.SniperSweetspotDoF'      = '0'          # no blur outside the scope sweet spot
    }
    switch ($tier) {
        # High: detail that improves target recognition stays on Ultra.
        # BF1 relies on TAA for a stable image (foliage and fences shimmer without it).
        3 { $t = [ordered]@{
                'GstRender.TextureQuality'    = '3'
                'GstRender.MeshQuality'       = '3'
                'GstRender.TerrainQuality'    = '3'
                'GstRender.TextureFiltering'  = '3'
                'GstRender.AnisotropicFilter' = '4'
                'GstRender.EffectsQuality'    = '1'   # lighter explosions and particles
                'GstRender.LightingQuality'   = '1'   # less sun glare
                'GstRender.ShadowQuality'     = '1'
                'GstRender.AntiAliasingPost'  = '3'   # TAA
                'GstRender.ResolutionScale'   = '1.000000'
                'GstRender.ClampGpuMemory'    = '0' } }  # GPU memory restriction off: plenty of VRAM
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
                'GstRender.AntiAliasingPost'  = '2'   # FXAA High: cheaper than TAA
                'GstRender.ResolutionScale'   = '1.000000'
                'GstRender.ClampGpuMemory'    = '1' } }  # keeps VRAM use within the card's limit
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
                'GstRender.AntiAliasingPost'  = '1'   # FXAA Medium
                'GstRender.ResolutionScale'   = '1.000000'
                'GstRender.ClampGpuMemory'    = '1' } }
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
# Get-ProfileSettingsBfv
# Every key below exists in profiles written by BF V itself; settings this
# tool has no opinion on (anti-aliasing, DX12, DLSS, HDR, FOV, HUD...) are
# left alone. Ultra (3) is never used.
# -----------------------------------------------------------------------------
function Get-ProfileSettingsBfv([int]$tier, [int]$threads, [double]$vramGB) {
    # Shared by every tier
    $common = [ordered]@{
        # BFV stores 0 here alongside customized settings (and does not
        # re-apply a preset over them), so 0 is the safe value to keep
        'GstRender.OverallGraphicsQuality' = '0'
        # Clarity: effects that blur or distort the image
        'GstRender.MotionBlurEnabled'      = '0'
        'GstRender.MotionBlur'             = '0.000000'
        'GstRender.ChromaticAberration'    = '0'
        'GstRender.FilmGrain'              = '0'
        'GstRender.LensDistortion'         = '0'
        'GstRender.Vignette'               = '0'
        'GstRender.WeaponDOF'              = '0'          # no blur around the weapon when aiming
        # Visibility: less grass, haze and bloom between you and enemies
        'GstRender.UndergrowthQuality'     = '0'
        'GstRender.PostProcessQuality'     = '0'
        # Expensive effects with no gameplay value
        'GstRender.AmbientOcclusion'       = '0'
        'GstRender.TransparentShadows'     = '0'
        'GstRender.Enlighten'              = '0'          # dynamic global illumination off
        'GstRender.VSyncEnabled'           = '0'          # V-Sync handled by the driver (or off)
    }
    switch ($tier) {
        # High: detail that helps target recognition stays on High
        3 { $t = [ordered]@{
                'GstRender.TextureQuality'    = '2'
                'GstRender.TextureFiltering'  = '2'
                'GstRender.MeshQuality'       = '2'
                'GstRender.TerrainQuality'    = '2'
                'GstRender.LightingQuality'   = '1'   # less sun glare
                'GstRender.EffectsQuality'    = '1'   # thinner smoke and explosions
                'GstRender.ShadowQuality'     = '1' } }
        # Medium
        2 { $t = [ordered]@{
                'GstRender.TextureQuality'    = '1'
                'GstRender.TextureFiltering'  = '2'   # cheap, keeps distant ground sharp
                'GstRender.MeshQuality'       = '1'
                'GstRender.TerrainQuality'    = '1'
                'GstRender.LightingQuality'   = '0'
                'GstRender.EffectsQuality'    = '0'
                'GstRender.ShadowQuality'     = '0' } }
        # Low
        default { $t = [ordered]@{
                'GstRender.TextureQuality'    = '0'
                'GstRender.TextureFiltering'  = '1'
                'GstRender.MeshQuality'       = '0'
                'GstRender.TerrainQuality'    = '0'
                'GstRender.LightingQuality'   = '0'
                'GstRender.EffectsQuality'    = '0'
                'GstRender.ShadowQuality'     = '0' } }
    }
    foreach ($k in $t.Keys) { $common[$k] = $t[$k] }

    # Ray-traced reflections are far too heavy below the High tier
    if ($tier -le 2) { $common['GstRender.DxREnabled'] = '0' }
    # Textures cost VRAM, not frame rate: limit them by video memory (when known)
    if ($vramGB -gt 0) {
        $maxTex = if ($vramGB -ge 6) { 2 } elseif ($vramGB -ge 4) { 1 } else { 0 }
        if ([int]$common['GstRender.TextureQuality'] -gt $maxTex) { $common['GstRender.TextureQuality'] = "$maxTex" }
    }
    # Weak CPU: mesh and terrain detail add draw calls, which load the CPU
    if ($threads -le 4) {
        if ([int]$common['GstRender.MeshQuality'] -gt 1)    { $common['GstRender.MeshQuality'] = '1' }
        if ([int]$common['GstRender.TerrainQuality'] -gt 1) { $common['GstRender.TerrainQuality'] = '1' }
    }
    $common
}

# -----------------------------------------------------------------------------
# Get-ProfileSettingsBf6
# Every key below exists in profiles written by BF6 itself; settings this
# tool has no opinion on (upscaling, DRS, HDR, FOV, HUD...) are left alone.
# Ultra (3) is never used.
# -----------------------------------------------------------------------------
function Get-ProfileSettingsBf6([int]$tier, [int]$threads, [int]$cores, [double]$vramGB, [bool]$isLaptop) {
    # Shared by every tier
    $common = [ordered]@{
        'GstRender.OverallGraphicsQuality'       = '6'          # Custom preset (what BF6 writes for customized settings)
        # Clarity: effects that blur or distort the image
        'GstRender.MotionBlurWorld'              = '0.000000'
        'GstRender.MotionBlurWeapon'             = '0.000000'
        'GstRender.ChromaticAberration'          = '0'
        'GstRender.FilmGrain'                    = '0'
        'GstRender.LensDistortion'               = '0'
        'GstRender.Vignette'                     = '0'
        'GstRender.WeaponDOF'                    = '0'          # no blur around the weapon when aiming
        # Visibility: less grass, haze and bloom between you and enemies
        'GstRender.UndergrowthQuality'           = '0'
        'GstRender.PostProcessQuality'           = '0'
        'GstRender.VolumetricQuality'            = '0'          # volumetric fog and light shafts
        # Expensive effects with no gameplay value
        'GstRender.AmbientOcclusion'             = '0'
        'GstRender.RaytracingAmbientOcclusion'   = '0'
        'GstRender.ScreenSpaceReflections'       = '0'
        'GstRender.ReflectionQuality'            = '0'
        'GstRender.LocalLightShadowQuality'      = '0'
        'GstRender.TransparentShadows'           = '0'
        'GstRender.Enlighten'                    = '0'          # dynamic global illumination off
        # Input lag: frame generation adds latency; the low-latency mode of
        # every vendor is turned on (only the one matching your GPU is used)
        'GstRender.FrameGeneration'              = '0'
        'GstRender.NVIDIAFrameGenerationEnabled' = '0'
        'GstRender.NvidiaMultiFrameGeneration'   = '0'
        'GstRender.AMDFrameGenerationEnabled'    = '0'
        'GstRender.IntelFrameGenerationEnabled'  = '0'
        'GstRender.NvidiaLowLatency'             = '1'          # NVIDIA Reflex
        'GstRender.AMDLowLatency'                = '1'          # AMD Anti-Lag
        'GstRender.IntelLowLatency'              = '1'          # Intel XeLL
        'GstRender.VSyncMode'                    = '0'          # V-Sync handled by the driver (or off)
    }
    switch ($tier) {
        # High: detail that helps target recognition stays on High
        3 { $t = [ordered]@{
                'GstRender.TextureQuality'    = '2'
                'GstRender.TextureFiltering'  = '2'
                'GstRender.MeshQuality'       = '2'
                'GstRender.TerrainQuality'    = '2'
                'GstRender.LightingQuality'   = '1'   # less sun glare
                'GstRender.EffectsQuality'    = '1'   # thinner smoke and explosions
                'GstRender.ShadowQuality'     = '1'
                'GstRender.SunShadowQuality'  = '1'
                'GstRender.ShadowFiltering'   = '1' } }
        # Medium
        2 { $t = [ordered]@{
                'GstRender.TextureQuality'    = '1'
                'GstRender.TextureFiltering'  = '2'   # cheap, keeps distant ground sharp
                'GstRender.MeshQuality'       = '1'
                'GstRender.TerrainQuality'    = '1'
                'GstRender.LightingQuality'   = '0'
                'GstRender.EffectsQuality'    = '0'
                'GstRender.ShadowQuality'     = '0'
                'GstRender.SunShadowQuality'  = '0'
                'GstRender.ShadowFiltering'   = '0' } }
        # Low
        default { $t = [ordered]@{
                'GstRender.TextureQuality'    = '0'
                'GstRender.TextureFiltering'  = '1'
                'GstRender.MeshQuality'       = '0'
                'GstRender.TerrainQuality'    = '0'
                'GstRender.LightingQuality'   = '0'
                'GstRender.EffectsQuality'    = '0'
                'GstRender.ShadowQuality'     = '0'
                'GstRender.SunShadowQuality'  = '0'
                'GstRender.ShadowFiltering'   = '0' } }
    }
    foreach ($k in $t.Keys) { $common[$k] = $t[$k] }

    # Textures cost VRAM, not frame rate: limit them by video memory (when known)
    if ($vramGB -gt 0) {
        $maxTex = if ($vramGB -ge 8) { 2 } elseif ($vramGB -ge 6) { 1 } else { 0 }
        if ([int]$common['GstRender.TextureQuality'] -gt $maxTex) { $common['GstRender.TextureQuality'] = "$maxTex" }
    }
    # BF6 is CPU-heavy: mesh and terrain detail (more draw calls) are capped at
    # Medium on 8 threads or fewer, below 8 cores and on laptops. The official
    # recommended CPUs (Core i7-10700, Ryzen 7 3700X) are 8-core parts, so a
    # 6-core/12-thread CPU such as the i7-8700K sits between minimum and
    # recommended; a laptop CPU shares its power and cooling with the GPU.
    if ($threads -le 8 -or $cores -lt 8 -or $isLaptop) {
        if ([int]$common['GstRender.MeshQuality'] -gt 1)    { $common['GstRender.MeshQuality'] = '1' }
        if ([int]$common['GstRender.TerrainQuality'] -gt 1) { $common['GstRender.TerrainQuality'] = '1' }
    }
    $common
}


# =============================================================================
#  OPTIMIZER RUN (one game)
# =============================================================================

# -----------------------------------------------------------------------------
# Invoke-Undo
# Restores the newest backup of the game's PROFSAVE_profile and user.cfg.
# -----------------------------------------------------------------------------
function Invoke-Undo($g, $loc) {
    Wait-GameClosed $g
    foreach ($f in @($loc.ProfPath, $loc.UserCfgPath)) {
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
}

# -----------------------------------------------------------------------------
# Invoke-Optimizer
# Generates, explains and (optionally) applies the files for one game.
# -----------------------------------------------------------------------------
function Invoke-Optimizer($g, [string]$scriptDir) {
    $id = $g.Id
    $classic = $id -ne 'bf6'          # BF4, BF1 and BF V cap FPS in user.cfg; BF6 in its profile

    # Everything printed through Say is also saved to README.txt in the output folder
    $log = New-Object System.Collections.Generic.List[string]
    function Say([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c; $log.Add($t) }

    Say ''
    Say "=== Battlefield Optimizer v$AppVersion - $($g.Name) (user.cfg + PROFSAVE_profile) ===" 'Cyan'
    Say ("Generated on {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm')) 'DarkGray'
    Say ''

    # --- Locations ---
    $loc         = Get-GameLocations $g $scriptDir
    $gameDir     = $loc.GameDir
    $profPath    = $loc.ProfPath
    $profDir     = if ($g.ProfileMode -eq 'fixed') { $loc.SettingsDir } elseif ($profPath) { Split-Path -Parent $profPath } else { $loc.SettingsDir }
    $userCfgPath = $loc.UserCfgPath

    # --- Undo menu, shown only when backups from a previous run exist ---
    if ((Get-LatestBackup $profPath) -or (Get-LatestBackup $userCfgPath)) {
        Write-Host 'Backups from a previous run were found.' -ForegroundColor Cyan
        Write-Host '  1) Generate optimized settings'
        Write-Host '  2) Undo the last apply (restore the previous files)'
        if ((Read-Host 'Choose [1/2] (Enter = 1)') -eq '2') {
            Invoke-Undo $g $loc
            return
        }
        Write-Host ''
    }

    # --- Output folder: "<game>_Optimized" next to this script, or on the Desktop if that is read-only ---
    $outDir = Join-Path $scriptDir "$($g.Short)_Optimized"
    [void](New-Item -ItemType Directory -Path $outDir -Force -ErrorAction SilentlyContinue)
    if (-not (Test-Write $outDir)) {
        $outDir = Join-Path ([Environment]::GetFolderPath('Desktop')) "$($g.Short)_Optimized"
        [void](New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop)
    }

    # --- Hardware (detected once per session) ---
    if (-not $script:Hw) { $script:Hw = Get-Hardware }
    $hw = $script:Hw
    $cores = $hw.Cores; $threads = $hw.Threads; $gpu = $hw.Gpu; $mons = $hw.Mons; $isLaptop = $hw.IsLaptop
    $hz = $hw.Hz

    Say '--- Hardware ---' 'Cyan'
    Say ("CPU      : {0}  ({1} cores / {2} threads)" -f $hw.CpuName, $cores, $threads)
    Say ("RAM      : {0} GB" -f $hw.RamGB)
    if ($gpu) { Say ("GPU      : {0}  ({1}{2} GB VRAM)" -f $gpu.Name, $gpu.VramGB, $(if ($gpu.VramExact) { '' } else { '+' })) }
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
    if ($id -eq 'bf6' -and $hw.RamGB -and $hw.RamGB -lt 16) { Say ("WARNING: BF6 needs 16 GB of RAM; with {0} GB expect stutter." -f $hw.RamGB) 'Yellow' }

    # Warn if Windows runs the monitor below its maximum refresh rate. Only
    # reliable with one display: with several, the Hz cannot be matched to a monitor.
    if ($mons.Count -eq 1 -and $mons[0].MaxHz -and $hz -and ($hz + 5) -lt $mons[0].MaxHz) {
        Say ("WARNING: the monitor supports up to {0} Hz but Windows is set to {1} Hz. Change it in Settings > Display > Advanced display." -f $mons[0].MaxHz, $hz) 'Yellow'
    }
    # Refresh rate questions are asked once per session and reused for every game
    if (-not $hz -or $hz -lt 30) {
        if ($null -eq $hw.HzAnswer) {
            $hw.HzAnswer = ((Read-Host 'Could not read the refresh rate. How many Hz is your display?') -replace '\D', '') -as [int]
            if ($hw.HzAnswer -lt 30) { $hw.HzAnswer = 60 }
        }
        $hz = $hw.HzAnswer
    } elseif ($mons.Count -gt 1) {
        if ($null -eq $hw.HzAnswer) {
            $v = ((Read-Host "Several displays found. Refresh rate (Hz) of the one you play on? (Enter = $hz)") -replace '\D', '') -as [int]
            $hw.HzAnswer = if ($v -ge 30) { $v } else { $hz }
        }
        $hz = $hw.HzAnswer
        Say ("Display used for the FPS cap: {0} Hz" -f $hz)
    }

    # BF4 only: in exclusive fullscreen BF4 switches the display to its own
    # refresh rate, which can be higher than the Windows desktop rate (laptops
    # often run the desktop at 60 Hz). The FPS cap then follows the rate the
    # game really uses. Only with one display, and never above what the monitor advertises.
    if ($id -eq 'bf4' -and $mons.Count -le 1 -and (Test-Path -LiteralPath $profPath)) {
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
    if ($null -eq $hw.VrrAnswer) {
        $vrrDetected = [bool]($mons | Where-Object { $_.FreeSync -or $_.HdmiVrr -or $_.DpAdaptiveSync -or $_.RangeVrr -or $_.NvidiaVsdb })
        $def = if ($vrrDetected) { 'Y' } else { 'N' }
        Write-Host ''
        Write-Host ("G-Sync/FreeSync detected: {0}" -f $(if ($vrrDetected) { 'YES' } else { 'NO' })) -ForegroundColor Cyan
        $ans = Read-Host "Is G-Sync/FreeSync ENABLED in your graphics driver? [Y/N] (Enter = $def)"
        if (-not $ans) { $ans = $def }
        $hw.VrrAnswer = [bool]($ans -match '^[yYsS]')
    }
    $vrr = $hw.VrrAnswer
    Say ("G-Sync/FreeSync: {0}" -f $(if ($vrr) { 'enabled' } else { 'disabled' }))

    # --- FPS cap ---
    $gt     = if ($id -eq 'bf6') { Get-GpuTierBf6 $gpu } else { Get-GpuTierClassic $gpu }
    $tier   = $gt.Tier
    $strong = $tier -ge 3 -and $threads -ge $(if ($id -eq 'bf6') { 12 } else { 8 })
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
    } elseif ($classic) {
        # Without VRR, rendering above refresh lowers input latency on a strong desktop
        $cap = [math]::Min($hz * 2, 300)
        $why = "no VRR, strong desktop: FPS above refresh rate lowers input latency"
    } else {
        $cap = 0                                  # BF6: 0 = limiter off
        $why = "no VRR, strong desktop: limiter off, FPS above refresh rate lowers input latency"
    }

    # --- user.cfg ---
    $outCfg  = Join-Path $outDir 'user.cfg'
    $haveCfg = $true
    Say ''
    Say '--- user.cfg ---' 'Green'
    if ($classic) {
        # Frame cap and render queue. A 1-frame queue gives the lowest input
        # lag; very weak CPUs stutter with it, so they get 2
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
        $keptCfg = Build-UserCfg $userCfgPath $cfg $outCfg
        $cfg | ForEach-Object { Say "  $_" }
        if ($keptCfg) { Say ("Kept {0} line(s) from your existing user.cfg." -f $keptCfg) }
        Say "FPS cap      : $cap  -> $why"
        Say "Render queue : $ral  -> $ralWhy"
    } else {
        # BF6: CPU thread settings. Widely used community fix for BF6's high
        # CPU usage: tells the engine how many cores (job threads) and logical
        # processors (render threads) to use.
        $haveCfg = [bool]($cores -and $threads)
        if ($haveCfg) {
            $cfg = @(
                "Thread.ProcessorCount $cores",
                "Thread.MaxProcessorCount $cores",
                'Thread.MinFreeProcessorCount 0',
                'Thread.JobThreadPriority 0',
                "GstRender.Thread.MaxProcessorCount $threads"
            )
            $keptCfg = Build-UserCfg $userCfgPath $cfg $outCfg
            $cfg | ForEach-Object { Say "  $_" }
            if ($keptCfg) { Say ("Kept {0} line(s) from your existing user.cfg." -f $keptCfg) }
            Say "Threads      : $cores cores / $threads logical processors (update it after a CPU upgrade)"
        } else {
            Say 'CPU core count could not be read: no user.cfg was generated.' 'Yellow'
        }
    }

    # --- PROFSAVE_profile: graphics tier applied on top of the current profile ---
    $outProf = Join-Path $outDir 'PROFSAVE_profile'
    $tierTxt = @{ 1 = 'LOW'; 2 = 'MEDIUM'; 3 = 'HIGH' }[$tier]
    $vramGB  = switch ($id) {
        'bf6'   { if ($gpu) { [double]$gpu.VramGB } else { 0 } }
        'bfv'   { if ($gpu -and $gpu.VramExact) { [double]$gpu.VramGB } else { 0 } }   # 0 = unknown: no texture limit
        default { 0 }
    }

    Say ''
    Say '--- PROFSAVE_profile ---' 'Green'
    Say "Graphics tier: $tierTxt  (based on: $($gt.Source))"
    if ($id -eq 'bf6') {
        if ($cap) { Say "FPS limiter  : $cap  -> $why" } else { Say "FPS limiter  : off  -> $why" }
        if ($threads -le 8 -or $cores -lt 8 -or $isLaptop) {
            $cpuWhy = if ($threads -le 8 -or $cores -lt 8) { '{0} cores / {1} threads' -f $cores, $threads } else { 'Laptop' }
            Say ('{0}: mesh and terrain quality capped at Medium (BF6 is CPU-heavy).' -f $cpuWhy)
        }
        if ($vramGB -gt 0 -and $vramGB -lt 8) { Say ("{0} GB VRAM: texture quality limited to fit in video memory." -f $vramGB) }
    } else {
        if ($threads -le 4) { Say '4 threads or fewer: mesh and terrain quality capped at Medium.' }
        if ($id -eq 'bfv' -and $vramGB -gt 0 -and $vramGB -lt 6) { Say ("{0} GB VRAM: texture quality limited to fit in video memory." -f $vramGB) }
    }

    $settings = switch ($id) {
        'bf4' { Get-ProfileSettingsBf4 $tier $threads }
        'bf1' { Get-ProfileSettingsBf1 $tier $threads }
        'bfv' { Get-ProfileSettingsBfv $tier $threads $vramGB }
        'bf6' { Get-ProfileSettingsBf6 $tier $threads $cores $vramGB $isLaptop }
    }
    if ($id -eq 'bf6') {
        # FPS cap through BF6's own frame rate limiter
        if ($cap) {
            $settings['GstRender.FrameRateLimiterEnable'] = '1'
            $settings['GstRender.FrameRateLimit']         = ([double]$cap).ToString('F6', $Invariant)
        } else {
            $settings['GstRender.FrameRateLimiterEnable'] = '0'
        }
    }

    $haveProf = [bool]$profPath -and (-not $g.NeedProfile -or (Test-Path -LiteralPath $profPath))
    if ($haveProf) {
        $res = Build-Profile $profPath $settings $outProf $g.Eol
        if ($res.FromExisting) {
            if ($g.NeedProfile) { Say "Based on: $profPath" }
            switch ($id) {
                'bf6'   { Say 'Keybinds, mouse, FOV, HUD, audio, resolution and upscaling are preserved.' }
                'bfv'   { Say 'Resolution, FOV, HUD, colour-blind colours, audio, anti-aliasing, DX12 and DLSS are preserved.' }
                default { Say 'Based on your current profile: keybinds, mouse, FOV, audio and resolution are preserved.' }
            }
            if ($res.Changes.Count) { Say 'Changes:'; $res.Changes | ForEach-Object { Say "  $_" } }
            if ($res.Added.Count)   { Say 'Added (not present in your current profile):'; $res.Added | ForEach-Object { Say "  $_" } }
            if (-not $res.Changes.Count -and -not $res.Added.Count) {
                Say 'Your current profile was already optimized; the generated file is identical.'
            }
            # Warn if the in-game refresh rate is lower than the display's
            $fr = $res.Lines | Where-Object { $_ -match '^GstRender\.FullscreenRefreshRate\s' } | Select-Object -First 1
            $frHz = if ($fr -match '([\d.]+)\s*$') { $Matches[1] -as [double] } else { $null }
            if ($frHz -gt 0 -and $frHz -lt ($hz - 1)) {
                $where = if ($id -eq 'bf6') { "the game's display settings" } else { 'Options > Video' }
                Say ("WARNING: the game is set to {0:N0} Hz but the display supports {1} Hz. Select {1} Hz in {2}." -f $frHz, $hz, $where) 'Yellow'
            }
            if ($id -eq 'bfv') {
                $dx12 = $res.Lines | Where-Object { $_ -match '^GstRender\.Dx12Enabled\s+1' }
                if ($dx12) { Say 'DirectX 12 is on (needed for DXR and DLSS). If you get stutter, try DX11 in Options > Video.' 'DarkGray' }
                if ($tier -le 2) { Say 'Ray-traced reflections (DXR) are kept off on this GPU.' }
            }
            if ($id -eq 'bf6' -and $tier -eq 1) { Say 'Tip: on this GPU, turn on DLSS / FSR / XeSS (Quality) in Options > Graphics for a big FPS gain.' 'Yellow' }
        } else {
            Say "No $($g.Short) profile found on this PC: a graphics-only profile was created." 'Yellow'
            Say 'Keybinds, mouse and resolution will use the game defaults.' 'Yellow'
        }
    } else {
        # A profile built from scratch would replace keybinds, HUD and audio
        # with defaults, so none is generated
        Say "No $($g.Short) settings file was found on this PC, so no PROFSAVE_profile was generated." 'Yellow'
        Say "Start $($g.Name) once (it creates the file), close it, and run this script again." 'Yellow'
    }

    # --- Where to put each file ---
    Say ''
    Say '=== WHERE TO APPLY ===' 'Cyan'
    Say "Generated files: $outDir"
    Say ''
    $sayCfgTarget = {
        param([string]$n)
        Say "$n) user.cfg  ->  game install folder (the one that contains $($g.Exe))"
        if ($gameDir) {
            Say "   Detected: $gameDir" 'Green'
        } else {
            Say '   Not detected. Common locations:' 'Yellow'
            foreach ($p in $g.ShowPaths) { Say "     $p" }
            Say "   $($g.FolderHint)"
        }
    }
    if (-not $g.NeedProfile) {
        # BF4 / BF1: user.cfg first, then the settings folder
        & $sayCfgTarget '1'
        Say ''
        Say '2) PROFSAVE_profile  ->  settings folder in Documents'
        Say "   $profDir" $(if (Test-Path -LiteralPath $profDir) { 'Green' } else { 'Yellow' })
        Say "   Copy it with the game CLOSED ($($g.Short) rewrites this file when it exits)."
        Say '   Changing video options in-game later will overwrite these values.'
    } else {
        # BF V / BF6: the exact profile file first, then user.cfg
        if ($haveProf) {
            Say '1) PROFSAVE_profile  ->'
            Say "   $profPath" 'Green'
            Say "   Copy it with the game CLOSED ($($g.Short) rewrites this file when it exits)."
            if ($id -eq 'bf6') { Say '   Changing graphics options in-game later will overwrite these values.' }
            else               { Say '   Changing video options in-game later will overwrite these values.' }
        } else {
            Say '1) PROFSAVE_profile  ->  not generated (see above)'
        }
        Say ''
        & $sayCfgTarget '2'
        if ($id -eq 'bf6') { Say '   It is optional: if the game behaves worse with it, run this script again and choose Undo.' }
    }
    Say ''
    Say "3) Graphics driver settings for $($g.Exe):"
    switch (Get-GpuVendor $gpu.Name) {
        'NVIDIA' {
            if ($vrr) { Say '   - NVIDIA Control Panel: G-Sync on + V-Sync ON (keep V-Sync off in-game)' }
            else      { Say '   - NVIDIA Control Panel: V-Sync off' }
            if ($id -eq 'bf6') { Say '   - Low Latency Mode: leave Off (NVIDIA Reflex is turned on in-game instead)' }
            else               { Say '   - Low Latency Mode: On' }
        }
        'AMD' {
            if ($vrr) { Say '   - AMD Adrenalin: FreeSync on + Wait for Vertical Refresh "Always on" (keep V-Sync off in-game)' }
            else      { Say '   - AMD Adrenalin: Wait for Vertical Refresh off' }
            if ($id -eq 'bf6') { Say '   - Anti-Lag: turned on in-game by the profile' }
            else               { Say '   - Radeon Anti-Lag: on' }
        }
        'Intel' {
            if ($vrr) { Say '   - Intel Graphics Software / Arc Control: Adaptive Sync on (keep V-Sync off in-game)' }
            else      { Say '   - Intel Graphics Software / Arc Control: V-Sync off' }
            if ($id -eq 'bf6') { Say '   - Low latency (XeLL): turned on in-game by the profile' }
            else               { Say '   - Low Latency: on (if your driver offers it)' }
        }
        default {
            if ($id -eq 'bf6') { Say '   - V-Sync off in the driver' }
            else               { Say '   - V-Sync off in the driver; turn on its low-latency option if it has one' }
        }
    }
    Say '   - Power management: prefer maximum performance'
    if ($id -eq 'bf1') {
        Say ''
        Say 'Note: the profile switches BF1 to DirectX 11 (more stable frame times than DX12).' 'DarkGray'
    }

    # Save the full report next to the generated files (UTF-8 keeps accented paths readable)
    [IO.File]::WriteAllLines((Join-Path $outDir 'README.txt'), $log.ToArray(), (New-Object System.Text.UTF8Encoding $true))

    # --- Optional: copy the files into place (default is No) ---
    Write-Host ''
    $ap = Read-Host 'Copy the files to those locations now? [Y/N] (Enter = N)'
    if ($ap -match '^[yYsS]') {
        Wait-GameClosed $g
        $stamp = Get-Date -Format yyyyMMdd_HHmmss

        # PROFSAVE_profile lives in Documents, so no admin rights are needed
        if ($haveProf) {
            if (-not $g.NeedProfile) { [void](New-Item -ItemType Directory -Path $profDir -Force -ErrorAction SilentlyContinue) }
            if ((Install-File $outProf $profPath $stamp) -eq 'ok') {
                Write-Host "PROFSAVE_profile applied (previous file saved as PROFSAVE_profile.bak_$stamp)" -ForegroundColor Green
            } else {
                Write-Host "ERROR: PROFSAVE_profile could not be applied. Copy it manually to $(Split-Path -Parent $profPath)" -ForegroundColor Red
            }
        }

        # user.cfg goes into the game folder, which may require admin rights
        if (-not $haveCfg) {
            # nothing to copy
        } elseif (-not $gameDir) {
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
        Write-Host 'To undo, run this script again, pick the same game and choose "Undo".' -ForegroundColor DarkGray
    } else {
        Write-Host 'Nothing was changed. Copy the files manually using the instructions above (also in README.txt).' -ForegroundColor Cyan
    }

    # Open the output folder in File Explorer
    Start-Process explorer.exe -ArgumentList "`"$outDir`""
}


# =============================================================================
#  MENU
# =============================================================================

# -----------------------------------------------------------------------------
# Show-Menu
# Lists the games with what was found on this PC and returns the choice
# ('1'-'4'), or $null to exit.
# -----------------------------------------------------------------------------
function Show-Menu([string]$scriptDir) {
    Write-Host ''
    Write-Host "=== Battlefield Optimizer v$AppVersion ===" -ForegroundColor Cyan
    Write-Host 'Which game do you want to optimize?'
    Write-Host ''
    foreach ($key in $Games.Keys) {
        $g   = $Games[$key]
        $loc = Get-GameLocations $g $scriptDir
        $hasProf = $loc.ProfPath -and (Test-Path -LiteralPath $loc.ProfPath)
        $status = if ($loc.GameDir -and $hasProf) { 'installed, settings found' }
                  elseif ($loc.GameDir)           { 'installed' }
                  elseif ($hasProf)               { 'settings found' }
                  else                            { 'not detected' }
        $color = if ($status -eq 'not detected') { 'DarkGray' } else { 'Gray' }
        Write-Host ("  {0}) {1,-15} [{2}]" -f $key, $g.Name, $status) -ForegroundColor $color
    }
    Write-Host '  0) Exit'
    Write-Host ''
    while ($true) {
        $c = "$(Read-Host 'Choose [1-4, 0 = exit]')".Trim()
        if ($c -eq '0' -or $c -eq '') { return $null }
        if ($Games.Contains($c)) { return $c }
        Write-Host 'Please type 1, 2, 3, 4 or 0.' -ForegroundColor Yellow
    }
}

# -----------------------------------------------------------------------------
# Main
# Menu loop: pick a game, optimize it, then pick another or exit.
# Hardware and display answers are reused between games.
# -----------------------------------------------------------------------------
function Main {
    $scriptDir = Split-Path -Parent $env:BFCFG_SCRIPT
    $script:Hw = $null
    while ($true) {
        $choice = Show-Menu $scriptDir
        if (-not $choice) { return }
        try {
            Invoke-Optimizer $Games[$choice] $scriptDir
        } catch {
            # Any unexpected error is shown instead of silently producing wrong files
            Write-Host ''
            Write-Host ("UNEXPECTED ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
            Write-Host ("Line {0}: {1}" -f $_.InvocationInfo.ScriptLineNumber, "$($_.InvocationInfo.Line)".Trim()) -ForegroundColor DarkGray
            Write-Host 'Please report this on GitHub together with the text above.' -ForegroundColor DarkGray
        }
        Write-Host ''
        if ((Read-Host 'Optimize another game? [Y/N] (Enter = N)') -notmatch '^[yYsS]') { return }
    }
}

try {
    Main
} catch {
    Write-Host ''
    Write-Host ("UNEXPECTED ERROR: {0}" -f $_.Exception.Message) -ForegroundColor Red
    Write-Host ("Line {0}: {1}" -f $_.InvocationInfo.ScriptLineNumber, "$($_.InvocationInfo.Line)".Trim()) -ForegroundColor DarkGray
    Write-Host 'Please report this on GitHub together with the text above.' -ForegroundColor DarkGray
}
