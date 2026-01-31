use dep::keccak256::keccak256;

// Keccak256 hash for 512-bit input (64 bytes)
fn main(input: [u8; 64]) -> pub [u8; 32] {
    keccak256(input, 64)
}
