class_name FirstPersonPlayer
extends CharacterBody3D
## First-person beachcomber controller.
##
## Mouse look on the body (yaw) and head (pitch), WASD movement, sprint, jump.
## The arrow keys also turn the camera, so the game is playable without a mouse.
## Digging itself lives in DigController so this script stays movement-only.
##
## This script also owns the hand: the shovel, the metal detector and any loot
## item held for selling are swapped in and out of the first-person view here.
## Holding R pulls the camera back to a third-person view of the character.

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

## Render layer for everything that only the first-person camera may see: the
## viewmodel hands, the tools and the item held for selling. The third-person
## camera skips this layer, so no floating arms hang in the air behind the body.
const VIEWMODEL_LAYER := 4

const TOOL_SHOVEL := 0
const TOOL_DETECTOR := 1

## Emitted when Q swaps the hand between the shovel and the detector.
signal tool_mode_changed(mode: int)

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var spoon_pivot: Node3D = $Head/Camera3D/SpoonPivot
@onready var detector_pivot: Node3D = $Head/Camera3D/DetectorPivot
@onready var item_pivot: Node3D = $Head/Camera3D/ItemPivot
@onready var third_camera: Camera3D = $ThirdPersonCamera
@onready var rig: CharacterRig = $Body

## Which tool is in hand. DigController flips this with Q.
var tool_mode: int = TOOL_SHOVEL

var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
var _third_person := false
var _held_item: Dictionary = {}
var _item_visual: MeshInstance3D
var _item_visual_id := -1


func _ready() -> void:
	add_to_group("player")
	global_position = spawn_point
	mouse_sensitivity = GameSettings.mouse_sensitivity
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_layers_recursive(spoon_pivot, VIEWMODEL_LAYER)
	_set_layers_recursive(detector_pivot, VIEWMODEL_LAYER)
	_set_layers_recursive(item_pivot, VIEWMODEL_LAYER)
	detector_pivot.visible = false
	item_pivot.visible = false
	if third_camera != null:
		third_camera.current = false

	var state := get_node_or_null("PlayerState") as PlayerState
	if state != null:
		state.equipment_changed.connect(apply_equipment)
		state.inventory_changed.connect(_on_inventory_changed)
		apply_equipment(state.get_current_equipment())
	_update_hand_visuals()


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


## Swaps which tool the first-person hand holds.
func set_tool_mode(mode: int) -> void:
	var next := TOOL_DETECTOR if mode == TOOL_DETECTOR else TOOL_SHOVEL
	var changed := next != tool_mode
	tool_mode = next
	_update_hand_visuals()
	if changed:
		tool_mode_changed.emit(tool_mode)


func toggle_tool() -> void:
	set_tool_mode(TOOL_DETECTOR if tool_mode == TOOL_SHOVEL else TOOL_SHOVEL)


func is_holding_loot() -> bool:
	return not _held_item.is_empty()


func _on_inventory_changed(slots: Array[Dictionary], held_slot: int) -> void:
	if held_slot >= 0 and held_slot < slots.size():
		_held_item = slots[held_slot]
	else:
		_held_item = {}
	_update_hand_visuals()


## Only one thing is ever visible in the hand: the held loot, else the detector,
## else the shovel. The viewmodel hands follow whatever is held.
func _update_hand_visuals() -> void:
	if spoon_pivot == null:
		return
	var holding := not _held_item.is_empty()
	spoon_pivot.visible = not holding and tool_mode == TOOL_SHOVEL
	detector_pivot.visible = not holding and tool_mode == TOOL_DETECTOR
	item_pivot.visible = holding
	if holding:
		_build_item_visual()
		rig.set_tool_pivot(item_pivot, 0.0, 0.07)
	elif tool_mode == TOOL_DETECTOR:
		rig.set_tool_pivot(detector_pivot, 0.02, 0.09)
	else:
		rig.set_tool_pivot(spoon_pivot, CharacterRig.RIGHT_GRIP_Z, CharacterRig.LEFT_GRIP_Z)


## Rebuilds the little junk model in the hand only when the held item changes.
func _build_item_visual() -> void:
	var item_id := int(_held_item.get("id", -1))
	if item_id == _item_visual_id and _item_visual != null:
		return
	_item_visual_id = item_id
	if _item_visual != null:
		_item_visual.queue_free()
		_item_visual = null
	var loot := get_tree().get_first_node_in_group("loot_manager") as LootManager
	if loot == null:
		return
	_item_visual = loot.make_piece_for(_held_item)
	_item_visual.name = "HeldItem"
	_item_visual.scale = Vector3(0.5, 0.5, 0.5)
	_item_visual.rotation_degrees = Vector3(-12.0, 24.0, 8.0)
	item_pivot.add_child(_item_visual)
	_set_layers_recursive(_item_visual, VIEWMODEL_LAYER)


func _set_layers_recursive(node: Node, layer: int) -> void:
	if node == null:
		return
	for child in node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).layers = layer
		_set_layers_recursive(child, layer)


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

	# Hold R to step outside the body and look at the character.
	var want_third := Input.is_action_pressed("third_person")
	if want_third != _third_person:
		_third_person = want_third
		if third_camera != null:
			third_camera.current = _third_person
			camera.current = not _third_person


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

	# Safety net: fell off the beach or waded out past the sea floor.
	if global_position.y < -3.5:
		respawn()


func respawn() -> void:
	global_position = spawn_point
	velocity = Vector3.ZERO


## Small spoon swing so digging has tactile feedback.
func play_dig_swing() -> void:
	if spoon_pivot == null or not spoon_pivot.visible:
		return
	spoon_pivot.rotation = Vector3.ZERO
	var tween := create_tween()
	tween.tween_property(spoon_pivot, "rotation:x", deg_to_rad(-42.0), 0.06)
	tween.tween_property(spoon_pivot, "rotation:x", deg_to_rad(-6.0), 0.18)
