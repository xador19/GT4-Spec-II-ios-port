# Developing the iOS port

How the pieces fit, where things live and the switches that help when something goes wrong. For building and installing
as a player, see [BUILDING.md](../BUILDING.md).

## The big picture

```
your Spec II .iso
  │  scripts/spec2_elf_patch.py      reads SCUS_974.36 from the disc, applies the 35 boot-time words of Spec II's loader
  │                                  (docs/inputs/spec2-patches.json), checks every step against docs/inputs pins
  │  scripts/spec2_ios_hud_patch.py  six HUD instructions become reads of the HUD parameter block (see Hooks)
  │  ps2-web-recomp's eerecomp       MIPS → C++ (private/spec2-aspect-gen/unit_XXXX.cpp, one per 16 KiB of code)
  │  scripts/spec2_entry_seeds.py    extra entry points so every reachable function is translated
  │  ports/macos/spec2_vu_generate.py  VU1/VU0 microprograms → C++ (ahead of time, private/spec2-vu)
  │  scripts/prepare_*.py            runtime "capsules": the donor runtime with this project's overlays, pinned
  ▼
ports/ios/CMakeLists.txt (Xcode)    → gt4.app: game code + runtime + host (native/) + iOS app (ports/ios)
                                        + PCSX2's GS (static libraries from build/ios-gs) + CoreGS 2.0 (native/hw_gs)
```

At run time the game runs on the app's main thread (SDL's `SDL_main`). Each guest VBlank, the window loop
(`native/window_sdl.cpp`) pumps iOS events, reads the controller (`native/host_io.cpp`) and paces the frame
(`native/pacing.cpp`). Graphics leave the game as a GS command stream (`native/gs_stream/`) to the chosen renderer:

- **PCSX2's GS** (`GT4_RENDERER=pcsx2`, default): `gs_stream_ipc.cpp` keeps the session in process memory and runs the
  GS's `gt4gs_main` on a thread. It draws into a `CAMetalLayer` the app creates (`ports/ios/gs_view.mm`). The iOS changes
  to the GS are in `ports/ios/patches/gt4recomp-gs-ios.patch`.
- **CoreGS 2.0** (`GT4_RENDERER=hw`): `native/hw_gs`, in process, Vulkan through MoltenVK onto the same layer.
- **The old built-in renderer** (`GT4_RENDERER=donor`): the donor's compute GS on MoltenVK, drawn into the SDL view.

## File map

| Where | What |
|---|---|
| `make_ipa.sh` | the player's one-command build (disc check, downloads, translation, GS, app, unsigned IPA) |
| `ports/ios/CMakeLists.txt` | the app target: sources, pins, resources, frameworks |
| `ports/ios/ios_main.mm` | app start: log file, `env.txt`, default settings files, disc and card, renderer options |
| `ports/ios/gs_view.mm` | the Metal view the renderers draw into; installs the touch overlay |
| `ports/ios/touch_controls.mm` | on-screen controls (floating stick, pedals, buttons, gear), tilt steering |
| `ports/ios/settings_screen.mm` | the settings screen; `ios_ui.h` is what the game side reads from it |
| `ports/ios/fps_overlay.mm` | frame-rate counter, thermal state in the log |
| `ports/ios/build_gs_deps.sh` | SDL3 and the GS's libraries built for iOS from pinned sources |
| `ports/ios/patches/` | the PCSX2 GS changes for iOS (GPL-3.0) |
| `ports/ios/make_icon.py` | the home screen icon |
| `ports/ios/build.sh` | a developer loop for people with a paid Apple developer team (signs, installs, runs a check) |
| `native/` | the host runtime shared with the PC and Mac builds: window, input, audio, pacing, hooks, GS stream |
| `native/hw_gs/` | CoreGS 2.0 (`hw_posix_compat.hpp` and `*_apple.cpp` are the Apple parts) |
| `scripts/` | the translation and capsule tools (Python); `docs/inputs/` holds their pins |

## Game-specific hooks

The translated code is plain C++, so the port changes the game in two ways: by patching instructions before translation
(the change is then compiled in), and by hooks in the runtime's dispatch, which every indirect call (`jalr`) goes through.

- **Screen shape** (`native/display_aspect.cpp`): a dispatch hook on the race camera's virtual call in
  `RaceBase::initMonitor` (Spec II 0x26BDB0) scales the projection matrix on the stack, Hor+ for wide screens and Vert+
  for taller ones like iPhones. A hook on `RaceDisplay::render` (0x1C5040) rewrites the HUD's orthographic matrix.
  Addresses per game build: `native/game_target.hpp`.
- **HUD parameter block** (guest RAM 0x7F00, five words): the font x scale, the mirror divisor, the HUD edge offset
  (float and integer) and the mini-map width. `scripts/spec2_ios_hud_patch.py` turns the game's immediates for these into
  loads from the block, and `display_aspect.cpp` fills it every VBlank. At 16:9 the block holds the original constants,
  so the game computes exactly what it did.
