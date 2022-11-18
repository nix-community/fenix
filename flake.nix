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
      inherit (builtins) concatLists concatStringsSep isAttrs listToAttrs typeOf;
      inherit (nixpkgs.lib) flatten genAttrs isDerivation mapAttrsToList nameValuePair systems warn;

      attrDerivations = set: path: (mapAttrsToList
        (k: v:
          if isDerivation v then
            [ (nameValuePair (concatStringsSep "." (path ++ [ k ])) v) ]
          else if isAttrs v then
            attrDerivations v (path ++ [ k ])
          else
            [ ])
        set);
    in

    {
      formatter = genAttrs systems.flakeExposed
        (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);

      packages = genAttrs
        [
          "aarch64-darwin"
          "aarch64-linux"
          "i686-linux"
          "x86_64-darwin"
          "x86_64-linux"
        ]
        (system: listToAttrs (concatLists (mapAttrsToList
          (k: v:
            if isDerivation v then
              [ (nameValuePair k v) ]
            else if isAttrs v then
              [
                (nameValuePair k (v // {
                  type = "derivation";
                  name = "dummy-attrset";
                }))
              ] ++ (if k == "targets" then
                map
                  (x: nameValuePair "targets.<triple>.${x}.rust-std" {
                    type = "derivation";
                    name = "dummy-rust-std";
                  })
                  [ "stable" "beta" "latest" ]
              else
                flatten (attrDerivations v [ k ]))
            else
              [
                (nameValuePair k {
                  type = "derivation";
                  name = "dummy-${typeOf v}";
                  __functor = _: v;
                })
              ]
          )
          (import ./. {
            inherit system rust-analyzer-src;
            inherit (nixpkgs) lib;
            pkgs = nixpkgs.legacyPackages.${system};
          }))));

      overlay = warn
        "`fenix.overlay` is deprecated; use 'fenix.overlays.default' instead"
        self.overlays.default;

      overlays.default = final: prev: import ./overlay.nix final prev;
    };
}
