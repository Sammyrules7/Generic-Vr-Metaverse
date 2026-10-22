class_name AvatarGIF
extends RefCounted
## Decode the first GIF frame for registry thumbnails; animation isn't needed.

static func decode(bytes: PackedByteArray) -> Image:
	if bytes.size() < 13 or bytes.slice(0, 3).get_string_from_ascii() != "GIF":
		return null
	var width := bytes.decode_u16(6)
	var height := bytes.decode_u16(8)
	if width < 1 or height < 1 or width > 1024 or height > 1024:
		return null
	var offset := 13
	var palette := PackedByteArray()
	if bytes[10] & 128:
		var size := 3 * (1 << ((bytes[10] & 7) + 1))
		palette = bytes.slice(offset, offset + size)
		offset += size
	var transparent := -1
	while offset < bytes.size():
		var marker := bytes[offset]
		offset += 1
		if marker == 0x21:
			if offset >= bytes.size():
				return null
			var extension := bytes[offset]
			offset += 1
			if extension == 0xf9 and offset + 5 <= bytes.size() and bytes[offset] == 4:
				transparent = bytes[offset + 4] if bytes[offset + 1] & 1 else -1
			var blocks := _blocks(bytes, offset)
			offset = blocks[1]
			if offset < 0:
				return null
		elif marker == 0x2c:
			if offset + 9 > bytes.size():
				return null
			var left := bytes.decode_u16(offset)
			var top := bytes.decode_u16(offset + 2)
			var frame_width := bytes.decode_u16(offset + 4)
			var frame_height := bytes.decode_u16(offset + 6)
			var flags := bytes[offset + 8]
			offset += 9
			if frame_width < 1 or frame_height < 1 or left + frame_width > width or top + frame_height > height:
				return null
			if flags & 128:
				var size := 3 * (1 << ((flags & 7) + 1))
				palette = bytes.slice(offset, offset + size)
				offset += size
			if offset >= bytes.size() or palette.size() < 3:
				return null
			var minimum := bytes[offset]
			var blocks := _blocks(bytes, offset + 1)
			if blocks[1] < 0:
				return null
			var indices := _lzw(blocks[0], minimum, frame_width * frame_height)
			if indices.size() != frame_width * frame_height:
				return null
			var rows: Array[int] = []
			if flags & 64:
				for pass_index in 4:
					var starts := [0, 4, 2, 1]
					var steps := [8, 8, 4, 2]
					for row in range(starts[pass_index], frame_height, steps[pass_index]):
						rows.append(row)
			else:
				for row in frame_height:
					rows.append(row)
			var rgba := PackedByteArray()
			rgba.resize(width * height * 4)
			for row in frame_height:
				for x in frame_width:
					var index := indices[row * frame_width + x]
					if index * 3 + 2 >= palette.size():
						return null
					var pixel := ((top + rows[row]) * width + left + x) * 4
					rgba[pixel] = palette[index * 3]
					rgba[pixel + 1] = palette[index * 3 + 1]
					rgba[pixel + 2] = palette[index * 3 + 2]
					rgba[pixel + 3] = 0 if index == transparent else 255
			return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, rgba)
		else:
			return null
	return null


static func _blocks(bytes: PackedByteArray, offset: int) -> Array:
	var data := PackedByteArray()
	while offset < bytes.size():
		var size := bytes[offset]
		offset += 1
		if size == 0:
			return [data, offset]
		if offset + size > bytes.size():
			return [data, -1]
		data.append_array(bytes.slice(offset, offset + size))
		offset += size
	return [data, -1]


static func _lzw(data: PackedByteArray, minimum: int, expected: int) -> PackedByteArray:
	if minimum < 2 or minimum > 8:
		return PackedByteArray()
	var clear := 1 << minimum
	var table: Array[PackedByteArray] = []
	table.resize(4096)
	for index in clear:
		table[index] = PackedByteArray([index])
	var next := clear + 2
	var bits := minimum + 1
	var bit_offset := 0
	var previous := PackedByteArray()
	var output := PackedByteArray()
	while bit_offset + bits <= data.size() * 8:
		var code := 0
		for bit in bits:
			code |= ((data[(bit_offset + bit) >> 3] >> ((bit_offset + bit) & 7)) & 1) << bit
		bit_offset += bits
		if code == clear:
			next = clear + 2
			bits = minimum + 1
			previous = PackedByteArray()
			continue
		if code == clear + 1:
			break
		var entry := PackedByteArray()
		if code < next:
			entry = table[code]
		elif code == next and not previous.is_empty():
			entry = previous.duplicate()
			entry.append(previous[0])
		if entry.is_empty() or output.size() + entry.size() > expected:
			return PackedByteArray()
		output.append_array(entry)
		if not previous.is_empty() and next < 4096:
			var added := previous.duplicate()
			added.append(entry[0])
			table[next] = added
			next += 1
			if next == (1 << bits) and bits < 12:
				bits += 1
		previous = entry
		if output.size() == expected:
			break
	return output
