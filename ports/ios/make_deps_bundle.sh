#!/bin/bash
# Makes the sources bundle: one file with every source the iOS build would otherwise download, so make_ipa.sh can
# build without any network (and without depending on other people's servers staying up).
#
#   ports/ios/make_deps_bundle.sh            -> dist/gt4spec2-ios-deps-1.tar
#
# Everything is fetched from its official source and checked against the pins in ports/ios/pins.sh and
# ports/ios/build_gs_deps.sh first; nothing is built or run. The bundle holds no game files. Attach it to a release of
# this repository; players put it in deps/ (or pass make_ipa.sh --deps FILE).
#
# Layout (an uncompressed tar; each member is checked again when it is used):
#   sources/ps2-web-recomp.tar.xz  sources/gt4recomp-gs.tar.xz   the two git checkouts, without .git
#   moltenvk/MoltenVK-ios.tar                                     Khronos' release file, as downloaded
#   libs/*                                                        the C library archives, as downloaded
#   python/*.whl                                                  pycdlib and Pillow (macOS arm64, Python 3.10-3.14)
#   crates.tar.xz                                                 cargo vendor of tools/wgsl_spirv/Cargo.lock
#   LICENSES.txt                                                  what each piece is and its licence
set -euo pipefail
GT4_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$GT4_ROOT"
export DEPS_BUNDLE=/nonexistent  # always fetch from the official sources here
source ports/ios/pins.sh

STAGE="$GT4_ROOT/build/deps-bundle"
rm -rf "$STAGE"
mkdir -p "$STAGE"/{sources,moltenvk,libs,python} dist

echo "== git sources"
for name in ps2-web-recomp gt4recomp-gs; do
  case "$name" in
    ps2-web-recomp) fetch_donor "$STAGE/checkout-$name" ;;
    gt4recomp-gs) fetch_gs "$STAGE/checkout-$name" ;;
  esac
  rm -rf "$STAGE/checkout-$name/.git"
  # the same files, no .git; sorted, with fixed owner and times so the archive does not carry this Mac's details
  (cd "$STAGE/checkout-$name" && find . -mindepth 1 | LC_ALL=C sort > "$STAGE/files.txt" && \
    COPYFILE_DISABLE=1 tar --uid 0 --gid 0 --uname "" --gname "" --no-recursion -cf - -T "$STAGE/files.txt") \
    | xz -T0 -6 > "$STAGE/sources/$name.tar.xz"
  rm -rf "$STAGE/checkout-$name" "$STAGE/files.txt"
done

echo "== MoltenVK"
pinned_curl -o "$STAGE/moltenvk/MoltenVK-ios.tar" "$MOLTENVK_URL"
check_file "$STAGE/moltenvk/MoltenVK-ios.tar" "$MOLTENVK_SHA256"

echo "== C libraries"
# The list and the hashes are build_gs_deps.sh's own: it runs with GT4_DEPS_FETCH_ONLY and stops after its check.
GT4_DEPS_FETCH_ONLY="$STAGE/libs" ports/ios/build_gs_deps.sh
rm -f "$STAGE/libs/SHASUMS"

echo "== Python wheels"
for version in $PYTHON_VERSIONS; do
  python3 -I -m pip download -q --disable-pip-version-check --require-hashes --only-binary=:all: --no-deps \
    --platform macosx_11_0_arm64 --implementation cp --python-version "$version" --abi "cp${version/./}" \
    -d "$STAGE/python" -r "$PYTHON_REQUIREMENTS"
done

echo "== Rust crates"
cargo vendor -q --locked --manifest-path tools/wgsl_spirv/Cargo.toml "$STAGE/crates" > /dev/null
check_tree "$STAGE/crates" "$CRATES_TREE_SHA256" "Rust crates"
(cd "$STAGE" && COPYFILE_DISABLE=1 tar --uid 0 --gid 0 --uname "" --gname "" -cf - crates) | xz -T0 -6 > "$STAGE/crates.tar.xz"
rm -rf "$STAGE/crates"

cat > "$STAGE/LICENSES.txt" <<'EOF'
Sources bundle for GT4 Spec II for iPhone (make_ipa.sh). No game files. Each piece keeps its own licence files:
  sources/ps2-web-recomp   MIT (LICENSE inside)
  sources/gt4recomp-gs     GPL-3.0 (COPYING.GPLv3 inside), PCSX2 and its third-party libraries (3rdparty/*)
  moltenvk                 Apache-2.0 (LICENSE inside)
  libs                     SDL3 zlib, freetype FTL/GPL-2.0, zstd BSD/GPL-2.0, lz4 BSD-2, libpng libpng licence,
                           libjpeg-turbo IJG/BSD-3, libwebp BSD-3, plutovg MIT, plutosvg MIT, rapidyaml MIT
  python                   pycdlib LGPL-2.1, Pillow MIT-CMU
  crates                   each crate's own licence (MIT and/or Apache-2.0)
EOF

echo "== packing"
out="dist/$DEPS_BUNDLE_NAME"
(cd "$STAGE" && find sources moltenvk libs python -type f | LC_ALL=C sort > members.txt && \
  printf '%s\n' crates.tar.xz LICENSES.txt >> members.txt && \
  COPYFILE_DISABLE=1 tar --uid 0 --gid 0 --uname "" --gname "" -cf "$GT4_ROOT/$out" -T members.txt)
rm -rf "$STAGE"
echo "Done: $out ($(du -h "$out" | cut -f1)), sha256 $(shasum -a 256 "$out" | cut -d' ' -f1)"
