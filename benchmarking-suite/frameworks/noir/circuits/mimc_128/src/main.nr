use dep::mimc::mimc_bn254;

// 128 bits = 16 bytes -> 1 field element (31 bytes per field)
fn main(input: [Field; 1]) -> pub Field {
    mimc_bn254(input)
}
