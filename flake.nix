{
  description = "Generic VR Platform server and nix-snapshotter container image";

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
      };

      server = pkgs.buildGoModule {
        pname = "vr-platform-server";
        version = "0.1.0";
        src = ./Server;
        vendorHash = "sha256-vYRH43OM4xzEuS5BBFx8eHMWlZq5CRJTLIU5FVp/3CE=";
        ldflags = [ "-s" "-w" ];
      };

      serverImage = pkgs.nix-snapshotter.buildImage {
        name = "forgejo.maio-tech.com/sammy/generic-vr-platform-server";
        tag = "latest";
        copyToRoot = server;
        config = {
          entrypoint = [ "${server}/bin/vr-platform-server" ];
          user = "65532:65532";
          exposedPorts."8080/tcp" = { };
          labels."org.opencontainers.image.source" =
            "https://forgejo.maio-tech.com/Sammy/Generic-Vr-Platform";
        };
      };

      publishServerImage = pkgs.writeShellApplication {
        name = "publish-server-image";
        runtimeInputs = [ pkgs.nix-snapshotter ];
        text = ''
          if (( $# == 0 )); then
            echo "usage: publish-server-image IMAGE[:TAG]..." >&2
            exit 2
          fi

          for image_ref in "$@"; do
            nix2container push --ref "$image_ref" ${serverImage}
          done
        '';
      };
    in {
      packages.${system} = {
        default = server;
        server = server;
        server-image = serverImage;
        publish-server-image = publishServerImage;
        attic-client = pkgs.attic-client;
      };

      apps.${system}.publish-server-image = {
        type = "app";
        program = "${publishServerImage}/bin/publish-server-image";
      };

      checks.${system} = {
        server = server;
        server-image = serverImage;
      };
    };
}
