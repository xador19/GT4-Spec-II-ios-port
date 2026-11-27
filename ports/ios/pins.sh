# Everything the iOS build needs from elsewhere, each locked to an exact version and checked with sha256 before
# anything in it is built or run. Sourced by make_ipa.sh, ports/ios/build.sh, ports/ios/fetch_deps.sh,
# ports/ios/build_gs_deps.sh and ports/ios/make_deps_bundle.sh; set GT4_ROOT to the repository root first.
#
# Two ways in, the same checks either way:
# - the sources bundle (DEPS_BUNDLE, made by ports/ios/make_deps_bundle.sh and attached to this repository's
#   releases): when it is there, nothing is downloaded;
# - otherwise the official sources: the git repositories and release downloads below.
#
# Source folders are checked by tree: scripts/tree_sha256.py hashes every file of the folder (sha256), and the result
# must equal the pin. A fresh git checkout and the same files from the bundle hash the same. To move a pin, change the
# commit or version, fetch it, print the new hash (python3 -I scripts/tree_sha256.py <folder>) and update it here.

# ps2-web-recomp (MIT): the translator and PS2 runtime this port builds on. Checked out with CRLF line endings, as the
# runtime pins in docs/inputs were made on Windows.
DONOR_REPO=https://github.com/snuri00/ps2-web-recomp.git
DONOR_COMMIT=1b4808793a12c45125262fd2d5f50a9ec9f7c020
DONOR_TREE_SHA256=5d1242b5603f62023f1c1df52fb9be04adaba9a38e3509f0dcf534aa38bb5bec

# gt4recomp-gs (GPL-3.0): PCSX2 v2.8.2's GS as vgs499p's macOS fork has it (the upstream, not a copy of ours);
# ports/ios/patches adds the iOS changes.
GS_REPO=https://github.com/vgs499p/gt4recomp-gs.git
GS_COMMIT=ec8eb8b1694cc02bd914629d18baae55e96397df
GS_TREE_SHA256=9289a35f951ad41e41dd579bc72dd8a630168e135cc77878ff4c6c146db48eb7

# MoltenVK v1.4.2 (Apache-2.0): Khronos' iOS release (static xcframework and Vulkan headers).
MOLTENVK_URL=https://github.com/KhronosGroup/MoltenVK/releases/download/v1.4.2/MoltenVK-ios.tar
MOLTENVK_SHA256=b5d947b1660e6e9fed40b9cd2387e160aaab9e80b775c0cef7e14059405178c1

# Python packages: exact versions with their sha256 (ports/ios/requirements-build.txt), wheels only.
PYTHON_REQUIREMENTS=ports/ios/requirements-build.txt
PYTHON_VERSIONS="3.10 3.11 3.12 3.13 3.14"   # the Pillow wheels the bundle carries (macOS arm64)

# The Rust crates of tools/wgsl_spirv: online, cargo checks each against the sha256 in its Cargo.lock; in the bundle
# they are the folder cargo vendor makes from that Cargo.lock, checked by tree.
CRATES_TREE_SHA256=e00df103fb1422002491b46f1fda04f5293ba5e6677e1dace419888002e589eb

# The sources bundle: one tar of everything above plus the C libraries of ports/ios/build_gs_deps.sh. Its members are
# checked one by one against these pins, so the bundle itself needs no pin. make_ipa.sh --deps FILE picks another file.
DEPS_BUNDLE_NAME=gt4spec2-ios-deps-1.tar
DEPS_BUNDLE="${DEPS_BUNDLE:-$GT4_ROOT/deps/$DEPS_BUNDLE_NAME}"

# git without the user's or the system's settings, so line-ending, hook or URL-rewrite settings cannot change a checkout
pinned_git() { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git "$@"; }
pinned_curl() { curl --proto '=https' --tlsv1.2 -fsSL "$@"; }

# --- the bundle ------------------------------------------------------------------------------------------------------
use_bundle() { [ -f "$DEPS_BUNDLE" ]; }
_bundle_listing=""
# bundle_has <member>
bundle_has() {
  use_bundle || return 1
  [ -n "$_bundle_listing" ] || _bundle_listing=$(tar -tf "$DEPS_BUNDLE")
  grep -qxF "$1" <<< "$_bundle_listing"
}
# bundle_extract <member> <folder>: copies one member out of the bundle (tar refuses absolute and ../ paths)
bundle_extract() {
  bundle_has "$1" || { echo "the sources bundle has no $1 ($DEPS_BUNDLE)" >&2; return 1; }
  mkdir -p "$2"
  tar -xf "$DEPS_BUNDLE" -C "$2" "$1"
}

# check_tree <folder> <tree sha256> <name>: deletes the folder and fails when it does not match
check_tree() {
  local got
  got=$(python3 -I "$GT4_ROOT/scripts/tree_sha256.py" "$1")
  if [ "$got" != "$2" ]; then
    rm -rf "$1"
    echo "$3 does not match its pin (tree sha256 $got, expected $2)" >&2
    return 1
  fi
  echo "$3: tree sha256 matches"
}

