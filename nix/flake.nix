{
    description = "";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/24.11";
        flake-utils.url = "github:numtide/flake-utils";
    };

    outputs = { self, flake-utils, nixpkgs } :
        flake-utils.lib.eachSystem ["x86_64-linux"] (system: let
            pkgs = import nixpkgs {
                inherit system;
            };
            in { 
                devShell = with pkgs; pkgs.mkShellNoCC {
                    packages = with pkgs; [
                        gcc
                        # The wrapped compiler adds host hardening flags that
                        # are not supported when targeting bare-metal RISC-V.
                        llvmPackages.clang-unwrapped
                        llvmPackages.lld
                        llvmPackages.llvm
                        cmake
                        bluespec
                        yosys
                        iverilog
                        verilator
                        # tk-8_5
                    ];
                };
            }
        );
}
