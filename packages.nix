{ pkgs }:

(import ./toolchains.nix).${(import ./system.nix).${pkgs.system}} {
  inherit (pkgs) lib stdenv symlinkJoin zlib;
}
