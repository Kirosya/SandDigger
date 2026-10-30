class_name Sea
extends Node3D
## The ocean on the -Z side of the beach, and the tide that drives it.
##
## The water is a real shallow-water simulation on the same 128x128 grid as the
## sand: every half-metre cell holds a water depth, and each step water runs
## downhill from one cell to the next. The open sea is an endless source and sink
## at the tide height, so a hole dug into the beach fills from wherever it is
## joined to the water - over the rim, through a breach - and the surface inside
## it really does climb from the bottom instead of a flat sheet appearing. When
## the tide drops the holes drain back out the same way.
##
## Once the sea has let go of a pool, the water left up on a ledge still runs
## down to the lowest point it can reach, and whatever is trapped in a closed
## bowl soaks slowly away into the sand.
##
## The surface is drawn by one mesh that follows the sand grid, its vertices
## raised to the simulated water height, plus a flat plane for the open sea
## beyond the sand.
## `tide_turned` is emitted when the tide switches direction; LootManager floats
## fresh trash ashore while the water is coming in.

signal tide_turned(rising: bool)

## Water height in metres. The beach is at y = 0, so both values are below it.
## The range is deliberately wide: over two metres of tide walks the waterline
## the better part of twenty metres up and down the shallow shore, so the sea
## really does pull back and leave the beach (and any hole in it) draining.
const TIDE_LOW := -2.30
const TIDE_HIGH := -0.10
## One full low -> high -> low cycle, in seconds.
const TIDE_PERIOD := 60.0
## How wide the sea is (X) and how far out it reaches (Z). The open sea plane has
## to span the horizon on the -Z side; the beach half is the simulated grid.
const WATER_SIZE := 700.0
const WATER_SPAN_Z := 460.0
## How fast water may run from one half-metre cell into the next, in metres of
## surface per second. High enough that a breach pours in like a waterfall, low
## enough that a crater takes a few seconds to fill instead of snapping full.
const FLOW_SPEED := 6.0
## At most this share of the surface difference moves in one step. Under 0.5 the
## transfer can never overshoot its target, so the flow stays stable whatever the
## frame rate is.
const FLOW_SHARE := 0.45
## Depth below which a cell counts as dry, in metres. Also the depth the shader
## needs before it draws anything.
const WET_DEPTH := 0.015
## Water the sand drinks, in metres per second. The constant part is the thin
## film on wet sand soaking away; the part that scales with depth is the pool
## seeping down into the beach. Together they empty a knee-deep puddle in about
## half a minute and a deep crater over a minute or two, so a pool the tide left
## behind slowly disappears instead of sitting there forever.
const SEEP_MIN := 0.004
const SEEP_RATE := 0.05
## The flow keeps even a millimetre of water moving downhill instead of dropping
## it on the spot: a sheet left high on a shelf has to reach the bottom of the
## hole before it soaks in, not vanish halfway there.
const FLOW_FLOOR := 0.0005
## The flow is stepped at a fixed rate instead of the frame rate, so it looks the
## same at 30 as at 144 fps. Twenty steps a second is plenty for a pool filling,
## and keeps a big crater from costing more than a frame now and then.
const WATER_STEP := 1.0 / 20.0
## World Z where the sand heightmap ends (128 cells of 0.5 m, centred on 0). The
## sea floor plane starts just inside it: everything inland of this is covered by
## sand, and a plane there would only ever be seen through a dug hole.
const SEABED_EDGE_Z := -31.0
## Screen veil while the camera is under water, so a flooded pit reads as water
## instead of as dry sand under a lid. It is a gradient, not a flat wash: light
## comes from the surface, so the top of the screen is clearer than the bottom.
const UNDERWATER_COLOR := Color(0.08, 0.34, 0.42)
const UNDERWATER_TOP_ALPHA := 0.24
const UNDERWATER_BOTTOM_ALPHA := 0.58
## Fog while the camera is under water. The water eats the distance, so the walls
## of a flooded pit fade into the murk instead of reading as dry sand a few
## metres away.
const UNDERWATER_FOG_DENSITY := 0.09
const UNDERWATER_FOG_COLOR := Color(0.10, 0.36, 0.42)
## Scattered light under water: more ambient and a greener tint, so the sand
## walls of a flooded pit are not just a black hole.
const UNDERWATER_AMBIENT_ENERGY := 0.55
const UNDERWATER_AMBIENT_COLOR := Color(0.35, 0.65, 0.70)

