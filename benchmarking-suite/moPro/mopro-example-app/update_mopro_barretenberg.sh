#!/bin/bash
# Post-build rename pass on the deployed MoproBarretenberg.swift.
#
# Symmetric to update_mopro_groth16.sh. Renames must match the header-level
# sed renames inside generate_ios_bindings.sh.
#
# BSD sed only — run on macOS.

set -e
FILE="flutter/mopro_flutter_plugin/ios/Classes/MoproBarretenberg.swift"

echo "Updating MoproBarretenberg.swift..."

# Common UniFFI C types
sed -i '' 's/RustBuffer/BarretenbergRustBuffer/g' "$FILE"
sed -i '' 's/ForeignBytes/BarretenbergForeignBytes/g' "$FILE"
sed -i '' 's/RustCallStatus/BarretenbergRustCallStatus/g' "$FILE"

# Barretenberg-owned user types
sed -i '' 's/\bMoproError\b/BarretenbergMoproError/g' "$FILE"

# Initialization helper
sed -i '' 's/uniffiEnsureDeimosBarretenbergInitialized/uniffiEnsureBarretenbergInitialized/g' "$FILE"

echo "Done."
