{ pkgs, baseTools, mkImageRoot, mkResolvedImage }:

let
  androidSdk = (pkgs.androidenv.composeAndroidPackages {
    # Match the Android export preset's target platform so gradle never has
    # to install SDK components into the read-only Nix store at build time.
    platformVersions = [ "36" ];
    buildToolsVersions = [ "36.1.0" ];
    includeCmake = false;
    includeNDK = true;
    ndkVersions = [ "28.1.13356709" ];
  }).androidsdk;
in
mkResolvedImage {
  name = "vr-platform-godot-ci";
  root = mkImageRoot "vr-platform-godot-ci-root" (baseTools ++ (with pkgs; [
    androidSdk
    butler
    fontconfig
    godot_4
    godot-export-templates-bin
    jdk17
    # A real rendering device is needed by Godot's shader baker.
    mesa
    vulkan-loader
    xvfb-run
  ]));
  env = [
    "ANDROID_HOME=${androidSdk}/libexec/android-sdk"
    "ANDROID_SDK_ROOT=${androidSdk}/libexec/android-sdk"
    "FONTCONFIG_FILE=${pkgs.fontconfig.out}/etc/fonts/fonts.conf"
    # CPU Vulkan makes shader baking available without a GPU device mount.
    "VK_DRIVER_FILES=${pkgs.mesa}/share/vulkan/icd.d/lvp_icd.x86_64.json"
    "JAVA_HOME=${pkgs.jdk17}"
    "PATH=/bin"
    "XDG_CONFIG_HOME=/tmp/godot-config"
    "XDG_DATA_HOME=/share"
  ];
}
