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

  formatDate = date:
    let
      year = substring 0 4 date;
      month = substring 4 2 date;
      day = substring 6 2 date;
    in
    "${year}-${month}-${day}";
in

{ system ? currentSystem
, pkgs ? import (getFlake "nixpkgs") { localSystem = { inherit system; }; }
, lib ? pkgs.lib
, rust-analyzer-src ? getFlake "rust-analyzer-src"
, rust-analyzer-rev ? rust-analyzer-src.rev or "0000000000000000000000000000000000000000"
, rust-analyzer-date ? formatDate (rust-analyzer-src.lastModifiedDate or "00000000000000")
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

  default_dist_server = "https://static.rust-lang.org/dist";

  fromManifest' = target: root: suffix: manifest:
    let
      toolchain = mkToolchain suffix {
        inherit (manifest) date;
        components = mapAttrs
          (_: src:
            let
              # Either use xz_url/xz_hash if xz_url is present, or url/hash
              # otherwise.
              url = if src ? xz_url then src.xz_url else src.url;
              hash = if src ? xz_url then src.xz_hash else src.hash;
            in
            { url = builtins.replaceStrings [ default_dist_server ] [ root ] url; sha256 = hash; })
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

  fromManifestFile' = target: root: name: file:
    fromManifest' target root name (importTOML file);

  toolchainOf' = target:
    { root ? default_dist_server
    , channel ? "nightly"
    , date ? null
    , sha256 ? null
    }:
    let
      url = "${root}${optionalString (date != null) "/${date}"}/channel-rust-${channel}.toml";
    in
    fromManifestFile' target root "-${channel}" (if (sha256 == null) then
      builtins.fetchurl url
    else
      pkgs.fetchurl { inherit url sha256; });

  fromToolchainName' = target: root: name: sha256:
    mapNullable
      (matches:
        let target' = elemAt matches 5; in
        toolchainOf' (if target' == null then target else target') {
          inherit root sha256;
          channel = elemAt matches 0;
          date = elemAt matches 3;
        })
      (match
        "^(stable|beta|nightly|[[:digit:]]+\.[[:digit:]]+(\.[[:digit:]]+(-beta\.[[:digit:]]+)?)?)(-([[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}))?(-([-[:alnum:]]+))?\n?$"
        name);

  fromToolchainFile' = target:
    { root ? default_dist_server, file ? null, dir ? null, sha256 ? null }:
    let
      text = readFile (if file == null && dir != null then
        findFirst pathIsRegularFile
          (throw "No rust toolchain file found in ${dir}")
          [ (dir + "/rust-toolchain") (dir + "/rust-toolchain.toml") ]
      else if file != null && dir == null then
        file
      else
        throw "One and only one of `file` and `dir` should be specified");
      toolchain = fromToolchainName' target root text sha256;
    in
    if toolchain == null then
      let t = (fromTOML text).toolchain; in
      if t ? path then
        throw "fenix doesn't support toolchain.path"
      else
        let toolchain = fromToolchainName' target root t.channel sha256; in
        combine' "rust-${t.channel}" (attrVals
          (filter (component: toolchain ? ${component}) (unique
            (toolchain.manifest.profiles.${t.profile or "default"}
              ++ t.components or [ ])))
          toolchain ++ map
          (target:
            (fromManifest' target root "-${t.channel}" toolchain.manifest).rust-std)
          (t.targets or [ ]))
    else
      toolchain.defaultToolchain;

  mkToolchains = channel:
    let manifest = importJSON (./data + "/${channel}.json"); in
    mapAttrs
      (target: _: { ${channel} = fromManifest' target default_dist_server "-${channel}" manifest; })
      manifest.pkg.rust-std.target;
in

nightlyToolchains.${v} // rec {
  combine = combine' "rust-mixed";

  fromManifest = fromManifest' v default_dist_server "";

  fromManifestFile = fromManifestFile' v default_dist_server "";

  toolchainOf = toolchainOf' v;

  fromToolchainFile = fromToolchainFile' v;

  fromToolchainName = { name, sha256 ? "" }: fromToolchainName' v default_dist_server name sha256;

  stable = fromManifest' v default_dist_server "-stable" (importJSON ./data/stable.json);

  beta = fromManifest' v default_dist_server "-beta" (importJSON ./data/beta.json);

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
          fromManifest = fromManifest' target default_dist_server "";
          fromManifestFile = fromManifestFile' target default_dist_server "";
          toolchainOf = toolchainOf' target;
          fromToolchainFile = fromToolchainFile' target;
          fromToolchainName = { name, sha256 ? "" }: fromToolchainName' target name sha256;
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
        libiconv
      ];
    doCheck = false;
    CARGO_INCREMENTAL = 0;

    # See rust-analyzer's https://github.com/rust-lang/rust-analyzer/blob/2025-08-25/crates/rust-analyzer/build.rs
    patchPhase = ''
      mkdir .git/
      echo nightly > .git/HEAD
    '';
    CFG_RELEASE_CHANNEL = "nightly";
    RA_COMMIT_HASH = rust-analyzer-rev;
    RA_COMMIT_SHORT_HASH = substring 0 7 rust-analyzer-rev;
    RA_COMMIT_DATE = rust-analyzer-date;
    # Value chosen to look like RA is from a nightly toolchain
    # Needs to be set explicitly to disable `POKE_RA_DEVS`
    # https://github.com/rust-lang/rust-analyzer/blob/2025-08-25/crates/rust-analyzer/src/version.rs#L39-L42
    # https://github.com/rust-lang/rust-analyzer/blob/2025-08-25/crates/rust-analyzer/build.rs#L9-L11
    # https://github.com/rust-lang/rust-analyzer/blob/f5e049d09dc17d0b61de2ec179b3607cf1e431b2/crates/rust-analyzer/src/lsp/utils.rs#L110
    CFG_RELEASE = "0.0.0-nightly";

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
      pname = "rust-analyzer";
      name = "rust-analyzer-${rust-analyzer-rev}";
      version = rust-analyzer-rev;
      src = ./data/rust-analyzer-vsix.zip;
      vscodeExtName = "rust-analyzer";
      vscodeExtPublisher = "The Rust Programming Language";
      vscodeExtUniqueId = "rust-lang.rust-analyzer";
      nativeBuildInputs = with pkgs; [ jq moreutils unzip ];
      postPatch = ''
        jq -e '
          ${setDefault "server.path" "${rust-analyzer}/bin/rust-analyzer"}
        ' package.json | sponge package.json
      '';
      meta.maintainers = with maintainers; [ figsoda ];
    };
}
