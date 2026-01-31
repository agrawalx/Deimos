use dep::keccak256::keccak256;

// Keccak256 hash for 1024-bit input (128 bytes)
fn main(input: [u8; 128]) -> pub [u8; 32] {
    keccak256(input, 128)
}
