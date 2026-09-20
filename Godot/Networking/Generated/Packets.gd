#
# BSD 3-Clause License
#
# Copyright (c) 2018 - 2026, Oleg Malyavkin
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
# * Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# DEBUG_TAB redefine this "  " if you need, example: const DEBUG_TAB = "\t"

const PROTO_VERSION = 3

const DEBUG_TAB : String = "  "

enum PB_ERR {
	NO_ERRORS = 0,
	VARINT_NOT_FOUND = -1,
	REPEATED_COUNT_NOT_FOUND = -2,
	REPEATED_COUNT_MISMATCH = -3,
	LENGTHDEL_SIZE_NOT_FOUND = -4,
	LENGTHDEL_SIZE_MISMATCH = -5,
	PACKAGE_SIZE_MISMATCH = -6,
	UNDEFINED_STATE = -7,
	PARSE_INCOMPLETE = -8,
	REQUIRED_FIELDS = -9
}

enum PB_DATA_TYPE {
	INT32 = 0,
	SINT32 = 1,
	UINT32 = 2,
	INT64 = 3,
	SINT64 = 4,
	UINT64 = 5,
	BOOL = 6,
	ENUM = 7,
	FIXED32 = 8,
	SFIXED32 = 9,
	FLOAT = 10,
	FIXED64 = 11,
	SFIXED64 = 12,
	DOUBLE = 13,
	STRING = 14,
	BYTES = 15,
	MESSAGE = 16,
	MAP = 17
}

const DEFAULT_VALUES_2 = {
	PB_DATA_TYPE.INT32: null,
	PB_DATA_TYPE.SINT32: null,
	PB_DATA_TYPE.UINT32: null,
	PB_DATA_TYPE.INT64: null,
	PB_DATA_TYPE.SINT64: null,
	PB_DATA_TYPE.UINT64: null,
	PB_DATA_TYPE.BOOL: null,
	PB_DATA_TYPE.ENUM: null,
	PB_DATA_TYPE.FIXED32: null,
	PB_DATA_TYPE.SFIXED32: null,
	PB_DATA_TYPE.FLOAT: null,
	PB_DATA_TYPE.FIXED64: null,
	PB_DATA_TYPE.SFIXED64: null,
	PB_DATA_TYPE.DOUBLE: null,
	PB_DATA_TYPE.STRING: null,
	PB_DATA_TYPE.BYTES: null,
	PB_DATA_TYPE.MESSAGE: null,
	PB_DATA_TYPE.MAP: null
}

const DEFAULT_VALUES_3 = {
	PB_DATA_TYPE.INT32: 0,
	PB_DATA_TYPE.SINT32: 0,
	PB_DATA_TYPE.UINT32: 0,
	PB_DATA_TYPE.INT64: 0,
	PB_DATA_TYPE.SINT64: 0,
	PB_DATA_TYPE.UINT64: 0,
	PB_DATA_TYPE.BOOL: false,
	PB_DATA_TYPE.ENUM: 0,
	PB_DATA_TYPE.FIXED32: 0,
	PB_DATA_TYPE.SFIXED32: 0,
	PB_DATA_TYPE.FLOAT: 0.0,
	PB_DATA_TYPE.FIXED64: 0,
	PB_DATA_TYPE.SFIXED64: 0,
	PB_DATA_TYPE.DOUBLE: 0.0,
	PB_DATA_TYPE.STRING: "",
	PB_DATA_TYPE.BYTES: [],
	PB_DATA_TYPE.MESSAGE: null,
	PB_DATA_TYPE.MAP: []
}

enum PB_TYPE {
	VARINT = 0,
	FIX64 = 1,
	LENGTHDEL = 2,
	STARTGROUP = 3,
	ENDGROUP = 4,
	FIX32 = 5,
	UNDEFINED = 8
}

enum PB_RULE {
	OPTIONAL = 0,
	REQUIRED = 1,
	REPEATED = 2,
	RESERVED = 3
}

enum PB_SERVICE_STATE {
	FILLED = 0,
	UNFILLED = 1
}

class PBField:
	func _init(a_name : String, a_type : int, a_rule : int, a_tag : int, packed : bool, a_value = null):
		name = a_name
		type = a_type
		rule = a_rule
		tag = a_tag
		option_packed = packed
		value = a_value

	var name : String
	var type : int
	var rule : int
	var tag : int
	var option_packed : bool
	var value
	var is_map_field : bool = false
	var option_default : bool = false

class PBTypeTag:
	var ok : bool = false
	var type : int
	var tag : int
	var offset : int

class PBServiceField:
	var field : PBField
	var func_ref = null
	var state : int = PB_SERVICE_STATE.UNFILLED

