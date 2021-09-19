let
  inherit (builtins)
    currentSystem elemAt filter fromJSON mapAttrs match readFile substring;

  nodes = (fromJSON (readFile ./flake.lock)).nodes;

  getFlake = name:
    with nodes.${name}.locked;
    fetchTarball {
      url = "https://github.com/${owner}/${repo}/archive/${rev}.tar.gz";
      sha256 = narHash;
    };

in { system ? currentSystem
, pkgs ? import (getFlake "nixpkgs") { inherit system; }, lib ? pkgs.lib
, rust-analyzer-src ? getFlake "rust-analyzer-src", rust-analyzer-rev ?
  rust-analyzer-src.shortRev or (substring 0 7
    nodes.rust-analyzer-src.locked.rev) }:

let
  inherit (lib)
    attrVals filterAttrs foldl mapAttrs' mapNullable nameValuePair
    optionalString optionals pathIsRegularFile unique zipAttrsWith;

  v = pkgs.rust.toRustTarget pkgs.stdenv.buildPlatform;

  combine' = pkgs.callPackage ./lib/combine.nix { };

  mkToolchain = pkgs.callPackage ./lib/mk-toolchain.nix { };

  nightlyToolchains =
    mapAttrs (_: mapAttrs (profile: mkToolchain "-nightly-${profile}"))
    (fromJSON (readFile ./data/nightly.json));

  fromManifest' = target: suffix: manifest:
    let
      toolchain = mkToolchain suffix {
        inherit (manifest) date;
        components = mapAttrs (_: src: {
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
        (filter (component: toolchain ? ${component}) v))) manifest.profiles
    // {
      inherit manifest;
    };

  fromManifestFile' = target: name: file:
    fromManifest' target name (fromTOML (readFile file));

  toolchainOf' = target:
    { root ? "https://static.rust-lang.org/dist", channel ? "nightly"
    , date ? null, sha256 ? null }:
    let
      url = "${root}${
          optionalString (date != null) "/${date}"
        }/channel-rust-${channel}.toml";
    in fromManifestFile' target "-${channel}" (if (sha256 == null) then
      builtins.fetchurl url
    else
      pkgs.fetchurl { inherit url sha256; });

  fromToolchainName = target: name: sha256:
    mapNullable (matches:
      let target' = elemAt matches 4;
      in toolchainOf' (if target' == null then target else target') {
        inherit sha256;
        channel = elemAt matches 0;
        date = elemAt matches 2;
      }) (match ''
        ^(stable|beta|nightly|[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+)(-([[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}))?(-([-[:alnum:]]+))?
        ?$'' name);

  fromToolchainFile' = target:
    { file ? null, dir ? null, sha256 ? null }:
    let
      text = readFile (if file == null && dir != null then
        let
          old = dir + "/rust-toolchain";
          new = dir + "/rust-toolchain.toml";
        in (if pathIsRegularFile old then
          old
        else if pathIsRegularFile new then
          new
        else
          throw "No rust toolchain file found in ${dir}")
      else if file != null && dir == null then
        file
      else
        throw "One and only one of `file` and `dir` should be specified");
      toolchain = fromToolchainName target text sha256;
    in if toolchain == null then
      let t = (fromTOML text).toolchain;
      in if t ? path then
        throw "fenix doesn't support toolchain.path"
      else
        let toolchain = fromToolchainName target t.channel sha256;
        in combine' "rust-${t.channel}" (attrVals
          (filter (component: toolchain ? ${component}) (unique
            (toolchain.manifest.profiles.${t.profile or "default"}
              ++ t.components or [ ]))) toolchain ++ map (target:
                (fromManifest' target "-${t.channel}"
                  toolchain.manifest).rust-std) (t.targets or [ ]))
    else
      toolchain.defaultToolchain;

  mkToolchains = channel:
    let manifest = fromTOML (readFile (./data + "/${channel}.toml"));
    in mapAttrs
    (target: _: { ${channel} = fromManifest' target "-${channel}" manifest; })
    manifest.pkg.rust-std.target;

in nightlyToolchains.${v} // rec {
  combine = combine' "rust-mixed";

  fromManifest = fromManifest' v "";

  fromManifestFile = fromManifestFile' v "";

  toolchainOf = toolchainOf' v;

  fromToolchainFile = fromToolchainFile' v;

  stable = fromManifestFile' v "-stable" ./data/stable.toml;

  beta = fromManifestFile' v "-beta" ./data/beta.toml;

  targets = let
    collectedTargets = zipAttrsWith (_: foldl (x: y: x // y) { }) [
      (mkToolchains "stable")
      (mkToolchains "beta")
      nightlyToolchains
    ];
  in mapAttrs (target: v:
    v // {
      fromManifest = fromManifest' target "";
      fromManifestFile = fromManifestFile' target "";
      toolchainOf = toolchainOf' target;
      fromToolchainFile = fromToolchainFile' target;
    }) collectedTargets;

  rust-analyzer = (pkgs.makeRustPlatform {
    inherit (nightlyToolchains.${v}.minimal) cargo rustc;
  }).buildRustPackage {
    pname = "rust-analyzer-nightly";
    version = rust-analyzer-rev;
    src = rust-analyzer-src;
    cargoLock.lockFile = rust-analyzer-src + "/Cargo.lock";
    cargoBuildFlags = [ "-p" "rust-analyzer" ];
    buildInputs = with pkgs;
      optionals stdenv.isDarwin [
        darwin.apple_sdk.frameworks.CoreServices
        libiconv
      ];
    doCheck = false;
    CARGO_INCREMENTAL = "0";
    RUST_ANALYZER_REV = rust-analyzer-rev;
    meta.mainProgram = "rust-analyzer";
  };

  rust-analyzer-vscode-extension = let
    setDefault = k: v: ''
      .contributes.configuration.properties."rust-analyzer.${k}".default = "${v}"
    '';
  in pkgs.vscode-utils.buildVscodeExtension {
    name = "rust-analyzer-${rust-analyzer-rev}";
    src = ./data/rust-analyzer-vsix.zip;
    vscodeExtUniqueId = "matklad.rust-analyzer";
    buildInputs = with pkgs; [ jq moreutils ];
    patchPhase = ''
      jq -e '
        ${setDefault "server.path" "${rust-analyzer}/bin/rust-analyzer"}
        | ${setDefault "updates.channel" "nightly"}
      ' package.json | sponge package.json
    '';
  };
}
