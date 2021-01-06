{
  description = "Rust nightly toolchains for nix";

  inputs = {
    naersk = {
      url = "github:nmattia/naersk";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    rust-analyzer-src = {
      url = "github:rust-analyzer/rust-analyzer/nightly";
      flake = false;
    };
  };

  outputs = { self, naersk, nixpkgs, rust-analyzer-src }: rec {
    defaultPackage = packages;

    packages = with builtins;
      mapAttrs (k: v:
        let
          pkgs = nixpkgs.legacyPackages.${k};
          toolchains = (import ./lib/toolchains.nix).${v} {
            inherit (pkgs) lib stdenv symlinkJoin zlib;
          };
          rust-analyzer-rev = substring 0 7 (fromJSON
            (readFile ./flake.lock)).nodes.rust-analyzer-src.locked.rev;
        in toolchains // rec {
          rust-analyzer = (naersk.lib.${k}.override {
            inherit (toolchains.minimal) cargo rustc;
          }).buildPackage {
            name = "rust-analyzer-nightly";
            version = rust-analyzer-rev;
            src = rust-analyzer-src;
            cargoBuildOptions = xs: xs ++ [ "-p" "rust-analyzer" ];
            CARGO_INCREMENTAL = "0";
            RUST_ANALYZER_REV = rust-analyzer-rev;
          };

          rust-analyzer-vscode-extension =
            pkgs.vscode-utils.buildVscodeExtension {
              name = "rust-analyzer-${rust-analyzer-rev}";
              src = ./lib/rust-analyzer-vsix.zip;
              vscodeExtUniqueId = "matklad.rust-analyzer";
              buildInputs = with pkgs; [ jq moreutils ];
              patchPhase = ''
                jq -e '.contributes.configuration.properties."rust-analyzer.server.path"
                  .default = "${rust-analyzer}/bin/rust-analyzer"
                ' package.json | sponge package.json
              '';
            };
        }) (import ./lib/systems.nix);

    overlay = _: super:
      let fenix = packages.${super.system};
      in {
        rust-nightly = { inherit (fenix) minimal default complete latest; };
        rust-analyzer-nightly = fenix.rust-analyzer;
        vscode-extensions.matklad.rust-analyzer-nightly =
          fenix.rust-analyzer-vscode-extension;
      };
  };
}
