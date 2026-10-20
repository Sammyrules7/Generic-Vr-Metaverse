{ pkgs, baseTools, mkImageRoot, mkResolvedImage }:

mkResolvedImage {
  name = "vr-platform-web-publish-ci";
  root = mkImageRoot "vr-platform-web-publish-ci-root" (baseTools ++ (with pkgs; [
    s5cmd
    wrangler
  ]));
  env = [ "PATH=/bin" ];
}
