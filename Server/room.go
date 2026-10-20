package main

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"os"
	"strings"
	"time"

	"vr.maio-tech.com/server/protocol"
)

const maxRoomPlayers = 16

// World allowlist. Must match the IDs in Godot/worlds/world_registry.tres
// (see WorldDefinition header). Adding a world = registry entry + this map + redeploy.

var supportedWorlds = map[string]struct{}{
	"floating_island":       {},
	"moon_garden":           {},
	"moonlit_grotto":        {},
	"starlight_observatory": {},
	"blackthorn_house":      {},
	"briarwick_manor":       {},
	"prairie_crossing":      {},
}

// Membership helpers run under Hub.mu, including notification queuing. A relay
// therefore cannot overtake the peer-joined notification that makes it usable.
type Room struct {
	id            uint32
	name          string
	worldID       string
	recoveryToken string
	clients       map[uint32]*Client
}

func (room *Room) packet() *protocol.Room {
	return &protocol.Room{Id: room.id, Name: room.name, WorldId: room.worldID, PlayerCount: uint32(len(room.clients)), RecoveryToken: room.recoveryToken}
}

// Public rooms are anonymous-open. The public nonce is not authentication.
// Only the join reply carries a capability bound to this member and incarnation.
// TURN's persistent secret keeps signatures valid across signaling restarts.
var recoveryKey = func() string {
	if key := os.Getenv("VR_PLATFORM_TURN_SECRET"); key != "" {
		return key
	}
	return rand.Text() // Local STUN-only mode: recovery cannot survive process restart.
}()

