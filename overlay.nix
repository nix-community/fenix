_: super:

let fenix = super.callPackage ./. { }; in

{
  inherit fenix;
  rust-analyzer-nightly = fenix.rust-analyzer;
  vscode-extensions = super.vscode-extensions // {
    matklad = super.vscode-extensions.matklad // {
      rust-analyzer-nightly = fenix.rust-analyzer-vscode-extension;
    };
    rust-lang = super.vscode-extensions.rust-lang // {
      rust-analyzer-nightly = fenix.rust-analyzer-vscode-extension;
    };
  };
}
