{ callPackage, fetchurl, lib, stdenv, zlib, curl, makeBinaryWrapper, path, apple-sdk ? null }:

suffix:
{ date, components }:

let
  inherit (builtins) attrValues mapAttrs pathExists;
  inherit (lib)
    attrVals maintainers mapAttrs' nameValuePair optionals optionalAttrs optionalString
    platforms removeSuffix;

  combine = callPackage ./combine.nix { };
  rpath = "${zlib}/lib:$out/lib";

  # Only available in recent nixpkgs.
  darwinSdkSetup = path + "/pkgs/build-support/wrapper-common/darwin-sdk-setup.bash";

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
                    --set-rpath ${stdenv.cc.cc.lib}/lib:${rpath} \
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

            # rustc links with its bundled lld (`gcc-ld/ld.lld`) by default on some targets, such
            # as x86_64-unknown-linux-gnu. That linker skips the nixpkgs ld wrapper, so the
            # binaries it links get no RUNPATH for the libraries they use from the Nix store,
            # and fail to start. Wrap it with the same ld wrapper that nixpkgs uses.
            #
            # `wrapBintools` can only wrap a standalone bintools package, so this copies the
            # minimum of its implementation, as oxalica/rust-overlay does:
            # https://github.com/NixOS/nixpkgs/blob/bfb7a882678e518398ce9a31a881538679f6f092/pkgs/build-support/bintools-wrapper/default.nix#L178
            wrap() {
              local dst="$1"
              local wrapper="$2"
              export prog="$3"
              export use_response_file_by_default=0
              substituteAll "$wrapper" "$dst"
              chmod +x "$dst"
            }

            dsts=( $out/lib/rustlib/*/bin/gcc-ld/ld.lld )
            if [ -e "''${dsts[0]}" ]; then
              mkdir -p $out/nix-support

              substituteAll ${path + "/pkgs/build-support/wrapper-common/utils.bash"} $out/nix-support/utils.bash

              substituteAll ${path + "/pkgs/build-support/bintools-wrapper/add-flags.sh"} $out/nix-support/add-flags.sh

              substituteAll ${path + "/pkgs/build-support/bintools-wrapper/add-hardening.sh"} $out/nix-support/add-hardening.sh

              ${optionalString (pathExists darwinSdkSetup) ''
                substituteAll ${darwinSdkSetup} $out/nix-support/darwin-sdk-setup.bash
              ''}

              ${optionalString stdenv.targetPlatform.isDarwin ''
                substituteAll ${path + "/pkgs/build-support/bintools-wrapper/add-darwin-ldflags-before.sh"} $out/nix-support/add-local-ldflags-before.sh
              ''}

              for dst in "''${dsts[@]}"; do
                # ld.lld finds rust-lld relative to its own path and picks its flavor from its
                # own name, so keep the name and the directory depth.
                unwrapped="$(dirname "$dst")-unwrapped/ld.lld"
                mkdir -p "$(dirname "$unwrapped")"
                mv "$dst" "$unwrapped"
                wrap "$dst" ${path + "/pkgs/build-support/bintools-wrapper/ld-wrapper.sh"} "$unwrapped"
              done
            fi
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

        # Values that the ld wrapper scripts above substitute.
        env = optionalAttrs (component == "rustc") (
          {
            inherit (stdenv.cc.bintools)
              coreutils_bin expandResponseParams shell suffixSalt wrapperName;

            # Only available in recent nixpkgs.
            mktemp = stdenv.cc.bintools.mktemp or "mktemp";
            rm = stdenv.cc.bintools.rm or "rm";

            hardening_unsupported_flags = "";

            fallback_sdk = optionalString (apple-sdk != null && stdenv.targetPlatform.isDarwin)
              (apple-sdk.__spliced.buildTarget or apple-sdk);
          }
          // mapAttrs (_: optionalString stdenv.targetPlatform.isDarwin) {
            inherit (stdenv.targetPlatform)
              darwinPlatform darwinSdkVersion darwinMinVersion darwinMinVersionVariable;
          }
        );

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
