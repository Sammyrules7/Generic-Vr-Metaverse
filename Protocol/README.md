# Signaling protocol

`packets.proto` defines the binary room and WebRTC signaling payloads. The
WebSocket handshake itself is versioned separately by a subprotocol token:

| Side | Token | Location |
| --- | --- | --- |
| Server | `vr-platform-v2` | `signalingProtocol` in `Server/main.go` |
| Godot client | `vr-platform-v2` | `SIGNALING_PROTOCOL` in `Godot/Networking/Networking.gd` |

The token is a compatibility marker, not a secret or an authentication
mechanism. It exists so two builds that do not share packet framing, room
admission rules, WebRTC channel layouts, or gameplay RPC signatures never form a session.

## Gate behavior

The server checks `Sec-WebSocket-Protocol` **before** upgrading the HTTP
request. A missing or different token receives `426 Upgrade Required` and the
required token in the response; the request is never admitted to the hub, so it
can never create/join a room, exchange SDP/ICE, or reach WebRTC data channels
and RPC.

The Godot client requests the token in `WebSocketPeer.supported_protocols`
before connecting. Once the socket opens it also verifies the selected
protocol and closes the connection if the server did not agree. This covers the
other mixed direction: an older server that ignores the token cannot hand a
new client an unversioned session.

## Coordinated rollout

This gate is deliberately incompatible with previous builds. A server and
client release must ship together; there is no fallback negotiation.

1. Announce a maintenance/coordinated release window. Stop accepting deploys of
   old clients and record the currently running server image/digest.
2. Publish the matching server and Godot builds from the same revision.
3. Update the deployment and clients during that window. With a rolling
   Kubernetes update, old and new signaling pods coexist briefly; clients
   routed to the wrong pod are rejected and retry, so expect temporary
   handshake failures until every pod and client runs the new build. If
   intermittent rejection is unacceptable, scale the signaling deployment down
   before rolling it up or use a maintenance window instead of an in-place
   rollout.
4. Verify a new client reaches `Connected` and that its selected protocol is
   `vr-platform-v2`, then verify room admission and WebRTC data channels.
5. Keep the previous server image and client build available for rollback, but
   roll both back together. Restoring only one side keeps the gate closed.

Do not add a legacy-protocol fallback on the shared endpoint. If a temporary
period with both builds is unavoidable, run the old server/client on a separate
endpoint or deployment rather than accepting both tokens on one server.

## Changing the token

Bump the token in both files for any incompatible change to signaling packet
framing or semantics, room admission, WebRTC channel layouts, or gameplay RPC signatures. Keep the two
constants identical and follow the coordinated rollout above.

## Checks

Server tests cover a real HTTP/WebSocket handshake for missing, legacy, wrong,
prefix-only, and current tokens:

```sh
cd Server && go test ./...
```

The Godot networking regression suite also asserts that the client requests the
token and that both sockets negotiate it.
