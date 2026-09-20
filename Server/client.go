package main

import (
	"fmt"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const (
	writeWait        = 10 * time.Second
	pongWait         = 60 * time.Second
	pingPeriod       = pongWait / 2
	packetBurst      = 200.0
	packetsPerSecond = 100.0
)

// Each limiter belongs to one client's read pump; no locking is needed.
type rateLimit struct {
	tokens  float64
	updated time.Time
}

func (limit *rateLimit) allow(rate, burst float64) bool {
	now := time.Now()
	if limit.updated.IsZero() {
		limit.tokens = burst
	} else {
		limit.tokens = min(burst, limit.tokens+now.Sub(limit.updated).Seconds()*rate)
	}
	limit.updated = now
	if limit.tokens < 1 {
		return false
	}
	limit.tokens--
	return true
}

type Client struct {
	id           uint32      // Godot multiplayer peer ID; assigned before pumps start.
	outgoing     chan []byte // Do not use directly, use Client.sendPacket()
	closed       chan struct{}
	conn         *websocket.Conn
	close        sync.Once
	roomID       uint32    // guarded by hub.mu
	sessionID    uint32    // guarded by hub.mu; renewed on every room entry
	roomCommands rateLimit // owned by the read pump
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
	defer func() {
		client.disconnect()
		hub.removeClient(client)
	}()
	client.conn.SetReadDeadline(time.Now().Add(pongWait))
	client.conn.SetPongHandler(func(string) error {
		return client.conn.SetReadDeadline(time.Now().Add(pongWait))
	})
	// Signaling is low-volume; bound floods before decoding or taking hub.mu.
	var packets rateLimit
	for {
		messageType, packet, err := client.conn.ReadMessage()
		if err != nil {
			return
		}
		if !packets.allow(packetsPerSecond, packetBurst) {
			return
		}
		if messageType != websocket.BinaryMessage {
			return
		}

		handlePacket(packet, client)
	}
}

func writePump(client *Client) {
	// One writer owns socket writes. Hub operations only enqueue bytes, so a slow
	// connection cannot hold up every client's membership changes.
	defer client.disconnect()
	ticker := time.NewTicker(pingPeriod)
	defer ticker.Stop()
	for {
		select {
		case <-client.closed:
			return
		case <-ticker.C:
			if err := client.conn.WriteControl(websocket.PingMessage, nil, time.Now().Add(writeWait)); err != nil {
				return
			}
		case message := <-client.outgoing:

			client.conn.SetWriteDeadline(time.Now().Add(writeWait))
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
		fmt.Printf("Client %d exited\n", client.id)
	})
}
