class_name DigController
extends Node
## First-person digging, looting, selling and tool use.
##
## Digging: hold left mouse to carve sand under the crosshair with THIS
## player's current equipment. Only the sand terrain is diggable, and every dig
## is rate limited so a held button cannot delete the beach in one frame.
##
## Left click also fires the metal detector when it is the tool in hand. Keys
## 1-7 pick up a bag slot (one item at a time) and Q swaps shovel <-> detector.
## The junkyard only buys the item actually in hand; the market stall sells the
## detector and the shovel upgrades.
##
## Phase 3 turns `_try_dig()` into a `request_dig` RPC and moves the heightmap
## mutation to the host; nothing else in this script changes.

const DIG_REACH := 3.6
const DIG_INTERVAL := 0.4
const INTERACT_RANGE := 2.8
## The detector is a one-shot sweep on a long recharge so it stays a decision.
const DETECTOR_COOLDOWN := 15.0

var _player_body: FirstPersonPlayer
var _camera: Camera3D
var _terrain: SandTerrain
var _state: PlayerState
var _loot: LootManager
var _hud: Hud
var _market: Market

var _dig_cooldown := 0.0
var _digging := false
var _total_dug := 0.0
var _dig_count := 0
var _detector_cooldown := 0.0


func _ready() -> void:
	_player_body = get_parent() as FirstPersonPlayer
	_camera = get_node_or_null("../Head/Camera3D") as Camera3D
	_state = get_node_or_null("../PlayerState") as PlayerState

	if _player_body == null or _camera == null:
		push_error("DigController must be a child of the player, with Head/Camera3D")
		set_process_unhandled_input(false)
		set_process(false)
		return
	# Only the machine that owns this body may dig, loot or sell with it.
	if not _player_body.is_local_player():
		set_process(false)
		set_process_unhandled_input(false)
		return
	_resolve_world()


## Binds the terrain/loot/HUD once they exist. Sibling order means they are not
## in their groups yet when this node starts, so this is retried from _process.
func _resolve_world() -> void:
	if _terrain == null:
		_terrain = get_tree().get_first_node_in_group("sand_terrain") as SandTerrain
	if _loot == null:
		_loot = get_tree().get_first_node_in_group("loot_manager") as LootManager
		if _loot != null and not _loot.loot_claimed.is_connected(_on_loot_claimed):
			_loot.loot_claimed.connect(_on_loot_claimed)
	if _hud == null:
		_hud = get_tree().get_first_node_in_group("hud") as Hud
	if _state == null and _player_body != null:
		# This player's own progression, never another player's.
		_state = _player_body.get_node_or_null("PlayerState") as PlayerState
	if _market == null:
		_market = get_tree().get_first_node_in_group("market") as Market


func _process(delta: float) -> void:
	_resolve_world()
	if _dig_cooldown > 0.0:
		_dig_cooldown -= delta
	if _detector_cooldown > 0.0:
		_detector_cooldown = maxf(0.0, _detector_cooldown - delta)
	if _digging and _dig_cooldown <= 0.0 and _mouse_captured() and _shovel_in_hand():
		_try_dig()
	_update_prompt()
	_update_tool_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_digging = mouse_event.pressed and _shovel_in_hand()
			if mouse_event.pressed and _mouse_captured():
				_primary_action()
		return

	if event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("switch_tool"):
		_switch_tool()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key >= KEY_1 and key <= KEY_7:
			_select_slot(key - KEY_1)


func _mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _holding_loot() -> bool:
	return _state != null and _state.held_slot >= 0


func _shovel_in_hand() -> bool:
	return (_player_body != null and _player_body.tool_mode == FirstPersonPlayer.TOOL_SHOVEL
		and not _holding_loot())


## Left click: fire the detector when it is in hand, otherwise dig.
func _primary_action() -> void:
	if _holding_loot():
		return
	if _player_body.tool_mode == FirstPersonPlayer.TOOL_DETECTOR:
		_use_detector()
		return
	if _dig_cooldown <= 0.0:
		_try_dig()


func _try_dig() -> void:
	if _terrain == null or _state == null or _camera == null:
		return
	_dig_cooldown = DIG_INTERVAL

	var origin := _camera.global_position
	var direction := -_camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * DIG_REACH)
	query.collide_with_areas = false
	var hit := _terrain.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	if hit.get("collider") != _terrain:
		return

	var equipment := _state.get_current_equipment()
	var world_position: Vector3 = hit["position"]
	# The host carves and broadcasts; a client only asks and lets the broadcast
	# carve its own copy, so every beach ends up identical.
	_terrain.submit_dig(world_position, _state.player_id, equipment.tier_index)
	_dig_count += 1
	if _player_body.has_method("play_dig_swing"):
		_player_body.play_dig_swing()
	print("[dig] p%d %s at %s" % [
		_state.player_id, equipment.display_name, str(world_position)])


