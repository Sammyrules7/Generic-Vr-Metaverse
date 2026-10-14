package main

import (
	"crypto/rand"
	"fmt"
	"strings"

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
	if client.roomID == roomID {
		// Acknowledge without changing the session, which preserves the active mesh.
		return roomJoinedPacket(room.packet(), room.peers(client.meshID()), client.sessionID)
	}
	if len(room.clients) >= maxRoomPlayers {
		return errorPacket("room is full")
	}
	h.leaveRoom(client)
	return h.enterRoom(client, room)
}

func (h *Hub) recoverRoom(client *Client, recovery *protocol.ClientRoomJoin, room *Room) *protocol.ServerPacket {
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
		if room.clients[recovery.ClientId] == client && client.sessionID == recovery.SessionId {
			return roomJoinedPacket(room.packet(), room.peers(client.meshID()), client.sessionID)
		}
	}
	if _, supported := supportedWorlds[recovery.RecoveryRoom.WorldId]; !supported {
		return errorPacket("unknown world")
	}
	name := strings.TrimSpace(recovery.RecoveryRoom.Name)
	if name == "" || len(name) > 48 {
		return errorPacket("invalid room name")
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
	return roomJoinedPacket(room.packet(), peers, client.sessionID)
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
	return roomJoinedPacket(room.packet(), peers, client.sessionID)
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
