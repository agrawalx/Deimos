use dep::sha256::sha256_var;

// SHA256 hash for 1024-bit input (128 bytes)
fn main(input: [u8; 128]) -> pub [u8; 32] {
    sha256_var(input, 128)
}
