package main

import (
	"fmt"
	"sync/atomic"

	"github.com/gorilla/websocket"
)

var clientIds atomic.Uint32

type Client struct {
	Id   uint32
	Chan chan []byte
}

func initClient(wsConn *websocket.Conn) {

	client := Client{
		Id:   clientIds.Add(1),
		Chan: make(chan []byte, 10),
	}

	// Send the client its id
	wsConn.WriteJSON(Packet{
		Type: "Init",
		Data: client.Id,
	})

	go readPump(&client, wsConn)
	go writePump(client.Chan, wsConn)
}

func readPump(client *Client, conn *websocket.Conn) {

	for {
		_, pkt, err := conn.ReadMessage()
		if err != nil {
			return
		}

		handlePacket(pkt, client)
	}
}

func writePump(ch <-chan []byte, conn *websocket.Conn) {

	for message := range ch {
		if err := conn.WriteMessage(websocket.TextMessage, message); err != nil {
			clientExit()
			return
		}
	}

	clientExit()
}

func clientExit() {
	fmt.Printf("Client exited\n")
}
