class_name AvatarCustomJob
extends RefCounted
## CPU-only preflight before any image decode or GLTF extension sees user bytes.
const MAX_BYTES := 32 * 1024 * 1024
const MAX_PIXELS := 32 * 1024 * 1024
const ALLOWED_EXTENSIONS := ["VRM", "VRMC_vrm", "VRMC_springBone", "VRMC_materials_mtoon", "VRMC_node_constraint", "VRMC_materials_hdr_emissiveMultiplier", "KHR_materials_unlit", "KHR_texture_transform", "KHR_materials_emissive_strength", "KHR_materials_pbrSpecularGlossiness"]
var bytes := PackedByteArray()
var filename := ""
var source_path := ""
var expected_hash := ""
var expected_size := 0
var chunks: Array[PackedByteArray] = []
var storage_directory := AvatarLocalLibrary.DIRECTORY
var error := ""
var id := ""
var title := ""
var metadata := {}
var task_id := -1
var json: Dictionary = {}
var _binary := PackedByteArray()

func run() -> void:
	if not chunks.is_empty():
		if expected_size < 28 or expected_size > MAX_BYTES:
			error = "Invalid received avatar size"
			return
		var buffer := StreamPeerBuffer.new()
		buffer.resize(expected_size)
		for chunk in chunks:
			if buffer.get_position() + chunk.size() > expected_size or buffer.put_data(chunk) != OK:
				error = "Invalid received avatar chunks"
				return
		if buffer.get_position() != expected_size:
			error = "Received avatar is incomplete"
			return
		bytes = buffer.data_array
		chunks.clear()
	if not source_path.is_empty():
		var source := FileAccess.open(source_path, FileAccess.READ)
		if source == null or source.get_length() > MAX_BYTES:
			error = "Could not read avatar, or file exceeds 32 MiB"
			return
		bytes = source.get_buffer(source.get_length())
		filename = source_path.get_file()
	if filename.get_extension().to_lower() not in ["vrm", "glb"]:
		error = "Choose a VRM file (.vrm or .glb)"
		return
	if bytes.size() < 28 or bytes.size() > MAX_BYTES:
		error = "Avatar must be smaller than 32 MiB"
		return
	if bytes.decode_u32(0) != 0x46546c67 or bytes.decode_u32(4) != 2 or bytes.decode_u32(8) != bytes.size() or bytes.decode_u32(16) != 0x4e4f534a:
		error = "Invalid GLB/VRM file"
		return
	var length := bytes.decode_u32(12)
	if length < 2 or length > 4 * 1024 * 1024 or length % 4 != 0 or 28 + length > bytes.size():
		error = "Invalid or oversized avatar JSON"
		return
	var parsed: Variant = JSON.parse_string(bytes.slice(20, 20 + length).get_string_from_utf8())
	if not parsed is Dictionary:
		error = "Invalid avatar JSON"
		return
	json = parsed
	var binary_at := 20 + length
	if bytes.decode_u32(binary_at + 4) != 0x004e4942 or bytes.decode_u32(binary_at) + binary_at + 8 != bytes.size():
		error = "Avatar must contain one embedded binary buffer"
		return
	_binary = bytes.slice(binary_at + 8)
	if not _walk(json, 0):
		return
	var extensions: Variant = json.get("extensions", {})
	if not extensions is Dictionary or not (extensions.has("VRM") or extensions.has("VRMC_vrm")):
		error = "This file has no VRM humanoid metadata"
		return
	if not _validate_nodes() or not _budget() or not _spring_budget():
		return
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	id = hash.finish().hex_encode()
	if not expected_hash.is_empty() and id != expected_hash:
		error = "Received avatar failed its SHA-256 integrity check"
		return
	metadata = extract_metadata(json)
	title = filename.get_file().get_basename().strip_edges().left(80)
	if title.is_empty():
		title = "Custom avatar"
	title = str(metadata.get("title", title))

func _walk(value: Variant, depth: int) -> bool:
	if depth > 48:
		error = "Avatar metadata is too deeply nested"
		return false
	if value is Dictionary:
		for key in value:
			if key == "uri":
				error = "Custom VRMs must embed their images and buffers"
				return false
			if key in ["extensions", "extensionsUsed", "extensionsRequired"]:
				if (key == "extensions" and not value[key] is Dictionary) or (key != "extensions" and not value[key] is Array):
					error = "Invalid avatar extension metadata"
					return false
				var names: Array = value[key].keys() if value[key] is Dictionary else value[key] if value[key] is Array else []
				for name in names:
					if str(name) not in ALLOWED_EXTENSIONS:
						error = "Unsupported avatar extension: " + str(name).left(80)
						return false
			if not _walk(value[key], depth + 1):
				return false
	elif value is Array:
		for item in value:
			if not _walk(item, depth + 1):
				return false
	elif value is float and not is_finite(value):
		error = "Avatar contains non-finite values"
		return false
	return true

