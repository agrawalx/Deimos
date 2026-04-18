//! iOS Pass 1 — Groth16 + RISC0 + Cairo-M + ProveKit.
//!
//! This is the crate root swapped into `src/lib.rs` by `generate_ios_bindings.sh`
//! for the first of two iOS build passes. It links everything *except* Barretenberg.
//! The Barretenberg pass uses `lib_barretenberg.rs`.
//!
//! The Android build uses the main `src/lib.rs` (which includes every backend in
//! one shared library) and does not touch these config files.

use methods::{RISC0_CIRCUIT_ELF, RISC0_CIRCUIT_ID};
#[cfg(feature = "cairo_m")]
use cairo_m_prover::{prove, verify};
use risc0_zkvm::{default_prover, ExecutorEnv, Receipt};

mopro_ffi::app!();

/// Groth16-pass `MoproError`. Only the Groth16 variant is needed in this pass —
/// Barretenberg lives in the other pass with its own `MoproError`.
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum MoproError {
    #[error("Groth16Error: {0}")]
    Groth16Error(String),
}

#[uniffi::export]
fn mopro_uniffi_hello_world() -> String {
    "Hello, World!".to_string()
}

#[macro_use]
mod stubs;

// ==============================================================================
// GROTH16 (CIRCOM)
// ==============================================================================

#[macro_use]
mod groth16;

mod rapidsnark;

// Bytes circuits
rust_witness::witness!(blake2s25616);
rust_witness::witness!(blake2s25632);
rust_witness::witness!(blake2s25664);
rust_witness::witness!(blake2s256128);

rust_witness::witness!(blake316);
rust_witness::witness!(blake332);
rust_witness::witness!(blake364);
rust_witness::witness!(blake3128);

rust_witness::witness!(keccak25616);
rust_witness::witness!(keccak25632);
rust_witness::witness!(keccak25664);
rust_witness::witness!(keccak256128);

rust_witness::witness!(sha25616);
rust_witness::witness!(sha25632);
rust_witness::witness!(sha25664);
rust_witness::witness!(sha256128);

rust_witness::witness!(pedersen16);
rust_witness::witness!(pedersen32);
rust_witness::witness!(pedersen64);
rust_witness::witness!(pedersen128);

// Field-element circuits — mimc256
rust_witness::witness!(mimc2561f);
rust_witness::witness!(mimc2562f);
rust_witness::witness!(mimc2563f);
rust_witness::witness!(mimc2565f);
rust_witness::witness!(mimc2569f);
rust_witness::witness!(mimc25617f);
rust_witness::witness!(mimc25634f);

// Field-element circuits — poseidon
rust_witness::witness!(poseidon1f);
rust_witness::witness!(poseidon2f);
rust_witness::witness!(poseidon3f);
rust_witness::witness!(poseidon5f);
rust_witness::witness!(poseidon9f);
rust_witness::witness!(poseidon17f);
rust_witness::witness!(poseidon34f);

// Field-element circuits — poseidon2
rust_witness::witness!(poseidon21f);
rust_witness::witness!(poseidon22f);
rust_witness::witness!(poseidon23f);
rust_witness::witness!(poseidon25f);
rust_witness::witness!(poseidon29f);
rust_witness::witness!(poseidon217f);
rust_witness::witness!(poseidon234f);

// Field-element circuits — rescue-prime
rust_witness::witness!(rescueprime1f);
rust_witness::witness!(rescueprime2f);
rust_witness::witness!(rescueprime3f);
rust_witness::witness!(rescueprime5f);
rust_witness::witness!(rescueprime9f);
rust_witness::witness!(rescueprime17f);
rust_witness::witness!(rescueprime34f);

