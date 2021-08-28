f: final: prev:
let fenix = f prev;
in {
  inherit fenix;
  rust-analyzer-nightly = fenix.rust-analyzer;
  vscode-extensions = prev.vscode-extensions // {
    matklad = prev.vscode-extensions.matklad // {
      rust-analyzer-nightly = fenix.rust-analyzer-vscode-extension;
    };
  };
}