func _budget() -> bool:
	for field in ["nodes", "meshes", "accessors", "bufferViews", "buffers", "materials", "images", "skins"]:
		if not json.get(field, []) is Array:
			error = "Invalid avatar " + field
			return false
	if json.get("nodes", []).size() > 2048 or json.get("materials", []).size() > 32 or json.get("images", []).size() > 64:
		error = "Avatar exceeds node, material or texture limits"
		return false
	var buffers: Array = json.get("buffers", [])
	if buffers.size() != 1 or not buffers[0] is Dictionary or _integer(buffers[0].get("byteLength", -1)) < 0 or _integer(buffers[0].byteLength) > _binary.size():
		error = "Invalid embedded avatar buffer"
		return false
	var views: Array = json.get("bufferViews", [])
	for view in views:
		if not view is Dictionary or _integer(view.get("buffer", 0)) != 0 or _integer(view.get("byteOffset", 0)) < 0 or _integer(view.get("byteLength", -1)) < 0 or _integer(view.get("byteOffset", 0)) + _integer(view.get("byteLength", 0)) > _integer(buffers[0].byteLength):
			error = "Avatar buffer view is out of bounds"
			return false
	var decoded_components := 0
	for accessor in json.get("accessors", []):
		if not accessor is Dictionary:
			error = "Invalid avatar accessor"
			return false
		var count := _integer(accessor.get("count", -1))
		var width := _integer({"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}.get(str(accessor.get("type", "")), 0))
		if count < 0 or count > 1000000 or width == 0 or _integer(accessor.get("componentType", 0)) not in [5120, 5121, 5122, 5123, 5125, 5126]:
			error = "Avatar has an invalid or oversized accessor"
			return false
		decoded_components += count * width
	if decoded_components > 32 * 1024 * 1024:
		error = "Avatar exceeds decoded geometry budget"
		return false
	var vertices := 0
	var triangles := 0
	var morph_work := 0
	var mesh_vertices: Array[int] = []
	var mesh_triangles: Array[int] = []
	var mesh_morphs: Array[int] = []
	for mesh in json.get("meshes", []):
		var before_vertices := vertices
		var before_triangles := triangles
		var before_morphs := morph_work
		if not mesh is Dictionary or not mesh.get("primitives", []) is Array:
			error = "Invalid avatar mesh"
			return false
		for primitive in mesh.get("primitives", []):
			if not primitive is Dictionary or not primitive.get("attributes", {}) is Dictionary or not primitive.get("targets", []) is Array:
				error = "Invalid avatar primitive"
				return false
			var count := _accessor_count(_integer(primitive.attributes.get("POSITION", -1)))
			var indices := _accessor_count(_integer(primitive.get("indices", -1))) if primitive.has("indices") else count
			if count < 0 or indices < 0 or _integer(primitive.get("mode", 4)) != 4:
				error = "Avatar requires valid triangle geometry"
				return false
			vertices += count
			triangles += indices / 3
			morph_work += count * primitive.get("targets", []).size()
			if primitive.get("targets", []).size() > 128:
				error = "Avatar has too many blend shapes"
				return false
		mesh_vertices.append(vertices - before_vertices)
		mesh_triangles.append(triangles - before_triangles)
		mesh_morphs.append(morph_work - before_morphs)
	var drawn_vertices := 0
	var drawn_triangles := 0
	var drawn_morphs := 0
	for node in json.get("nodes", []):
		if node.has("mesh"):
			var mesh_index := _integer(node.mesh)
			if mesh_index < 0 or mesh_index >= mesh_vertices.size():
				error = "Invalid avatar mesh reference"
				return false
			drawn_vertices += mesh_vertices[mesh_index]
			drawn_triangles += mesh_triangles[mesh_index]
			drawn_morphs += mesh_morphs[mesh_index]
	if drawn_vertices > 200000 or drawn_triangles > 100000 or drawn_morphs > 8000000:
		error = "Avatar exceeds instanced geometry limits"
		return false
	if vertices <= 0 or vertices > 200000 or triangles > 100000 or morph_work > 8000000:
		error = "Avatar exceeds geometry limits (100k triangles / 200k vertices)"
		return false
	for skin in json.get("skins", []):
		if not skin is Dictionary or not skin.get("joints", []) is Array or skin.get("joints", []).size() > 256:
			error = "Avatar exceeds the 256-bone skeleton limit"
			return false
	var pixels := 0
	for image in json.get("images", []):
		if not image is Dictionary:
			error = "Invalid avatar image"
			return false
		var index := _integer(image.get("bufferView", -1))
		if index < 0 or index >= views.size():
			error = "Avatar image must use an embedded buffer view"
			return false
		var view: Dictionary = views[index]
		var start := _integer(view.get("byteOffset", 0))
		var data := _binary.slice(start, start + _integer(view.byteLength))
		var size := _image_size(data)
		if size.x <= 0 or size.y <= 0 or size.x > 4096 or size.y > 4096:
			error = "Avatar textures must be PNG/JPEG and at most 4096 pixels per side"
			return false
		pixels += size.x * size.y
	if pixels > MAX_PIXELS:
		error = "Avatar exceeds the 32-megapixel texture budget"
		return false
	return true

func _accessor_count(index: int) -> int:
	var accessors: Array = json.get("accessors", [])
	if index < 0 or index >= accessors.size() or not accessors[index] is Dictionary:
		return -1
	return _integer(accessors[index].get("count", -1))

static func _image_size(data: PackedByteArray) -> Vector2i:
	if data.size() >= 24 and data.slice(0, 8) == PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return Vector2i(_be32(data, 16), _be32(data, 20))
	if data.size() >= 4 and data[0] == 255 and data[1] == 216:
		var cursor := 2
		while cursor + 4 <= data.size():
			if data[cursor] != 255:
				return Vector2i.ZERO
			var marker := _integer(data[cursor + 1])
			if marker == 255:
				cursor += 1
				continue
			if marker == 0xd9 or marker == 0xda:
				break
			var length := _integer(data[cursor + 2]) * 256 + _integer(data[cursor + 3])
			if length < 2 or cursor + 2 + length > data.size():
				break
			if marker in [0xc0, 0xc1, 0xc2] and length >= 7:
				return Vector2i(_integer(data[cursor + 7]) * 256 + _integer(data[cursor + 8]), _integer(data[cursor + 5]) * 256 + _integer(data[cursor + 6]))
			cursor += 2 + length
	return Vector2i.ZERO

static func _be32(data: PackedByteArray, at: int) -> int:
	return _integer(data[at]) * 16777216 + _integer(data[at + 1]) * 65536 + _integer(data[at + 2]) * 256 + _integer(data[at + 3])


func store() -> void:
	var path := storage_directory + "/" + id + ".vrm" if AvatarLocalLibrary.valid_id(id) else ""
	if path.is_empty():
		error = "Invalid custom avatar hash"
		return
	DirAccess.make_dir_recursive_absolute(storage_directory)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		error = "Could not store avatar on this device"
		return
	file.store_buffer(bytes)
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		error = "Could not save avatar on this device"


func _validate_nodes() -> bool:
	var nodes: Variant = json.get("nodes", [])
	if not nodes is Array or nodes.size() > 2048:
		error = "Invalid or oversized avatar node graph"
		return false
	var parents := {}
	for index in nodes.size():
		var node: Variant = nodes[index]
		if not node is Dictionary or not node.get("children", []) is Array:
			error = "Invalid avatar node"
			return false
		for child in node.get("children", []):
			if not (child is int or child is float) or _integer(child) < 0 or _integer(child) >= nodes.size() or parents.has(_integer(child)):
				error = "Invalid or shared avatar node child"
				return false
			parents[_integer(child)] = index
	for index in nodes.size():
		var cursor: int = index
		var depth := 0
		while parents.has(cursor):
			cursor = parents[cursor]
			depth += 1
			if depth > 64:
				error = "Avatar node graph is cyclic or too deep"
				return false
	var extensions: Dictionary = json.get("extensions", {})
	var humanoid: Variant
	var vrm: Variant = extensions.get("VRM", extensions.get("VRMC_vrm", {}))
	if not vrm is Dictionary or not vrm.get("humanoid", {}) is Dictionary:
		error = "Invalid humanoid metadata"
		return false
	humanoid = vrm.get("humanoid", {}).get("humanBones", {})
	var bones := {}
	if humanoid is Array:
		for bone in humanoid:
			if bone is Dictionary:
				bones[str(bone.get("bone", ""))] = bone.get("node", -1)
	elif humanoid is Dictionary:
		for name in humanoid:
			if humanoid[name] is Dictionary:
				bones[name] = humanoid[name].get("node", -1)
	for required in ["hips", "head", "leftHand", "rightHand"]:
		if not bones.has(required) or not (bones[required] is int or bones[required] is float) or _integer(bones[required]) < 0 or _integer(bones[required]) >= nodes.size():
			error = "Avatar is missing a required humanoid bone: " + required
			return false
	return true


func _spring_budget() -> bool:
	var extensions: Dictionary = json.get("extensions", {})
	var springs: Variant = extensions.get("VRMC_springBone", {})
	if not springs is Dictionary:
		error = "Invalid spring metadata"
		return false
	var chains: Variant = springs.get("springs", [])
	var colliders: Variant = springs.get("colliders", [])
	if not chains is Array or not colliders is Array or chains.size() > 64 or colliders.size() > 128:
		error = "Avatar exceeds spring chain or collider limits"
		return false
	for chain in chains:
		if not chain is Dictionary or not chain.get("joints", []) is Array or chain.get("joints", []).size() > 64:
			error = "Avatar exceeds spring joint limits"
			return false
	var vrm: Variant = extensions.get("VRM", {})
	var secondary: Variant = vrm.get("secondaryAnimation", {}) if vrm is Dictionary else {}
	if not secondary is Dictionary or not secondary.get("boneGroups", []) is Array or not secondary.get("colliderGroups", []) is Array:
		error = "Invalid legacy spring metadata"
		return false
	var root_count := 0
	var collider_count := 0
	for group in secondary.get("boneGroups", []):
		if not group is Dictionary or not group.get("bones", []) is Array:
			error = "Invalid legacy spring chain"
			return false
		root_count += group.get("bones", []).size()
	for group in secondary.get("colliderGroups", []):
		if not group is Dictionary or not group.get("colliders", []) is Array:
			error = "Invalid legacy spring colliders"
			return false
		collider_count += group.get("colliders", []).size()
	if root_count > 64 or collider_count > 128:
		error = "Avatar exceeds legacy spring limits"
		return false
	return true


static func _integer(value: Variant) -> int:
	if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value)) > 1099511627776.0 or floor(float(value)) != float(value):
		return -1
	return int(value)


