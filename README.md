# fenix

Fenix provides the `minimal`, `default`, `complete`, and [`latest`](#the-latest-profile) [profile](https://rust-lang.github.io/rustup/concepts/profiles.html) of rust nightly toolchains, nightly version of [rust analyzer](https://rust-analyzer.github.io) and [its vscode extension](https://marketplace.visualstudio.com/items?itemName=matklad.rust-analyzer) with all components.
It intends to be an alternative to [rustup](https://rustup.rs) and the rust overlay provided by [nixpkgs-mozilla](https://github.com/mozilla/nixpkgs-mozilla).

Binary cache is available for x86_64-linux on [cachix](https://app.cachix.org/cache/fenix)

```sh
cachix use fenix
```

- [Usage](#usage)
- [Supported platforms and targets](#supported-platforms-and-targets)
- [The `latest` profile](#the-latest-profile)
- [Examples](#examples)


## Usage

As a flake (recommended)

```nix
# flake.nix
{
  inputs = {
    fenix = {
      url = "github:figsoda/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, fenix, nixpkgs }: {
    ## as a set of packages
    # fenix.x86_64-linux.default.toolchain
    # fenix.x86_64-linux.rust-analyzer
    # fenix.x86_64-linux.rust-analyzer-vscode-extension

    ## as an overlay (in your nixos configuration)
    # nixpkgs.overlays = [ fenix.overlay ];
    # environment.systemPackages = with pkgs; [
    #   (rust-nightly.latest.withComponents [
    #     "cargo"
    #     "clippy-preview"
    #     "rust-src"
    #     "rust-std"
    #     "rustc"
    #     "rustfmt-preview"
    #   ])
    #   (vscode-with-extensions.override {
    #     vscodeExtensions = [
    #       vscode-extensions.matklad.rust-analyzer-nightly
    #     ];
    #   })
    # ];
  };
}
```

As an overlay

```nix
# configuration.nix
{
  nixpkgs.overlays = [
    (import (fetchTarball
      https://github.com/figsoda/fenix/archive/main.tar.gz))
  ];
  environment.systemPackages = [ pkgs.rust-nightly.default.toolchain ];
}
```

As a set of packages
```nix
{ callPackage }:

let
  fenix = callPackage "${
      fetchTarball "https://github.com/figsoda/fenix/archive/main.tar.gz"
    }/packages.nix" { };
in fenix.default.rustc
```


## Supported platforms and targets

all profiles (minimal, default, complete, and latest)

| platform | target |
-|-
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


## The `latest` profile

The `latest` profile is a custom profile that contains all the components from the `complete` profile but not from necessarily the same date.
Components from this profile are more bleeding edge, but there is also a larger chance of incompatibility.


## Examples

Examples to build rust programs with [flake-utils](https://github.com/numtide/flake-utils) and [naersk](https://github.com/nmattia/naersk)

<details>
  <summary>building with makeRustPlatform</summary>

  ```nix
  # flake.nix
  {
    inputs = {
      fenix = {
        url = "github:figsoda/fenix";
        inputs.nixpkgs.follows = "nixpkgs";
      };
      flake-utils.url = "github:numtide/flake-utils";
      nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    };

    outputs = { self, fenix, flake-utils, nixpkgs }:
      flake-utils.lib.eachDefaultSystem (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in {
          defaultPackage = let
            toolchain = fenix.packages.${system}.minimal.toolchain.overrideAttrs
              (_: { meta.platforms = [ system ]; });
          in (pkgs.makeRustPlatform {
            cargo = toolchain;
            rustc = toolchain;
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
  # flake.nix
  {
    inputs = {
      fenix = {
        url = "github:figsoda/fenix";
        inputs.nixpkgs.follows = "nixpkgs";
      };
      flake-utils.url = "github:numtide/flake-utils";
      naersk = {
        url = "github:nmattia/naersk";
        inputs.nixpkgs.follows = "nixpkgs";
      };
      nixpkgs.url = "nixpkgs/nixpkgs-unstable";
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
  # flake.nix
  {
    inputs = {
      fenix = {
        url = "github:figsoda/fenix";
        inputs.nixpkgs.follows = "nixpkgs";
      };
      flake-utils.url = "github:numtide/flake-utils";
      naersk = {
        url = "github:nmattia/naersk";
        inputs.nixpkgs.follows = "nixpkgs";
      };
      nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    };

    outputs = { self, fenix, flake-utils, naersk, nixpkgs }:
      flake-utils.lib.eachDefaultSystem (system: {
        defaultPackage = let
          toolchain = with fenix.packages.${system};
            combine [
              minimal.rustc
              minimal.cargo
              targets.x86_64-unknown-linux-musl.latest.rust-std
            ];
        in (naersk.lib.${system}.override {
          cargo = toolchain;
          rustc = toolchain;
        }).buildPackage {
          src = ./.;
          CARGO_BUILD_TARGET = "x86_64-unknown-linux-musl";
        };
      });
  }
  ```
</details>
