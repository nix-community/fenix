{
  description = "Rust nightly toolchains for nix";

  inputs.nixpkgs.url = "nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }: {
    packages = builtins.mapAttrs (k: v:
      (import ./lib/toolchains.nix).${v} {
        inherit (nixpkgs.legacyPackages.${k}) lib stdenv symlinkJoin zlib;
      }) (import ./lib/system.nix);
    overlay = import ./.;
  };
}
