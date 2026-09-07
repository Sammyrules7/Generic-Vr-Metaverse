# Kubernetes cluster configuration

This directory is a Kustomize root intended to be reconciled by FluxCD. It
deploys the Go WebSocket server into the `vr-platform` namespace and exposes it
inside the cluster as `server.vr-platform.svc:8080` (`/ws`).

The Forgejo Actions workflow publishes the server container to
`forgejo.maio-tech.com/sammy/generic-vr-platform-server`. For a private
registry, add an `imagePullSecret` to the pod specification or arrange registry
credentials at the cluster level.

Validate or preview the rendered resources with:

```sh
kubectl kustomize cluster
```

An Ingress is intentionally not included because its hostname, TLS secret, and
IngressClass are cluster-specific. Route external WebSocket traffic to the
`server` Service on port `8080` and preserve the `/ws` path.