class PBPacker:
	static func convert_signed(n : int) -> int:
		if n < -2147483648:
			return (n << 1) ^ (n >> 63)
		else:
			return (n << 1) ^ (n >> 31)

	static func deconvert_signed(n : int) -> int:
		if n & 0x01:
			return ~(n >> 1)
		else:
			return (n >> 1)

	static func pack_varint(value) -> PackedByteArray:
		var varint : PackedByteArray = PackedByteArray()
		if typeof(value) == TYPE_BOOL:
			if value:
				value = 1
			else:
				value = 0
		for _i in range(9):
			var b = value & 0x7F
			value >>= 7
			if value:
				varint.append(b | 0x80)
			else:
				varint.append(b)
				break
		if varint.size() == 9 && (varint[8] & 0x80 != 0):
			varint.append(0x01)
		return varint

	static func pack_bytes(value, count : int, data_type : int) -> PackedByteArray:
		var bytes : PackedByteArray = PackedByteArray()
		if data_type == PB_DATA_TYPE.FLOAT:
			var spb : StreamPeerBuffer = StreamPeerBuffer.new()
			spb.put_float(value)
			bytes = spb.get_data_array()
		elif data_type == PB_DATA_TYPE.DOUBLE:
			var spb : StreamPeerBuffer = StreamPeerBuffer.new()
			spb.put_double(value)
			bytes = spb.get_data_array()
		else:
			for _i in range(count):
				bytes.append(value & 0xFF)
				value >>= 8
		return bytes

	static func unpack_bytes(bytes : PackedByteArray, index : int, count : int, data_type : int):
		if data_type == PB_DATA_TYPE.FLOAT:
			return bytes.decode_float(index)
		elif data_type == PB_DATA_TYPE.DOUBLE:
			return bytes.decode_double(index)
		elif data_type == PB_DATA_TYPE.FIXED32:
			return bytes.decode_u32(index)
		elif data_type == PB_DATA_TYPE.SFIXED32:
			return bytes.decode_s32(index)
		elif data_type == PB_DATA_TYPE.FIXED64:
			return bytes.decode_u64(index)
		elif data_type == PB_DATA_TYPE.SFIXED64:
			return bytes.decode_s64(index)
		else:
			var value : int = 0
			for i in range(count):
				value |= bytes[index + i] << (8 * i)
			return value

	static func unpack_varint(varint_bytes) -> int:
		var value : int = 0
		var i: int = varint_bytes.size() - 1
		while i > -1:
			value = (value << 7) | (varint_bytes[i] & 0x7F)
			i -= 1
		return value

	static func pack_type_tag(type : int, tag : int) -> PackedByteArray:
		return pack_varint((tag << 3) | type)

	static func isolate_varint(bytes : PackedByteArray, index : int) -> PackedByteArray:
		var i: int = index
		while i <= index + 10 && i < bytes.size(): # Protobuf varint max size is 10 bytes
			if !(bytes[i] & 0x80):
				return bytes.slice(index, i + 1)
			i += 1
		return [] # Unreachable

	static func unpack_type_tag(bytes : PackedByteArray, index : int) -> PBTypeTag:
		var varint_bytes : PackedByteArray = isolate_varint(bytes, index)
		var result : PBTypeTag = PBTypeTag.new()
		if varint_bytes.size() != 0:
			result.ok = true
			result.offset = varint_bytes.size()
			var unpacked : int = unpack_varint(varint_bytes)
			result.type = unpacked & 0x07
			result.tag = unpacked >> 3
		return result

	static func pack_length_delimeted(type : int, tag : int, bytes : PackedByteArray) -> PackedByteArray:
		var result : PackedByteArray = pack_type_tag(type, tag)
		result.append_array(pack_varint(bytes.size()))
		result.append_array(bytes)
		return result

	static func pb_type_from_data_type(data_type : int) -> int:
		if data_type == PB_DATA_TYPE.INT32 || data_type == PB_DATA_TYPE.SINT32 || data_type == PB_DATA_TYPE.UINT32 || data_type == PB_DATA_TYPE.INT64 || data_type == PB_DATA_TYPE.SINT64 || data_type == PB_DATA_TYPE.UINT64 || data_type == PB_DATA_TYPE.BOOL || data_type == PB_DATA_TYPE.ENUM:
			return PB_TYPE.VARINT
		elif data_type == PB_DATA_TYPE.FIXED32 || data_type == PB_DATA_TYPE.SFIXED32 || data_type == PB_DATA_TYPE.FLOAT:
			return PB_TYPE.FIX32
		elif data_type == PB_DATA_TYPE.FIXED64 || data_type == PB_DATA_TYPE.SFIXED64 || data_type == PB_DATA_TYPE.DOUBLE:
			return PB_TYPE.FIX64
		elif data_type == PB_DATA_TYPE.STRING || data_type == PB_DATA_TYPE.BYTES || data_type == PB_DATA_TYPE.MESSAGE || data_type == PB_DATA_TYPE.MAP:
			return PB_TYPE.LENGTHDEL
		else:
			return PB_TYPE.UNDEFINED

	static func pack_field(field : PBField) -> PackedByteArray:
		var type : int = pb_type_from_data_type(field.type)
		var type_copy : int = type
		if field.rule == PB_RULE.REPEATED && field.option_packed:
			type = PB_TYPE.LENGTHDEL
		var head : PackedByteArray = pack_type_tag(type, field.tag)
		var data : PackedByteArray = PackedByteArray()
		if type == PB_TYPE.VARINT:
			var value
			if field.rule == PB_RULE.REPEATED:
				for v in field.value:
					data.append_array(head)
					if field.type == PB_DATA_TYPE.SINT32 || field.type == PB_DATA_TYPE.SINT64:
						value = convert_signed(v)
					else:
						value = v
					data.append_array(pack_varint(value))
				return data
			else:
				if field.type == PB_DATA_TYPE.SINT32 || field.type == PB_DATA_TYPE.SINT64:
					value = convert_signed(field.value)
				else:
					value = field.value
				data = pack_varint(value)
		elif type == PB_TYPE.FIX32:
			if field.rule == PB_RULE.REPEATED:
				for v in field.value:
					data.append_array(head)
					data.append_array(pack_bytes(v, 4, field.type))
				return data
			else:
				data.append_array(pack_bytes(field.value, 4, field.type))
		elif type == PB_TYPE.FIX64:
			if field.rule == PB_RULE.REPEATED:
				for v in field.value:
					data.append_array(head)
					data.append_array(pack_bytes(v, 8, field.type))
				return data
			else:
				data.append_array(pack_bytes(field.value, 8, field.type))
		elif type == PB_TYPE.LENGTHDEL:
			if field.rule == PB_RULE.REPEATED:
				if type_copy == PB_TYPE.VARINT:
					if field.type == PB_DATA_TYPE.SINT32 || field.type == PB_DATA_TYPE.SINT64:
						var signed_value : int
						for v in field.value:
							signed_value = convert_signed(v)
							data.append_array(pack_varint(signed_value))
					else:
						for v in field.value:
							data.append_array(pack_varint(v))
					return pack_length_delimeted(type, field.tag, data)
				elif type_copy == PB_TYPE.FIX32:
					for v in field.value:
						data.append_array(pack_bytes(v, 4, field.type))
					return pack_length_delimeted(type, field.tag, data)
				elif type_copy == PB_TYPE.FIX64:
					for v in field.value:
						data.append_array(pack_bytes(v, 8, field.type))
					return pack_length_delimeted(type, field.tag, data)
				elif field.type == PB_DATA_TYPE.STRING:
					for v in field.value:
						var obj = v.to_utf8_buffer()
						data.append_array(pack_length_delimeted(type, field.tag, obj))
					return data
				elif field.type == PB_DATA_TYPE.BYTES:
					for v in field.value:
						data.append_array(pack_length_delimeted(type, field.tag, v))
					return data
				elif typeof(field.value[0]) == TYPE_OBJECT:
					for v in field.value:
						var obj : PackedByteArray = v.to_bytes()
						data.append_array(pack_length_delimeted(type, field.tag, obj))
					return data
			else:
				if field.type == PB_DATA_TYPE.STRING:
					var str_bytes : PackedByteArray = field.value.to_utf8_buffer()
					if PROTO_VERSION == 2 || (PROTO_VERSION == 3 && str_bytes.size() > 0):
						data.append_array(str_bytes)
						return pack_length_delimeted(type, field.tag, data)
				if field.type == PB_DATA_TYPE.BYTES:
					if PROTO_VERSION == 2 || (PROTO_VERSION == 3 && field.value.size() > 0):
						data.append_array(field.value)
						return pack_length_delimeted(type, field.tag, data)
				elif typeof(field.value) == TYPE_OBJECT:
					var obj : PackedByteArray = field.value.to_bytes()
					if obj.size() > 0:
						data.append_array(obj)
					return pack_length_delimeted(type, field.tag, data)
				else:
					pass
		if data.size() > 0:
			head.append_array(data)
			return head
		else:
			return data

	static func skip_unknown_field(bytes : PackedByteArray, offset : int, type : int) -> int:
		if type == PB_TYPE.VARINT:
			return offset + isolate_varint(bytes, offset).size()
		if type == PB_TYPE.FIX64:
			return offset + 8
		if type == PB_TYPE.LENGTHDEL:
			var length_bytes : PackedByteArray = isolate_varint(bytes, offset)
			var length : int = unpack_varint(length_bytes)
			return offset + length_bytes.size() + length
		if type == PB_TYPE.FIX32:
			return offset + 4
		return PB_ERR.UNDEFINED_STATE

	static func unpack_field(bytes : PackedByteArray, offset : int, field : PBField, type : int, message_func_ref) -> int:
		if field.rule == PB_RULE.REPEATED && type != PB_TYPE.LENGTHDEL && field.option_packed:
			var count = isolate_varint(bytes, offset)
			if count.size() > 0:
				offset += count.size()
				count = unpack_varint(count)
				if type == PB_TYPE.VARINT:
					var val
					var counter = offset + count
					while offset < counter:
						val = isolate_varint(bytes, offset)
						if val.size() > 0:
							offset += val.size()
							val = unpack_varint(val)
							if field.type == PB_DATA_TYPE.SINT32 || field.type == PB_DATA_TYPE.SINT64:
								val = deconvert_signed(val)
							elif field.type == PB_DATA_TYPE.BOOL:
								if val:
									val = true
								else:
									val = false
							field.value.append(val)
						else:
							return PB_ERR.REPEATED_COUNT_MISMATCH
					return offset
				elif type == PB_TYPE.FIX32 || type == PB_TYPE.FIX64:
					var type_size
					if type == PB_TYPE.FIX32:
						type_size = 4
					else:
						type_size = 8
					var val
					var counter = offset + count
					while offset < counter:
						if (offset + type_size) > bytes.size():
							return PB_ERR.REPEATED_COUNT_MISMATCH
						val = unpack_bytes(bytes, offset, type_size, field.type)
						offset += type_size
						field.value.append(val)
					return offset
			else:
				return PB_ERR.REPEATED_COUNT_NOT_FOUND
		else:
			if type == PB_TYPE.VARINT:
				var val = isolate_varint(bytes, offset)
				if val.size() > 0:
					offset += val.size()
					val = unpack_varint(val)
					if field.type == PB_DATA_TYPE.SINT32 || field.type == PB_DATA_TYPE.SINT64:
						val = deconvert_signed(val)
					elif field.type == PB_DATA_TYPE.BOOL:
						if val:
							val = true
						else:
							val = false
					if field.rule == PB_RULE.REPEATED:
						field.value.append(val)
					else:
						field.value = val
				else:
					return PB_ERR.VARINT_NOT_FOUND
				return offset
			elif type == PB_TYPE.FIX32 || type == PB_TYPE.FIX64:
				var type_size
				if type == PB_TYPE.FIX32:
					type_size = 4
				else:
					type_size = 8
				var val
				if (offset + type_size) > bytes.size():
					return PB_ERR.REPEATED_COUNT_MISMATCH
				val = unpack_bytes(bytes, offset, type_size, field.type)
				offset += type_size
				if field.rule == PB_RULE.REPEATED:
					field.value.append(val)
				else:
					field.value = val
				return offset
			elif type == PB_TYPE.LENGTHDEL:
				var inner_size = isolate_varint(bytes, offset)
				if inner_size.size() > 0:
					offset += inner_size.size()
					inner_size = unpack_varint(inner_size)
					if inner_size >= 0:
						if inner_size + offset > bytes.size():
							return PB_ERR.LENGTHDEL_SIZE_MISMATCH
						if message_func_ref != null:
							var message = message_func_ref.call()
							if inner_size > 0:
								var sub_offset = message.from_bytes(bytes, offset, inner_size + offset)
								if sub_offset > 0:
									if sub_offset - offset >= inner_size:
										offset = sub_offset
										return offset
									else:
										return PB_ERR.LENGTHDEL_SIZE_MISMATCH
								return sub_offset
							else:
								return offset
						elif field.type == PB_DATA_TYPE.STRING:
							var str_bytes : PackedByteArray = bytes.slice(offset, inner_size + offset)
							if field.rule == PB_RULE.REPEATED:
								field.value.append(str_bytes.get_string_from_utf8())
							else:
								field.value = str_bytes.get_string_from_utf8()
							return offset + inner_size
						elif field.type == PB_DATA_TYPE.BYTES:
							var val_bytes : PackedByteArray = bytes.slice(offset, inner_size + offset)
							if field.rule == PB_RULE.REPEATED:
								field.value.append(val_bytes)
							else:
								field.value = val_bytes
							return offset + inner_size
					else:
						return PB_ERR.LENGTHDEL_SIZE_NOT_FOUND
				else:
					return PB_ERR.LENGTHDEL_SIZE_NOT_FOUND
		return PB_ERR.UNDEFINED_STATE

	static func unpack_message(data, bytes : PackedByteArray, offset : int, limit : int) -> int:
		while true:
			var tt : PBTypeTag = unpack_type_tag(bytes, offset)
			if tt.ok:
				offset += tt.offset
				if data.has(tt.tag):
					var service : PBServiceField = data[tt.tag]
					var type : int = pb_type_from_data_type(service.field.type)
					if type == tt.type || (tt.type == PB_TYPE.LENGTHDEL && service.field.rule == PB_RULE.REPEATED && service.field.option_packed):
						var res : int = unpack_field(bytes, offset, service.field, type, service.func_ref)
						if res > 0:
							service.state = PB_SERVICE_STATE.FILLED
							offset = res
							if offset == limit:
								return offset
							elif offset > limit:
								return PB_ERR.PACKAGE_SIZE_MISMATCH
						elif res < 0:
							return res
						else:
							break
				else:
					var res : int = skip_unknown_field(bytes, offset, tt.type)
					if res > 0:
						offset = res
						if offset == limit:
							return offset
						elif offset > limit:
							return PB_ERR.PACKAGE_SIZE_MISMATCH
					elif res < 0:
						return res
					else:
						break
			else:
				return offset
		return PB_ERR.UNDEFINED_STATE

	static func pack_message(data) -> PackedByteArray:
		var DEFAULT_VALUES
		if PROTO_VERSION == 2:
			DEFAULT_VALUES = DEFAULT_VALUES_2
		elif PROTO_VERSION == 3:
			DEFAULT_VALUES = DEFAULT_VALUES_3
		var result : PackedByteArray = PackedByteArray()
		var keys : Array = data.keys()
		keys.sort()
		for i in keys:
			if data[i].field.value != null:
				if data[i].state == PB_SERVICE_STATE.UNFILLED \
				&& !data[i].field.is_map_field \
				&& typeof(data[i].field.value) == typeof(DEFAULT_VALUES[data[i].field.type]) \
				&& data[i].field.value == DEFAULT_VALUES[data[i].field.type]:
					continue
				elif data[i].field.rule == PB_RULE.REPEATED && data[i].field.value.size() == 0:
					continue
				result.append_array(pack_field(data[i].field))
			elif data[i].field.rule == PB_RULE.REQUIRED:
				print("Error: required field is not filled: Tag:", data[i].field.tag)
				return PackedByteArray()
		return result

	static func check_required(data) -> bool:
		var keys : Array = data.keys()
		for i in keys:
			if data[i].field.rule == PB_RULE.REQUIRED && data[i].state == PB_SERVICE_STATE.UNFILLED:
				return false
		return true

	static func construct_map(key_values):
		var result = {}
		for kv in key_values:
			result[kv.get_key()] = kv.get_value()
		return result

	static func tabulate(text : String, nesting : int) -> String:
		var tab : String = ""
		for _i in range(nesting):
			tab += DEBUG_TAB
		return tab + text

	static func value_to_string(value, field : PBField, nesting : int) -> String:
		var result : String = ""
		var text : String
		if field.type == PB_DATA_TYPE.MESSAGE:
			result += "{"
			nesting += 1
			text = message_to_string(value.data, nesting)
			if text != "":
				result += "\n" + text
				nesting -= 1
				result += tabulate("}", nesting)
			else:
				nesting -= 1
				result += "}"
		elif field.type == PB_DATA_TYPE.BYTES:
			result += "<"
			for i in range(value.size()):
				result += str(value[i])
				if i != (value.size() - 1):
					result += ", "
			result += ">"
		elif field.type == PB_DATA_TYPE.STRING:
			result += "\"" + value + "\""
		elif field.type == PB_DATA_TYPE.ENUM:
			result += "ENUM::" + str(value)
		else:
			result += str(value)
		return result

	static func field_to_string(field : PBField, nesting : int) -> String:
		var result : String = tabulate(field.name + ": ", nesting)
		if field.type == PB_DATA_TYPE.MAP:
			if field.value.size() > 0:
				result += "(\n"
				nesting += 1
				for i in range(field.value.size()):
					var local_key_value = field.value[i].data[1].field
					result += tabulate(value_to_string(local_key_value.value, local_key_value, nesting), nesting) + ": "
					local_key_value = field.value[i].data[2].field
					result += value_to_string(local_key_value.value, local_key_value, nesting)
					if i != (field.value.size() - 1):
						result += ","
					result += "\n"
				nesting -= 1
				result += tabulate(")", nesting)
			else:
				result += "()"
		elif field.rule == PB_RULE.REPEATED:
			if field.value.size() > 0:
				result += "[\n"
				nesting += 1
				for i in range(field.value.size()):
					result += tabulate(str(i) + ": ", nesting)
					result += value_to_string(field.value[i], field, nesting)
					if i != (field.value.size() - 1):
						result += ","
					result += "\n"
				nesting -= 1
				result += tabulate("]", nesting)
			else:
				result += "[]"
		else:
			result += value_to_string(field.value, field, nesting)
		result += ";\n"
		return result

	static func message_to_string(data, nesting : int = 0) -> String:
		var DEFAULT_VALUES
		if PROTO_VERSION == 2:
			DEFAULT_VALUES = DEFAULT_VALUES_2
		elif PROTO_VERSION == 3:
			DEFAULT_VALUES = DEFAULT_VALUES_3
		var result : String = ""
		var keys : Array = data.keys()
		keys.sort()
		for i in keys:
			if data[i].field.value != null:
				if data[i].state == PB_SERVICE_STATE.UNFILLED \
				&& !data[i].field.is_map_field \
				&& typeof(data[i].field.value) == typeof(DEFAULT_VALUES[data[i].field.type]) \
				&& data[i].field.value == DEFAULT_VALUES[data[i].field.type]:
					continue
				elif data[i].field.rule == PB_RULE.REPEATED && data[i].field.value.size() == 0:
					continue
				result += field_to_string(data[i].field, nesting)
			elif data[i].field.rule == PB_RULE.REQUIRED:
				result += data[i].field.name + ": " + "error"
		return result



