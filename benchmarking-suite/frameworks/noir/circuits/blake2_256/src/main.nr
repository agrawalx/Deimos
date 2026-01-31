use std::hash::blake2s;

// Blake2s hash for 256-bit input (32 bytes)
fn main(input: [u8; 32]) -> pub [u8; 32] {
    blake2s(input)
}
