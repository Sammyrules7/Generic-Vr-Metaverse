package main

import (
	"fmt"
	"net/http"
)

func main() {
	http.HandleFunc("/ws", wsConnected)

	fmt.Print("Starting server.\n")

	err := http.ListenAndServe(":8080", nil)
	if err != nil {
		fmt.Printf("Server failed to start: %s\n", err)
		return
	}
}
