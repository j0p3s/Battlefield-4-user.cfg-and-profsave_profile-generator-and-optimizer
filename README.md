# Battlefield Optimizer

Tuned `user.cfg` and `PROFSAVE_profile` files for **Battlefield 4, Battlefield 1, Battlefield V and Battlefield 6**, matched to your hardware, with every setting explained.

There are two ways to use it. Both are free and open source.

| | 🌐 **Web page** | 💻 **Windows script** |
|---|---|---|
| Link | **[Open the Config Builder](https://j0p3s.github.io/Battlefield-user-profile-tweaker/)** | [Download `Battlefield_Optimizer.cmd`](../../releases/latest) |
| Install or download anything? | **No.** It runs in your browser | One `.cmd` file, no installer |
| Hardware | You pick CPU, GPU, RAM and display from lists | Detected automatically |
| G-Sync / FreeSync | You choose | Read from your monitor, then you confirm |
| Your keybinds, FOV, audio | Kept if you load your current `PROFSAVE_profile` | Kept automatically |
| Copies files into the game | You copy them yourself | Optional, with backups |
| Undo | Keep your own backup | Built in |
| Works on | Any device with a browser | Windows 10 / 11 |

**Don't want to install or run anything on your PC?** Use the **[web page](https://j0p3s.github.io/Battlefield-user-profile-tweaker/)**. It works on any computer or phone. Everything happens in your browser and nothing is uploaded.

---

## Table of contents

- [Option 1: Web page (no install)](#option-1-web-page-no-install)
- [Option 2: Windows script](#option-2-windows-script)
  - [Requirements](#requirements)
  - [Quick start](#quick-start)
  - [What happens when you run it](#what-happens-when-you-run-it)
  - [Output folders](#output-folders)
- [Where to put the files](#where-to-put-the-files)
- [How settings are chosen](#how-settings-are-chosen)
- [Recommended driver settings](#recommended-driver-settings)
- [How hardware detection works](#how-hardware-detection-works)
- [Safety, backups and Undo](#safety-backups-and-undo)
- [FAQ](#faq)
- [Troubleshooting](#troubleshooting)
- [Limitations](#limitations)
- [Contributing](#contributing)
- [Disclaimer](#disclaimer)
- [License](#license)

---

## Option 1: Web page (no install)

**🌐 [j0p3s.github.io/Battlefield-user-profile-tweaker](https://j0p3s.github.io/Battlefield-user-profile-tweaker/)**

The **Battlefield Config Builder** uses the same rules as the script and builds the same files, but you describe your PC instead of the script detecting it. It runs entirely in your browser: nothing is uploaded, and there's nothing to install.

**How to use it:**

1. **Pick the game:** Battlefield 4, 1, V or 6.
2. **Pick your processor and graphics card** from the lists. If yours isn't listed, choose *Not listed* and enter the cores and threads, or the GPU brand and performance level. The cores and threads are shown in Task Manager > Performance > CPU.
3. **Pick your RAM, refresh rate and PC type** (desktop or laptop), and say whether G-Sync / FreeSync is **enabled in your driver**.
4. **Load your current `PROFSAVE_profile` (recommended).** This keeps your keybinds, sensitivity, FOV and audio. The file is read in your browser and never leaves your PC. **For Battlefield V and Battlefield 6 this is required**, because a profile built from scratch would reset your HUD, keybinds and audio.
5. **Download or copy** the `user.cfg` and `PROFSAVE_profile`.

The **Why these values** tab explains every setting. If you loaded your profile, it shows each old value next to the new one.

The page also includes the install folders for each file and the recommended driver settings for your GPU. **Copy link to this setup** gives you a link with your choices, handy for sharing or asking for help.

> **Tip:** before replacing your `PROFSAVE_profile`, make a copy of the old one. The web page can't make backups for you; the script can.

---

## Option 2: Windows script

One `.cmd` file for all four games. It detects your hardware, builds the files, tells you where each one goes, and can copy them into place with backups and Undo.

No executables, no DLLs, no game files modified. It's a single, fully commented plain-text file you can open and read before running it.

### Requirements

- Windows 10 or Windows 11
- Battlefield 4, 1, V and/or 6, installed through the EA app, Origin, Steam or Epic
- Nothing else. The script uses Windows PowerShell 5.1, which comes with Windows.

### Quick start

1. Download **`Battlefield_Optimizer.cmd`** from the [latest release](../../releases/latest).
2. Launch the game **once**, reach the main menu, then close it. This creates your `PROFSAVE_profile`.
3. Double-click `Battlefield_Optimizer.cmd`.
4. Pick the game from the menu.
5. Answer the G-Sync / FreeSync question. Press Enter to accept what was detected.
6. A **`<game>_Optimized` folder** (for example `BF4_Optimized`) appears next to the script, and File Explorer opens it.
7. Copy the files where the script tells you, or answer **Y** to let it do it for you.

### What happens when you run it

1. **Menu.** Every game is listed, showing whether it's installed and whether its settings file was found:

   ```
   === Battlefield Optimizer v2.0.0 ===
   Which game do you want to optimize?

     1) Battlefield 4   [installed, settings found]
     2) Battlefield 1   [not detected]
     3) Battlefield V   [installed]
     4) Battlefield 6   [installed, settings found]
     0) Exit
   ```

2. **Undo option.** If backups from an earlier run exist, you can choose to **generate** new settings or **undo** the last apply.
3. **Hardware scan:** CPU, RAM, GPU and VRAM, laptop or desktop, and the EDID of every monitor. This happens once per session.
4. **One question:** is G-Sync / FreeSync **enabled** in your driver? Windows only reports what the monitor *supports*, not what the driver has *enabled*. The answer is reused if you optimize another game in the same session.
5. **Files generated** in `<game>_Optimized`:
   - `user.cfg`
   - `PROFSAVE_profile`
   - `README.txt`, a full report of what was detected, what changed and where each file goes
6. **Instructions** with the paths found on your PC, and driver settings for your GPU.
7. **Optional install.** *"Copy the files to those locations now? [Y/N] (Enter = N)"*
   - **N (default):** nothing on your system is changed.
   - **Y:** the script waits until the game is closed and backs up your current files, then copies the new ones. It asks for admin rights only if the game folder needs them.
8. **Another game?** You can optimize the next game without restarting the script.

#### Example output (Battlefield 4)

```
=== Battlefield Optimizer v2.0.0 - Battlefield 4 (user.cfg + PROFSAVE_profile) ===

--- Hardware ---
CPU      : Intel(R) Core(TM) i7-8700K CPU @ 3.70GHz  (6 cores / 12 threads)
RAM      : 48 GB
GPU      : NVIDIA GeForce RTX 3080 Laptop GPU  (16 GB VRAM)
System   : Laptop
Display  : 144 Hz (current Windows refresh rate)

--- user.cfg ---
  PerfOverlay.DrawFps 1
  GameTime.MaxVariableFps 144
  RenderDevice.RenderAheadLimit 1
  RenderDevice.TripleBufferingEnable 0
  RenderDevice.VSyncEnable 0
  WorldRender.MotionBlurEnable 0
FPS cap      : 144  -> no VRR: matches the display refresh rate (stable frame times and temperatures)

--- PROFSAVE_profile ---
Graphics tier: HIGH  (based on: GPU model)
Based on your current profile: keybinds, mouse, FOV, audio and resolution are preserved.
Changes:
  GstRender.AmbientOcclusion: 2 -> 0
  GstRender.AntiAliasingDeferred: 2 -> 0
  ...
```

### Output folders

Each game gets its own folder next to the script:

```
Battlefield_Optimizer.cmd
BF4_Optimized\
├── user.cfg            <- goes into the game folder
├── PROFSAVE_profile    <- goes into Documents\Battlefield 4\settings
└── README.txt          <- full report: hardware, changes, instructions
BF6_Optimized\
└── ...
```

- If the script's folder can't be written to, the folders go on your Desktop instead. The exact path is printed and saved in `README.txt`.
- Running the script again replaces the files in these folders. Your game files are only changed if you answer **Y**.

---

## Where to put the files

This applies to both the web page and the script.

| File | Goes to | Notes |
|---|---|---|
| `user.cfg` | The game's install folder, next to the game's `.exe` | Read at every launch |
| `PROFSAVE_profile` | `Documents\<game>\settings\` | Copy **with the game closed**; the game rewrites it when it exits |

**BF V and BF6:** if the settings folder has a `steam`, `ea` or `epic` subfolder, the profile is inside the one for your launcher. The script finds it automatically.

**Typical game folders:**

| Game | EA app | Steam |
|---|---|---|
| Battlefield 4 | `C:\Program Files\EA Games\Battlefield 4` | `...\steamapps\common\Battlefield 4` |
| Battlefield 1 | `C:\Program Files\EA Games\Battlefield 1` | `...\steamapps\common\Battlefield 1` |
| Battlefield V | `C:\Program Files\EA Games\Battlefield V` | `...\steamapps\common\Battlefield V` |
| Battlefield 6 | `C:\Program Files\EA Games\Battlefield 6` | `...\steamapps\common\Battlefield 6` |

Older Origin installs use `C:\Program Files (x86)\Origin Games\<game>`.

To find the folder:
- **EA app:** right-click the game > **View properties > Browse**.
- **Steam:** right-click the game > **Manage > Browse local files**.

Make sure Windows doesn't save the file as `user.cfg.txt`.

---

## How settings are chosen

The presets favor **visibility, low input lag and frame rate** for competitive play over visual effects. Your resolution, refresh rate, FOV, brightness, HUD, keybinds, mouse and controller settings, and audio are **never changed**.

### FPS cap

| Your setup | FPS cap | Why |
|---|---|---|
| G-Sync / FreeSync on | Below your refresh rate, with more margin at higher rates: 60 Hz → 57, 144 Hz → 138, 165 Hz → 157, 240 Hz → 224 | Keeps every frame inside the variable refresh range, so there's no tearing or V-Sync lag at the top |
| Laptop, or no VRR | Your refresh rate | Even frame times, and lower laptop temperatures |
| Strong desktop, no VRR | BF4 / BF1 / BF V: 2× refresh rate (max 300). BF6: limiter off | Higher FPS means lower input lag |

"Strong" means a High-tier GPU with 8+ threads, or 12+ threads for BF6.

**Where the cap goes:**
- **BF4, BF1 and BF V:** in `user.cfg`.
- **BF6:** in its own frame limiter, inside `PROFSAVE_profile`.

**BF4 only:** in exclusive fullscreen, BF4 can run the display at a higher refresh rate than the Windows desktop, which laptops often leave at 60 Hz. The script uses the game's fullscreen rate when that's the case.

### `user.cfg`

**Battlefield 4, 1 and V:**

| Command | Value | Purpose |
|---|---|---|
| `PerfOverlay.DrawFps` | `1` | On-screen FPS counter; set it to `0` to hide it |
| `GameTime.MaxVariableFps` | see above | Frame rate cap |
| `RenderDevice.RenderAheadLimit` | `1`, or `2` on CPUs with 4 threads or fewer | Frames the CPU queues ahead of the GPU; fewer means less input lag |
| `RenderDevice.TripleBufferingEnable` | `0` | Triple buffering adds latency |
| `RenderDevice.VSyncEnable` | `0` | V-Sync is handled by the driver, or off |
| `WorldRender.MotionBlurEnable` | `0` | Makes sure motion blur is off |

**Battlefield 6** gets CPU thread settings instead. This is a widely used community fix for BF6's high CPU usage, and it's **optional**: if the game runs worse with it, use Undo.

| Command | Value |
|---|---|
| `Thread.ProcessorCount` | your core count |
| `Thread.MaxProcessorCount` | your core count |
| `Thread.MinFreeProcessorCount` | `0` |
| `Thread.JobThreadPriority` | `0` |
| `GstRender.Thread.MaxProcessorCount` | your thread count |

If you already have a `user.cfg`, the script keeps your own lines and only replaces the commands it manages.

### GPU tiers

The tier comes from the **GPU model**, not just its VRAM: a 4 GB GT 1030 is still a very slow card. Laptop GPUs follow the same rules as their desktop versions. Unknown models fall back to VRAM size.

**Battlefield 4, 1 and V:**

| Tier | NVIDIA | AMD | Intel |
|---|---|---|---|
| **High** | RTX 2060 and up (except 2050 / 3050), GTX 1070 / 1080 / 980 Ti / 1660 Ti / 1660 SUPER, TITAN | RX 5700, RX 6600 and up, 7000 / 9000 series, Vega 56 / 64, Radeon VII, Radeon 8060S | Arc A750 / A770, B-series |
| **Medium** | RTX 2050 / 3050, GTX 1660 / 1650 / 1060 / 970 / 980 | RX 470–590, 5500 / 5600, 6500 XT, Radeon 680M / 760M / 780M / 880M / 890M | Arc A380 / A580 |
| **Low** | GTX 1630 / 1050 and older, GT, MX | RX 6400 / 6300 / 460 / 550 / 560, R7 / R9 / HD, Vega and other older integrated graphics | UHD, Iris Xe, integrated and laptop Arc |

VRAM fallback: under 4 GB is Low, 4–7 GB is Medium, 8 GB or more is High.

**Battlefield 6** is much heavier, so its tiers follow the official specs. The minimum is RTX 2060 / RX 5600 XT / Arc A380; the recommended is RTX 3060 Ti / RX 6700 XT / Arc B580.

| Tier | NVIDIA | AMD | Intel |
|---|---|---|---|
| **High** | RTX 3060 Ti, desktop 4060 / 4060 Ti, 2080 and up, 3070 and up, most 40 / 50 series | RX 6700 XT and up, 7700 XT and up, 9000 series | Arc B580 |
| **Medium** | RTX 2060 SUPER / 2070 / 3060 / 4050 / laptop 4060 / 5050, GTX 1080 Ti, TITAN Xp / V | RX 5700, 6600-class, 7600-class, Radeon VII, laptop RX 6600M / 6x00S / 7x00S, Radeon 8060S | Arc A750 / A770 / A580, B570 |
| **Low** | RTX 2050 / 2060 / 3050, other GTX, GT, MX | Older RX, integrated graphics | Arc A3x0, laptop and integrated Arc |

VRAM fallback: under 6 GB is Low, 6–9 GB is Medium, 10 GB or more is High.

### Graphics settings per game

**Same in every game and tier:**
- **Off:** motion blur, weapon depth of field, ambient occlusion, Enlighten, transparent shadows and in-game V-Sync. Also chromatic aberration, film grain, lens distortion and vignette in the games that have them.
- **Low:** undergrowth (less grass hiding prone players) and post-processing (less bloom and haze).
- **Weak CPUs (4 threads or fewer):** mesh and terrain quality are capped at Medium, since they add CPU draw calls.

**Battlefield 4**

| Setting | High | Medium | Low |
|---|---|---|---|
| Textures / mesh / terrain / filtering | Ultra | High | Medium |
| Effects / lighting / shadows | Medium | Medium | Low |
| Anisotropic filtering | 16x | 16x | 4x |
| Antialiasing post | Off | FXAA Low | FXAA Low |
| MSAA | Off | Off | Off |
| Resolution scale | 125% | 100% | 100% |

On High tier, rendering at 125% gives a sharper image than MSAA for much less cost. Head tracking and speech recognition are turned off.

**Battlefield 1**

| Setting | High | Medium | Low |
|---|---|---|---|
| Textures / mesh / terrain / filtering | Ultra | High | Medium |
| Effects / lighting / shadows | Medium | Medium | Low |
| Anisotropic filtering | 16x | 16x | 4x |
| Antialiasing post | TAA | FXAA High | FXAA Medium |
| GPU memory restriction | Off | On | On |

BF1 is switched to **DirectX 11**, which gives steadier frame times than its DX12 mode. TAA keeps foliage and fences from shimmering. Sniper sweet-spot blur is off.

**Battlefield V**

| Setting | High | Medium | Low |
|---|---|---|---|
| Textures | High | Medium | Low |
| Texture filtering | High | High | Medium |
| Mesh / terrain | High | Medium | Low |
| Effects / lighting / shadows | Medium | Low | Low |
| Ray tracing (DXR) | as you set it | Off | Off |

Textures are limited by VRAM: High needs 6 GB or more, Medium 4 GB. Your **anti-aliasing, DirectX 12 and DLSS** settings are left as you set them.

**Battlefield 6**

| Setting | High | Medium | Low |
|---|---|---|---|
| Textures | High | Medium | Low |
| Texture filtering | High | High | Medium |
| Mesh / terrain | High | Medium | Low |
| Effects / lighting / shadows / sun shadows / shadow filtering | Medium | Low | Low |

**On every tier:**
- **Off:** frame generation (it adds input lag), ray-traced ambient occlusion and screen space reflections.
- **Low:** volumetric fog, reflections and local light shadows.
- **On:** NVIDIA Reflex, AMD Anti-Lag and Intel XeLL. Only the one for your GPU is used.

**Caps:**
- Textures are limited by VRAM: High needs 8 GB or more, Medium 6 GB.
- Mesh and terrain are capped at Medium on CPUs with fewer than 8 cores or 8 threads, and on laptops, because BF6 is CPU-heavy.

Upscaling (DLSS / FSR / XeSS), dynamic resolution and HDR are left as you set them. On Low-tier GPUs, turn on upscaling at Quality for a big FPS gain.

---

## Recommended driver settings

The script prints these for your GPU at the end, and the web page shows them too.

**NVIDIA Control Panel** (Manage 3D settings > Program settings > the game's `.exe`):

| Setting | With G-Sync | Without G-Sync |
|---|---|---|
| G-Sync | On | — |
| Vertical sync | **On** | Off |
| Low Latency Mode | On (BF6: Off, Reflex is used in-game) | On (BF6: Off) |
| Power management mode | Prefer maximum performance | Prefer maximum performance |

**AMD Software: Adrenalin Edition:**

| Setting | With FreeSync | Without FreeSync |
|---|---|---|
| AMD FreeSync | On | — |
| Wait for Vertical Refresh | Always on | Off |
| Radeon Anti-Lag | On (BF6: turned on in-game by the profile) | On |

With variable refresh, V-Sync goes **on in the driver** and stays **off in the game**. Together with the FPS cap, that gives smooth, tear-free, low-latency output.

---

## How hardware detection works

This applies to the script only. On the web page, you pick your hardware yourself.

| What | Source |
|---|---|
| CPU, cores, threads | `Win32_Processor` |
| RAM | `Win32_ComputerSystem` |
| GPU name and VRAM | Display driver registry key. `Win32_VideoController` caps VRAM at 4 GB, so it's only a fallback |
| Main GPU | NVIDIA / AMD / Arc preferred over integrated graphics, then the most VRAM |
| Refresh rate | `Win32_VideoController.CurrentRefreshRate`. With several monitors, you're asked which one you play on |
| Laptop vs. desktop | Portable chassis type (battery only as a fallback) |
| Monitor capabilities | EDID read from the registry |
| Game folder | EA app / Origin and Steam registry entries, then default folders. For BF V and BF6, also the usual library folders on every drive |
| Documents folder | Windows known-folder API (works with OneDrive) |

**The EDID is checked for:**
- the refresh range;
- the AMD FreeSync block;
- HDMI 2.1 VRR;
- DisplayPort Adaptive-Sync;
- a VRR-style range descriptor;
- the NVIDIA vendor block, as a hint that G-Sync is present.

The script also warns you if Windows runs your monitor below its maximum refresh rate, or if the game itself is set lower than your display.

---

## Safety, backups and Undo

- **Nothing on your system is changed unless you answer Y.** By default, the script only writes to the `<game>_Optimized` folders.
- Before replacing a file, it saves a backup next to it, named `PROFSAVE_profile.bak_YYYYMMDD_HHMMSS` or `user.cfg.bak_YYYYMMDD_HHMMSS`.
- **Undo:** run the script, pick the same game and choose **2) Undo the last apply**. Each Undo goes one step further back. If there was no `user.cfg` before, Undo deletes it.
- It only touches the games' own plain-text config files. No DLLs, no injection, no game files modified, no registry changes.
- Admin rights are requested only to copy `user.cfg` into a protected game folder, and only for that one copy.
- `ExecutionPolicy Bypass` applies to this one PowerShell process only. Your system policy isn't changed.
- **The web page** never uploads anything: your profile is read and edited in your browser.

**Restoring by hand:** close the game, delete the new file, and rename the newest `.bak_` file back to `PROFSAVE_profile` or `user.cfg`. Alternatively, in-game, choose a graphics preset and apply it; the game rewrites the profile with its own values.

---

## FAQ

**Should I use the web page or the script?**
- **Web page:** if you don't want to run anything on your PC, you're on another device, or you just want to see the values first.
- **Script:** if you want automatic detection, one-click install and Undo.

**Can I get banned for this?**
`user.cfg` and `PROFSAVE_profile` are the games' own configuration files, used by the community for years. Neither option modifies game files, injects code or touches memory. Still, use them at your own risk; see the [Disclaimer](#disclaimer).

**I changed video settings in-game and my tweaks are gone.**
That's expected: the game rewrites `PROFSAVE_profile` whenever you apply video options. Run the script again or regenerate the profile on the web page. `user.cfg` isn't affected.

**Can I run it more than once?**
Yes, for example after upgrading your GPU or monitor. Each install creates a new backup.

**I prefer higher visual quality.**
Apply the files, then raise individual options in-game. Your keybinds and other personal settings stay intact either way.

**Why is my FPS capped at 138 / 144?**
See [FPS cap](#fps-cap). For BF4 / BF1 / BF V, edit `GameTime.MaxVariableFps` in `user.cfg`; `0` means no cap. For BF6, change the frame rate limit in the game's options.

**Why do BF V and BF6 need my profile?**
Their profiles hold many settings besides graphics: a BF6 profile has almost 1,000. One built from scratch would reset your HUD, keybinds and audio, so both the script and the web page only edit your existing file.

**I have multiple monitors.**
The script asks for the refresh rate of the monitor you play on. On the web page, choose that monitor's refresh rate.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| Windows SmartScreen blocks the script | Click **More info > Run anyway**, or right-click > **Properties** > tick **Unblock**. Right-click > **Edit** lets you read the script first. |
| The window closes immediately | Make sure the file still ends in `.cmd`, not `.cmd.txt`. If you edited it, save it with Windows (CRLF) line endings. |
| "No ... profile found" / "no PROFSAVE_profile was generated" | Start the game, reach the main menu, close it, then run the script again. |
| The game shows as "not detected" in the menu | It's installed in an unusual folder. Put `Battlefield_Optimizer.cmd` in the game folder (next to the `.exe`) and run it from there. |
| Wrong GPU detected on a laptop | Check that the dedicated GPU is enabled in Device Manager and the drivers are installed. Open an issue with your `README.txt`. |
| "model not recognized" next to the GPU tier | The VRAM fallback was used. Please open an issue with the GPU name shown in `README.txt`. |
| G-Sync / FreeSync not detected but you have it | Answer **Y**. Some panels, especially laptop screens, don't advertise VRR in their EDID. |
| Windows shows 60 Hz on a high refresh monitor | Settings > System > Display > Advanced display > pick the highest refresh rate, then run the script again. |
| "Permission declined" when copying `user.cfg` | Accept the Windows admin prompt, or copy the file by hand from the `<game>_Optimized` folder. |
| Settings reverted after playing | You probably changed video options in-game. Run the script again. |
| Web page: download button for BF V or BF6 is greyed out | Load your current `PROFSAVE_profile` for that game in step 6 first. |

---

## Limitations

- **VRR detection is a hint.** The script reads what the monitor advertises, not the driver's state, so it asks you to confirm.
- **The GPU and CPU lists are hand-made.** New or rare models fall back to VRAM size or manual input until they're added.
- **The presets are competitive-oriented:** visibility and FPS come first, visuals second.
- **Some values are undocumented by the games**, such as anti-aliasing levels in BF1. Check the in-game options after applying.
- **The script is Windows only.** The web page works anywhere.
- It has been tested on a limited number of systems, so feedback is very welcome.

---

## Contributing

Issues and pull requests are welcome! These are especially useful:

- **GPUs or CPUs missing from the lists.** Include the exact name shown in `README.txt`.
- **Monitors whose G-Sync / FreeSync isn't detected.** Include the monitor model and connection type (DP / HDMI).
- **Before / after results** on your hardware: FPS, 1% lows, temperatures.

**Editing the script:**
- Keep `.cmd` files with **CRLF** line endings; the repository's `.gitattributes` enforces this. Keep the file ASCII-only.
- Per-game data (folders, Steam IDs, process names) is in the `$Games` table at the top.
- GPU tiers are in `Get-GpuTierClassic` and `Get-GpuTierBf6`. Rules are checked top to bottom and the first match wins, so put exceptions above broader patterns.
- Graphics values are in `Get-ProfileSettingsBf4`, `...Bf1`, `...Bfv` and `...Bf6`.

**Editing the web page:** `index.html` is a single self-contained file. The CPU and GPU lists are at the top of its script.

**Repository layout:**

```
Battlefield_Optimizer.cmd   # Windows script (batch launcher + PowerShell)
index.html                  # web page (GitHub Pages)
README.md                   # this file
LICENSE                     # MIT license
.gitattributes              # keeps CRLF line endings for .cmd files
```

---

## Disclaimer

This project is not affiliated with, endorsed by or connected to Electronic Arts or DICE. Battlefield is a trademark of Electronic Arts Inc.

The script and the web page are provided "as is", without warranty of any kind. Always keep backups of your settings. Use at your own risk.

---

## License

[MIT](LICENSE)
