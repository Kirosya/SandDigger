class_name FirstPersonPlayer
extends CharacterBody3D
## First-person beachcomber controller.
##
## Mouse look on the body (yaw) and head (pitch), WASD movement, sprint, jump.
## The arrow keys also turn the camera, so the game is playable without a mouse.
## Digging itself lives in DigController so this script stays movement-only.

@export var walk_speed := 4.0
@export var sprint_speed := 6.8
@export var jump_velocity := 5.0
@export var mouse_sensitivity := 0.0022
@export var arrow_look_speed := 2.0
@export var spawn_point := Vector3(0.0, 0.2, 6.0)

## How much the held tool grows per tier (Teaspoon -> Earth Shovel).
const TOOL_SCALES := [1.0, 1.3, 1.65, 2.1]
## Resting pose of the tool in the camera; the scene transform matches this.
const TOOL_BASE_POSITION := Vector3(0.26, -0.25, -0.46)
## Local z of the handle end nearest the camera (the "hand" end).
const TOOL_HANDLE_NEAR_Z := 0.27

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var spoon_pivot: Node3D = $Head/Camera3D/SpoonPivot

var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


func _ready() -> void:
	add_to_group("player")
	global_position = spawn_point
	mouse_sensitivity = GameSettings.mouse_sensitivity
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var state := get_node_or_null("PlayerState") as PlayerState
	if state != null:
		state.equipment_changed.connect(apply_equipment)
		apply_equipment(state.get_current_equipment())


## Grows the held tool with the tier. The hand end of the handle stays put and
## the head is pushed further away, so a better shovel reads as longer instead
## of as a giant spoon pressed against the camera.
func apply_equipment(equipment: EquipmentData) -> void:
	if spoon_pivot == null:
		return
	var tier := clampi(equipment.tier_index, 0, TOOL_SCALES.size() - 1)
	var scale_factor: float = TOOL_SCALES[tier]
	var target_position := TOOL_BASE_POSITION
	target_position.z -= TOOL_HANDLE_NEAR_Z * (scale_factor - 1.0)
	target_position.y -= 0.04 * (scale_factor - 1.0)
	target_position.x += 0.02 * (scale_factor - 1.0)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(spoon_pivot, "scale", Vector3.ONE * scale_factor, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(spoon_pivot, "position", target_position, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _unhandled_input(event: InputEvent) -> void:
	# Esc is owned by the pause menu; this script only recaptures the mouse.
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		head.rotation.x = clampf(
			head.rotation.x - motion.relative.y * mouse_sensitivity,
			deg_to_rad(-89.0), deg_to_rad(89.0))


func _process(delta: float) -> void:
	# Arrow keys: left/right turn the body, up/down tilt the head.
	var turn := Input.get_axis("cam_left", "cam_right")
	var tilt := Input.get_axis("cam_down", "cam_up")
	if absf(turn) > 0.01:
		rotate_y(-turn * arrow_look_speed * delta)
	if absf(tilt) > 0.01:
		head.rotation.x = clampf(
			head.rotation.x + tilt * arrow_look_speed * delta,
			deg_to_rad(-89.0), deg_to_rad(89.0))


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed

	if direction.length_squared() > 0.001:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 8.0 * delta)

	move_and_slide()

	# Safety net: fell off the sand or into a very deep pit.
	if global_position.y < -8.0:
		respawn()


func respawn() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO


## Small spoon swing so digging has tactile feedback.
func play_dig_swing() -> void:
	if spoon_pivot == null:
		return
	spoon_pivot.rotation = Vector3.ZERO
	var tween := create_tween()
	tween.tween_property(spoon_pivot, "rotation:x", deg_to_rad(-42.0), 0.06)
	tween.tween_property(spoon_pivot, "rotation:x", deg_to_rad(-6.0), 0.18)
