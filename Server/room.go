package main

import (
	"fmt"
	"strings"

	"vr.maio-tech.com/server/protocol"
)

const maxRoomPlayers = 16

type Room struct {
	id      uint32
	name    string
	clients map[uint32]*Client
}

func (room *Room) packet() *protocol.Room {
	return &protocol.Room{Id: room.id, Name: room.name, PlayerCount: uint32(len(room.clients))}
}

func (room *Room) peerIDs(except uint32) []uint32 {
	ids := make([]uint32, 0, len(room.clients))
	for id := range room.clients {
		if id != except {
			ids = append(ids, id)
		}
	}
	return ids
}

func (h *Hub) createRoom(client *Client, requestedName string) {
	name := strings.TrimSpace(requestedName)
	if len(name) > 48 {
		sendError(client, "room name is too long")
		return
	}
	h.leaveRoom(client, false)
	h.nextRoomID++
	if name == "" {
		name = fmt.Sprintf("Room %d", h.nextRoomID)
	}
	room := &Room{
		id:      h.nextRoomID,
		name:    name,
		clients: map[uint32]*Client{client.id: client},
	}
	h.rooms[room.id] = room
	client.roomID = room.id
	info := room.packet()
	h.broadcast(roomUpdatedPacket(info))
	send(client, roomJoinedPacket(info, nil))
}

func (h *Hub) joinRoom(client *Client, roomID uint32) {
	room := h.rooms[roomID]
	if room == nil {
		sendError(client, "room does not exist")
		return
	}
	if client.roomID == roomID {
		send(client, roomJoinedPacket(room.packet(), room.peerIDs(client.id)))
		return
	}
	if len(room.clients) >= maxRoomPlayers {
		sendError(client, "room is full")
		return
	}

	h.leaveRoom(client, false)
	peerIDs := room.peerIDs(0)
	room.clients[client.id] = client
	client.roomID = roomID
	info := room.packet()
	for _, peerID := range peerIDs {
		send(room.clients[peerID], peerJoinedPacket(client.id))
	}
	send(client, roomJoinedPacket(info, peerIDs))
	h.broadcast(roomUpdatedPacket(info))
}

func (h *Hub) leaveRoom(client *Client, notifyClient bool) {
	room := h.rooms[client.roomID]
	if room != nil {
		delete(room.clients, client.id)
		client.roomID = 0
		for _, peer := range room.clients {
			send(peer, peerLeftPacket(client.id))
		}
		if len(room.clients) == 0 {
			delete(h.rooms, room.id)
			h.broadcast(roomRemovedPacket(room.id))
		} else {
			h.broadcast(roomUpdatedPacket(room.packet()))
		}
	}
	if notifyClient {
		send(client, roomLeftPacket())
	}
}
