package main

import (
	"fmt"
	"math/rand/v2"
	"net/http"

	"github.com/gorilla/websocket"
)

type Client struct {
	ID   int32
	Conn *websocket.Conn
}

var Clients = make(map[int32]*Client)

var wsUpgrader = websocket.Upgrader{}

func main() {
	http.HandleFunc("/ws", ws_connection)

	http.ListenAndServe(":8080", nil)
}

func ws_connection(w http.ResponseWriter, r *http.Request) {
	fmt.Println("Connected!")

	wsConn, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		fmt.Printf("Error: Websocket failed to upgrade: %s", err)
	}

	// Add to player list
	id := rand.Int32()
	Clients[id] = &Client{
		ID:   id,
		Conn: wsConn,
	}

}
