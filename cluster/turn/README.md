# TURN relay (coturn)

Relays WebRTC media for clients behind symmetric NATs that STUN alone cannot
connect. Everything else stays peer-to-peer; this process only sees relayed
users' traffic.

## One-time setup (out of band, never committed)

Pick a strong random secret and create the two Secrets Flux must not manage:

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
