{ system ? builtins.currentSystem, flakeLock ? import ./flake.lock.nix
, nixpkgs ? import flakeLock.nixpkgs {
  inherit system;
  config = { };
  overlays = [ ];
}, lib ? nixpkgs.lib, rust-analyzer-src ? flakeLock.rust-analyzer-src }:
with builtins;
with lib;
let
  systemToRust = {
    aarch64-darwin = "aarch64-apple-darwin";
    aarch64-linux = "aarch64-unknown-linux-gnu";
    i686-linux = "i686-unknown-linux-gnu";
    x86_64-darwin = "x86_64-apple-darwin";
    x86_64-linux = "x86_64-unknown-linux-gnu";
  };

  v = systemToRust.${system} or (throw
    "system '${system}' is unsupported by fenix");

  mkToolchain = nixpkgs.callPackage ./lib/mk-toolchain.nix { };

  nightlyToolchains =
    mapAttrs (_: mapAttrs (profile: mkToolchain "rust-nightly-${profile}"))
    (fromJSON (readFile ./data/nightly.json));

  fromManifest' = target: name: manifest:
    let
      toolchain = mkToolchain name {
        inherit (manifest) date;
        components = lib.mapAttrs (_: src: {
          inherit (src) url;
          sha256 = src.hash;
        }) (filterAttrs (_: src: src ? available && src.available) (mapAttrs
          (component: pkg:
            if pkg.target ? "*" then
              pkg.target."*"
            else if pkg.target ? ${target} then
              pkg.target.${target}
            else
              null) manifest.pkg));
      };
    in toolchain // mapAttrs' (k: v:
      nameValuePair "${k}Toolchain" (toolchain.withComponents
        (filter (component: toolchain ? ${component}) v))) manifest.profiles;

  fromManifestFile' = target: name: file:
    fromManifest' target name (fromTOML (readFile file));

  toolchainOf' = target:
    { root ? "https://static.rust-lang.org/dist", channel ? "nightly", date
    , sha256 }:
    fromManifestFile' target "rust-${channel}" (fetchurl {
      inherit sha256;
      url = "${root}/${date}/channel-rust-${channel}.toml";
    });

  mkToolchains = channel:
    let manifest = fromTOML (readFile (./data + "/${channel}.toml"));
    in mapAttrs (target: _: {
      ${channel} = fromManifest' target "rust-${channel}" manifest;
    }) manifest.pkg.rust-std.target;

  rust-analyzer-rev = substring 0 7
    (fromJSON (readFile ./flake.lock)).nodes.rust-analyzer-src.locked.rev;
in nightlyToolchains.${v} // rec {
  combine = nixpkgs.callPackage ./lib/combine.nix { } "rust-mixed";

  fromManifest = fromManifest' v "rust";

  fromManifestFile = fromManifestFile' v "rust";

  toolchainOf = toolchainOf' v;

  stable = fromManifestFile' v "rust-stable" ./data/stable.toml;

  beta = fromManifestFile' v "rust-beta" ./data/beta.toml;

  targets = let
    collectedTargets = zipAttrsWith (_: foldl (x: y: x // y) { }) [
      (mkToolchains "stable")
      (mkToolchains "beta")
      nightlyToolchains
    ];
  in mapAttrs (target: v: v // { toolchainOf = toolchainOf' target; })
  collectedTargets;

  rust-analyzer = (nixpkgs.makeRustPlatform {
    inherit (nightlyToolchains.${v}.minimal) cargo rustc;
  }).buildRustPackage {
    pname = "rust-analyzer-nightly";
    version = rust-analyzer-rev;
    src = rust-analyzer-src;
    cargoLock.lockFile = rust-analyzer-src + "/Cargo.lock";
    cargoBuildFlags = [ "-p" "rust-analyzer" ];
    buildInputs = with nixpkgs;
      optionals stdenv.isDarwin [
        darwin.apple_sdk.frameworks.CoreServices
        libiconv
      ];
    doCheck = false;
    CARGO_INCREMENTAL = "0";
    RUST_ANALYZER_REV = rust-analyzer-rev;
  };

  rust-analyzer-vscode-extension = let
    setDefault = k: v: ''
      .contributes.configuration.properties."rust-analyzer.${k}".default = "${v}"
    '';
  in nixpkgs.vscode-utils.buildVscodeExtension {
    name = "rust-analyzer-${rust-analyzer-rev}";
    src = ./data/rust-analyzer-vsix.zip;
    vscodeExtUniqueId = "matklad.rust-analyzer";
    buildInputs = with nixpkgs; [ jq moreutils ];
    patchPhase = ''
      jq -e '
        ${setDefault "server.path" "${rust-analyzer}/bin/rust-analyzer"}
        | ${setDefault "updates.channel" "nightly"}
      ' package.json | sponge package.json
    '';
  };
}
