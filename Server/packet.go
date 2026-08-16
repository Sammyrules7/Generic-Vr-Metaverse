package main

type Packet struct {
	Sender uint32
	Type   int
	Data   any
}

const (
	PacketDirect = iota
	PacketInit
	PacketCreateRoom
)
