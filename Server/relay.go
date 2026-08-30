package main

import "vr.maio-tech.com/server/protocol"

const maxRelayBytes = 128 * 1024

// relay treats signaling as opaque bytes. Its only policy is that both peers
// must currently belong to the same room.
func (h *Hub) relay(sender *Client, relay *protocol.ClientRelay) {
	if len(relay.Value) == 0 || len(relay.Value) > maxRelayBytes {
		sendError(sender, "invalid relay payload")
		return
	}

	h.mu.RLock()
	room := h.rooms[sender.roomID]
	var destination *Client
	if room != nil && relay.DestinationId != sender.id {
		destination = room.clients[relay.DestinationId]
	}
	h.mu.RUnlock()
	if destination == nil {
		sendError(sender, "relay destination is not in your room")
		return
	}

	send(destination, &protocol.ServerPacket{Payload: &protocol.ServerPacket_Relay{
		Relay: &protocol.ServerRelay{SenderId: sender.id, Value: relay.Value},
	}})
}
