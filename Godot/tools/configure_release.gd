extends SceneTree
## Embed the release endpoint before exporting any platform.


func _initialize() -> void:
	var url := OS.get_environment("VR_PLATFORM_SERVER_URL").strip_edges()
	var pattern := RegEx.new()
	pattern.compile("^wss?://(\\[[0-9a-fA-F:]+\\]|[a-zA-Z0-9.-]+)(?::([0-9]{1,5}))?(/[^\\s#]*)?$")
	var parsed := pattern.search(url)
	if parsed == null:
		_fail("Set VR_PLATFORM_SERVER_URL to the reachable ws:// or wss:// release endpoint.")
		return
	var host := parsed.get_string(1).to_lower().trim_suffix(".")
	var port := parsed.get_string(2)
	if host == "localhost" or host.ends_with(".localhost") or host.begins_with("127.") or host in ["[::1]", "[0:0:0:0:0:0:0:1]", "0.0.0.0", "[::]"]:
		_fail("The release endpoint must be reachable from other devices; loopback and wildcard addresses are not allowed.")
		return
	if not port.is_empty() and (port.to_int() < 1 or port.to_int() > 65535):
		_fail("The release endpoint port must be between 1 and 65535.")
		return
	ProjectSettings.set_setting("network/signaling/server_url", url)
	var result := ProjectSettings.save()
	if result != OK:
		_fail("Could not save the release endpoint: " + error_string(result))
		return
	print("Release signaling endpoint configured.")
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
