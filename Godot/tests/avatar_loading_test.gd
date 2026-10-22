extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func run() -> void:
	var gif := Marshalls.base64_to_raw("R0lGODlhAgACAIAAAAAAAP8AACH5BAEAAAAALAAAAAACAAIAAAIEBMMQBQA7")
	var thumbnail := AvatarGIF.decode(gif)
	check(thumbnail != null and thumbnail.get_size() == Vector2i(2, 2), "GIF first-frame thumbnail decoding failed")
	if thumbnail != null:
		check(thumbnail.get_pixel(0, 0).a == 0.0 and thumbnail.get_pixel(1, 0).r == 1.0, "GIF palette/transparency decoding failed")
	check(AvatarGIF.decode(gif.slice(0, 15)) == null, "Truncated GIF must fail without a partial image")
	var service := root.get_node("AvatarService")
	check(AvatarCatalog.entries().size() > 4000, "Full registry catalog missing")
	check(AvatarCatalog.collections().size() == 10, "Bundled and all upstream collections must be available")
	check(AvatarCatalog.search("", "100Avatars R2").size() == 100, "Collection filtering must include the entire collection")
	check(AvatarCatalog.search("Godette").size() == 1, "Catalog name search failed")
	for entry in AvatarCatalog.entries():
		check(AvatarCatalog.has_avatar(entry.id), "Registry IDs must fit the replication contract")
	check(not AvatarCatalog.has_avatar("https://example.com/evil.vrm"), "Peer URLs must not resolve")
	var invalid: AvatarLoadRequest = service.acquire("unknown")
	check(invalid.finished and not invalid.error.is_empty(), "Unknown avatar should fail immediately")
	var fallback: AvatarLoadRequest = service.acquire("default")
	check(fallback.finished and fallback.scene == null and fallback.error.is_empty(), "Fallback must work offline")

	var warm: AvatarLoadRequest = service.acquire("godette", true)
	var warm_deadline := Time.get_ticks_msec() + 15000
	while not warm.finished and Time.get_ticks_msec() < warm_deadline:
		await process_frame
	check(warm.finished and warm.scene == null and warm.error.is_empty(), "Byte-only prefetch must complete without generating a scene")
	check(not service._cache.has("godette"), "Hover prefetch must not parse/upload a scene")
	warm.release()
	check(AvatarAssets.url("godette", "model").begins_with("https://app.vr.maio-tech.com/avatar-assets/godette/model?v="), "Models must use the catalog proxy")
	check(AvatarAssets.url("unknown", "thumbnail").is_empty(), "Proxy requests must only resolve known catalog assets")

	# One consumer cancelling must not interrupt another consumer's shared load.
	var cancelled: AvatarLoadRequest = service.acquire("godette")
	var survivor: AvatarLoadRequest = service.acquire("godette")
	cancelled.release()
	check(cancelled.finished and cancelled.released, "Cancellation must resolve pending awaits")
	var deadline := Time.get_ticks_msec() + 15000
	while not survivor.finished and Time.get_ticks_msec() < deadline:
		await process_frame
	check(survivor.finished and survivor.scene != null and survivor.error.is_empty(), "Bundled VRM failed: " + survivor.error)
	if survivor.scene != null:
		var first := survivor.scene.instantiate() as Node3D
		var second := survivor.scene.instantiate() as Node3D
		var skeleton := first.find_child("GeneralSkeleton", true, false) as Skeleton3D
		var other := second.find_child("GeneralSkeleton", true, false) as Skeleton3D
		check(skeleton != null and other != null, "VRM humanoid mapping missing")
		if skeleton != null and other != null:
			var head := skeleton.find_bone("Head")
			check(head >= 0, "Humanoid Head bone missing")
			if head >= 0:
				var look := first.find_child("LookOffset", true, false) as Node3D
				var eye_height := skeleton.get_bone_global_rest(head).origin.y + (look.position.y if look != null else 0.0)
				check(absf(eye_height - 1.7) < 0.001, "Standing avatar eye height must be baked into the rest pose")
				check(skeleton.scale.is_equal_approx(Vector3.ONE), "Native spring skeleton must remain unscaled")
				skeleton.set_bone_pose_position(head, Vector3(1, 2, 3))
				check(other.get_bone_pose_position(head) != Vector3(1, 2, 3), "Players must not share mutable skeleton poses")
			var original_meshes: Array[Mesh] = []
			for mesh: MeshInstance3D in first.find_children("*", "MeshInstance3D", true, false):
				original_meshes.append(mesh.mesh)
			AvatarFirstPerson.use_tracked_hands(first, true)
			AvatarFirstPerson.use_tracked_hands(first, false)
			var index := 0
			for mesh: MeshInstance3D in first.find_children("*", "MeshInstance3D", true, false):
				check(mesh.mesh == original_meshes[index], "Desktop switch must restore avatar hand geometry")
				index += 1
		first.free()
		second.free()
		var cached: AvatarLoadRequest = service.acquire("godette")
		check(cached.finished and cached.scene == survivor.scene, "Repeated loads should use the parsed cache")
		cached.release()
	survivor.release()

	var bytes := FileAccess.get_file_as_bytes("res://avatar/godette.vrm")
	var definition := AvatarCatalog.definition("godette")
	var verification := AvatarAssetJob.new()
	verification.bytes = bytes
	verification.expected_size = bytes.size()
	verification.expected_hash = definition.sha256
	verification.run()
	check(verification.error.is_empty(), "Pinned bundled asset hash does not match")
	verification.expected_hash = ""
	verification.expected_size = 0
	verification.run()
	check(verification.error.is_empty(), "Registry assets without published hashes/sizes must load")
	verification.expected_hash = definition.sha256
	verification.expected_size = bytes.size()
	bytes[bytes.size() - 1] ^= 1
	verification.bytes = bytes
	verification.run()
	check(not verification.error.is_empty(), "Modified downloads must be rejected before parsing")
	if "--network" in OS.get_cmdline_user_args():
		var ca_path := OS.get_environment("SSL_CERT_FILE")
		if not ca_path.is_empty():
			var certificates := X509Certificate.new()
			check(certificates.load(ca_path) == OK, "Could not load test trust store")
			service.tls_options = TLSOptions.client(certificates)
		for entry in AvatarCatalog.entries():
			if entry.id in ["default", "godette"] or not entry.has("sha256"):
				continue
			var remote: AvatarLoadRequest = service.acquire(entry.id)
			deadline = Time.get_ticks_msec() + 40000
			while not remote.finished and Time.get_ticks_msec() < deadline:
				await process_frame
			check(remote.finished and remote.scene != null, "Remote avatar " + str(entry.title) + ": " + remote.error)
			remote.release()
	print("Avatar loading: %d failures" % failures)
	quit(1 if failures > 0 else 0)
