let
  inherit (builtins)
    currentSystem elemAt filter fromJSON mapAttrs match readFile substring;

  getFlake = name:
    with (fromJSON (readFile ./flake.lock)).nodes.${name}.locked; {
      inherit rev;
      outPath = fetchTarball {
        url = "https://github.com/${owner}/${repo}/archive/${rev}.tar.gz";
        sha256 = narHash;
      };
    };
in

{ system ? currentSystem
, pkgs ? import (getFlake "nixpkgs") { localSystem = { inherit system; }; }
, lib ? pkgs.lib
, rust-analyzer-src ? getFlake "rust-analyzer-src"
, rust-analyzer-rev ? substring 0 7 (rust-analyzer-src.rev or "0000000")
}:

let
  inherit (lib)
    attrVals filterAttrs findFirst foldl importJSON importTOML maintainers
    mapAttrs' mapNullable nameValuePair optionalString optionals
    pathIsRegularFile unique zipAttrsWith;

  v = pkgs.stdenv.buildPlatform.rust.rustcTarget;

  combine' = pkgs.callPackage ./lib/combine.nix { };

  mkToolchain = pkgs.callPackage ./lib/mk-toolchain.nix { };

  nightlyToolchains = mapAttrs
    (_: mapAttrs (profile: mkToolchain "-nightly-${profile}"))
    (importJSON ./data/nightly.json);

  fromManifest' = target: suffix: manifest:
    let
      toolchain = mkToolchain suffix {
        inherit (manifest) date;
        components = mapAttrs
          (_: src: { inherit (src) url; sha256 = src.hash; })
          (filterAttrs (_: src: src ? available && src.available) (mapAttrs
            (_: pkg: pkg.target."*" or pkg.target.${target} or null)
            manifest.pkg));
      };
    in
    toolchain // mapAttrs'
      (k: v:
        nameValuePair "${k}Toolchain" (toolchain.withComponents
          (filter (component: toolchain ? ${component}) v)))
      manifest.profiles
    // {
      inherit manifest;
    };

  fromManifestFile' = target: name: file:
    fromManifest' target name (importTOML file);

  toolchainOf' = target:
    { root ? "https://static.rust-lang.org/dist"
    , channel ? "nightly"
    , date ? null
    , sha256 ? null
    }:
    let
      url = "${root}${optionalString (date != null) "/${date}"}/channel-rust-${channel}.toml";
    in
    fromManifestFile' target "-${channel}" (if (sha256 == null) then
      builtins.fetchurl url
    else
      pkgs.fetchurl { inherit url sha256; });

  fromToolchainName' = target: name: sha256:
    mapNullable
      (matches:
        let target' = elemAt matches 5; in
        toolchainOf' (if target' == null then target else target') {
          inherit sha256;
          channel = elemAt matches 0;
          date = elemAt matches 3;
        })
      (match
        "^(stable|beta|nightly|[[:digit:]]+\.[[:digit:]]+(\.[[:digit:]]+)?)(-([[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}))?(-([-[:alnum:]]+))?\n?$"
        name);

  fromToolchainFile' = target:
    { file ? null, dir ? null, sha256 ? null }:
    let
      text = readFile (if file == null && dir != null then
        findFirst pathIsRegularFile
          (throw "No rust toolchain file found in ${dir}")
          [ (dir + "/rust-toolchain") (dir + "/rust-toolchain.toml") ]
      else if file != null && dir == null then
        file
      else
        throw "One and only one of `file` and `dir` should be specified");
      toolchain = fromToolchainName' target text sha256;
    in
    if toolchain == null then
      let t = (fromTOML text).toolchain; in
      if t ? path then
        throw "fenix doesn't support toolchain.path"
      else
        let toolchain = fromToolchainName' target t.channel sha256; in
        combine' "rust-${t.channel}" (attrVals
          (filter (component: toolchain ? ${component}) (unique
            (toolchain.manifest.profiles.${t.profile or "default"}
              ++ t.components or [ ])))
          toolchain ++ map
          (target:
            (fromManifest' target "-${t.channel}" toolchain.manifest).rust-std)
          (t.targets or [ ]))
    else
      toolchain.defaultToolchain;

  mkToolchains = channel:
    let manifest = importJSON (./data + "/${channel}.json"); in
    mapAttrs
      (target: _: { ${channel} = fromManifest' target "-${channel}" manifest; })
      manifest.pkg.rust-std.target;
in

nightlyToolchains.${v} // rec {
  combine = combine' "rust-mixed";

  fromManifest = fromManifest' v "";

  fromManifestFile = fromManifestFile' v "";

  toolchainOf = toolchainOf' v;

  fromToolchainFile = fromToolchainFile' v;

  fromToolchainName = { name, sha256 ? "" }: fromToolchainName' v name sha256;

  stable = fromManifest' v "-stable" (importJSON ./data/stable.json);

  beta = fromManifest' v "-beta" (importJSON ./data/beta.json);

  targets =
    let
      collectedTargets = zipAttrsWith (_: foldl (x: y: x // y) { }) [
        (mkToolchains "stable")
        (mkToolchains "beta")
        nightlyToolchains
      ];
    in
    mapAttrs
      (target: v:
        v // {
          fromManifest = fromManifest' target "";
          fromManifestFile = fromManifestFile' target "";
          toolchainOf = toolchainOf' target;
          fromToolchainFile = fromToolchainFile' target;
        })
      collectedTargets;

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
    CARGO_INCREMENTAL = 0;
    # ensure `rust-analyzer` is built in release mode https://github.com/rust-lang/rust-analyzer/blob/8772b865c913afd1510f69649f238b0f31eace3d/crates/rust-analyzer/build.rs#L9
    CFG_RELEASE = 1;
    RUST_ANALYZER_REV = rust-analyzer-rev;
    meta = {
      maintainers = with maintainers; [ figsoda ];
      mainProgram = "rust-analyzer";
    };
  };

  rust-analyzer-vscode-extension =
    let
      setDefault = k: v: ''
        .contributes.configuration |= map(if .properties."rust-analyzer.${k}" != null then .properties."rust-analyzer.${k}".default = "${v}" end)
      '';
    in
    pkgs.vscode-utils.buildVscodeExtension {
      name = "rust-analyzer-${rust-analyzer-rev}";
      pname = "rust-analyzer";
      version = rust-analyzer-rev;
      src = ./data/rust-analyzer-vsix.zip;
      vscodeExtName = "rust-analyzer";
      vscodeExtPublisher = "The Rust Programming Language";
      vscodeExtUniqueId = "rust-lang.rust-analyzer";
      nativeBuildInputs = with pkgs; [ jq moreutils ];
      postPatch = ''
        jq -e '
          ${setDefault "server.path" "${rust-analyzer}/bin/rust-analyzer"}
        ' package.json | sponge package.json
      '';
      meta.maintainers = with maintainers; [ figsoda ];
    };
}
