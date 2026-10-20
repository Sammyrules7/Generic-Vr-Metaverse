{ pkgs, mkImageRoot, mkResolvedImage, ... }:

mkResolvedImage {
  name = "vr-platform-cleanup-ci";
  root = mkImageRoot "vr-platform-cleanup-ci-root" (with pkgs; [
    bashInteractive
    cacert
    coreutils
    gnused
    gnutar
    s5cmd
  ]);
  env = [ "PATH=/bin" ];
}
