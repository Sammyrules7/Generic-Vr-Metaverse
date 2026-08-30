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

type departure struct {
	roomID uint32
	peers  []*Client
	info   *protocol.Room
	empty  bool
}

// packet must be called while the hub lock protects room.clients.
func (room *Room) packet() *protocol.Room {
	return &protocol.Room{Id: room.id, Name: room.name, PlayerCount: uint32(len(room.clients))}
}

func (h *Hub) createRoom(client *Client, requestedName string) {
	name := strings.TrimSpace(requestedName)
	if name == "" {
		name = fmt.Sprintf("Room %d", h.nextID.Load()+1)
	}
	if len(name) > 48 {
		sendError(client, "room name is too long")
		return
	}
	h.leaveRoom(client, false)

	h.mu.Lock()
	id := h.nextID.Add(1)
	room := &Room{id: id, name: name, clients: map[uint32]*Client{client.id: client}}
	h.rooms[id] = room
	client.roomID = id
	info := room.packet()
	h.mu.Unlock()

	h.broadcastRoomUpdate(info)
	send(client, &protocol.ServerPacket{Payload: &protocol.ServerPacket_RoomJoined{
		RoomJoined: &protocol.ServerRoomJoined{Room: info},
	}})
}

func (h *Hub) joinRoom(client *Client, roomID uint32) {
	h.mu.Lock()
	room := h.rooms[roomID]
	if room == nil {
		h.mu.Unlock()
		sendError(client, "room does not exist")
		return
	}
	if client.roomID == roomID {
		info := room.packet()
		peerIDs := make([]uint32, 0, len(room.clients)-1)
		for id := range room.clients {
			if id != client.id {
				peerIDs = append(peerIDs, id)
			}
		}
		h.mu.Unlock()
		send(client, &protocol.ServerPacket{Payload: &protocol.ServerPacket_RoomJoined{
			RoomJoined: &protocol.ServerRoomJoined{Room: info, PeerIds: peerIDs},
		}})
		return
	}
	if len(room.clients) >= maxRoomPlayers {
		h.mu.Unlock()
		sendError(client, "room is full")
		return
	}

	peerIDs := make([]uint32, 0, len(room.clients))
	peers := make([]*Client, 0, len(room.clients))
	for id, peer := range room.clients {
		peerIDs = append(peerIDs, id)
		peers = append(peers, peer)
	}
	left := h.detachLocked(client)
	room.clients[client.id] = client
	client.roomID = roomID
	info := room.packet()
	h.mu.Unlock()

	h.notifyDeparture(left, client.id)
	for _, peer := range peers {
		send(peer, &protocol.ServerPacket{Payload: &protocol.ServerPacket_PeerJoined{
			PeerJoined: &protocol.ServerPeerJoined{PeerId: client.id},
		}})
	}
	send(client, &protocol.ServerPacket{Payload: &protocol.ServerPacket_RoomJoined{
		RoomJoined: &protocol.ServerRoomJoined{Room: info, PeerIds: peerIDs},
	}})
	h.broadcastRoomUpdate(info)
}

func (h *Hub) leaveRoom(client *Client, notifyClient bool) {
	h.mu.Lock()
	left := h.detachLocked(client)
	h.mu.Unlock()

	h.notifyDeparture(left, client.id)
	if notifyClient {
		sendRoomLeft(client)
	}
}

// detachLocked updates membership atomically with a join. Callers perform the
// resulting network notifications after releasing the hub lock.
func (h *Hub) detachLocked(client *Client) departure {
	room := h.rooms[client.roomID]
	if room == nil {
		client.roomID = 0
		return departure{}
	}
	delete(room.clients, client.id)
	client.roomID = 0
	left := departure{roomID: room.id, info: room.packet(), empty: len(room.clients) == 0}
	for _, peer := range room.clients {
		left.peers = append(left.peers, peer)
	}
	if left.empty {
		delete(h.rooms, room.id)
	}
	return left
}

func (h *Hub) notifyDeparture(left departure, peerID uint32) {
	if left.roomID == 0 {
		return
	}
	for _, peer := range left.peers {
		send(peer, &protocol.ServerPacket{Payload: &protocol.ServerPacket_PeerLeft{
			PeerLeft: &protocol.ServerPeerLeft{PeerId: peerID},
		}})
	}
	if left.empty {
		h.broadcast(&protocol.ServerPacket{Payload: &protocol.ServerPacket_RoomRemoved{
			RoomRemoved: &protocol.ServerRoomRemoved{RoomId: left.roomID},
		}})
	} else {
		h.broadcastRoomUpdate(left.info)
	}
}

func sendRoomLeft(client *Client) {
	send(client, &protocol.ServerPacket{Payload: &protocol.ServerPacket_RoomLeft{
		RoomLeft: &protocol.ServerRoomLeft{},
	}})
}
