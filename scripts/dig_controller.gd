class_name DigController
extends Node
## First-person digging, looting, selling and upgrading.
##
## Digging: hold left mouse to carve sand under the crosshair with THIS
## player's current equipment. Only the sand terrain is diggable, and every dig
## is rate limited so a held button cannot delete the beach in one frame.
##
## Phase 3 turns `_try_dig()` into a `request_dig` RPC and moves the heightmap
## mutation to the host; nothing else in this script changes.

const DIG_REACH := 3.6
const DIG_INTERVAL := 0.4
const INTERACT_RANGE := 2.8
## The detector is a one-shot sweep on a long recharge so it stays a decision.
const DETECTOR_COOLDOWN := 15.0

var _player_body: CharacterBody3D
var _camera: Camera3D
var _terrain: SandTerrain
var _state: PlayerState
var _loot: LootManager
var _hud: Hud

var _dig_cooldown := 0.0
var _digging := false
var _total_dug := 0.0
var _dig_count := 0
var _detector_cooldown := 0.0


func _ready() -> void:
	_player_body = get_parent() as CharacterBody3D
	_camera = get_node_or_null("../Head/Camera3D") as Camera3D
	_state = get_node_or_null("../PlayerState") as PlayerState

	if _player_body == null or _camera == null:
		push_error("DigController must be a child of the player, with Head/Camera3D")
		set_process_unhandled_input(false)
		set_process(false)
		return
	_resolve_world()


## Binds the terrain/loot/HUD once they exist. Sibling order means they are not
## in their groups yet when this node starts, so this is retried from _process.
func _resolve_world() -> void:
	if _terrain == null:
		_terrain = get_tree().get_first_node_in_group("sand_terrain") as SandTerrain
	if _loot == null:
		_loot = get_tree().get_first_node_in_group("loot_manager") as LootManager
	if _hud == null:
		_hud = get_tree().get_first_node_in_group("hud") as Hud
	if _state == null:
		_state = get_tree().get_first_node_in_group("player_state") as PlayerState


func _process(delta: float) -> void:
	_resolve_world()
	if _dig_cooldown > 0.0:
		_dig_cooldown -= delta
	if _detector_cooldown > 0.0:
		_detector_cooldown = maxf(0.0, _detector_cooldown - delta)
	if _digging and _dig_cooldown <= 0.0 and _mouse_captured():
		_try_dig()
	_update_prompt()
	_update_detector_status()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_digging = mouse_event.pressed
			if mouse_event.pressed and _dig_cooldown <= 0.0 and _mouse_captured():
				_try_dig()
		return

	if event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("detector"):
		_use_detector()
	elif event.is_action_pressed("upgrade"):
		_try_upgrade()


func _mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


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
	var volume := _terrain.dig_at(world_position, equipment.radius, equipment.depth)
	if volume <= 0.0:
		return

	var xp_gained := _state.add_dig_volume(volume)
	_total_dug += volume
	_dig_count += 1
	if _player_body.has_method("play_dig_swing"):
		_player_body.play_dig_swing()
	print("[dig] p%d %s vol=%.4f xp=+%.1f total=%.3f m3" % [
		_state.player_id, equipment.display_name, volume, xp_gained, _total_dug])


func _interact() -> void:
	if _state == null:
		return
	var position := _player_body.global_position

	if _loot != null:
		var item := _loot.nearest_claimable(position, INTERACT_RANGE)
		if item != null:
			if _loot.take_loot(item.loot_id, _state.player_id):
				_flash_hud("Picked up %s  ($%d)" % [item.display_name, int(item.value)])
			else:
				_flash_hud("Too late - already claimed")
			return

	var yard := get_tree().get_first_node_in_group("junkyard") as Node3D
	if yard != null and position.distance_to(yard.global_position) <= Junkyard.SELL_RADIUS:
		if _state.carried_loot.is_empty():
			_flash_hud("Nothing to sell")
			return
		var count := _state.carried_loot.size()
		var earned := _state.sell_all()
		_flash_hud("Sold %d item(s) for $%d" % [count, int(earned)])
		return


func _use_detector() -> void:
	if _loot == null or _hud == null:
		return
	if _detector_cooldown > 0.0:
		_flash_hud("Detector recharging - %.0f s" % ceilf(_detector_cooldown))
		return
	_detector_cooldown = DETECTOR_COOLDOWN
	_hud.ping_detector()
	_flash_hud("Detector ping - listen for the beeps")


func _update_detector_status() -> void:
	if _hud == null:
		return
	if _detector_cooldown > 0.0:
		_hud.set_detector_status("Detector: %.0f s" % ceilf(_detector_cooldown))
	else:
		_hud.set_detector_status("Detector: ready  [F]")


func _try_upgrade() -> void:
	if _state == null:
		return
	if _state.try_upgrade():
		var equipment := _state.get_current_equipment()
		_flash_hud("Upgraded to %s!  radius %.2f m" % [equipment.display_name, equipment.radius])
		return
	var next_index := _state.next_tier_index()
	if next_index < 0:
		_flash_hud("Already has the best shovel")
		return
	var tier := _state.tiers[next_index]
	var missing := []
	if _state.current_level < tier.level_required:
		missing.append("Lv %d (you are %d)" % [tier.level_required, _state.current_level])
	if _state.current_money < tier.money_required:
		missing.append("$%d (you have $%d)" % [int(tier.money_required), int(_state.current_money)])
	_flash_hud("Need %s" % " and ".join(missing))


func _update_prompt() -> void:
	if _hud == null or _state == null or _player_body == null:
		return
	var position := _player_body.global_position

	if _loot != null:
		var item := _loot.nearest_claimable(position, INTERACT_RANGE)
		if item != null:
			_hud.show_prompt("[E] Take %s  ($%d)" % [item.display_name, int(item.value)])
			return

	var yard := get_tree().get_first_node_in_group("junkyard") as Node3D
	if yard != null and position.distance_to(yard.global_position) <= Junkyard.SELL_RADIUS:
		if _state.carried_loot.is_empty():
			_hud.show_prompt("Junkyard - nothing to sell yet")
		else:
			_hud.show_prompt("[E] Sell %d item(s)  ($%d)" % [
				_state.carried_loot.size(), int(_state.carried_value())])
		return

	_hud.show_prompt("")


func _flash_hud(text: String) -> void:
	if _hud != null:
		_hud.flash(text)
