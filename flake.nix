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

      imageArgs = { inherit pkgs baseTools mkImageRoot mkResolvedImage; };
      godotCiImage = import ./nix/images/godot-release-ci.nix imageArgs;
      godotWebCiImage = import ./nix/images/godot-web-ci.nix imageArgs;

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

      builderCiImage = mkResolvedImage {
        name = "vr-platform-builder-ci";
        root = mkImageRoot "vr-platform-builder-ci-root" (baseTools ++ (with pkgs; [
          attic-client
          nix
        ]));
        env = [
          "NIX_CONFIG=experimental-features = nix-command flakes"
          "NIX_REMOTE=daemon"
          "PATH=/bin"
        ];
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
        godot-web-ci-image = godotWebCiImage;
        publish-ci-image = publishCiImage;
        cleanup-ci-image = cleanupCiImage;
        builder-ci-image = builderCiImage;
        attic-client = pkgs.attic-client;
      };

      checks.${system} = {
        server = server;
        server-image = serverImage;
        godot-ci-image = godotCiImage;
        godot-web-ci-image = godotWebCiImage;
        publish-ci-image = publishCiImage;
        cleanup-ci-image = cleanupCiImage;
        builder-ci-image = builderCiImage;
      };
    };
}
