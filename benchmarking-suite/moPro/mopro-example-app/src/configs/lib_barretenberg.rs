//! iOS Pass 2 — Barretenberg only.
//!
//! Swapped into `src/lib.rs` by `generate_ios_bindings.sh` for the second of
//! two iOS build passes. `noir_rs` is a heavy dependency tree and isolating
//! it in its own crate keeps link times for the other backends reasonable.

mopro_ffi::app!();

/// Barretenberg-pass `MoproError`.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum MoproError {
    #[error("BarretenbergError: {0}")]
    BarretenbergError(String),
}

#[uniffi::export]
fn mopro_uniffi_hello_world() -> String {
    "Hello, World!".to_string()
}

#[macro_use]
mod stubs;

mod barretenberg;

#[cfg(test)]
mod uniffi_tests {
    #[test]
    fn test_mopro_uniffi_hello_world() {
        assert_eq!(super::mopro_uniffi_hello_world(), "Hello, World!");
    }
}
