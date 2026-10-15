# TURN relay (coturn)

Relays WebRTC media for clients behind symmetric NATs that STUN alone cannot
connect. Everything else stays peer-to-peer; this process only sees relayed
users' traffic.

## Setup (automatic)

The `turn-init` Job in this directory provisions everything on first Flux
reconcile: it generates a random shared secret and creates the `turn-config`
(coturn config file) and `signaling-turn` (server env) Secrets, then bounces
the server and coturn Deployments so boot-time config picks them up. It is
idempotent — re-runs are no-ops while both Secrets exist, so it can never
rotate credentials out from under running pods.

To rotate after a suspected leak: `kubectl -n vr-platform delete job turn-init`
and delete both Secrets; Flux recreates the Job, which mints fresh ones.

The signaling server mints time-boxed credentials from the shared secret (see
`Server/turn.go`), so no per-user state exists anywhere. `VR_PLATFORM_TURN_URLS`
in `cluster/server/deployment.yaml` must name the public hostname below —
change it if yours differs.

## Setup (manual fallback)

If you prefer imperative commands over the Job, or are not Flux-managed:

```sh
TURN_SECRET="$(openssl rand -base64 32)"

kubectl -n vr-platform create secret generic turn-config \
  --from-literal=turnserver.conf="listening-port=3478
realm=vr.maio-tech.com
static-auth-secret=${TURN_SECRET}
fingerprint
log-file=stdout
no-multicast-peers"

kubectl -n vr-platform create secret generic signaling-turn \
  --from-literal=shared-secret="${TURN_SECRET}"
```

The signaling server mints time-boxed credentials from the same secret (see
`Server/turn.go`), so no per-user state exists anywhere. `VR_PLATFORM_TURN_URLS`
in `cluster/server/deployment.yaml` must name the public hostname below —
change it if yours differs.

## DNS

Point the TURN hostname (default `turn.vr.maio-tech.com`) with an **unproxied**
(DNS-only, grey cloud) A record at the Klipper LoadBalancer IP. The Cloudflare
proxy cannot pass TURN UDP; proxied records will fail allocation.

## Firewall

Open these to all cluster nodes (or the LoadBalancer, which forwards to them):

| Port | Proto | Purpose |
| --- | --- | --- |
| 3478 | UDP | TURN allocations, permissions, relayed media signaling |
| 3478 | TCP | TURN/TCP fallback for clients whose NAT blocks UDP |
| 49160–49200 | UDP | Relayed media (constrained by `min-port`/`max-port` in the generated `turnserver.conf`, so the full ephemeral range stays closed) |

## Verify

```sh
# STUN binding works (expect a mapped address in the reply):
nix run nixpkgs#coturn -- turnutils_stunclient turn.vr.maio-tech.com
# Allocation needs a server-minted credential; join any room with a client
# built from this commit and confirm relay candidates in verbose logs.
```

## Restarts

A coturn restart drops active relayed sessions (allocations are process
memory; this is true of every TURN server). Clients detect the dead data
channel while room membership persists and renegotiate automatically within
`TRANSPORT_RECOVERY_MS` — no rejoin needed. P2P clients are unaffected.
Keep `replicas: 1`: spreading allocations across pods breaks relayed calls.
