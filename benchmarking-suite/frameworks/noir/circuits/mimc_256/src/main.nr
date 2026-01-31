use dep::mimc::mimc_bn254;

// 256 bits = 32 bytes -> 2 field elements (31 bytes per field)
fn main(input: [Field; 2]) -> pub Field {
    mimc_bn254(input)
}
