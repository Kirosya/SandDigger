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
## How far down a spot can be dug. Deep enough that a real shaft is possible and
## the endgame chest can hide well below the reach of the early shovels.
const MAX_DEPTH := 8.0

## --- Sand that does not stand in a wall ------------------------------------
##
## Dry beach sand has an angle of repose: a vertical wall is impossible, so a
## narrow hole caves in and half-buries itself again. That is also the game's
## rhythm - you cannot sink a 1 m wide tube to the bottom, you have to keep
## widening the pit - so the numbers matter.
##
## `SAND_SLOPE_STEP` is how much one grid cell (0.5 m) may drop relative to its
## neighbour before sand slides: 0.50 m over 0.5 m is ~45 degrees. `SLUMP_PASSES`
## lets the collapse travel a couple of cells per scoop, and `SLUMP_RELAX` how
## much of the offending step is moved per pass (volume is conserved, so what
## falls in has to come from the wall).
const SAND_SLOPE_STEP := 0.50
const SLUMP_PASSES := 3
const SLUMP_RELAX := 0.50
## How far below the natural sea bed a wet spot may be dug, so the surf never
## gets a hole punched through it.
const SEA_DIG_MARGIN := 1.4

## --- Sand packs harder the deeper you go -----------------------------------
##
## A shovel is at full strength on the surface and loses bite as the hole gets
## deep: the sand is compacted, the swing has less room, and there is more of it
## above you. `HARDEN_DEPTH` is how many metres of depth it takes to reach the
## weakest the tool ever gets (`HARDEN_MIN`), so a top-tier shovel still works
## down there, just far more slowly than on the beach.
const HARDEN_DEPTH := 8.0
const HARDEN_MIN := 0.40

const HALF_GRID := (GRID_SIZE - 1) * 0.5
const CELL_AREA := CELL_SIZE * CELL_SIZE

## Visual chunks are 16x16 cells (17x17 vertices). 127 cells fit in 8 chunks.
const CHUNK_CELLS := 16
const CHUNKS_PER_SIDE := 8

const SAND_TOP_COLOR := Color(0.62, 0.5, 0.32)
const SAND_DEEP_COLOR := Color(0.24, 0.17, 0.09)
## Recently wetted sand reads darker and a little grey. Sea pushes the current
## waterline in, so this is the band that visibly walks up and down the beach.
const SAND_WET_COLOR := Color(0.30, 0.26, 0.18)
## The sand fades into these at the inland edges: pine forest floor on +X and
## leaf litter where the fallen-log barriers sit on -X and +Z.
const FOREST_FLOOR_COLOR := Color(0.22, 0.30, 0.14)
const LEAF_LITTER_COLOR := Color(0.40, 0.32, 0.18)

## The beach slopes into the sea on the -Z side only. Inland (Z > SHORE_START_Z)
## the sand is flat at 0; past the start it drops on a long, smooth curve to
## SEA_FLOOR by SHORE_END_Z. The wide shallow slope is what makes the sea look
## like it gradually gets deeper, and gives the tide room to move the waterline.
const SHORE_START_Z := -8.0
const SHORE_END_Z := -30.0
const SEA_FLOOR := -2.8

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
## The beach exactly as generated, before any digging. The sea reads its
## waterline from this, so carving a hole can never drag the shoreline inland
## (which would slide the water plane up over dry sand).
var base_heights := PackedFloat32Array()
## World Z of the current waterline. Sea pushes it in as the tide moves, which
## tints the sand at and below it wet; the colour fades back to dry sand inland.
var wet_line_z := SHORE_START_Z
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
	base_heights.resize(GRID_SIZE * GRID_SIZE)
	for z in GRID_SIZE:
		var world_z := (float(z) - HALF_GRID) * CELL_SIZE
		var t := clampf((SHORE_START_Z - world_z) / span, 0.0, 1.0)
		var smooth := t * t * (3.0 - 2.0 * t)
		var height := SEA_FLOOR * smooth
		var row := z * GRID_SIZE
		for x in GRID_SIZE:
			heights[row + x] = height
			base_heights[row + x] = height


## How much of its nominal bite a shovel still gets at `world_pos`. Full power
## on the surface, `HARDEN_MIN` at the bottom of the sand.
func dig_power_at(world_pos: Vector3) -> float:
	return clampf(1.0 + get_height_at(world_pos) / HARDEN_DEPTH, HARDEN_MIN, 1.0)


