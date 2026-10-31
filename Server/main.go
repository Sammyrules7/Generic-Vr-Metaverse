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

var wsUpgrader = websocket.Upgrader{CheckOrigin: checkWebSocketOrigin}

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
	wsConn, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		fmt.Printf("Error upgrading WebSocket: %s\n", err)
		return
	}
	wsConn.SetReadLimit(256 * 1024)

	initClient(wsConn)

}
