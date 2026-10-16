package main

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"google.golang.org/protobuf/proto"
	"vr.maio-tech.com/server/protocol"
)

func testClient(h *Hub) *Client {
	c := &Client{outgoing: make(chan []byte, 512), closed: make(chan struct{})}
	h.addClient(c)
	return c
}

func packets(t *testing.T, c *Client) []*protocol.ServerPacket {
	t.Helper()
	var result []*protocol.ServerPacket
	for len(c.outgoing) > 0 {
		p := &protocol.ServerPacket{}
		if err := proto.Unmarshal(<-c.outgoing, p); err != nil {
			t.Fatal(err)
		}
		result = append(result, p)
	}
	return result
}

func TestWebSocketOriginPolicy(t *testing.T) {
	t.Setenv("VR_PLATFORM_ALLOWED_ORIGINS", "app.vr.maio-tech.com")
	for _, test := range []struct {
		origin string
		want   bool
	}{
		{"", true},
		{"https://app.vr.maio-tech.com", true},
		{"https://app.vr.maio-tech.com:443", true},
		{"http://app.vr.maio-tech.com", false},
		{"https://example.com", false},
	} {
		r := httptest.NewRequest(http.MethodGet, "http://internal/ws", nil)
		if test.origin != "" {
			r.Header.Set("Origin", test.origin)
		}
		if got := checkWebSocketOrigin(r); got != test.want {
			t.Errorf("origin %q: got %v, want %v", test.origin, got, test.want)
		}
	}
}

func create(h *Hub, c *Client) {
	h.handle(c, &protocol.ClientPacket{Payload: &protocol.ClientPacket_RoomCreate{RoomCreate: &protocol.ClientRoomCreate{}}})
}

func join(h *Hub, c *Client, roomID uint32) {
	h.handle(c, &protocol.ClientPacket{Payload: &protocol.ClientPacket_RoomJoin{RoomJoin: &protocol.ClientRoomJoin{RoomId: roomID}}})
}

func recover(h *Hub, c *Client, roomID, peerID, sessionID uint32) {
	room := &protocol.Room{Id: roomID, Name: "Recovered room", WorldId: "floating_island", RecoveryToken: "test-nonce"}
	room.RecoveryToken = memberToken(room, peerID, sessionID)
	h.handle(c, &protocol.ClientPacket{Payload: &protocol.ClientPacket_RoomJoin{RoomJoin: &protocol.ClientRoomJoin{
		RoomId: roomID, ClientId: peerID, SessionId: sessionID,
		RecoveryRoom: room,
	}}})
}

func TestRoomLifecycle(t *testing.T) {
	h := newHub()
	a, b := testClient(h), testClient(h)
	initial := packets(t, a)
	if len(initial) != 2 || initial[0].GetConnected().GetClientId() != a.id || initial[1].GetRoomList() == nil || a.id <= 1 {
		t.Fatalf("incorrect handshake: %v", initial)
	}
	create(h, a)
	roomID := a.roomID
	packets(t, a)
	packets(t, b)
	join(h, b, roomID)
	got := packets(t, b)
	if len(got) != 2 || got[1].GetRoomJoined().GetRoom().GetId() != roomID || len(got[1].GetRoomJoined().GetPeers()) != 1 || got[1].GetRoomJoined().GetPeers()[0].GetId() != a.id {
		t.Fatalf("incorrect join: %v", got)
	}
	got = packets(t, a)
	if len(got) != 2 || got[0].GetPeerJoined().GetPeer().GetId() != b.id || got[1].GetRoomUpdated().GetRoom().GetPlayerCount() != 2 {
		t.Fatalf("incorrect membership notification: %v", got)
	}
	join(h, b, roomID)
	got = packets(t, b)
	if len(packets(t, a)) != 0 || len(got) != 1 || got[0].GetRoomJoined().GetSessionId() != b.sessionID {
		t.Fatal("duplicate join must acknowledge the existing session")
	}
	join(h, b, roomID+999)
	if b.roomID != roomID || packets(t, b)[0].GetError() == nil {
		t.Fatal("failed join changed membership")
	}
	create(h, b)
	got = packets(t, a)
	if got[0].GetPeerLeft().GetPeerId() != b.id || len(h.rooms[roomID].clients) != 1 {
		t.Fatal("room switch did not remove old membership")
	}
	h.removeClient(a)
	if h.rooms[roomID] != nil || h.clients[a.id] != nil {
		t.Fatal("disconnect did not remove empty room and client")
	}
	h.removeClient(a)
	create(h, a)
	if len(h.rooms) != 1 {
		t.Fatal("disconnected client was allowed to create a room")
	}
}

