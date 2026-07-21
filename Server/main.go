package main

import (
	"fmt"
	"math/rand/v2"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
)

type Client struct {
	ID   int32
	Conn *websocket.Conn
}

var Clients = make(map[int32]*Client)
var ClientMu = sync.RWMutex{}

var wsUpgrader = websocket.Upgrader{}

func main() {
	http.HandleFunc("/ws", wsConnected)

	fmt.Print("Starting server.\n")

	err := http.ListenAndServe(":8080", nil)
	if err != nil {
		fmt.Printf("Server failed to start: %s\n", err)
		return
	}
}

func wsConnected(w http.ResponseWriter, r *http.Request) {

	// Upgrade Connection
	wsConn, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		fmt.Printf("Error: Websocket failed to upgrade: %s\n", err)
		return
	}

	// Add to player list
	id := rand.Int32()
	fmt.Printf("Client %d connected!\n", id)

	ClientMu.Lock()
	Clients[id] = &Client{
		ID:   id,
		Conn: wsConn,
	}
	ClientMu.Unlock()

	defer func() {
		fmt.Printf("Client %d disconnected\n", id)
		ClientMu.Lock()
		delete(Clients, id)
		ClientMu.Unlock()
		wsConn.Close()
	}()

}
