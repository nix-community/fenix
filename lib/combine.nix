symlinkJoin: name: paths:
symlinkJoin {
  inherit name paths;
  postBuild = "cp --remove-destination $(realpath $out/bin/*) $out/bin";
}
