# Building the iOS Bindings on macOS

This is the step-by-step runbook for taking the repo from its current state to a
working iOS build. You must run these commands on a Mac with Xcode — the
underlying `mopro build --platforms ios` step invokes `lipo`, `libtool`, the
iOS SDK linker, and BSD `sed -i ''`, none of which are available on Linux.

> Paired with [`IOS_IMPLEMENTATION.md`](./IOS_IMPLEMENTATION.md). That document
> explains the *why*; this one explains the *how*.

---

## 1. Prerequisites

```bash
# Xcode and command-line tools
xcode-select --install
# (open Xcode once, accept the licence, let it install iOS SDKs)

# Rust + iOS targets
rustup target add aarch64-apple-ios aarch64-apple-ios-sim

# Mopro CLI
cargo install mopro-cli

# CocoaPods + Flutter (if not already installed)
sudo gem install cocoapods
# https://docs.flutter.dev/get-started/install/macos
```

Sanity check:
```bash
xcodebuild -version
cargo --version
mopro --version
pod --version
flutter doctor
```

---

## 2. What already changed in this branch

All Linux-side changes are committed. When you `git pull` onto the Mac, you'll
already have:

| File | Change |
|---|---|
| `moPro/mopro-example-app/src/configs/Cargo_groth16.toml` | **new** — package name `deimos-groth16`, feature set for Pass 1 |
| `moPro/mopro-example-app/src/configs/Cargo_barretenberg.toml` | **new** — package name `deimos-barretenberg`, Pass 2 |
| `moPro/mopro-example-app/src/configs/build_groth16.rs` | **new** — witness compilation + RISC0 methods |
| `moPro/mopro-example-app/src/configs/build_barretenberg.rs` | **new** — empty build.rs |
| `moPro/mopro-example-app/src/configs/lib_groth16.rs` | rewritten — current circuit list + RISC0/Cairo-M/ProveKit exports |
| `moPro/mopro-example-app/src/configs/lib_barretenberg.rs` | rewritten — barretenberg-only crate root |
| `moPro/mopro-example-app/generate_ios_bindings.sh` | rewritten — uses `lib_groth16.rs` / `lib_barretenberg.rs`, renames outputs to `MoproGroth16Bindings.xcframework` / `MoproBarretenbergBindings.xcframework`, prefixes symbols with `Groth16` / `Barretenberg` |
| `moPro/mopro-example-app/update_mopro_groth16.sh` | **new** — replaces `update_mopro_circom.sh` |
| `moPro/mopro-example-app/update_mopro_barretenberg.sh` | **new** — replaces `update_mopro_noir.sh` |
| `moPro/mopro-example-app/Config.toml` | `target_platforms = ["android", "ios"]` |
| `flutter/mopro_flutter_plugin/ios/Classes/MoproFlutterPlugin.swift` | rewritten — `Groth16ProofLib` / `Groth16Proof` (was `CircomProofLib` / `CircomProof`), RISC0 + Cairo-M handlers added, Barretenberg dispatched off main thread |
| `flutter/mopro_flutter_plugin/ios/mopro_flutter.podspec` | framework names + header paths updated |
| `flutter/mopro_flutter_plugin/ios/Frameworks/Mopro{Groth16,Barretenberg}Bindings.xcframework/Info.plist` | points at new `.a` filenames |
| `flutter/mopro_flutter_plugin/ios/Frameworks/.../module.modulemap` | module names updated |

The xcframeworks themselves are still empty shells (no `.a` files) — Step 3
populates them.

---

## 3. Generate the bindings

From the repo root on the Mac:

```bash
cd benchmarking-suite/moPro/mopro-example-app
./generate_ios_bindings.sh
```

The script does two full `cargo clean` + `mopro build --platforms ios` passes.
On an M-series Mac expect **~8–15 min for Pass 1** (Groth16 + RISC0 + Cairo-M +
ProveKit — the witness C++ compile dominates) and **~15–25 min for Pass 2**
(Barretenberg — `noir_rs` is heavy). First run can be slower because cargo is
downloading its full dep graph twice.

