{
  description = "Rust nightly toolchains and rust analyzer nightly for nix";

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
          toolchains = pkgs.callPackage ./lib/toolchains.nix { };
          rust-analyzer-rev = substring 0 7 (fromJSON
            (readFile ./flake.lock)).nodes.rust-analyzer-src.locked.rev;
        in toolchains.${v} // rec {
          combine =
            import ./lib/combine.nix pkgs.symlinkJoin "rust-nightly-mixed";

          targets = toolchains;

          rust-analyzer = (naersk.lib.${k}.override {
            inherit (toolchains.${v}.minimal) cargo rustc;
          }).buildPackage {
            name = "rust-analyzer-nightly";
            version = rust-analyzer-rev;
            src = rust-analyzer-src;
            cargoBuildOptions = xs: xs ++ [ "-p" "rust-analyzer" ];
            CARGO_INCREMENTAL = "0";
            RUST_ANALYZER_REV = rust-analyzer-rev;
          };

          rust-analyzer-vscode-extension = let
            setDefault = k: v: ''
              .contributes.configuration.properties."rust-analyzer.${k}".default = "${v}"
            '';
          in pkgs.vscode-utils.buildVscodeExtension {
            name = "rust-analyzer-${rust-analyzer-rev}";
            src = ./lib/rust-analyzer-vsix.zip;
            vscodeExtUniqueId = "matklad.rust-analyzer";
            buildInputs = with pkgs; [ jq moreutils ];
            patchPhase = ''
              jq -e '
                ${setDefault "server.path" "${rust-analyzer}/bin/rust-analyzer"}
                | ${setDefault "updates.channel" "nightly"}
              ' package.json | sponge package.json
            '';
          };
        }) (import ./lib/systems.nix);

    overlay = import ./lib/overlay.nix (pkgs: packages.${pkgs.system});
  };
}