## Current water height (world Y).
var level := TIDE_LOW
## World Z of the waterline for the current tide. More negative = further out.
var shoreline_z := -13.0
## True while the water is coming in.
var rising := true

var _time := 0.0
var _was_rising := true
var _terrain: SandTerrain
var _material: ShaderMaterial
var _water: MeshInstance3D
## Simulated water depth per grid cell, in metres. 0 is dry; the open sea is not
## stored here at all, it is worked out from the undug sand profile.
var _depth := PackedFloat32Array()
## Cells the flow has to touch, and the ones it just reached.
var _active := PackedInt32Array()
var _pending := PackedInt32Array()
var _in_active := PackedByteArray()
## 1 where the open sea touches the cell, i.e. water can be poured straight in.
var _feed := PackedByteArray()
var _water_texture: ImageTexture
var _water_dirty := false
var _water_revision := -1
var _water_level := 999.0
var _step_accumulator := 0.0
var _textures_bound := false
var _veil: TextureRect
var _veil_alpha := 0.0
var _env: Environment
var _dry_fog_density := 0.0
var _dry_fog_color := Color.WHITE
var _dry_ambient_energy := 0.0
var _dry_ambient_color := Color.WHITE


func _ready() -> void:
	add_to_group("sea")
	_terrain = get_tree().get_first_node_in_group("sand_terrain") as SandTerrain
	_build()
	_build_veil()
	_update_tide(0.0)


func _process(delta: float) -> void:
	_update_tide(delta)
	_update_veil(delta)


## Advances the tide by `delta` seconds. Called every frame, and directly by the
## headless test to fast-forward.
func _update_tide(delta: float) -> void:
	_time += delta
	# Start at low tide: the first thing the player sees is the sea coming in.
	level = lerpf(TIDE_LOW, TIDE_HIGH, 0.5 - 0.5 * cos(_time * TAU / TIDE_PERIOD))
	rising = sin(_time * TAU / TIDE_PERIOD) > 0.0
	# The water surface is not moved as a whole any more: the tide is a shader
	# uniform (outside the sand, and inside the open-sea cells) and the holes are
	# simulated per cell.
	if _material != null:
		_material.set_shader_parameter("water_level", level)
	_bind_terrain_textures()
	_refresh_water()
	_step_water(delta)
	_update_shoreline()
	if rising != _was_rising:
		_was_rising = rising
		tide_turned.emit(rising)


## How deep the water actually is at a world position, in metres. 0 means dry
## sand: a hole above the waterline is dry even if its floor is below sea level.
func water_depth_at(world_pos: Vector3) -> float:
	var cell := _cell_at(world_pos)
	if cell < 0 or _terrain == null:
		if _terrain == null:
			return maxf(0.0, level)
		return maxf(0.0, level - _terrain.get_height_at(world_pos))
	if _is_open_sea(cell):
		return maxf(0.0, level - _terrain.heights[cell])
	return _depth[cell]


## True when there is water over this spot right now: the open sea, or a hole
## the water has actually run into. A dry hole in the sand is not flooded even if
## it is deeper than the sea.
func is_flooded_at(world_pos: Vector3) -> bool:
	var cell := _cell_at(world_pos)
	if cell < 0:
		# Past the edge of the sand: open sea on the -Z side, land everywhere else.
		return world_pos.z < SandTerrain.SHORE_END_Z
	return _depth[cell] > WET_DEPTH or _is_open_sea(cell)


