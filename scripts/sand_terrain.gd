class_name SandTerrain
extends StaticBody3D
## Heightmap sand terrain (Phase 2 prototype).
##
## Single source of truth: `heights` (GRID_SIZE * GRID_SIZE floats, row-major,
## index = z * GRID_SIZE + x). The visual surface is split into small chunk
## meshes so a dig only re-uploads the chunks that overlap the dirty rect --
## the full 128x128 surface is never rebuilt. Collision is a HeightMapShape3D
## kept in sync with `heights` after every dig.
##
## Grid spacing is CELL_SIZE metres; heightmap collision shapes always use a
## 1 m grid, so the collision node is scaled by CELL_SIZE on X/Z.

const GRID_SIZE := 128
const CELL_SIZE := 0.5
const MAX_DEPTH := 2.0

const HALF_GRID := (GRID_SIZE - 1) * 0.5
const CELL_AREA := CELL_SIZE * CELL_SIZE

## Visual chunks are 16x16 cells (17x17 vertices). 127 cells fit in 8 chunks.
const CHUNK_CELLS := 16
const CHUNKS_PER_SIDE := 8

const SAND_TOP_COLOR := Color(0.62, 0.5, 0.32)
const SAND_DEEP_COLOR := Color(0.24, 0.17, 0.09)

## The beach slopes into the sea on the -Z side. Inland (Z > SHORE_START_Z) the
## sand is flat at 0; past the start it drops smoothly to SEA_FLOOR by
## SHORE_END_Z, which is what lets the water plane cover it and the tide walk the
## waterline up and down the sand.
const SHORE_START_Z := -8.0
const SHORE_END_Z := -26.0
const SEA_FLOOR := -2.2

## Emitted after a dig that changed the heightmap. Loot, VFX and (later) the
## host's apply_dig broadcast all listen to this instead of polling heights.
signal dug(world_position: Vector3, radius: float, depth: float)

## Chunk-local mesh data. Rebuilt only when its region is dirty.
class Chunk:
	var index: int = 0
	var grid_x: int = 0
	var grid_z: int = 0
	var size_x: int = 0
	var size_z: int = 0
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var mesh: ArrayMesh
	var instance: MeshInstance3D

## Height of every grid vertex in metres (0 = untouched surface).
var heights := PackedFloat32Array()
## Last region passed to rebuild_mesh (debug/tests).
var last_dirty_rect := Rect2i()

var _chunks: Array[Chunk] = []
var _chunks_root: Node3D
var _collision: CollisionShape3D
var _heightmap := HeightMapShape3D.new()
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group("sand_terrain")
	heights.resize(GRID_SIZE * GRID_SIZE)
	heights.fill(0.0)
	_generate_beach()
	_material = _create_material()
	_setup_collision()
	_create_chunks()
	rebuild_mesh(Rect2i(0, 0, GRID_SIZE, GRID_SIZE))


## Carves the static beach profile into the heightmap before the first mesh
## build: flat sand inland, a smooth slope down into the sea toward -Z.
func _generate_beach() -> void:
	var span := SHORE_START_Z - SHORE_END_Z
	for z in GRID_SIZE:
		var world_z := (float(z) - HALF_GRID) * CELL_SIZE
		var t := clampf((SHORE_START_Z - world_z) / span, 0.0, 1.0)
		var smooth := t * t * (3.0 - 2.0 * t)
		var height := SEA_FLOOR * smooth
		var row := z * GRID_SIZE
		for x in GRID_SIZE:
			heights[row + x] = height


## Digs a smooth bowl into the sand at `world_pos`.
## Returns the removed volume in cubic metres (0 if nothing was removed).
##
## The footprint is padded by one cell (radius + CELL_SIZE) because vertices
## are 0.5 m apart: sampling a 0.15 m teaspoon bowl exactly at grid points would
## miss every vertex and dig nothing. The padding keeps the teaspoon carving a
## visible scoop while every tier still widens as its radius grows.
func dig_at(world_pos: Vector3, radius: float, depth: float) -> float:
	if radius <= 0.0 or depth <= 0.0:
		return 0.0

	var support := radius + CELL_SIZE
	var local_pos := to_local(world_pos)
	var grid_center := Vector2(
		local_pos.x / CELL_SIZE + HALF_GRID,
		local_pos.z / CELL_SIZE + HALF_GRID)
	var cell_radius := support / CELL_SIZE

	var min_x := maxi(floori(grid_center.x - cell_radius), 0)
	var max_x := mini(ceili(grid_center.x + cell_radius), GRID_SIZE - 1)
	var min_z := maxi(floori(grid_center.y - cell_radius), 0)
	var max_z := mini(ceili(grid_center.y + cell_radius), GRID_SIZE - 1)
	if min_x > max_x or min_z > max_z:
		return 0.0

	var dirty := Rect2i(min_x, min_z, max_x - min_x + 1, max_z - min_z + 1)
	var dug_volume := 0.0

	for z in range(min_z, max_z + 1):
		var world_dz := (float(z) - grid_center.y) * CELL_SIZE
		var row := z * GRID_SIZE
		for x in range(min_x, max_x + 1):
			var world_dx := (float(x) - grid_center.x) * CELL_SIZE
			var dist := sqrt(world_dx * world_dx + world_dz * world_dz)
			if dist > support:
				continue
			var falloff := 1.0 - pow(dist / support, 2.0)
			if falloff <= 0.0:
				continue
			var index := row + x
			var old_height := heights[index]
			var new_height := clampf(old_height - depth * falloff, -MAX_DEPTH, 0.0)
			if new_height < old_height - 0.000001:
				heights[index] = new_height
				# Approximate removed volume: one grid vertex owns one cell.
				dug_volume += (old_height - new_height) * CELL_AREA

	if dug_volume <= 0.0:
		return 0.0

	rebuild_mesh(dirty)
	_sync_collision()
	dug.emit(world_pos, radius, depth)
	return dug_volume


