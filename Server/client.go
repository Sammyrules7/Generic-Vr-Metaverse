package main

import (
	"fmt"
	"sync"
	"sync/atomic"

	"github.com/gorilla/websocket"
)

var clientIds atomic.Uint32

type Client struct {
	Id   uint32
	Chan chan []byte
	conn *websocket.Conn
	done sync.Once
}

func initClient(wsConn *websocket.Conn) {

	client := Client{
		Id:   clientIds.Add(1),
		Chan: make(chan []byte, 10),
		conn: wsConn,
	}

	// Send the client its id
	wsConn.WriteJSON(Packet{
		Type: "Init",
		Data: client.Id,
	})

	go readPump(&client)
	go writePump(&client)
}

func readPump(client *Client) {

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

	for message := range client.Chan {
		if err := client.conn.WriteMessage(websocket.TextMessage, message); err != nil {
			client.done.Do(client.clientExit)
			return
		}
	}

	client.done.Do(client.clientExit)
}

func (client *Client) clientExit() {
	close(client.Chan)
	client.conn.Close()
	fmt.Printf("Client %d exited\n", client.Id)
}