## True when this cell is plain, undug sand under the tide: the open sea. It is
## never simulated - it is an endless source and sink that simply sits at the
## tide height. Digging the cell makes it a hole the flow has to fill.
func _is_open_sea(index: int) -> bool:
	var h := _terrain.heights[index]
	return h < level - WET_DEPTH and absf(h - _terrain.base_heights[index]) < 0.02


## Keeps the water simulation in step with the sand and the tide. Both are cheap:
## a dig only re-seeds the cells it touched, and the tide only refreshes which
## cells the sea can pour into. Nothing here ever walks the whole grid.
func _refresh_water() -> void:
	if _terrain == null or _terrain.heights.size() != SandTerrain.GRID_SIZE * SandTerrain.GRID_SIZE:
		return
	var cells := SandTerrain.GRID_SIZE * SandTerrain.GRID_SIZE
	if _depth.size() != cells:
		_depth.resize(cells)
		_depth.fill(0.0)
		_in_active.resize(cells)
		_in_active.fill(0)
		_feed.resize(cells)
		_feed.fill(0)
		_active.clear()
		_pending.clear()
		_water_dirty = true
	var dug := _terrain.revision != _water_revision
	_water_revision = _terrain.revision
	if dug:
		_seed_dug_area(_terrain.last_dirty_rect)
	if dug or absf(_water_level - level) > 0.02:
		_water_level = level
		_refresh_feeds()


## Adds the cells around a fresh dig to the simulation: the dug sand itself plus
## a margin, so water sitting just outside the hole can run in.
func _seed_dug_area(rect: Rect2i) -> void:
	var grid := SandTerrain.GRID_SIZE
	var heights := _terrain.heights
	var base := _terrain.base_heights
	var area := Rect2i(rect.position - Vector2i(2, 2), rect.size + Vector2i(4, 4))
	area = area.intersection(Rect2i(0, 0, grid, grid))
	for z in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var index := z * grid + x
			if absf(heights[index] - base[index]) < 0.02 and _depth[index] <= 0.0:
				continue
			_add_active(index)
			if x > 0:
				_add_active(index - 1)
			if x < grid - 1:
				_add_active(index + 1)
			if z > 0:
				_add_active(index - grid)
			if z < grid - 1:
				_add_active(index + grid)


func _add_active(index: int) -> void:
	if _in_active[index] == 1:
		return
	_in_active[index] = 1
	_active.append(index)


## Recomputes which simulated cells are next to the open sea, i.e. can be topped
## up straight from it. Cost is linear in the number of live cells, not the grid.
func _refresh_feeds() -> void:
	var grid := SandTerrain.GRID_SIZE
	var heights := _terrain.heights
	var base := _terrain.base_heights
	var wet := level - WET_DEPTH
	for index in _active:
		var z := index / grid
		var x := index - z * grid
		var feeds := 0
		for side in 4:
			var other: int
			if side == 0:
				if x == 0:
					continue
				other = index - 1
			elif side == 1:
				if x == grid - 1:
					continue
				other = index + 1
			elif side == 2:
				if z == 0:
					continue
				other = index - grid
			else:
				if z == grid - 1:
					continue
				other = index + grid
			var h := heights[other]
			if h < wet and absf(h - base[other]) < 0.02:
				feeds = 1
				break
		_feed[index] = feeds


## Advances the flow by `delta` seconds in fixed steps. Does nothing at all when
## there is no water anywhere that a dig could have disturbed.
func _step_water(delta: float) -> void:
	if _active.is_empty():
		if _water_dirty:
			_upload_water()
		return
	_step_accumulator += minf(delta, 0.2)
	var steps := 0
	while _step_accumulator >= WATER_STEP and steps < 4:
		_flow_step(WATER_STEP)
		_step_accumulator -= WATER_STEP
		steps += 1
	if _step_accumulator > WATER_STEP * 4.0:
		_step_accumulator = 0.0
	if _water_dirty:
		_upload_water()


## Runs the flow for `seconds` all at once. Used by the tests and the screenshot
## tool, which cannot sit and wait for a hole to fill in real time.
func settle_water(seconds: float) -> void:
	if _active.is_empty():
		return
	var steps := int(clampf(seconds / WATER_STEP, 1.0, 2400.0))
	for i in steps:
		_flow_step(WATER_STEP)
	if _water_dirty:
		_upload_water()


