{
  description = "Rust toolchains and rust analyzer nightly for nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-analyzer-src = {
      url = "github:rust-analyzer/rust-analyzer/nightly";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, rust-analyzer-src }: rec {
    packages = builtins.mapAttrs (system: _:
      import ./. {
        inherit system rust-analyzer-src;
        flakeLock = throw "should not be accessed";
        nixpkgs = nixpkgs.legacyPackages.${system};
        lib = nixpkgs.lib;
      }) {
        aarch64-darwin = null;
        aarch64-linux = null;
        i686-linux = null;
        x86_64-darwin = null;
        x86_64-linux = null;
      };

    overlay = import ./lib/overlay.nix (pkgs: packages.${pkgs.system});
  };
}
