{
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, flake-utils, nixpkgs }:
    let pkgs = nixpkgs.legacyPackages;
    in {
      packages = builtins.mapAttrs (k: v:
        (import ./toolchains.nix).${v} { inherit (pkgs.${k}) stdenv zlib; })
        (import ./system.nix);
      overlay = (import ./.);
    } // flake-utils.lib.eachDefaultSystem (system: {
      devShell = with pkgs.${system};
        mkShell { buildInputs = [ (python3.withPackages (ps: [ ps.toml ])) ]; };
    });
}