## One step of shallow water. Water runs downhill from every cell into its lower
## neighbours, and any cell the open sea touches is topped up straight from it -
## so a hole dug at the shore fills over its rim like water poured in, and drains
## back out the same way when the tide drops. On top of that the sand drinks:
## every wet cell loses a little to the beach each step, which is what slowly
## empties a pool the tide has cut off. Volume is conserved except at the sea and
## in the sand.
func _flow_step(dt: float) -> void:
	var grid := SandTerrain.GRID_SIZE
	var heights := _terrain.heights
	var base := _terrain.base_heights
	var cap := FLOW_SPEED * dt
	var tide := level
	var count := _active.size()
	for k in count:
		var index := _active[k]
		var d := _depth[index]
		var h := heights[index]
		# The sand soaks water up: a thin film goes quickly, a deep pool slowly.
		# A cell the sea is still feeding gets topped back up just below, so the
		# shore does not drain while the tide is in.
		if d > 0.0:
			d -= (SEEP_MIN + d * SEEP_RATE) * dt
			if d < FLOW_FLOOR:
				d = 0.0
			_depth[index] = d
			_water_dirty = true
		# The sea pours in over the rim of a hole it touches.
		if _feed[index] == 1 and h + d < tide - 0.001:
			var add := (tide - h - d) * FLOW_SHARE
			if add > cap:
				add = cap
			if add > tide - h:
				add = tide - h
			if add > 0.0:
				d += add
				_depth[index] = d
				_water_dirty = true
		if d <= 0.0:
			continue
		var surface := h + d
		var z := index / grid
		var x := index - z * grid
		for side in 4:
			var other: int
			if side == 0:
				if x == 0:
					continue
				other = index - 1
			elif side == 1:
				if x == grid - 1:
					continue
				other = index + 1
			elif side == 2:
				if z == 0:
					continue
				other = index - grid
			else:
				if z == grid - 1:
					continue
				other = index + grid
			var oh := heights[other]
			var od := _depth[other]
			var sea := od <= 0.0 and oh < tide - WET_DEPTH \
				and absf(oh - base[other]) < 0.02
			var osurface := tide if sea else oh + od
			var diff := surface - osurface
			if diff <= 0.0005:
				continue
			var move := diff * FLOW_SHARE
			if move > cap:
				move = cap
			if move > d:
				move = d
			if move <= 0.0:
				continue
			d -= move
			_depth[index] = 0.0 if d < FLOW_FLOOR else d
			# Re-derive the surface: a cell that has already poured water into one
			# neighbour is lower for the next one, and ignoring that makes the
			# water slosh back and forth instead of settling.
			surface = h + d
			_water_dirty = true
			if sea:
				continue
			_depth[other] = od + move
			if _in_active[other] == 0:
				_in_active[other] = 1
				_pending.append(other)
	if not _pending.is_empty():
		_active.append_array(_pending)
		_pending.clear()


func _upload_water() -> void:
	var grid := SandTerrain.GRID_SIZE
	var image := Image.create_from_data(grid, grid, false, Image.FORMAT_RF,
		_depth.to_byte_array())
	if _water_texture == null:
		_water_texture = ImageTexture.create_from_image(image)
	else:
		_water_texture.update(image)
	if _material != null:
		_material.set_shader_parameter("water_depth", _water_texture)
	_water_dirty = false


## Grid cell index under a world position, or -1 outside the sand.
func _cell_at(world_pos: Vector3) -> int:
	if _depth.is_empty():
		return -1
	var grid := SandTerrain.GRID_SIZE
	var gx := roundi(world_pos.x / SandTerrain.CELL_SIZE + SandTerrain.HALF_GRID)
	var gz := roundi(world_pos.z / SandTerrain.CELL_SIZE + SandTerrain.HALF_GRID)
	if gx < 0 or gz < 0 or gx >= grid or gz >= grid:
		return -1
	return gz * grid + gx


