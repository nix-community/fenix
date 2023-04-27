{ lib, symlinkJoin, stdenv }:

let
  inherit (lib) maintainers optionalString platforms;
in

name: paths:

symlinkJoin {
  inherit name paths;
  postBuild = ''
    for file in $(find $out/bin -xtype f -maxdepth 1); do
      install -m755 $(realpath "$file") $out/bin

      if [[ $file =~ /rustfmt$ ]]; then
        continue
      fi

      ${optionalString stdenv.isLinux ''
        if isELF "$file"; then
          patchelf --set-rpath $out/lib "$file" || true
        fi
      ''}

      ${optionalString stdenv.isDarwin ''
        install_name_tool -add_rpath $out/lib "$file" || true
      ''}
    done

    for file in $(find $out/lib -name "librustc_driver-*"); do
      install $(realpath "$file") "$file"
    done
  '';
  meta = {
    maintainers = with maintainers; [ figsoda ];
    platforms = platforms.all;
  };
}
