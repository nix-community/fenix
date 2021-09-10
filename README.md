# fenix

Fenix provides the `minimal`, `default`, and `complete` [profile](https://rust-lang.github.io/rustup/concepts/profiles.html) of rust toolchains, [`latest`](#latest) profile of nightly toolchains, nightly version of [rust analyzer](https://rust-analyzer.github.io) and [its vscode extension](https://marketplace.visualstudio.com/items?itemName=matklad.rust-analyzer).
It aims to be a replacement for [rustup](https://rustup.rs) and the rust overlay provided by [nixpkgs-mozilla](https://github.com/mozilla/nixpkgs-mozilla).

Binary cache is available for `x86_64-darwin` and `x86_64-linux` on [cachix](https://nix-community.cachix.org/)

```sh
cachix use nix-community
```

- [Usage](#usage)
- [Supported platforms and targets](#supported-platforms-and-targets)
- [Examples](#examples)


## Usage

<details>
  <summary>As a flake (recommended)</summary>

  ```nix
  {
    inputs = {
      fenix = {
        url = "github:nix-community/fenix";
        inputs.nixpkgs.follows = "nixpkgs";
      };
      nixpkgs.url = "nixpkgs/nixos-unstable";
    };

    outputs = { self, fenix, nixpkgs }: {
      defaultPackage.x86_64-linux = fenix.packages.x86_64-linux.minimal.toolchain;
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = x86_64-linux;
        modules = [
          ({ pkgs, ... }: {
            nixpkgs.overlays = [ fenix.overlay ];
            environment.systemPackages = with pkgs; [
              (fenix.complete.withComponents [
                "cargo"
                "clippy"
                "rust-src"
                "rustc"
                "rustfmt"
              ])
              rust-analyzer-nightly
            ];
          })
        ];
      };
    };
  }
  ```
</details>

<details>
  <summary>As a set of packages</summary>

  ```nix
  let
    fenix = import
      (fetchTarball "https://github.com/nix-community/fenix/archive/main.tar.gz")
      { };
  in fenix.minimal.toolchain
  ```
</details>

<details>
  <summary>As an overlay</summary>

  ```nix
  # configuration.nix
  { pkgs, ... }: {
    nixpkgs.overlays = [
      (import "${
          fetchTarball
          "https://github.com/nix-community/fenix/archive/main.tar.gz"
        }/overlay.nix")
    ];
    environment.systemPackages = with pkgs; [
      (fenix.complete.withComponents [
        "cargo"
        "clippy"
        "rust-src"
        "rustc"
        "rustfmt"
      ])
      rust-analyzer-nightly
    ];
  }
  ```
</details>

Following is a list of outputs, examples are prefixed with:

  - `with fenix.packages.<system>;` (flakes), or
  - `with import (fetchTarball "https://github.com/nix-community/fenix/archive/main.tar.gz") { };`

<a name="toolchain" />

Some outputs are toolchains, a rust toolchain in fenix is structured like this:

```nix
{
  # components
  cargo = <derivation>;
  rustc = <derivation>; # rustc with rust-std
  rustc-unwrapped = <derivation>; # rustc without rust-std, same as rustc.unwrapped
  rustfmt = <derivation>; # alias to rustfmt-preview
  # ...

  # derivation with all the components
  toolchain = <derivation>;

  # not available in nightly toolchains
  # derivation with all the components from a profile
  minimalToolchain = <derivation>;
  defaultToolchain = <derivation>;
  completeToolchain = <derivation>;

  # wtihComponents : [string] -> derivation
  # creates a derivation with the given list of components from the toolchain
  withComponents = <function>;
}
```


<details>
  <summary><code>combine : [derivation] -> derivation</code></summary>

  Combines a list of components into a derivation. If the components are from the same toolchain, use `withComponents` instead.

  ```nix
  combine [
    minimal.rustc
    minimal.cargo
    targets.wasm32-unknown-unknown.latest.rust-std
  ]
  ```
</details>

<details>
  <summary><code>fromManifest : attrs -> <a href="#toolchain">toolchain</a></code></summary>

  Creates a [toolchain](#toolchain) from a rustup manifest

  ```nix
  fromManifest (fromTOML (builtins.readFile ./channel-rust-nightly.toml))
  ```
</details>

<details>
  <summary><code>fromManifestFile : path -> <a href="#toolchain">toolchain</a></code></summary>

  Creates a [toolchain](#toolchain) from a rustup manifest file

  ```nix
  fromManifestFile ./channel-rust-nightly.toml
  ```
</details>

<details>
  <summary><code>toolchainOf : attrs -> <a href="#toolchain">toolchain</a></code></summary>

  Creates [toolchain](#toolchain) from given arguments:

  argument | default | description
  -|-|-
  root | `"https://static.rust-lang.org/dist"` | root url from downloading manifest, usually left as default
  channel | `"nightly"` | rust channel, one of `"stable"`, `"beta"`, `"nightly"`, and version number
  date | `null` | date of the toolchain, latest if unset
  sha256 | `null` | sha256 of the manifest, required in pure evaluation mode, set to `lib.fakeSha256` to get the actual sha256 from the error message

  ```nix
  toolchainOf {
    channel = "beta";
    date = "2021-08-29";
    sha256 = "0dkmjil9avba6l0l9apmgwa8d0h4f8jzgxkq3gvn8d2xc68ks5a5";
  }
  ```
</details>

<details>
  <summary><code>fromToolchainFile : attrs -> <a href="#toolchain">toolchain</a></code></summary>

  Creates a [toolchain](#toolchain) from a [rust toolchain file](https://rust-lang.github.io/rustup/overrides.html#the-toolchain-file), accepts the following arguments:

  argument | description
  -|-
  file | path to the rust toolchain file, usually either `./rust-toolchain` or `./rust-toolchain.toml`, conflicts with `dir`
  dir | path to the directory that has `rust-toolchain` or `rust-toolchain.toml`, conflicts with `file`
  sha256 | sha256 of the manifest, required in pure evalution mode, set to `lib.fakeSha256` to get the actual sha256 from the error message

  ```nix
  fromToolchainFile {
    file = ./rust-toolchain.toml;
    sha256 = lib.fakeSha256;
  }
  ```

  ```nix
  fromToolchainFile { dir = ./.; }
  ```
</details>

<details>
  <summary><code>stable : <a href="#toolchain">toolchain</a></code></summary>

  The stable [toolchain](#toolchain)
</details>

<details>
  <summary><code>beta : <a href="#toolchain">toolchain</a></code></summary>

  The beta [toolchain](#toolchain)
</details>

<details>
  <summary><code>minimal : <a href="#toolchain">toolchain</a></code></summary>

  The minimal profile of the nightly [toolchain](#toolchain)
</details>

<details>
  <summary><code>default : <a href="#toolchain">toolchain</a></code></summary>

  The default profile of the nightly [toolchain](#toolchain), sometimes lags behind the `minimal` profile
</details>

<details>
  <summary><code>complete : <a href="#toolchain">toolchain</a></code></summary>

  The complete profile of the nightly [toolchain](#toolchain), usually lags behind the `minimal` and `default` profile
</details>

<a name="latest" />
<details>
  <summary><code>latest : <a href="#toolchain">toolchain</a></code></summary>

  A custom [toolchain](#toolchain) that contains all the components from the `complete` profile but not from necessarily the same date.
  Unlike the `complete` profile, you get the latest version of the components, but risks a larger chance of incompatibility.
</details>

<details>
  <summary><code>targets.${target}.* : <a href="#toolchain">toolchain</a></code></summary>

  [Toolchain](#toolchain)s for [supported targets](#supported-platforms-and-targets), everything mentioned above except for `combine` is supported

  ```nix
  targets.wasm32-unknown-unknown.latest.rust-std
  ```
</details>

<details>
  <summary><code>rust-analyzer : derivation</code></summary>

  Nightly version of `rust-analyzer`, also available with overlay as `rust-analyzer-nightly`

  ```nix
  # configuration.nix with overlay
  { pkgs, ... }: {
    environment.systemPackages = with pkgs; [ rust-analyzer-nightly ];
  }
  ```
</details>

<details>
  <summary><code>rust-analyzer-vscode-extension : derivation</code></summary>

  Nightly version of `vscode-extensions.matklad.rust-analyzer`, also available with overlay as `vscode-extensions.matklad.rust-analyzer-nightly`

  ```nix
  # with overlay
  with pkgs; vscode-with-extensions.override {
    vscodeExtensions = [
      vscode-extensions.matklad.rust-analyzer-nightly
    ];
  }
  ```
</details>


## Supported platforms and targets

| platform | target |
-|-
aarch64-darwin | aarch64-apple-darwin
aarch64-linux | aarch64-unknown-linux-gnu
i686-linux | i686-unknown-linux-gnu
x86_64-darwin | x86_64-apple-darwin
x86_64-linux | x86_64-unknown-linux-gnu

<details>
  <summary>
    only rust-std (for cross compiling)
  </summary>

  - aarch64-apple-darwin
  - aarch64-apple-ios
  - aarch64-linux-android
  - aarch64-pc-windows-msvc
  - aarch64-unknown-fuchsia
  - aarch64-unknown-linux-musl
  - arm-linux-androideabi
  - arm-unknown-linux-gnueabi
  - arm-unknown-linux-gnueabihf
  - arm-unknown-linux-musleabi
  - arm-unknown-linux-musleabihf
  - armv5te-unknown-linux-gnueabi
  - armv7-linux-androideabi
  - armv7-unknown-linux-gnueabihf
  - armv7-unknown-linux-musleabihf
  - asmjs-unknown-emscripten
  - i586-pc-windows-msvc
  - i586-unknown-linux-gnu
  - i586-unknown-linux-musl
  - i686-linux-android
  - i686-pc-windows-gnu
  - i686-pc-windows-msvc
  - i686-unknown-freebsd
  - i686-unknown-linux-musl
  - mips-unknown-linux-gnu
  - mips-unknown-linux-musl
  - mips64-unknown-linux-gnuabi64
  - mips64el-unknown-linux-gnuabi64
  - mipsel-unknown-linux-gnu
  - mipsel-unknown-linux-musl
  - powerpc-unknown-linux-gnu
  - powerpc64-unknown-linux-gnu
  - powerpc64le-unknown-linux-gnu
  - s390x-unknown-linux-gnu
  - sparc64-unknown-linux-gnu
  - sparcv9-sun-solaris
  - wasm32-unknown-emscripten
  - wasm32-unknown-unknown
  - x86_64-apple-ios
  - x86_64-linux-android
  - x86_64-pc-windows-gnu
  - x86_64-pc-windows-msvc
  - x86_64-rumprun-netbsd
  - x86_64-sun-solaris
  - x86_64-unknown-freebsd
  - x86_64-unknown-fuchsia
  - x86_64-unknown-illumos
  - x86_64-unknown-linux-gnux32
  - x86_64-unknown-linux-musl
  - x86_64-unknown-netbsd
  - x86_64-unknown-redox
</details>


## Examples

Examples to build rust programs with [flake-utils](https://github.com/numtide/flake-utils) and [naersk](https://github.com/nmattia/naersk) (optional)

<details>
  <summary>building with makeRustPlatform</summary>

  ```nix
  {
    inputs = {
      fenix = {
        url = "github:nix-community/fenix";
        inputs.nixpkgs.follows = "nixpkgs";
      };
      flake-utils.url = "github:numtide/flake-utils";
      nixpkgs.url = "nixpkgs/nixos-unstable";
    };

    outputs = { self, fenix, flake-utils, nixpkgs }:
      flake-utils.lib.eachDefaultSystem (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          defaultPackage = (pkgs.makeRustPlatform {
            inherit (fenix.packages.${system}.minimal) cargo rustc;
          }).buildRustPackage {
            pname = "hello";
            version = "0.1.0";
            src = ./.;
            cargoSha256 = nixpkgs.lib.fakeSha256;
          };
       });
  }
  ```
</details>

<details>
  <summary>building with naersk</summary>

  ```nix
  {
    inputs = {
      fenix = {
        url = "github:nix-community/fenix";
        inputs.nixpkgs.follows = "nixpkgs";
      };
      flake-utils.url = "github:numtide/flake-utils";
      naersk = {
        url = "github:nmattia/naersk";
        inputs.nixpkgs.follows = "nixpkgs";
      };
      nixpkgs.url = "nixpkgs/nixos-unstable";
    };

    outputs = { self, fenix, flake-utils, naersk, nixpkgs }:
      flake-utils.lib.eachDefaultSystem (system: {
        defaultPackage = (naersk.lib.${system}.override {
          inherit (fenix.packages.${system}.minimal) cargo rustc;
        }).buildPackage { src = ./.; };
      });
  }
  ```
</details>

<details>
  <summary>cross compiling with naersk</summary>

  ```nix
  {
    inputs = {
      fenix = {
        url = "github:nix-community/fenix";
        inputs.nixpkgs.follows = "nixpkgs";
      };
      flake-utils.url = "github:numtide/flake-utils";
      naersk = {
        url = "github:nmattia/naersk";
        inputs.nixpkgs.follows = "nixpkgs";
      };
      nixpkgs.url = "nixpkgs/nixos-unstable";
    };

    outputs = { self, fenix, flake-utils, naersk, nixpkgs }:
      flake-utils.lib.eachDefaultSystem (system: {
        defaultPackage = let
          pkgs = nixpkgs.legacyPackages.${system};
          target = "aarch64-unknown-linux-gnu";
          toolchain = with fenix.packages.${system};
            combine [
              minimal.rustc
              minimal.cargo
              targets.${target}.latest.rust-std
            ];
        in (naersk.lib.${system}.override {
          cargo = toolchain;
          rustc = toolchain;
        }).buildPackage {
          src = ./.;
          CARGO_BUILD_TARGET = target;
          CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER =
            "${pkgs.pkgsCross.aarch64-multiplatform.stdenv.cc}/bin/${target}-gcc";
        };
      });
  }
  ```
</details>
