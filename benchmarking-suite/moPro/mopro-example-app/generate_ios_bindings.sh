#!/bin/bash
# Build iOS bindings for the Deimos benchmarking suite.
#
# Runs `mopro build --platforms ios` twice — once for the Groth16-family pass
# (groth16 + risc0 + cairo_m + provekit) and once for the Barretenberg pass.
# Each pass swaps in a different `src/lib.rs`, `Cargo.toml`, `build.rs`, which is
# why we back up the originals and always restore them on exit.
#
# Requirements (must run on macOS):
#   - Xcode 26+ with command-line tools
#   - `xcodebuild -downloadComponent MetalToolchain` (one-time, for risc0 GPU kernels)
#   - `cargo install mopro-cli`
#   - Rust iOS targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim`
#   - `rzup install rust && rzup install cargo-risczero` (for risc0 guest toolchain)
#   - Homebrew: `brew install cmake pkg-config git-lfs` and `git lfs install` once
#
# Apple Silicon Mac quirks handled inline:
#   - rust-witness 0.1.6 cross-compiles w2c2 for the iOS target rather than the
#     host (because target arch == host arch on M-series). We detect the bad
#     iOS w2c2 binary and rebuild it for macOS so transpile_wasm() can run.
#   - Xcode 26's clang 21 promoted -Wimplicit-function-declaration to an error.
#     We export CFLAGS to demote it for cc-rs deps.
#   - iOS 26.4 SDK dropped <sys/random.h>; the getentropy() symbol is still in
#     libSystem but the public header is gone. We inject a tiny shim into the
#     vendored wasi.c so it compiles.
#   - Release-with-debuginfo .a files exceed 2GB and break CocoaPods'
#     ruby-macho parser. We `xcrun strip -S` post-build to drop debug sections.
#
# This script uses BSD sed (`sed -i ''`) and macOS-only tools. Do not run on Linux.

set -e

# ------------------------------------------------------------------------------
# Paths
# ------------------------------------------------------------------------------
CONFIG_DIR="src/configs"
BACKUP_DIR="src/backup_tmp"
FLUTTER_IOS_PLUGIN_DIR="flutter/mopro_flutter_plugin/ios/Classes"
FRAMEWORKS_DIR="flutter/mopro_flutter_plugin/ios/Frameworks"
IOS_BINDINGS_DIR="MoproiOSBindings"

echo "=========================================================="
echo "   Generating iOS Bindings — Groth16 + Barretenberg"
echo "=========================================================="

# ------------------------------------------------------------------------------
# Compiler flags applied to every cc-rs invocation in the dep graph
# ------------------------------------------------------------------------------
# -DW2C2_LOOP_START=  : silences a w2c2 macro warning treated as error
# -Wno-error=implicit-function-declaration : Xcode 26 clang 21 promoted this
#   to a hard error; many vendored C deps still call functions without including
#   their header. Demoting it back to a warning lets the link succeed (the
#   symbols exist in libSystem at link time even when no header is included).
COMMON_CFLAGS="-DW2C2_LOOP_START= -Wno-error=implicit-function-declaration"
export CFLAGS="$COMMON_CFLAGS"
export CXXFLAGS="-Wno-error=implicit-function-declaration"
export CFLAGS_aarch64_apple_ios="$COMMON_CFLAGS"
export CFLAGS_aarch64_apple_ios_sim="$COMMON_CFLAGS"
export CMAKE_C_FLAGS="$COMMON_CFLAGS"
export TARGET_CFLAGS="$COMMON_CFLAGS"

