#!/bin/bash
# Builds the GT4 Spec II iOS app from your own disc (ports/ios/README.md).
#
#   ports/ios/build.sh --team TEAMID --iso FILE [--bundle-id ID] [--install] [--copy-iso] [--device ID]
#                      [--check FRAMES]
#
#   --team ID       your Apple Developer team ID (Xcode > Settings > Accounts)
#   --iso FILE      your Gran Turismo 4 Spec II 1.10 disc image (needed for the first build and for --copy-iso)
#   --bundle-id ID  app identifier, unique to your team (default: com.<team>.gt4spec2)
#   --install       install the app on the connected iPhone / iPad
#   --copy-iso      copy the disc image into the app's Documents on the device (once; 3.4 GB over USB)
#   --device ID     the device to use (xcrun devicectl list devices; default: the first available one)
#   --check FRAMES  after installing, run the game for FRAMES frames on the device and copy its log and every 300th
#                   frame back into private/ios-check (an unattended boot check)
set -euo pipefail
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

TEAM="" BUNDLE_ID="" ISO="" DEVICE="" INSTALL=0 COPY_ISO=0 CHECK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --team) TEAM="$2"; shift 2 ;;
    --bundle-id) BUNDLE_ID="$2"; shift 2 ;;
    --iso) ISO="$2"; shift 2 ;;
    --device) DEVICE="$2"; shift 2 ;;
    --install) INSTALL=1; shift ;;
    --copy-iso) COPY_ISO=1; shift ;;
    --check) CHECK="$2"; shift 2 ;;
    *) echo "unknown option $1 (see the top of ports/ios/build.sh)"; exit 2 ;;
  esac
done
[ -n "$TEAM" ] || { echo "--team TEAMID is required (Xcode > Settings > Accounts)"; exit 2; }
BUNDLE_ID="${BUNDLE_ID:-com.$(echo "$TEAM" | tr 'A-Z' 'a-z').gt4spec2}"
PY=private/tooling-venv/bin/python
GT4_ROOT="$PWD"
source ports/ios/pins.sh  # every download pinned and sha256-checked

ports/ios/fetch_deps.sh

# 1. Tools: the Python environment, the pinned MIT donor (runtime and translator source).
[ -x "$PY" ] || make_tooling_venv private/tooling-venv
if [ ! -f "private/references/ps2-web-recomp/.tree-$DONOR_TREE_SHA256" ]; then
  fetch_donor private/references/ps2-web-recomp
  touch "private/references/ps2-web-recomp/.tree-$DONOR_TREE_SHA256"
fi

# 2. The game, from your disc (stays on this Mac): the derived ELF with the Spec II patches, then the translated code.
ELF=private/slice272-spec2-elf/SCUS_974.36
if [ ! -f "$ELF" ]; then
  [ -n "$ISO" ] || { echo "--iso FILE is required for the first build"; exit 2; }
  "$PY" -E -s scripts/spec2_elf_patch.py --iso "$ISO" --output private/slice272-spec2-elf
fi
if [ ! -f private/spec2-gen/table.cpp ]; then
  mkdir -p private/spec2-tool private/spec2-seeds
  D=private/references/ps2-web-recomp/recomp
  clang++ -std=c++20 -O2 -o private/spec2-tool/eerecomp $D/main.cpp $D/r5900.cpp $D/elf.cpp $D/analysis.cpp \
          $D/codegen.cpp $D/snr2.cpp
  rm -rf private/spec2-gen-plain
  private/spec2-tool/eerecomp "$ELF" --out private/spec2-gen-plain --stats | tail -1
  "$PY" -E -s scripts/spec2_entry_seeds.py --elf "$ELF" --generated private/spec2-gen-plain \
        --output private/spec2-seeds/entry-seeds.txt --json private/spec2-seeds/seeds.json >/dev/null
  private/spec2-tool/eerecomp "$ELF" --entries private/spec2-seeds/entry-seeds.txt --out private/spec2-gen --stats | tail -1
