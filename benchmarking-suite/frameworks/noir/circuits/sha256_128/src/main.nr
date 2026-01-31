use dep::sha256::digest;

// SHA256 hash for 128-bit input (16 bytes)
fn main(input: [u8; 16]) -> pub [u8; 32] {
    // Pad the 16-byte input to 32 bytes for sha256
    let mut padded: [u8; 32] = [0; 32];
    for i in 0..16 {
        padded[i] = input[i];
    }
    digest(padded)
}
