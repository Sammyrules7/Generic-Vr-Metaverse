package main

import (
	"fmt"
	"net/http"
	"sync/atomic"

	"github.com/gorilla/websocket"
)

var wsUpgrader = websocket.Upgrader{}

var clientIds atomic.Uint32

type Client struct {
	ID   uint32
	Conn *websocket.Conn
	Ch   chan ClientEvent
}

type ClientEvent struct {
	Type
	Payload
}

type ClientEventType Int

const (
	err ClientEventTypes = iota
	PacketRecived
)

func wsConnected(w http.ResponseWriter, r *http.Request) {

	// Upgrade Connection
	wsConn, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		fmt.Printf("Error: Websocket failed to upgrade: %s\n", err)
		return
	}

	// Create the client struct
	client := Client{
		ID:      clientIds.Add(1),
		Conn:    wsConn,
		EventCh: make(chan ClientEvent, 10),
		WriteCh: make(chan packet, 10),
	}

	// Inform the client
	pktErr := wsConn.WriteJSON(Packet{
		Type: TypeInit,
		Data: client.ID,
	})
	if pktErr != nil {
		fmt.Printf("An error occurred in %i's init packet:%s\n", client.ID, err)
	}

	fmt.Printf("Client %d connected!\n", client.ID)

	pollClientEvents(&client)

	go pollPacket(&client)

}

func pollPacket(client *Client) {
	for {
		// Check for packet
		_, p, err := client.Conn.ReadMessage()

		// Check for error in packet
		if err != nil {
			fmt.Printf("An error occurred in the websocket connection: %s\n", err)
			break
		}

		// If no error handle it
		handlePacket(p, client.ID)
	}
}
