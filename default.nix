_: super:
let fenix = import ./packages.nix;
in {
  rust-nightly = { inherit (fenix) minimal default complete latest; };
  rust-analyzer-nightly = fenix.rust-analyzer;
  vscode-extensions = super.vscode-extensions // {
    matklad = super.vscode-extensions.matklad // {
      rust-analyzer-nightly = fenix.rust-analyzer-vscode-extension;
    };
  };
}
