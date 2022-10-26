{
  description = "Rust toolchains and rust analyzer nightly for nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-analyzer-src = {
      url = "github:rust-lang/rust-analyzer/nightly";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, rust-analyzer-src }:
    let
      inherit (builtins) isAttrs mapAttrs typeOf;
      inherit (nixpkgs.lib) genAttrs isDerivation warn;
    in

    {
      packages = genAttrs
        [
          "aarch64-darwin"
          "aarch64-linux"
          "i686-linux"
          "x86_64-darwin"
          "x86_64-linux"
        ]
        (system: mapAttrs
          (_: x:
            if isDerivation x then x
            else if isAttrs x then x // {
              type = "derivation";
              name = "dummy-attrset";
            } else {
              type = "derivation";
              name = "dummy-${typeOf x}";
              __functor = _: x;
            })
          (import ./. {
            inherit system rust-analyzer-src;
            inherit (nixpkgs) lib;
            pkgs = nixpkgs.legacyPackages.${system};
          }));

      overlay = warn
        "`fenix.overlay` is deprecated; use 'fenix.overlays.default' instead"
        self.overlays.default;

      overlays.default = final: prev: import ./overlay.nix final prev;
    };
}
