class_name BeachStore
extends RefCounted
## Binary container for the saved beach: the dug heightmap plus the loot state.
##
## The heightmap is 16 384 floats (64 KB raw) but it is mostly the untouched
## beach profile, so it is zstd-compressed before it is written: a heavily dug
## beach still comes out in single-digit kilobytes and saves never hitch.
##
## The format is a short little-endian header followed by two compressed blobs:
##   magic u32, version u32, vertex count u32,
##   heights length u32, heights bytes,
##   loot length u32, loot bytes.
##
## Decoding is defensive and treats the file as untrusted: a wrong magic, a
## version mismatch, a size mismatch, a failed decompression or a wrong vertex
## count all return an empty Dictionary so the caller keeps a pristine beach
## instead of loading nonsense into the terrain. Height values are clamped to the
## beach's real range (sea floor .. flat sand), so even a hand-edited file can
## only ever make a hole, never a spike.

const MAGIC := 0x42454143  # "BEAC"
const VERSION := 1
## Upper bound for the decompressed loot blob. The real snapshot is a few
## hundred bytes; anything bigger is a broken or hostile file.
const MAX_LOOT_BYTES := 1024 * 1024


## Packs a heightmap and a loot snapshot into the on-disk byte layout.
static func encode(heights: PackedFloat32Array, loot: Dictionary) -> PackedByteArray:
	var clean := PackedFloat32Array()
	clean.resize(heights.size())
	for i in heights.size():
		var height := heights[i]
		if is_nan(height) or is_inf(height):
			clean[i] = 0.0
		else:
			clean[i] = clampf(height, -SandTerrain.MAX_DEPTH, 0.0)

	var height_bytes := clean.to_byte_array().compress(FileAccess.COMPRESSION_ZSTD)
	var loot_bytes := var_to_bytes(loot).compress(FileAccess.COMPRESSION_ZSTD)

	var buffer := StreamPeerBuffer.new()
	buffer.put_32(MAGIC)
	buffer.put_32(VERSION)
	buffer.put_32(clean.size())
	buffer.put_32(height_bytes.size())
	buffer.put_data(height_bytes)
	buffer.put_32(loot_bytes.size())
	buffer.put_data(loot_bytes)
	return buffer.data_array


## Unpacks bytes written by `encode`. Returns `{heights, loot}`, or an empty
## Dictionary when the data cannot be trusted.
static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 24:
		return {}
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	if buffer.get_32() != MAGIC or buffer.get_32() != VERSION:
		return {}
	var count := int(buffer.get_32())
	if count != SandTerrain.GRID_SIZE * SandTerrain.GRID_SIZE:
		return {}
	if buffer.get_available_bytes() < 4:
		return {}

	var height_size := int(buffer.get_32())
	if height_size <= 0 or height_size > buffer.get_available_bytes():
		return {}
	var height_bytes: PackedByteArray = buffer.get_data(height_size)[1]
	var raw_heights := height_bytes.decompress(count * 4, FileAccess.COMPRESSION_ZSTD)
	if raw_heights.size() != count * 4:
		return {}

	if buffer.get_available_bytes() < 4:
		return {}
	var loot_size := int(buffer.get_32())
	if loot_size < 0 or loot_size > buffer.get_available_bytes():
		return {}

	var loot_data: Dictionary = {}
	if loot_size > 0:
		var loot_bytes: PackedByteArray = buffer.get_data(loot_size)[1]
		var raw_loot := loot_bytes.decompress(MAX_LOOT_BYTES, FileAccess.COMPRESSION_ZSTD)
		if raw_loot.is_empty():
			return {}
		var parsed: Variant = bytes_to_var(raw_loot)
		if typeof(parsed) != TYPE_DICTIONARY:
			return {}
		loot_data = parsed

	var heights := raw_heights.to_float32_array()
	for i in heights.size():
		var height := heights[i]
		if is_nan(height) or is_inf(height):
			heights[i] = 0.0
		else:
			heights[i] = clampf(height, -SandTerrain.MAX_DEPTH, 0.0)
	return {"heights": heights, "loot": loot_data}
