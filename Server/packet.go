package main

import (
	"fmt"

	"google.golang.org/protobuf/proto"
	"vr.maio-tech.com/server/protocol"
)

func (client *Client) sendPacket(encoded []byte) bool {
	select {
	case <-client.closed:
		return false
	default:
	}

	select {
	case <-client.closed:
		return false
	case client.outgoing <- encoded:
		return true
	default:
		fmt.Printf("Client %d outgoing packet queue is full\n", client.id)
		client.disconnect()
		return false
	}
}

func send(client *Client, packet *protocol.ServerPacket) bool {
	encoded, err := proto.Marshal(packet)
	if err != nil {
		fmt.Printf("Failed to encode packet for client %d: %v\n", client.id, err)
		return false
	}
	return client.sendPacket(encoded)
}

func sendError(client *Client, reason string) {
	send(client, errorPacket(reason))
}

func handlePacket(encoded []byte, sender *Client) {
	packet := &protocol.ClientPacket{}
	if err := proto.Unmarshal(encoded, packet); err != nil {
		sendError(sender, "invalid packet")
		return
	}
	hub.handle(sender, packet)
}

func connectedPacket(id uint32) *protocol.ServerPacket {
	return &protocol.ServerPacket{Payload: &protocol.ServerPacket_Connected{Connected: &protocol.ClientConnected{ClientId: id}}}
}

func roomListPacket(rooms []*protocol.Room) *protocol.ServerPacket {
	return &protocol.ServerPacket{Payload: &protocol.ServerPacket_RoomList{RoomList: &protocol.ServerRoomList{Rooms: rooms}}}
}

func roomUpdatedPacket(room *protocol.Room) *protocol.ServerPacket {
	return &protocol.ServerPacket{Payload: &protocol.ServerPacket_RoomUpdated{RoomUpdated: &protocol.ServerRoomUpdated{Room: room}}}
}

func roomRemovedPacket(id uint32) *protocol.ServerPacket {
	return &protocol.ServerPacket{Payload: &protocol.ServerPacket_RoomRemoved{RoomRemoved: &protocol.ServerRoomRemoved{RoomId: id}}}
}

func roomJoinedPacket(room *protocol.Room, peers []*protocol.Peer, sessionID uint32) *protocol.ServerPacket {
	joined := &protocol.ServerRoomJoined{Room: room, Peers: peers, SessionId: sessionID}
	return &protocol.ServerPacket{Payload: &protocol.ServerPacket_RoomJoined{RoomJoined: joined}}
}

func roomLeftPacket() *protocol.ServerPacket {
	return &protocol.ServerPacket{Payload: &protocol.ServerPacket_RoomLeft{RoomLeft: &protocol.ServerRoomLeft{}}}
}

func peerJoinedPacket(client *Client) *protocol.ServerPacket {
	return &protocol.ServerPacket{Payload: &protocol.ServerPacket_PeerJoined{PeerJoined: &protocol.ServerPeerJoined{Peer: &protocol.Peer{Id: client.id, SessionId: client.sessionID}}}}
}

func peerLeftPacket(id uint32) *protocol.ServerPacket {
	return &protocol.ServerPacket{Payload: &protocol.ServerPacket_PeerLeft{PeerLeft: &protocol.ServerPeerLeft{PeerId: id}}}
}

func relayPacket(relay *protocol.ServerRelay) *protocol.ServerPacket {
	return &protocol.ServerPacket{Payload: &protocol.ServerPacket_Relay{Relay: relay}}
}

func errorPacket(reason string) *protocol.ServerPacket {
	return &protocol.ServerPacket{Payload: &protocol.ServerPacket_Error{Error: &protocol.ServerError{Reason: reason}}}
}
