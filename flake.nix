{
  description = "Rust nightly toolchains for nix";

  inputs.nixpkgs.url = "nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }: {
    packages = builtins.mapAttrs (k: v:
      (import ./toolchains.nix).${v} {
        inherit (nixpkgs.legacyPackages.${k}) lib stdenv zlib;
      }) (import ./system.nix);
    overlay = import ./.;
  };
}
