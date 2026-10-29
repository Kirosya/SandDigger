extends Node
## Beach / sea / tide test on the real main scene.
##
## Verifies that the beach now slopes into the sea on the -Z side, that the tide
## moves the waterline, and that sea trash floats in and becomes claimable
## surface loot when it washes ashore. Run headless:
##   godot --headless --path . res://tests/sea_test.tscn

var _failures := 0


func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(0.4).timeout

	var terrain := get_tree().get_first_node_in_group("sand_terrain") as SandTerrain
	var sea := get_tree().get_first_node_in_group("sea") as Sea
	var loot := get_tree().get_first_node_in_group("loot_manager") as LootManager
	_check("main scene has the sea", sea != null)
	_check("main scene has the terrain", terrain != null)
	_check("main scene has loot", loot != null)
	if sea == null or terrain == null or loot == null:
		_finish()
		return

	# --- Beach profile ------------------------------------------------------
	var inland := terrain.get_height_at(Vector3(0.0, 0.0, 6.0))
	var shore := terrain.get_height_at(Vector3(0.0, 0.0, SandTerrain.SHORE_START_Z))
	var deep := terrain.get_height_at(Vector3(0.0, 0.0, SandTerrain.SHORE_END_Z))
	print("SEA heights inland=%.3f shore=%.3f deep=%.3f" % [inland, shore, deep])
	_check("beach is flat at the spawn", absf(inland) < 0.01)
	_check("shore starts at sand level", absf(shore) < 0.01)
	_check("beach slopes under the sea", deep <= SandTerrain.SEA_FLOOR + 0.01)

	# The underwater sand has to go down in one long, smooth ramp, not a step.
	var previous := shore
	var gradual := true
	var sample_z := SandTerrain.SHORE_START_Z - 2.0
	while sample_z > SandTerrain.SHORE_END_Z:
		var h := terrain.get_height_at(Vector3(0.0, 0.0, sample_z))
		if h > previous + 0.001 or previous - h > 0.7:
			gradual = false
		previous = h
		sample_z -= 2.0
	_check("seabed descends gradually", gradual)

	# --- Water only on the -Z side -----------------------------------------
	var water := sea.get_node_or_null("Water") as MeshInstance3D
	_check("sea has a water surface", water != null)
	if water != null:
		var plane := water.mesh as PlaneMesh
		var inland_edge := water.position.z + plane.size.y * 0.5
		print("SEA water z=%.1f size_z=%.1f inland_edge=%.2f" % [
			water.position.z, plane.size.y, inland_edge])
		_check("water never reaches the inland half of the beach", inland_edge <= 0.5)
		_check("water still reaches the horizon", plane.size.y >= 300.0)

	# --- Tide ---------------------------------------------------------------
	print("SEA tide level=%.3f rising=%s shoreline=%.2f" % [
		sea.level, str(sea.rising), sea.shoreline_z])
	_check("tide starts at low water", absf(sea.level - Sea.TIDE_LOW) < 0.05)
	_check("waterline sits on the slope",
		sea.shoreline_z < SandTerrain.SHORE_START_Z
		and sea.shoreline_z > SandTerrain.SHORE_END_Z)
	var level_before := sea.level
	var shore_before := sea.shoreline_z
	sea._update_tide(Sea.TIDE_PERIOD * 0.5)
	print("SEA after half a cycle level=%.3f shoreline=%.2f" % [
		sea.level, sea.shoreline_z])
	_check("tide rises to high water", sea.level > level_before + 0.3)
	_check("high tide pushes the waterline inland", sea.shoreline_z > shore_before + 0.5)
	_check("tide range is clearly visible", Sea.TIDE_HIGH - Sea.TIDE_LOW >= 0.9)
	_check("wet sand band follows the waterline",
		absf(terrain.wet_line_z - sea.shoreline_z) < 0.25)

	# --- The rising tide floats trash in on its own ------------------------
	sea._time = Sea.TIDE_PERIOD * 0.25
	sea._update_tide(0.0)
	var floating_before := loot._floating_count()
	loot._sea_spawn_timer = 0.0
	loot._process(0.05)
	print("SEA auto spawn floating=%d rising=%s" % [
		loot._floating_count(), str(sea.rising)])
	_check("the rising tide floats trash in by itself",
		sea.rising and loot._floating_count() > floating_before)

	# --- Sea trash floats in and beaches itself ----------------------------
	var item := loot._spawn_sea_trash()
	_check("sea trash spawns", item != null and item.floating)
	if item == null:
		_finish()
		return
	_check("sea trash starts in the water",
		item.node.position.z < sea.shoreline_z)
	_check("sea trash is not digging loot", item.on_surface and item.from_sea)
	# One huge step covers the whole drift; the second call notices it arrived.
	loot._drift_floating(1000.0)
	loot._drift_floating(1000.0)
	_check("sea trash washes ashore", not item.floating)
	var sand := terrain.get_height_at(item.buried_position)
	print("SEA beached z=%.2f y=%.3f sand=%.3f" % [
		item.buried_position.z, item.node.position.y, sand])
	_check("beached trash sits on the dry sand",
		absf(item.node.position.y - (sand + 0.1)) < 0.01)
	_check("beached trash is claimable",
		loot.nearest_claimable(item.buried_position, 1.0) == item)

	# --- Loot stays out of the surf ---------------------------------------
	var deepest := 0.0
	for other in loot.loot:
		if other.from_sea:
			continue
		deepest = minf(deepest, other.buried_position.z)
	_check("regular loot never spawns in the sea", deepest >= LootManager.DRY_LIMIT_Z - 0.01)

	_finish()


func _finish() -> void:
	if _failures == 0:
		print("SEA OK")
		get_tree().quit(0)
	else:
		print("SEA FAILED (%d)" % _failures)
		get_tree().quit(1)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