# ------------------------------------------------------------------------------
# Apple Silicon w2c2 fix
# ------------------------------------------------------------------------------
# rust-witness 0.1.6's cmake invocation cross-compiles w2c2 for the cargo
# target. On Apple Silicon Macs targeting aarch64-apple-ios, that produces an
# iOS binary that macOS refuses to execute, and rust-witness's `.expect()`
# only catches IO errors, not exec failures — so the build script panics
# later at `fs::read_to_string` of the .c file w2c2 was supposed to produce.
#
# We work around it by rebuilding w2c2 with the host toolchain in the same
# directory rust-witness uses, then re-running mopro build.
fix_w2c2_for_apple_silicon() {
    local w2c2_dir
    w2c2_dir=$(find build -type d -name 'w2c2' -path '*/out/w2c2' 2>/dev/null | head -1)

    if [ -z "$w2c2_dir" ]; then
        echo "[i] No w2c2 source dir found yet — rust-witness hasn't cloned. Skipping w2c2 fix."
        return 0
    fi

    local wasi_c="$w2c2_dir/wasi/wasi.c"
    if [ -f "$wasi_c" ] && ! grep -q 'arc4random_buf(buffer, length)' "$wasi_c"; then
        echo "[+] Injecting getentropy() shim into vendored wasi.c"
        local tmp
        tmp=$(mktemp)
        cat > "$tmp" <<'SHIM_EOF'
#include <stdlib.h>
#include <stddef.h>
static inline int getentropy(void *buffer, size_t length) {
    arc4random_buf(buffer, length);
    return 0;
}
SHIM_EOF
        cat "$wasi_c" >> "$tmp"
        mv "$tmp" "$wasi_c"
    fi

    local w2c2_bin="$w2c2_dir/build/w2c2/w2c2"
    # If a w2c2 binary already exists and is executable on this host, keep it.
    if [ -x "$w2c2_bin" ] && "$w2c2_bin" -h >/dev/null 2>&1; then
        echo "[i] Existing w2c2 binary is host-executable — reusing."
        return 0
    fi

    echo "[+] Rebuilding w2c2 for macOS host (iOS-built binary won't run here)..."
    rm -rf "$w2c2_dir/build"
    mkdir -p "$w2c2_dir/build"
    (
        cd "$w2c2_dir/build"
        # Strip every cross-compile env var so cmake picks up the macOS toolchain.
        env -u CFLAGS -u CXXFLAGS \
            -u CFLAGS_aarch64_apple_ios -u CFLAGS_aarch64_apple_ios_sim \
            -u CMAKE_C_FLAGS -u TARGET_CFLAGS -u SDKROOT \
            cmake .. -DCMAKE_BUILD_TYPE=Release
        make w2c2 -j"$(sysctl -n hw.ncpu)"
    )
}

# Run mopro build, and if it fails on the rust-witness w2c2 issue, apply the
# Apple Silicon fix and retry exactly once.
mopro_build_with_recovery() {
    if mopro build --platforms ios; then
        return 0
    fi

    echo ""
    echo "[!] First mopro build failed. Attempting Apple Silicon w2c2 recovery..."
    fix_w2c2_for_apple_silicon

    echo "[+] Retrying mopro build..."
    mopro build --platforms ios
}

# ------------------------------------------------------------------------------
# Backup the canonical Android-friendly sources so the build restores them on exit
# ------------------------------------------------------------------------------
echo "[+] Backing up current configuration..."
mkdir -p "$BACKUP_DIR"
cp src/lib.rs "$BACKUP_DIR/"
cp Cargo.toml "$BACKUP_DIR/"
cp build.rs "$BACKUP_DIR/"

cleanup() {
    echo "[+] Restoring original Android configuration..."
    cp "$BACKUP_DIR/lib.rs" src/lib.rs
    cp "$BACKUP_DIR/Cargo.toml" Cargo.toml
    cp "$BACKUP_DIR/build.rs" build.rs
    rm -rf "$BACKUP_DIR"
    echo "[+] Done."
}
trap cleanup EXIT

# ==============================================================================
# PASS 1 — Groth16 (+ RISC0, Cairo-M, ProveKit)
# ==============================================================================
echo ""
echo ">>> Building Groth16 pass..."
cp "$CONFIG_DIR/lib_groth16.rs"      src/lib.rs
cp "$CONFIG_DIR/Cargo_groth16.toml"  Cargo.toml
cp "$CONFIG_DIR/build_groth16.rs"    build.rs

echo "[+] Cleaning previous artifacts..."
rm -rf test-vectors/circom/witnesscalc
cargo clean

mopro_build_with_recovery

echo "[+] Deploying MoproGroth16.swift..."
cp "$IOS_BINDINGS_DIR/mopro.swift" "$FLUTTER_IOS_PLUGIN_DIR/MoproGroth16.swift"

echo "[+] Deploying MoproGroth16Bindings.xcframework..."
rm -rf "$FRAMEWORKS_DIR/MoproGroth16Bindings.xcframework"
cp -R "$IOS_BINDINGS_DIR/MoproBindings.xcframework" "$FRAMEWORKS_DIR/MoproGroth16Bindings.xcframework"

