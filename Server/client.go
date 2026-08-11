package main

import (
	"fmt"
	"net/http"
	"sync"
	"sync/atomic"

	"github.com/gorilla/websocket"
)

var wsUpgrader = websocket.Upgrader{}

var Clients []chan []byte
var ClientsMu sync.Mutex

var clientIds atomic.Uint32

type Client struct {
	ID   uint32
	conn *websocket.Conn
	Ch   chan []byte
}

type ClientEvent struct {
	Type    ClientEventType
	Payload any
}

type ClientEventType int

const (
	err ClientEventType = iota
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
		ID:   clientIds.Add(1),
		conn: wsConn,
		Ch:   make(chan []byte, 10),
	}

	ClientsMu.Lock()
	Clients = append(Clients, client.Ch)
	ClientsMu.Unlock()

	// Inform the client
	pktErr := wsConn.WriteJSON(Packet{
		Type: TypeInit,
		Data: client.ID,
	})
	if pktErr != nil {
		fmt.Printf("An error occurred in %d's init packet:%s\n", client.ID, err)
	}

	fmt.Printf("Client %d connected!\n", client.ID)

	go pollClientEvents(&client)

	go pollPacket(&client)

}

func pollClientEvents(client *Client) {
	for pkt := range client.Ch {
		err := client.conn.WriteMessage(websocket.TextMessage, pkt)
		if err != nil {
			fmt.Printf("Error sending packet too peer %d: %s", client.ID, pkt)
		}
	}
}

func pollPacket(client *Client) {
	for {
		// Check for packet
		_, p, err := client.conn.ReadMessage()

		// Check for error in packet
		if err != nil {
			fmt.Printf("An error occurred in the websocket connection: %s\n", err)
			break
		}

		// If no error handle it
		handlePacket(p, client.ID)
	}
}
