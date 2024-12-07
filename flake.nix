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
      inherit (builtins)
        concatStringsSep
        isAttrs
        ;
      inherit (nixpkgs.lib)
        concatMapAttrs
        genAttrs
        isDerivation
        isFunction
        warn
        ;

      eachSystem = genAttrs [
        "aarch64-darwin"
        "aarch64-linux"
        "i686-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      attrDerivations = set: path: (concatMapAttrs
        (k: v:
          if isDerivation v then
            { ${concatStringsSep "." (path ++ [ k ])} = v; }
          else if isAttrs v then
            attrDerivations v (path ++ [ k ])
          else
            { })
        set);
    in

    {
      formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);

      packages = eachSystem (system: concatMapAttrs
        (k: v:
          if isDerivation v then
            { ${k} = v; }
          else if isFunction v then
            {
              ${k} = {
                type = "derivation";
                name = "dummy-function";
                __functor = _: v;
              };
            }
          else if isAttrs v then
            (if k == "targets" then
              genAttrs
                (map (x: "targets.<triple>.${x}.rust-std") [ "stable" "beta" "latest" ])
                (_: {
                  type = "derivation";
                  name = "dummy-rust-std";
                })
            else
              attrDerivations v [ k ])
            // {
              ${k} = {
                type = "derivation";
                name = "dummy-attrset";
              } // v;
            }
          else v)
        (import ./. {
          inherit rust-analyzer-src;
          inherit (nixpkgs) lib;
          pkgs = nixpkgs.legacyPackages.${system};
        }));

      overlay = warn
        "`fenix.overlay` is deprecated; use 'fenix.overlays.default' instead"
        self.overlays.default;

      overlays.default = import ./overlay.nix;
    };
}