func memberToken(room *protocol.Room, peerID, sessionID uint32) string {
	mac := hmac.New(sha256.New, []byte(recoveryKey))
	fmt.Fprintf(mac, "recovery-v1:%d:%q:%q:%q:%d:%d", room.Id, room.Name, room.WorldId, room.RecoveryToken, peerID, sessionID)
	return room.RecoveryToken + "." + base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func (room *Room) memberPacket(client *Client) *protocol.Room {
	packet := room.packet()
	packet.RecoveryToken = memberToken(packet, client.meshID(), client.sessionID)
	return packet
}

func (room *Room) peers(except uint32) []*protocol.Peer {
	peers := make([]*protocol.Peer, 0, len(room.clients))
	for id, client := range room.clients {
		if id != except {
			peers = append(peers, &protocol.Peer{Id: id, SessionId: client.sessionID})
		}
	}
	return peers
}

func (h *Hub) createRoom(client *Client, requestedName string, requestedWorld ...string) *protocol.ServerPacket {
	if len(h.rooms) >= 128 {
		return errorPacket("room admission limit exceeded")
	}
	worldID := "floating_island"
	if len(requestedWorld) > 0 && requestedWorld[0] != "" {
		worldID = requestedWorld[0]
	}
	if _, supported := supportedWorlds[worldID]; !supported {
		return errorPacket("unknown world")
	}
	name := strings.TrimSpace(requestedName)
	if len(name) > 48 {
		return errorPacket("room name is too long")
	}
	if !h.admitMembership(client) {
		return errorPacket("membership mint quota exceeded")
	}
	h.leaveRoom(client)
	h.nextRoomID++
	if name == "" {
		name = fmt.Sprintf("Room %d", h.nextRoomID)
	}
	room := &Room{id: h.nextRoomID, name: name, worldID: worldID, recoveryToken: rand.Text(), clients: make(map[uint32]*Client)}
	h.rooms[room.id] = room
	return h.enterRoom(client, room)
}

func (h *Hub) joinRoom(client *Client, request *protocol.ClientRoomJoin) *protocol.ServerPacket {
	roomID := request.RoomId
	// Validate the destination before leaving: a rejected switch keeps the old room.
	room := h.rooms[roomID]
	if request.RecoveryRoom != nil && request.ClientId > 1 && request.SessionId != 0 {
		return h.recoverRoom(client, request, room)
	}
	if room == nil {
		return errorPacket("room does not exist")
	}
	if client.roomID != roomID && len(room.clients) >= maxRoomPlayers {
		return errorPacket("room is full")
	}
	if !h.admitMembership(client) {
		return errorPacket("membership mint quota exceeded")
	}
	if client.roomID == roomID {
		// Acknowledge without changing the session, which preserves the active mesh.
		return roomJoinedPacket(room.memberPacket(client), room.peers(client.meshID()), client.sessionID, mintTurnCredentials(time.Now(), client.meshID()))
	}
	h.leaveRoom(client)
	return h.enterRoom(client, room)
}

func (h *Hub) recoverRoom(client *Client, recovery *protocol.ClientRoomJoin, room *Room) *protocol.ServerPacket {
	// Verify before trusting IDs, advancing counters, or creating rooms.
	claimed := protocol.Room{Id: recovery.RecoveryRoom.Id, Name: recovery.RecoveryRoom.Name, WorldId: recovery.RecoveryRoom.WorldId, RecoveryToken: recovery.RecoveryRoom.RecoveryToken}
	nonce, _, ok := strings.Cut(claimed.RecoveryToken, ".")
	claimed.RecoveryToken = nonce
	if !ok || !hmac.Equal([]byte(recovery.RecoveryRoom.RecoveryToken), []byte(memberToken(&claimed, recovery.ClientId, recovery.SessionId))) {
		return errorPacket("invalid member recovery capability")
	}
	copyRequest := protocol.ClientRoomJoin{RoomId: recovery.RoomId, ClientId: recovery.ClientId, SessionId: recovery.SessionId}
	copyRequest.RecoveryRoom = &claimed
	recovery = &copyRequest
	if room == nil && len(h.rooms) >= 128 {
		return errorPacket("room admission limit exceeded")
	}
	if recovery.RoomId == 0 || recovery.RecoveryRoom.Id != recovery.RoomId {
		return errorPacket("invalid recovered room ID")
	}
	if client.roomID != 0 && (client.meshID() != recovery.ClientId || client.sessionID != recovery.SessionId) {
		return errorPacket("cannot replace an active recovered identity")
	}
	if h.identityInUse(client, recovery.ClientId, recovery.SessionId) {
		return errorPacket("recovered identity is already in use")
	}
	if room != nil {
		if room.name != strings.TrimSpace(recovery.RecoveryRoom.Name) || room.worldID != recovery.RecoveryRoom.WorldId ||
			room.recoveryToken != recovery.RecoveryRoom.RecoveryToken {
			return errorPacket("recovered room conflicts with an existing room")
		}
		if existing := room.clients[recovery.ClientId]; existing != nil && existing != client {
			return errorPacket("recovered peer ID is already in the room")
		}
		if len(room.clients) >= maxRoomPlayers && room.clients[recovery.ClientId] != client {
			return errorPacket("room is full")
		}
	}
	if _, supported := supportedWorlds[recovery.RecoveryRoom.WorldId]; !supported {
		return errorPacket("unknown world")
	}
	name := strings.TrimSpace(recovery.RecoveryRoom.Name)
	if name == "" || len(name) > 48 {
		return errorPacket("invalid room name")
	}
	if !h.admitMembership(client) {
		return errorPacket("membership mint quota exceeded")
	}
	if room != nil && room.clients[recovery.ClientId] == client && client.sessionID == recovery.SessionId {
		return roomJoinedPacket(room.memberPacket(client), room.peers(client.meshID()), client.sessionID, mintTurnCredentials(time.Now(), client.meshID()))
	}

	if room == nil {
		room = &Room{id: recovery.RoomId, name: name, worldID: recovery.RecoveryRoom.WorldId, recoveryToken: recovery.RecoveryRoom.RecoveryToken, clients: make(map[uint32]*Client)}
		h.rooms[room.id] = room
		if room.id > h.nextRoomID {
			h.nextRoomID = room.id
		}
	}
	// Fresh server counters must never hand a new client a surviving mesh identity.
	h.nextClientID = max(h.nextClientID, recovery.ClientId)
	h.nextSessionID = max(h.nextSessionID, recovery.SessionId)
	if client.roomID != 0 && client.roomID != room.id {
		h.leaveRoom(client)
	}
	peers := room.peers(0)
	client.peerID = recovery.ClientId
	client.roomID = room.id
	if client.sessionID != 0 && h.bySessionID[client.sessionID] == client {
		delete(h.bySessionID, client.sessionID)
	}
	client.sessionID = recovery.SessionId
	room.clients[client.meshID()] = client
	h.trackIdentity(client)
	// One marshal shared by every notified peer, not N marshals under the lock.
	if joined, ok := mustMarshal(peerJoinedPacket(client)); ok {
		for _, peer := range peers {
			if member := room.clients[peer.Id]; member != nil {
				sendEncoded(member, joined)
			}
		}
	}
	h.broadcast(roomUpdatedPacket(room.packet()))
	return roomJoinedPacket(room.memberPacket(client), peers, client.sessionID, mintTurnCredentials(time.Now(), client.meshID()))
}

// Admission runs after validation, before changing membership or minting credentials.
// The per-socket rate stays below the global rate so one caller cannot starve it.
// Socket churn and multiple callers are still bounded by the global budget.
// Caller holds hub.mu, so consuming both budgets only succeeds or leaves both.
func (h *Hub) admitMembership(client *Client) bool {
	member := client.memberMints
	if !member.allow(memberMintRate, memberMintBurst) {
		return false
	}
	if h.turnMints.allow(globalMintRate, globalMintBurst) {
		client.memberMints = member // persist the consumed per-socket token
		return true
	}
	// The shared budget rejected the request, so the caller keeps its own
	// token instead of being drained by other sockets' load.
	return false
}

func (h *Hub) enterRoom(client *Client, room *Room) *protocol.ServerPacket {
	peers := room.peers(0)
	// Renew even when rejoining the same room; room and peer IDs alone cannot
	// distinguish delayed signaling from the previous connection attempt.
	h.nextSessionID++
	if client.sessionID != 0 && h.bySessionID[client.sessionID] == client {
		delete(h.bySessionID, client.sessionID)
	}
	client.sessionID = h.nextSessionID
	client.roomID = room.id
	room.clients[client.meshID()] = client
	h.trackIdentity(client)
	if joined, ok := mustMarshal(peerJoinedPacket(client)); ok {
		for _, peer := range peers {
			if member := room.clients[peer.Id]; member != nil {
				sendEncoded(member, joined)
			}
		}
	}
	h.broadcast(roomUpdatedPacket(room.packet()))
	return roomJoinedPacket(room.memberPacket(client), peers, client.sessionID, mintTurnCredentials(time.Now(), client.meshID()))
}

func (h *Hub) leaveRoom(client *Client, signalingDisconnected ...bool) {
	room := h.rooms[client.roomID]
	client.roomID = 0
	if client.sessionID != 0 && h.bySessionID[client.sessionID] == client {
		delete(h.bySessionID, client.sessionID)
	}
	client.sessionID = 0
	if room == nil {
		return
	}
	peerID := client.meshID()
	delete(room.clients, peerID)
	// Marshal the farewell once; skip re-marshaling per remaining member.
	if left, ok := mustMarshal(peerLeftPacket(peerID, signalingDisconnected...)); ok {
		for _, peer := range room.clients {
			sendEncoded(peer, left)
		}
	}
	if len(room.clients) == 0 {
		delete(h.rooms, room.id)
		h.broadcast(roomRemovedPacket(room.id))
	} else {
		h.broadcast(roomUpdatedPacket(room.packet()))
	}
}
