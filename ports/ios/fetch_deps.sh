#!/bin/bash
# MoltenVK for iOS (Khronos' release: static xcframework and the Vulkan headers) into ports/ios/deps, checked against
# its sha256 in ports/ios/pins.sh. The other libraries are built from pinned sources by ports/ios/build_gs_deps.sh.
set -euo pipefail
cd "$(dirname "$0")"
GT4_ROOT="$(cd ../.. && pwd)"
source ./pins.sh
if [ -f deps/MoltenVK/MoltenVK/static/MoltenVK.xcframework/ios-arm64/libMoltenVK.a ]; then
  echo "MoltenVK already in ports/ios/deps"; exit 0
fi
fetch_moltenvk deps
echo "MoltenVK v1.4.2 in ports/ios/deps/MoltenVK"
