#!/bin/bash
# Post-build rename pass on the deployed MoproGroth16.swift.
#
# Rewrites shared UniFFI symbol names (RustBuffer, ForeignBytes, RustCallStatus)
# and the Groth16-owned user types (MoproError, ProofLib) to carry a Groth16 prefix.
# This must match the header-file renames in generate_ios_bindings.sh — if the two
# drift, the Swift file won't compile against the C headers it imports.
#
# BSD sed only — run on macOS.

set -e
FILE="flutter/mopro_flutter_plugin/ios/Classes/MoproGroth16.swift"

echo "Updating MoproGroth16.swift..."

# Common UniFFI C types (must match the prefix applied to the headers)
sed -i '' 's/RustBuffer/Groth16RustBuffer/g' "$FILE"
sed -i '' 's/ForeignBytes/Groth16ForeignBytes/g' "$FILE"
sed -i '' 's/RustCallStatus/Groth16RustCallStatus/g' "$FILE"

# Groth16-owned user types (defined in lib_groth16.rs / src/groth16.rs)
sed -i '' 's/\bMoproError\b/Groth16MoproError/g' "$FILE"
sed -i '' 's/\bProofLib\b/Groth16ProofLib/g' "$FILE"

# Initialization helper (namespaced by crate name)
sed -i '' 's/uniffiEnsureDeimosGroth16Initialized/uniffiEnsureGroth16Initialized/g' "$FILE"

echo "Done."
