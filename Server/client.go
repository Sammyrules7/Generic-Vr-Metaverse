package main

import (
	"fmt"
	"sync"

	"github.com/gorilla/websocket"
)

type Client struct {
	id       uint32      // Godot compatable M Api id
	outgoing chan []byte // Do not use directly, use Client.sendPacket()
	closed   chan struct{}
	conn     *websocket.Conn
	close    sync.Once
	roomID   uint32 // guarded by hub.mu
}

func initClient(wsConn *websocket.Conn) {
	client := &Client{
		outgoing: make(chan []byte, 64),
		closed:   make(chan struct{}),
		conn:     wsConn,
	}

	go writePump(client)
	hub.addClient(client)
	go readPump(client)
}

func readPump(client *Client) {
	for {
		messageType, packet, err := client.conn.ReadMessage()
		if err != nil {
			client.clientExit()
			return
		}
		if messageType != websocket.BinaryMessage {
			fmt.Printf("Client %d sent a non-binary packet\n", client.id)
			continue
		}

		handlePacket(packet, client)
	}
}

func writePump(client *Client) {
	for {
		select {
		case <-client.closed:
			return
		case message := <-client.outgoing:

			err := client.conn.WriteMessage(websocket.BinaryMessage, message)

			if err != nil {
				client.clientExit()
				return
			}
		}
	}
}

func (client *Client) clientExit() {
	client.close.Do(func() {
		hub.removeClient(client)
		close(client.closed)
		client.conn.Close()
		fmt.Printf("Client %d exited\n", client.id)
	})
}
