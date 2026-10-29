extends Node
## Detector edge-wash proof: one shot standing far from junk (cool, dim wash) and
## one standing on top of a buried item (hot, bright wash).

func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(0.9).timeout

	var hud := get_tree().get_first_node_in_group("hud") as Hud
	var loot := get_tree().get_first_node_in_group("loot_manager") as LootManager
	var player := get_tree().get_first_node_in_group("player") as Node3D

	# Stand on the loneliest spot we can find, so the reading is cold.
	var best := Vector3.ZERO
	var best_distance := -1.0
	for i in 24:
		var angle := TAU * float(i) / 24.0
		for radius in [6.0, 12.0, 18.0, 24.0]:
			var point := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			var distance := loot.nearest_distance(point)
			if distance > best_distance:
				best_distance = distance
				best = point
	player.global_position = Vector3(best.x, 0.2, best.z)
	await get_tree().create_timer(0.3).timeout
	print("EDGE SHOT far distance=%.2f strength=%.2f" % [
		best_distance, loot.signal_strength(player.global_position)])
	hud._fire_ping()
	await get_tree().create_timer(0.06).timeout
	await RenderingServer.frame_post_draw
	_save("res://edge_far.png")

	# Stand right beside a buried item, so the reading is hot.
	var target: LootManager.LootItem = null
	for item in loot.loot:
		if not item.on_surface and not item.claimed:
			target = item
			break
	if target != null:
		var spot := target.buried_position
		player.global_position = Vector3(spot.x + 0.5, 0.2, spot.z)
		await get_tree().create_timer(0.3).timeout
		print("EDGE SHOT near strength=%.2f" % loot.signal_strength(player.global_position))
		hud._fire_ping()
		await get_tree().create_timer(0.06).timeout
		await RenderingServer.frame_post_draw
		_save("res://edge_near.png")

	get_tree().quit(0)


func _save(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("EDGE SHOT %s err=%d" % [path, err])
