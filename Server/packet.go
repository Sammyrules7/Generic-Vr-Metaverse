package main

import (
	"fmt"

	"google.golang.org/protobuf/proto"
	"vr.maio-tech.com/server/protocol"
)

// encode a packet to then pass to Client.sendPacket()
func encodePacket(packet *protocol.ServerPacket) ([]byte, error) {
	return proto.Marshal(packet)
}

// sendPacket queues an already-encoded packet for the client's single
// WebSocket writer. The byte slice must not be modified after this call.
// returns true if seuceccsful.
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

func handlePacket(encoded []byte, sender *Client) {
	packet := &protocol.ClientPacket{}
	if err := proto.Unmarshal(encoded, packet); err != nil {
		fmt.Printf("Failed to decode packet from client %d: %v\n", sender.id, err)
		return
	}

	payload := packet.GetData()
	if payload == nil {
		fmt.Printf("Client %d sent a packet without a payload\n", sender.id)
		return
	}

	// Echo the payload for now to prove the transport in both directions.
	// Final implementain would have a switch case for the diffrent methods to call.
	response, err := encodePacket(&protocol.ServerPacket{
		Payload: &protocol.ServerPacket_Data{
			Data: &protocol.ServerData{
				SenderId: sender.id,
				Value:    payload.Value,
			},
		},
	})
	if err != nil {
		fmt.Printf("Failed to encode response for client %d: %v\n", sender.id, err)
		return
	}

	sender.sendPacket(response)
}
