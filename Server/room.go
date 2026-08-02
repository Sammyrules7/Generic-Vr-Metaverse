package main

import (
	"encoding/json"
	"fmt"
	"sync/atomic"
)

var roomIds atomic.Uint32

type Room struct {
	ID      uint32
	Clients map[uint32]*Client
}

func CreateRoom() *Room {
	room := Room{
		ID: roomIds.Add(1),
	}

	announceRoom(&room)

	return &room
}

func announceRoom(room *Room) {

	pktBytes, err := json.Marshal(
		Packet{
			Type: TypeCreated,
			Payload: &room,
		},
	)

	if err != nil {
		fmt.Printf("Error marshaling packet to announce room creation:%s", err)
	}

	for peer
}