- **Controls** (`native/host_io.cpp`, iOS sections): the triggers drive the right stick's vertical axis (GT4 reads that
  as a plain analog value, while it boosts the pressure buttons); the trigger range scales them; touch input is merged
  there too.

## Settings and files on the phone

Everything lives in the app's Documents folder (Files app → GT4 Spec II):

| File | What |
|---|---|
| `*.iso` | the disc (the first `.iso` found is used) |
| `memcards/spec2.ps2` | the memory card |
| `gt4-gs.ini` | PCSX2 GS settings (the settings screen edits it; the allowed keys are the GS fork's allow-list) |
| `gt4-gs/textures/SCUS-97436/` | HD texture pack |
| `gt4-gs/cache`, `gt4-gs/coregs2-cache` | shader caches |
| `controls.toml` | controller bindings (format: `native/controls.hpp` and the project's controls docs) |
| `env.txt` | `NAME=value` lines applied as environment variables at start (debug switches below) |
| `gt4.log` | the log of the last session |

The settings screen's own values (touch, vibration, renderer, ...) are in the app's preferences (`NSUserDefaults`).

## Debug switches (`env.txt`)

| Variable | Effect |
|---|---|
| `GT4_RENDERER=pcsx2\|hw\|donor` | renderer, over the settings screen |
| `GT4_PERF=0` | no 5-second timing report in `gt4.log` (on by default) |
| `GT4_IOS_CHECK_FRAMES=N` | run N frames unattended, save every 300th frame in `frames/`, then close |
| `GT4_GS_FRAMES_IN_FLIGHT=1\|2\|3` | frames the game may queue ahead of the GS (1 by default, for lower input lag) |
| `GT4_DISPLAY_ASPECT=16:9` | force a picture shape instead of the screen's |
| `GT4_HW_SCALE`, `GT4_HW_TEXTURES`, other `GT4_HW_*` | CoreGS 2.0 options (`native/hw_gs/hw_gs_options.cpp`) |

What the log shows:

- `[perf]` every 5 seconds: frame rate, frame times and where the game's time went; `[gs-ipc] summary` splits the game's
  frame into its own work and waits for the GS.
- `[slow]` frames over two refreshes, with what grew (for example `gs_ipc_readback_wait`: the game waited for a GS
  readback, usually the lens-flare test).
- `[pad]` every button and trigger change as the controller reported it; `[link]` gaps in the controller's reports
  (Bluetooth dropouts).
- `[ios] thermal state` when the phone heats up (iOS then slows the GPU).
- `[aspect]` the screen shape, the HUD block and the camera hooks; `[core2]`/`[hw]` CoreGS 2.0.

## What the build downloads

The app itself never goes online: no update checks, no achievements, no downloads. PCSX2's GS is built with
`HTTPDownloaderNone` (no HTTP transport), and its other networked parts, which are linked with it (achievements, the
PINE IPC server, Discord presence, the emulated network adapter), are forced off in `pcsx2-gt4gs/Main.cpp` and are not
on the settings allow-list. Only the build on the Mac downloads source code, every piece locked to an exact version and
checked with sha256 before anything in it is built or run:

| What | Where it is pinned | Checked by |
|---|---|---|
| ps2-web-recomp, gt4recomp-gs (git, exact commits) | `ports/ios/pins.sh` | sha256 of every tracked file (`scripts/tree_sha256.py`) |
| MoltenVK v1.4.2 | `ports/ios/pins.sh` | sha256 of the archive |
| pycdlib 1.20.0, Pillow 12.0.0 (wheels only) | `ports/ios/requirements-build.txt` | `pip --require-hashes` |
| SDL3, freetype, zstd, lz4, libpng, libjpeg-turbo, libwebp, plutovg, plutosvg, rapidyaml | `ports/ios/build_gs_deps.sh` | sha256 of each archive |
| naga and the other Rust crates of `tools/wgsl_spirv` | `tools/wgsl_spirv/Cargo.lock` | cargo `--locked` (sha256 per crate) |

The **sources bundle** (`ports/ios/make_deps_bundle.sh` makes `dist/gt4spec2-ios-deps-1.tar`, for a release of this
repository) holds all of the above. When it is in `deps/` (or given with `make_ipa.sh --deps FILE`), the build makes no
downloads and checks every member against the same pins; the Rust crates are then the `cargo vendor` folder, checked by
tree (`CRATES_TREE_SHA256`).

Not pinned by this repository: Xcode and its Metal toolchain (Apple), and the Homebrew tools (`brew install`). Git runs
without the user's own git settings for these checkouts, so line-ending or URL-rewrite settings cannot change them.

## A development loop

With a paid Apple developer team you can sign, install and test in one go:

```bash
ports/ios/build.sh --team YOURTEAMID --iso "/path/to/Spec II.iso" --install --check 1800
```

`--check` runs 1800 frames on the phone and copies `gt4.log` and the frames back into `private/ios-check`. Run
`make_ipa.sh` once first: `build.sh` reuses what it made.
