extends Node3D
## Inventory, hand and market test.
##
## Verifies the 7-slot bag, one-at-a-time selling of the held item, the detector
## as a bought hand tool, sequential shovel upgrades, and the R third-person
## camera. Run headless:
##   godot --headless --path . res://tests/inventory_test.tscn

var _failures := 0


func _ready() -> void:
	var terrain := SandTerrain.new()
	terrain.name = "SandTerrain"
	add_child(terrain)
	await get_tree().process_frame

	var loot := LootManager.new()
	loot.name = "LootManager"
	add_child(loot)
	await get_tree().process_frame

	var player: Node3D = load("res://scenes/player.tscn").instantiate()
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame

	var state := player.get_node_or_null("PlayerState") as PlayerState
	_check("player state exists", state != null)
	if state == null:
		_finish()
		return

	# --- Seven-slot bag -----------------------------------------------------
	for i in PlayerState.INVENTORY_SLOTS:
		state.add_loot({"id": i + 1, "name": "Junk %d" % (i + 1), "kind": "can",
			"value": 10.0 + float(i)})
	_check("bag holds 7 items", state.carried_loot.size() == PlayerState.INVENTORY_SLOTS)
	_check("bag reports full", state.is_inventory_full())
	_check("an eighth item is rejected",
		not state.add_loot({"id": 99, "name": "Extra", "kind": "can", "value": 1.0}))
	_check("picking loot up leaves the tool in hand", state.held_slot == -1)

	state.set_held_slot(2)
	_check("pressing a slot holds that item", state.held_slot == 2)
	_check("held item follows the slot",
		str(state.held_item().get("name", "")) == "Junk 3")
	state.set_held_slot(2)
	_check("pressing the same slot puts it away", state.held_slot == -1)
	state.set_held_slot(2)

	# --- Selling only what is in hand --------------------------------------
	var carried_before := state.carried_value()
	var money_before := state.current_money
	var sold := state.sell_held()
	var earned := state.current_money - money_before
	print("INV sell carried=%.0f sold=%s earned=%.0f bag=%d held=%d" % [
		carried_before, str(sold.get("name", "?")), earned,
		state.carried_loot.size(), state.held_slot])
	_check("sold exactly the held item", str(sold.get("name", "")) == "Junk 3")
	_check("only one item left the bag",
		state.carried_loot.size() == PlayerState.INVENTORY_SLOTS - 1)
	_check("money increased by that item's value", is_equal_approx(earned, 12.0))
	_check("held slot slides to the next item",
		state.held_slot == 2 and str(state.held_item().get("name", "")) == "Junk 4")

	# --- Detector is a bought hand tool ------------------------------------
	_check("no detector at the start", not state.has_detector)
	state.add_money(PlayerState.DETECTOR_PRICE)
	var money_before_detector := state.current_money
	_check("detector can be bought", state.buy_detector())
	_check("detector is owned", state.has_detector)
	_check("detector cost its price",
		is_equal_approx(money_before_detector - state.current_money, PlayerState.DETECTOR_PRICE))
	_check("detector cannot be bought twice", not state.buy_detector())

	# Put the item away before swapping tools, exactly like Q does in game.
	state.set_held_slot(state.held_slot)
	player.set_tool_mode(FirstPersonPlayer.TOOL_DETECTOR)
	_check("detector model is in hand",
		player.detector_pivot.visible and not player.spoon_pivot.visible)
	player.set_tool_mode(FirstPersonPlayer.TOOL_SHOVEL)
	_check("shovel model comes back",
		player.spoon_pivot.visible and not player.detector_pivot.visible)

	# --- The held loot has a real 3D piece in the hand ----------------------
	state.set_held_slot(2)
	_check("held item pivot is visible", player.item_pivot.visible)
	_check("held item has a mesh in hand", player.item_pivot.get_child_count() > 0)
	_check("the tool is put away while holding loot", not player.spoon_pivot.visible)

	# --- Sequential shovel upgrades ----------------------------------------
	state.add_money(50.0)
	state.add_dig_volume(2.0)
	_check("tier 1 requires level 3", state.current_level == 3)
	_check("cannot skip straight to tier 2", not state.buy_tier(2))
	var money_before_upgrade := state.current_money
	_check("tier 1 upgrade succeeds", state.buy_tier(1))
	_check("tier 1 money was spent",
		is_equal_approx(money_before_upgrade - state.current_money, 50.0))
	_check("now owns the Sand Shovel", state.equipment_tier_index == 1)

	# --- Third-person camera on R ------------------------------------------
	Input.action_press("third_person")
	await get_tree().process_frame
	await get_tree().process_frame
	_check("holding R switches to the third-person camera", player.third_camera.current)
	_check("third-person camera skips the first-person viewmodel",
		(player.third_camera.cull_mask & FirstPersonPlayer.VIEWMODEL_LAYER) == 0)
	_check("third-person camera still renders the body",
		(player.third_camera.cull_mask & CharacterRig.OWNER_HIDDEN_LAYER) != 0)
	Input.action_release("third_person")
	await get_tree().process_frame
	await get_tree().process_frame
	_check("releasing R returns to first person", player.camera.current)

	_finish()


func _finish() -> void:
	if _failures == 0:
		print("INVENTORY OK")
		get_tree().quit(0)
	else:
		print("INVENTORY FAILED (%d)" % _failures)
		get_tree().quit(1)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
