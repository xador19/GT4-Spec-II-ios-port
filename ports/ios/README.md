# iOS (build it yourself)

Gran Turismo 4 Spec II 1.10 as an app for your own iPhone or iPad (arm64, A20 by default: `-DGT4_IOS_CPU=...` for
another chip). It is the macOS Spec II build (`ports/macos`, `GT4_TARGET=spec2`) with MoltenVK linked statically, SDL3
built from source and the built-in GS renderer. The app contains code translated from your disc: it is for your own
device only, don't share it.

## Build and install

Needs Xcode with the iOS platform, CMake, Ninja, Python 3, Rust (`brew install cmake ninja rust`) and a paid Apple
Developer account signed in to Xcode (the app asks for the increased memory limit entitlement).

```
ports/ios/build.sh --team TEAMID --iso "/path/to/Gran Turismo 4 (USA) (Spec II v1.10).iso" --install --copy-iso
```

1. patches the Spec II ELF from your disc and translates it into `private/spec2-gen` (stays on your Mac),
2. prepares the runtime pieces against their pins (renderer port and shaders, the slice276 Spec II runtime capsule,
   the slice277 license guard, the VU1 table and a VU0 table from the Spec II image),
3. builds `build/ios/ports/ios/Release-iphoneos/gt4.app` signed for your team (app ID `com.<team>.gt4spec2`),
4. installs it and copies the disc image into the app's Documents (3.4 GB, once).

Later rebuilds: `ports/ios/build.sh --team TEAMID --install`. `--check 1800` runs 1,800 frames on the device and copies
the log and frame dumps back to `private/ios-check`.

## On the device

The app's Documents folder (Files app > On My iPhone > GT4 Spec II): the `.iso`, `memcards/spec2.ps2`, an optional
`env.txt` (`NAME=value` lines for the `GT4_*` options) and `gt4.log` of the last session.

## Limits

- Controls: a Bluetooth or USB controller (SDL3 / GameController). No touch controls yet.
- An FPS counter in the top-left corner (guest VBlanks per second; 60 is full speed). `GT4_FPS=0` in env.txt hides it.
- Renderer: the built-in GS only. iOS apps cannot start the separate gt4-gs (PCSX2) process, so upscaling and texture
  packs are not available yet.
- No RetroAchievements: the app never contacts a server.
- Leaving the app pauses the game at the next VBlank; it continues when the app is back in front.
