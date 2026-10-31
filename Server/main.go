package main

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/gorilla/websocket"
)

// signalingProtocol is the build token for the signaling/WebRTC control plane.
// Bump it for any incompatible change to packet framing, room admission, or
// WebRTC channel layouts or gameplay RPC signatures. Older clients cannot join a newer server (and vice versa)
// instead of failing later during SDP/ICE or RPC.
const signalingProtocol = "vr-platform-v2"

var wsUpgrader = websocket.Upgrader{
	CheckOrigin:  checkWebSocketOrigin,
	Subprotocols: []string{signalingProtocol},
}

func acceptsSignalingProtocol(r *http.Request) bool {
	for _, protocol := range websocket.Subprotocols(r) {
		if protocol == signalingProtocol {
			return true
		}
	}
	return false
}

func checkWebSocketOrigin(r *http.Request) bool {
	origin := r.Header.Get("Origin")
	if origin == "" {
		// Native Godot clients do not send a browser Origin header.
		return true
	}

	parsed, err := url.Parse(origin)
	if err != nil || parsed.Scheme != "https" {
		return false
	}

	allowed := os.Getenv("VR_PLATFORM_ALLOWED_ORIGINS")
	if allowed == "" {
		allowed = "app.vr.maio-tech.com,vr.maio-tech.com"
	}
	for _, host := range strings.Split(allowed, ",") {
		if strings.EqualFold(parsed.Hostname(), strings.TrimSpace(host)) {
			return true
		}
	}
	return false
}

func main() {

	http.HandleFunc("/ws", handleWsConn)

	address := os.Getenv("VR_PLATFORM_LISTEN_ADDR")
	if address == "" {
		address = ":8080"
	}
	server := &http.Server{
		Addr:              address,
		ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    16 * 1024,
	}
	listener, err := net.Listen("tcp", address)
	if err != nil {
		log.Fatalf("HTTP server failed: %s", err)
	}
	fmt.Printf("Starting server on %s\n", listener.Addr())
	err = server.Serve(listener)
	if err != nil {
		log.Fatalf("HTTP server failed: %s", err)
	}
}

func handleWsConn(w http.ResponseWriter, r *http.Request) {
	// Reject mixed builds at the HTTP handshake, before the socket is upgraded,
	// admitted to the hub, or able to exchange room signaling and WebRTC data.
	if !acceptsSignalingProtocol(r) {
		w.Header().Set("Sec-WebSocket-Protocol", signalingProtocol)
		http.Error(w, "unsupported signaling protocol; this server requires "+signalingProtocol, http.StatusUpgradeRequired)
		return
	}

	wsConn, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		fmt.Printf("Error upgrading WebSocket: %s\n", err)
		return
	}
	wsConn.SetReadLimit(256 * 1024)

	initClient(wsConn)

}
