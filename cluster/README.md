# Kubernetes cluster configuration

This directory is a Kustomize root intended to be reconciled by FluxCD. It
deploys the Go WebSocket server into the `vr-platform` namespace and exposes it
inside the cluster as `server.vr-platform.svc:8080` (`/ws`).

The Forgejo Actions workflow builds Nix images, publishes their closures to the
Attic cache, and updates `nix:0/nix/store/...` references in Git. Cluster nodes
need nix-snapshotter and access to that cache; these are not ordinary OCI image
tags that can be pulled by an unconfigured container runtime.

Membership lives in one server process. The deployment uses one replica and a
`Recreate` rollout so old and new pods cannot serve different room directories
simultaneously. A rollout temporarily interrupts signaling; established WebRTC
sessions may continue, but reconnecting does not reattach their old membership.
Session affinity alone would not provide a shared directory across replicas.

Validate or preview the rendered resources with:

```sh
kubectl kustomize cluster
```

`server/httproute.yaml` connects the Service to the configured Gateway. The
Cloudflare worker proxies the public API hostname to the configured origin.
Preserve the `/ws` path and WebSocket upgrades when changing either route.
