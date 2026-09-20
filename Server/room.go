package main

import (
	"fmt"
	"strings"

	"vr.maio-tech.com/server/protocol"
)

const maxRoomPlayers = 16

var supportedWorlds = map[string]struct{}{
	"floating_island":       {},
	"moon_garden":           {},
	"moonlit_grotto":        {},
	"starlight_observatory": {},
	"blackthorn_house":      {},
	"briarwick_manor":       {},
}

// Membership helpers run under Hub.mu, including notification queuing. A relay
// therefore cannot overtake the peer-joined notification that makes it usable.
type Room struct {
	id      uint32
	name    string
	worldID string
	clients map[uint32]*Client
}

func (room *Room) packet() *protocol.Room {
	return &protocol.Room{Id: room.id, Name: room.name, WorldId: room.worldID, PlayerCount: uint32(len(room.clients))}
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
	room := &Room{id: h.nextRoomID, name: name, worldID: worldID, clients: make(map[uint32]*Client)}
	h.rooms[room.id] = room
	return h.enterRoom(client, room)
}

func (h *Hub) joinRoom(client *Client, roomID uint32) *protocol.ServerPacket {
	// Validate the destination before leaving: a rejected switch keeps the old room.
	room := h.rooms[roomID]
	if room == nil {
		return errorPacket("room does not exist")
	}
	if client.roomID == roomID {
		// Acknowledge without changing the session, which preserves the active mesh.
		return roomJoinedPacket(room.packet(), room.peers(client.id), client.sessionID)
	}
	if len(room.clients) >= maxRoomPlayers {
		return errorPacket("room is full")
	}
	h.leaveRoom(client)
	return h.enterRoom(client, room)
}

func (h *Hub) enterRoom(client *Client, room *Room) *protocol.ServerPacket {
	peers := room.peers(0)
	// Renew even when rejoining the same room; room and peer IDs alone cannot
	// distinguish delayed signaling from the previous connection attempt.
	h.nextSessionID++
	client.sessionID = h.nextSessionID
	client.roomID = room.id
	room.clients[client.id] = client
	for _, peer := range peers {
		send(room.clients[peer.Id], peerJoinedPacket(client))
	}
	h.broadcast(roomUpdatedPacket(room.packet()))
	return roomJoinedPacket(room.packet(), peers, client.sessionID)
}

func (h *Hub) leaveRoom(client *Client, signalingDisconnected ...bool) {
	room := h.rooms[client.roomID]
	client.roomID = 0
	client.sessionID = 0
	if room == nil {
		return
	}
	delete(room.clients, client.id)
	for _, peer := range room.clients {
		send(peer, peerLeftPacket(client.id, signalingDisconnected...))
	}
	if len(room.clients) == 0 {
		delete(h.rooms, room.id)
		h.broadcast(roomRemovedPacket(room.id))
	} else {
		h.broadcast(roomUpdatedPacket(room.packet()))
	}
}
