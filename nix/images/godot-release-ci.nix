{ pkgs, baseTools, mkImageRoot, mkResolvedImage }:

let
  androidSdk = (pkgs.androidenv.composeAndroidPackages {
    platformVersions = [ "35" ];
    buildToolsVersions = [ "35.0.1" ];
    includeCmake = false;
    includeNDK = true;
    ndkVersions = [ "28.1.13356709" ];
  }).androidsdk;
in
mkResolvedImage {
  name = "vr-platform-godot-ci";
  root = mkImageRoot "vr-platform-godot-ci-root" (baseTools ++ (with pkgs; [
    androidSdk
    awscli2
    fontconfig
    godot_4
    godot-export-templates-bin
    jdk17
    wrangler
  ]));
  env = [
    "ANDROID_HOME=${androidSdk}/libexec/android-sdk"
    "ANDROID_SDK_ROOT=${androidSdk}/libexec/android-sdk"
    "GODOT4_CONFIG_DIR=/tmp/godot-config"
    "GODOT4_DATA_DIR=/share/godot"
    "JAVA_HOME=${pkgs.jdk17}"
    "PATH=/bin"
  ];
}