## Height of the sand surface at `world_pos` (bilinear between grid points).
## Returns 0.0 outside the grid.
func get_height_at(world_pos: Vector3) -> float:
	if heights.is_empty():
		return 0.0
	var local_pos := to_local(world_pos)
	var gx := local_pos.x / CELL_SIZE + HALF_GRID
	var gz := local_pos.z / CELL_SIZE + HALF_GRID
	if gx < 0.0 or gz < 0.0 or gx > GRID_SIZE - 1 or gz > GRID_SIZE - 1:
		return 0.0
	var x0 := int(floor(gx))
	var z0 := int(floor(gz))
	var x1 := mini(x0 + 1, GRID_SIZE - 1)
	var z1 := mini(z0 + 1, GRID_SIZE - 1)
	var tx := gx - float(x0)
	var tz := gz - float(z0)
	var h00 := heights[z0 * GRID_SIZE + x0]
	var h10 := heights[z0 * GRID_SIZE + x1]
	var h01 := heights[z1 * GRID_SIZE + x0]
	var h11 := heights[z1 * GRID_SIZE + x1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Re-uploads every chunk mesh that overlaps `dirty_rect`.
## Vertex positions, normals and colours are only recomputed for grid points
## inside the rect; untouched vertices of a chunk keep their cached data.
func rebuild_mesh(dirty_rect: Rect2i) -> void:
	var rect := _clamp_rect(dirty_rect)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	last_dirty_rect = rect

	var chunk_x_min := rect.position.x / CHUNK_CELLS
	var chunk_x_max := (rect.end.x - 1) / CHUNK_CELLS
	var chunk_z_min := rect.position.y / CHUNK_CELLS
	var chunk_z_max := (rect.end.y - 1) / CHUNK_CELLS

	for cz in range(chunk_z_min, chunk_z_max + 1):
		if cz < 0 or cz >= CHUNKS_PER_SIDE:
			continue
		for cx in range(chunk_x_min, chunk_x_max + 1):
			if cx < 0 or cx >= CHUNKS_PER_SIDE:
				continue
			var chunk := _chunks[cz * CHUNKS_PER_SIDE + cx]
			_update_chunk_region(chunk, rect)
			_upload_chunk(chunk)


func _clamp_rect(rect: Rect2i) -> Rect2i:
	var x0 := clampi(rect.position.x, 0, GRID_SIZE - 1)
	var z0 := clampi(rect.position.y, 0, GRID_SIZE - 1)
	var x1 := clampi(rect.end.x, 0, GRID_SIZE - 1)
	var z1 := clampi(rect.end.y, 0, GRID_SIZE - 1)
	return Rect2i(x0, z0, maxi(x1 - x0, 0), maxi(z1 - z0, 0))


func _update_chunk_region(chunk: Chunk, rect: Rect2i) -> void:
	var gx0 := maxi(rect.position.x, chunk.grid_x)
	var gx1 := mini(rect.end.x, chunk.grid_x + chunk.size_x - 1)
	var gz0 := maxi(rect.position.y, chunk.grid_z)
	var gz1 := mini(rect.end.y, chunk.grid_z + chunk.size_z - 1)
	if gx0 > gx1 or gz0 > gz1:
		return

	for gz in range(gz0, gz1 + 1):
		var local_z := gz - chunk.grid_z
		var row := gz * GRID_SIZE
		for gx in range(gx0, gx1 + 1):
			var local_x := gx - chunk.grid_x
			var vertex_index := local_z * chunk.size_x + local_x
			var height := heights[row + gx]
			chunk.vertices[vertex_index] = Vector3(local_x * CELL_SIZE, height, local_z * CELL_SIZE)
			chunk.normals[vertex_index] = _normal_at(gx, gz)
			chunk.colors[vertex_index] = _color_at(height)


func _upload_chunk(chunk: Chunk) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = chunk.vertices
	arrays[Mesh.ARRAY_NORMAL] = chunk.normals
	arrays[Mesh.ARRAY_COLOR] = chunk.colors
	arrays[Mesh.ARRAY_INDEX] = chunk.indices
	chunk.mesh.clear_surfaces()
	chunk.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	chunk.mesh.surface_set_material(0, _material)


func _normal_at(x: int, z: int) -> Vector3:
	var hl := heights[z * GRID_SIZE + maxi(x - 1, 0)]
	var hr := heights[z * GRID_SIZE + mini(x + 1, GRID_SIZE - 1)]
	var hb := heights[maxi(z - 1, 0) * GRID_SIZE + x]
	var hf := heights[mini(z + 1, GRID_SIZE - 1) * GRID_SIZE + x]
	var slope_x := (hr - hl) / (2.0 * CELL_SIZE)
	var slope_z := (hf - hb) / (2.0 * CELL_SIZE)
	return Vector3(-slope_x, 1.0, -slope_z).normalized()


func _color_at(height: float) -> Color:
	var depth_ratio := clampf(-height / MAX_DEPTH, 0.0, 1.0)
	return SAND_TOP_COLOR.lerp(SAND_DEEP_COLOR, pow(depth_ratio, 0.55))


func _create_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.metallic = 0.0
	material.metallic_specular = 0.15
	return material


func _setup_collision() -> void:
	_collision = get_node_or_null("TerrainCollision") as CollisionShape3D
	if _collision == null:
		_collision = CollisionShape3D.new()
		_collision.name = "TerrainCollision"
		add_child(_collision)
	_heightmap.map_width = GRID_SIZE
	_heightmap.map_depth = GRID_SIZE
	_heightmap.map_data = heights
	_collision.shape = _heightmap
	# HeightMapShape3D always uses a 1 m grid; shrink X/Z to CELL_SIZE.
	_collision.scale = Vector3(CELL_SIZE, 1.0, CELL_SIZE)


func _sync_collision() -> void:
	_heightmap.map_data = heights


func _create_chunks() -> void:
	_chunks_root = get_node_or_null("TerrainChunks") as Node3D
	if _chunks_root == null:
		_chunks_root = Node3D.new()
		_chunks_root.name = "TerrainChunks"
		add_child(_chunks_root)

	_chunks.clear()
	for cz in CHUNKS_PER_SIDE:
		for cx in CHUNKS_PER_SIDE:
			var chunk := Chunk.new()
			chunk.index = cz * CHUNKS_PER_SIDE + cx
			chunk.grid_x = cx * CHUNK_CELLS
			chunk.grid_z = cz * CHUNK_CELLS
			chunk.size_x = mini(CHUNK_CELLS, GRID_SIZE - 1 - chunk.grid_x) + 1
			chunk.size_z = mini(CHUNK_CELLS, GRID_SIZE - 1 - chunk.grid_z) + 1
			_build_chunk_arrays(chunk)
			chunk.mesh = ArrayMesh.new()
			chunk.mesh.resource_name = "SandChunk%d" % chunk.index
			chunk.instance = MeshInstance3D.new()
			chunk.instance.name = "SandChunk%d" % chunk.index
			chunk.instance.mesh = chunk.mesh
			chunk.instance.position = Vector3(
				(chunk.grid_x - HALF_GRID) * CELL_SIZE,
				0.0,
				(chunk.grid_z - HALF_GRID) * CELL_SIZE)
			_chunks_root.add_child(chunk.instance)
			_chunks.append(chunk)


func _build_chunk_arrays(chunk: Chunk) -> void:
	var vertex_count := chunk.size_x * chunk.size_z
	chunk.vertices.resize(vertex_count)
	chunk.normals.resize(vertex_count)
	chunk.colors.resize(vertex_count)
	for i in vertex_count:
		chunk.normals[i] = Vector3.UP
		chunk.colors[i] = SAND_TOP_COLOR

	chunk.indices.resize((chunk.size_x - 1) * (chunk.size_z - 1) * 6)
	var write := 0
	for z in chunk.size_z - 1:
		for x in chunk.size_x - 1:
			var a := (z + 1) * chunk.size_x + x
			var b := z * chunk.size_x + x
			var c := z * chunk.size_x + x + 1
			var d := (z + 1) * chunk.size_x + x + 1
			# Same triangle split as HeightMapShape3D so visuals match collision.
			chunk.indices[write] = a
			chunk.indices[write + 1] = b
			chunk.indices[write + 2] = c
			chunk.indices[write + 3] = a
			chunk.indices[write + 4] = c
			chunk.indices[write + 5] = d
			write += 6
