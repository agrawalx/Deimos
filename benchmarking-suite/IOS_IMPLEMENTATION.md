# iOS App Implementation Guide

Companion to [ARCHITECTURE.md](./ARCHITECTURE.md). Covers the iOS build path, why it diverges from Android, and the current (broken) state of the iOS toolchain.

---

## 1. Why iOS Is Different From Android

The Rust core (`moPro/mopro-example-app/src/lib.rs`) is the same for both platforms — same `#[uniffi::export]` functions, same `mopro_ffi::app!()` macro, same circuit registries. The divergence starts at the binding layer.

| Dimension | Android | iOS |
|---|---|---|
| **Native artifact** | One shared library `libmopro_example_app.so` per arch | One static library `libdeimos_<backend>.a` per backend, wrapped in an `xcframework` |
| **Linkage** | Dynamic — `System.loadLibrary(...)` via JNA at runtime | Static — `.a` linked into the app binary at build time |
| **Symbol scope** | JVM/JNA loads into per-library namespace; collisions are irrelevant | **Swift/ObjC have global symbol scope** — two libraries cannot both export `RustBuffer`, `ffi_..._rustbuffer_alloc`, etc. |
| **FFI plumbing** | JNA reads C function signatures from a Kotlin `Library` interface (reflection + `dlsym`) | Swift imports C headers via a `module.modulemap`; symbols are resolved at link time |
| **Bindings file** | One `mopro.kt` covers every backend | One `.swift` per backend, with type names hand-prefixed (`CircomRustBuffer`, `NoirRustBuffer`) |
| **Build output** | `uniffi-bindgen generate` → single Kotlin file | `uniffi-bindgen generate` → Swift file, **plus** a post-processing rename pass |
| **Asset access** | Assets live in APK; must be copied to app-private storage to get a filesystem path | Assets live in `.app` bundle with readable filesystem paths — no copy needed |
| **Threading** | Current Android plugin calls FFI on platform (UI) thread | Swift plugin dispatches FFI to `DispatchQueue.global(qos: .userInitiated)` and hops back to main for the result |
| **Build command** | `mopro build --platforms android` — one pass | `mopro build --platforms ios` — **two passes**, with file-swapping between them |

### The root cause of every iOS-specific hack: Swift's global symbol namespace

UniFFI generates a **fixed set of symbol names per crate** — `RustBuffer`, `ForeignBytes`, `RustCallStatus`, `ffi_<crate>_rustbuffer_alloc`, and so on. Each Rust crate you want to expose produces its own copy of those symbols. On Android, JNA loads each `.so` into its own handle and calls by name — no clash. On iOS, linking two static libraries that both export `RustBuffer` produces a duplicate-symbol error at link time.

So Deimos solves it by **compiling the Rust core twice**, once per backend, producing two independent static libraries with renamed symbols.

---

## 2. The Two-Pass iOS Build

Driven by `moPro/mopro-example-app/generate_ios_bindings.sh`.

### Pass 1 — Groth16

```sh
cp src/configs/lib_groth16.rs  src/lib.rs
cp src/configs/Cargo_groth16.toml Cargo.toml      # ← expected but missing (see §4)
cp src/configs/build_groth16.rs   build.rs
mopro build --platforms ios
```

Outputs:
- `MoproiOSBindings/mopro.swift` → copied to `flutter/mopro_flutter_plugin/ios/Classes/MoproGroth16.swift`
- `MoproiOSBindings/MoproBindings.xcframework` → copied to `flutter/mopro_flutter_plugin/ios/Frameworks/MoproGroth16Bindings.xcframework`

Then `sed` rewrites symbol names inside the deployed headers and Swift file:
```
RustBuffer      → Groth16RustBuffer
ForeignBytes    → Groth16ForeignBytes
RustCallStatus  → Groth16RustCallStatus
MoproError      → Groth16MoproError
ProofLib        → Groth16ProofLib
```
`G1`, `G2`, `Groth16Proof`, `Groth16ProofResult` keep their names — only the UniFFI infrastructure and the per-pass `MoproError` / `ProofLib` need prefixing to avoid collisions with the Barretenberg pass. `risc0_prove`, `cairo_prove`, `provekit_prove` all have unique names and need no rename.