## Digs a smooth bowl into the sand at `world_pos`.
## Returns the removed volume in cubic metres (0 if nothing was removed).
##
## The footprint is padded by one cell (radius + CELL_SIZE) because vertices
## are 0.5 m apart: sampling a 0.15 m teaspoon bowl exactly at grid points would
## miss every vertex and dig nothing. The padding keeps the teaspoon carving a
## visible scoop while every tier still widens as its radius grows.
##
## After the scoop the walls are given a chance to collapse (`_settle_sand`), so
## the hole that survives is the one the sand allows: a wide pit holds, a narrow
## shaft fills itself back in. The whole thing is deterministic because clients
## replay it through `apply_dig`.
func dig_at(world_pos: Vector3, radius: float, depth: float) -> float:
	last_dig_changed = false
	if radius <= 0.0 or depth <= 0.0:
		return 0.0

	# Deep sand is hard sand: the scoop (both its area and its bite) shrinks with
	# the depth of the hole it is made in. Applied here, from the heightmap, so a
	# client replaying the host call gets exactly the same scoop.
	var power := dig_power_at(world_pos)
	radius *= power
	depth *= lerpf(1.0, power, 0.5)

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
	# Snapshot the sand first: the collapse runs outward, and the XP has to be
	# what is actually gone once the walls have fallen in, not what the scoop
	# removed on paper.
	var area := _clamp_rect(dirty.grow(3))
	var before := _copy_region(area)

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
			var floor_limit := -MAX_DEPTH
			# Wet sand under the sea keeps a floor, so a dig in the surf cannot
			# open a hole in the sea bed.
			if base_heights[index] < -0.05:
				floor_limit = maxf(-MAX_DEPTH, base_heights[index] - SEA_DIG_MARGIN)
			var new_height := clampf(old_height - depth * falloff, floor_limit, 0.0)
			if new_height < old_height - 0.000001:
				heights[index] = new_height

	_settle_sand(area)
	if not _region_changed(before, area):
		return 0.0
	# The scoop and the collapse both moved sand, so the mesh has to be rebuilt
	# even when the net loss is zero (a fully refilled hole still changed shape),
	# and the dig has to be broadcast for the same reason: the shape changed even
	# when nothing was carried away.
	last_dig_changed = true
	var dug_volume := _volume_lost(before, area)
	rebuild_mesh(area)
	_sync_collision()
	dug.emit(world_pos, radius, depth)
	return dug_volume


## One pass of "too steep, sand slides" over `area`, repeated a few times so the
## collapse walks outward from the fresh scoop instead of leaving a cliff.
##
## Volume conserving and order dependent but fully deterministic: the host and
## every client run the exact same loop over the exact same heights.
func _settle_sand(area: Rect2i) -> void:
	var rect := _clamp_rect(area)
	for _pass in SLUMP_PASSES:
		var slid := false
		for z in range(rect.position.y, rect.end.y):
			var row := z * GRID_SIZE
			for x in range(rect.position.x, rect.end.x):
				var index := row + x
				var height := heights[index]
				var lowest := height
				var lowest_index := -1
				if x > 0 and heights[index - 1] < lowest:
					lowest = heights[index - 1]
					lowest_index = index - 1
				if x < GRID_SIZE - 1 and heights[index + 1] < lowest:
					lowest = heights[index + 1]
					lowest_index = index + 1
				if z > 0 and heights[index - GRID_SIZE] < lowest:
					lowest = heights[index - GRID_SIZE]
					lowest_index = index - GRID_SIZE
				if z < GRID_SIZE - 1 and heights[index + GRID_SIZE] < lowest:
					lowest = heights[index + GRID_SIZE]
					lowest_index = index + GRID_SIZE
				if lowest_index < 0:
					continue
				var step := height - lowest
				if step <= SAND_SLOPE_STEP:
					continue
				var moved := (step - SAND_SLOPE_STEP) * SLUMP_RELAX
				heights[index] -= moved
				heights[lowest_index] += moved
				slid = true
		if not slid:
			return


## Copies the rectangle into a flat array laid out row by row, for measuring how
## much sand the scoop plus the collapse actually removed.
func _copy_region(rect: Rect2i) -> PackedFloat32Array:
	var copy := PackedFloat32Array()
	copy.resize(rect.size.x * rect.size.y)
	var out := 0
	for z in range(rect.position.y, rect.end.y):
		var row := z * GRID_SIZE
		for x in range(rect.position.x, rect.end.x):
			copy[out] = heights[row + x]
			out += 1
	return copy


