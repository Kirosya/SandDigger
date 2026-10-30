extends Node
## Proof shots for "loot is always in the sand": a buried ring is hidden under
## flat sand, then emerges as the pit deepens, then is revealed.

func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(0.9).timeout

	var loot := get_tree().get_first_node_in_group("loot_manager") as LootManager
	var terrain := get_tree().get_first_node_in_group("sand_terrain") as SandTerrain
	var ring: LootManager.LootItem = null
	for item in loot.loot:
		if item.kind == "ring" and not item.on_surface:
			ring = item
			break
	if ring == null:
		print("BURIED SHOT no ring")
		get_tree().quit(1)
		return

	var spot := ring.buried_position
	# Wide eye-level look first: no buried item may poke through the sand.
	var wide := Camera3D.new()
	game.add_child(wide)
	wide.global_position = Vector3(spot.x, 1.7, spot.z + 5.0)
	wide.look_at(Vector3(spot.x, 0.0, spot.z))
	wide.fov = 70.0
	wide.current = true
	await RenderingServer.frame_post_draw
	await _capture("res://buried_wide.png", ring, terrain)

	var cam := Camera3D.new()
	game.add_child(cam)
	var target := Vector3(spot.x, -ring.depth * 0.5, spot.z)
	cam.global_position = target + Vector3(0.0, 1.25, 1.05)
	cam.look_at(target)
	cam.fov = 55.0
	cam.current = true
	await RenderingServer.frame_post_draw
	await _capture("res://buried_0_hidden.png", ring, terrain)

	var digs := 0
	var stage := 0
	# The ring is the deepest item on the beach (RING_DEPTH), and sand caves in:
	# reaching it takes a wide, patient excavation with a late-game shovel, not a
	# fixed number of narrow scoops.
	while digs < 400:
		digs += 1
		terrain.dig_at(spot, 0.9, 0.3)
		var surface := terrain.get_height_at(spot)
		if stage == 0 and surface <= -ring.depth * 0.65:
			stage = 1
			await _capture("res://buried_1_pit.png", ring, terrain)
		elif stage == 1 and surface <= -ring.depth + 0.09:
			stage = 2
			await _capture("res://buried_2_peeking.png", ring, terrain)
		if ring.revealed:
			break
	await _capture("res://buried_3_revealed.png", ring, terrain)

	print("BURIED SHOT done digs=%d depth=%.2f" % [digs, ring.depth])
	get_tree().quit(0)


func _capture(path: String, ring: LootManager.LootItem, terrain: SandTerrain) -> void:
	await RenderingServer.frame_post_draw
	var surface := terrain.get_height_at(ring.buried_position)
	print("BURIED SHOT %s surface=%.3f item_y=%.3f revealed=%s" % [
		path, surface, ring.node.position.y, str(ring.revealed)])
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("BURIED SHOT save %s err=%d" % [path, err])
