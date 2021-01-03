# fenix

Rust nightly toolchains for nix.
Fenix provides the minimal, default and complete profile of rust nightly toolchains with all components.
It intends to be an alternative to [rustup](https://rustup.rs) and the rust overlay provided by [nixpkgs-mozilla](https://github.com/mozilla/nixpkgs-mozilla).


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
    # fenix.x86_64-linux.default.rustc

    ## as an overlay (in your nixos configuration)
    # nixpkgs.overlays = [ fenix.overlay ];
    # environment.systemPackages = builtins.attrValues pkgs.rust-nightly.default;
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
  environment.systemPackages = builtins.attrValues pkgs.rust-nightly.default;
}
```

As a set of packages
```nix
{ callPackage }:

let
  fenix = callPackage "${fetchTarball https://github.com/figsoda/fenix/archive/main.tar.gz}/packages.nix" { };
in fenix.default.rustc
```


## Example: building with naersk

```nix
# flake.nix
{
  inputs = {
    fenix = {
      url = "github:figsoda/fenix";
      inputs = {
        flake-utils.follows = "flake-utils";
        nixpkgs.follows = "nixpkgs";
      };
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
