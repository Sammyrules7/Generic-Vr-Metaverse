{
  description = "Generic VR Platform packages and nix-snapshotter images";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-snapshotter = {
      url = "github:pdtpartners/nix-snapshotter";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-snapshotter }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ nix-snapshotter.overlays.default ];
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };

      server = pkgs.buildGoModule {
        pname = "vr-platform-server";
        version = "0.1.0";
        src = ./Server;
        vendorHash = "sha256-vYRH43OM4xzEuS5BBFx8eHMWlZq5CRJTLIU5FVp/3CE=";
        ldflags = [ "-s" "-w" ];
      };

      mkImageRoot = name: paths: pkgs.buildEnv {
        inherit name paths;
        pathsToLink = [ "/bin" "/etc" "/lib" "/share" ];
      };

      baseTools = with pkgs; [
        bashInteractive
        cacert
        coreutils
        curl
        file
        findutils
        gawk
        git
        git-lfs
        gnugrep
        gnused
        gzip
        nodejs_24
        openssh
        unzip
        xz
        zstd
      ];

      # Godot's Gradle export expects a conventional Android SDK directory.
      androidSdk = (pkgs.androidenv.composeAndroidPackages {
        platformVersions = [ "35" ];
        buildToolsVersions = [ "35.0.1" ];
        includeCmake = false;
        includeNDK = true;
        ndkVersions = [ "28.1.13356709" ];
      }).androidsdk;

      godotTools = baseTools ++ (with pkgs; [
        androidSdk
        awscli2
        butler
        fontconfig
        godot_4
        godot-export-templates-bin
        jdk17
        wrangler
      ]);

      mkResolvedImage = { name, root, env ? [ ], entrypoint ? [ "/bin/bash" ] }:
        pkgs.nix-snapshotter.buildImage {
          inherit name;
          resolvedByNix = true;
          copyToRoot = root;
          config = {
            inherit entrypoint env;
            workingDir = "/workspace";
          };
        };

      godotCiImage = mkResolvedImage {
        name = "vr-platform-godot-ci";
        root = mkImageRoot "vr-platform-godot-ci-root" godotTools;
        env = [
          "ANDROID_HOME=${androidSdk}/libexec/android-sdk"
          "ANDROID_SDK_ROOT=${androidSdk}/libexec/android-sdk"
          "GODOT4_CONFIG_DIR=/tmp/godot-config"
          "GODOT4_DATA_DIR=/share/godot"
          "JAVA_HOME=${pkgs.jdk17}"
          "PATH=/bin"
        ];
      };

      publishCiImage = mkResolvedImage {
        name = "vr-platform-publish-ci";
        root = mkImageRoot "vr-platform-publish-ci-root" (baseTools ++ (with pkgs; [ butler ]));
        env = [ "PATH=/bin" ];
      };

      cleanupCiImage = mkResolvedImage {
        name = "vr-platform-cleanup-ci";
        root = mkImageRoot "vr-platform-cleanup-ci-root" (baseTools ++ (with pkgs; [ awscli2 ]));
        env = [ "PATH=/bin" ];
      };

      serverImage = pkgs.nix-snapshotter.buildImage {
        name = "vr-platform-server";
        resolvedByNix = true;
        copyToRoot = server;
        config = {
          entrypoint = [ "${server}/bin/vr-platform-server" ];
          user = "65532:65532";
          exposedPorts."8080/tcp" = { };
          labels."org.opencontainers.image.source" =
            "https://forgejo.maio-tech.com/Sammy/Generic-Vr-Platform";
        };
      };

    in {
      packages.${system} = {
        default = server;
        server = server;
        server-image = serverImage;
        godot-ci-image = godotCiImage;
        publish-ci-image = publishCiImage;
        cleanup-ci-image = cleanupCiImage;
        attic-client = pkgs.attic-client;
      };

      checks.${system} = {
        server = server;
        server-image = serverImage;
        godot-ci-image = godotCiImage;
        publish-ci-image = publishCiImage;
        cleanup-ci-image = cleanupCiImage;
      };
    };
}
