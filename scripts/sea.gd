class_name Sea
extends Node3D
## The ocean on the -Z side of the beach, and the tide that drives it.
##
## A single big transparent plane sits at the current tide height. It is drawn
## only where the sand under it is below the water AND connected to the open sea:
## `SandTerrain.height_texture` says how high the sand is and the flood fill says
## which holes the tide can actually reach, so a pit dug at the shore fills up
## with water while a hole in the middle of the beach stays dry.
## `tide_turned` is emitted when the tide switches direction; LootManager floats
## fresh trash ashore while the water is coming in.

signal tide_turned(rising: bool)

## Water height in metres. The beach is at y = 0, so both values are below it.
## The range is deliberately wide: a metre of tide walks the waterline several
## metres up and down the shallow shore, which is what makes it visible.
const TIDE_LOW := -1.15
const TIDE_HIGH := -0.06
## One full low -> high -> low cycle, in seconds.
const TIDE_PERIOD := 60.0
## How wide the sea is (X) and how far out it reaches (Z). The plane has to span
## the horizon on the -Z side and the whole beach on the +Z side: it is only
## *drawn* where the sand is below the tide, but it must cover every hole that
## could ever fill up.
const WATER_SIZE := 700.0
const WATER_SPAN_Z := 460.0
## How far inland of the beach centre the water plane reaches.
const WATER_INLAND_Z := 32.0
## How much deeper than the water level the sand has to be for a cell to count
## as wet. Keeps the exact waterline out of z-fighting with the sand.
const FLOOD_EPSILON := 0.01
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
## 1 where the sea reaches the sand at the current tide, 0 where it cannot.
var _flood := PackedByteArray()
var _flood_texture: ImageTexture
var _flood_revision := -1
var _flood_level := 999.0
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
	# Only the water plane rises; the seabed stays where it is.
	if _water != null:
		_water.position.y = level
	if _material != null:
		_material.set_shader_parameter("water_level", level)
	_bind_terrain_textures()
	_refresh_flood()
	_update_shoreline()
	if rising != _was_rising:
		_was_rising = rising
		tide_turned.emit(rising)


## How deep the water is at a world position: > 0 means the sand there is under
## the water. Says nothing about whether the sea can reach it (see
## `is_flooded_at`).
func water_depth_at(world_pos: Vector3) -> float:
	var ground := 0.0
	if _terrain != null:
		ground = _terrain.get_height_at(world_pos)
	return level - ground


## True when the sea actually covers this spot at the current tide: the sand is
## below the water and connected to the open sea, so a flooded pit counts and a
## dry hole in the middle of the beach does not.
func is_flooded_at(world_pos: Vector3) -> bool:
	if water_depth_at(world_pos) <= FLOOD_EPSILON:
		return false
	if _flood.is_empty() or _terrain == null:
		return false
	var grid := SandTerrain.GRID_SIZE
	var gx := roundi(world_pos.x / SandTerrain.CELL_SIZE + SandTerrain.HALF_GRID)
	var gz := roundi(world_pos.z / SandTerrain.CELL_SIZE + SandTerrain.HALF_GRID)
	if gx < 0 or gz < 0 or gx >= grid or gz >= grid:
		# Past the edge of the sand: open sea on the -Z side, land everywhere else.
		return world_pos.z < SandTerrain.SHORE_END_Z
	return _flood[gz * grid + gx] == 1


## Flood fill: which cells of the sand the sea can reach. A cell is wet when it is
## below the water level and joined to the open sea through other wet cells, so
## a pit dug at the shore fills up and a pit dug inland stays dry. Recomputed
## only when the sand or the tide actually changed.
func _refresh_flood() -> void:
	if _terrain == null:
		return
	if _flood_revision == _terrain.revision and absf(_flood_level - level) < 0.02:
		return
	_flood_revision = _terrain.revision
	_flood_level = level
	var grid := SandTerrain.GRID_SIZE
	var heights := _terrain.heights
	if _flood.size() != grid * grid:
		_flood.resize(grid * grid)
	_flood.fill(0)
	var limit := level - FLOOD_EPSILON
	# Seed from the seaward edge of the heightmap (row 0 is the most -Z one).
	var stack := PackedInt32Array()
	for x in grid:
		if heights[x] < limit:
			_flood[x] = 1
			stack.append(x)
	while not stack.is_empty():
		var index := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		var z := index / grid
		var x := index - z * grid
		if x > 0 and _flood[index - 1] == 0 and heights[index - 1] < limit:
			_flood[index - 1] = 1
			stack.append(index - 1)
		if x < grid - 1 and _flood[index + 1] == 0 and heights[index + 1] < limit:
			_flood[index + 1] = 1
			stack.append(index + 1)
		if z > 0 and _flood[index - grid] == 0 and heights[index - grid] < limit:
			_flood[index - grid] = 1
			stack.append(index - grid)
		if z < grid - 1 and _flood[index + grid] == 0 and heights[index + grid] < limit:
			_flood[index + grid] = 1
			stack.append(index + grid)
	var bytes := PackedByteArray()
	bytes.resize(grid * grid)
	for i in grid * grid:
		bytes[i] = 255 if _flood[i] == 1 else 0
	var image := Image.create_from_data(grid, grid, false, Image.FORMAT_R8, bytes)
	if _flood_texture == null:
		_flood_texture = ImageTexture.create_from_image(image)
	else:
		_flood_texture.update(image)
	if _material != null:
		_material.set_shader_parameter("flood_mask", _flood_texture)


## Hands the shader the sand heightmap and the world rectangle it covers. Done
## lazily because the terrain may build its texture after the sea is ready.
func _bind_terrain_textures() -> void:
	if _textures_bound or _material == null or _terrain == null:
		return
	if _terrain.height_texture == null:
		return
	_textures_bound = true
	_material.set_shader_parameter("terrain_height", _terrain.height_texture)
	_material.set_shader_parameter("map_origin",
		-SandTerrain.HALF_GRID * SandTerrain.CELL_SIZE)
	_material.set_shader_parameter("map_span",
		(SandTerrain.GRID_SIZE - 1) * SandTerrain.CELL_SIZE)


## Blue-green veil and murky fog while the camera is inside the water. Without it
## a flooded pit is just dry sand seen from under a blue lid.
func _update_veil(delta: float) -> void:
	if _veil == null:
		return
	var under := false
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var eye := camera.global_position
		under = eye.y < level - 0.02 and is_flooded_at(eye)
	_veil_alpha = move_toward(_veil_alpha, 1.0 if under else 0.0, delta * 2.5)
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
	var water := MeshInstance3D.new()
	water.name = "Water"
	var plane := PlaneMesh.new()
	var water_span := WATER_SPAN_Z + WATER_INLAND_Z
	plane.size = Vector2(WATER_SIZE, water_span)
	plane.subdivide_width = 110
	plane.subdivide_depth = 96
	water.mesh = plane
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The plane spans Z = -WATER_SPAN_Z .. +WATER_INLAND_Z. Most of the beach half
	# is never drawn (the sand there is above the tide), but it has to be there so
	# a hole the sea can reach fills up wherever it was dug.
	water.position = Vector3(0.0, 0.0, (WATER_INLAND_Z - WATER_SPAN_Z) * 0.5)
	_water = water

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

	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/sea.gdshader") as Shader
	_material.set_shader_parameter("water_level", level)
	water.material_override = _material
	add_child(water)


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
