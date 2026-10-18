# Templates

## With Flakes

A list of available flake templates can be found in the [`flakes`](./flakes) directory.

```sh
nix flake init -t github:nix-community/fenix#<TEMPLATE>`
```

## Without Flakes

Non-flake templates are located in the [`templates`](./.) directory.

```sh
curl -L https://github.com/nix-community/fenix/archive/main.tar.gz | tar xz --strip-components=2 fenix-main/templates/<TEMPLATE>/
```