############### USER DATA BEGIN ################


class ClientPacket:
	func _init():
		var service

		__room_create = PBField.new("room_create", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __room_create
		service.func_ref = Callable(self, "new_room_create")
		data[__room_create.tag] = service

		__room_join = PBField.new("room_join", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __room_join
		service.func_ref = Callable(self, "new_room_join")
		data[__room_join.tag] = service

		__room_leave = PBField.new("room_leave", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __room_leave
		service.func_ref = Callable(self, "new_room_leave")
		data[__room_leave.tag] = service

		__relay = PBField.new("relay", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __relay
		service.func_ref = Callable(self, "new_relay")
		data[__relay.tag] = service

		__request_id = PBField.new("request_id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 10, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __request_id
		data[__request_id.tag] = service

	var data = {}

	enum PayloadCase {
		PAYLOAD_NOT_SET = 0,
		ROOM_CREATE = 1,
		ROOM_JOIN = 2,
		ROOM_LEAVE = 3,
		RELAY = 4,
	}
	var _payload_case: int = 0

	var __room_create: PBField
	func has_room_create() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_room_create() -> ClientRoomCreate:
		return __room_create.value
	func clear_room_create() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__room_create.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_room_create() -> ClientRoomCreate:
		data[1].state = PB_SERVICE_STATE.FILLED
		_payload_case = 1
		__room_join.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__room_leave.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__relay.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__room_create.value = ClientRoomCreate.new()
		return __room_create.value

	var __room_join: PBField
	func has_room_join() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_room_join() -> ClientRoomJoin:
		return __room_join.value
	func clear_room_join() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__room_join.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_room_join() -> ClientRoomJoin:
		__room_create.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[1].state = PB_SERVICE_STATE.UNFILLED
		data[2].state = PB_SERVICE_STATE.FILLED
		_payload_case = 2
		__room_leave.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__relay.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__room_join.value = ClientRoomJoin.new()
		return __room_join.value

	var __room_leave: PBField
	func has_room_leave() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_room_leave() -> ClientRoomLeave:
		return __room_leave.value
	func clear_room_leave() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__room_leave.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_room_leave() -> ClientRoomLeave:
		__room_create.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__room_join.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[2].state = PB_SERVICE_STATE.UNFILLED
		data[3].state = PB_SERVICE_STATE.FILLED
		_payload_case = 3
		__relay.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__room_leave.value = ClientRoomLeave.new()
		return __room_leave.value

	var __relay: PBField
	func has_relay() -> bool:
		return data[4].state == PB_SERVICE_STATE.FILLED
	func get_relay() -> ClientRelay:
		return __relay.value
	func clear_relay() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__relay.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_relay() -> ClientRelay:
		__room_create.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__room_join.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__room_leave.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[3].state = PB_SERVICE_STATE.UNFILLED
		data[4].state = PB_SERVICE_STATE.FILLED
		_payload_case = 4
		__relay.value = ClientRelay.new()
		return __relay.value

	var __request_id: PBField
	func has_request_id() -> bool:
		if __request_id.value != null:
			return true
		return false
	func get_request_id() -> int:
		return __request_id.value
	func clear_request_id() -> void:
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__request_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_request_id(value : int) -> void:
		__request_id.value = value

	func get_payload_case() -> int:
		return _payload_case
	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class ServerPacket:
	func _init():
		var service

		__connected = PBField.new("connected", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __connected
		service.func_ref = Callable(self, "new_connected")
		data[__connected.tag] = service

		__room_list = PBField.new("room_list", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __room_list
		service.func_ref = Callable(self, "new_room_list")
		data[__room_list.tag] = service

		__room_updated = PBField.new("room_updated", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __room_updated
		service.func_ref = Callable(self, "new_room_updated")
		data[__room_updated.tag] = service

		__room_removed = PBField.new("room_removed", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __room_removed
		service.func_ref = Callable(self, "new_room_removed")
		data[__room_removed.tag] = service

		__room_joined = PBField.new("room_joined", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 5, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __room_joined
		service.func_ref = Callable(self, "new_room_joined")
		data[__room_joined.tag] = service

		__room_left = PBField.new("room_left", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 6, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __room_left
		service.func_ref = Callable(self, "new_room_left")
		data[__room_left.tag] = service

		__peer_joined = PBField.new("peer_joined", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 7, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __peer_joined
		service.func_ref = Callable(self, "new_peer_joined")
		data[__peer_joined.tag] = service

		__peer_left = PBField.new("peer_left", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 8, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __peer_left
		service.func_ref = Callable(self, "new_peer_left")
		data[__peer_left.tag] = service

		__relay = PBField.new("relay", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 9, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __relay
		service.func_ref = Callable(self, "new_relay")
		data[__relay.tag] = service

		__error = PBField.new("error", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 10, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __error
		service.func_ref = Callable(self, "new_error")
		data[__error.tag] = service

		__request_id = PBField.new("request_id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 11, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __request_id
		data[__request_id.tag] = service

	var data = {}

	enum PayloadCase {
		PAYLOAD_NOT_SET = 0,
		CONNECTED = 1,
		ROOM_LIST = 2,
		ROOM_UPDATED = 3,
		ROOM_REMOVED = 4,
		ROOM_JOINED = 5,
		ROOM_LEFT = 6,
		PEER_JOINED = 7,
		PEER_LEFT = 8,
		RELAY = 9,
		ERROR = 10,
	}
	var _payload_case: int = 0

	var __connected: PBField
	func has_connected() -> bool:
		return data[1].state == PB_SERVICE_STATE.FILLED
	func get_connected() -> ClientConnected:
		return __connected.value
	func clear_connected() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__connected.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_connected() -> ClientConnected:
		data[1].state = PB_SERVICE_STATE.FILLED
		_payload_case = 1
		__room_list.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__room_updated.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__room_removed.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__room_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__room_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__peer_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__peer_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__relay.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[9].state = PB_SERVICE_STATE.UNFILLED
		__error.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__connected.value = ClientConnected.new()
		return __connected.value

	var __room_list: PBField
	func has_room_list() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_room_list() -> ServerRoomList:
		return __room_list.value
	func clear_room_list() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__room_list.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_room_list() -> ServerRoomList:
		__connected.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[1].state = PB_SERVICE_STATE.UNFILLED
		data[2].state = PB_SERVICE_STATE.FILLED
		_payload_case = 2
		__room_updated.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__room_removed.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__room_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__room_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__peer_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__peer_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__relay.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[9].state = PB_SERVICE_STATE.UNFILLED
		__error.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__room_list.value = ServerRoomList.new()
		return __room_list.value

	var __room_updated: PBField
	func has_room_updated() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_room_updated() -> ServerRoomUpdated:
		return __room_updated.value
	func clear_room_updated() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__room_updated.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_room_updated() -> ServerRoomUpdated:
		__connected.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__room_list.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[2].state = PB_SERVICE_STATE.UNFILLED
		data[3].state = PB_SERVICE_STATE.FILLED
		_payload_case = 3
		__room_removed.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__room_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__room_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__peer_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__peer_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__relay.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[9].state = PB_SERVICE_STATE.UNFILLED
		__error.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__room_updated.value = ServerRoomUpdated.new()
		return __room_updated.value

	var __room_removed: PBField
	func has_room_removed() -> bool:
		return data[4].state == PB_SERVICE_STATE.FILLED
	func get_room_removed() -> ServerRoomRemoved:
		return __room_removed.value
	func clear_room_removed() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__room_removed.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_room_removed() -> ServerRoomRemoved:
		__connected.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__room_list.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__room_updated.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[3].state = PB_SERVICE_STATE.UNFILLED
		data[4].state = PB_SERVICE_STATE.FILLED
		_payload_case = 4
		__room_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__room_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__peer_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__peer_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__relay.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[9].state = PB_SERVICE_STATE.UNFILLED
		__error.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__room_removed.value = ServerRoomRemoved.new()
		return __room_removed.value

	var __room_joined: PBField
	func has_room_joined() -> bool:
		return data[5].state == PB_SERVICE_STATE.FILLED
	func get_room_joined() -> ServerRoomJoined:
		return __room_joined.value
	func clear_room_joined() -> void:
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__room_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_room_joined() -> ServerRoomJoined:
		__connected.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__room_list.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__room_updated.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__room_removed.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[4].state = PB_SERVICE_STATE.UNFILLED
		data[5].state = PB_SERVICE_STATE.FILLED
		_payload_case = 5
		__room_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__peer_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__peer_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__relay.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[9].state = PB_SERVICE_STATE.UNFILLED
		__error.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__room_joined.value = ServerRoomJoined.new()
		return __room_joined.value

	var __room_left: PBField
	func has_room_left() -> bool:
		return data[6].state == PB_SERVICE_STATE.FILLED
	func get_room_left() -> ServerRoomLeft:
		return __room_left.value
	func clear_room_left() -> void:
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__room_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_room_left() -> ServerRoomLeft:
		__connected.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__room_list.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__room_updated.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__room_removed.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__room_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[5].state = PB_SERVICE_STATE.UNFILLED
		data[6].state = PB_SERVICE_STATE.FILLED
		_payload_case = 6
		__peer_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__peer_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__relay.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[9].state = PB_SERVICE_STATE.UNFILLED
		__error.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__room_left.value = ServerRoomLeft.new()
		return __room_left.value

	var __peer_joined: PBField
	func has_peer_joined() -> bool:
		return data[7].state == PB_SERVICE_STATE.FILLED
	func get_peer_joined() -> ServerPeerJoined:
		return __peer_joined.value
	func clear_peer_joined() -> void:
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__peer_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_peer_joined() -> ServerPeerJoined:
		__connected.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__room_list.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__room_updated.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__room_removed.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__room_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__room_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[6].state = PB_SERVICE_STATE.UNFILLED
		data[7].state = PB_SERVICE_STATE.FILLED
		_payload_case = 7
		__peer_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__relay.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[9].state = PB_SERVICE_STATE.UNFILLED
		__error.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__peer_joined.value = ServerPeerJoined.new()
		return __peer_joined.value

	var __peer_left: PBField
	func has_peer_left() -> bool:
		return data[8].state == PB_SERVICE_STATE.FILLED
	func get_peer_left() -> ServerPeerLeft:
		return __peer_left.value
	func clear_peer_left() -> void:
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__peer_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_peer_left() -> ServerPeerLeft:
		__connected.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__room_list.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__room_updated.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__room_removed.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__room_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__room_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__peer_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[7].state = PB_SERVICE_STATE.UNFILLED
		data[8].state = PB_SERVICE_STATE.FILLED
		_payload_case = 8
		__relay.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[9].state = PB_SERVICE_STATE.UNFILLED
		__error.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__peer_left.value = ServerPeerLeft.new()
		return __peer_left.value

	var __relay: PBField
	func has_relay() -> bool:
		return data[9].state == PB_SERVICE_STATE.FILLED
	func get_relay() -> ServerRelay:
		return __relay.value
	func clear_relay() -> void:
		data[9].state = PB_SERVICE_STATE.UNFILLED
		__relay.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_relay() -> ServerRelay:
		__connected.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__room_list.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__room_updated.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__room_removed.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__room_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__room_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__peer_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__peer_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[8].state = PB_SERVICE_STATE.UNFILLED
		data[9].state = PB_SERVICE_STATE.FILLED
		_payload_case = 9
		__error.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__relay.value = ServerRelay.new()
		return __relay.value

	var __error: PBField
	func has_error() -> bool:
		return data[10].state == PB_SERVICE_STATE.FILLED
	func get_error() -> ServerError:
		return __error.value
	func clear_error() -> void:
		data[10].state = PB_SERVICE_STATE.UNFILLED
		__error.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_error() -> ServerError:
		__connected.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__room_list.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__room_updated.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__room_removed.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__room_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__room_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[6].state = PB_SERVICE_STATE.UNFILLED
		__peer_joined.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[7].state = PB_SERVICE_STATE.UNFILLED
		__peer_left.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[8].state = PB_SERVICE_STATE.UNFILLED
		__relay.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[9].state = PB_SERVICE_STATE.UNFILLED
		data[10].state = PB_SERVICE_STATE.FILLED
		_payload_case = 10
		__error.value = ServerError.new()
		return __error.value

	var __request_id: PBField
	func has_request_id() -> bool:
		if __request_id.value != null:
			return true
		return false
	func get_request_id() -> int:
		return __request_id.value
	func clear_request_id() -> void:
		data[11].state = PB_SERVICE_STATE.UNFILLED
		__request_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_request_id(value : int) -> void:
		__request_id.value = value

	func get_payload_case() -> int:
		return _payload_case
	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class Room:
	func _init():
		var service

		__id = PBField.new("id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __id
		data[__id.tag] = service

		__name = PBField.new("name", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __name
		data[__name.tag] = service

		__player_count = PBField.new("player_count", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __player_count
		data[__player_count.tag] = service

		__world_id = PBField.new("world_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __world_id
		data[__world_id.tag] = service

	var data = {}

	var __id: PBField
	func has_id() -> bool:
		if __id.value != null:
			return true
		return false
	func get_id() -> int:
		return __id.value
	func clear_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_id(value : int) -> void:
		__id.value = value

	var __name: PBField
	func has_name() -> bool:
		if __name.value != null:
			return true
		return false
	func get_name() -> String:
		return __name.value
	func clear_name() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__name.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_name(value : String) -> void:
		__name.value = value

	var __player_count: PBField
	func has_player_count() -> bool:
		if __player_count.value != null:
			return true
		return false
	func get_player_count() -> int:
		return __player_count.value
	func clear_player_count() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__player_count.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_player_count(value : int) -> void:
		__player_count.value = value

	var __world_id: PBField
	func has_world_id() -> bool:
		if __world_id.value != null:
			return true
		return false
	func get_world_id() -> String:
		return __world_id.value
	func clear_world_id() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__world_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_world_id(value : String) -> void:
		__world_id.value = value

	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class Peer:
	func _init():
		var service

		__id = PBField.new("id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __id
		data[__id.tag] = service

		__session_id = PBField.new("session_id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __session_id
		data[__session_id.tag] = service

	var data = {}

	var __id: PBField
	func has_id() -> bool:
		if __id.value != null:
			return true
		return false
	func get_id() -> int:
		return __id.value
	func clear_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_id(value : int) -> void:
		__id.value = value

	var __session_id: PBField
	func has_session_id() -> bool:
		if __session_id.value != null:
			return true
		return false
	func get_session_id() -> int:
		return __session_id.value
	func clear_session_id() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__session_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_session_id(value : int) -> void:
		__session_id.value = value

	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class ClientRoomCreate:
	func _init():
		var service

		__name = PBField.new("name", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __name
		data[__name.tag] = service

		__world_id = PBField.new("world_id", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __world_id
		data[__world_id.tag] = service

	var data = {}

	var __name: PBField
	func has_name() -> bool:
		if __name.value != null:
			return true
		return false
	func get_name() -> String:
		return __name.value
	func clear_name() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__name.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_name(value : String) -> void:
		__name.value = value

	var __world_id: PBField
	func has_world_id() -> bool:
		if __world_id.value != null:
			return true
		return false
	func get_world_id() -> String:
		return __world_id.value
	func clear_world_id() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__world_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_world_id(value : String) -> void:
		__world_id.value = value

	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class ClientRoomJoin:
	func _init():
		var service

		__room_id = PBField.new("room_id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __room_id
		data[__room_id.tag] = service

		__recovery_room = PBField.new("recovery_room", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __recovery_room
		service.func_ref = Callable(self, "new_recovery_room")
		data[__recovery_room.tag] = service

		__client_id = PBField.new("client_id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __client_id
		data[__client_id.tag] = service

		__session_id = PBField.new("session_id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __session_id
		data[__session_id.tag] = service

	var data = {}

	var __room_id: PBField
	func has_room_id() -> bool:
		if __room_id.value != null:
			return true
		return false
	func get_room_id() -> int:
		return __room_id.value
	func clear_room_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__room_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_room_id(value : int) -> void:
		__room_id.value = value

	var __recovery_room: PBField
	func has_recovery_room() -> bool:
		if __recovery_room.value != null:
			return true
		return false
	func get_recovery_room() -> Room:
		return __recovery_room.value
	func clear_recovery_room() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__recovery_room.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_recovery_room() -> Room:
		__recovery_room.value = Room.new()
		return __recovery_room.value

	var __client_id: PBField
	func has_client_id() -> bool:
		if __client_id.value != null:
			return true
		return false
	func get_client_id() -> int:
		return __client_id.value
	func clear_client_id() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__client_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_client_id(value : int) -> void:
		__client_id.value = value

	var __session_id: PBField
	func has_session_id() -> bool:
		if __session_id.value != null:
			return true
		return false
	func get_session_id() -> int:
		return __session_id.value
	func clear_session_id() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__session_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_session_id(value : int) -> void:
		__session_id.value = value

	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class ClientRoomLeave:
	func _init():
		var service

	var data = {}

	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class ClientRelay:
	func _init():
		var service

		__destination_id = PBField.new("destination_id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __destination_id
		data[__destination_id.tag] = service

		__description = PBField.new("description", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __description
		service.func_ref = Callable(self, "new_description")
		data[__description.tag] = service

		__candidate = PBField.new("candidate", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __candidate
		service.func_ref = Callable(self, "new_candidate")
		data[__candidate.tag] = service

		__sender_session_id = PBField.new("sender_session_id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __sender_session_id
		data[__sender_session_id.tag] = service

		__destination_session_id = PBField.new("destination_session_id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 5, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __destination_session_id
		data[__destination_session_id.tag] = service

	var data = {}

	enum SignalCase {
		SIGNAL_NOT_SET = 0,
		DESCRIPTION = 2,
		CANDIDATE = 3,
	}
	var _signal_case: int = 0

	var __destination_id: PBField
	func has_destination_id() -> bool:
		if __destination_id.value != null:
			return true
		return false
	func get_destination_id() -> int:
		return __destination_id.value
	func clear_destination_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__destination_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_destination_id(value : int) -> void:
		__destination_id.value = value

	var __description: PBField
	func has_description() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_description() -> WebRTCSessionDescription:
		return __description.value
	func clear_description() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__description.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_description() -> WebRTCSessionDescription:
		data[2].state = PB_SERVICE_STATE.FILLED
		_signal_case = 2
		__candidate.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__description.value = WebRTCSessionDescription.new()
		return __description.value

	var __candidate: PBField
	func has_candidate() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_candidate() -> WebRTCIceCandidate:
		return __candidate.value
	func clear_candidate() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__candidate.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_candidate() -> WebRTCIceCandidate:
		__description.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[2].state = PB_SERVICE_STATE.UNFILLED
		data[3].state = PB_SERVICE_STATE.FILLED
		_signal_case = 3
		__candidate.value = WebRTCIceCandidate.new()
		return __candidate.value

	var __sender_session_id: PBField
	func has_sender_session_id() -> bool:
		if __sender_session_id.value != null:
			return true
		return false
	func get_sender_session_id() -> int:
		return __sender_session_id.value
	func clear_sender_session_id() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__sender_session_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_sender_session_id(value : int) -> void:
		__sender_session_id.value = value

	var __destination_session_id: PBField
	func has_destination_session_id() -> bool:
		if __destination_session_id.value != null:
			return true
		return false
	func get_destination_session_id() -> int:
		return __destination_session_id.value
	func clear_destination_session_id() -> void:
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__destination_session_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_destination_session_id(value : int) -> void:
		__destination_session_id.value = value

	func get_signal_case() -> int:
		return _signal_case
	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class ClientConnected:
	func _init():
		var service

		__client_id = PBField.new("client_id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __client_id
		data[__client_id.tag] = service

	var data = {}

	var __client_id: PBField
	func has_client_id() -> bool:
		if __client_id.value != null:
			return true
		return false
	func get_client_id() -> int:
		return __client_id.value
	func clear_client_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__client_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_client_id(value : int) -> void:
		__client_id.value = value

	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class ServerRoomList:
	func _init():
		var service

		var __rooms_default: Array[Room] = []
		__rooms = PBField.new("rooms", PB_DATA_TYPE.MESSAGE, PB_RULE.REPEATED, 1, true, __rooms_default)
		service = PBServiceField.new()
		service.field = __rooms
		service.func_ref = Callable(self, "add_rooms")
		data[__rooms.tag] = service

	var data = {}

	var __rooms: PBField
	func get_rooms() -> Array[Room]:
		return __rooms.value
	func clear_rooms() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__rooms.value.clear()
	func add_rooms() -> Room:
		var element = Room.new()
		__rooms.value.append(element)
		return element

	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class ServerRoomUpdated:
	func _init():
		var service

		__room = PBField.new("room", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __room
		service.func_ref = Callable(self, "new_room")
		data[__room.tag] = service

	var data = {}

	var __room: PBField
	func has_room() -> bool:
		if __room.value != null:
			return true
		return false
	func get_room() -> Room:
		return __room.value
	func clear_room() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__room.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_room() -> Room:
		__room.value = Room.new()
		return __room.value

	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class ServerRoomRemoved:
	func _init():
		var service

		__room_id = PBField.new("room_id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __room_id
		data[__room_id.tag] = service

	var data = {}

	var __room_id: PBField
	func has_room_id() -> bool:
		if __room_id.value != null:
			return true
		return false
	func get_room_id() -> int:
		return __room_id.value
	func clear_room_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__room_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_room_id(value : int) -> void:
		__room_id.value = value

	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class ServerRoomJoined:
	func _init():
		var service

		__room = PBField.new("room", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __room
		service.func_ref = Callable(self, "new_room")
		data[__room.tag] = service

		var __peers_default: Array[Peer] = []
		__peers = PBField.new("peers", PB_DATA_TYPE.MESSAGE, PB_RULE.REPEATED, 2, true, __peers_default)
		service = PBServiceField.new()
		service.field = __peers
		service.func_ref = Callable(self, "add_peers")
		data[__peers.tag] = service

		__session_id = PBField.new("session_id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __session_id
		data[__session_id.tag] = service

	var data = {}

	var __room: PBField
	func has_room() -> bool:
		if __room.value != null:
			return true
		return false
	func get_room() -> Room:
		return __room.value
	func clear_room() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__room.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_room() -> Room:
		__room.value = Room.new()
		return __room.value

	var __peers: PBField
	func get_peers() -> Array[Peer]:
		return __peers.value
	func clear_peers() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__peers.value.clear()
	func add_peers() -> Peer:
		var element = Peer.new()
		__peers.value.append(element)
		return element

	var __session_id: PBField
	func has_session_id() -> bool:
		if __session_id.value != null:
			return true
		return false
	func get_session_id() -> int:
		return __session_id.value
	func clear_session_id() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__session_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_session_id(value : int) -> void:
		__session_id.value = value

	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class ServerRoomLeft:
	func _init():
		var service

	var data = {}

	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class ServerPeerJoined:
	func _init():
		var service

		__peer = PBField.new("peer", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __peer
		service.func_ref = Callable(self, "new_peer")
		data[__peer.tag] = service

	var data = {}

	var __peer: PBField
	func has_peer() -> bool:
		if __peer.value != null:
			return true
		return false
	func get_peer() -> Peer:
		return __peer.value
	func clear_peer() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__peer.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_peer() -> Peer:
		__peer.value = Peer.new()
		return __peer.value

	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class ServerPeerLeft:
	func _init():
		var service

		__peer_id = PBField.new("peer_id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __peer_id
		data[__peer_id.tag] = service

		__signaling_disconnected = PBField.new("signaling_disconnected", PB_DATA_TYPE.BOOL, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL])
		service = PBServiceField.new()
		service.field = __signaling_disconnected
		data[__signaling_disconnected.tag] = service

	var data = {}

	var __peer_id: PBField
	func has_peer_id() -> bool:
		if __peer_id.value != null:
			return true
		return false
	func get_peer_id() -> int:
		return __peer_id.value
	func clear_peer_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__peer_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_peer_id(value : int) -> void:
		__peer_id.value = value

	var __signaling_disconnected: PBField
	func has_signaling_disconnected() -> bool:
		if __signaling_disconnected.value != null:
			return true
		return false
	func get_signaling_disconnected() -> bool:
		return __signaling_disconnected.value
	func clear_signaling_disconnected() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__signaling_disconnected.value = DEFAULT_VALUES_3[PB_DATA_TYPE.BOOL]
	func set_signaling_disconnected(value : bool) -> void:
		__signaling_disconnected.value = value

	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class ServerRelay:
	func _init():
		var service

		__sender_id = PBField.new("sender_id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __sender_id
		data[__sender_id.tag] = service

		__description = PBField.new("description", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __description
		service.func_ref = Callable(self, "new_description")
		data[__description.tag] = service

		__candidate = PBField.new("candidate", PB_DATA_TYPE.MESSAGE, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE])
		service = PBServiceField.new()
		service.field = __candidate
		service.func_ref = Callable(self, "new_candidate")
		data[__candidate.tag] = service

		__sender_session_id = PBField.new("sender_session_id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 4, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __sender_session_id
		data[__sender_session_id.tag] = service

		__destination_session_id = PBField.new("destination_session_id", PB_DATA_TYPE.UINT32, PB_RULE.OPTIONAL, 5, true, DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32])
		service = PBServiceField.new()
		service.field = __destination_session_id
		data[__destination_session_id.tag] = service

	var data = {}

	enum SignalCase {
		SIGNAL_NOT_SET = 0,
		DESCRIPTION = 2,
		CANDIDATE = 3,
	}
	var _signal_case: int = 0

	var __sender_id: PBField
	func has_sender_id() -> bool:
		if __sender_id.value != null:
			return true
		return false
	func get_sender_id() -> int:
		return __sender_id.value
	func clear_sender_id() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__sender_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_sender_id(value : int) -> void:
		__sender_id.value = value

	var __description: PBField
	func has_description() -> bool:
		return data[2].state == PB_SERVICE_STATE.FILLED
	func get_description() -> WebRTCSessionDescription:
		return __description.value
	func clear_description() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__description.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_description() -> WebRTCSessionDescription:
		data[2].state = PB_SERVICE_STATE.FILLED
		_signal_case = 2
		__candidate.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__description.value = WebRTCSessionDescription.new()
		return __description.value

	var __candidate: PBField
	func has_candidate() -> bool:
		return data[3].state == PB_SERVICE_STATE.FILLED
	func get_candidate() -> WebRTCIceCandidate:
		return __candidate.value
	func clear_candidate() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__candidate.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
	func new_candidate() -> WebRTCIceCandidate:
		__description.value = DEFAULT_VALUES_3[PB_DATA_TYPE.MESSAGE]
		data[2].state = PB_SERVICE_STATE.UNFILLED
		data[3].state = PB_SERVICE_STATE.FILLED
		_signal_case = 3
		__candidate.value = WebRTCIceCandidate.new()
		return __candidate.value

	var __sender_session_id: PBField
	func has_sender_session_id() -> bool:
		if __sender_session_id.value != null:
			return true
		return false
	func get_sender_session_id() -> int:
		return __sender_session_id.value
	func clear_sender_session_id() -> void:
		data[4].state = PB_SERVICE_STATE.UNFILLED
		__sender_session_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_sender_session_id(value : int) -> void:
		__sender_session_id.value = value

	var __destination_session_id: PBField
	func has_destination_session_id() -> bool:
		if __destination_session_id.value != null:
			return true
		return false
	func get_destination_session_id() -> int:
		return __destination_session_id.value
	func clear_destination_session_id() -> void:
		data[5].state = PB_SERVICE_STATE.UNFILLED
		__destination_session_id.value = DEFAULT_VALUES_3[PB_DATA_TYPE.UINT32]
	func set_destination_session_id(value : int) -> void:
		__destination_session_id.value = value

	func get_signal_case() -> int:
		return _signal_case
	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class WebRTCSessionDescription:
	func _init():
		var service

		__type = PBField.new("type", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __type
		data[__type.tag] = service

		__sdp = PBField.new("sdp", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __sdp
		data[__sdp.tag] = service

	var data = {}

	var __type: PBField
	func has_type() -> bool:
		if __type.value != null:
			return true
		return false
	func get_type() -> String:
		return __type.value
	func clear_type() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__type.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_type(value : String) -> void:
		__type.value = value

	var __sdp: PBField
	func has_sdp() -> bool:
		if __sdp.value != null:
			return true
		return false
	func get_sdp() -> String:
		return __sdp.value
	func clear_sdp() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__sdp.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_sdp(value : String) -> void:
		__sdp.value = value

	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class WebRTCIceCandidate:
	func _init():
		var service

		__media = PBField.new("media", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __media
		data[__media.tag] = service

		__index = PBField.new("index", PB_DATA_TYPE.INT32, PB_RULE.OPTIONAL, 2, true, DEFAULT_VALUES_3[PB_DATA_TYPE.INT32])
		service = PBServiceField.new()
		service.field = __index
		data[__index.tag] = service

		__candidate = PBField.new("candidate", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 3, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __candidate
		data[__candidate.tag] = service

	var data = {}

	var __media: PBField
	func has_media() -> bool:
		if __media.value != null:
			return true
		return false
	func get_media() -> String:
		return __media.value
	func clear_media() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__media.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_media(value : String) -> void:
		__media.value = value

	var __index: PBField
	func has_index() -> bool:
		if __index.value != null:
			return true
		return false
	func get_index() -> int:
		return __index.value
	func clear_index() -> void:
		data[2].state = PB_SERVICE_STATE.UNFILLED
		__index.value = DEFAULT_VALUES_3[PB_DATA_TYPE.INT32]
	func set_index(value : int) -> void:
		__index.value = value

	var __candidate: PBField
	func has_candidate() -> bool:
		if __candidate.value != null:
			return true
		return false
	func get_candidate() -> String:
		return __candidate.value
	func clear_candidate() -> void:
		data[3].state = PB_SERVICE_STATE.UNFILLED
		__candidate.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_candidate(value : String) -> void:
		__candidate.value = value

	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

class ServerError:
	func _init():
		var service

		__reason = PBField.new("reason", PB_DATA_TYPE.STRING, PB_RULE.OPTIONAL, 1, true, DEFAULT_VALUES_3[PB_DATA_TYPE.STRING])
		service = PBServiceField.new()
		service.field = __reason
		data[__reason.tag] = service

	var data = {}

	var __reason: PBField
	func has_reason() -> bool:
		if __reason.value != null:
			return true
		return false
	func get_reason() -> String:
		return __reason.value
	func clear_reason() -> void:
		data[1].state = PB_SERVICE_STATE.UNFILLED
		__reason.value = DEFAULT_VALUES_3[PB_DATA_TYPE.STRING]
	func set_reason(value : String) -> void:
		__reason.value = value

	func _to_string() -> String:
		return PBPacker.message_to_string(data)

	func to_bytes() -> PackedByteArray:
		return PBPacker.pack_message(data)

	func from_bytes(bytes : PackedByteArray, offset : int = 0, limit : int = -1) -> int:
		var cur_limit = bytes.size()
		if limit != -1:
			cur_limit = limit
		var result = PBPacker.unpack_message(data, bytes, offset, cur_limit)
		if result == cur_limit:
			if PBPacker.check_required(data):
				if limit == -1:
					return PB_ERR.NO_ERRORS
			else:
				return PB_ERR.REQUIRED_FIELDS
		elif limit == -1 && result > 0:
			return PB_ERR.PARSE_INCOMPLETE
		return result

################ USER DATA END #################
