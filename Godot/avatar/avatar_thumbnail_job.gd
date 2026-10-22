class_name AvatarThumbnailJob
extends RefCounted

var bytes := PackedByteArray()
var image: Image
var task_id := -1

func run() -> void:
	if bytes.slice(0, 3).get_string_from_ascii() == "GIF":
		image = AvatarGIF.decode(bytes)
	else:
		image = Image.new()
		var error := ERR_FILE_UNRECOGNIZED
		if bytes.size() >= 8 and bytes[0] == 137 and bytes[1] == 80:
			error = image.load_png_from_buffer(bytes)
		elif bytes.size() >= 3 and bytes[0] == 255 and bytes[1] == 216:
			error = image.load_jpg_from_buffer(bytes)
		elif bytes.size() >= 12 and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
			error = image.load_webp_from_buffer(bytes)
		if error != OK:
			image = null
	if image != null and not image.is_empty():
		var factor := minf(1.0, 256.0 / maxf(image.get_width(), image.get_height()))
		image.resize(maxi(1, roundi(image.get_width() * factor)), maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_BILINEAR)
