use std::hash::blake3;

// Blake3 hash for 1024-bit input (128 bytes)
fn main(input: [u8; 128]) -> pub [u8; 32] {
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
    
    let mut chunk3: [u8; 32] = [0; 32];
    for i in 0..32 {
        chunk3[i] = input[i + 64];
    }
    let h3 = blake3(chunk3);
    
    let mut chunk4: [u8; 32] = [0; 32];
    for i in 0..32 {
        chunk4[i] = input[i + 96];
    }
    let h4 = blake3(chunk4);
    
    // Combine h1 and h2
    let mut combined12: [u8; 32] = [0; 32];
    for i in 0..32 {
        combined12[i] = h1[i] ^ h2[i];
    }
    let h12 = blake3(combined12);
    
    // Combine h3 and h4
    let mut combined34: [u8; 32] = [0; 32];
    for i in 0..32 {
        combined34[i] = h3[i] ^ h4[i];
    }
    let h34 = blake3(combined34);
    
    // Final combination
    let mut final_combined: [u8; 32] = [0; 32];
    for i in 0..32 {
        final_combined[i] = h12[i] ^ h34[i];
    }
    blake3(final_combined)
}