fi
# The race HUD for any screen ratio (scripts/spec2_ios_hud_patch.py): the same translation of the HUD-patched ELF.
if [ ! -f private/spec2-aspect-gen/table.cpp ]; then
  [ -f private/spec2-aspect-elf/SCUS_974.36 ] || "$PY" -E -s scripts/spec2_ios_hud_patch.py --elf "$ELF" \
      --output private/spec2-aspect-elf
  private/spec2-tool/eerecomp private/spec2-aspect-elf/SCUS_974.36 --entries private/spec2-seeds/entry-seeds.txt \
      --out private/spec2-aspect-gen --stats | tail -1
fi

# 3. Runtime pieces (checked against their pins by CMake): renderer port and shaders, runtime capsule, license guard,
#    VU tables.
[ -f private/macos-port/gpu.cpp ] || "$PY" -E -s scripts/prepare_external_vulkan.py private/macos-port --gs-stream-hooks
if [ ! -f private/macos-shaders/raster.spv ]; then
  build_wgsl_tool build/wgsl_spirv
  build/wgsl_spirv/release/gt4-wgsl-spirv private/references/ps2-web-recomp/runtime/src/gs/gpu/gs.wgsl private/macos-shaders
fi
[ -f private/spec2-runtime/runtime.json ] || "$PY" -E -s scripts/prepare_perf_runtime.py private/spec2-runtime \
    --assets-root . --mtvu --gs-stream --frame-cost --spec2-iop
[ -f private/spec2-license-guard/runtime.json ] || "$PY" -E -s scripts/prepare_license_guard.py \
    private/spec2-license-guard --assets-root . --display-aspect --frame-counters
[ -f private/spec2-vu/summary.json ] || "$PY" -E -s ports/macos/spec2_vu_generate.py "$ELF" private/spec2-vu

# 4. The app, signed for your team. The first time, open build/ios/GT4Recomp.xcodeproj in Xcode and Run the gt4
#    scheme once on your device: that creates the certificate and the profile with the entitlement.
cmake -S . -B build/ios -G Xcode -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=arm64 \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=17.4 -DGT4_IOS_BUNDLE_ID="$BUNDLE_ID" \
      -DCMAKE_XCODE_ATTRIBUTE_DEVELOPMENT_TEAM="$TEAM" -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_STYLE=Automatic >/dev/null
xcodebuild -project build/ios/GT4Recomp.xcodeproj -target gt4 -configuration Release -sdk iphoneos \
           -allowProvisioningUpdates -quiet
APP="build/ios/ports/ios/Release-iphoneos/gt4.app"
echo "built $APP"

# 5. The device.
if { [ "$INSTALL" = 1 ] || [ "$COPY_ISO" = 1 ] || [ -n "$CHECK" ]; } && [ -z "$DEVICE" ]; then
  DEVICE=$(xcrun devicectl list devices --hide-default-columns --columns Identifier --hide-headers \
           --filter "State CONTAINS 'available' OR State CONTAINS 'connected'" 2>/dev/null | head -1 | sed 's/(UDID)//' | tr -d ' ')
  [ -n "$DEVICE" ] || { echo "no device found (USB, unlocked, Developer Mode on; or pass --device ID)"; exit 1; }
fi
if [ "$INSTALL" = 1 ]; then
  xcrun devicectl device install app --device "$DEVICE" "$APP"
fi
if [ "$COPY_ISO" = 1 ]; then
  [ -n "$ISO" ] || { echo "--copy-iso needs --iso FILE"; exit 2; }
  xcrun devicectl device copy to --device "$DEVICE" --domain-type appDataContainer \
        --domain-identifier "$BUNDLE_ID" --source "$ISO" --destination "Documents/$(basename "$ISO")"
fi
if [ -n "$CHECK" ]; then
  xcrun devicectl device process launch --device "$DEVICE" --terminate-existing \
        --environment-variables "{\"GT4_IOS_CHECK_FRAMES\": \"$CHECK\"}" "$BUNDLE_ID"
  echo "waiting for $CHECK frames..."
  sleep $(( CHECK / 60 + 20 ))
  rm -rf private/ios-check && mkdir -p private/ios-check
  for item in gt4.log frames; do
    xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
          --domain-identifier "$BUNDLE_ID" --source "Documents/$item" --destination "private/ios-check/$item" || true
  done
  tail -5 private/ios-check/gt4.log || true
fi
