use dep::keccak256::keccak256;

// Keccak256 hash for 256-bit input (32 bytes)
fn main(input: [u8; 32]) -> pub [u8; 32] {
    keccak256(input, 32)
}
