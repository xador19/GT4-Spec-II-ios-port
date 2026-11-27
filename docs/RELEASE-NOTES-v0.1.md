# GT4 Spec II for iPhone v0.1

The first public release: **Gran Turismo 4 Spec II, recompiled into a native iPhone app.** Build it from your own
disc with one command; no game files are included.

**This is a hobby project, released as is**, tested on one iPhone (an iPhone Duo on iOS 27). There's no guaranteed
support.

## What's in it

- The game's code compiled for the iPhone, at **60 fps**, no JIT.
- PCSX2's GS on Metal at 2×, 3× or 4× resolution, with **HD texture packs** (bring your own, for SCUS-97436).
- Races fill the iPhone screen with the 3D view corrected for its shape; the race HUD sits on the screen edges.
- **Touch controls** like a phone racing game, optional **tilt steering**, and **controllers** with analog triggers on
  the right stick, adjustable vibration and lower input lag.
- An iOS **settings screen** (the gear at the top): controls, picture, renderer and more.
- Shaders are remembered between sessions; iOS Game Mode.
- **CoreGS 2.0**, the upstream project's own renderer, as an experimental choice.

## Known issues

- Only tested on one phone. Older iPhones with less memory may close the app.
- CoreGS 2.0 draws grey square artifacts on iPhone; PCSX2 stays the default.
- Occasional short stutters with PCSX2's renderer, mostly around lens flares; 4× resolution can drop below 60 fps on
  heavy tracks.

## How to get it

Download the source (below), then follow [BUILDING.md](https://github.com/xador19/GT4-Spec-II-ios-port/blob/main/BUILDING.md):
`./make_ipa.sh "Gran Turismo 4 (USA) (Spec II v1.10).iso"`, then sideload `dist/GT4SpecII.ipa`.
