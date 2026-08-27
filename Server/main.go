package main

import (
	"fmt"
	"net/http"
	_ "net/http/pprof"

	"github.com/gorilla/websocket"
)

var wsUpgrader = websocket.Upgrader{}

func main() {

	http.HandleFunc("/ws", handleWsConn)

	fmt.Printf("Starting server on :8080\n")

	err := http.ListenAndServe(":8080", nil)
	if err != nil {
		fmt.Printf("Http server failed with error: %s\n", err)
	}
}

func handleWsConn(w http.ResponseWriter, r *http.Request) {
	fmt.Printf("Conn recived!\n")

	wsConn, err := wsUpgrader.Upgrade(w, r, nil)
	if err != nil {
		fmt.Printf("Error upgrading WebSocket: %s\n", err)
		return
	}

	initClient(wsConn)

}
