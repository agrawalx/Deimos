use dep::poseidon::poseidon::bn254::sponge;

// 256 bits = 32 bytes -> 2 field elements (31 bytes per field)
fn main(input: [Field; 2]) -> pub Field {
    sponge(input)
}
