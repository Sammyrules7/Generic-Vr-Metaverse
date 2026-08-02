package main

import (
	"fmt"
	"net/http"
	"sync/atomic"

	"github.com/gorilla/websocket"
)

var wsUpgrader = websocket.Upgrader{}

var ids atomic.Uint32

type Client struct {
	ID   uint32
	Conn *websocket.Conn
}

func wsConnected(w http.ResponseWriter, r *http.Request) {

	// Upgrade Connection
	wsConn, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		fmt.Printf("Error: Websocket failed to upgrade: %s\n", err)
		return
	}

	// Create the client struct
	client := Client{
		ID:   ids.Add(1),
		Conn: wsConn,
	}

	// Inform the client
	pktErr := wsConn.WriteJSON(Packet{
		Type: "Init",
		Data: client.ID,
	})
	if pktErr != nil {
		print("An error occurred in %i's init packet:%s\n", client.ID, err)
	}

	fmt.Printf("Client %d connected!\n", client.ID)

	pollPacket(&client)

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
