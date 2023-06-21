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
          vmtZig = zigpkgs."master";
        in
        {
          defaultPackage = self.outputs.packages.${system}.vmt;
          packages.vmt = pkgs.stdenv.mkDerivation {
            name = "vmt";
            nativeBuildInputs = with pkgs; [ vmtZig grub2 xorriso ];
            src = self;

            buildPhase = ''
              export HOME=$TMPDIR;
              zig build iso
            '';

            installPhase = ''
              mkdir -p $out
              cp -r ./build/kernel.iso $out/kernel.iso
            '';

          };

          devShell = pkgs.mkShell {
            buildInputs = with pkgs; [ qemu grub2 xorriso bochs nixpkgs-fmt ] ++ [vmtZig];
          };
        }
      );
}
