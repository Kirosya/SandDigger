extends Node
## Proof shots for the hand/inventory/market/third-person pass.

func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(1.0).timeout

	var state := get_tree().get_first_node_in_group("player_state") as PlayerState
	var player := get_tree().get_first_node_in_group("player") as FirstPersonPlayer
	if state == null or player == null:
		print("SHOT FAIL no player")
		get_tree().quit(1)
		return

	# 1. Metal detector held in the first-person hand.
	state.add_money(120.0)
	state.buy_detector()
	player.set_tool_mode(FirstPersonPlayer.TOOL_DETECTOR)
	await get_tree().create_timer(0.5).timeout
	_save("res://proof_detector.png")

	# 2. Seven-slot bag with a couple of items, one of them held.
	state.add_loot({"id": 1, "name": "Rusty Can", "kind": "can", "value": 28.0})
	state.add_loot({"id": 2, "name": "Old Boot", "kind": "leather", "value": 44.0})
	state.add_loot({"id": 3, "name": "Scrap Metal", "kind": "scrap", "value": 61.0})
	state.set_held_slot(1)
	await get_tree().create_timer(0.4).timeout
	_save("res://proof_inventory.png")

	# 3. Market panel.
	var shop := get_tree().get_first_node_in_group("shop_ui") as ShopUI
	if shop != null:
		shop.open(state, player)
		await get_tree().create_timer(0.4).timeout
		_save("res://proof_shop.png")
		shop.close()
		await get_tree().create_timer(0.3).timeout

	# 4. Hold R: third-person view of the beachcomber.
	state.set_held_slot(-1)
	player.set_tool_mode(FirstPersonPlayer.TOOL_SHOVEL)
	Input.action_press("third_person")
	await get_tree().create_timer(0.5).timeout
	_save("res://proof_third_person.png")
	Input.action_release("third_person")
	await get_tree().create_timer(0.3).timeout

	# 5. The beach with the tide in: sea, foam line and wet sand.
	var sea := get_tree().get_first_node_in_group("sea") as Sea
	if sea != null:
		player.global_position = Vector3(0.0, 0.2, -5.0)
		player.rotation.y = 0.0
		sea._update_tide(Sea.TIDE_PERIOD * 0.5)
		await get_tree().create_timer(0.8).timeout
		_save("res://proof_sea.png")

	get_tree().quit(0)


func _save(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("SHOT %s err=%d" % [path, err])
