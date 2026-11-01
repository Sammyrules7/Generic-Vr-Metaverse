class_name AvatarImageJob
extends RefCounted
## CPU-only image decoding/resizing. The GLTF importer creates textures later;
## their uploads and pipeline work still pass through the rendering backend.
var bytes := PackedByteArray()
var images := {}
var task_id := -1
var elapsed_ms := 0.0
var max_dimension := 2048 if OS.has_feature("android") else 0
var resized_images := 0

func run() -> void:
	var started := Time.get_ticks_usec()
	if bytes.size() < 20:
		return
	var json_length := bytes.decode_u32(12)
	if json_length > bytes.size() - 20:
		return
	var parsed: Variant = JSON.parse_string(bytes.slice(20, 20 + json_length).get_string_from_utf8())
	if not parsed is Dictionary:
		return
	var binary_start := 20 + json_length + 8
	var views: Array = parsed.get("bufferViews", [])
	for definition: Dictionary in parsed.get("images", []):
		var encoded := PackedByteArray()
		if definition.has("bufferView"):
			var index := int(definition.bufferView)
			if index < 0 or index >= views.size():
				continue
			var view: Dictionary = views[index]
			if int(view.get("buffer", 0)) != 0:
				continue
			var start := binary_start + int(view.get("byteOffset", 0))
			var length := int(view.get("byteLength", 0))
			if start < binary_start or length <= 0 or start > bytes.size() - length:
				continue
			encoded = bytes.slice(start, start + length)
		elif str(definition.get("uri", "")).begins_with("data:"):
			var uri := str(definition.uri)
			if uri.contains(";base64,"):
				encoded = Marshalls.base64_to_raw(uri.get_slice(",", 1))
		if encoded.is_empty():
			continue
		var image := Image.new()
		var mime := str(definition.get("mimeType", ""))
		var result := ERR_FILE_UNRECOGNIZED
		if mime == "image/jpeg" or encoded[0] == 0xff:
			result = image.load_jpg_from_buffer(encoded)
		elif mime == "image/webp":
			result = image.load_webp_from_buffer(encoded)
		else:
			result = image.load_png_from_buffer(encoded)
		if result != OK:
			continue
		if max_dimension > 0 and maxi(image.get_width(), image.get_height()) > max_dimension:
			var ratio := float(max_dimension) / maxi(image.get_width(), image.get_height())
			image.resize(maxi(1, roundi(image.get_width() * ratio)), maxi(1, roundi(image.get_height() * ratio)), Image.INTERPOLATE_LANCZOS)
			resized_images += 1
		images[encoded] = image
	elapsed_ms = (Time.get_ticks_usec() - started) / 1000.0
