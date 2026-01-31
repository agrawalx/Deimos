use std::hash::blake3;

// Blake3 hash for 128-bit input (16 bytes)
fn main(input: [u8; 16]) -> pub [u8; 32] {
    // Pad to 32 bytes for blake3
    let mut padded: [u8; 32] = [0; 32];
    for i in 0..16 {
        padded[i] = input[i];
    }
    blake3(padded)
}
