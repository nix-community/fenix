{
  description = "Rust toolchains and rust analyzer nightly for nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-analyzer-src = {
      url = "github:rust-analyzer/rust-analyzer/nightly";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, rust-analyzer-src }: {
    legacyPackages = nixpkgs.lib.genAttrs [
      "aarch64-darwin"
      "aarch64-linux"
      "i686-linux"
      "x86_64-darwin"
      "x86_64-linux"
    ] (system:
      import ./. {
        inherit system rust-analyzer-src;
        pkgs = nixpkgs.legacyPackages.${system};
        lib = nixpkgs.lib;
      });

    overlay =
      import ./lib/overlay.nix (pkgs: self.legacyPackages.${pkgs.system});
  };
}
