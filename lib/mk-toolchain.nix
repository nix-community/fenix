{ callPackage, fetchurl, lib, stdenv, zlib, curl, makeBinaryWrapper }:

suffix:
{ date, components }:

let
  inherit (builtins) attrValues mapAttrs;
  inherit (lib)
    attrVals maintainers mapAttrs' nameValuePair optionals optionalAttrs optionalString
    platforms removeSuffix;

  combine = callPackage ./combine.nix { };
  rpath = "${zlib}/lib:$out/lib:${stdenv.cc.cc.lib}/lib";

  toolchain = mapAttrs
    (component: source:
      stdenv.mkDerivation {
        pname = "${component}${suffix}";
        version = source.date or date;
        src = fetchurl { inherit (source) url sha256; };

        nativeBuildInputs = optionals (component == "rustfmt-preview" && stdenv.hostPlatform.isDarwin) [
          makeBinaryWrapper
        ];

        installPhase = ''
          patchShebangs install.sh
          CFG_DISABLE_LDCONFIG=1 ./install.sh --prefix=$out

          rm $out/lib/rustlib/{components,install.log,manifest-*,rust-installer-version,uninstall.sh} || true

          ${optionalString stdenv.hostPlatform.isLinux ''
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

              for file in $(find $out/lib -path '*/bin/*' -type f); do
                if isELF "$file"; then
                  patchelf \
                    --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
                    --set-rpath ${rpath} \
                    "$file" || true
                fi
              done
            fi

            if [ -d $out/libexec ]; then
              for file in $(find $out/libexec -type f); do
                if isELF "$file"; then
                  patchelf \
                    --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
                    --set-rpath ${rpath} \
                    "$file" || true
                fi
              done
            fi

            ${optionalString (component == "llvm-tools-preview") ''
              for file in $out/lib/rustlib/*/bin/*; do
                patchelf \
                  --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
                  --set-rpath $out/lib/rustlib/*/lib \
                  "$file" || true
              done
            ''}
          ''}

          ${optionalString (component == "rustc") ''
            ${optionalString stdenv.hostPlatform.isDarwin ''
              if [ -e $out/lib/libLLVM.dylib ]; then
                for dir in $out/lib/rustlib/*-apple-darwin; do
                  if [ -d "$dir/bin" ] && [ ! -e "$dir/lib/libLLVM.dylib" ]; then
                    mkdir -p "$dir/lib"
                    ln -s $out/lib/libLLVM.dylib "$dir/lib/libLLVM.dylib"
                  fi
                done
              fi
            ''}
          ''}

          ${optionalString (component == "cargo") ''
            ${optionalString stdenv.hostPlatform.isDarwin ''
              install_name_tool \
                -change "/usr/lib/libcurl.4.dylib" "${curl.out}/lib/libcurl.4.dylib" \
                $out/bin/cargo || true
            ''}
          ''}
          
          ${optionalString (component == "miri-preview") ''
            ${optionalString stdenv.hostPlatform.isLinux ''
              patchelf \
                --set-rpath ${toolchain.rustc}/lib $out/bin/miri || true
            ''}
            ${optionalString stdenv.hostPlatform.isDarwin ''
              install_name_tool \
                -add_rpath ${toolchain.rustc}/lib $out/bin/miri || true
            ''}
          ''}

          ${optionalString (component == "rls-preview") ''
            ${optionalString stdenv.hostPlatform.isLinux ''
              patchelf \
                --set-rpath ${toolchain.rustc}/lib $out/bin/rls || true
            ''}
            ${optionalString stdenv.hostPlatform.isDarwin ''
              install_name_tool \
                -add_rpath ${toolchain.rustc}/lib $out/bin/rls || true
            ''}
          ''}

          ${optionalString (component == "rustfmt-preview") ''
            ${optionalString stdenv.hostPlatform.isLinux ''
              patchelf \
                --set-rpath ${toolchain.rustc}/lib $out/bin/rustfmt || true
            ''}
            ${
              # error: install_name_tool: changing install names or rpaths can't be redone
              # because larger updated load commands do not fit (the program must be relinked)
              optionalString stdenv.hostPlatform.isDarwin ''
                wrapProgram $out/bin/rustfmt \
                  --prefix DYLD_LIBRARY_PATH : ${toolchain.rustc}/lib
              ''
            }
          ''}

          ${optionalString (component == "rust-analyzer-preview") ''
            ${optionalString stdenv.hostPlatform.isLinux ''
              patchelf \
                --set-rpath ${toolchain.rustc}/lib $out/bin/rust-analyzer || true
            ''}
            ${optionalString stdenv.hostPlatform.isDarwin ''
              install_name_tool \
                -add_rpath ${toolchain.rustc}/lib $out/bin/rust-analyzer || true
            ''}
          ''}
        '';
        dontStrip = true;
        meta = {
          maintainers = with maintainers; [ figsoda ];
          platforms = platforms.all;
        };
      })
    components;

  toolchain' = toolchain // {
    toolchain = combine "rust${suffix}-${date}"
      (attrValues (removeAttrs toolchain [ "rustc-dev" ]));
  } // optionalAttrs (toolchain ? rustc) {
    rustc = combine "rust${suffix}-with-std-${date}"
      (with toolchain; [ rustc rust-std ]) // {
      unwrapped = toolchain.rustc;
    };
    rustc-unwrapped = toolchain.rustc;
  } // optionalAttrs (toolchain ? clippy-preview) {
    clippy-preview = combine "clippy${suffix}-with-std-${date}"
      (with toolchain; [ clippy-preview rustc rust-std ]) // {
      unwrapped = toolchain.clippy-preview;
    };
    clippy-preview-unwrapped = toolchain.clippy-preview;
    clippy-unwrapped = toolchain.clippy-preview;
  } // optionalAttrs (toolchain ? miri-preview) {
    miri-preview = combine "clippy${suffix}-with-src-${date}"
      (with toolchain; [ miri-preview rustc rust-src ]) // {
      unwrapped = toolchain.miri-preview;
    };
    miri-preview-unwrapped = toolchain.miri-preview;
    miri-unwrapped = toolchain.miri-preview;
  };

  toolchain'' = toolchain' // mapAttrs' (k: nameValuePair (removeSuffix "-preview" k)) toolchain';
in

toolchain'' // {
  withComponents = componentNames: combine
    "rust${suffix}-with-components-${date}"
    (attrVals componentNames toolchain'');
}
