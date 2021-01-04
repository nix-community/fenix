{ pkgs }:

(import ./lib/toolchains.nix).${(import ./lib/system.nix).${pkgs.system}} {
  inherit (pkgs) lib stdenv symlinkJoin zlib;
}
