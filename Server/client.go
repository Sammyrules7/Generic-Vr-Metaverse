package main

import (
	"fmt"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

type Client struct {
	id        uint32      // Godot multiplayer peer ID; assigned before pumps start.
	outgoing  chan []byte // Do not use directly, use Client.sendPacket()
	closed    chan struct{}
	conn      *websocket.Conn
	close     sync.Once
	roomID    uint32 // guarded by hub.mu
	sessionID uint32 // guarded by hub.mu; renewed on every room entry
}

func initClient(wsConn *websocket.Conn) {
	client := &Client{
		outgoing: make(chan []byte, 64),
		closed:   make(chan struct{}),
		conn:     wsConn,
	}

	hub.addClient(client)
	go writePump(client)
	go readPump(client)
}

func readPump(client *Client) {
	defer client.disconnect()
	for {
		messageType, packet, err := client.conn.ReadMessage()
		if err != nil {
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
	// One writer owns socket writes. Hub operations only enqueue bytes, so a slow
	// connection cannot hold up every client's membership changes.
	defer client.disconnect()
	for {
		select {
		case <-client.closed:
			return
		case message := <-client.outgoing:

			client.conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			err := client.conn.WriteMessage(websocket.BinaryMessage, message)

			if err != nil {
				return
			}
		}
	}
}

// Closing the socket wakes the read pump, which removes membership. Keeping
// that cleanup out of disconnect lets a hub send disconnect a slow client.
func (client *Client) disconnect() {
	client.close.Do(func() {
		close(client.closed)
		client.conn.Close()
		hub.removeClient(client)
		fmt.Printf("Client %d exited\n", client.id)
	})
}
