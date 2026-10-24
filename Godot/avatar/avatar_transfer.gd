class_name AvatarTransfer
extends Node
## Reliable, bounded avatar-byte transfer on a separate WebRTC channel.
## Peers may request only the owner's currently equipped custom asset.
signal avatar_ready(peer_id: int, id: String)
signal avatar_failed(peer_id: int, id: String, reason: String)
const CHUNK_BYTES := 12 * 1024
const WINDOW_BYTES := 192 * 1024
const MAX_RECEIVES := 2
const MAX_SENDS := 32
const IDLE_TIMEOUT_MS := 20000
const TOTAL_TIMEOUT_MS := 300000
var equipped_id: Callable
var _wanted := {}
var _incoming := {}
var _outgoing := {}
var _serial := 0
var _source_job: AvatarAssetJob
var _source_id := ""
var _source_bytes := PackedByteArray()
var _send_cursor := 0
var received_bytes_total := 0
var completed_transfers := 0

func _ready() -> void:
	multiplayer.peer_disconnected.connect(_drop_peer)

func ensure(peer: int, id: String, force_transfer := false) -> void:
	if not AvatarLocalLibrary.valid_id(id):
		return
	if _wanted.get(peer, "") == id and _incoming.has(peer):
		return
	cancel_receive(peer)
	_wanted[peer] = id
	if not force_transfer and AvatarService.remote_available(id):
		avatar_ready.emit(peer, id)
		_wanted.erase(peer)
		return
	AvatarService.record_event(id, "P2P queued", "owner %d" % peer)
	_start_waiting()

func cancel_receive(peer: int) -> void:
	_wanted.erase(peer)
	if _incoming.has(peer):
		var state: Dictionary = _incoming[peer]
		if multiplayer.get_peers().has(peer):
			cancel_transfer.rpc_id(peer, state.nonce)
		_incoming.erase(peer)

func _start_waiting() -> void:
	for peer in _wanted.keys():
		if _incoming.size() >= MAX_RECEIVES:
			return
		if _incoming.has(peer) or not multiplayer.get_peers().has(peer):
			continue
		var id: String = _wanted[peer]
		# Share one download among peers wearing identical content.
		var already_fetching := false
		for state: Dictionary in _incoming.values():
			if state.id == id:
				already_fetching = true
		if already_fetching:
			continue
		_serial += 1
		var now := Time.get_ticks_msec()
		_incoming[peer] = {"id": id, "nonce": _serial, "total": 0, "received": 0, "chunks": [], "phase": "waiting for offer", "start": now, "last": now, "reported": 0}
		request_avatar.rpc_id(peer, id, _serial)
		AvatarService.record_event(id, "P2P requesting", "owner %d" % peer)