On completion, the script restores `src/lib.rs`, `Cargo.toml`, `build.rs` to
their Android-canonical forms via the `trap cleanup EXIT` handler. If you
interrupt the script, the same cleanup runs. If the Mac crashes mid-build, the
backup lives at `moPro/mopro-example-app/src/backup_tmp/` — restore manually:

```bash
cp src/backup_tmp/lib.rs     src/lib.rs
cp src/backup_tmp/Cargo.toml Cargo.toml
cp src/backup_tmp/build.rs   build.rs
rm -rf src/backup_tmp
```

What you should see on disk after success:

```
flutter/mopro_flutter_plugin/ios/
├── Classes/
│   ├── MoproFlutterPlugin.swift           (hand-written, unchanged by the script)
│   ├── MoproGroth16.swift                 ← regenerated + renamed
│   └── MoproBarretenberg.swift            ← regenerated + renamed
└── Frameworks/
    ├── MoproGroth16Bindings.xcframework/
    │   └── ios-arm64/
    │       ├── libdeimos_groth16.a        ← NEW — previously absent
    │       └── Headers/deimos_groth16/
    │           ├── deimos_groth16FFI.h    ← renamed: Groth16RustBuffer, etc.
    │           └── module.modulemap
    └── MoproBarretenbergBindings.xcframework/
        └── ios-arm64/
            ├── libdeimos_barretenberg.a   ← NEW
            └── Headers/deimos_barretenberg/
                ├── deimos_barretenbergFFI.h
                └── module.modulemap
```

---

## 4. Verify the symbol rename actually worked

Before bringing Xcode into the picture, sanity-check the sed pass landed:

```bash
cd benchmarking-suite/moPro/mopro-example-app

# Should print matches for the renamed symbols, not the originals
grep -l 'Groth16RustBuffer'     flutter/mopro_flutter_plugin/ios/Classes/MoproGroth16.swift
grep -l 'BarretenbergRustBuffer' flutter/mopro_flutter_plugin/ios/Classes/MoproBarretenberg.swift

# Headers must match
grep -c 'Groth16RustBuffer' flutter/mopro_flutter_plugin/ios/Frameworks/MoproGroth16Bindings.xcframework/ios-arm64/Headers/deimos_groth16/*.h

# Should print nothing — if you still see 'RustBuffer' alone, the sed didn't run on that file
grep -w 'RustBuffer' flutter/mopro_flutter_plugin/ios/Classes/MoproGroth16.swift      || true
grep -w 'RustBuffer' flutter/mopro_flutter_plugin/ios/Classes/MoproBarretenberg.swift || true
```

