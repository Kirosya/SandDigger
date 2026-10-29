extends Node3D
## Phase 2 / Step 1 visual proof.
##
## Boots the real main scene, aims the camera down at the sand, then fires real
## left-click InputEvents through the normal input path (player input -> DigController
## raycast -> SandTerrain.dig_at -> PlayerState XP). Saves a rendered screenshot and
## prints the XP before/after so the collapse and the XP gain can be verified.

const CLICKS := 6
const PITCH_DEGREES := -55.0
const SHOT_PATH := "res://dig_proof.png"

var _terrain: SandTerrain
var _state: PlayerState


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)

	await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout

	_terrain = get_tree().get_first_node_in_group("sand_terrain") as SandTerrain
	_state = get_tree().get_first_node_in_group("player_state") as PlayerState
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if _terrain == null or _state == null or player == null:
		print("PROOF FAIL missing terrain/state/player")
		get_tree().quit(1)
		return

	var head := player.get_node("Head") as Node3D
	head.rotation.x = deg_to_rad(PITCH_DEGREES)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().process_frame

	var aim := _aim_point()
	var xp_before: float = _state.current_xp
	var height_before: float = _terrain.get_height_at(aim)
	print("PROOF start xp=%.1f level=%d tier=%s aim=%s sand_height=%.4f" % [
		xp_before, _state.current_level, _state.get_current_equipment().display_name,
		str(aim), height_before])

	for i in CLICKS:
		_click()
		await get_tree().create_timer(0.5).timeout

	var xp_after: float = _state.current_xp
	var height_after: float = _terrain.get_height_at(aim)
	print("PROOF end xp=%.1f (gained %.1f) level=%d sand_height=%.4f pit_depth=%.4f dirty=%s" % [
		xp_after, xp_after - xp_before, _state.current_level, height_after,
		height_before - height_after, str(_terrain.last_dirty_rect)])

	await get_tree().process_frame
	await get_tree().process_frame
	_save_shot()
	print("PROOF DONE")
	get_tree().quit(0)


## Where the crosshair lands on the sand (same query DigController uses).
func _aim_point() -> Vector3:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var camera := player.get_node("Head/Camera3D") as Camera3D
	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 3.6)
	query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return origin + direction * 2.0
	return hit["position"]


## A real left-click press + release at the viewport centre.
func _click() -> void:
	var centre := get_viewport().get_visible_rect().size * 0.5
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = centre
	press.global_position = centre
	Input.parse_input_event(press)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = centre
	release.global_position = centre
	Input.parse_input_event(release)


func _save_shot() -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		print("PROOF FAIL no viewport image")
		return
	var err := image.save_png(SHOT_PATH)
	print("PROOF screenshot=%s err=%d size=%dx%d" % [
		SHOT_PATH, err, image.get_width(), image.get_height()])
