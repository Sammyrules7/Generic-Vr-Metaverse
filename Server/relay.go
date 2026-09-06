package main

import "vr.maio-tech.com/server/protocol"

const (
	maxSDPBytes       = 128 * 1024
	maxCandidateBytes = 16 * 1024
)

func (h *Hub) relay(sender *Client, relay *protocol.ClientRelay) {
	room := h.rooms[sender.roomID]
	if room == nil || relay.DestinationId == sender.id {
		sendError(sender, "relay destination is not in your room")
		return
	}
	// Either endpoint may have left and rejoined while signaling was in flight.
	// Stale sessions are expected during transitions, so discard them quietly.
	if relay.SenderSessionId != sender.sessionID {
		return
	}
	destination := room.clients[relay.DestinationId]
	if destination == nil {
		sendError(sender, "relay destination is not in your room")
		return
	}
	if relay.DestinationSessionId != destination.sessionID {
		return
	}

	forwarded := &protocol.ServerRelay{SenderId: sender.id, SenderSessionId: sender.sessionID, DestinationSessionId: destination.sessionID}
	switch signal := relay.Signal.(type) {
	case *protocol.ClientRelay_Description:
		description := signal.Description
		if description == nil || (description.Type != "offer" && description.Type != "answer") ||
			description.Sdp == "" || len(description.Sdp) > maxSDPBytes {
			sendError(sender, "invalid session description")
			return
		}
		forwarded.Signal = &protocol.ServerRelay_Description{Description: description}
	case *protocol.ClientRelay_Candidate:
		candidate := signal.Candidate
		if candidate == nil || len(candidate.Candidate) > maxCandidateBytes {
			sendError(sender, "invalid ICE candidate")
			return
		}
		forwarded.Signal = &protocol.ServerRelay_Candidate{Candidate: candidate}
	default:
		sendError(sender, "relay has no signal")
		return
	}

	send(destination, relayPacket(forwarded))
}
