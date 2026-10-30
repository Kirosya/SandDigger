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
		# The beach half is a grid that follows the sand cells, so the surface
		# can sit at the water height inside each hole.
		var sand_edge := SandTerrain.HALF_GRID * SandTerrain.CELL_SIZE
		var box := water.get_aabb()
		print("SEA water grid x=%.1f..%.1f z=%.1f..%.1f" % [
			box.position.x, box.end.x, box.position.z, box.end.z])
		_check("water covers the whole sand grid",
			box.position.x <= -sand_edge and box.end.x >= sand_edge
			and box.position.z <= -sand_edge and box.end.z >= sand_edge)
		var open := sea.get_node_or_null("OpenWater") as MeshInstance3D
		_check("water still reaches the horizon", open != null)
		if open != null:
			var plane := open.mesh as PlaneMesh
			_check("the open sea starts at the edge of the sand",
				open.position.z + plane.size.y * 0.5 <= -sand_edge + 0.6)
			_check("the open sea reaches the horizon", plane.size.y >= 300.0)

		var material := water.material_override as ShaderMaterial
		_check("water is a shader", material != null)
		if material != null:
			_check("the water knows where the sand is",
				material.get_shader_parameter("terrain_height") != null)
			_check("the water knows how deep every cell is",
				material.get_shader_parameter("water_depth") != null)
			_check("the water knows the tide height",
				is_equal_approx(float(material.get_shader_parameter("water_level")),
					sea.level))

	# The shader samples the live heightmap as a float texture.
	var height_tex := terrain.height_texture
	_check("the terrain exposes its heightmap to shaders", height_tex != null)
	if height_tex != null:
		_check("the heightmap texture covers the sand grid",
			height_tex.get_width() == SandTerrain.GRID_SIZE
			and height_tex.get_height() == SandTerrain.GRID_SIZE)
		var image := height_tex.get_image()
		if image != null and image.get_width() == SandTerrain.GRID_SIZE:
			var index := 40 * SandTerrain.GRID_SIZE + 64
			print("SEA heightmap texel=%.3f sand=%.3f" % [
				image.get_pixel(64, 40).r, terrain.heights[index]])
			_check("the shader heightmap matches the sand",
				absf(image.get_pixel(64, 40).r - terrain.heights[index]) < 0.001)

	# The sea floor must only exist past the edge of the sand. It used to run all
	# the way to z = 0, three metres under the flat beach, so any pit dug at the
	# shore deeper than that showed it as a dead grey-blue slab with a perfectly
	# straight edge - the "dark blue area inside the beach".
	var seabed := sea.get_node_or_null("Seabed") as MeshInstance3D
	_check("the sea has a floor under the horizon", seabed != null)
	if seabed != null:
		var floor_plane := seabed.mesh as PlaneMesh
		var near_edge := seabed.position.z + floor_plane.size.y * 0.5
		var sand_edge := -SandTerrain.HALF_GRID * SandTerrain.CELL_SIZE
		print("SEA seabed near_edge=%.2f (sand mesh ends at %.2f)" % [near_edge, sand_edge])
		_check("the sea floor never reaches under the beach", near_edge <= sand_edge + 1.0)
		_check("the sea floor still reaches the horizon",
			seabed.position.z - floor_plane.size.y * 0.5 <= -400.0)

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
	_check("the waterline swings miles up the beach", sea.shoreline_z - shore_before > 10.0)
	_check("wet sand band follows the waterline",
		absf(terrain.wet_line_z - sea.shoreline_z) < 0.25)

	# --- Digging must not move the sea --------------------------------------
	# The waterline used to be read from the LIVE heightmap, so a hole dug at
	# x = 0 dragged it inland and slid the water plane up over dry sand, where it
	# showed through the pit as a flat white slab. The waterline is now derived
	# from the undug beach profile.
	var shore_before_dig := sea.shoreline_z
	var wet_before_dig := terrain.wet_line_z
	for i in 6:
		terrain.host_dig(Vector3(0.0, terrain.get_height_at(Vector3(0.0, 0.0, -10.0)), -10.0), 1, 3)
	sea._update_tide(0.0)
	print("SEA after digging shoreline=%.2f (was %.2f) dug_height=%.2f" % [
		sea.shoreline_z, shore_before_dig,
		terrain.get_height_at(Vector3(0.0, 0.0, -10.0))])
	_check("digging does not drag the waterline inland",
		absf(sea.shoreline_z - shore_before_dig) < 0.05)
	_check("digging does not move the wet-sand band", absf(terrain.wet_line_z - wet_before_dig) < 0.05)
	_check("the dug sand really did go below the waterline",
		terrain.get_height_at(Vector3(0.0, 0.0, -10.0)) < sea.level)
	_check("the undug profile is untouched",
		absf(terrain.base_height_at(Vector3(0.0, 0.0, -10.0))
			- sea.level) < 0.35)

	# --- The sea fills the holes it can reach ------------------------------
	# A pit dug at the shore is joined to the open sea (its rim reaches past the
	# waterline), so water pours in over that rim and fills it up to sea level. A
	# pit dug in the middle of the beach is a closed bowl: its floor is well below
	# sea level, but nothing connects it to the water, so it has to stay bone dry.
	sea._time = 0.0
	sea._update_tide(0.0)
	# Kept off to the side: sea trash drifts in over x = -14..14 and the ebb test
	# parks a piece right on the waterline, where this pit would be.
	var shore_pit := Vector3(22.0, 0.0, -22.0)
	for i in 40:
		terrain.dig_at(shore_pit, 3.0, 2.0)
	# Rebuild the map but do not run the flow: the hole is dry until the water
	# has actually travelled in from the rim.
	sea._refresh_water()
	_check("a fresh hole is not full the instant it is dug",
		not sea.is_flooded_at(shore_pit))
	var floor_before := sea.water_depth_at(shore_pit)
	# A tenth of a second in, some water has run in, but the hole is nowhere near
	# full: it fills over seconds, not in one frame.
	sea.settle_water(0.1)
	var early := sea.water_depth_at(shore_pit)
	print("SEA shore pit after 0.1s depth=%.2f (was %.2f)" % [early, floor_before])
	_check("the water runs in instead of appearing", early < 0.5)
	# Half a second later it has climbed, and only after several seconds is the
	# hole full. A pool that fills from its rim reads like that at every step.
	sea.settle_water(0.4)
	var middle := sea.water_depth_at(shore_pit)
	sea.settle_water(6.0)
	var late := sea.water_depth_at(shore_pit)
	print("SEA shore pit depth 0.1s=%.2f 0.5s=%.2f 6s=%.2f" % [early, middle, late])
	_check("the hole fills gradually, not all at once",
		early <= middle and middle < late and late > 0.5)
	# Let the flow settle. Water pours over the rim and fills the hole up to the
	# tide, cell by cell.
	sea.settle_water(20.0)
	print("SEA shore pit floor=%.2f depth=%.2f flooded=%s (waterline %.2f)" % [
		terrain.get_height_at(shore_pit), sea.water_depth_at(shore_pit),
		str(sea.is_flooded_at(shore_pit)), sea.shoreline_z])
	_check("the tide floods a pit joined to the sea",
		sea.water_depth_at(shore_pit) > 0.5 and sea.is_flooded_at(shore_pit))

	var inland_pit := Vector3(4.0, 0.0, 6.0)
	for i in 40:
		terrain.dig_at(inland_pit, 3.0, 2.0)
	sea._update_tide(0.0)
	sea.settle_water(3.0)
	print("SEA inland pit floor=%.2f depth=%.2f flooded=%s" % [
		terrain.get_height_at(inland_pit), sea.water_depth_at(inland_pit),
		str(sea.is_flooded_at(inland_pit))])
	_check("a pit the sea cannot reach stays dry",
		terrain.get_height_at(inland_pit) < sea.level - 3.0
		and not sea.is_flooded_at(inland_pit)
		and sea.water_depth_at(inland_pit) < 0.05)

	# --- The water looks like water from the inside ------------------------
	# A deep hole at the shore fills up at high tide. A camera down at the bottom
	# of it is under the surface, so the sea has to fade in its blue-green veil
	# and fog instead of leaving dry sand under a blue lid.
	sea._time = Sea.TIDE_PERIOD * 0.5
	sea._update_tide(0.0)
	var deep_pit := Vector3(22.0, 0.0, -9.5)
	for i in 60:
		terrain.dig_at(deep_pit, 4.0, 2.0)
	sea._update_tide(0.0)
	sea.settle_water(10.0)
	var pit_floor := terrain.get_height_at(deep_pit)
	var player := get_tree().get_first_node_in_group("player") as FirstPersonPlayer
	_check("the test can look through the player camera", player != null)
	if player != null:
		player.global_position = Vector3(deep_pit.x, pit_floor, deep_pit.z)
		sea._update_veil(1.0)
		var wet_alpha := sea._veil_alpha
		var eye := player.head.global_position
		print("SEA deep pit floor=%.2f eye=%.2f depth=%.2f flooded=%s veil=%.2f" % [
			pit_floor, eye.y, sea.water_depth_at(eye),
			str(sea.is_flooded_at(eye)), wet_alpha])
		_check("a deep shore pit fills up to the tide",
			sea.is_flooded_at(eye) and sea.water_depth_at(eye) > 3.0)
		_check("the water looks like water from the inside", wet_alpha > 0.2)
		# Back on the dry beach the veil has to fade away again.
		player.global_position = Vector3(0.0, 0.0, 6.0)
		sea._update_veil(1.0)
		print("SEA back on the beach veil=%.2f" % sea._veil_alpha)
		_check("the veil clears on dry land", sea._veil_alpha < 0.05)

	# --- Water the tide left behind runs down, then soaks away -------------
	# Take the tide out: the deep hole above is now cut off from the sea. What is
	# left in it has to run down to a level surface in the bottom of the hole
	# rather than sit up on the walls, and the sand then drinks it away instead of
	# keeping the pool there forever.
	var full_depth := sea.water_depth_at(deep_pit)
	sea._time = 0.0
	sea._update_tide(0.0)
	sea.settle_water(16.0)
	var centre := sea._cell_at(deep_pit)
	var low := 999.0
	var high := -999.0
	var wet := 0
	for dz in range(-8, 9):
		for dx in range(-8, 9):
			var i: int = centre + dz * SandTerrain.GRID_SIZE + dx
			if sea._depth[i] > 0.05:
				var s: float = terrain.heights[i] + sea._depth[i]
				low = minf(low, s)
				high = maxf(high, s)
				wet += 1
	print("SEA cut-off pool wet=%d surface %.2f..%.2f spread=%.2f" % [
		wet, low, high, high - low])
	_check("water left in a cut-off hole runs down to one level",
		wet >= 100 and high - low < 0.25)

	var levelled_depth := sea.water_depth_at(deep_pit)
	sea.settle_water(40.0)
	var soaked_depth := sea.water_depth_at(deep_pit)
	print("SEA seep depth full=%.2f levelled=%.2f soaked=%.2f" % [
		full_depth, levelled_depth, soaked_depth])
	_check("the sand drinks a pool the tide left behind",
		soaked_depth < levelled_depth and soaked_depth < full_depth * 0.5)

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

	# --- The sea is stingy with a littered beach ---------------------------
	# Every piece already lying ashore slows the next delivery down, and there is
	# a hard ceiling so the beach can never silt up completely. Collecting the
	# junk empties the beach and the sea speeds straight back up.
	var littered := loot._sea_trash_count()
	loot._sea_spawn_timer = 0.0
	loot._process(0.0)
	var expected := LootManager.SEA_SPAWN_INTERVAL * (1.0 + float(littered) * LootManager.SEA_LITTER_PENALTY)
	print("SEA littered=%d next delivery in %.1f s (clean beach %.1f s)" % [
		littered, loot._sea_spawn_timer, LootManager.SEA_SPAWN_INTERVAL])
	_check("a littered beach slows the sea down",
		is_equal_approx(loot._sea_spawn_timer, expected)
		and loot._sea_spawn_timer > LootManager.SEA_SPAWN_INTERVAL)
	_check("the shore junk ceiling is tight enough to stay tidy",
		LootManager.SEA_MAX_TOTAL <= 20)

	# Fill the beach: every delivery is beached straight away, so the only thing
	# that can stop the sea is the ceiling itself.
	for i in LootManager.SEA_MAX_TOTAL + 10:
		loot._sea_spawn_timer = 0.0
		loot._process(0.0)
		loot._drift_floating(1000.0)
		loot._drift_floating(1000.0)
	print("SEA beach junk after %d delivery attempts: %d" % [
		LootManager.SEA_MAX_TOTAL + 10, loot._sea_trash_count()])
	_check("the sea stops delivering at the ceiling",
		loot._sea_trash_count() == LootManager.SEA_MAX_TOTAL)

	# --- Ebb tide: junk sinks into the sand, it is not carried back out -----
	# When the wave pulls back, junk still in the surf must stop travelling and
	# be swallowed by the wet sand where the wave left it.
	sea._time = Sea.TIDE_PERIOD * 0.75
	sea._update_tide(0.0)
	_check("the tide is going out", not sea.rising)
	var left := loot._spawn_sea_trash()
	_check("ebb junk starts afloat", left != null and left.floating)
	if left != null:
		# Put it on the wet sand just inside the waterline, as if the surf had
		# just pushed it up the beach.
		var left_x := left.node.position.x
		var left_z := sea.shoreline_z + 1.5
		var left_sand := terrain.get_height_at(Vector3(left_x, 0.0, left_z))
		left.node.position = Vector3(left_x, left_sand + 0.08, left_z)
		left.buried_position = Vector3(left_x, 0.0, left_z)
		var y_before := left.node.position.y
		var z_before := left.node.position.z
		for i in 120:
			sea._update_tide(0.1)
			loot._drift_floating(0.1)
		var rest := left_sand + LootManager.SURFACE_LIFT - LootManager.SEA_SETTLE_DEPTH
		print("SEA ebb junk z %.2f -> %.2f, y %.2f -> %.2f (rest %.2f, floating=%s)" % [
			z_before, left.node.position.z, y_before, left.node.position.y,
			rest, str(left.floating)])
		_check("ebbing junk does not travel with the water",
			absf(left.node.position.z - z_before) < 0.01
			and absf(left.node.position.x - left_x) < 0.01)
		_check("ebbing junk settles down into the sand",
			left.node.position.y < y_before
			and absf(left.node.position.y - rest) < 0.02)
		_check("settled junk is still claimable",
			not left.floating and left.revealed
			and loot.nearest_claimable(left.world_position(), 0.01) == left)

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
