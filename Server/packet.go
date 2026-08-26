package main

import (
	"encoding/json"
	"fmt"
)

type Packet struct {
	Sender uint32
	Type   any
	Data   any
}

const (
	PacketDirect = iota
	PacketCreateRoom
)

func (client *Client) sendPacket(pkt []byte) {
	select {
	case client.Chan <- pkt:
	default:
		return
	}
}

func handlePacket(pkt []byte, sender *Client) {

	jsonPkt := Packet{
		Sender: sender.Id,
	}

	if err := json.Unmarshal(pkt, &jsonPkt.Data); err != nil {
		fmt.Printf("Error unmarshelling packet: %s\n", err)
		return
	}

	newpkt, err := json.Marshal(jsonPkt)
	if err != nil {
		fmt.Printf("Error marshelling apksdfakrdjkl\n")
		return
	}

	sender.sendPacket(newpkt)
}
