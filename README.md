# I made a free one-click script that tunes BF4’s user.cfg and graphics profile to your hardware (detects G-Sync/FreeSync too)
Hey all,

I got tired of copying random user.cfg tweaks from 2014 threads, so I wrote a small script that looks at your actual hardware and builds the config for you.

What it does:

Detects your CPU, GPU, RAM, laptop vs desktop and your monitor’s refresh rate.
Reads your monitor’s EDID to check for G-Sync / FreeSync / HDMI VRR, then asks you to confirm.
Generates a user.cfg with the right FPS cap:
refresh − 3 with VRR;
refresh rate without VRR;
2× refresh on strong desktops.
Also sets render-ahead limit 1 for low input lag.
Generates a PROFSAVE_profile with a competitive preset for your GPU tier (High / Medium / Low, based on the actual GPU model, not just VRAM):
MSAA off and supersampling on for high-end cards;
post-processing and undergrowth on Low for better visibility;
texture/mesh detail kept up where your card can handle it.
Keeps your keybinds, sensitivity, FOV and audio. It edits your existing profile instead of replacing it.
Tells you exactly where each file goes, and only copies them if you say yes (with automatic backups).

What it isn’t:

No .exe, no installs, no DLLs, nothing injected. It’s a single .cmd file you can open in Notepad and read. Every section is commented.
It only writes the game’s own config files.

Link: https://github.com/j0p3s/Battlefield-4-user.cfg-and-profsave_profile-generator-and-optimizer/tree/main

It’s been tested on a limited number of machines (mine is an i7-8700K + RTX 3080 laptop on a 144 Hz panel). Feedback is very welcome, especially:

if your GPU shows “model not recognized”;
if your G-Sync/FreeSync monitor isn’t detected;
before/after FPS numbers.

See you on Locker. 🫡
