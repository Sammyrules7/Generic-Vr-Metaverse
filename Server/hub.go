package main

import (
	"sort"

	"vr.maio-tech.com/server/protocol"
)

const roomSnapshotLimit = 100

// Hub serializes all client, room, and membership changes through events.
// That makes notification order deterministic without locks or state copies.
type Hub struct {
	events       chan func()
	clients      map[uint32]*Client
	rooms        map[uint32]*Room
	nextClientID uint32
	nextRoomID   uint32
}

var hub = newHub()

func newHub() *Hub {
	h := &Hub{
		events:       make(chan func(), 256),
		clients:      make(map[uint32]*Client),
		rooms:        make(map[uint32]*Room),
		nextClientID: 1, // Godot reserves peer ID 1 for a server.
	}
	go func() {
		for event := range h.events {
			event()
		}
	}()
	return h
}

// addClient waits until the initial packets are queued, so the read pump can
// never process a room request before the client receives its assigned ID.
func (h *Hub) addClient(client *Client) {
	done := make(chan struct{})
	h.events <- func() {
		h.nextClientID++
		client.id = h.nextClientID
		h.clients[client.id] = client
		send(client, connectedPacket(client.id))
		h.sendRoomList(client)
		close(done)
	}
	<-done
}

func (h *Hub) removeClient(client *Client) {
	h.events <- func() {
		if h.clients[client.id] != client {
			return
		}
		h.leaveRoom(client, false)
		delete(h.clients, client.id)
	}
}

func (h *Hub) handle(client *Client, packet *protocol.ClientPacket) {
	h.events <- func() {
		if h.clients[client.id] != client {
			return
		}
		switch payload := packet.Payload.(type) {
		case *protocol.ClientPacket_RoomCreate:
			h.createRoom(client, payload.RoomCreate.Name)
		case *protocol.ClientPacket_RoomJoin:
			h.joinRoom(client, payload.RoomJoin.RoomId)
		case *protocol.ClientPacket_RoomLeave:
			h.leaveRoom(client, true)
		case *protocol.ClientPacket_Relay:
			h.relay(client, payload.Relay)
		default:
			sendError(client, "packet has no payload")
		}
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
	encoded, err := encodePacket(packet)
	if err != nil {
		return
	}
	for _, client := range h.clients {
		client.sendPacket(encoded)
	}
}
