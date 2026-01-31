use std::hash::blake3;

// Blake3 hash for 256-bit input (32 bytes)
fn main(input: [u8; 32]) -> pub [u8; 32] {
    blake3(input)
}
