package main

import (
	"fmt"
	"sync"
	"sync/atomic"

	"github.com/gorilla/websocket"
)

var clientIds atomic.Uint32

type Client struct {
	Id   uint32          // Godot M-Api compatable id
	ch   chan []byte     // Feeder for packets. May block so use Client.sendPacket()
	conn *websocket.Conn // Do not use directly. Use Client.sendPacket()
	done sync.Once       // Do not use directly. Used as helper with clientExit() to clean up goroutines
}

func initClient(wsConn *websocket.Conn) {

	client := Client{
		Id:   clientIds.Add(1),
		ch:   make(chan []byte, 10),
		conn: wsConn,
	}

	// Send the client its id
	wsConn.WriteJSON(Packet{
		Type: Init,
		Data: client.Id,
	})

	// Start it's pollers and handlers
	go readPump(&client)
	go writePump(&client)
}

func readPump(client *Client) {

	// Just polls for messages and then feeds them to the handlePacket() func
	for {
		_, pkt, err := client.conn.ReadMessage()
		if err != nil {
			client.done.Do(client.clientExit)
			return
		}

		handlePacket(pkt, client)
	}
}

func writePump(client *Client) {

	// Just feeds raw bytes into the websocket
	for message := range client.ch {
		if err := client.conn.WriteMessage(websocket.TextMessage, message); err != nil {
			client.done.Do(client.clientExit)
			return
		}
	}

	client.done.Do(client.clientExit)
}

func (client *Client) clientExit() {
	close(client.ch)
	client.conn.Close()
	fmt.Printf("Client %d exited\n", client.Id)
}
