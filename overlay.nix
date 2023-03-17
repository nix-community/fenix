final: prev:

let fenix = prev.callPackage ./. { }; in

{
  inherit fenix;
  rust-analyzer-nightly = fenix.rust-analyzer;
  vscode-extensions = prev.vscode-extensions // {
    matklad = prev.vscode-extensions.matklad // {
      rust-analyzer-nightly = fenix.rust-analyzer-vscode-extension;
    };
    rust-lang = prev.vscode-extensions.rust-lang // {
      rust-analyzer-nightly = fenix.rust-analyzer-vscode-extension;
    };
  };
}
