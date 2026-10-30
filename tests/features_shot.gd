extends Node
## Renders the two new feedback features: a bigger tier-3 shovel in hand and the
## gold-ring banner.

func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(0.9).timeout

	var state := get_tree().get_first_node_in_group("player_state") as PlayerState
	var loot := get_tree().get_first_node_in_group("loot_manager") as LootManager

	# Equip the Earth Shovel through the normal signal path.
	state.equipment_tier_index = 3
	state.equipment_changed.emit(state.get_current_equipment())
	await get_tree().create_timer(0.8).timeout
	_save("res://shovel_tier3_proof.png")

	# Uncover a ring for real (dig it out) so the shot shows it in its pit.
	var terrain := get_tree().get_first_node_in_group("sand_terrain") as SandTerrain
	var player := get_tree().get_first_node_in_group("player") as FirstPersonPlayer
	var ring: LootManager.LootItem = null
	for item in loot.loot:
		if item.kind == "ring" and not item.revealed and not item.claimed:
			ring = item
			break
	if ring != null:
		var digs := 0
		while not ring.revealed and digs < 400:
			terrain.dig_at(ring.buried_position, 0.9, 0.3)
			digs += 1
		player.global_position = ring.buried_position + Vector3(0.0, 0.2, 1.9)
		player.head.rotation_degrees.x = -32.0
	await get_tree().create_timer(0.5).timeout
	_save("res://ring_proof.png")

	get_tree().quit(0)


func _save(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("FEATURE SHOT %s err=%d" % [path, err])
