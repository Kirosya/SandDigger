class_name Sea
extends Node3D
## The ocean on the -Z side of the beach, and the tide that drives it.
##
## A single big transparent plane sits at the current tide height. The sand is
## above it inland and slopes under it offshore (see SandTerrain._generate_beach),
## so raising and lowering the plane moves the waterline up and down the beach.
## `tide_turned` is emitted when the tide switches direction; LootManager floats
## fresh trash ashore while the water is coming in.
##
## The waterline is found by binary-searching the terrain height along Z, which
## also gives the shader the `shoreline_z` it needs for the foam band.

signal tide_turned(rising: bool)

## Water height in metres. The beach is at y = 0, so both values are below it.
## The range is deliberately wide: a metre of tide walks the waterline several
## metres up and down the shallow shore, which is what makes it visible.
const TIDE_LOW := -1.15
const TIDE_HIGH := -0.06
## One full low -> high -> low cycle, in seconds.
const TIDE_PERIOD := 60.0
## How wide the sea is (X) and how far out it reaches (Z). The plane stops at
## Z = 0 so the water only ever exists on the -Z side of the beach; the other
## three edges are forest and windfall, never open water.
const WATER_SIZE := 700.0
const WATER_SPAN_Z := 460.0
## How far behind the moving waterline the water plane stops being drawn. The
## plane still spans the whole horizon, but on the beach side it is masked off so
## a hole dug in the sand can never expose it as a flat sheet under the surface.
const DRY_MARGIN := 0.35

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


func _ready() -> void:
	add_to_group("sea")
	_terrain = get_tree().get_first_node_in_group("sand_terrain") as SandTerrain
	_build()
	_update_tide(0.0)


func _process(delta: float) -> void:
	_update_tide(delta)


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
	_update_shoreline()
	if rising != _was_rising:
		_was_rising = rising
		tide_turned.emit(rising)


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
	if _material != null:
		_material.set_shader_parameter("shoreline_z", shoreline_z)
	# Keep the wet-sand band on the terrain glued to the moving waterline.
	_terrain.set_wet_line(shoreline_z)


func _build() -> void:
	var water := MeshInstance3D.new()
	water.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(WATER_SIZE, WATER_SPAN_Z)
	plane.subdivide_width = 110
	plane.subdivide_depth = 90
	water.mesh = plane
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The plane spans Z = -WATER_SPAN_Z .. 0, so the sea reaches the horizon on
	# the -Z side but never wraps around the inland edges of the beach.
	water.position = Vector3(0.0, 0.0, -WATER_SPAN_Z * 0.5)
	_water = water

	# Seabed under the open water, past the edge of the 64 m heightmap. It keeps
	# the transparent water from fading into the sky at the horizon. Kept a
	# light wet-sand tone: a dark floor plus the water tint used to read as a
	# murky maroon band out where the beach ends.
	var seabed := MeshInstance3D.new()
	seabed.name = "Seabed"
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(WATER_SIZE, WATER_SPAN_Z)
	seabed.mesh = floor_mesh
	seabed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	seabed.position = Vector3(0.0, SandTerrain.SEA_FLOOR - 0.4, -WATER_SPAN_Z * 0.5)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.34, 0.36, 0.30)
	floor_material.roughness = 1.0
	floor_material.metallic = 0.0
	seabed.material_override = floor_material
	add_child(seabed)

	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/sea.gdshader") as Shader
	_material.set_shader_parameter("shoreline_z", shoreline_z)
	_material.set_shader_parameter("dry_margin", DRY_MARGIN)
	water.material_override = _material
	add_child(water)