If the last two `grep`s find unrenamed `RustBuffer` symbols, the post-build sed
pass missed something — check that the shell session was bash (macOS default
login shell is zsh; scripts still start `#!/bin/bash`, so that's fine).

---

## 5. Build the Flutter iOS app

```bash
cd benchmarking-suite/moPro/mopro-example-app/flutter
flutter clean
flutter pub get

cd ios
pod deintegrate           # clear any stale Pods/Podfile.lock entries from old framework names
pod install --repo-update
cd ..

flutter build ios --no-codesign    # quick compile-only check
# or, to run on a device:
flutter run -d <your-ios-device-id>
```

### Expected Xcode build behaviour

Two things will fail loudly if something drifted:

- **Linker error "duplicate symbol _uniffi_..."** → the symbol rename didn't
  apply to one of the two passes. Re-run `./generate_ios_bindings.sh`. If it
  still fails, check that `update_mopro_groth16.sh` and
  `update_mopro_barretenberg.sh` are executable (`chmod +x`).
- **"No such module 'deimos_groth16FFI'"** → the podspec `OTHER_SWIFT_FLAGS`
  module-map flag isn't reaching Swift. Re-run `pod install --repo-update`.

---

## 6. Smoke-test each backend

Ship a throwaway build to a device and exercise each method channel:

| Dart call | What to expect |
|---|---|
| `generateGroth16Proof(zkeyPath: 'sha256_16.zkey', inputs: '{"in":[...]}', proofLib: 0)` | Returns a map with `proof.a / b / c` + `inputs` |
| `generateBarretenbergProof(circuitPath: 'noir_multiplier2.json', ...)` | Returns `Uint8List` proof bytes |
| `generateRisc0Proof(input: 42)` | Returns `{ 'receipt': Uint8List }` (~100KB+) |
| `generateCairoProof(programJson: '...', inputsJson: '...', entrypoint: 'sha256_hash')` | Returns `{ 'proof': Uint8List }` |
| `generateProveKitProof(proverPath: '...pkp', inputToml: '...')` | Returns `{ 'proof': Uint8List }` |
| `getIOSMemoryUsage` | Returns `{ 'used': Int, 'total': Int }` — handy for the benchmark UI |

All five proving channels should never block the main thread — each one
dispatches to `DispatchQueue.global(qos: .userInitiated)` and hops back on
completion. If the iOS UI visibly stalls during a proof, that's a bug.

---

## 7. Commit the built artifacts

After the Mac build succeeds, commit the populated xcframeworks and regenerated
Swift files. These are binary / large-text artefacts that the Linux dev host
cannot produce, so the branch needs them committed for CI and for other devs:

```bash
git add flutter/mopro_flutter_plugin/ios/Frameworks/MoproGroth16Bindings.xcframework
git add flutter/mopro_flutter_plugin/ios/Frameworks/MoproBarretenbergBindings.xcframework
git add flutter/mopro_flutter_plugin/ios/Classes/MoproGroth16.swift
git add flutter/mopro_flutter_plugin/ios/Classes/MoproBarretenberg.swift
git commit -m "Rebuild iOS bindings (Groth16 + Barretenberg passes)"
```

The `.a` files are ~50–200 MB each. If repo size becomes a problem, consider
Git LFS for `*.xcframework/**/*.a`. That's a later cleanup — not urgent for
the first working build.

---

## 8. Troubleshooting cheatsheet

| Symptom | Cause | Fix |
|---|---|---|
| `cp: src/configs/Cargo_groth16.toml: No such file or directory` | Stale branch | `git pull`; files were added in this PR |
| `mopro: command not found` | Mopro CLI not installed | `cargo install mopro-cli` |
| `error: linking with cc failed` during Pass 1 | `rust-witness` header drift | `rm -rf test-vectors/circom/witnesscalc && cargo clean && retry` (the script does this, but a mid-run interrupt can leave partial state) |
| Link error `duplicate symbol _uniffi_...` in Xcode | sed rename incomplete | Re-run `generate_ios_bindings.sh` end-to-end; don't re-run a single pass |
| `undefined symbols for architecture arm64: _risc0_prove` | RISC0 methods crate not in scope | Check `../risc0-circuit/methods` exists and `Cargo_groth16.toml` has the `methods = { path = ... }` line |
| Xcode: "Sandbox not in sync" | `.xcframework` modified mid-build | Quit Xcode, re-run `pod install`, reopen |

---

## 9. Follow-up work (post-first-working-build)

- Simulator support (`aarch64-apple-ios-sim` is already in `Config.toml`, but the current `generate_ios_bindings.sh` only handles `ios-arm64` in the header-patch step). Add a second `find "$FRAMEWORKS_DIR/.../ios-arm64_x86_64-simulator" ...` block.
- Prebuilt CI artifact: move the xcframeworks out of git and into a build artifact that CI fetches. 200MB+ per framework × two frameworks is a lot to keep in git.
- Collapse the two-pass build: upstream work in uniffi-bindgen to namespace generated symbols per crate would remove the need for sed renames entirely. Track [mozilla/uniffi-rs#2257](https://github.com/mozilla/uniffi-rs/issues/2257).
