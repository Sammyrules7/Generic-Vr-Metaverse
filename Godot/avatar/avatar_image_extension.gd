extends GLTFDocumentExtension
## Reuse images decoded by the worker instead of decoding them during GLTF import.
func _import_preflight(state: GLTFState, _extensions: PackedStringArray) -> Error:
	return OK if state.get_additional_data(&"avatar/decoded_images") is Dictionary else ERR_SKIP

func _parse_image_data(state: GLTFState, image_data: PackedByteArray, _mime_type: String, ret_image: Image) -> Error:
	var images: Dictionary = state.get_additional_data(&"avatar/decoded_images")
	if images.has(image_data):
		ret_image.copy_from(images[image_data])
		state.set_additional_data(&"avatar/decoded_image_hits", int(state.get_additional_data(&"avatar/decoded_image_hits")) + 1)
	return OK
