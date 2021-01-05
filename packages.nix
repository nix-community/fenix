{ pkgs }:

(import ./lib/toolchains.nix).${(import ./lib/systems.nix).${pkgs.system}} {
  inherit (pkgs) lib stdenv symlinkJoin zlib;
}
