package main

import (
	"encoding/json"
	"fmt"
	"math/rand/v2"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
)

type PacketType string

const (
	TypeOffer     PacketType = "offer"
	TypeAnswer    PacketType = "answer"
	TypeCandidate PacketType = "candidate"
	TypeJoin      PacketType = "join_room"
	TypeCreate    PacketType = "create_room"
	TypeCreated   PacketType = "room_created"
	TypeGeneric   PacketType = "generic"
)

type DataPacket struct {
	Type     PacketType      `json:"type"`
	SenderID int32           `json:"sender"`
	TargetID int32           `json:"target"`
	Payload  json.RawMessage `json:"payload"`
}

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
	wsConn.WriteJSON(Packet{
		Type: "Init",
		Data: id,
	})
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

	// Check packet loop
	for {
		_, p, err := wsConn.ReadMessage()
		if err != nil {
			fmt.Printf("And error occured in the websocket connection: %s\n", err)
			break
		}

		handlePacket(p, id)
	}

}

func handlePacket(contents []byte, id int32) {
	var packetJson DataPacket
	var err error = json.Unmarshal(contents, &packetJson)
	if err != nil {
		fmt.Printf("Json parsing error: %s\n", err)
	}

	fmt.Printf("Packet recived from %d. Contents: %s\n", id, string(contents))

	switch packetJson.Type {
	case TypeGeneric:
		fmt.Printf("Generic Packet from %s contain: %s\n", string(packetJson.SenderID), packetJson.Payload)
	case TypeCreate:
		fmt.Printf("Room Created\n")
	default:
		fmt.Printf("An error occured matching packet\n")
	}
}

type Packet struct {
	Type string `json:"type"`
	Data any    `json:"data"`
}