## Hands the shader the sand heightmap, the undug profile and the world rectangle
## they cover. Done lazily because the terrain may build its texture after the sea
## is ready.
func _bind_terrain_textures() -> void:
	if _textures_bound or _material == null or _terrain == null:
		return
	if _terrain.height_texture == null:
		return
	_textures_bound = true
	_material.set_shader_parameter("terrain_height", _terrain.height_texture)
	# The undug profile never changes, so the shader can work out on its own where
	# the open sea is: a cell whose height still matches the profile and sits
	# below the tide is sea, anything dug is a hole that has to fill first.
	var grid := SandTerrain.GRID_SIZE
	_material.set_shader_parameter("terrain_base", ImageTexture.create_from_image(
		Image.create_from_data(grid, grid, false, Image.FORMAT_RF,
			_terrain.base_heights.to_byte_array())))
	_material.set_shader_parameter("map_origin",
		-SandTerrain.HALF_GRID * SandTerrain.CELL_SIZE)
	_material.set_shader_parameter("map_span",
		(grid - 1) * SandTerrain.CELL_SIZE)


## Blue-green veil and murky fog while the camera is inside the water. Without it
## a flooded pit is just dry sand seen from under a blue lid.
func _update_veil(delta: float) -> void:
	if _veil == null:
		return
	var under := 0.0
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var eye := camera.global_position
		if is_flooded_at(eye):
			# Shallow wading gets a light tint; a few centimetres under the
			# surface is still "under water", so ramp in over the first 0.8 m.
			under = clampf((level - eye.y) / 0.8, 0.0, 1.0)
	_veil_alpha = move_toward(_veil_alpha, under, delta * 2.5)
	_veil.modulate.a = _veil_alpha
	_veil.visible = _veil_alpha > 0.002
	if _env != null:
		_env.fog_density = lerpf(_dry_fog_density, UNDERWATER_FOG_DENSITY, _veil_alpha)
		_env.fog_light_color = _dry_fog_color.lerp(UNDERWATER_FOG_COLOR, _veil_alpha)
		_env.ambient_light_energy = lerpf(_dry_ambient_energy,
			UNDERWATER_AMBIENT_ENERGY, _veil_alpha)
		_env.ambient_light_color = _dry_ambient_color.lerp(
			UNDERWATER_AMBIENT_COLOR, _veil_alpha)


func _update_shoreline() -> void:
	if _terrain == null:
		_terrain = get_tree().get_first_node_in_group("sand_terrain") as SandTerrain
		if _terrain == null:
			return
	# The beach is flat inland (height 0) and slopes down toward -Z, so the
	# height is monotonic along Z and a binary search finds the waterline.
	# This deliberately reads the UNDUG profile: a hole in the sand must not drag
	# the waterline inland, or the water plane slides up over dry beach and shows
	# through every pit as a flat white/turquoise slab.
	var dry := 8.0
	var deep := -32.0
	for i in 22:
		var mid := (dry + deep) * 0.5
		if _terrain.base_height_at(Vector3(0.0, 0.0, mid)) > level:
			# Dry here: the waterline is further out (more negative Z).
			dry = mid
		else:
			# Wet here: the waterline is further inland (less negative Z).
			deep = mid
	shoreline_z = (dry + deep) * 0.5
	# Keep the wet-sand band on the terrain glued to the moving waterline.
	_terrain.set_wet_line(shoreline_z)


