#!/usr/bin/env bash
# Gran Turismo 4 Spec II for iPhone: turns YOUR OWN Spec II disc image into an app (.ipa) you can sideload.
#
#   ./make_ipa.sh <Spec II v1.10 .iso> [options]
#
# options:
#   --icon FILE        a square picture (PNG or JPEG) to use as the home screen icon (default: a plain icon)
#   --bundle-id ID     app identifier (default com.example.gt4spec2; sideloading tools usually replace it)
#   --deps FILE        the sources bundle to build from (default: deps/gt4spec2-ios-deps-1.tar when it is there)
#   --clean            start over (deletes build/ and private/, the downloads and everything made from your disc)
#
# Needs a Mac with Apple silicon, Xcode (from the App Store, opened once) and Homebrew:
#   brew install bash cmake ninja python rust glslang
# The first run fetches and builds everything it needs (10-60 minutes, depending on the Mac); later runs reuse it.
# With the sources bundle from this repository's releases in deps/, nothing is downloaded; without it, the same
# pinned sources come from their official sites. Either way every piece is checked with sha256 before it is used.
# Nothing from the game is downloaded or stored anywhere but this folder; the .ipa holds code translated from YOUR
# disc, so it is yours alone: do not share it.
if [ -z "${BASH_VERSION:-}" ] || [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
  for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [ -x "$b" ] && exec "$b" "$0" "$@"; done
  echo "this script needs a newer bash: brew install bash" >&2; exit 1
fi
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

# --- what we accept and fetch ---------------------------------------------------------------------------------------
SPEC2_SHA256=$(sed -n 's/.*"sha256": "\([0-9a-f]\{64\}\)".*/\1/p' docs/inputs/spec2-iso.json | head -1)  # Spec II v1.10
# Every download is locked to an exact version and checked with sha256 before it is built or run: the git sources,
# MoltenVK and the Python packages in ports/ios/pins.sh, the C libraries in ports/ios/build_gs_deps.sh, the Rust
# crates by tools/wgsl_spirv/Cargo.lock (cargo --locked).

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }
[ $# -ge 1 ] || { usage; exit 2; }
case "$1" in -h|--help) usage; exit 0 ;; esac
iso="$1"; shift
icon=""; bundle_id="com.example.gt4spec2"; clean=0; deps_bundle=""
while [ $# -gt 0 ]; do
  case "$1" in
    --icon) icon="$2"; shift ;;
    --bundle-id) bundle_id="$2"; shift ;;
    --deps) deps_bundle="$2"; shift ;;
    --clean) clean=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option $1 (see ./make_ipa.sh --help)" >&2; exit 2 ;;
  esac
  shift
done

if [ -n "$deps_bundle" ]; then
  [ -f "$deps_bundle" ] || { echo "no such sources bundle: $deps_bundle" >&2; exit 2; }
  DEPS_BUNDLE="$(cd "$(dirname "$deps_bundle")" && pwd)/$(basename "$deps_bundle")"
fi
GT4_ROOT="$ROOT"
source ports/ios/pins.sh
export DEPS_BUNDLE  # build_gs_deps.sh runs as its own process

LOG="$ROOT/build/logs"
PY="$ROOT/private/tooling-venv/bin/python"
step() { printf '\n== %s\n' "$*"; }
fail() { printf '\nerror: %s\n' "$*" >&2; exit 1; }
# runs a long step quietly into a log file; on failure shows its end
quiet() { local log="$LOG/$1.log"; shift; if ! "$@" > "$log" 2>&1; then tail -30 "$log" >&2; fail "see $log"; fi; }

