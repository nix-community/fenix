with builtins;

mapAttrs (target: v:
  { lib, stdenv, zlib }:
  let rpath = "${zlib}/lib:$out/lib";
  in mapAttrs (_:
    { date, components }:
    let
      toolchain = mapAttrs (component: source:
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
            ${lib.optionalString (component == "rustc")
            "ln -sT {${toolchain.rust-std},$out}/lib/rustlib/${target}/lib"}
          '';
        }) components;
    in toolchain) v) (fromJSON (readFile ./toolchains.json))
