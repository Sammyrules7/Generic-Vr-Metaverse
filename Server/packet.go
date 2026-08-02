package main

import (
	"encoding/json"
	"fmt"
)

type PacketType string

const (
	TypeOffer     PacketType = "offer"
	TypeAnswer    PacketType = "answer"
	TypeCandidate PacketType = "candidate"
	TypeJoin      PacketType = "join_room"
	TypeCreate    PacketType = "create_room"
	TypeCreated   PacketType = "room_created"
	TypeGeneric   PacketType = "generic"
)

type DataPacket struct {
	Type     PacketType      `json:"type"`
	SenderID int32           `json:"sender"`
	TargetID int32           `json:"target"`
	Payload  json.RawMessage `json:"payload"`
}

type Packet struct {
	Type string `json:"type"`
	Data any    `json:"data"`
}

func handlePacket(contents []byte, id uint32) {
	var packetJson DataPacket
	var err error = json.Unmarshal(contents, &packetJson)
	if err != nil {
		fmt.Printf("Json parsing error: %s\n", err)
	}

	fmt.Printf("Packet recived from %d. Contents: %s\n", id, string(contents))

	switch packetJson.Type {
	case TypeGeneric:
		fmt.Printf("Generic Packet from %s contain: %s\n", string(packetJson.SenderID), packetJson.Payload)
	case TypeCreate:
		fmt.Printf("Room Created\n")
	default:
		fmt.Printf("An error occured matching packet\n")
	}
}
