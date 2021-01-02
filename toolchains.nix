with builtins;

mapAttrs (_: v:
  { stdenv, zlib }:
  let rpath = "${zlib}/lib:$out/lib";
  in mapAttrs (_:
    { date, components }:
    mapAttrs (component: source:
      stdenv.mkDerivation {
        pname = "${component}-nightly";
        version = date;
        src = fetchurl source;
        installPhase = ''
          patchShebangs install.sh
          CFG_DISABLE_LDCONFIG=1 ./install.sh --prefix=$out

          for file in $(find $out/bin -type f); do
            if isELF "$file"; then
              patchelf \
                --set-interpreter "$(< ${stdenv.cc}/nix-support/dynamic-linker)" \
                --set-rpath ${rpath} \
                "$file"
            fi
          done

          for file in $(find $out/lib -type f); do
            if isELF "$file"; then
              patchelf --set-rpath ${rpath} "$file"
            fi
          done
        '';
      }) components) v) (fromJSON (readFile ./toolchains.json))
