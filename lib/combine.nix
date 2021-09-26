{ lib, symlinkJoin }:

name: paths:

symlinkJoin {
  inherit name paths;
  postBuild = ''
    if [ -d $out/bin ]; then
      cp --remove-destination $(realpath $out/bin/*) $out/bin
    fi
  '';
  meta.platforms = lib.platforms.all;
}
