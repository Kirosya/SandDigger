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
	var dig := player.get_node_or_null("DigController") as DigController
	_check("player has a dig controller", dig != null)

	# --- Seven-slot bag -----------------------------------------------------
	for i in PlayerState.INVENTORY_SLOTS:
		state.add_loot({"id": i + 1, "name": "Junk %d" % (i + 1), "kind": "can",
			"value": 10.0 + float(i)})
	_check("bag holds 7 items", state.carried_count() == PlayerState.INVENTORY_SLOTS)
	_check("bag has exactly 7 fixed slots",
		state.bag_slots.size() == PlayerState.INVENTORY_SLOTS)
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
		state.carried_count(), state.held_slot])
	_check("sold exactly the held item", str(sold.get("name", "")) == "Junk 3")
	_check("only one item left the bag",
		state.carried_count() == PlayerState.INVENTORY_SLOTS - 1)
	_check("money increased by that item's value", is_equal_approx(earned, 12.0))
	_check("the sold slot is empty", state.bag_slots[2].is_empty())
	_check("nothing is held after a sale", state.held_slot == -1)
	_check("later items keep the slots they were put in",
		str(state.bag_slots[3].get("name", "")) == "Junk 4"
		and str(state.bag_slots[6].get("name", "")) == "Junk 7")
	# New loot fills the first hole instead of shifting everything forward.
	state.add_loot({"id": 50, "name": "New Junk", "kind": "can", "value": 5.0})
	_check("new loot fills the first empty slot",
		str(state.bag_slots[2].get("name", "")) == "New Junk")
	_check("the bag is full again", state.carried_count() == PlayerState.INVENTORY_SLOTS)

	# --- Detector is a bought hand tool ------------------------------------
	_check("no detector at the start", not state.has_detector)
	# Slot 2 is the detector's fixed place on the hotbar. Without owning one it
	# must not switch the hand.
	dig._select_hotbar(PlayerState.SLOT_DETECTOR)
	_check("slot 2 does nothing without a detector",
		player.tool_mode == FirstPersonPlayer.TOOL_SHOVEL and state.held_slot == -1)
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

	# --- Unified hotbar: tools and loot in one numbered row ----------------
	_check("hotbar is the two tools plus the seven bag slots",
		PlayerState.SLOT_COUNT == PlayerState.FIRST_BAG_SLOT + PlayerState.INVENTORY_SLOTS)
	_check("shovel is hotbar slot 1", PlayerState.hotbar_index(-1, false) == PlayerState.SLOT_SHOVEL)
	_check("detector is hotbar slot 2", PlayerState.hotbar_index(-1, true) == PlayerState.SLOT_DETECTOR)
	_check("a held item maps to its bag slot", PlayerState.hotbar_index(3, false) == 5)
	_check("bag slots start at the third slot",
		PlayerState.bag_index_of(PlayerState.FIRST_BAG_SLOT) == 0)
	_check("tool slots have no bag index",
		PlayerState.bag_index_of(PlayerState.SLOT_DETECTOR) == -1)

	# Slot 2 puts the detector in hand and stows whatever was held.
	dig._select_hotbar(PlayerState.SLOT_DETECTOR)
	_check("slot 2 puts the detector in hand",
		player.tool_mode == FirstPersonPlayer.TOOL_DETECTOR and state.held_slot == -1)
	_check("the detector is held in one hand",
		player.rig._right_arm.visible and not player.rig._left_arm.visible)
	dig._select_hotbar(PlayerState.SLOT_SHOVEL)
	_check("slot 1 puts the shovel back",
		player.tool_mode == FirstPersonPlayer.TOOL_SHOVEL and state.held_slot == -1)
	_check("the shovel is held in both hands",
		player.rig._right_arm.visible and player.rig._left_arm.visible)

	dig._select_hotbar(PlayerState.FIRST_BAG_SLOT + 2)
	_check("slot 5 holds bag item 3", state.held_slot == 2)
	_check("a bag item hides the tool", player.item_pivot.visible)
	_check("junk is held in one hand, not two",
		player.rig._right_arm.visible and not player.rig._left_arm.visible)
	dig._cycle_hotbar(1)
	_check("wheel down goes to the next bag slot", state.held_slot == 3)
	dig._cycle_hotbar(-1)
	_check("wheel up comes back", state.held_slot == 2)

	# --- An empty slot is a valid choice: empty hands ----------------------
	# Empty a slot by selling what it held: the cursor stays on it.
	var empty_bag := 6
	state.select_slot(PlayerState.FIRST_BAG_SLOT + empty_bag)
	state.sell_held()
	_check("a sold slot is empty but still selected",
		state.bag_slots[empty_bag].is_empty()
		and state.selected_slot == PlayerState.FIRST_BAG_SLOT + empty_bag
		and state.held_slot == -1)
	dig._select_hotbar(PlayerState.SLOT_SHOVEL)
	dig._select_hotbar(PlayerState.FIRST_BAG_SLOT + empty_bag)
	_check("an empty slot can be selected",
		state.selected_slot == PlayerState.FIRST_BAG_SLOT + empty_bag)
	_check("an empty slot means empty hands",
		state.held_slot == -1 and state.is_hand_empty())
	_check("empty hands show no tool and no item",
		not player.spoon_pivot.visible and not player.detector_pivot.visible
		and not player.item_pivot.visible)
	_check("empty hands hide both viewmodel arms",
		not player.rig._right_arm.visible and not player.rig._left_arm.visible)
	# A tool click while empty-handed must not dig or swing anything.
	dig._primary_action()
	_check("left click with empty hands does nothing",
		dig._dig_count == 0 and not player.spoon_pivot.visible)

	# Pressing the selected filled slot again stows the item but keeps the slot.
	dig._select_hotbar(PlayerState.FIRST_BAG_SLOT + 2)
	dig._select_hotbar(PlayerState.FIRST_BAG_SLOT + 2)
	_check("pressing the selected slot again stows the item", state.held_slot == -1)
	_check("stowing keeps the cursor on that slot",
		state.selected_slot == PlayerState.FIRST_BAG_SLOT + 2)
	dig._select_hotbar(PlayerState.FIRST_BAG_SLOT + 2)
	_check("pressing it once more holds it again", state.held_slot == 2)

	# --- Left click sells at the junkyard, exactly like E -----------------
	var yard := Junkyard.new()
	yard.name = "TestJunkyard"
	add_child(yard)
	await get_tree().process_frame
	yard.global_position = player.global_position
	var money_before_click := state.current_money
	dig._primary_action()
	print("INV click sell held=%d money=%.0f bag=%d" % [
		state.held_slot, state.current_money, state.carried_count()])
	_check("left click sells the held item at the junkyard",
		state.held_slot == -1 and state.current_money > money_before_click)
	_check("left click sold only the held item", state.bag_slots[2].is_empty())
	_check("after a sale the hand stays empty on the same slot",
		state.selected_slot == PlayerState.FIRST_BAG_SLOT + 2
		and state.is_hand_empty())
	_check("after a sale no other item jumps into the hand",
		not player.item_pivot.visible and not player.spoon_pivot.visible)
	_check("after a sale the cursor did not move to another slot",
		state.held_slot == -1)

	# The same click away from the junkyard must not sell anything.
	yard.global_position = player.global_position + Vector3(0.0, 0.0, 40.0)
	state.set_held_slot(1)
	var money_before_far := state.current_money
	dig._primary_action()
	_check("a click away from the junkyard does not sell",
		state.held_slot == 1 and is_equal_approx(state.current_money, money_before_far))

	# An empty bag slot is skipped instead of becoming a dead stop.
	dig._cycle_hotbar(1)
	_check("wheel skips an empty bag slot", state.held_slot == 3)
	state.set_held_slot(-1)
	yard.queue_free()
	await get_tree().process_frame

	# The wheel itself is bound, not just the helper it calls.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	dig._select_hotbar(PlayerState.FIRST_BAG_SLOT)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	dig._unhandled_input(wheel)
	_check("mouse wheel down changes the slot", state.held_slot == 1)
	state.set_held_slot(-1)

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
		# Let the level-up fanfare (0.71 s) finish: quitting in the same frame as
		# a playing stream makes Godot report a leaked playback at exit.
		await get_tree().create_timer(0.9).timeout
		get_tree().quit(0)
	else:
		print("INVENTORY FAILED (%d)" % _failures)
		get_tree().quit(1)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
