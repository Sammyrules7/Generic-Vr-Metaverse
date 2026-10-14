package main

import (
	"fmt"
	"sort"
	"sync"

	"vr.maio-tech.com/server/protocol"
)

const roomSnapshotLimit = 100 // Number of rooms to send to the client

// Hub holds mu while changing membership and queuing notifications, so peers
// see room changes and signaling in the same order. Sends never block on I/O.
type Hub struct {
	mu            sync.RWMutex
	clients       map[uint32]*Client
	rooms         map[uint32]*Room
	byMeshID      map[uint32]*Client
	bySessionID   map[uint32]*Client
	nextClientID  uint32
	nextRoomID    uint32
	nextSessionID uint32
}

var hub = newHub()

func newHub() *Hub {
	return &Hub{
		clients:      make(map[uint32]*Client),
		rooms:        make(map[uint32]*Room),
		byMeshID:     make(map[uint32]*Client),
		bySessionID:  make(map[uint32]*Client),
		nextClientID: 1, // Godot reserves peer ID 1 for a server.
	}
}

// Queue the handshake before starting either pump, so the ID is immutable
// once I/O begins and replies cannot overtake the handshake.
func (h *Hub) addClient(client *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.nextClientID++
	client.id = h.nextClientID
	h.clients[client.id] = client
	h.byMeshID[client.meshID()] = client
	if client.sessionID != 0 {
		h.bySessionID[client.sessionID] = client
	}
	send(client, connectedPacket(client.id))
	h.sendRoomList(client)
}

func (h *Hub) removeClient(client *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.clients[client.id] != client {
		fmt.Printf("Error could not find client %d in hub clients array upon removal.\n", client.id)
		return
	}
	h.leaveRoom(client, true)
	delete(h.clients, client.id)
	for key, other := range h.byMeshID {
		if other == client {
			delete(h.byMeshID, key)
		}
	}
	for key, other := range h.bySessionID {
		if other == client {
			delete(h.bySessionID, key)
		}
	}
}

// trackIdentity indexes surviving mesh/session IDs after recovery so future
// conflict checks are O(1) instead of scanning every client. Caller holds mu.
func (h *Hub) trackIdentity(client *Client) {
	for key, other := range h.byMeshID {
		if other == client && key != client.meshID() {
			delete(h.byMeshID, key)
		}
	}
	for key, other := range h.bySessionID {
		if other == client && key != client.sessionID {
			delete(h.bySessionID, key)
		}
	}
	h.byMeshID[client.meshID()] = client
	if client.sessionID != 0 {
		h.bySessionID[client.sessionID] = client
	}
}

func (h *Hub) identityInUse(except *Client, meshID, sessionID uint32) bool {
	if other := h.byMeshID[meshID]; other != nil && other != except {
		return true
	}
	if other := h.bySessionID[sessionID]; other != nil && other != except {
		return true
	}
	return false
}

func (h *Hub) handle(client *Client, packet *protocol.ClientPacket) {
	// Relays are the highest-frequency path and only read membership.
	// Serve them under a read lock so signaling never serializes behind
	// room creates/joins/leaves.
	if _, ok := packet.Payload.(*protocol.ClientPacket_Relay); ok {
		h.mu.RLock()
		known := h.clients[client.id] == client
		h.mu.RUnlock()
		if !known {
			return
		}
		h.relay(client, packet.Payload.(*protocol.ClientPacket_Relay).Relay)
		return
	}
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.clients[client.id] != client {
		return
	}
	var reply *protocol.ServerPacket
	switch payload := packet.Payload.(type) {
	case *protocol.ClientPacket_RoomCreate:
		reply = h.createRoom(client, payload.RoomCreate.Name, payload.RoomCreate.WorldId)
	case *protocol.ClientPacket_RoomJoin:
		reply = h.joinRoom(client, payload.RoomJoin)
	case *protocol.ClientPacket_RoomLeave:
		h.leaveRoom(client)
		reply = roomLeftPacket()
	case *protocol.ClientPacket_Relay:
		h.relay(client, payload.Relay)
	default:
		reply = errorPacket("packet has invalid payload")
	}
	if reply != nil {
		// Correlate errors as well as successes; unsolicited room updates must not
		// complete whichever command the client happens to have pending.
		reply.RequestId = packet.RequestId
		send(client, reply)
	}
}

func (h *Hub) sendRoomList(client *Client) {
	if len(h.rooms) == 0 {
		send(client, roomListPacket(nil))
		return
	}
	rooms := make([]*protocol.Room, 0, len(h.rooms))
	for _, room := range h.rooms {
		rooms = append(rooms, room.packet())
	}
	if len(rooms) > 1 {
		sort.Slice(rooms, func(i, j int) bool { return rooms[i].Id > rooms[j].Id })
		if len(rooms) > roomSnapshotLimit {
			rooms = rooms[:roomSnapshotLimit]
		}
	}
	send(client, roomListPacket(rooms))
}

func (h *Hub) broadcast(packet *protocol.ServerPacket) {
	encoded, ok := mustMarshal(packet)
	if !ok {
		return
	}
	for _, client := range h.clients {
		client.sendPacket(encoded)
	}
}

// broadcastExcept shares one buffer with every client but one (the joiner,
// who already gets the same state in its room-joined reply).
func (h *Hub) broadcastExcept(packet *protocol.ServerPacket, except *Client) {
	encoded, ok := mustMarshal(packet)
	if !ok {
		return
	}
	for _, client := range h.clients {
		if client != except {
			client.sendPacket(encoded)
		}
	}
}