func _build() -> void:
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/sea.gdshader") as Shader
	_material.set_shader_parameter("water_level", level)

	# The beach half: one vertex per sand cell, so the shader can raise each one
	# to the water height the flow simulation found for that cell. The topology
	# never changes, only the depth texture is uploaded while water is moving.
	var grid := SandTerrain.GRID_SIZE
	var step := SandTerrain.CELL_SIZE
	var origin := -SandTerrain.HALF_GRID * step
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	verts.resize(grid * grid)
	uvs.resize(grid * grid)
	normals.resize(grid * grid)
	for z in grid:
		for x in grid:
			var i := z * grid + x
			verts[i] = Vector3(origin + x * step, 0.0, origin + z * step)
			uvs[i] = Vector2(float(x) / (grid - 1), float(z) / (grid - 1))
			normals[i] = Vector3.UP
	var indices := PackedInt32Array()
	indices.resize((grid - 1) * (grid - 1) * 6)
	var at := 0
	for z in grid - 1:
		for x in grid - 1:
			var i := z * grid + x
			indices[at] = i
			indices[at + 1] = i + grid
			indices[at + 2] = i + 1
			indices[at + 3] = i + 1
			indices[at + 4] = i + grid
			indices[at + 5] = i + grid + 1
			at += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var water := MeshInstance3D.new()
	water.name = "Water"
	water.mesh = mesh
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.material_override = _material
	_water = water
	add_child(water)

	# The open sea past the sand mesh: flat at the tide, no flow to simulate.
	var edge := SandTerrain.HALF_GRID * SandTerrain.CELL_SIZE
	var open := MeshInstance3D.new()
	open.name = "OpenWater"
	var plane := PlaneMesh.new()
	var open_span := WATER_SPAN_Z - edge
	plane.size = Vector2(WATER_SIZE, open_span)
	plane.subdivide_width = 48
	plane.subdivide_depth = 32
	open.mesh = plane
	open.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	open.position = Vector3(0.0, 0.0, -edge - open_span * 0.5)
	var open_material := ShaderMaterial.new()
	open_material.shader = _material.shader
	open_material.set_shader_parameter("water_level", level)
	open_material.set_shader_parameter("use_water_map", false)
	open.material_override = open_material
	add_child(open)

	# Seabed under the open water, past the edge of the heightmap. It keeps the
	# transparent water from fading into the sky at the horizon. It starts at the
	# edge of the sand mesh, not under the beach: it used to reach z = 0, which
	# put a flat slab three metres under the flat beach, and any pit dug at the
	# shore deeper than that showed it as a dead grey-blue sheet. Kept a light
	# wet-sand tone as well, so the horizon does not go murky.
	var seabed := MeshInstance3D.new()
	seabed.name = "Seabed"
	var floor_mesh := PlaneMesh.new()
	var seabed_span := WATER_SPAN_Z - absf(SEABED_EDGE_Z)
	floor_mesh.size = Vector2(WATER_SIZE, seabed_span)
	seabed.mesh = floor_mesh
	seabed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	seabed.position = Vector3(0.0, SandTerrain.SEA_FLOOR - 0.4,
		SEABED_EDGE_Z - seabed_span * 0.5)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.34, 0.36, 0.30)
	floor_material.roughness = 1.0
	floor_material.metallic = 0.0
	seabed.material_override = floor_material
	add_child(seabed)


## Screen veil for the underwater look. Sits under the HUD (layer 10) so the
## text stays readable while the camera is inside the water.
func _build_veil() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Underwater"
	layer.layer = 5
	add_child(layer)
	_veil = TextureRect.new()
	_veil.name = "Veil"
	_veil.texture = _veil_gradient()
	_veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_veil.stretch_mode = TextureRect.STRETCH_SCALE
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.visible = false
	layer.add_child(_veil)
	# The scene fog turns into the water murk while the camera is under. Captured
	# here so the dry look is restored exactly when the camera comes back up.
	var world := get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if world != null and world.environment != null:
		_env = world.environment
		_dry_fog_density = _env.fog_density
		_dry_fog_color = _env.fog_light_color
		_dry_ambient_energy = _env.ambient_light_energy
		_dry_ambient_color = _env.ambient_light_color


## The veil itself: clear at the top (light from the surface) and heavier at the
## bottom, so the water reads as a column instead of a flat blue wash.
func _veil_gradient() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(UNDERWATER_COLOR, UNDERWATER_TOP_ALPHA))
	gradient.set_color(1, Color(UNDERWATER_COLOR.darkened(0.35),
		UNDERWATER_BOTTOM_ALPHA))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 4
	texture.height = 128
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	return texture
