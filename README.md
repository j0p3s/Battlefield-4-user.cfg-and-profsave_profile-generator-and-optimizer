# BF4 Optimizer

A one-click Windows script that detects your hardware and generates a tuned `user.cfg` and `PROFSAVE_profile` for **Battlefield 4**, saves them in a **`BF4_Optimized` folder on your Desktop**, and tells you exactly where each file goes.

No installs, no executables, no game file modifications. It is a single, fully commented `.cmd` file you can open and read before running it.

---

## Table of contents

- [Features](#features)
- [Requirements](#requirements)
- [Quick start](#quick-start)
- [What happens when you run it](#what-happens-when-you-run-it)
- [The output folder on your Desktop](#the-output-folder-on-your-desktop)
- [Where to put the files](#where-to-put-the-files)
- [How settings are chosen](#how-settings-are-chosen)
- [Recommended driver settings](#recommended-driver-settings)
- [How hardware detection works](#how-hardware-detection-works)
- [Safety and backups](#safety-and-backups)
- [Restoring your old settings](#restoring-your-old-settings)
- [FAQ](#faq)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [Contributing](#contributing)
- [Disclaimer](#disclaimer)
- [License](#license)

---

## Features

- **Hardware detection:**
  - CPU, RAM and GPU, including the GPU's real VRAM;
  - laptop vs. desktop;
  - display refresh rate.
- **G-Sync / FreeSync detection** by reading your monitor's EDID: AMD FreeSync, HDMI 2.1 VRR, DisplayPort Adaptive-Sync and NVIDIA vendor blocks.
- **Tuned `user.cfg`:** frame rate cap and render queue picked for your display and hardware.
- **Tuned `PROFSAVE_profile`:** a competitive graphics preset for your GPU tier (High / Medium / Low). The tier is based on the actual GPU model, not just VRAM.
- **Your personal settings are kept.** Keybinds, mouse sensitivity, FOV, audio and resolution are copied from your current profile.
- **Everything goes to a `BF4_Optimized` folder on your Desktop**, along with a `README.txt` report of what was detected, what changed and where each file goes.
- **Optional automatic install** with timestamped backups. The default answer is No.
- **Works with Origin, EA app and Steam** installs.

---

## Requirements

- Windows 10 or Windows 11
- Battlefield 4 (Origin, EA app or Steam)
- Nothing else. The script uses Windows PowerShell 5.1, which ships with Windows.

---

## Quick start

1. Download `BF4_Optimizer.cmd` from this repository (or from the Releases page).
2. Launch Battlefield 4 **once**, reach the main menu, then close the game. This makes sure your `PROFSAVE_profile` exists.
3. Double-click `BF4_Optimizer.cmd`.
4. Answer the G-Sync/FreeSync question. Press Enter to accept what was detected.
5. A **`BF4_Optimized` folder appears on your Desktop** with your files. File Explorer opens it for you.
6. Copy the files where the script tells you, or answer **Y** and let it do it for you.

---

## What happens when you run it

1. **Hardware scan.** The script reads your CPU, RAM, GPU, chassis type and the EDID of every connected monitor.
2. **One question:** is G-Sync/FreeSync **enabled** in your driver? Windows only reports what the monitor *supports*, not what the driver has *enabled*. The script shows what it detected, and you press Enter to accept or type Y/N.
3. **File generation.** It creates `Desktop\BF4_Optimized\` with:
   - `user.cfg`
   - `PROFSAVE_profile`
   - `README.txt`
4. **Instructions.** It prints where each file goes, using the paths found on your PC.
5. **Optional install.** It asks *"Copy the files to those locations now? [Y/N] (Enter = N)"*.
   - **N (default):** nothing on your system is changed. You copy the files yourself.
   - **Y:** it waits until BF4 is closed and backs up your current files. It then copies the new ones, asking for admin rights only for the game folder and only if that folder needs them.
6. **File Explorer** opens the `BF4_Optimized` folder.

### Example output

```
=== Battlefield 4 Optimizer (user.cfg + PROFSAVE_profile) ===
Generated on 2026-10-09 08:40

--- Hardware ---
CPU      : Intel(R) Core(TM) i7-8700K CPU @ 3.70GHz  (6 cores / 12 threads)
RAM      : 48 GB
GPU      : NVIDIA GeForce RTX 3080 Laptop GPU  (16 GB VRAM)
System   : Laptop
Display  : 144 Hz (current Windows refresh rate)
Monitor  : AUO (built-in display) | EDID range 40-144 Hz | no VRR advertised in EDID

G-Sync/FreeSync detected: NO
Is G-Sync/FreeSync ENABLED in your graphics driver? [Y/N] (Enter = N):
G-Sync/FreeSync: disabled

--- user.cfg ---
  PerfOverlay.DrawFps 1
  GameTime.MaxVariableFps 144
  RenderDevice.RenderAheadLimit 1
  RenderDevice.TripleBufferingEnable 0
  RenderDevice.VSyncEnable 0
  WorldRender.MotionBlurEnable 0
FPS cap      : 144  -> no VRR: matches the display refresh rate (stable frame times and temperatures)
Render queue : 1  -> 1-frame queue = lowest input lag

--- PROFSAVE_profile ---
Graphics tier: HIGH  (based on: GPU model)
Based on your current profile: keybinds, mouse, FOV, audio and resolution are preserved.
Changes:
  GstRender.AmbientOcclusion: 2 -> 0
  GstRender.AntiAliasingDeferred: 2 -> 0
  ...

=== WHERE TO APPLY ===
Generated files: C:\Users\you\Desktop\BF4_Optimized
...
```

---

## The output folder on your Desktop

Each run creates (or updates) this folder:

```
Desktop\
└── BF4_Optimized\
    ├── user.cfg            <- goes into the game folder
    ├── PROFSAVE_profile    <- goes into Documents\Battlefield 4\settings
    └── README.txt          <- full report: hardware, changes, instructions
```

- If your Desktop is synced with OneDrive, the folder is created in the OneDrive Desktop. That's the one you see on screen.
- If the Desktop can't be written to, the folder is created next to the script instead, and the script prints its location.
- Running the script again overwrites the files in this folder with fresh ones. Your game files are never touched unless you answer Y.

---

## Where to put the files

| File | Destination | Notes |
|---|---|---|
| `user.cfg` | Game install folder, next to `bf4.exe` | Read by the game at every launch |
| `PROFSAVE_profile` | `Documents\Battlefield 4\settings\` | Copy **with the game closed**; BF4 rewrites it on exit |

**Typical game folders:**

| Launcher | Default path |
|---|---|
| Origin | `C:\Program Files (x86)\Origin Games\Battlefield 4` |
| EA app | `C:\Program Files\EA Games\Battlefield 4` |
| Steam | `C:\Program Files (x86)\Steam\steamapps\common\Battlefield 4` |

To find the folder:
- **EA app:** right-click the game, then **View properties > Browse**.
- **Steam:** right-click the game, then **Manage > Browse local files**.

The script detects the folder automatically in most cases and prints the exact path.

---

## How settings are chosen

### `user.cfg`

| Command | Value | Purpose |
|---|---|---|
| `PerfOverlay.DrawFps` | `1` | On-screen FPS counter (set to `0` to hide it) |
| `GameTime.MaxVariableFps` | see below | Frame rate cap |
| `RenderDevice.RenderAheadLimit` | `1` (or `2`) | How many frames the CPU can queue ahead of the GPU; fewer = less input lag |
| `RenderDevice.TripleBufferingEnable` | `0` | Triple buffering adds latency |
| `RenderDevice.VSyncEnable` | `0` | V-Sync is handled by the driver (or off) |
| `WorldRender.MotionBlurEnable` | `0` | Makes sure motion blur is off |

**Frame rate cap:**

| Situation | FPS cap | Why |
|---|---|---|
| G-Sync / FreeSync enabled | Refresh rate − 3 (e.g. 141 on 144 Hz) | Keeps every frame inside the VRR range, avoiding tearing or V-Sync lag at the top |
| No VRR, laptop or mid/low-end hardware | Refresh rate (e.g. 144) | Even frame times and lower temperatures |
| No VRR, high-end desktop | 2× refresh rate (max 300) | Higher FPS means lower input latency |

**Render queue:** CPUs with 4 threads or fewer get `2` instead of `1`, because a 1-frame queue can cause stutter on weak CPUs.

**What the script deliberately leaves out:**
- `Thread.ProcessorCount` and similar thread commands. Forcing them often stops BF4 from using Hyper-Threading / SMT. The engine already scales well on its own.
- Placebo commands that circulate in old guides and aren't valid in BF4.

### `PROFSAVE_profile`

#### GPU tiers

The tier comes from the **GPU model**, not just its VRAM, since VRAM alone is misleading: a 4 GB GT 1030 is still a very slow card. Unknown models fall back to VRAM size: under 4 GB is Low, 4–7 GB is Medium, 8 GB or more is High.

| Tier | NVIDIA | AMD | Intel |
|---|---|---|---|
| **High** | RTX 2060 and up (all 20/30/40/50 series), GTX 1070/1080, 980 Ti, 1660 Ti/Super, TITAN | RX 5700, RX 6600 and up, 7000/9000 series, Vega 56/64, Radeon VII | Arc A750/A770, B-series |
| **Medium** | RTX 2050/3050, GTX 1660, 1650, 1060, 970/980 | RX 470/480/570/580/590, 5500/5600, 6500 XT | Arc A380/A580 |
| **Low** | GTX 1630, 1050/1050 Ti, older 9xx/7xx, GT and MX series | RX 6400/6300, 460/550/560, R7/R9/HD, all integrated (Vega, 680M/780M) | UHD, Iris Xe, integrated Arc, laptop Arc A350M/A370M |

Laptop versions ("Laptop GPU") follow the same rules as their desktop counterparts.

#### Settings per tier

The preset favors **visibility and frame rate** for competitive play over visual effects.

| Setting | High | Medium | Low |
|---|---|---|---|
| Texture quality | Ultra | High | Medium |
| Texture filtering | Ultra | High | Medium |
| Mesh quality | Ultra | High | Medium |
| Terrain quality | Ultra | High | Medium |
| Effects quality | Medium | Medium | Low |
| Lighting quality | Medium | Medium | Low |
| Shadow quality | Medium | Medium | Low |
| Anisotropic filtering | 16x | 16x | 4x |
| Post-process AA | Off | FXAA Low | FXAA Low |
| Resolution scale | 125% | 100% | 100% |

**Same for every tier:**

| Setting | Value | Reason |
|---|---|---|
| Graphics quality preset | Custom | Required for individual settings |
| Antialiasing deferred (MSAA) | Off | Extremely expensive in BF4's deferred renderer |
| Ambient occlusion | Off | Big performance cost, no gameplay benefit |
| Enlighten (dynamic GI) | Off | Performance |
| Post-process quality | Low | Less bloom and haze, so enemies stand out |
| Undergrowth quality | Low | Less grass hiding prone players |
| Motion blur | Off | Clarity |
| Weapon depth of field | Off | No blur around the weapon when aiming |
| Transparent shadows | Off | Performance |
| In-game V-Sync | Off | Use the driver instead |
| Head tracking / speech recognition | Off | Unused features |

**Weak CPUs** (4 threads or fewer): Mesh and Terrain are capped at Medium, since they add CPU draw calls.

**Not changed:** resolution, refresh rate, FOV, brightness, HUD, keybinds, mouse and controller settings, audio.

---

## Recommended driver settings

The script prints these at the end, tailored to your setup.

**NVIDIA Control Panel** (Manage 3D settings > Program settings > `bf4.exe`):

| Setting | With G-Sync | Without G-Sync |
|---|---|---|
| G-Sync | On | — |
| Vertical sync | **On** | Off |
| Low Latency Mode | On | On |
| Power management mode | Prefer maximum performance | Prefer maximum performance |

**AMD Software: Adrenalin Edition:**

| Setting | With FreeSync | Without FreeSync |
|---|---|---|
| AMD FreeSync | On | — |
| Wait for Vertical Refresh | Always on | Off |
| Radeon Anti-Lag | On | On |

With VRR, V-Sync goes **on in the driver** and stays **off in the game**. This combination plus the FPS cap gives smooth, tear-free and low-latency output.

---

## How hardware detection works

| What | Source |
|---|---|
| CPU, cores, threads | `Win32_Processor` |
| RAM | `Win32_ComputerSystem` |
| GPU name and VRAM | Display driver registry key. `Win32_VideoController` caps VRAM at 4 GB, so it's only a fallback |
| Main GPU | NVIDIA/AMD/Arc preferred over integrated graphics, then most VRAM |
| Refresh rate | `Win32_VideoController.CurrentRefreshRate` |
| Laptop vs. desktop | Battery present or portable chassis type |
| Monitor capabilities | EDID read from the registry (see below) |
| Game folder | Origin/EA app and Steam registry entries, then default paths |
| Documents folder | Windows known-folder API (works with OneDrive) |

**EDID parsing** looks for:

| EDID field | Meaning |
|---|---|
| Display Range Limits descriptor | Minimum and maximum refresh rate |
| AMD Vendor-Specific Data Block | FreeSync support |
| HDMI Forum VSDB with VRRmax | HDMI 2.1 VRR |
| DisplayID Adaptive-Sync block | DisplayPort Adaptive-Sync |
| NVIDIA Vendor-Specific Data Block | G-Sync hint |

The script also warns you if Windows is running your monitor below its maximum refresh rate (e.g. a 144 Hz monitor left at 60 Hz). It also warns if BF4 itself is set to a lower refresh rate than your display.

---

## Safety and backups

- **Nothing on your system is changed unless you answer Y** at the end. By default, the script only writes to `Desktop\BF4_Optimized`.
- Before replacing a file, it saves a backup next to it: `PROFSAVE_profile.bak_YYYYMMDD_HHMMSS` and `user.cfg.bak_YYYYMMDD_HHMMSS`.
- It only touches the game's own plain-text config files. No DLLs, no injection, no game files modified, no registry changes.
- Admin rights are requested only to copy `user.cfg` into a protected game folder, and only for that single copy.
- `ExecutionPolicy Bypass` applies to this one PowerShell process only. Your system policy isn't changed.
- The full source is in one readable, commented file.

---

## Restoring your old settings

**`PROFSAVE_profile`** (in `Documents\Battlefield 4\settings\`):
1. Close the game.
2. Delete `PROFSAVE_profile`.
3. Rename your backup `PROFSAVE_profile.bak_YYYYMMDD_HHMMSS` to `PROFSAVE_profile`.

**`user.cfg`** (in the game folder):
- If you had one before, delete the new one and rename `user.cfg.bak_YYYYMMDD_HHMMSS` to `user.cfg`.
- If you didn't have one, just delete `user.cfg`.

**Alternative:** in-game, open Options > Video, choose a preset and apply. The game rewrites the profile with its own values.

---

## FAQ

**Can I get banned for this?**
`user.cfg` and `PROFSAVE_profile` are the game's own configuration files and have been used by the BF4 community for years. The script doesn't modify game files, inject code or touch memory. That said, use it at your own risk; see the [Disclaimer](#disclaimer).

**Does it work with the EA app / Steam version?**
Yes. Both are detected automatically. If yours isn't, the script lists the usual paths and you can copy the files manually.

**I changed video settings in-game and my tweaks are gone.**
That's expected: BF4 rewrites `PROFSAVE_profile` whenever you apply video options. Run the script again. `user.cfg` is not affected.

**Can I run it more than once?**
Yes. It's safe to re-run at any time, for example after upgrading your GPU or monitor. Each install run creates a new timestamped backup.

**I prefer higher visual quality.**
Apply the files, then adjust individual options in-game. Your keybinds and other personal settings stay intact either way.

**Why is my FPS capped at 141 / 144?**
See [Frame rate cap](#usercfg). To change it, open `user.cfg` in Notepad and edit the `GameTime.MaxVariableFps` value. Use `0` for no cap.

**Why not MSAA?**
In BF4's deferred renderer, 4x MSAA can cost a huge share of your frame rate. On High-tier GPUs, a 125% resolution scale gives a sharper image for less cost.

**I have multiple monitors.**
All active monitors are listed. The refresh rate used is the highest one reported, so make sure BF4 runs on your main (fastest) display.

**Does it support other Battlefield games?**
No, only Battlefield 4. The setting names and values are specific to BF4.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| Windows SmartScreen blocks the file | Click **More info > Run anyway**, or right-click > **Properties** > tick **Unblock**. Right-click > **Edit** lets you read the script first. |
| The window closes immediately | Make sure the file still ends in `.cmd` (not `.cmd.txt`). If you edited it, check it was saved with Windows (CRLF) line endings. |
| "No BF4 profile found on this PC" | Launch BF4, reach the main menu, close it, then run the script again. |
| Wrong GPU detected on a laptop | Check that the dedicated GPU is enabled in Device Manager and your drivers are installed. Open an issue with your `README.txt`. |
| "model not recognized" next to the GPU tier | The VRAM fallback was used. Please open an issue with the GPU name shown in `README.txt`. |
| G-Sync/FreeSync not detected but you have it | Answer **Y** to the question. Some panels, especially laptop screens, don't advertise VRR in their EDID. |
| Windows shows 60 Hz on a high refresh monitor | Settings > System > Display > Advanced display > choose the highest refresh rate. Then run the script again. |
| "Permission denied" when copying `user.cfg` | Accept the Windows admin prompt, or copy the file manually from `Desktop\BF4_Optimized`. |
| Settings reverted after playing | You probably changed video options in-game. Run the script again. |
| The `BF4_Optimized` folder isn't on the Desktop | If the Desktop isn't writable, the folder is created next to the script. The exact path is printed and saved in `README.txt`. |

---

## Limitations

- **VRR detection is a hint, not a guarantee.** It reads what the monitor advertises; it can't read the driver's state. That's why you're asked to confirm.
- **The GPU tier list is hand-made.** New or rare models fall back to VRAM size until they're added.
- **The preset is competitive-oriented.** It prioritizes visibility and FPS over visuals.
- **Windows only.** BF4 isn't available on other PC platforms anyway.
- Tested on a limited number of systems. Feedback is very welcome.

---

## Contributing

Issues and pull requests are welcome! Especially useful:

- **GPUs missing from the tier list.** Include the exact name shown in `README.txt`.
- **Monitors whose G-Sync/FreeSync isn't detected.** Include the monitor model and connection type (DP/HDMI).
- **Before/after results** on different hardware: FPS, frame times, temperatures.

**Editing the script:**
- Keep `.cmd` files with **CRLF** line endings. The repository's `.gitattributes` enforces this.
- Keep the file ASCII-only. Non-ASCII characters can break the batch launcher.
- The GPU tiers live in `Get-GpuTier`. Rules are checked top to bottom and the first match wins, so put exceptions above broader patterns.
- Graphics values live in `Get-ProfileSettings`.

**Repository layout:**

```
BF4_Optimizer.cmd   # the script (batch launcher + PowerShell)
README.md           # this file
LICENSE             # MIT license
.gitattributes      # keeps CRLF line endings for .cmd files
```

---

## Disclaimer

This project is not affiliated with, endorsed by or connected to Electronic Arts or DICE. Battlefield is a trademark of Electronic Arts Inc.

The script is provided "as is", without warranty of any kind. Always keep backups of your settings. Use at your own risk.

---

## License

[MIT](LICENSE)
