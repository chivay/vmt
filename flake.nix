{
  description = "VMT - toy OS written in Zig";
  nixConfig.bash-prompt = "\[vmt-develop\]$ ";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    zig.url = "github:mitchellh/zig-overlay";
    zig.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, zig }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          zigpkgs = zig.packages.${system};
          vmtZig = zigpkgs."0.10.1";
        in
        {
          packages.vmt = pkgs.stdenv.mkDerivation {
            name = "vmt";
            nativeBuildInputs = [ vmtZig ];
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

          devShell = pkgs.mkShell {
            buildInputs = with pkgs; [ qemu grub2 xorriso bochs nixpkgs-fmt ] ++ [vmtZig];
          };
        }
      );
}
