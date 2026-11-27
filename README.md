# GT4 Spec II for iPhone: Gran Turismo 4, recompiled

A native iPhone port of **Gran Turismo 4 Spec II** (the community mod of GT4, built on the US *Online Public Beta*,
SCUS-97436), made by *static recompilation*: the game's PS2 program is translated to C++ and compiled into a real iOS
app, instead of being emulated instruction by instruction. It runs at **60 frames per second**, at up to **4× the PS2's
resolution**, with **HD texture packs**, **touch controls**, **controller support** and an iOS **settings screen**.

> **This is a hobby project, released as is.** It was built and tested on one iPhone. It may not work on yours, and
> there's no guaranteed support. Claude built it with xador19, and it's shared because a lot of work went into it and
> it's cool that it exists. Issues and pull requests are welcome, but answers may be slow.

> **Unofficial fan project.** Not affiliated with, endorsed by or connected to Sony Interactive Entertainment,
> Polyphony Digital or the Spec II team. **No game files, ROMs, disc images (ISOs) or built `.ipa` files are shared
> here, and requests for them in issues won't be answered.**

**No game files are included or downloaded by anything here.** You build the app yourself from **your own disc**. The
resulting `.ipa` contains code translated from that disc, so it's yours alone. Please don't share it.

## What you get

- **Native speed.** The game's main processor code and its vector-unit microprograms run as compiled ARM code, with
  no JIT. The rest of the PS2 (sound and I/O processor, DMA, disc) is reproduced in software.
