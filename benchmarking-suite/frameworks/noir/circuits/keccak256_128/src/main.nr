use dep::keccak256::keccak256;

// Keccak256 hash for 128-bit input (16 bytes)
fn main(input: [u8; 16]) -> pub [u8; 32] {
    keccak256(input, 16)
}
