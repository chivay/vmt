{
  description = "VMT - toy OS written in Zig";
  nixConfig.bash-prompt = "\[vmt-develop\]$ ";

  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.zig-nightly.url = "github:chivay/zig-nightly";

  outputs = { self, nixpkgs, flake-utils, zig-nightly }:
    flake-utils.lib.eachDefaultSystem
      (system:
      let pkgs = nixpkgs.legacyPackages.${system};
          zig = zig-nightly.defaultPackage.${system};
      in
        {
          packages.vmt = pkgs.stdenv.mkDerivation {
            name = "vmt";
            nativeBuildInputs = [ zig ];
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
          devShell = pkgs.mkShell { buildInputs = [ zig pkgs.qemu pkgs.grub2 pkgs.xorriso ]; };
        }
      );
}
