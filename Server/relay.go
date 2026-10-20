package main

import "vr.maio-tech.com/server/protocol"

const (
	maxSDPBytes       = 128 * 1024
	maxCandidateBytes = 16 * 1024
)

func (h *Hub) relay(sender *Client, relay *protocol.ClientRelay) {
	h.mu.RLock()
	room := h.rooms[sender.roomID]
	senderRoom := sender.roomID
	senderSession := sender.sessionID
	senderMesh := sender.meshID()
	var destination *Client
	var destSession uint32
	if room != nil {
		destination = room.clients[relay.DestinationId]
		if destination != nil {
			destSession = destination.sessionID
		}
	}
	h.mu.RUnlock()
	if room == nil || relay.DestinationId == senderMesh {
		sendError(sender, "relay destination is not in your room")
		return
	}
	// Either endpoint may have left and rejoined while signaling was in flight.
	// Stale sessions are expected during transitions, so discard them quietly.
	// Membership was snapshotted under RLock; re-checking the live client
	// without the lock would race with join/leave.
	_ = senderRoom
	if relay.SenderSessionId != senderSession {
		return
	}
	// A candidate can cross the peer-loss notification in flight. Discard it
	// when the recipient disconnected or changed sessions; healthy P2P traffic
	// must not turn a control-plane race into a fatal application error.
	if destination == nil {
		return
	}
	if relay.DestinationSessionId != destSession {
		return
	}

	forwarded := &protocol.ServerRelay{SenderId: senderMesh, SenderSessionId: senderSession, DestinationSessionId: destSession}
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
