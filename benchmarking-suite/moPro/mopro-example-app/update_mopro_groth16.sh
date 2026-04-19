#!/bin/bash
# Post-build rename pass on the deployed MoproGroth16.swift.
#
# Rewrites shared UniFFI symbol names (RustBuffer, ForeignBytes, RustCallStatus)
# and the Groth16-owned user types (MoproError, ProofLib) to carry a Groth16
# prefix. This must match the header-file renames in generate_ios_bindings.sh —
# if the two drift, the Swift file won't compile against the C headers it imports.
#
# All sed expressions use BSD's `[[:<:]]` / `[[:>:]]` word boundaries so the
# renames are idempotent — `Groth16MoproError` will not be re-renamed to
# `Groth16Groth16MoproError` on a second run, because the `M` is no longer at
# the start of a word.
#
# BSD sed only — run on macOS.

set -e
FILE="flutter/mopro_flutter_plugin/ios/Classes/MoproGroth16.swift"

echo "Updating MoproGroth16.swift..."

# Common UniFFI C types (must match the prefix applied to the headers)
sed -i '' -E 's/[[:<:]]RustBuffer[[:>:]]/Groth16RustBuffer/g' "$FILE"
sed -i '' -E 's/[[:<:]]ForeignBytes[[:>:]]/Groth16ForeignBytes/g' "$FILE"
sed -i '' -E 's/[[:<:]]RustCallStatus[[:>:]]/Groth16RustCallStatus/g' "$FILE"

# Groth16-owned user types (defined in lib_groth16.rs / src/groth16.rs).
# `MoproError` rename also catches `FfiConverterTypeMoproError` ->
# `FfiConverterTypeGroth16MoproError` because the [[:<:]] boundary matches
# after the `e` in `Type` (alphanumeric->capital is not a word boundary in
# BSD's POSIX class, but the leading `T` is end-of-word for Type, then the
# `M` is start-of-word for MoproError).
sed -i '' -E 's/[[:<:]]MoproError[[:>:]]/Groth16MoproError/g' "$FILE"
sed -i '' -E 's/[[:<:]]ProofLib[[:>:]]/Groth16ProofLib/g' "$FILE"

# Top-level helpers that would collide between the two passes
sed -i '' -E 's/[[:<:]]moproUniffiHelloWorld[[:>:]]/groth16MoproUniffiHelloWorld/g' "$FILE"

# Initialization helper (namespaced by crate name)
sed -i '' 's/uniffiEnsureDeimosGroth16Initialized/uniffiEnsureGroth16Initialized/g' "$FILE"

echo "Done."