# --- 1. this Mac ---------------------------------------------------------------------------------------------------
step "1/7 checking this Mac"
[[ "$ROOT" != *" "* ]] || fail "move this folder somewhere without spaces in its path (now: $ROOT)"
[ "$(uname -m)" = arm64 ] || fail "this needs a Mac with Apple silicon"
[ -d /Applications/Xcode.app ] || fail "install Xcode from the App Store and open it once"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun --sdk iphoneos --show-sdk-path > /dev/null 2>&1 || fail "Xcode has no iOS SDK: open Xcode > Settings > Components"
missing=()
for tool in cmake ninja python3 git curl cargo glslangValidator; do command -v "$tool" > /dev/null || missing+=("$tool"); done
if [ ${#missing[@]} -gt 0 ]; then
  names="${missing[*]}"; names="${names/python3/python}"; names="${names/cargo/rust}"; names="${names/glslangValidator/glslang}"
  fail "missing tools: ${missing[*]} (brew install $names)"
fi
python3 -I -c 'import sys; sys.exit(not (3, 10) <= sys.version_info[:2] <= (3, 14))' \
  || fail "python3 must be version 3.10 to 3.14 (now $(python3 --version)): brew install python@3.14"
if ! xcrun -sdk iphoneos metal --version > /dev/null 2>&1; then
  echo "downloading Apple's Metal shader compiler (Xcode component, once)"
  xcodebuild -downloadComponent MetalToolchain > /dev/null || fail "could not download the Metal toolchain: Xcode > Settings > Components"
fi
[ -f "$iso" ] || fail "no such disc image: $iso"
iso="$(cd "$(dirname "$iso")" && pwd)/$(basename "$iso")"
[ "$clean" = 0 ] || rm -rf build private ports/ios/deps ports/ios/local-res
mkdir -p "$LOG" private
echo "Xcode $(xcodebuild -version | head -1 | cut -d' ' -f2), $(cmake --version | head -1)"
if use_bundle; then echo "sources: the bundle $(basename "$DEPS_BUNDLE") (no downloads)"
else echo "sources: their official sites (no bundle in deps/)"; fi

# --- 2. the disc ---------------------------------------------------------------------------------------------------
step "2/7 checking your disc"
if [ ! -f "private/disc-checked.$SPEC2_SHA256" ]; then
  echo "reading $(basename "$iso") (a minute)"
  sha=$(shasum -a 256 "$iso" | cut -d' ' -f1)
  [ "$sha" = "$SPEC2_SHA256" ] || fail "this is not the Gran Turismo 4 Spec II v1.10 image this port is built for
  (sha256 $sha, expected $SPEC2_SHA256). Spec II is made by applying the Spec II patch to your own
  Gran Turismo 4 Online Public Beta (USA) disc; see BUILDING.md."
  touch "private/disc-checked.$SPEC2_SHA256"
fi
echo "Gran Turismo 4 Spec II v1.10"

# --- 3. the game's code, translated from your disc -----------------------------------------------------------------
step "3/7 translating the game from your disc (10-20 minutes the first time)"
if [ ! -x "$PY" ]; then
  quiet pip make_tooling_venv private/tooling-venv
fi
DONOR=private/references/ps2-web-recomp
if [ ! -f "$DONOR/.tree-$DONOR_TREE_SHA256" ]; then
  quiet donor-fetch fetch_donor "$DONOR"
  touch "$DONOR/.tree-$DONOR_TREE_SHA256"
fi
ELF=private/slice272-spec2-elf/SCUS_974.36
[ -f "$ELF" ] || quiet elf "$PY" -E -s scripts/spec2_elf_patch.py --iso "$iso" --output private/slice272-spec2-elf
if [ ! -f private/spec2-gen/table.cpp ]; then
  mkdir -p private/spec2-tool private/spec2-seeds
  D="$DONOR/recomp"
  quiet translator clang++ -std=c++20 -O2 -o private/spec2-tool/eerecomp "$D/main.cpp" "$D/r5900.cpp" "$D/elf.cpp" \
    "$D/analysis.cpp" "$D/codegen.cpp" "$D/snr2.cpp"
  rm -rf private/spec2-gen-plain
  quiet translate-plain private/spec2-tool/eerecomp "$ELF" --out private/spec2-gen-plain --stats
  quiet seeds "$PY" -E -s scripts/spec2_entry_seeds.py --elf "$ELF" --generated private/spec2-gen-plain \
    --output private/spec2-seeds/entry-seeds.txt --json private/spec2-seeds/seeds.json
  quiet translate private/spec2-tool/eerecomp "$ELF" --entries private/spec2-seeds/entry-seeds.txt --out private/spec2-gen --stats
fi
# The race HUD for any screen shape (scripts/spec2_ios_hud_patch.py): the same translation of the HUD-patched ELF.
if [ ! -f private/spec2-aspect-gen/table.cpp ]; then
  [ -f private/spec2-aspect-elf/SCUS_974.36 ] || quiet hud-patch "$PY" -E -s scripts/spec2_ios_hud_patch.py --elf "$ELF" \
    --output private/spec2-aspect-elf
  quiet translate-hud private/spec2-tool/eerecomp private/spec2-aspect-elf/SCUS_974.36 \
    --entries private/spec2-seeds/entry-seeds.txt --out private/spec2-aspect-gen --stats
fi
# Runtime pieces, each checked against its pin by CMake: renderer port and shaders, runtime capsule, license guard,
# VU microcode tables.
[ -f private/macos-port/gpu.cpp ] || quiet port "$PY" -E -s scripts/prepare_external_vulkan.py private/macos-port --gs-stream-hooks
if [ ! -f private/macos-shaders/raster.spv ]; then
  quiet wgsl-tool build_wgsl_tool build/wgsl_spirv
  quiet wgsl build/wgsl_spirv/release/gt4-wgsl-spirv "$DONOR/runtime/src/gs/gpu/gs.wgsl" private/macos-shaders
fi
[ -f private/spec2-runtime/runtime.json ] || quiet runtime "$PY" -E -s scripts/prepare_perf_runtime.py private/spec2-runtime \
  --assets-root . --mtvu --gs-stream --frame-cost --spec2-iop
[ -f private/spec2-license-guard/runtime.json ] || quiet guard "$PY" -E -s scripts/prepare_license_guard.py \
  private/spec2-license-guard --assets-root . --display-aspect --frame-counters
[ -f private/spec2-vu/summary.json ] || quiet vu "$PY" -E -s ports/macos/spec2_vu_generate.py "$ELF" private/spec2-vu
echo "done"

# --- 4. libraries for iOS ------------------------------------------------------------------------------------------
step "4/7 libraries for iOS (first time only)"
if [ ! -f ports/ios/deps/MoltenVK/MoltenVK/static/MoltenVK.xcframework/ios-arm64/libMoltenVK.a ]; then
  echo "MoltenVK"
  quiet moltenvk fetch_moltenvk ports/ios/deps
fi
if [ ! -f private/ios-gs-deps/lib/libSDL3.a ]; then
  echo "SDL3, freetype, zstd, lz4, libpng, libjpeg-turbo, libwebp, plutovg, plutosvg, rapidyaml"
  quiet deps ports/ios/build_gs_deps.sh
fi
echo "ready"

# --- 5. PCSX2's GS (graphics) with the iOS changes ------------------------------------------------------------------
step "5/7 PCSX2's graphics core for iOS (first time: 10-20 minutes)"
GS=private/references/gt4recomp-gs
GSB=build/ios-gs
if [ ! -f "$GS/.ios-patched-$GS_TREE_SHA256" ]; then
  quiet gs-fetch fetch_gs "$GS"
  pinned_git -C "$GS" apply --whitespace=nowarn "$ROOT/ports/ios/patches/gt4recomp-gs-ios.patch" || fail "the iOS patch did not apply"
  touch "$GS/.ios-patched-$GS_TREE_SHA256"
fi
if [ ! -f "$GSB/pcsx2-gt4gs/libgt4-gs.a" ]; then
  quiet gs-configure cmake -G Ninja -S "$GS" -B "$GSB" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=aarch64 -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_PREFIX_PATH="$ROOT/private/ios-gs-deps" -DCMAKE_FIND_ROOT_PATH="$ROOT/private/ios-gs-deps" \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
    -DENABLE_GT4GS=ON -DGT4GS_ONLY=ON -DENABLE_QT_UI=OFF -DENABLE_TESTS=OFF -DENABLE_GSRUNNER=OFF -DUSE_VULKAN=OFF
  quiet gs-build ninja -C "$GSB" pcsx2-gt4gs
fi
# Its Metal shaders: the GS build makes them for macOS only, so they are compiled for iOS here (Metal 2.3).
if [ ! -f "$GSB/metal-ios/Metal23.metallib" ]; then
  mkdir -p "$GSB/metal-ios"
  for shader in cas convert present merge misc interlace tfx fxaa; do
    quiet "metal-$shader" xcrun -sdk iphoneos metal -ffast-math -std=ios-metal2.3 -target air64-apple-ios17.0 \
      -o "$GSB/metal-ios/$shader.air" -c "$GS/pcsx2/GS/Renderers/Metal/$shader.metal"
  done
  quiet metallib xcrun -sdk iphoneos metallib -o "$GSB/metal-ios/Metal23.metallib" "$GSB"/metal-ios/*.air
fi
echo "ready"

# --- 6. the app ----------------------------------------------------------------------------------------------------
step "6/7 building the app (15-30 minutes the first time)"
quiet icon "$PY" -E -s ports/ios/make_icon.py ${icon:+--picture "$icon"}
quiet app-configure cmake -S . -B build/ios -G Xcode -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=17.4 -DGT4_IOS_BUNDLE_ID="$bundle_id"
quiet app-build xcodebuild -project build/ios/GT4Recomp.xcodeproj -target gt4 -configuration Release -sdk iphoneos \
  -jobs "$(sysctl -n hw.ncpu)" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
app=build/ios/ports/ios/Release-iphoneos/gt4.app
[ -x "$app/gt4" ] || fail "the app was not built (see $LOG/app-build.log)"

# --- 7. the .ipa ---------------------------------------------------------------------------------------------------
step "7/7 packing the .ipa"
mkdir -p dist
rm -rf build/ipa; mkdir -p build/ipa/Payload
cp -R "$app" build/ipa/Payload/
rm -f dist/GT4SpecII.ipa
(cd build/ipa && zip -qry "$ROOT/dist/GT4SpecII.ipa" Payload)
cat <<EOF

Done: dist/GT4SpecII.ipa ($(du -h dist/GT4SpecII.ipa | cut -f1))

Next (BUILDING.md has the details):
  1. Install it with Sideloadly or AltStore (they sign it with your Apple ID).
  2. Copy the same disc image onto the phone: Finder > your iPhone > Files > GT4 Spec II
       $(basename "$iso")
  3. Optional: your memory card as memcards/spec2.ps2, an HD texture pack's SCUS-97436 folder in gt4-gs/textures/.
This .ipa contains code translated from your disc. Keep it to yourself.
EOF