## Net sand lost inside `rect` since `before` was taken (never negative).
func _volume_lost(before: PackedFloat32Array, rect: Rect2i) -> float:
	var lost := 0.0
	var i := 0
	for z in range(rect.position.y, rect.end.y):
		var row := z * GRID_SIZE
		for x in range(rect.position.x, rect.end.x):
			lost += before[i] - heights[row + x]
			i += 1
	return maxf(lost * CELL_AREA, 0.0)


## True when any grid point inside `rect` differs from the snapshot, even by a
## hair. Used to rebuild the mesh after a collapse that put every grain back.
func _region_changed(before: PackedFloat32Array, rect: Rect2i) -> bool:
	var i := 0
	for z in range(rect.position.y, rect.end.y):
		var row := z * GRID_SIZE
		for x in range(rect.position.x, rect.end.x):
			if absf(before[i] - heights[row + x]) > 0.000001:
				return true
			i += 1
	return false


## --- Multiplayer ---------------------------------------------------------

## How far a dig request may land from the player who sent it. A little over the
## best shovel's reach so a small position desync never rejects a legitimate dig.
const MAX_DIG_DISTANCE := 9.0

var _dig_stamps: Dictionary = {}

## Set by `dig_at` on every call: true when the scoop or the collapse changed the
## heightmap at all. A dig can move sand around and still net zero (a hole that
## filled itself back in), and those still have to be broadcast or the host and a
## client would drift apart.
var last_dig_changed := false


## Offline or host: this machine owns the sand. Clients only mirror it.
func is_authority() -> bool:
	return Net.is_host()


func export_heights() -> PackedFloat32Array:
	return heights.duplicate()


## Replaces the whole heightmap (late join) and rebuilds every chunk once.
func set_heights(data: PackedFloat32Array) -> void:
	if data.size() != heights.size():
		push_warning("set_heights: size mismatch %d != %d" % [data.size(), heights.size()])
		return
	heights = data.duplicate()
	rebuild_mesh(Rect2i(0, 0, GRID_SIZE, GRID_SIZE))
	_sync_collision()


## Entry point for a player's shovel. The host carves the sand and broadcasts;
## a client only asks the host and lets the broadcast carve its copy.
func submit_dig(world_position: Vector3, player_id: int, tier_index: int) -> void:
	if not Net.is_online() or Net.is_host():
		host_dig(world_position, player_id, tier_index)
	else:
		rpc_id(1, "request_dig", world_position, player_id, tier_index)


@rpc("any_peer", "call_remote", "reliable")
func request_dig(world_position: Vector3, player_id: int, tier_index: int) -> void:
	if not Net.is_host():
		print("[dig] request ignored: not host")
		return
	if multiplayer.get_remote_sender_id() != player_id:
		print("[dig] request rejected: sender %d != player %d" % [multiplayer.get_remote_sender_id(), player_id])
		return
	var now := Time.get_ticks_msec()
	if now - int(_dig_stamps.get(player_id, -100000)) < 120:
		print("[dig] request rejected: cooldown")
		return
	_dig_stamps[player_id] = now
	var player := Net.player_by_id(player_id)
	if player == null:
		print("[dig] request rejected: no player %d" % player_id)
		return
	var distance := player.global_position.distance_to(world_position)
	if distance > MAX_DIG_DISTANCE:
		print("[dig] request rejected: %.2f m away" % distance)
		return
	host_dig(world_position, player_id, tier_index)


## Carves the sand for `player_id`, tells every peer, and awards the XP.
func host_dig(world_position: Vector3, player_id: int, tier_index: int) -> float:
	var state := _state_for(player_id)
	var tiers := EquipmentData.default_tiers()
	var equipment: EquipmentData = tiers[clampi(tier_index, 0, tiers.size() - 1)]
	var volume := dig_at(world_position, equipment.radius, equipment.depth)
	if not last_dig_changed:
		return 0.0
	if Net.is_online():
		rpc("apply_dig", world_position, equipment.radius, equipment.depth)
	if state != null and volume > 0.0:
		state.add_dig_volume(volume)
		if Net.is_online() and player_id != multiplayer.get_unique_id():
			rpc_id(player_id, "grant_xp", volume)
	return volume


## Clients carve the same bowl the host carved. Deterministic: same heights,
## same radius, same depth.
@rpc("authority", "call_remote", "reliable")
func apply_dig(world_position: Vector3, radius: float, depth: float) -> void:
	dig_at(world_position, radius, depth)


