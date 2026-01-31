use std::hash::blake3;

// Blake3 hash for 512-bit input (64 bytes)
fn main(input: [u8; 64]) -> pub [u8; 32] {
    // Blake3 in std::hash accepts [u8; 32], so we need to hash in chunks
    let mut chunk1: [u8; 32] = [0; 32];
    for i in 0..32 {
        chunk1[i] = input[i];
    }
    let h1 = blake3(chunk1);
    
    let mut chunk2: [u8; 32] = [0; 32];
    for i in 0..32 {
        chunk2[i] = input[i + 32];
    }
    let h2 = blake3(chunk2);
    
    // Combine the hashes by XORing
    let mut result: [u8; 32] = [0; 32];
    for i in 0..32 {
        result[i] = h1[i] ^ h2[i];
    }
    // Final hash of the combined result
    blake3(result)
}
