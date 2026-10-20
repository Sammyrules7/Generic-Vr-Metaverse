# TURN relay (coturn)

Relays WebRTC media for clients behind symmetric NATs that STUN alone cannot
connect. Everything else stays peer-to-peer; this process only sees relayed
users' traffic.

## Setup (automatic)

The `turn-init` Job creates the canonical `turn-shared` key and derives
`turn-config` (coturn) and `signaling-turn` (server). It checks every surviving
key before writing, fails on disagreement, and repairs missing Secrets using
the surviving key. Concurrent creators are re-read and checked. Existing config
is migrated without rotating the key; changed consumers are restarted.

To rotate deliberately, stop both consumers, delete all three Secrets and the
Job, then let Flux reconcile. Deleting only the Job never rotates the key.

Before reconciliation, point `turn.vr.maio-tech.com` at the stable IPv4
LoadBalancer address. The Job resolves it into coturn's `external-ip`; update
DNS and rerun the Job when that address changes. Kubernetes forwards each UDP
relay port to the identical pod port. This requires the LoadBalancer to preserve
ports and support the entire relay range; the generated Service exposes all 41
ports. No host networking is required. The public IPv4 must be reachable through
any upstream NAT with the same port mapping. IPv6-only deployment is unsupported.

Rooms and ordinary joins are **anonymous-open**, not account-authenticated.
Only a member's join reply carries its signed recovery capability in
`Room.recovery_token`; public room listings carry only an incarnation nonce.
The HMAC binds room ID/name/world/nonce and peer/session IDs. The persistent
TURN key verifies it after a signaling restart; without that key, local
STUN-only recovery survives socket reconnects but not process restarts.
Capabilities are bearer credentials: protect them with WSS. They do not expire;
key rotation revokes them. Old unsigned clients must rejoin after this upgrade.

Admission is bounded to 256 signaling sockets, 128 rooms and a global membership
mint budget of 2/second with burst 20, including repeated joins and recovery.
Validated admissions also have a per-socket mint budget of 1/second with burst 4;
invalid requests consume neither mint budget. This prevents one persistent socket
from draining the shared budget; multiple callers can still exhaust it.
Coturn additionally enforces 4 allocations per username and 64 total allocations.
These abuse limits also constrain relay-dependent rooms below the experimental
16-player admission limit. Anonymous distributed users can exhaust them.

## Relay capacity limits

Evidence for the numbers above (`Server/room.go` `maxRoomPlayers`, `job.yaml`):

- Rooms are experimental at 16 players and signal as a mesh: every client
  keeps one peer connection per other member, and each connection that fails
  direct STUN dialing needs its own TURN allocation.
- coturn is configured with `user-quota=4` and `total-quota=64`, and the relay
  range 49160–49200 provides exactly 41 relayed ports. Each allocation holds
  one port, so port exhaustion caps simultaneous allocations at 41 even though
  `total-quota=64` allows more.
- Consequences: a symmetric-NAT client relaying all 15 mesh peers of a full
  room exceeds `user-quota=4` and stops receiving relayed peer connections
  mid-room; across rooms, allocations hard-stop at 41 before 64.

These are the current deployment bounds, not a verified 16-player relay capacity.
ICE implementations can gather relay candidates even when a direct route wins,
so direct connectivity alone does not establish the allocation budget.
Options include keeping the present bounds with reduced relay coverage, lowering
`total-quota` to 41 so quota and ports agree, or raising
either limit past 41 also requires widening `min-port`/`max-port` **and** the
generated Service port list, which is a deliberate deployment change.

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