## The host computed this XP from the dig it accepted.
@rpc("authority", "call_remote", "reliable")
func grant_xp(volume: float) -> void:
	var state := Net.local_state()
	if state != null:
		state.add_dig_volume(volume)


func _state_for(player_id: int) -> PlayerState:
	var player := Net.player_by_id(player_id)
	if player == null:
		return null
	return player.get_node_or_null("PlayerState") as PlayerState


## Height of the sand surface at `world_pos` (bilinear between grid points).
## Returns 0.0 outside the grid.
func get_height_at(world_pos: Vector3) -> float:
	return _sample_height(heights, world_pos)


## Height of the beach before anything was dug (bilinear). The sea uses this so
## the waterline is where the beach meets the water, not wherever the last hole
## happened to be.
func base_height_at(world_pos: Vector3) -> float:
	return _sample_height(base_heights, world_pos)


func _sample_height(source: PackedFloat32Array, world_pos: Vector3) -> float:
	if source.is_empty():
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
	var h00 := source[z0 * GRID_SIZE + x0]
	var h10 := source[z0 * GRID_SIZE + x1]
	var h01 := source[z1 * GRID_SIZE + x0]
	var h11 := source[z1 * GRID_SIZE + x1]
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
		var world_z := (float(gz) - HALF_GRID) * CELL_SIZE
		for gx in range(gx0, gx1 + 1):
			var local_x := gx - chunk.grid_x
			var vertex_index := local_z * chunk.size_x + local_x
			var height := heights[row + gx]
			var world_x := (float(gx) - HALF_GRID) * CELL_SIZE
			chunk.vertices[vertex_index] = Vector3(local_x * CELL_SIZE, height, local_z * CELL_SIZE)
			chunk.normals[vertex_index] = _normal_at(gx, gz)
			chunk.colors[vertex_index] = _color_at(height, world_x, world_z)


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


## Tints the sand for the current state: darker where it is buried, wet below the
## waterline, forest floor near the pines and leaf litter near the log barriers.
func _color_at(height: float, world_x: float, world_z: float) -> Color:
	var depth_ratio := clampf(-height / MAX_DEPTH, 0.0, 1.0)
	var color := SAND_TOP_COLOR.lerp(SAND_DEEP_COLOR, pow(depth_ratio, 0.55))

	# The inland dressing only exists on dry sand, so fade it out near the shore.
	var inland := smoothstep(SHORE_START_Z - 3.0, SHORE_START_Z + 3.0, world_z)
	var forest := smoothstep(19.0, 25.0, world_x) * inland
	var litter := maxf(
		smoothstep(-20.0, -26.0, world_x),
		smoothstep(20.0, 26.0, world_z)) * inland
	color = color.lerp(FOREST_FLOOR_COLOR, forest * 0.95)
	color = color.lerp(LEAF_LITTER_COLOR, litter * 0.9)

	# Wet sand: everything at or below the waterline, fading dry several metres
	# inland. This band is what makes the tide readable from the beach.
	var wet := smoothstep(wet_line_z + 4.5, wet_line_z, world_z)
	color = color.lerp(SAND_WET_COLOR, wet * 0.85)

	# A darker rim right at the waterline gives the eye a crisp edge to follow as
	# the tide walks it up and down the sand.
	var rim := 1.0 - smoothstep(0.0, 0.8, absf(world_z - wet_line_z))
	color = color.lerp(SAND_WET_COLOR.darkened(0.25), rim * 0.55)

	# Fine grain so the wide flat beach does not read as one solid colour.
	return color.lightened(_grain(world_x, world_z) * 0.05)


## Moves the wet-sand band to the tide's current waterline. Only the chunk rows
## the band can touch are rebuilt, so this is cheap enough to follow the tide.
func set_wet_line(world_z: float) -> void:
	if absf(world_z - wet_line_z) < 0.12:
		return
	wet_line_z = world_z
	if _chunks.is_empty():
		return
	var gz0 := clampi(floori((world_z - 5.0) / CELL_SIZE + HALF_GRID), 0, GRID_SIZE - 1)
	var gz1 := clampi(ceili((world_z + 6.0) / CELL_SIZE + HALF_GRID), 0, GRID_SIZE - 1)
	rebuild_mesh(Rect2i(0, gz0, GRID_SIZE - 1, gz1 - gz0 + 1))


func _grain(x: float, z: float) -> float:
	var n := sin(x * 12.9898 + z * 78.233) * 43758.5453
	return n - floorf(n)


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
