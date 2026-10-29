extends Node
## Market / junkyard integration test on the real main scene.
##
## Walks up to the market, opens the panel with E, buys the detector, checks the
## level gate on shovels, then walks to the junkyard and sells exactly the held
## item. Run headless:
##   godot --headless --path . res://tests/shop_test.tscn

var _failures := 0


func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(0.4).timeout

	var state := get_tree().get_first_node_in_group("player_state") as PlayerState
	var player := get_tree().get_first_node_in_group("player") as FirstPersonPlayer
	var shop := get_tree().get_first_node_in_group("shop_ui") as ShopUI
	var market := get_tree().get_first_node_in_group("market") as Market
	var yard := get_tree().get_first_node_in_group("junkyard") as Node3D
	_check("main scene has a player state", state != null)
	_check("main scene has a market", market != null)
	_check("main scene has a shop panel", shop != null)
	_check("main scene has a junkyard", yard != null)
	if state == null or player == null or shop == null or market == null or yard == null:
		_finish()
		return

	# --- Open the market by standing next to it and pressing E -------------
	player.global_position = market.global_position + Vector3(0.0, 0.2, 2.0)
	await get_tree().process_frame
	_press_key(KEY_E)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("E at the market opens the shop", shop.is_open())
	_check("shop pauses the game", get_tree().paused)

	# --- Buy the detector --------------------------------------------------
	state.add_money(100.0)
	var money_before := state.current_money
	shop._buy(0)
	_check("detector bought through the shop", state.has_detector)
	_check("detector money was spent",
		is_equal_approx(money_before - state.current_money, PlayerState.DETECTOR_PRICE))
	_check("detector is swapped into the hand",
		player.tool_mode == FirstPersonPlayer.TOOL_DETECTOR)

	# --- Shovel upgrades need level AND money, and are sequential ----------
	var money_before_shovel := state.current_money
	shop._buy(1)
	_check("Sand Shovel is blocked below level 3", state.equipment_tier_index == 0)
	_check("no money was taken for a blocked upgrade",
		is_equal_approx(state.current_money, money_before_shovel))
	shop._buy(2)
	_check("Garden Shovel cannot be bought out of order", state.equipment_tier_index == 0)

	state.add_money(50.0)
	state.add_dig_volume(2.0)
	_check("level 3 reached", state.current_level == 3)
	# A row is a Button, so a mouse click / touch tap buys it like the keys do.
	var shovel_row := shop._rows[1] as Button
	_check("shop rows are clickable buttons", shovel_row != null)
	if shovel_row != null:
		var center := shovel_row.get_global_rect().get_center()
		_click(center)
		await get_tree().process_frame
		await get_tree().process_frame
	_check("Sand Shovel bought by clicking its row", state.equipment_tier_index == 1)

	shop.close()
	_check("closing the shop unpauses", not get_tree().paused)

	# --- Junkyard sells only the held item --------------------------------
	state.add_loot({"id": 501, "name": "Rusty Can", "kind": "can", "value": 28.0})
	state.add_loot({"id": 502, "name": "Old Boot", "kind": "leather", "value": 44.0})
	state.set_held_slot(1)
	player.global_position = yard.global_position + Vector3(0.0, 0.2, 2.0)
	await get_tree().process_frame
	var bag_before := state.carried_count()
	var money_before_sale := state.current_money
	_press_key(KEY_E)
	await get_tree().process_frame
	await get_tree().process_frame
	print("SHOP sale bag=%d money=%.0f held=%d" % [
		state.carried_count(), state.current_money, state.held_slot])
	_check("one item was sold", state.carried_count() == bag_before - 1)
	_check("the sold item was the held one",
		str(state.bag_slots[0].get("name", "")) == "Rusty Can"
		and state.bag_slots[1].is_empty())
	_check("junkyard paid the item value",
		is_equal_approx(state.current_money - money_before_sale, 44.0))

	# Empty hand: the junkyard must refuse.
	state.set_held_slot(-1)
	var money_before_empty := state.current_money
	_press_key(KEY_E)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("empty hand sells nothing",
		state.carried_count() == 1
		and is_equal_approx(state.current_money, money_before_empty))

	_finish()


func _press_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)


## Sends a real left click through the viewport GUI, exactly like a mouse or a
## touch tap would.
func _click(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_viewport().push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = position
		event.global_position = position
		get_viewport().push_input(event, true)


func _finish() -> void:
	if _failures == 0:
		print("SHOP OK")
		get_tree().quit(0)
	else:
		print("SHOP FAILED (%d)" % _failures)
		get_tree().quit(1)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
