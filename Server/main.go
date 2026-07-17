package main

import (
	"encoding/json"
	"log"
	"math/rand"
	"net/http"
	"sync"

	"github.com/gorilla/websocket"
)

// Message is the JSON payload exchanged between clients and the signaling server
type Message struct {
	Type     string      `json:"type"`
	SenderID int32       `json:"sender_id"`
	TargetID int32       `json:"target_id"`
	Data     interface{} `json:"data"`
}

// Client represents an active player's signaling connection
type Client struct {
	ID   int32
	Conn *websocket.Conn
	Send chan []byte
}

func (c *Client) writePump() {
	defer c.Conn.Close()
	for message := range c.Send {
		err := c.Conn.WriteMessage(websocket.TextMessage, message)
		if err != nil {
			log.Printf("Error writing to client %d: %v", c.ID, err)
			return
		}
	}
}

func (c *Client) readPump(lobby *Lobby) {
	defer func() {
		lobby.Unregister(c.ID)
		c.Conn.Close()
	}()
	for {
		_, message, err := c.Conn.ReadMessage()
		if err != nil {
			break
		}
		lobby.HandleMessage(c.ID, message)
	}
}

// Lobby manages all connected clients in a single global space
type Lobby struct {
	clients map[int32]*Client
	mu      sync.RWMutex
}

func NewLobby() *Lobby {
	return &Lobby{
		clients: make(map[int32]*Client),
	}
}

func (l *Lobby) Register(conn *websocket.Conn) {
	l.mu.Lock()

	// Generate a unique non-zero 32-bit ID (required by Godot)
	var id int32
	for {
		id = rand.Int31() // Positve int32
		if id > 0 {
			if _, exists := l.clients[id]; !exists {
				break
			}
		}
	}

	client := &Client{
		ID:   id,
		Conn: conn,
		Send: make(chan []byte, 256),
	}
	l.clients[id] = client
	l.mu.Unlock()

	go client.writePump()

	// Gather all existing peers
	l.mu.RLock()
	existingPeers := []int32{}
	for peerID := range l.clients {
		if peerID != id {
			existingPeers = append(existingPeers, peerID)
		}
	}
	l.mu.RUnlock()

	// 1. Tell the new client their ID and provide list of current peers
	initMsg := Message{
		Type:     "id",
		SenderID: id,
		Data:     existingPeers,
	}
	initBytes, _ := json.Marshal(initMsg)
	client.Send <- initBytes

	// 2. Broadcast "peer_joined" to everyone else
	joinMsg := Message{
		Type:     "peer_joined",
		SenderID: id,
	}
	joinBytes, _ := json.Marshal(joinMsg)

	l.mu.RLock()
	for _, peer := range l.clients {
		if peer.ID != id {
			peer.Send <- joinBytes
		}
	}
	l.mu.RUnlock()

	log.Printf("Client %d connected. Lobby size: %d", id, len(existingPeers)+1)

	// Start reading loops
	client.readPump(l)
}

func (l *Lobby) Unregister(id int32) {
	l.mu.Lock()
	client, exists := l.clients[id]
	if !exists {
		l.mu.Unlock()
		return
	}
	delete(l.clients, id)
	close(client.Send)
	l.mu.Unlock()

	// Broadcast disconnect
	leaveMsg := Message{
		Type:     "peer_left",
		SenderID: id,
	}
	leaveBytes, _ := json.Marshal(leaveMsg)

	l.mu.RLock()
	for _, peer := range l.clients {
		peer.Send <- leaveBytes
	}
	l.mu.RUnlock()

	log.Printf("Client %d disconnected. Lobby size: %d", id, len(l.clients))
}

func (l *Lobby) HandleMessage(senderID int32, data []byte) {
	var msg Message
	if err := json.Unmarshal(data, &msg); err != nil {
		log.Println("Error unmarshaling message:", err)
		return
	}

	// Force correct sender ID for security
	msg.SenderID = senderID

	// Directly relay SDP Offers, Answers, and ICE Candidates to target
	if msg.Type == "offer" || msg.Type == "answer" || msg.Type == "candidate" {
		l.mu.RLock()
		target, exists := l.clients[msg.TargetID]
		l.mu.RUnlock()

		if exists {
			payload, _ := json.Marshal(msg)
			target.Send <- payload
		}
	}
}

var upgrader = websocket.Upgrader{
	ReadBufferSize:  2048,
	WriteBufferSize: 2048,
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow development environments
	},
}

func main() {
	lobby := NewLobby()

	http.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Println("WebSocket Upgrade failed:", err)
			return
		}
		lobby.Register(conn)
	})

	log.Println("WebRTC Signaling Server online on :8080...")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatal(err)
	}
}
