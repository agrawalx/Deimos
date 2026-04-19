#!/bin/bash
# Post-build rename pass on the deployed MoproBarretenberg.swift.
#
# Symmetric to update_mopro_groth16.sh. Renames must match the header-level
# sed renames inside generate_ios_bindings.sh.
#
# All sed expressions use BSD's `[[:<:]]` / `[[:>:]]` word boundaries so the
# renames are idempotent on re-runs.
#
# BSD sed only — run on macOS.

set -e
FILE="flutter/mopro_flutter_plugin/ios/Classes/MoproBarretenberg.swift"

echo "Updating MoproBarretenberg.swift..."

# Common UniFFI C types
sed -i '' -E 's/[[:<:]]RustBuffer[[:>:]]/BarretenbergRustBuffer/g' "$FILE"
sed -i '' -E 's/[[:<:]]ForeignBytes[[:>:]]/BarretenbergForeignBytes/g' "$FILE"
sed -i '' -E 's/[[:<:]]RustCallStatus[[:>:]]/BarretenbergRustCallStatus/g' "$FILE"

# Barretenberg-owned user types
sed -i '' -E 's/[[:<:]]MoproError[[:>:]]/BarretenbergMoproError/g' "$FILE"

# Top-level helpers that would collide between the two passes
sed -i '' -E 's/[[:<:]]moproUniffiHelloWorld[[:>:]]/barretenbergMoproUniffiHelloWorld/g' "$FILE"

# Initialization helper
sed -i '' 's/uniffiEnsureDeimosBarretenbergInitialized/uniffiEnsureBarretenbergInitialized/g' "$FILE"

echo "Done."