- **60 fps**, with frames paced to the screen and the race at full game speed.
- **Two renderers.** [PCSX2](https://github.com/PCSX2/pcsx2)'s GS on Metal (the default), or **CoreGS 2.0**, the
  [gt4-staticrecomp](https://github.com/moesuito/gt4-staticrecomp) project's own renderer, on MoltenVK
  (experimental on iPhone, see Known issues).
- **2×, 3× or 4×** the PS2's resolution, with high blending accuracy, 16× texture filtering and optional sharpening.
- **HD texture packs:** any PCSX2-format pack for SCUS-97436 works, for example the
  [Gran Turismo 4 Retexture Mod](https://www.gtplanet.net/forum/threads/gran-turismo-4-retexture-mod-v3-0-4.408852/) and the
  [HD HUD and user interface pack](https://www.gtplanet.net/forum/threads/gt4-hd-hud-and-user-interface-texture-pack-for-pcsx2.417873).
  Not included; bring your own.
- **Fits the iPhone screen.** Races fill the screen with the 3D view corrected for its shape, and the race HUD sits on
  the screen's edges. Menus and videos keep the game's 16:9 picture.
- **Touch controls** in the style of a phone racing game (a steering stick wherever your thumb lands, tap-to-drive gas
  and brake), shown when no controller is connected. **Tilt steering** as an option.
- **Controllers** (PlayStation, Xbox, MFi), with analog triggers for throttle and brake, stronger vibration and lower
  input lag.
- **Settings screen:** tap the gear at the top. Touch layout and button labels (PlayStation, Xbox or Nintendo),
  trigger range, vibration, renderer, resolution, blending, textures and the frame-rate counter.
- Shaders are remembered between sessions, so a car or track only stutters the first time it is ever drawn.
- iOS Game Mode, and your memory card from PCSX2 or a PS2 works as is.
- **Works offline.** The app never goes online: no update checks, no account, no downloads.

## What you need

- **A Mac with Apple silicon** and **Xcode** (free, from the App Store). The build has to happen on a Mac: iOS doesn't
  allow apps to compile code, so your disc is translated and compiled before the app is made.
- **Your own Gran Turismo 4 Spec II v1.10 disc image** (`.iso`). Spec II is made by applying the
  [Spec II patch](https://www.theadmiester.co.uk/specii/) to your own *Gran Turismo 4 Online Public Beta (USA)* disc;
  BUILDING.md explains how. The build checks the result (sha256
  `6a3484b9672c10a92154ecee6faa5bbcfd4ed8cd538d8283e429c3fe6e1704b2`).
- **An iPhone on iOS 17.4 or later.** A recent iPhone is recommended.
- **A way to sideload:** [Sideloadly](https://sideloadly.io) or [AltStore](https://altstore.io) with a free Apple ID,
  or Xcode with a developer account.

## Quick start

```bash
brew install bash cmake ninja python rust glslang
./make_ipa.sh "Gran Turismo 4 (USA) (Spec II v1.10).iso"
```

That builds `dist/GT4SpecII.ipa`. The first run takes 10 to 60 minutes depending on your Mac (about 10 on a recent
one); later runs are much faster. Then:

1. Install `GT4SpecII.ipa` with Sideloadly or AltStore.
2. Copy the same `.iso` onto the phone: Finder → your iPhone → **Files** → **GT4 Spec II**.
3. Optionally: your memory card as `memcards/spec2.ps2`, and a texture pack's `SCUS-97436` folder in `gt4-gs/textures/`.
4. Open GT4 Spec II.

**[BUILDING.md](BUILDING.md)** walks through every step: Spec II, textures, saves, settings and troubleshooting.
Coders who want to change the port: see **[docs/DEVELOPING.md](docs/DEVELOPING.md)**.

## Known issues

- Played on one real phone so far (an iPhone Duo, iOS 27). Other iPhones are untested. Phones with less memory may
  close the app, because a free Apple ID can't grant iOS's larger memory limit.
- **CoreGS 2.0 is experimental on iPhone:** it runs at full speed but draws grey square artifacts. PCSX2 is the
  default for that reason.
- Occasional short stutters remain with PCSX2's renderer, mostly when the game checks its lens flares and sun glare.
  4× resolution can drop below 60 fps on heavy tracks; 3× is the default.
- Some Bluetooth controllers drop out on iPhone for a few seconds (the last input then stays held). That's the
  controller's link, not the app; a wired controller avoids it.
- Changing the screen's shape while playing (a foldable phone opening or closing) is untested.
- Free Apple ID installs expire after 7 days. Sideloadly or AltStore can refresh them, and your save stays.

## How it works, briefly

1. **Translate.** The game's program (`SCUS_974.36`) is read from your disc, a few fixed patches that Spec II's own
   loader would apply are applied, and [ps2-web-recomp](https://github.com/snuri00/ps2-web-recomp)'s translator turns
   its MIPS code into C++. The VU1 and VU0 microprograms are compiled ahead of time too.
2. **Patch the HUD.** Six HUD constants of the game are turned into values the app sets for the screen's shape
   ([`scripts/spec2_ios_hud_patch.py`](scripts/spec2_ios_hud_patch.py)), so the HUD reaches the screen edges.
3. **Draw.** Graphics commands stream to PCSX2's GS, which runs on a thread inside the app on Metal, or to CoreGS 2.0.
4. **Build.** Everything is compiled with Xcode into one app, with no JIT and no emulator core translating code at
   runtime.

## What Claude added

On top of [gt4-staticrecomp](https://github.com/moesuito/gt4-staticrecomp) and its
[macOS port](https://github.com/vgs499p/gt4-recomp-mac):

- the iOS app: SDL3 window, Metal view, Files-app folder, memory card, settings screen, touch and tilt controls, icon
- PCSX2's GS inside the app on a thread (`ports/ios/patches`): JIT-free on ARM, Metal on iOS views, no shared memory
  the iOS sandbox refuses, its input sources off, and its shaders rebuilt at startup from a list it keeps
- CoreGS 2.0 on MoltenVK and Metal surfaces (`native/hw_gs`, `ports/ios/CMakeLists.txt`)
- the HUD-to-screen-edges patch for screens taller than 16:9, and the 3D view correction on iPhone screens
- controls: triggers on the right stick axis, a trigger range, a stronger vibration curve, lower input lag (one frame in
  flight, two drawables), controller link and timing logs
- `make_ipa.sh`: from your disc to an installable app in one command

## Credits

- [gt4-staticrecomp](https://github.com/moesuito/gt4-staticrecomp) (GT4Recomp) by João Alano (moesuito) and
  contributors, which started as a fork of [Kaezzey](https://github.com/Kaezzey)'s original gt4-staticrecomp: the
  recompilation, runtime, renderers and almost everything that makes the game run (MIT). Its README is kept in
  [docs/gt4-staticrecomp-README.md](docs/gt4-staticrecomp-README.md), with its own credits.
- [gt4-recomp-mac](https://github.com/vgs499p/gt4-recomp-mac) by vgs499p: the macOS port this iOS port grew from (MIT),
  and the macOS fork of the GS, [vgs499p/gt4recomp-gs](https://github.com/vgs499p/gt4recomp-gs), which `make_ipa.sh`
  downloads.
- [ps2-web-recomp](https://github.com/snuri00/ps2-web-recomp) by snuri00: the translator and PS2 runtime (MIT).
- [PCSX2](https://github.com/PCSX2/pcsx2): the GS renderer (GPL-3.0), through
  [gt4recomp-gs](https://github.com/moesuito/gt4recomp-gs).
- [Gran Turismo 4 Spec II](https://www.theadmiester.co.uk/specii/) by TheAdmiester and contributors (not included).
- The authors of the GT4 HD texture packs (not included).
- [iPSX2](https://github.com/Thiago-Heleno/iPSX2-src), whose iOS port showed how to live without shared memory in the
  iOS sandbox, and Silent, whose notes on GT4's trigger scaling explained the throttle curve.
- [SDL](https://github.com/libsdl-org/SDL), [MoltenVK](https://github.com/KhronosGroup/MoltenVK),
  [glslang](https://github.com/KhronosGroup/glslang) and the libraries in `ports/ios/build_gs_deps.sh`.

Gran Turismo is © Sony Interactive Entertainment, developed by Polyphony Digital. This project isn't affiliated with or
endorsed by Sony Interactive Entertainment or Polyphony Digital.

## License

The recompilation, runtime and iOS app code are MIT ([LICENSE](LICENSE)). The iOS app links PCSX2's GS, so **a built
app is under the GPL-3.0**. The PCSX2 changes are in [`ports/ios/patches`](ports/ios/patches) under the GPL-3.0, like
PCSX2. See [NOTICE.md](NOTICE.md).
