package main

import (
	"fmt"
	"sync"
	"sync/atomic"

	"github.com/gorilla/websocket"
	"vr.maio-tech.com/server/protocol"
)

var clientIDs atomic.Uint32

type Client struct {
	id       uint32
	outgoing chan []byte
	closed   chan struct{}
	conn     *websocket.Conn
	close    sync.Once
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

	connected, err := encodePacket(&protocol.ServerPacket{
		Payload: &protocol.ServerPacket_Connected{
			Connected: &protocol.ClientConnected{ClientId: client.id},
		},
	})
	if err != nil {
		fmt.Printf("Failed to encode connection packet for client %d: %v\n", client.id, err)
		client.clientExit()
		return
	}
	client.sendPacket(connected)
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
		close(client.closed)
		client.conn.Close()
		fmt.Printf("Client %d exited\n", client.id)
	})
}
