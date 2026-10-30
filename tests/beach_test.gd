extends Node
## Beach persistence test.
##
## Uses scratch files, never the real `user://beach.save` or profile, and covers:
##   - the binary container round-tripping heights and the loot snapshot;
##   - wild/garbage height values being clamped on load;
##   - truncated or random files being refused (so a broken save cannot brick the
##     beach);
##   - a real dug beach surviving save -> fresh scene -> load: the hole is still
##     there, uncovered loot is uncovered again, claimed loot is still gone.

const SCRATCH := "user://test_beach.save"

var _failures := 0


func _ready() -> void:
	Profile.world_path_override = SCRATCH
	Profile.clear_world()

	_check_store()
	await _check_round_trip()
	_check_damaged_files()

	Profile.clear_world()
	Profile.world_path_override = ""
	print("BEACH %s" % ("OK" if _failures == 0 else "FAILED (%d)" % _failures))
	await get_tree().create_timer(0.4).timeout
	get_tree().quit(0 if _failures == 0 else 1)


## --- The container on its own --------------------------------------------

func _check_store() -> void:
	_check("no beach file yet", not Profile.has_world() and Profile.load_world().is_empty())

	var heights := PackedFloat32Array()
	heights.resize(SandTerrain.GRID_SIZE * SandTerrain.GRID_SIZE)
	heights.fill(0.0)
	heights[0] = 5.0
	heights[1] = -9.0
	heights[2] = NAN
	heights[3] = -0.75
	var loot := {"claimed": PackedInt32Array([3, 7]), "sea": []}
	_check("beach save succeeds", Profile.save_world(heights, loot))
	_check("beach file was written", Profile.has_world())

	var data := Profile.load_world()
	_check("beach decodes", not data.is_empty())
	var restored: PackedFloat32Array = data.get("heights", PackedFloat32Array())
	_check("height count survives", restored.size() == heights.size())
	_check("positive garbage heights are clamped", restored[0] == 0.0)
	_check("too-deep walls are clamped to the floor",
		is_equal_approx(restored[1], SandTerrain.SEA_FLOOR))
	_check("NaN heights fall back to flat sand", restored[2] == 0.0)
	_check("a real dig depth is kept", absf(restored[3] + 0.75) < 0.0001)
	_check("loot snapshot survives",
		data.get("loot", {}).get("claimed", PackedInt32Array()) == PackedInt32Array([3, 7]))

	# A container with the wrong number of vertices must not be accepted.
	_check("a beach of the wrong size is refused",
		BeachStore.decode(BeachStore.encode(PackedFloat32Array(), {})).is_empty())


## --- A whole dug beach through a save and a fresh scene -------------------

func _check_round_trip() -> void:
	var game := await _spawn_beach()
	var terrain := game.get_node("SandTerrain") as SandTerrain
	var loot := game.get_node("LootManager") as LootManager
	if terrain == null or loot == null:
		_check("the beach has terrain and loot", false)
		return

	var spot := Vector3(1.5, 0.0, 5.0)
	var pristine := terrain.get_height_at(spot)
	terrain.dig_at(spot, 0.8, 0.25)
	var dug := terrain.get_height_at(spot)
	_check("the test dig lowered the sand", dug < pristine - 0.1)

	# Two untouched buried items: uncover one and leave it, uncover and take the
	# other. Both outcomes have to survive the reload differently.
	var left_item = null
	var taken_item = null
	for item in loot.loot:
		if item.on_surface or item.floating:
			continue
		if left_item == null:
			left_item = item
		elif left_item.loot_id != item.loot_id:
			taken_item = item
			break
	if left_item == null or taken_item == null:
		_check("the beach has buried loot to test with", false)
		return

	_uncover(terrain, left_item)
	_uncover(terrain, taken_item)
	_check("digging uncovers the first test item", left_item.revealed)
	_check("digging uncovers the second test item", taken_item.revealed)
	_check("the uncovered item can be claimed",
		loot.take_loot(taken_item.loot_id, 1))
	_check("the claim is in the saved snapshot",
		taken_item.loot_id in loot.export_snapshot().claimed)
	# Read the hole last: uncovering a starter item can deepen the same spot.
	dug = terrain.get_height_at(spot)
	# Go through the real save path (`main._save_world`), not a hand-rolled call,
	# so the wiring the running game uses is what this test covers.
	game._profile_enabled = true
	game._owns_world = true
	game._world_dirty = true
	game._save_world()
	_check("the dug beach is written", Profile.has_world())

	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# A brand new beach, exactly like a restart, then the saved world on top of it.
	var again := await _spawn_beach()
	var terrain2 := again.get_node("SandTerrain") as SandTerrain
	var loot2 := again.get_node("LootManager") as LootManager
	# Same boot path as the real game: main restores its own beach on ready.
	again._profile_enabled = true
	again._owns_world = true
	again._load_world()
	var data := Profile.load_world()
	_check("the saved beach decodes on the second run", not data.is_empty())
	if data.is_empty():
		again.queue_free()
		return

	_check("the dug hole survives the restart",
		absf(terrain2.get_height_at(spot) - dug) < 0.001)

	var left_again = loot2.find_loot(left_item.loot_id)
	_check("uncovered loot is uncovered again",
		left_again != null and left_again.revealed)
	_check("uncovered loot is claimable again",
		left_again != null and loot2.nearest_claimable(left_again.buried_position, 3.0) != null)

	var taken_again = loot2.find_loot(taken_item.loot_id)
	_check("claimed loot stays claimed", taken_again != null and taken_again.claimed)
	_check("claimed loot has no visual left", taken_again != null and taken_again.node == null)
	_check("claimed loot is still marked claimed",
		taken_item.loot_id in loot2.export_snapshot().claimed)

	again.queue_free()
	await get_tree().create_timer(0.4).timeout


func _spawn_beach() -> Node:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(0.3).timeout
	return game


## Digs straight down on an item until its sand is gone.
func _uncover(terrain: SandTerrain, item) -> void:
	var at := Vector3(item.buried_position.x, 0.0, item.buried_position.z)
	for i in 4:
		if item.revealed:
			return
		terrain.dig_at(at, 1.0, 0.6)


## --- Broken files ---------------------------------------------------------

func _check_damaged_files() -> void:
	var bytes := FileAccess.get_file_as_bytes(SCRATCH)
	var file := FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_buffer(bytes.slice(0, bytes.size() / 2))
	file.close()
	_check("a truncated beach is refused", Profile.load_world().is_empty())

	file = FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_buffer(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))
	file.close()
	_check("random bytes are refused", Profile.load_world().is_empty())

	# A well-formed header with a lying vertex count is refused as well.
	var heights := PackedFloat32Array()
	heights.resize(SandTerrain.GRID_SIZE * SandTerrain.GRID_SIZE)
	var good := BeachStore.encode(heights, {})
	var lying := good.duplicate()
	lying.encode_u32(8, 12)
	_check("a lying vertex count is refused", BeachStore.decode(lying).is_empty())
	_check("the untouched container still decodes", not BeachStore.decode(good).is_empty())


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])

