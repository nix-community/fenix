let
  inherit (pkgs) lib stdenv;

  sources = import ./npins;
  system = builtins.currentSystem;

  pkgs = import sources.nixpkgs {
    localSystem = { inherit system; };
  };

  fenix = import sources.fenix {
    inherit system pkgs;
  };
  toolchain = with fenix; combine [
    (stable.withComponents [
      "rust-analyzer"
      "rust-src"
      "cargo"
      "rustc"
      "rustfmt"
      "clippy"
    ])
    targets.wasm32-unknown-unknown.stable.rust-std
  ];
  crane =
    let
      crane = import sources.crane {
        inherit pkgs;
      };
    in
    crane.overrideToolchain toolchain;

  src = crane.cleanCargoSource ./.;

  buildArgs = {
    inherit src;
    strictDeps = true;

    nativeBuildInputs = with pkgs; [
      # Additional compile time deps
      # llvmPackages.bintools
    ] ++ lib.optionals stdenv.isDarwin [
      # MacOS only compile time deps
      libiconv
    ] ++ lib.optionals stdenv.isLinux [
      # Linux only compile time deps
      # autoPatchelfHook
    ];
    buildInputs = with pkgs; [
      # Additional runtime deps  
    ] ++ lib.optionals stdenv.isDarwin [
      # MacOS only runtime deps
      # libclang.lib
    ] ++ lib.optionals stdenv.isLinux [
      # Linux only runtime deps
      # gcc.cc
      # gcc.cc.lib
    ];
  };

  # Build only the dependency derivations for caching tools like cachix
  cargoArtifacts = crane.buildDepsOnly buildArgs;

  packages = {
    # Build for the wasm target
    fenix-wasm = crane.buildPackage (buildArgs // {
      pname = "fenix-wasm";
      doCheck = false; # Checks cannot be ran for this target without wasm-pack
      CARGO_BUILD_TARGET = "wasm32-unknown-unknown";
    });

    # Build an optimized wasm pkg with wasm-pack
    fenix-wasm-pack = crane.buildPackage (buildArgs // {
      pname = "fenix-wasm-pack";
      nativeBuildInputs = with pkgs; [
        wasm-pack
        wasm-bindgen-cli_0_2_114 # wasm-bindgen-cli must match the version of wasm-bindgen
        binaryen
      ];
      buildPhaseCargoCommand = ''
        wasm-pack build \
          --mode no-install \
          --target web \
          --out-dir $out/pkg
      '';
      dontInstall = true;
      doNotPostBuildInstallCargoBinaries = true;
      WASM_PACK_CACHE = "/build/.wasm-pack-cache";
    });
  };

  checks = {
    treefmt-check =
      let
        treefmt =
          let
            treefmt = import sources.treefmt;
            formattingOptions = {
              projectRootFile = "Cargo.lock";
              programs = {
                # Add additional formatters and settings:
                # https://github.com/numtide/treefmt-nix/tree/main/programs
                nixpkgs-fmt.enable = true;
                rustfmt.enable = true;
                taplo.enable = true;
                prettier.enable = true;
              };
            };
          in
          treefmt.evalModule pkgs formattingOptions;
      in
      treefmt.config.build.check src;

    cargo-clippy = crane.cargoClippy (buildArgs // {
      inherit cargoArtifacts src;
      cargoClippyExtraArgs = "--all-targets -- --deny warnings";
    });

    cargo-nextest = crane.cargoNextest (buildArgs // {
      inherit cargoArtifacts src;
      partitions = 1;
      partitionType = "count";
      cargoNextestExtraArgs = "--no-tests=warn";
    });

    cargo-doc = crane.cargoDoc (buildArgs // {
      inherit cargoArtifacts;
      env.RUSTDOCFLAGS = "--deny warnings";
    });
  };
in
packages // checks // {
  # Build all packages: `nix-build`
  default = pkgs.symlinkJoin {
    name = "fenix-wasm-packages";
    paths = builtins.attrValues packages;
  };

  # Build all checks: `nix-build release.nix -A checks`
  checks = pkgs.linkFarm "fenix-wasm-checks" (lib.mapAttrsToList
    (name: path: {
      inherit name path;
    })
    checks);

  # Enter a development shell with the toolchain used
  # to build packages and checks: `nix-shell`
  devshell = crane.devShell {
    inherit checks;
    packages =
      let
        nix-clean = pkgs.writeShellApplication {
          name = "nix-clean";
          meta.description = "Clean up result symlinks produced by nix.";
          text = ''
            ${pkgs.findutils}/bin/find . -maxdepth 1 -name 'result*' -type l -delete
          '';
        };
      in
      with pkgs; [
        git
        npins
        nil
        cachix
        nix-clean
        wasm-pack
        wasm-bindgen-cli_0_2_114 # wasm-bindgen-cli must match the version of wasm-bindgen
        binaryen
        miniserve
      ];
    shellHook = ''
      echo "🦊 Running example shellHook..."
      echo "🦊 Updating pins..."
      npins upgrade
      npins update
      if [ ! -d .git ]; then
        echo "🦊 Initializing git repository..."
        git init .
      fi
      echo "🦊 Formatting code..."
      treefmt
      echo "🦊 Building and serving the wasm-pack pkg to localhost:8080..."
      wasm-pack build --target web
      miniserve . --index "index.html" -p 8080
    '';
  };
}
