package main

import (
	"sort"
	"sync"
	"sync/atomic"

	"vr.maio-tech.com/server/protocol"
)

const roomSnapshotLimit = 100

// Hub owns all mutable client, room, and membership state. Network writes are
// performed after releasing the lock so a slow client never stalls the hub.
type Hub struct {
	mu      sync.RWMutex
	clients map[uint32]*Client
	rooms   map[uint32]*Room
	nextID  atomic.Uint32
}

var hub = newHub()

func newHub() *Hub {
	return &Hub{clients: make(map[uint32]*Client), rooms: make(map[uint32]*Room)}
}

func (h *Hub) addClient(client *Client) {
	h.mu.Lock()
	h.clients[client.id] = client
	h.mu.Unlock()
}

func (h *Hub) removeClient(client *Client) {
	h.leaveRoom(client, false)
	h.mu.Lock()
	delete(h.clients, client.id)
	h.mu.Unlock()
}

// sendRoomList sends one bounded initial snapshot. Changes after this are
// delivered as RoomUpdated and RoomRemoved packets, never as periodic lists.
func (h *Hub) sendRoomList(client *Client) {
	h.mu.RLock()
	rooms := make([]*protocol.Room, 0, len(h.rooms))
	for _, room := range h.rooms {
		rooms = append(rooms, room.packet())
	}
	h.mu.RUnlock()

	sort.Slice(rooms, func(i, j int) bool { return rooms[i].Id > rooms[j].Id })
	if len(rooms) > roomSnapshotLimit {
		rooms = rooms[:roomSnapshotLimit]
	}
	send(client, &protocol.ServerPacket{Payload: &protocol.ServerPacket_RoomList{
		RoomList: &protocol.ServerRoomList{Rooms: rooms},
	}})
}

func (h *Hub) broadcast(packet *protocol.ServerPacket) {
	h.mu.RLock()
	clients := make([]*Client, 0, len(h.clients))
	for _, client := range h.clients {
		clients = append(clients, client)
	}
	h.mu.RUnlock()
	for _, client := range clients {
		send(client, packet)
	}
}

func (h *Hub) broadcastRoomUpdate(room *protocol.Room) {
	h.broadcast(&protocol.ServerPacket{Payload: &protocol.ServerPacket_RoomUpdated{
		RoomUpdated: &protocol.ServerRoomUpdated{Room: room},
	}})
}
