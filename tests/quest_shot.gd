extends Node
## Renders the quest HUD: the open quest with its progress, and the completion
## banner with the payout.

func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(0.9).timeout

	var loot := get_tree().get_first_node_in_group("loot_manager") as LootManager
	var state := Net.local_state()
	if loot == null or state == null:
		get_tree().quit(1)
		return

	# One of three junk finds, so the line shows the progress counter.
	_claim(loot, state, "trash", "Old Boot")
	await get_tree().create_timer(0.3).timeout
	_save("res://quest_hud_proof.png")

	# Finish the quest for the banner.
	_claim(loot, state, "trash", "Plastic Bottle")
	_claim(loot, state, "trash", "Rusty Can")
	await get_tree().create_timer(0.45).timeout
	_save("res://quest_complete_proof.png")

	get_tree().quit(0)


func _claim(loot: LootManager, state: PlayerState, kind: String, display_name: String) -> void:
	loot.loot_claimed.emit({
		"id": 1,
		"name": display_name,
		"kind": kind,
		"value": 10.0,
		"owner": state.player_id,
		"position": Vector3.ZERO,
		"treasure": false,
	})


func _save(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("QUEST SHOT %s err=%d" % [path, err])
