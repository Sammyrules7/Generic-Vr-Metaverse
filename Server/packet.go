package main

import (
	"fmt"

	"google.golang.org/protobuf/proto"
	"vr.maio-tech.com/server/protocol"
)

func encodePacket(packet *protocol.ServerPacket) ([]byte, error) {
	return proto.Marshal(packet)
}

func (client *Client) sendPacket(encoded []byte) bool {
	select {
	case <-client.closed:
		return false
	case client.outgoing <- encoded:
		return true
	default:
		fmt.Printf("Client %d outgoing packet queue is full\n", client.id)
		return false
	}
}

func send(client *Client, packet *protocol.ServerPacket) bool {
	encoded, err := encodePacket(packet)
	if err != nil {
		fmt.Printf("Failed to encode packet for client %d: %v\n", client.id, err)
		return false
	}
	return client.sendPacket(encoded)
}

func sendError(client *Client, reason string) {
	send(client, &protocol.ServerPacket{Payload: &protocol.ServerPacket_Error{
		Error: &protocol.ServerError{Reason: reason},
	}})
}

func handlePacket(encoded []byte, sender *Client) {
	packet := &protocol.ClientPacket{}
	if err := proto.Unmarshal(encoded, packet); err != nil {
		sendError(sender, "invalid packet")
		return
	}

	switch payload := packet.Payload.(type) {
	case *protocol.ClientPacket_RoomCreate:
		hub.createRoom(sender, payload.RoomCreate.Name)
	case *protocol.ClientPacket_RoomJoin:
		hub.joinRoom(sender, payload.RoomJoin.RoomId)
	case *protocol.ClientPacket_RoomLeave:
		hub.leaveRoom(sender, true)
	case *protocol.ClientPacket_Relay:
		hub.relay(sender, payload.Relay)
	default:
		sendError(sender, "packet has no payload")
	}
}
