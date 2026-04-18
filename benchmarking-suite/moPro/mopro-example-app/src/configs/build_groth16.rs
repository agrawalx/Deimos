fn main() {
    // ==============================================================================
    // CIRCOM witness calculators
    // ==============================================================================
    let dir = "./test-vectors/circom";
    rust_witness::transpile::transpile_wasm(dir.to_string());

    let witnesscalc_dir = std::path::Path::new(dir).join("witnesscalc");
    if witnesscalc_dir.exists() {
        let mut build = cc::Build::new();
        build.cpp(true);
        build.define("W2C2_LOOP_START", Some(""));

        let paths = std::fs::read_dir(&witnesscalc_dir).unwrap();
        let mut has_cpp = false;
        for path in paths {
            let path = path.unwrap().path();
            if path.extension().map_or(false, |e| e == "cpp") {
                build.file(&path);
                has_cpp = true;
                println!("cargo:warning=Compiling witness file: {:?}", path);
            }
        }

        if has_cpp {
            build.compile("witnesses");
            println!("cargo:rustc-link-lib=static=witnesses");
        }
    }

    // ==============================================================================
    // RISC0 methods
    // ==============================================================================
    // The `methods` crate (via its own build.rs) compiles the guest program.
    // Nothing to do here beyond asserting the path exists.
    if !std::path::Path::new("../risc0-circuit/methods").exists() {
        println!("cargo:warning=risc0-circuit/methods not found — RISC0 exports will fail to link.");
    }
}
