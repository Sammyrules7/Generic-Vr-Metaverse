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
        gitMinimal
        git-lfs
        gnugrep
        gnused
        gnutar
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
            inherit entrypoint;
            env = [
              "HOME=/tmp"
              "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            ] ++ env;
            workingDir = "/workspace";
          };
        };

      imageArgs = { inherit pkgs baseTools mkImageRoot mkResolvedImage; };
      godotCiImage = import ./nix/images/godot-release-ci.nix imageArgs;
      godotWebCiImage = import ./nix/images/godot-web-ci.nix imageArgs;
      webPublishCiImage = import ./nix/images/web-publish-ci.nix imageArgs;
      cleanupCiImage = import ./nix/images/web-cleanup-ci.nix imageArgs;

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
        copyToRoot = mkImageRoot "vr-platform-server-root" [ server ];
        config = {
          entrypoint = [ "/bin/server" ];
          user = "65532:65532";
          exposedPorts."8080/tcp" = { };
          labels."org.opencontainers.image.source" =
            "https://forgejo.maio-tech.com/Sammy/Generic-Vr-Platform";
        };
      };

    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          go godot_4 protobuf protoc-gen-go git-lfs ripgrep shellcheck nodejs_24 python3
        ];
      };

      packages.${system} = {
        default = server;
        server = server;
        server-image = serverImage;
        godot-ci-image = godotCiImage;
        godot-web-ci-image = godotWebCiImage;
        web-publish-ci-image = webPublishCiImage;
        cleanup-ci-image = cleanupCiImage;
        builder-ci-image = builderCiImage;
        attic-client = pkgs.attic-client;
      };

      checks.${system} = {
        server = server;
        server-image = serverImage;
        godot-ci-image = godotCiImage;
        godot-web-ci-image = godotWebCiImage;
        web-publish-ci-image = webPublishCiImage;
        cleanup-ci-image = cleanupCiImage;
        builder-ci-image = builderCiImage;
      };
    };
}
