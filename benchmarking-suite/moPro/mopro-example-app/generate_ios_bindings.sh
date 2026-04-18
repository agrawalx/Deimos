#!/bin/bash
# Build iOS bindings for the Deimos benchmarking suite.
#
# Runs `mopro build --platforms ios` twice — once for the Groth16-family pass
# (groth16 + risc0 + cairo_m + provekit) and once for the Barretenberg pass.
# Each pass swaps in a different `src/lib.rs`, `Cargo.toml`, `build.rs`, which is
# why we back up the originals and always restore them on exit.
#
# Requirements (must run on macOS):
#   - Xcode with command-line tools
#   - `cargo install mopro-cli`
#   - Rust iOS targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim`
#
# This script uses BSD sed (`sed -i ''`). Do not run it on Linux.

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

# Fix for w2c2 / rust-witness header compatibility.
export CFLAGS="-DW2C2_LOOP_START="

echo "[+] Cleaning previous artifacts..."
rm -rf test-vectors/circom/witnesscalc
cargo clean

mopro build --platforms ios

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
    find "$GROTH16_HEADERS_DIR" -name "*.h" -exec sed -i '' 's/RustBuffer/Groth16RustBuffer/g' {} +
    find "$GROTH16_HEADERS_DIR" -name "*.h" -exec sed -i '' 's/ForeignBytes/Groth16ForeignBytes/g' {} +
    find "$GROTH16_HEADERS_DIR" -name "*.h" -exec sed -i '' 's/RustCallStatus/Groth16RustCallStatus/g' {} +
    find "$GROTH16_HEADERS_DIR" -name "*.h" -exec sed -i '' 's/UNIFFI_SHARED_H/UNIFFI_SHARED_H_GROTH16/g' {} +
    find "$GROTH16_HEADERS_DIR" -name "*.h" -exec sed -i '' 's/UNIFFI_SHARED_HEADER_V4/UNIFFI_SHARED_HEADER_V4_GROTH16/g' {} +
else
    echo "WARNING: Groth16 headers not found at $GROTH16_HEADERS_DIR"
fi

./update_mopro_groth16.sh

# ==============================================================================
# PASS 2 — Barretenberg
# ==============================================================================
echo ""
echo ">>> Building Barretenberg pass..."
cp "$CONFIG_DIR/lib_barretenberg.rs"     src/lib.rs
cp "$CONFIG_DIR/Cargo_barretenberg.toml" Cargo.toml
cp "$CONFIG_DIR/build_barretenberg.rs"   build.rs

# Barretenberg pass does not need the witness-header flag.
unset CFLAGS
cargo clean

mopro build --platforms ios

echo "[+] Deploying MoproBarretenberg.swift..."
cp "$IOS_BINDINGS_DIR/mopro.swift" "$FLUTTER_IOS_PLUGIN_DIR/MoproBarretenberg.swift"

echo "[+] Deploying MoproBarretenbergBindings.xcframework..."
rm -rf "$FRAMEWORKS_DIR/MoproBarretenbergBindings.xcframework"
cp -R "$IOS_BINDINGS_DIR/MoproBindings.xcframework" "$FRAMEWORKS_DIR/MoproBarretenbergBindings.xcframework"

BARRETENBERG_HEADERS_DIR="$FRAMEWORKS_DIR/MoproBarretenbergBindings.xcframework/ios-arm64/Headers/deimos_barretenberg"
if [ -d "$BARRETENBERG_HEADERS_DIR" ]; then
    echo "[+] Renaming shared types in Barretenberg headers..."
    find "$BARRETENBERG_HEADERS_DIR" -name "*.h" -exec sed -i '' 's/RustBuffer/BarretenbergRustBuffer/g' {} +
    find "$BARRETENBERG_HEADERS_DIR" -name "*.h" -exec sed -i '' 's/ForeignBytes/BarretenbergForeignBytes/g' {} +
    find "$BARRETENBERG_HEADERS_DIR" -name "*.h" -exec sed -i '' 's/RustCallStatus/BarretenbergRustCallStatus/g' {} +
    find "$BARRETENBERG_HEADERS_DIR" -name "*.h" -exec sed -i '' 's/UNIFFI_SHARED_H/UNIFFI_SHARED_H_BARRETENBERG/g' {} +
    find "$BARRETENBERG_HEADERS_DIR" -name "*.h" -exec sed -i '' 's/UNIFFI_SHARED_HEADER_V4/UNIFFI_SHARED_HEADER_V4_BARRETENBERG/g' {} +
else
    echo "WARNING: Barretenberg headers not found at $BARRETENBERG_HEADERS_DIR"
fi

./update_mopro_barretenberg.sh

echo ""
echo ">>> SUCCESS: Both passes built and bindings deployed."
