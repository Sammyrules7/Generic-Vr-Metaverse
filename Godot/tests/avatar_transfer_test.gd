extends SceneTree
var failures := 0
var ready_count := 0
var errors: Array[String] = []
func _initialize() -> void:
	run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func until(condition: Callable, timeout_ms := 15000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return condition.call()
func endpoint(label: String, transport: ENetMultiplayerPeer, id: String) -> Node:
	var branch := Node3D.new()
	branch.name = label
	root.add_child(branch)
	var api := SceneMultiplayer.new()
	api.root_path = branch.get_path()
	set_multiplayer(api, branch.get_path())
	api.multiplayer_peer = transport
	var transfer = load("res://avatar/avatar_transfer.gd").new()
	transfer.name = "AvatarTransfer"
	transfer.equipped_id = func(): return id
	branch.add_child(transfer)
	return transfer
func run() -> void:
	var manifest_existed := FileAccess.file_exists(AvatarLocalLibrary.MANIFEST)
	var backup := FileAccess.get_file_as_bytes(AvatarLocalLibrary.MANIFEST) if manifest_existed else PackedByteArray()
	var bytes := FileAccess.get_file_as_bytes("res://avatar/godette.vrm")
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	var id := hash.finish().hex_encode()
	var was_owned := AvatarCatalog.is_owned(id)
	var service := root.get_node("AvatarService")
	var imported: Dictionary = await service.import_local_bytes("P2P fixture.vrm", bytes)
	check(imported.get("id", "") == id, "Could not prepare transfer fixture")
	var owned := AvatarCatalog.definition(id)
	var host := ENetMultiplayerPeer.new()
	check(host.create_server(0, 8, 3) == OK, "Cannot start local protocol test")
	var port := host.get_host().get_local_port()
	var client := ENetMultiplayerPeer.new()
	check(client.create_client("127.0.0.1", port, 3) == OK, "Cannot connect protocol test")
	var sender = endpoint("AvatarSender", host, id)
	var receiver = endpoint("AvatarReceiver", client, "default")
	receiver.avatar_ready.connect(func(_peer, _id): ready_count += 1)
	receiver.avatar_failed.connect(func(_peer, _id, reason): errors.append(reason))
	check(await until(func(): return sender.multiplayer.get_peers().size() == 1 and receiver.multiplayer.get_peers().has(1)), "Protocol peers did not connect")
	var remote_id: int = receiver.multiplayer.get_unique_id()
	# Force bytes over the transport even though this single-process test shares
	# its catalog. Remove the owned entry once source reading is complete.
	receiver.ensure(1, id, true)
	check(await until(func(): return sender._outgoing.has(remote_id) and sender._outgoing[remote_id].offered), "Owner did not offer equipped VRM")
	AvatarCatalog.unregister_local(id)
	service._cache.erase(id)
	service._lru.erase(id)
	check(await until(func(): return ready_count == 1), "Transferred VRM was not verified/imported: " + str(errors))
	check(receiver.received_bytes_total == bytes.size() and receiver.completed_transfers == 1, "Transfer lost or duplicated bytes")
	check(AvatarCatalog.definition(id).get("remote_custom", false), "Received content must be marked remote")
	check(not AvatarCatalog.search("", "Custom").any(func(entry): return entry.id == id), "Received content must not enter the custom picker")
	check(AvatarCatalog.replication_id(id) == "default", "Received avatars must not be advertised as owned")
	check(not AvatarLocalLibrary.load_entries().any(func(entry): return entry.id == id and entry.get("remote_custom", false)), "Remote avatar leaked into owned manifest")
	AvatarCatalog.register_local(owned)
	# Pause the sender pump to inject malformed offers/chunks over real RPCs.
	sender.set_process(false)
	receiver.ensure(1, id, true)
	check(await until(func(): return sender._outgoing.has(remote_id)), "Second request did not reach owner")
	var nonce: int = receiver._incoming[1].nonce
	sender.offer_avatar.rpc_id(remote_id, id, nonce, AvatarCustomJob.MAX_BYTES + 1, "oversized")
	check(await until(func(): return errors.size() == 1), "Oversized transfer offer was accepted")
	check(receiver._incoming.is_empty(), "Rejected offer retained receive memory")
	check(await until(func(): return sender._outgoing.is_empty()), "Receiver rejection did not cancel sender")
	receiver.ensure(1, id, true)
	check(await until(func(): return sender._outgoing.has(remote_id)), "Corruption request did not reach owner")
	nonce = receiver._incoming[1].nonce
	sender.offer_avatar.rpc_id(remote_id, id, nonce, bytes.size(), "tampered")
	var corrupted := bytes.duplicate()
	corrupted[corrupted.size() - 1] ^= 1
	for offset in range(0, corrupted.size(), sender.CHUNK_BYTES):
		sender.avatar_chunk.rpc_id(remote_id, id, nonce, offset, corrupted.slice(offset, mini(offset + sender.CHUNK_BYTES, corrupted.size())))
	check(await until(func(): return errors.size() == 2), "Tampered payload was accepted")
	check(errors[1].contains("SHA-256"), "Tampering must fail integrity before import")
	check(await until(func(): return sender._outgoing.is_empty()), "Integrity rejection retained sender state")
	receiver.ensure(1, id, true)
	check(await until(func(): return sender._outgoing.has(remote_id)), "Cancellation request did not reach owner")
	nonce = receiver._incoming[1].nonce
	sender.offer_avatar.rpc_id(remote_id, id, nonce, bytes.size(), "partial")
	sender.avatar_chunk.rpc_id(remote_id, id, nonce + 1, 0, bytes.slice(0, 12))
	sender.avatar_chunk.rpc_id(remote_id, id, nonce, 0, bytes.slice(0, sender.CHUNK_BYTES))
	check(await until(func(): return receiver._incoming[1].received == sender.CHUNK_BYTES), "Stale nonce modified receive offset")
	receiver.cancel_receive(1)
	var received: int = receiver.received_bytes_total
	sender.avatar_chunk.rpc_id(remote_id, id, nonce, sender.CHUNK_BYTES, bytes.slice(sender.CHUNK_BYTES, 2 * sender.CHUNK_BYTES))
	await create_timer(0.05).timeout
	check(receiver._incoming.is_empty() and receiver.received_bytes_total == received, "Late chunks revived a canceled transfer")
	receiver.ensure(1, id, true)
	check(await until(func(): return sender._outgoing.has(remote_id)), "Timeout fixture did not start")
	receiver._incoming[1].last -= receiver.IDLE_TIMEOUT_MS + 1
	check(await until(func(): return errors.size() == 3), "Idle transfers must time out visibly")
	check(errors[2].contains("timed out"), "Timeout reason missing")
	sender.get_parent().free()
	receiver.get_parent().free()
	host.close()
	client.close()
	if not was_owned:
		AvatarCatalog.unregister_local(id)
		DirAccess.remove_absolute(AvatarLocalLibrary.path_for(id))
		DirAccess.remove_absolute("user://avatars/received" + "/" + id + ".vrm")
	if manifest_existed:
		FileAccess.open(AvatarLocalLibrary.MANIFEST, FileAccess.WRITE).store_buffer(backup)
	else:
		DirAccess.remove_absolute(AvatarLocalLibrary.MANIFEST)
	print("Avatar P2P protocol: %d failures" % failures)
	quit(1 if failures else 0)