func TestPeersRecoverMissingRoom(t *testing.T) {
	h := newHub()
	a, b := testClient(h), testClient(h)
	create(h, a)
	join(h, b, a.roomID)
	roomID, aID, bID, aSession, bSession := a.roomID, a.meshID(), b.meshID(), a.sessionID, b.sessionID
	h.removeClient(a)
	h.removeClient(b)
	if h.rooms[roomID] != nil {
		t.Fatal("disconnected room was not removed")
	}

	reconnectedB, reconnectedA := testClient(h), testClient(h)
	packets(t, reconnectedB)
	packets(t, reconnectedA)
	recover(h, reconnectedB, roomID, bID, bSession)
	recover(h, reconnectedA, roomID, aID, aSession)
	if reconnectedA.meshID() != aID || reconnectedB.meshID() != bID || len(h.rooms[roomID].clients) != 2 {
		t.Fatal("peers did not rebuild their room with preserved mesh IDs")
	}
	got := packets(t, reconnectedA)
	joined := got[len(got)-1].GetRoomJoined()
	if joined == nil || joined.SessionId != aSession || len(joined.Peers) != 1 || joined.Peers[0].Id != bID || joined.Peers[0].SessionId != bSession {
		t.Fatalf("recovered membership did not preserve the live mesh: %v", got)
	}
}

func TestRelayIsolation(t *testing.T) {
	h := newHub()
	a, b, outsider := testClient(h), testClient(h), testClient(h)
	create(h, a)
	join(h, b, a.roomID)
	for _, c := range []*Client{a, b, outsider} {
		packets(t, c)
	}
	relay := &protocol.ClientRelay{DestinationId: b.id, SenderSessionId: a.sessionID, DestinationSessionId: b.sessionID, Signal: &protocol.ClientRelay_Description{Description: &protocol.WebRTCSessionDescription{Type: "offer", Sdp: "test sdp"}}}
	request := &protocol.ClientPacket{Payload: &protocol.ClientPacket_Relay{Relay: relay}}
	h.handle(a, request)
	got := packets(t, b)
	if len(got) != 1 || got[0].GetRelay().GetSenderId() != a.id || got[0].GetRelay().GetSenderSessionId() != a.sessionID || got[0].GetRelay().GetDestinationSessionId() != b.sessionID || got[0].GetRelay().GetDescription().GetSdp() != "test sdp" {
		t.Fatalf("incorrect relay: %v", got)
	}
	h.handle(outsider, request)
	if len(packets(t, b)) != 0 || packets(t, outsider)[0].GetError() == nil {
		t.Fatal("cross-room signaling was allowed")
	}
	create(h, a)
	join(h, b, a.roomID)
	packets(t, a)
	packets(t, b)
	h.handle(a, request)
	if len(packets(t, b)) != 0 {
		t.Fatal("signaling from the previous room reached the new connection")
	}
	relay.SenderSessionId = a.sessionID
	relay.DestinationSessionId = b.sessionID
	relay.Signal = nil
	h.handle(a, request)
	if len(packets(t, b)) != 0 || packets(t, a)[0].GetError() == nil {
		t.Fatal("empty signaling was allowed")
	}
}

func TestConcurrentMembership(t *testing.T) {
	h := newHub()
	var wg sync.WaitGroup
	for range 8 {
		wg.Go(func() {
			c := testClient(h)
			for range 10 {
				create(h, c)
				h.handle(c, &protocol.ClientPacket{Payload: &protocol.ClientPacket_RoomLeave{RoomLeave: &protocol.ClientRoomLeave{}}})
			}
			h.removeClient(c)
		})
	}
	wg.Wait()
	if len(h.clients) != 0 || len(h.rooms) != 0 {
		t.Fatal("concurrent requests left stale membership")
	}
}