set_groth16_circuits! {
    ("blake2s256_16.zkey", circom_prover::witness::WitnessFn::RustWitness(blake2s25616_witness)),
    ("blake2s256_32.zkey", circom_prover::witness::WitnessFn::RustWitness(blake2s25632_witness)),
    ("blake2s256_64.zkey", circom_prover::witness::WitnessFn::RustWitness(blake2s25664_witness)),
    ("blake2s256_128.zkey", circom_prover::witness::WitnessFn::RustWitness(blake2s256128_witness)),

    ("blake3_16.zkey", circom_prover::witness::WitnessFn::RustWitness(blake316_witness)),
    ("blake3_32.zkey", circom_prover::witness::WitnessFn::RustWitness(blake332_witness)),
    ("blake3_64.zkey", circom_prover::witness::WitnessFn::RustWitness(blake364_witness)),
    ("blake3_128.zkey", circom_prover::witness::WitnessFn::RustWitness(blake3128_witness)),

    ("keccak256_16.zkey", circom_prover::witness::WitnessFn::RustWitness(keccak25616_witness)),
    ("keccak256_32.zkey", circom_prover::witness::WitnessFn::RustWitness(keccak25632_witness)),
    ("keccak256_64.zkey", circom_prover::witness::WitnessFn::RustWitness(keccak25664_witness)),
    ("keccak256_128.zkey", circom_prover::witness::WitnessFn::RustWitness(keccak256128_witness)),

    ("sha256_16.zkey", circom_prover::witness::WitnessFn::RustWitness(sha25616_witness)),
    ("sha256_32.zkey", circom_prover::witness::WitnessFn::RustWitness(sha25632_witness)),
    ("sha256_64.zkey", circom_prover::witness::WitnessFn::RustWitness(sha25664_witness)),
    ("sha256_128.zkey", circom_prover::witness::WitnessFn::RustWitness(sha256128_witness)),

    ("pedersen_16.zkey", circom_prover::witness::WitnessFn::RustWitness(pedersen16_witness)),
    ("pedersen_32.zkey", circom_prover::witness::WitnessFn::RustWitness(pedersen32_witness)),
    ("pedersen_64.zkey", circom_prover::witness::WitnessFn::RustWitness(pedersen64_witness)),
    ("pedersen_128.zkey", circom_prover::witness::WitnessFn::RustWitness(pedersen128_witness)),

    ("mimc256_1f.zkey", circom_prover::witness::WitnessFn::RustWitness(mimc2561f_witness)),
    ("mimc256_2f.zkey", circom_prover::witness::WitnessFn::RustWitness(mimc2562f_witness)),
    ("mimc256_3f.zkey", circom_prover::witness::WitnessFn::RustWitness(mimc2563f_witness)),
    ("mimc256_5f.zkey", circom_prover::witness::WitnessFn::RustWitness(mimc2565f_witness)),
    ("mimc256_9f.zkey", circom_prover::witness::WitnessFn::RustWitness(mimc2569f_witness)),
    ("mimc256_17f.zkey", circom_prover::witness::WitnessFn::RustWitness(mimc25617f_witness)),
    ("mimc256_34f.zkey", circom_prover::witness::WitnessFn::RustWitness(mimc25634f_witness)),

    ("poseidon_1f.zkey", circom_prover::witness::WitnessFn::RustWitness(poseidon1f_witness)),
    ("poseidon_2f.zkey", circom_prover::witness::WitnessFn::RustWitness(poseidon2f_witness)),
    ("poseidon_3f.zkey", circom_prover::witness::WitnessFn::RustWitness(poseidon3f_witness)),
    ("poseidon_5f.zkey", circom_prover::witness::WitnessFn::RustWitness(poseidon5f_witness)),
    ("poseidon_9f.zkey", circom_prover::witness::WitnessFn::RustWitness(poseidon9f_witness)),
    ("poseidon_17f.zkey", circom_prover::witness::WitnessFn::RustWitness(poseidon17f_witness)),
    ("poseidon_34f.zkey", circom_prover::witness::WitnessFn::RustWitness(poseidon34f_witness)),

    ("poseidon2_1f.zkey", circom_prover::witness::WitnessFn::RustWitness(poseidon21f_witness)),
    ("poseidon2_2f.zkey", circom_prover::witness::WitnessFn::RustWitness(poseidon22f_witness)),
    ("poseidon2_3f.zkey", circom_prover::witness::WitnessFn::RustWitness(poseidon23f_witness)),
    ("poseidon2_5f.zkey", circom_prover::witness::WitnessFn::RustWitness(poseidon25f_witness)),
    ("poseidon2_9f.zkey", circom_prover::witness::WitnessFn::RustWitness(poseidon29f_witness)),
    ("poseidon2_17f.zkey", circom_prover::witness::WitnessFn::RustWitness(poseidon217f_witness)),
    ("poseidon2_34f.zkey", circom_prover::witness::WitnessFn::RustWitness(poseidon234f_witness)),

    ("rescue-prime_1f.zkey", circom_prover::witness::WitnessFn::RustWitness(rescueprime1f_witness)),
    ("rescue-prime_2f.zkey", circom_prover::witness::WitnessFn::RustWitness(rescueprime2f_witness)),
    ("rescue-prime_3f.zkey", circom_prover::witness::WitnessFn::RustWitness(rescueprime3f_witness)),
    ("rescue-prime_5f.zkey", circom_prover::witness::WitnessFn::RustWitness(rescueprime5f_witness)),
    ("rescue-prime_9f.zkey", circom_prover::witness::WitnessFn::RustWitness(rescueprime9f_witness)),
    ("rescue-prime_17f.zkey", circom_prover::witness::WitnessFn::RustWitness(rescueprime17f_witness)),
    ("rescue-prime_34f.zkey", circom_prover::witness::WitnessFn::RustWitness(rescueprime34f_witness)),
}

// ==============================================================================
// RISC0
// ==============================================================================

#[derive(uniffi::Error, thiserror::Error, Debug)]
pub enum Risc0Error {
    #[error("Failed to prove: {0}")]
    ProveError(String),
    #[error("Failed to serialize receipt: {0}")]
    SerializeError(String),
    #[error("Failed to verify: {0}")]
    VerifyError(String),
    #[error("Failed to decode journal: {0}")]
    DecodeError(String),
}

#[derive(uniffi::Record, Clone)]
pub struct Risc0ProofOutput {
    pub receipt: Vec<u8>,
}

