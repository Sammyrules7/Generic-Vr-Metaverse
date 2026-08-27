package main

import (
	"encoding/json"
	"fmt"
)

type Packet struct {
	Sender uint32          `json:"sender"`
	Type   PacketType      `json:"type"`
	Data   json.RawMessage `json:"data"`
}

type PacketType int

const (
	Init PacketType = iota
	PacketDirect
	PacketCreateRoom
)

// Putting the packet directly in the goroutine may block. This stops that.
func (client *Client) sendPacket(pkt []byte) {
	select {
	case client.ch <- pkt:
	default:
		return
	}
}

func handlePacket(pkt []byte, sender *Client) {

	jsonPkt := Packet{}

	if err := json.Unmarshal(pkt, &jsonPkt); err != nil {
		fmt.Printf("Error unmarshelling packet: %s\n", err)
		return
	}

	// Check if the sender might be modifing packets
	if jsonPkt.Sender != sender.Id {
		fmt.Printf("Ids do not match with packet from: %d.\n", sender.Id)
		return
	}

	// Call the correct function for the packets. (Test prints for now.)
	switch jsonPkt.Type {

	case Init:
		fmt.Printf("Packet init")
	case PacketDirect:
		fmt.Printf("Got a direct packet!")
	case PacketCreateRoom:
		fmt.Printf("Got a create room packet")
	default:
		fmt.Printf("Packet from %d failed to match type: %+v .\n", sender.Id, jsonPkt)
	}

	// Test Implementation ping pong sending the packets back
	newpkt, err := json.Marshal(jsonPkt)
	if err != nil {
		fmt.Printf("Error marshelling apksdfakrdjkl\n")
		return
	}

	sender.sendPacket(newpkt)
}
