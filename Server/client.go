package main

import "github.com/gorilla/websocket"

type Client struct {
	Id   uint32
	Chan chan Packet
	Conn websocket.Conn
}