func _interact() -> void:
	if _state == null:
		return
	var position := _player_body.global_position

	# Market stall first: standing there means you want the shop, not the loot.
	if _market != null and position.distance_to(_market.global_position) <= Market.INTERACT_RADIUS:
		_market.open_shop()
		return

	# Junkyard buys ONLY the item in hand, one sale per press.
	var yard := get_tree().get_first_node_in_group("junkyard") as Node3D
	if yard != null and position.distance_to(yard.global_position) <= Junkyard.SELL_RADIUS:
		_sell_held()
		return

	if _loot != null:
		var item := _loot.nearest_claimable(position, INTERACT_RANGE)
		if item != null:
			if _state.is_inventory_full():
				_flash_hud("Bag full (%d/%d) - sell something first" % [
					PlayerState.INVENTORY_SLOTS, PlayerState.INVENTORY_SLOTS])
				return
			# The host decides who got it; the "Picked up" line comes from the
			# claim broadcast so every peer tells the same story.
			if not _loot.take_loot(item.loot_id, _state.player_id):
				_flash_hud("Too late - already claimed")


func _on_loot_claimed(item: Dictionary) -> void:
	if _state == null or int(item.get("owner", 0)) != _state.player_id:
		return
	Sfx.play_ui("pickup", 0.05, -4.0)
	_flash_hud("Picked up %s  ($%d)  -  bag %d/%d" % [
		str(item.get("name", "loot")), int(item.get("value", 0)),
		_state.carried_count(), PlayerState.INVENTORY_SLOTS])


## Puts the item in bag slot `index` in hand (pressing it again puts it away).
func _select_slot(index: int) -> void:
	if _state == null:
		return
	if index < 0 or index >= _state.bag_slots.size() or _state.bag_slots[index].is_empty():
		_flash_hud("Slot %d is empty" % (index + 1))
		return
	_state.set_held_slot(index)


func _sell_held() -> void:
	var item := _state.sell_held()
	if item.is_empty():
		Sfx.play_ui("denied", 0.04, -8.0)
		_flash_hud("Hold an item first - press 1-7")
		return
	Sfx.play_ui("coin", 0.06, -3.0)
	_flash_hud("Sold %s for $%d" % [str(item.get("name", "item")), int(item.get("value", 0))])


func _switch_tool() -> void:
	if _state == null or _player_body == null:
		return
	if not _state.has_detector:
		_flash_hud("No detector yet - buy one at the market ($%d)" % int(PlayerState.DETECTOR_PRICE))
		return
	# Swapping tools puts the item in hand away first.
	if _state.held_slot >= 0:
		_state.set_held_slot(-1)
	_player_body.toggle_tool()
	_flash_hud("Holding: %s" % ("Metal Detector" if _player_body.tool_mode == FirstPersonPlayer.TOOL_DETECTOR else "Shovel"))


func _use_detector() -> void:
	if _loot == null or _hud == null or _state == null:
		return
	if not _state.has_detector:
		return
	if _detector_cooldown > 0.0:
		_flash_hud("Detector recharging - %.0f s" % ceilf(_detector_cooldown))
		return
	_detector_cooldown = DETECTOR_COOLDOWN
	_hud.ping_detector()
	_flash_hud("Detector ping - listen for the beeps")


func _update_tool_status() -> void:
	if _hud == null or _state == null or _player_body == null:
		return
	var held := _state.held_item()
	if not held.is_empty():
		_hud.set_detector_status("In hand: %s  ($%d)  -  press %d to put away" % [
			str(held.get("name", "item")), int(held.get("value", 0)), _state.held_slot + 1])
		return
	if _player_body.tool_mode == FirstPersonPlayer.TOOL_DETECTOR:
		if _detector_cooldown > 0.0:
			_hud.set_detector_status("Detector: %.0f s" % ceilf(_detector_cooldown))
		else:
			_hud.set_detector_status("Detector: ready  -  left click   [Q] shovel")
		return
	_hud.set_detector_status("Shovel: %s   [Q] %s" % [
		_state.get_current_equipment().display_name,
		"detector" if _state.has_detector else "detector (buy at the market)"])


func _update_prompt() -> void:
	if _hud == null or _state == null or _player_body == null:
		return
	var position := _player_body.global_position

	if _market != null and position.distance_to(_market.global_position) <= Market.INTERACT_RADIUS:
		_hud.show_prompt("[E] Open the market")
		return

	var yard := get_tree().get_first_node_in_group("junkyard") as Node3D
	if yard != null and position.distance_to(yard.global_position) <= Junkyard.SELL_RADIUS:
		var held := _state.held_item()
		if not held.is_empty():
			_hud.show_prompt("[E] Sell %s  ($%d)" % [
				str(held.get("name", "item")), int(held.get("value", 0))])
		elif _state.carried_count() == 0:
			_hud.show_prompt("Junkyard - nothing to sell yet")
		else:
			_hud.show_prompt("Junkyard - hold an item (1-7) to sell it")
		return

	if _loot != null:
		var item := _loot.nearest_claimable(position, INTERACT_RANGE)
		if item != null:
			if _state.is_inventory_full():
				_hud.show_prompt("Bag full - sell items at the junkyard")
			else:
				_hud.show_prompt("[E] Take %s  ($%d)" % [item.display_name, int(item.value)])
			return

	_hud.show_prompt("")


func _flash_hud(text: String) -> void:
	if _hud != null:
		_hud.flash(text)
