package main

import (
	"fmt"
	"sync"
	"sync/atomic"

	"github.com/gorilla/websocket"
	"vr.maio-tech.com/server/protocol"
)

var clientIDs atomic.Uint32

func init() {
	// Godot reserves multiplayer peer ID 1 for a server. This is a peer mesh.
	clientIDs.Store(1)
}

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
		id:       clientIDs.Add(1),
		outgoing: make(chan []byte, 10),
		closed:   make(chan struct{}),
		conn:     wsConn,
	}

	go readPump(client)
	go writePump(client)
	hub.addClient(client)

	// Send init packet
	pkt, err := encodePacket(&protocol.ServerPacket{
		Payload: &protocol.ServerPacket_Connected{
			Connected: &protocol.ClientConnected{ClientId: client.id},
		},
	})
	if err != nil {
		fmt.Printf("Failed to encode connection packet for client %d: %v\n", client.id, err)
		client.clientExit()
		return
	}
	client.sendPacket(pkt)
	hub.sendRoomList(client)
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
