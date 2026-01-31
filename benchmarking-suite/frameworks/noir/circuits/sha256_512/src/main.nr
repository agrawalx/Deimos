use dep::sha256::sha256_var;

// SHA256 hash for 512-bit input (64 bytes)
fn main(input: [u8; 64]) -> pub [u8; 32] {
    sha256_var(input, 64)
}
