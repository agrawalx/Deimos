use dep::poseidon::poseidon::bn254::sponge;

// 1024 bits = 128 bytes -> 5 field elements (31 bytes per field)
fn main(input: [Field; 5]) -> pub Field {
    sponge(input)
}
