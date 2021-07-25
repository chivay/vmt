{
  description = "VMT - toy OS written in Zig";
  nixConfig.bash-prompt = "\[vmt-develop\]$ ";

  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:nixos/nixpkgs";
  inputs.zig-nightly.url = "github:chivay/zig-nightly";

  outputs = { self, nixpkgs, flake-utils, zig-nightly }:
    flake-utils.lib.eachDefaultSystem
      (system:
      let pkgs = nixpkgs.legacyPackages.${system};
          zig = zig-nightly.defaultPackage.${system};
      in
        {
          devShell = pkgs.mkShell { buildInputs = [ zig ]; };
        }
      );
}
