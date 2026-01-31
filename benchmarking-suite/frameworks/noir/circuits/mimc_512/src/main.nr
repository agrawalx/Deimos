use dep::mimc::mimc_bn254;

// 512 bits = 64 bytes -> 3 field elements (31 bytes per field)
fn main(input: [Field; 3]) -> pub Field {
    mimc_bn254(input)
}