# --- Patch header files: rename shared UniFFI infrastructure types so they
# --- don't collide with the Barretenberg pass at Swift link time.
GROTH16_HEADERS_DIR="$FRAMEWORKS_DIR/MoproGroth16Bindings.xcframework/ios-arm64/Headers/deimos_groth16"
if [ -d "$GROTH16_HEADERS_DIR" ]; then
    echo "[+] Renaming shared types in Groth16 headers..."
    find "$GROTH16_HEADERS_DIR" -name "*.h" -exec sed -i '' -E 's/[[:<:]]RustBuffer[[:>:]]/Groth16RustBuffer/g' {} +
    find "$GROTH16_HEADERS_DIR" -name "*.h" -exec sed -i '' -E 's/[[:<:]]ForeignBytes[[:>:]]/Groth16ForeignBytes/g' {} +
    find "$GROTH16_HEADERS_DIR" -name "*.h" -exec sed -i '' -E 's/[[:<:]]RustCallStatus[[:>:]]/Groth16RustCallStatus/g' {} +
    find "$GROTH16_HEADERS_DIR" -name "*.h" -exec sed -i '' 's/UNIFFI_SHARED_H/UNIFFI_SHARED_H_GROTH16/g' {} +
    find "$GROTH16_HEADERS_DIR" -name "*.h" -exec sed -i '' 's/UNIFFI_SHARED_HEADER_V4/UNIFFI_SHARED_HEADER_V4_GROTH16/g' {} +
else
    echo "WARNING: Groth16 headers not found at $GROTH16_HEADERS_DIR"
fi

./update_mopro_groth16.sh

# Strip debug info — keeps file under CocoaPods' ruby-macho 2GB read limit.
GROTH16_STATIC_LIB="$FRAMEWORKS_DIR/MoproGroth16Bindings.xcframework/ios-arm64/libdeimos_groth16.a"
if [ -f "$GROTH16_STATIC_LIB" ]; then
    echo "[+] Stripping debug info from libdeimos_groth16.a (this can take 2-5 min)..."
    xcrun strip -S "$GROTH16_STATIC_LIB"
fi

# ==============================================================================
# PASS 2 — Barretenberg
# ==============================================================================
echo ""
echo ">>> Building Barretenberg pass..."
cp "$CONFIG_DIR/lib_barretenberg.rs"     src/lib.rs
cp "$CONFIG_DIR/Cargo_barretenberg.toml" Cargo.toml
cp "$CONFIG_DIR/build_barretenberg.rs"   build.rs

cargo clean

# Barretenberg has no rust-witness dep, so no w2c2 recovery needed.
mopro build --platforms ios

echo "[+] Deploying MoproBarretenberg.swift..."
cp "$IOS_BINDINGS_DIR/mopro.swift" "$FLUTTER_IOS_PLUGIN_DIR/MoproBarretenberg.swift"

echo "[+] Deploying MoproBarretenbergBindings.xcframework..."
rm -rf "$FRAMEWORKS_DIR/MoproBarretenbergBindings.xcframework"
cp -R "$IOS_BINDINGS_DIR/MoproBindings.xcframework" "$FRAMEWORKS_DIR/MoproBarretenbergBindings.xcframework"

BARRETENBERG_HEADERS_DIR="$FRAMEWORKS_DIR/MoproBarretenbergBindings.xcframework/ios-arm64/Headers/deimos_barretenberg"
if [ -d "$BARRETENBERG_HEADERS_DIR" ]; then
    echo "[+] Renaming shared types in Barretenberg headers..."
    find "$BARRETENBERG_HEADERS_DIR" -name "*.h" -exec sed -i '' -E 's/[[:<:]]RustBuffer[[:>:]]/BarretenbergRustBuffer/g' {} +
    find "$BARRETENBERG_HEADERS_DIR" -name "*.h" -exec sed -i '' -E 's/[[:<:]]ForeignBytes[[:>:]]/BarretenbergForeignBytes/g' {} +
    find "$BARRETENBERG_HEADERS_DIR" -name "*.h" -exec sed -i '' -E 's/[[:<:]]RustCallStatus[[:>:]]/BarretenbergRustCallStatus/g' {} +
    find "$BARRETENBERG_HEADERS_DIR" -name "*.h" -exec sed -i '' 's/UNIFFI_SHARED_H/UNIFFI_SHARED_H_BARRETENBERG/g' {} +
    find "$BARRETENBERG_HEADERS_DIR" -name "*.h" -exec sed -i '' 's/UNIFFI_SHARED_HEADER_V4/UNIFFI_SHARED_HEADER_V4_BARRETENBERG/g' {} +
else
    echo "WARNING: Barretenberg headers not found at $BARRETENBERG_HEADERS_DIR"
fi

./update_mopro_barretenberg.sh

BARRETENBERG_STATIC_LIB="$FRAMEWORKS_DIR/MoproBarretenbergBindings.xcframework/ios-arm64/libdeimos_barretenberg.a"
if [ -f "$BARRETENBERG_STATIC_LIB" ]; then
    echo "[+] Stripping debug info from libdeimos_barretenberg.a..."
    xcrun strip -S "$BARRETENBERG_STATIC_LIB"
fi

echo ""
echo ">>> SUCCESS: Both passes built and bindings deployed."