@rpc("any_peer", "call_remote", "reliable", 2)
func request_avatar(id: String, nonce: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(peer) or not AvatarLocalLibrary.valid_id(id) or nonce <= 0:
		return
	var current := str(equipped_id.call()) if equipped_id.is_valid() else ""
	if id != current or not AvatarCatalog.is_owned(id):
		reject_avatar.rpc_id(peer, nonce, "Owner is no longer wearing this avatar")
		return
	if not _outgoing.has(peer) and _outgoing.size() >= MAX_SENDS:
		reject_avatar.rpc_id(peer, nonce, "Avatar upload queue is full")
		return
	if _outgoing.has(peer) and _outgoing[peer].nonce == nonce:
		return
	_outgoing[peer] = {"id": id, "nonce": nonce, "sent": 0, "acked": 0, "offered": false, "last": Time.get_ticks_msec(), "start": Time.get_ticks_msec()}
	AvatarService.record_event(id, "P2P upload requested", "peer %d" % peer)

@rpc("any_peer", "call_remote", "reliable", 2)
func offer_avatar(id: String, nonce: int, total: int, title: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not _matches(peer, id, nonce):
		return
	var state: Dictionary = _incoming[peer]
	if state.phase != "waiting for offer":
		return
	if total < 28 or total > AvatarCustomJob.MAX_BYTES or title.length() > 80:
		_fail_receive(peer, "Invalid avatar offer or file exceeds 32 MiB")
		return
	state.total = total
	state.title = title
	state.phase = "receiving"
	state.last = Time.get_ticks_msec()
	AvatarService.record_event(id, "P2P receiving", "%d bytes from %d" % [total, peer])

@rpc("any_peer", "call_remote", "reliable", 2)
func avatar_chunk(id: String, nonce: int, offset: int, bytes: PackedByteArray) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not _matches(peer, id, nonce):
		return
	var state: Dictionary = _incoming[peer]
	if state.phase != "receiving":
		return
	if offset != state.received or bytes.is_empty() or bytes.size() > CHUNK_BYTES or bytes.size() > state.total - state.received:
		_fail_receive(peer, "Invalid avatar chunk offset or length")
		return
	state.chunks.append(bytes)
	state.received += bytes.size()
	state.last = Time.get_ticks_msec()
	received_bytes_total += bytes.size()
	acknowledge.rpc_id(peer, nonce, state.received)
	var progress := int(state.received * 4 / state.total)
	if progress > state.reported:
		state.reported = progress
		AvatarService.record_event(id, "P2P progress", "%d / %d bytes" % [state.received, state.total])
	if state.received == state.total:
		state.phase = "validating and importing"
		_finish_receive(peer, id, nonce, state)

func _finish_receive(peer: int, id: String, nonce: int, state: Dictionary) -> void:
	var chunks: Array[PackedByteArray] = []
	chunks.assign(state.chunks)
	state.chunks = []
	AvatarService.receive_remote_chunks(id, chunks, state.total, state.title, _received_result.bind(peer, id, nonce))

func _received_result(result: Dictionary, peer: int, id: String, nonce: int) -> void:
	if not _matches(peer, id, nonce):
		return
	if not str(result.get("error", "")).is_empty():
		_fail_receive(peer, str(result.error))
		return
	_incoming.erase(peer)
	completed_transfers += 1
	AvatarService.record_event(id, "P2P ready", "SHA-256 and VRM checks passed")
	for owner in _wanted.keys():
		if _wanted[owner] == id:
			_wanted.erase(owner)
			avatar_ready.emit(owner, id)
	_start_waiting()

@rpc("any_peer", "call_remote", "reliable", 2)
func acknowledge(nonce: int, received: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not _outgoing.has(peer):
		return
	var state: Dictionary = _outgoing[peer]
	if state.nonce != nonce or received < state.acked or received > state.sent:
		return
	state.acked = received
	state.last = Time.get_ticks_msec()
	if received == _source_bytes.size() and state.sent == received and state.offered:
		_outgoing.erase(peer)

@rpc("any_peer", "call_remote", "reliable", 2)
func reject_avatar(nonce: int, reason: String) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _incoming.has(peer) and _incoming[peer].nonce == nonce:
		_fail_receive(peer, reason.left(160))

@rpc("any_peer", "call_remote", "reliable", 2)
func cancel_transfer(nonce: int) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if _outgoing.has(peer) and _outgoing[peer].nonce == nonce:
		_outgoing.erase(peer)

func _matches(peer: int, id: String, nonce: int) -> bool:
	return _incoming.has(peer) and _incoming[peer].id == id and _incoming[peer].nonce == nonce and _wanted.get(peer, "") == id

func _fail_receive(peer: int, reason: String) -> void:
	if not _incoming.has(peer):
		return
	var id: String = _incoming[peer].id
	cancel_receive(peer)
	AvatarService.record_event(id, "P2P failed", "peer %d: %s" % [peer, reason])
	avatar_failed.emit(peer, id, reason)
	_start_waiting()

func _drop_peer(peer: int) -> void:
	if _incoming.has(peer):
		var id: String = _incoming[peer].id
		AvatarService.record_event(id, "P2P canceled", "Owner disconnected")
		avatar_failed.emit(peer, id, "Owner disconnected")
	_wanted.erase(peer)
	_incoming.erase(peer)
	_outgoing.erase(peer)

func _process(_delta: float) -> void:
	var peers := multiplayer.get_peers()
	var now := Time.get_ticks_msec()
	for peer in _wanted.keys():
		if not peers.has(peer):
			_drop_peer(peer)
	for peer in _incoming.keys():
		var state: Dictionary = _incoming[peer]
		if now - state.start > TOTAL_TIMEOUT_MS or (state.phase != "validating and importing" and now - state.last > IDLE_TIMEOUT_MS):
			_fail_receive(peer, "Avatar transfer timed out")
	var current := str(equipped_id.call()) if equipped_id.is_valid() else ""
	for peer in _outgoing.keys():
		var state: Dictionary = _outgoing[peer]
		if not peers.has(peer):
			_outgoing.erase(peer)
		elif state.id != current or now - state.last > IDLE_TIMEOUT_MS or now - state.start > TOTAL_TIMEOUT_MS:
			reject_avatar.rpc_id(peer, state.nonce, "Avatar changed or transfer timed out")
			_outgoing.erase(peer)
	_poll_source(current)
	_start_waiting()
	if _source_bytes.is_empty() or _source_id != current:
		return
	# One global packet budget, round-robin across peers, plus bounded ACK and
	# SCTP windows. Avatar traffic cannot build an unbounded browser send queue.
	var pending := _outgoing.keys()
	var packets := 0
	for index in pending.size():
		var peer: int = pending[(_send_cursor + index) % pending.size()]
		var state: Dictionary = _outgoing[peer]
		if not state.offered:
			offer_avatar.rpc_id(peer, state.id, state.nonce, _source_bytes.size(), str(AvatarCatalog.definition(state.id).get("title", "Custom avatar")).left(80))
			state.offered = true
		if _buffered_amount(peer) > WINDOW_BYTES:
			continue
		while packets < 4 and state.sent < _source_bytes.size() and state.sent - state.acked < WINDOW_BYTES:
			var end := mini(state.sent + CHUNK_BYTES, _source_bytes.size())
			avatar_chunk.rpc_id(peer, state.id, state.nonce, state.sent, _source_bytes.slice(state.sent, end))
			state.sent = end
			packets += 1
		if packets >= 4:
			break
	_send_cursor += 1

func _poll_source(current: String) -> void:
	if _source_job != null:
		if _source_job.task_id >= 0 and not WorkerThreadPool.is_task_completed(_source_job.task_id):
			return
		if _source_job.task_id >= 0:
			WorkerThreadPool.wait_for_task_completion(_source_job.task_id)
		if not _source_job.error.is_empty():
			for peer in _outgoing.keys():
				reject_avatar.rpc_id(peer, _outgoing[peer].nonce, _source_job.error)
			_outgoing.clear()
			AvatarService.record_event(_source_id, "P2P upload failed", _source_job.error)
		elif current == _source_id:
			_source_bytes = _source_job.bytes
		_source_job = null
	if current != _source_id:
		_source_bytes = PackedByteArray()
	if _outgoing.is_empty() or not _source_bytes.is_empty() or _source_job != null:
		return
	_source_id = current
	_source_job = AvatarAssetJob.new()
	_source_job.path = AvatarLocalLibrary.path_for(current)
	_source_job.from_cache = true
	_source_job.expected_hash = current
	_source_job.max_bytes = AvatarCustomJob.MAX_BYTES
	if OS.has_feature("web") and not OS.has_feature("threads"):
		_source_job.run()
	else:
		_source_job.task_id = WorkerThreadPool.add_task(_source_job.run, false, "Read equipped avatar for P2P")

func _buffered_amount(peer: int) -> int:
	var rtc := multiplayer.multiplayer_peer as WebRTCMultiplayerPeer
	if rtc == null or not rtc.has_peer(peer):
		return 0
	var channels: Array = rtc.get_peer(peer).get("channels", [])
	return (channels[4] as WebRTCDataChannel).get_buffered_amount() if channels.size() > 4 else WINDOW_BYTES + 1

func debug_report() -> String:
	var lines: Array[String] = ["P2P avatar transfers (12 KiB chunks, channel 2):"]
	for peer in _wanted:
		if not _incoming.has(peer):
			lines.append("Peer %d: queued %s" % [peer, _wanted[peer]])
	for peer in _incoming:
		var state: Dictionary = _incoming[peer]
		lines.append("Receive %d: %s | %d / %d bytes | %.1fs" % [peer, state.phase, state.received, state.total, (Time.get_ticks_msec() - state.start) / 1000.0])
	for peer in _outgoing:
		var state: Dictionary = _outgoing[peer]
		lines.append("Send %d: %d sent / %d acknowledged" % [peer, state.sent, state.acked])
	if lines.size() == 1:
		lines.append("Idle")
	return "\n".join(lines)

func _exit_tree() -> void:
	if _source_job != null and _source_job.task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_source_job.task_id)