## Plain display text only. Metadata is descriptive, never executable or fetched.
static func _text(value: Variant, limit := 1024) -> String:
	return value.strip_edges().left(limit) if value is String else ""

static func extract_metadata(document: Dictionary) -> Dictionary:
	var extensions: Variant = document.get("extensions", {})
	if not extensions is Dictionary:
		return {}
	var modern: bool = extensions.has("VRMC_vrm")
	var vrm: Variant = extensions.get("VRMC_vrm" if modern else "VRM", {})
	if not vrm is Dictionary or not vrm.get("meta", {}) is Dictionary:
		return {}
	var meta: Dictionary = vrm.get("meta", {})
	var result := {"metadata_version": 1}
	var name := _text(meta.get("name" if modern else "title", ""), 80)
	if not name.is_empty():
		result["title"] = name
	var authors: Array[String] = []
	var source: Variant = meta.get("authors", []) if modern else [meta.get("author", "")]
	if source is Array:
		for author in source.slice(0, 16):
			var text := _text(author, 160)
			if not text.is_empty():
				authors.append(text)
	result["creator"] = ", ".join(authors)
	var license_name := _text(meta.get("licenseName", ""), 128)
	var license_url := _text(meta.get("licenseUrl", ""))
	if modern:
		license_name = "" if license_url.is_empty() else "VRM 1.0" if license_url == "https://vrm.dev/licenses/1.0/" else "Custom license"
	elif license_name.begins_with("CC_"):
		license_name = license_name.replace("_", "-")
	result["license"] = license_name if not license_name.is_empty() else "License unspecified"
	var credits: Array[String] = []
	if not result.creator.is_empty():
		credits.append(result.creator)
	credits.append(result.license)
	for key in ["copyrightInformation", "thirdPartyLicenses", "contactInformation", "reference", "otherPermissionUrl", "licenseUrl", "otherLicenseUrl"]:
		var text := _text(meta.get(key, ""), 8192 if key == "thirdPartyLicenses" else 2048)
		if not text.is_empty():
			result[key] = text
			credits.append(text)
	var references: Variant = meta.get("references", [])
	if references is Array:
		var links: Array[String] = []
		for reference in references.slice(0, 16):
			var text := _text(reference)
			if not text.is_empty():
				links.append(text)
		if not links.is_empty():
			result["references"] = links
			credits.append("\n".join(links))
	result["attribution"] = "\n".join(credits)
	return result
