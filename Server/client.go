package main

import (
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
		Type: PacketInit,
		Data: client.Id,
	})

	pollForEventsAndSend(client.Chan, wsConn)
}

func pollForEventsAndSend(ch chan []byte, conn *websocket.Conn) {
	select {
	case message, ok := <-ch:
		if !ok {
			clientExit()
			return
		}

		err := conn.WriteMessage(websocket.TextMessage, message)
		if err != nil {
			clientExit()
		}
	}
}

func clientExit()
