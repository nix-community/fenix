_: _:
let fenix = import ./packages.nix;
in {
  rust-nightly = { inherit (fenix) minimal default complete; };
  rust-analyzer-nightly = fenix.rust-analyzer;
}
