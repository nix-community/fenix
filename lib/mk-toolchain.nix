{ callPackage, lib, stdenv, zlib }:
name: date: components:

with builtins;

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

        ${lib.optionalString (component == "clippy-preview") ''
          patchelf \
            --set-rpath ${toolchain.rustc}/lib:${rpath} \
            $out/bin/clippy-driver
        ''}
      '';
      dontStrip = true;
      meta.platforms = lib.platforms.all;
    }) components;
in toolchain // {
  toolchain = combine "${name}-${date}" (attrValues toolchain);
  withComponents = componentNames:
    combine "${name}-with-components-${date}"
    (lib.attrVals componentNames toolchain);
} // lib.optionalAttrs (toolchain ? rustc) {
  rustc =
    combine "${name}-with-std-${date}" (with toolchain; [ rustc rust-std ]);
  rustc-unwrapped = toolchain.rustc;
}
