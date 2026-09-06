package main

import (
	"fmt"
	"sort"
	"sync"

	"google.golang.org/protobuf/proto"
	"vr.maio-tech.com/server/protocol"
)

const roomSnapshotLimit = 100 // Number of rooms to send to the client

// Hub holds mu while changing membership and queuing notifications, so peers
// see room changes and signaling in the same order. Sends never block on I/O.
type Hub struct {
	mu            sync.Mutex
	clients       map[uint32]*Client
	rooms         map[uint32]*Room
	nextClientID  uint32
	nextRoomID    uint32
	nextSessionID uint32
}

var hub = newHub()

func newHub() *Hub {
	return &Hub{
		clients:      make(map[uint32]*Client),
		rooms:        make(map[uint32]*Room),
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
	h.leaveRoom(client)
	delete(h.clients, client.id)
}

func (h *Hub) handle(client *Client, packet *protocol.ClientPacket) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.clients[client.id] != client {
		return
	}
	var reply *protocol.ServerPacket
	switch payload := packet.Payload.(type) {
	case *protocol.ClientPacket_RoomCreate:
		reply = h.createRoom(client, payload.RoomCreate.Name)
	case *protocol.ClientPacket_RoomJoin:
		reply = h.joinRoom(client, payload.RoomJoin.RoomId)
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
	rooms := make([]*protocol.Room, 0, len(h.rooms))
	for _, room := range h.rooms {
		rooms = append(rooms, room.packet())
	}
	sort.Slice(rooms, func(i, j int) bool { return rooms[i].Id > rooms[j].Id })
	if len(rooms) > roomSnapshotLimit {
		rooms = rooms[:roomSnapshotLimit]
	}
	send(client, roomListPacket(rooms))
}

func (h *Hub) broadcast(packet *protocol.ServerPacket) {
	encoded, err := proto.Marshal(packet)
	if err != nil {
		return
	}
	for _, client := range h.clients {
		client.sendPacket(encoded)
	}
}