### Pass 2 — Barretenberg

Same pattern, with `lib_barretenberg.rs` → `mopro.swift` → `MoproBarretenberg.swift`, framework → `MoproBarretenbergBindings.xcframework`, and a rename pass that prefixes the infrastructure types with `Barretenberg*`.

### Why the passes can't be merged

If you compiled both backends into one crate, `uniffi-bindgen` would emit one Swift file and one header with one `RustBuffer` type — no collision to resolve. The problem is that the two backends have **conflicting type names in user space** (both define their own `MoproError`, and earlier iterations had conflicting `ProofLib` enums). Splitting into two crates was the cleanest way to keep the Rust code mono-repo while producing two fully-separated Swift APIs.

The trade-off: **linker output is doubled** (libdeimos_groth16.a + libdeimos_barretenberg.a, each contains its own copy of `noir_rs`, `circom-prover`, etc. that it needs). Android avoids this — everything lives in the single `libmopro_example_app.so`.

---

## 3. Runtime Call Path on iOS

Reference: `flutter/mopro_flutter_plugin/ios/Classes/MoproFlutterPlugin.swift`.

```
Dart                  invokeMethod('generateGroth16Proof', {...})
  │
  ▼
MoproFlutterPlugin.handle  (platform/UI thread)
  ├── Resolve Flutter asset key to iOS bundle path
  │     FlutterDartProject.lookupKey(forAsset:) → Bundle.main.path(forResource:)
  │     (no file copy needed — iOS bundle is filesystem-addressable)
  ├── DispatchQueue.global(qos: .userInitiated).async
  │     └── generateGroth16Proof(...)          [from MoproGroth16.swift]
  │           FfiConverter<String>.lower(zkeyPath) → Groth16RustBuffer
  │           rustCall { ffi_deimos_groth16_fn_func_generate_groth16_proof(...) }
  │             │
  │             ▼   static link — Swift calls C via extern "C" declared in header
  │           libdeimos_groth16.a
  │             ├── UniFFI C ABI wrapper
  │             └── generate_groth16_proof (Rust)
  │                   circom-prover → Arkworks/Rapidsnark
  │                   libwitnesses.a (native C++ witness calculator)
  │           → Groth16ProofResult
  └── DispatchQueue.main.async { result(resultMap) }
```

Two important differences from the Android path:

1. **No JNA / no reflection.** The Swift compiler sees C function declarations in `deimos_groth16FFI.h` and generates direct calls. Resolution is at link time, not runtime.
2. **Background dispatch is mandatory.** Proof generation is CPU-bound and seconds long; blocking the main thread on iOS freezes the UI. The Android plugin currently doesn't do this (and should).

---

## 4. Current iOS Status — Source Fully Aligned, Awaiting Mac Build

> **Bottom line: every source-level fix is committed. The remaining step is to run `generate_ios_bindings.sh` on a Mac to populate the static libraries.**

For a step-by-step runbook, see [IOS_BUILD_GUIDE.md](./IOS_BUILD_GUIDE.md).

### 4.1 What's now aligned

All source-level drift between "circom/noir" (old) and "groth16/barretenberg" (current backend names) has been resolved on this branch:

| Location | State |
|---|---|
| `src/configs/Cargo_groth16.toml`, `Cargo_barretenberg.toml` | Created — define `deimos-groth16` and `deimos-barretenberg` crate names so the `.a` and header filenames match the xcframework naming |
| `src/configs/build_groth16.rs`, `build_barretenberg.rs` | Created — Groth16 pass does witness-C++ compilation + RISC0 methods; Barretenberg pass has no witness step |
| `src/configs/lib_groth16.rs` | Rewritten — matches the circuit list in canonical `src/lib.rs`, includes `#[uniffi::export]` for RISC0 / Cairo-M / ProveKit so all four backends land in Pass 1 |
| `src/configs/lib_barretenberg.rs` | Rewritten — minimal crate root with only the barretenberg module |
| `generate_ios_bindings.sh` | Rewritten — swaps in the new config filenames, outputs `MoproGroth16Bindings.xcframework` + `MoproGroth16.swift` (and Barretenberg equivalents), applies `Groth16*` / `Barretenberg*` symbol prefixes via `sed` on both the headers and the generated Swift |
| `update_mopro_groth16.sh`, `update_mopro_barretenberg.sh` | Replace the old `update_mopro_circom.sh` / `update_mopro_noir.sh`; apply prefixes that match the header rename |
| `flutter/mopro_flutter_plugin/ios/mopro_flutter.podspec` | `vendored_frameworks`, `HEADER_SEARCH_PATHS`, and `OTHER_SWIFT_FLAGS` all use the `MoproGroth16Bindings` / `MoproBarretenbergBindings` names |
| `flutter/mopro_flutter_plugin/ios/Classes/MoproFlutterPlugin.swift` | Rewritten — `CircomProof` / `CircomProofLib` replaced with `Groth16Proof` / `Groth16ProofLib`; added `generateRisc0Proof` / `verifyRisc0Proof` / `generateCairoProof` / `verifyCairoProof` handlers; Barretenberg now dispatches off the main thread |
| `Config.toml` | `target_platforms = ["android", "ios"]` with `ios = ["aarch64-apple-ios", "aarch64-apple-ios-sim"]` |
| `Mopro{Groth16,Barretenberg}Bindings.xcframework/Info.plist` + `module.modulemap` | Updated to reference `libdeimos_groth16.a` / `libdeimos_barretenberg.a` and the matching module names (the Mac build will regenerate these; this keeps the checked-in state consistent in the meantime) |

### 4.2 What still requires macOS

The xcframeworks are still **empty of `.a` files**. `mopro build --platforms ios` needs Xcode, `lipo`, and the iOS SDK — none of which exist on Linux. On a Mac:

```sh
cd benchmarking-suite/moPro/mopro-example-app
./generate_ios_bindings.sh
```

This runs both passes, drops the static libraries into their xcframeworks, applies the sed renames, and restores the Android-canonical `src/lib.rs` / `Cargo.toml` / `build.rs` via the `trap cleanup EXIT` handler. See [IOS_BUILD_GUIDE.md](./IOS_BUILD_GUIDE.md) for prerequisites, expected timing, and troubleshooting.

### 4.3 Design decision — 2 passes, not 4

RISC0, Cairo-M, and ProveKit could each have been split into their own iOS pass (one xcframework per backend). Instead, the Groth16 pass is the "everything except Barretenberg" pass, because:

1. `noir_rs` is the largest dependency tree in the project and needs isolation regardless — keeping it in its own pass is mandatory.
2. The other backends (Groth16, RISC0, Cairo-M, ProveKit) have unique function names (`risc0_prove`, `cairo_prove`, etc.), so the only Swift-level collision with Barretenberg is the shared UniFFI scaffolding (`RustBuffer`, `ForeignBytes`, `RustCallStatus`) plus the per-pass `MoproError` enum — all of which the sed rename handles.
3. Two passes keep the build simple enough to debug. Adding a 3rd or 4th pass per minor backend would triple build time and require maintaining three more config triplets for minimal isolation gain.

