{ callPackage, lib, stdenv, zlib }:

name:
{ date, components }:

with builtins;
with lib;

let
  combine = callPackage ./combine.nix { };
  rpath = "${zlib}/lib:$out/lib";
in let
  toolchain = mapAttrs (component: source:
    stdenv.mkDerivation {
      pname = "${component}-nightly";
      version = source.date or date;
      src = fetchurl { inherit (source) url sha256; };
      installPhase = ''
        patchShebangs install.sh
        CFG_DISABLE_LDCONFIG=1 ./install.sh --prefix=$out

        rm $out/lib/rustlib/{components,install.log,manifest-*,rust-installer-version,uninstall.sh} || true

        ${optionalString stdenv.isLinux ''
          if [ -d $out/bin ]; then
            for file in $(find $out/bin -type f); do
              if isELF "$file"; then
                patchelf \
                  --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
                  --set-rpath ${rpath} \
                  "$file" || true
              fi
            done
          fi

          if [ -d $out/lib ]; then
            for file in $(find $out/lib -type f); do
              if isELF "$file"; then
                patchelf --set-rpath ${rpath} "$file" || true
              fi
            done
          fi

          ${optionalString (component == "rustc") ''
            for file in $(find $out/lib/rustlib/*/bin -type f); do
              if isELF "$file"; then
                patchelf \
                  --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
                  --set-rpath $out/lib \
                  "$file"
              fi
            done
          ''}

          ${optionalString (component == "llvm-tools-preview") ''
            for file in $out/lib/rustlib/*/bin/*; do
              patchelf \
                --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
                --set-rpath $out/lib/rustlib/*/lib \
                "$file"
            done
          ''}
        ''}

        ${optionalString (component == "clippy-preview") ''
          ${optionalString stdenv.isLinux ''
            patchelf \
              --set-rpath ${toolchain.rustc}/lib:${rpath} \
              $out/bin/clippy-driver
          ''}
          ${optionalString stdenv.isDarwin ''
            install_name_tool \
              -add_rpath ${toolchain.rustc}/lib \
              $out/bin/clippy-driver
          ''}
        ''}
      '';
      dontStrip = true;
      meta.platforms = platforms.all;
    }) components;
in toolchain // {
  toolchain = combine "${name}-${date}" (attrValues toolchain);
  withComponents = componentNames:
    combine "${name}-with-components-${date}"
    (attrVals componentNames toolchain);
} // optionalAttrs (toolchain ? rustc) {
  rustc =
    combine "${name}-with-std-${date}" (with toolchain; [ rustc rust-std ]);
  rustc-unwrapped = toolchain.rustc;
}