# check_file <file> <sha256>: deletes the file and fails when it does not match
check_file() {
  if ! echo "$2  $1" | shasum -a 256 --check --status; then
    rm -f "$1"
    echo "$(basename "$1") does not match its sha256 ($2)" >&2
    return 1
  fi
}

# --- the git sources -------------------------------------------------------------------------------------------------
# fetch_source <bundle name> <repo> <commit> <tree sha256> <folder> <autocrlf true|false> [extra clone options]
fetch_source() {
  local name="$1" repo="$2" commit="$3" want="$4" folder="$5" crlf="$6" staging
  shift 6
  rm -rf "$folder"
  if use_bundle; then
    staging="$folder.bundle"
    rm -rf "$staging"
    bundle_extract "sources/$name.tar.xz" "$staging"
    mkdir -p "$folder"
    tar -xJf "$staging/sources/$name.tar.xz" -C "$folder"
    rm -rf "$staging"
    check_tree "$folder" "$want" "$name $commit (sources bundle)"
    # its own empty repository, so git apply and version lookups work on it and never reach an enclosing checkout
    pinned_git -C "$folder" init -q
  else
    pinned_git clone -q -c core.autocrlf="$crlf" --no-checkout "$@" "$repo" "$folder"
    pinned_git -C "$folder" checkout -q --detach "$commit"
    check_tree "$folder" "$want" "$repo $commit"
  fi
}
fetch_donor() { fetch_source ps2-web-recomp "$DONOR_REPO" "$DONOR_COMMIT" "$DONOR_TREE_SHA256" "$1" true; }
fetch_gs() { fetch_source gt4recomp-gs "$GS_REPO" "$GS_COMMIT" "$GS_TREE_SHA256" "$1" false --filter=blob:none; }

# --- MoltenVK --------------------------------------------------------------------------------------------------------
# fetch_moltenvk <deps folder>: puts MoltenVK into <deps folder>/MoltenVK
fetch_moltenvk() {
  local deps="$1" archive="$1/MoltenVK-ios.tar"
  mkdir -p "$deps"
  if use_bundle; then
    bundle_extract moltenvk/MoltenVK-ios.tar "$deps"
    mv "$deps/moltenvk/MoltenVK-ios.tar" "$archive"
    rmdir "$deps/moltenvk"
  else
    pinned_curl -o "$archive" "$MOLTENVK_URL"
  fi
  check_file "$archive" "$MOLTENVK_SHA256"
  tar -xf "$archive" -C "$deps"
  rm "$archive"
}

# --- the C libraries (ports/ios/build_gs_deps.sh) -------------------------------------------------------------------
# fetch_library <url> <file>: into the current folder; build_gs_deps.sh checks every file with its SHASUMS afterwards
fetch_library() {
  [ ! -f "$2" ] || return 0
  if use_bundle; then
    bundle_extract "libs/$2" .
    mv "libs/$2" "$2"
    rmdir libs
  else
    pinned_curl -o "$2" "$1"
  fi
}

# --- Python ----------------------------------------------------------------------------------------------------------
# make_tooling_venv <folder>: a Python environment with exactly the pinned packages, nothing else
make_tooling_venv() {
  local wheels="$1.wheels"
  python3 -I -m venv "$1"
  if use_bundle; then
    rm -rf "$wheels"
    mkdir -p "$wheels"
    tar -xf "$DEPS_BUNDLE" -C "$wheels" --include 'python/*.whl'
    PIP_DISABLE_PIP_VERSION_CHECK=1 "$1/bin/python" -I -m pip install -q --no-index --find-links "$wheels/python" \
      --require-hashes --only-binary=:all: --no-deps -r "$GT4_ROOT/$PYTHON_REQUIREMENTS"
    rm -rf "$wheels"
  else
    PIP_DISABLE_PIP_VERSION_CHECK=1 "$1/bin/python" -I -m pip install -q --require-hashes --only-binary=:all: \
      --no-deps -r "$GT4_ROOT/$PYTHON_REQUIREMENTS"
  fi
}

# --- Rust ------------------------------------------------------------------------------------------------------------
# build_wgsl_tool <target folder>: builds tools/wgsl_spirv (cargo --locked; from the bundle's crates with no network)
build_wgsl_tool() {
  local manifest="$GT4_ROOT/tools/wgsl_spirv/Cargo.toml" vendor="$GT4_ROOT/private/wgsl-crates"
  if use_bundle; then
    rm -rf "$vendor" "$vendor.bundle"
    bundle_extract crates.tar.xz "$vendor.bundle"
    mkdir -p "$vendor"
    tar -xJf "$vendor.bundle/crates.tar.xz" -C "$vendor" --strip-components 1
    rm -rf "$vendor.bundle"
    check_tree "$vendor" "$CRATES_TREE_SHA256" "Rust crates (sources bundle)"
    cargo build --release --locked --offline --manifest-path "$manifest" --target-dir "$1" \
      --config "source.crates-io.replace-with=\"bundle\"" --config "source.bundle.directory=\"$vendor\""
  else
    cargo build --release --locked --manifest-path "$manifest" --target-dir "$1"
  fi
}
