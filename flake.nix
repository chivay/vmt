{
  description = "VMT - toy OS written in Zig";
  nixConfig.bash-prompt = "\[vmt-develop\]$ ";

  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.zig-nightly.url = "github:chivay/zig-nightly";

  outputs = { self, nixpkgs, flake-utils, zig-nightly}:
    flake-utils.lib.eachDefaultSystem
      (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          packages.vmt = pkgs.stdenv.mkDerivation {
            name = "vmt";
            nativeBuildInputs = [ pkgs.zig ];
            src = self;

            buildPhase = ''
              export HOME=$TMPDIR;
              zig build kernel
            '';

            doCheck = true;
            checkPhase = ''
              zig test kernel/kernel.zig
            '';

            installPhase = ''
              cp -r ./build/x86_64/kernel $out
            '';

          };
          devShell = pkgs.mkShell { buildInputs = with pkgs; [ zig-nightly.packages.${system}.zig-nightly-bin qemu grub2 xorriso bochs nixpkgs-fmt llvmPackages_14.llvm ]; };
        }
      );
}
