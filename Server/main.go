package main

import (
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/gorilla/websocket"
)

var wsUpgrader = websocket.Upgrader{}

func main() {

	http.HandleFunc("/ws", handleWsConn)

	address := os.Getenv("VR_PLATFORM_LISTEN_ADDR")
	if address == "" {
		address = ":8080"
	}
	fmt.Printf("Starting server on %s\n", address)

	err := http.ListenAndServe(address, nil)
	if err != nil {
		log.Fatalf("HTTP server failed: %s", err)
	}
}

func handleWsConn(w http.ResponseWriter, r *http.Request) {
	fmt.Printf("Conn recived!\n")

	wsConn, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		fmt.Printf("Error upgrading WebSocket: %s\n", err)
		return
	}
	wsConn.SetReadLimit(256 * 1024)

	initClient(wsConn)

}
