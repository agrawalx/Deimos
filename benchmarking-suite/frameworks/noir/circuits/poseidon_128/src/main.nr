use dep::poseidon::poseidon::bn254::sponge;

// 128 bits = 16 bytes -> 1 field element (31 bytes per field)
fn main(input: [Field; 1]) -> pub Field {
    sponge(input)
}