func TestQueueOverflowDisconnects(t *testing.T) {
	accepted := make(chan *websocket.Conn, 1)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		conn, err := wsUpgrader.Upgrade(w, r, nil)
		if err != nil {
			t.Error(err)
			return
		}
		accepted <- conn
	}))
	defer server.Close()
	remote, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(server.URL, "http"), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer remote.Close()
	c := &Client{conn: <-accepted, outgoing: make(chan []byte, 2), closed: make(chan struct{})}
	hub.addClient(c) // The handshake fills the queue before a writer starts.
	go readPump(c)
	defer c.disconnect()
	// Room replies and broadcasts enqueue while holding hub.mu. Exercise that
	// production path: closing a slow socket must not reacquire the same lock.
	finished := make(chan struct{})
	go func() {
		hub.handle(c, &protocol.ClientPacket{Payload: &protocol.ClientPacket_RoomJoin{
			RoomJoin: &protocol.ClientRoomJoin{RoomId: 999},
		}})
		close(finished)
	}()
	select {
	case <-finished:
	case <-time.After(time.Second):
		t.Fatal("queue overflow blocked the hub")
	}
	select {
	case <-c.closed:
	default:
		t.Fatal("slow client was left connected after losing a packet")
	}
	if c.sendPacket(nil) {
		t.Fatal("closed client accepted a packet")
	}
	deadline := time.Now().Add(time.Second)
	for time.Now().Before(deadline) {
		hub.mu.Lock()
		removed := hub.clients[c.id] == nil
		hub.mu.Unlock()
		if removed {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("socket closure did not clean up hub membership")
}

func TestRoomRequestReplies(t *testing.T) {
	h := newHub()
	c := testClient(h)
	packets(t, c)
	request := &protocol.ClientPacket{RequestId: 42, Payload: &protocol.ClientPacket_RoomJoin{RoomJoin: &protocol.ClientRoomJoin{RoomId: 999}}}
	h.handle(c, request)
	got := packets(t, c)
	if len(got) != 1 || got[0].RequestId != 42 || got[0].GetError() == nil {
		t.Fatalf("failure was not correlated with its request: %v", got)
	}
	request.Payload = &protocol.ClientPacket_RoomCreate{RoomCreate: &protocol.ClientRoomCreate{}}
	h.handle(c, request)
	got = packets(t, c)
	if len(got) != 2 || got[1].RequestId != 42 || got[1].GetRoomJoined().GetSessionId() == 0 {
		t.Fatalf("success was not correlated with its request: %v", got)
	}
}

func TestRejoinInvalidatesBothRelayEndpoints(t *testing.T) {
	h := newHub()
	a, b := testClient(h), testClient(h)
	create(h, a)
	roomID := a.roomID
	join(h, b, roomID)
	relay := &protocol.ClientRelay{
		DestinationId: b.id, SenderSessionId: a.sessionID, DestinationSessionId: b.sessionID,
		Signal: &protocol.ClientRelay_Description{Description: &protocol.WebRTCSessionDescription{Type: "offer", Sdp: "sdp"}},
	}
	request := &protocol.ClientPacket{Payload: &protocol.ClientPacket_Relay{Relay: relay}}
	leave := &protocol.ClientPacket{Payload: &protocol.ClientPacket_RoomLeave{RoomLeave: &protocol.ClientRoomLeave{}}}
	h.handle(b, leave)
	join(h, b, roomID)
	packets(t, a)
	packets(t, b)
	h.handle(a, request)
	if len(packets(t, b)) != 0 {
		t.Fatal("relay targeting an old recipient session was delivered")
	}
	relay.DestinationSessionId = b.sessionID
	h.handle(a, leave)
	join(h, a, roomID)
	packets(t, a)
	packets(t, b)
	h.handle(a, request)
	if len(packets(t, b)) != 0 {
		t.Fatal("relay from an old sender session was delivered")
	}
	relay.SenderSessionId = a.sessionID
	h.handle(a, request)
	if got := packets(t, b); len(got) != 1 || got[0].GetRelay() == nil {
		t.Fatal("current sessions could not relay after rejoining")
	}
}

func TestWorldSelectionAndCapacity(t *testing.T) {
	h := newHub()
	host := testClient(h)
	h.handle(host, &protocol.ClientPacket{Payload: &protocol.ClientPacket_RoomCreate{
		RoomCreate: &protocol.ClientRoomCreate{Name: "  Moon friends  ", WorldId: "moon_garden"},
	}})
	roomID := host.roomID
	room := h.rooms[roomID]
	if room == nil || room.packet().WorldId != "moon_garden" || room.name != "Moon friends" {
		t.Fatal("room did not retain world and normalized name")
	}
	// Validate the destination before leaving the current room.
	h.handle(host, &protocol.ClientPacket{Payload: &protocol.ClientPacket_RoomCreate{
		RoomCreate: &protocol.ClientRoomCreate{WorldId: "res://untrusted.tscn"},
	}})
	if host.roomID != roomID {
		t.Fatal("unknown world removed existing membership")
	}
	got := packets(t, host)
	if got[len(got)-1].GetError() == nil {
		t.Fatal("unknown world was not rejected")
	}
	for i := 1; i < maxRoomPlayers; i++ {
		member := testClient(h)
		join(h, member, roomID)
		replies := packets(t, member)
		joined := replies[len(replies)-1].GetRoomJoined()
		if joined == nil || joined.Room.WorldId != "moon_garden" {
			t.Fatal("joining client did not receive the room world")
		}
	}
	extra := testClient(h)
	create(h, extra)
	originalRoom := extra.roomID
	packets(t, extra)
	join(h, extra, roomID)
	got = packets(t, extra)
	if extra.roomID != originalRoom || len(room.clients) != maxRoomPlayers || got[len(got)-1].GetError() == nil {
		t.Fatal("full room should reject entry and preserve previous membership")
	}
	legacy := testClient(h)
	create(h, legacy)
	if h.rooms[legacy.roomID].worldID != "floating_island" {
		t.Fatal("omitted world must select the default world")
	}
}

func TestStarlightObservatoryIsSupported(t *testing.T) {
	h := newHub()
	host := testClient(h)
	h.handle(host, &protocol.ClientPacket{Payload: &protocol.ClientPacket_RoomCreate{
		RoomCreate: &protocol.ClientRoomCreate{Name: "Stargazers", WorldId: "starlight_observatory"},
	}})
	room := h.rooms[host.roomID]
	if room == nil || room.worldID != "starlight_observatory" {
		t.Fatal("starlight observatory room was not created")
	}
}

func TestMoonlitGrottoIsSupported(t *testing.T) {
	h := newHub()
	host := testClient(h)
	h.handle(host, &protocol.ClientPacket{Payload: &protocol.ClientPacket_RoomCreate{
		RoomCreate: &protocol.ClientRoomCreate{Name: "Grotto", WorldId: "moonlit_grotto"},
	}})
	room := h.rooms[host.roomID]
	if room == nil || room.worldID != "moonlit_grotto" {
		t.Fatal("moonlit grotto room was not created")
	}
}

func TestSignalingDisconnectIsNotExplicitPeerLeave(t *testing.T) {
	h := newHub()
	a, b, c := testClient(h), testClient(h), testClient(h)
	create(h, a)
	join(h, b, a.roomID)
	join(h, c, a.roomID)
	packets(t, a)
	h.removeClient(b)
	got := packets(t, a)
	if len(got) < 1 || got[0].GetPeerLeft() == nil || !got[0].GetPeerLeft().SignalingDisconnected {
		t.Fatal("signaling loss must be distinguished from leaving the P2P session")
	}
	h.handle(c, &protocol.ClientPacket{Payload: &protocol.ClientPacket_RoomLeave{RoomLeave: &protocol.ClientRoomLeave{}}})
	got = packets(t, a)
	if len(got) < 1 || got[0].GetPeerLeft() == nil || got[0].GetPeerLeft().SignalingDisconnected {
		t.Fatal("explicit leave must still remove the peer")
	}
}

func TestLateCandidateAfterSignalingDisconnect(t *testing.T) {
	h := newHub()
	a, b := testClient(h), testClient(h)
	create(h, a)
	join(h, b, a.roomID)
	oldSession := b.sessionID
	h.removeClient(b)
	packets(t, a)
	h.handle(a, &protocol.ClientPacket{Payload: &protocol.ClientPacket_Relay{Relay: &protocol.ClientRelay{
		DestinationId: b.id, SenderSessionId: a.sessionID, DestinationSessionId: oldSession,
		Signal: &protocol.ClientRelay_Candidate{Candidate: &protocol.WebRTCIceCandidate{Candidate: "late"}},
	}}})
	if len(packets(t, a)) != 0 {
		t.Fatal("in-flight candidate for a disconnected peer should be discarded quietly")
	}
}

func TestFreshServerRecoveryReservesIdentities(t *testing.T) {
	h := newHub()
	survivor := testClient(h)
	recover(h, survivor, 9, 3, 1)
	newcomer := testClient(h)
	join(h, newcomer, 9)
	if newcomer.meshID() == survivor.meshID() || len(h.rooms[9].clients) != 2 || h.rooms[9].clients[3] != survivor {
		t.Fatal("new member overwrote recovered peer")
	}
	oldSession := survivor.sessionID
	reply := h.createRoom(survivor, "Another world", "moon_garden")
	if reply.GetRoomJoined() == nil || reply.GetRoomJoined().SessionId == oldSession {
		t.Fatal("new membership reused recovered session")
	}
}

func TestRecoveryRejectsReusedRoomID(t *testing.T) {
	for _, sameWorld := range []bool{false, true} {
		h := newHub()
		newcomer := testClient(h)
		create(h, newcomer)
		survivor := testClient(h)
		original := h.rooms[newcomer.roomID]
		world := "moon_garden"
		if sameWorld {
			world = original.worldID
		}
		claim := &protocol.Room{Id: original.id, Name: original.name, WorldId: world, RecoveryToken: "old-incarnation"}
		claim.RecoveryToken = memberToken(claim, 8, 40)
		reply := h.joinRoom(survivor, &protocol.ClientRoomJoin{
			RoomId: original.id, ClientId: 8, SessionId: 40,
			RecoveryRoom: claim,
		})
		if reply.GetError() == nil || survivor.roomID != 0 || len(original.clients) != 1 {
			t.Fatal("recovery attached to unrelated room with reused ID")
		}
	}
}

func TestRecoveryRejectsOccupiedPeerIdentity(t *testing.T) {
	h := newHub()
	occupied := testClient(h)
	create(h, occupied)
	survivor := testClient(h)
	claim := &protocol.Room{Id: 9, Name: "Surviving room", WorldId: "moon_garden", RecoveryToken: "surviving"}
	claim.RecoveryToken = memberToken(claim, occupied.meshID(), 40)
	reply := h.joinRoom(survivor, &protocol.ClientRoomJoin{
		RoomId: 9, ClientId: occupied.meshID(), SessionId: 40,
		RecoveryRoom: claim,
	})
	if reply.GetError() == nil || h.rooms[9] != nil {
		t.Fatal("recovery accepted an already allocated peer ID")
	}
}

func TestRecoveredRoomTokenSurvivesFreshHub(t *testing.T) {
	old := newHub()
	a, b := testClient(old), testClient(old)
	create(old, a)
	join(old, b, a.roomID)
	room := old.rooms[a.roomID].packet()
	h := newHub()
	for _, original := range []*Client{b, a} {
		reconnect := testClient(h)
		reply := h.joinRoom(reconnect, &protocol.ClientRoomJoin{RoomId: room.Id, ClientId: original.meshID(), SessionId: original.sessionID, RecoveryRoom: old.rooms[room.Id].memberPacket(original)})
		if reply.GetRoomJoined() == nil || reply.GetRoomJoined().Room.RecoveryToken != old.rooms[room.Id].memberPacket(original).RecoveryToken {
			t.Fatal("fresh hub did not restore room token and peer")
		}
	}
	if len(h.rooms[room.Id].clients) != 2 {
		t.Fatal("missing recovered member")
	}
}

func TestTurnCredentialsDisabledWithoutConfig(t *testing.T) {
	saved := turn
	turn = turnConfig{}
	defer func() { turn = saved }()
	if mintTurnCredentials(time.Now(), 7) != nil {
		t.Fatal("credentials minted without a shared secret")
	}
	h := newHub()
	a := testClient(h)
	packets(t, a)
	create(h, a)
	for _, p := range packets(t, a) {
		if joined := p.GetRoomJoined(); joined != nil && joined.GetTurn() != nil {
			t.Fatal("join reply carried TURN credentials with no relay configured")
		}
	}
}

func TestTurnCredentialsMintAndJoin(t *testing.T) {
	saved := turn
	turn = turnConfig{secret: "test-shared-secret", urls: []string{"turn:turn.example:3478"}, ttl: 24 * time.Hour}
	defer func() { turn = saved }()
	now := time.Now()
	creds := mintTurnCredentials(now, 7)
	if creds == nil {
		t.Fatal("no credentials minted with relay configured")
	}
	var expiry int64
	var clientID uint32
	if _, err := fmt.Sscanf(creds.GetUsername(), "%d:%d", &expiry, &clientID); err != nil {
		t.Fatalf("username %q is not expiry:clientID: %v", creds.GetUsername(), err)
	}
	if clientID != 7 || expiry < now.Add(23*time.Hour).Unix() || expiry > now.Add(25*time.Hour).Unix() {
		t.Fatalf("bad username scope: %q", creds.GetUsername())
	}
	if creds.GetTtl() != 24*3600 || len(creds.GetUrls()) != 1 {
		t.Fatalf("bad credential scope: ttl=%d urls=%v", creds.GetTtl(), creds.GetUrls())
	}
	mac := hmac.New(sha1.New, []byte("test-shared-secret"))
	mac.Write([]byte(creds.GetUsername()))
	if base64.StdEncoding.EncodeToString(mac.Sum(nil)) != creds.GetPassword() {
		t.Fatal("password is not HMAC-SHA1(secret, username)")
	}
	h := newHub()
	a := testClient(h)
	packets(t, a)
	create(h, a)
	found := false
	for _, p := range packets(t, a) {
		if joined := p.GetRoomJoined(); joined != nil && joined.GetTurn() != nil {
			found = true
			if joined.GetTurn().GetUsername() == "" || joined.GetTurn().GetPassword() == "" {
				t.Fatal("join reply carried empty TURN credentials")
			}
		}
	}
	if !found {
		t.Fatal("join reply carried no TURN credentials with relay configured")
	}
}

func TestRecoveryCapabilityRejectsForgery(t *testing.T) {
	old := newHub()
	member := testClient(old)
	create(old, member)
	room := old.rooms[member.roomID]
	for _, token := range []string{room.recoveryToken, room.memberPacket(member).RecoveryToken} {
		fresh := newHub()
		attacker := testClient(fresh)
		claim := room.packet()
		claim.RecoveryToken = token
		reply := fresh.joinRoom(attacker, &protocol.ClientRoomJoin{RoomId: room.id, ClientId: member.meshID() + 10, SessionId: member.sessionID, RecoveryRoom: claim})
		if reply.GetError() == nil || len(fresh.rooms) != 0 {
			t.Fatal("forged recovery mutated fresh hub")
		}
	}
}

func TestMembershipMintQuota(t *testing.T) {
	h := newHub()
	c := testClient(h)
	for i := 0; i < 20; i++ {
		if h.createRoom(c, "quota").GetRoomJoined() == nil {
			t.Fatal("unexpected admission failure")
		}
	}
	if h.createRoom(c, "quota").GetError() == nil {
		t.Fatal("mint quota bypassed")
	}
}
