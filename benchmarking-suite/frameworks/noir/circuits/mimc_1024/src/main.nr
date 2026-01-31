use dep::mimc::mimc_bn254;

// 1024 bits = 128 bytes -> 5 field elements (31 bytes per field)
fn main(input: [Field; 5]) -> pub Field {
    mimc_bn254(input)
}
