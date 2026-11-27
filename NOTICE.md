# Notices

## What this repository contains

Source code and build scripts only. **No part of Gran Turismo 4 or Spec II is included:** no disc image, executable,
game code, textures, audio, logos or other assets. `make_ipa.sh` reads the player's own disc on their own Mac, and the
app it makes stays with that player.

Two files describe the game's program without containing it:

- `docs/inputs/spec2-patches.json`, from the gt4-staticrecomp project: the 35 words that Spec II's own loader writes
  into the game when it boots, recorded so the translated code includes them. Each entry is checked against the player's
  own disc before it is used.
- `scripts/spec2_ios_hud_patch.py`, this port's own: six HUD instructions of the game turned into reads of values the
  app sets for the screen's shape.

The other `docs/inputs/*.json` files are fingerprints (hashes and sizes) the build uses to check that each step worked
on the expected input.

The Spec II mod, HD texture packs and memory cards are third-party or the player's own, and are **not** included. The
player supplies them. The home screen icon is this project's own drawing, or a picture the player chooses.

## Licenses

| Part | License | Where |
|---|---|---|
| gt4-staticrecomp (GT4Recomp): recompilation, runtime, renderers, CoreGS 2.0 (`native/`, `scripts/`, `tools/`) | MIT | [LICENSE](LICENSE) |
| macOS port it builds on (gt4-recomp-mac) and the iOS port added here (`ports/ios`, `make_ipa.sh`) | MIT | [LICENSE](LICENSE) |
| ps2-web-recomp, the translator and PS2 runtime (`make_ipa.sh` fetches it, or takes it from the sources bundle) | MIT | its repository |
| Changes to PCSX2's GS for iOS (`ports/ios/patches/gt4recomp-gs-ios.patch`) | GPL-3.0-or-later | [ports/ios/patches/LICENSE-GPL-3.0.txt](ports/ios/patches/LICENSE-GPL-3.0.txt) |
| PCSX2's GS ([gt4recomp-gs](https://github.com/moesuito/gt4recomp-gs), PCSX2 v2.8.2 based; its macOS fork [vgs499p/gt4recomp-gs](https://github.com/vgs499p/gt4recomp-gs) is what `make_ipa.sh` fetches) | GPL-3.0-or-later | [ports/ios/patches/LICENSE-GPL-3.0.txt](ports/ios/patches/LICENSE-GPL-3.0.txt) |
| SDL3 and the libraries built by `ports/ios/build_gs_deps.sh`, MoltenVK, glslang | their own (zlib, MIT, BSD, FTL, Apache-2.0) | their sources |
| Third-party code inside `native/` (xxHash, stb_image and others) | their own | [native/THIRD_PARTY.md](native/THIRD_PARTY.md) and file headers |

Because a built app links PCSX2's GS, **the app as a whole is under the GPL-3.0**. Its complete source is this
repository plus the GS fork at the commit `ports/ios/pins.sh` names, with the patch in `ports/ios/patches` applied.
The sources bundle (`ports/ios/make_deps_bundle.sh`) carries that GS source, with its own licence files, as well.

## Trademarks

Gran Turismo is © Sony Interactive Entertainment, developed by Polyphony Digital. PlayStation 2 is a trademark of Sony
Interactive Entertainment. This project isn't affiliated with or endorsed by either, or by the authors of Spec II.