If `noir_rs` ever gets small enough to live alongside the other backends without symbol noise, the passes could collapse to one. Track [mozilla/uniffi-rs#2257](https://github.com/mozilla/uniffi-rs/issues/2257) for proper upstream namespacing that would eliminate the need for sed altogether.

---

## 5. Remaining Post-Build Follow-ups

After the first successful Mac build, consider:

1. **Simulator support.** `Config.toml` now declares `aarch64-apple-ios-sim`, but the `find ... -name "*.h"` loops in `generate_ios_bindings.sh` only patch the `ios-arm64` slice. Add an `ios-arm64_x86_64-simulator` block once simulator support is actually needed.
2. **Binary artefact hygiene.** `libdeimos_groth16.a` + `libdeimos_barretenberg.a` together are ~200–400 MB. Keeping them in git works for a small team but should move to a CI artifact or Git LFS before the repo grows.
3. **Bring Android's threading hygiene up to iOS's.** `MoproFlutterPlugin.kt` currently calls Rust synchronously on the platform/UI thread — long proofs block the UI. Wrap every `generate*` case in a coroutine / thread. See ARCHITECTURE.md §3.6.
4. **Upstream UniFFI namespacing.** Track [mozilla/uniffi-rs#2257](https://github.com/mozilla/uniffi-rs/issues/2257); when generated symbols get proper per-crate prefixes, the sed passes go away and the two iOS passes can potentially collapse into one.

---

## 6. Key File Index (iOS Only)

| File | Role |
|---|---|
| `moPro/mopro-example-app/generate_ios_bindings.sh` | Orchestrates the two-pass build; applies the `sed` rename to headers and Swift |
| `moPro/mopro-example-app/update_mopro_groth16.sh` | Post-build sed pass applied to `MoproGroth16.swift` |
| `moPro/mopro-example-app/update_mopro_barretenberg.sh` | Post-build sed pass applied to `MoproBarretenberg.swift` |
| `moPro/mopro-example-app/src/configs/lib_groth16.rs` | Crate root swapped in for Pass 1 (Groth16 + RISC0 + Cairo-M + ProveKit) |
| `moPro/mopro-example-app/src/configs/lib_barretenberg.rs` | Crate root swapped in for Pass 2 (Barretenberg only) |
| `moPro/mopro-example-app/src/configs/Cargo_groth16.toml` | Package name `deimos-groth16` → drives `.a` filename and UniFFI module name |
| `moPro/mopro-example-app/src/configs/Cargo_barretenberg.toml` | Package name `deimos-barretenberg` |
| `moPro/mopro-example-app/src/configs/build_groth16.rs` | WASM → C++ transpile + `cc` compile of witness calculators |
| `moPro/mopro-example-app/src/configs/build_barretenberg.rs` | Empty — barretenberg has no witness compilation step |
| `flutter/mopro_flutter_plugin/ios/Classes/MoproGroth16.swift` | Generated UniFFI Swift bindings, Groth16 pass (regenerated by Mac build) |
| `flutter/mopro_flutter_plugin/ios/Classes/MoproBarretenberg.swift` | Generated UniFFI Swift bindings, Barretenberg pass (regenerated by Mac build) |
| `flutter/mopro_flutter_plugin/ios/Classes/MoproFlutterPlugin.swift` | Hand-written Flutter dispatcher; one `case` per method-channel call, each dispatched onto `DispatchQueue.global(qos: .userInitiated)` |
| `flutter/mopro_flutter_plugin/ios/Frameworks/MoproGroth16Bindings.xcframework/` | Static `.a` + C headers for Pass 1 (populated by Mac build) |
| `flutter/mopro_flutter_plugin/ios/Frameworks/MoproBarretenbergBindings.xcframework/` | Static `.a` + C headers for Pass 2 |
| `flutter/mopro_flutter_plugin/ios/mopro_flutter.podspec` | CocoaPods manifest — vendors both xcframeworks, wires module-map search paths |
| `flutter/ios/Podfile` | Standard Flutter iOS Podfile — no manual edits required |
| `flutter/ios/Runner/AppDelegate.swift`, `GeneratedPluginRegistrant.m` | Flutter-Xcode glue; auto-generated |
| `IOS_BUILD_GUIDE.md` | Mac-side runbook for building and shipping |