#[derive(uniffi::Record, Clone)]
pub struct Risc0VerifyOutput {
    pub is_valid: bool,
    pub output_value: u32,
}

#[uniffi::export]
pub fn risc0_prove(input: u32) -> Result<Risc0ProofOutput, Risc0Error> {
    let env = ExecutorEnv::builder()
        .write(&input)
        .map_err(|e| Risc0Error::ProveError(format!("Failed to write input: {}", e)))?
        .build()
        .map_err(|e| Risc0Error::ProveError(format!("Failed to build executor environment: {}", e)))?;

    let prover = default_prover();
    let prove_info = prover
        .prove(env, RISC0_CIRCUIT_ELF)
        .map_err(|e| Risc0Error::ProveError(format!("Failed to generate proof: {}", e)))?;
    let receipt_bytes = bincode::serialize(&prove_info.receipt)
        .map_err(|e| Risc0Error::SerializeError(format!("Failed to serialize receipt: {}", e)))?;
    Ok(Risc0ProofOutput { receipt: receipt_bytes })
}

#[uniffi::export]
pub fn risc0_verify(receipt_bytes: Vec<u8>) -> Result<Risc0VerifyOutput, Risc0Error> {
    let receipt: Receipt = bincode::deserialize(&receipt_bytes)
        .map_err(|e| Risc0Error::SerializeError(format!("Failed to deserialize receipt: {}", e)))?;
    receipt
        .verify(RISC0_CIRCUIT_ID)
        .map_err(|e| Risc0Error::VerifyError(format!("Failed to verify receipt: {}", e)))?;
    let output_value: u32 = receipt
        .journal
        .decode()
        .map_err(|e| Risc0Error::DecodeError(format!("Failed to decode journal: {}", e)))?;
    Ok(Risc0VerifyOutput { is_valid: true, output_value })
}

// ==============================================================================
// CAIRO-M
// ==============================================================================

#[cfg(feature = "cairo_m")]
#[derive(uniffi::Error, thiserror::Error, Debug)]
pub enum CairoError {
    #[error("Failed to prove: {0}")]
    ProveError(String),
    #[error("Failed to verify: {0}")]
    VerifyError(String),
    #[error("Serialization error: {0}")]
    SerializeError(String),
}

#[cfg(feature = "cairo_m")]
#[derive(uniffi::Record, Clone)]
pub struct CairoProofOutput {
    pub proof: Vec<u8>,
}

#[cfg(feature = "cairo_m")]
#[derive(uniffi::Record, Clone)]
pub struct CairoVerifyOutput {
    pub is_valid: bool,
}

#[cfg(feature = "cairo_m")]
#[uniffi::export]
pub fn cairo_prove(program_json: String, inputs_json: String, entrypoint: String) -> Result<CairoProofOutput, CairoError> {
    let proof = prove(&program_json, &inputs_json, &entrypoint)
        .map_err(|e| CairoError::ProveError(e.to_string()))?;
    Ok(CairoProofOutput { proof })
}

#[cfg(feature = "cairo_m")]
#[uniffi::export]
pub fn cairo_verify(proof: Vec<u8>) -> Result<CairoVerifyOutput, CairoError> {
    let is_valid = verify(&proof)
        .map_err(|e| CairoError::VerifyError(e.to_string()))?;
    Ok(CairoVerifyOutput { is_valid })
}

// ==============================================================================
// PROVEKIT
// ==============================================================================

#[cfg(feature = "provekit")]
use provekit_wrapper::{prove as _provekit_prove, verify as _provekit_verify};

#[cfg(feature = "provekit")]
#[derive(uniffi::Error, thiserror::Error, Debug)]
pub enum ProveKitError {
    #[error("Failed to prove: {0}")]
    ProveError(String),
    #[error("Failed to verify: {0}")]
    VerifyError(String),
}

#[cfg(feature = "provekit")]
#[derive(uniffi::Record, Clone)]
pub struct ProveKitProofOutput {
    pub proof: Vec<u8>,
}

#[cfg(feature = "provekit")]
#[derive(uniffi::Record, Clone)]
pub struct ProveKitVerifyOutput {
    pub is_valid: bool,
}

#[cfg(feature = "provekit")]
#[uniffi::export]
pub fn provekit_prove(prover_path: String, input_toml: String) -> Result<ProveKitProofOutput, ProveKitError> {
    let proof = _provekit_prove(&prover_path, &input_toml)
        .map_err(|e| ProveKitError::ProveError(format!("{:?}", e)))?;
    Ok(ProveKitProofOutput { proof })
}

#[cfg(feature = "provekit")]
#[uniffi::export]
pub fn provekit_verify(verifier_path: String, proof: Vec<u8>) -> Result<ProveKitVerifyOutput, ProveKitError> {
    let is_valid = _provekit_verify(&verifier_path, &proof)
        .map_err(|e| ProveKitError::VerifyError(format!("{:?}", e)))?;
    Ok(ProveKitVerifyOutput { is_valid })
}
