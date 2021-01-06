# fenix

Fenix provides the `minimal`, `default`, `complete`, and [`latest`](#the-latest-profile) [profile](https://rust-lang.github.io/rustup/concepts/profiles.html) of rust nightly toolchains, nightly version of [rust analyzer](https://rust-analyzer.github.io) and [its vscode extension](https://marketplace.visualstudio.com/items?itemName=matklad.rust-analyzer) with all components.
It intends to be an alternative to [rustup](https://rustup.rs) and the rust overlay provided by [nixpkgs-mozilla](https://github.com/mozilla/nixpkgs-mozilla).

Binary cache is available for x86_64-linux on [cachix](https://app.cachix.org/cache/fenix)

```sh
cachix use fenix
```


## Supported platforms

| platform | target |
-|-
aarch64-linux | aarch64-unknown-linux-gnu
i686-linux | i686-unknown-linux-gnu
x86_64-darwin | x86_64-apple-darwin
x86_64-linux | x86_64-unknown-linux-gnu


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


## The `latest` profile

The `latest` profile is a custom profile that contains all the components from the `complete` profile but not from necessarily the same date.
Components from this profile are more bleeding edge, but there is also a larger chance of incompatibility.


## Example: building with [naersk](https://github.com/nmattia/naersk)

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
