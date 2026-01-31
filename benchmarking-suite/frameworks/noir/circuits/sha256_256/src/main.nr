use dep::sha256::digest;

// SHA256 hash for 256-bit input (32 bytes)
fn main(input: [u8; 32]) -> pub [u8; 32] {
    digest(input)
}
