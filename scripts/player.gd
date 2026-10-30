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

## How much the held tool grows per tier (Teaspoon -> Dune Excavator).
const TOOL_SCALES := [1.0, 1.3, 1.65, 2.1, 2.5, 2.9, 3.35]
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

## Seconds between footstep sounds: quicker when sprinting.
const STEP_INTERVAL_WALK := 0.52
const STEP_INTERVAL_SPRINT := 0.38

## The player id this body belongs to (the host is 1, clients get their peer id).
var player_id: int = 1

## Where the owner's latest streamed transform wants this body to be.
var _net_target_position := Vector3.ZERO
var _net_target_yaw := 0.0
var _net_target_pitch := 0.0
var _has_net_target := false
var _net_stream_timer := 0.0

## 15 Hz is enough for a beach stroll and keeps the packet rate low.
const NET_STREAM_INTERVAL := 1.0 / 15.0

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

## Below this Y the player is considered lost (off the beach, out to sea).
const FALL_LIMIT := -8.5
var _third_person := false
var _held_item: Dictionary = {}
var _item_visual: MeshInstance3D
var _item_visual_id := -1
var _step_timer := 0.0
## This body's own progression, used to tell which hotbar slot is selected (and
## therefore whether the tool, a loot item or nothing at all is in hand).
var _state: PlayerState


func _ready() -> void:
	add_to_group("player")
	global_position = spawn_point
	mouse_sensitivity = GameSettings.mouse_sensitivity

	_state = get_node_or_null("PlayerState") as PlayerState
	if _state != null:
		_state.player_id = player_id

	if not is_local_player():
		_setup_remote()
		return

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_layers_recursive(spoon_pivot, VIEWMODEL_LAYER)
	_set_layers_recursive(detector_pivot, VIEWMODEL_LAYER)
	_set_layers_recursive(item_pivot, VIEWMODEL_LAYER)
	detector_pivot.visible = false
	item_pivot.visible = false
	if third_camera != null:
		third_camera.current = false

	if _state != null:
		_state.equipment_changed.connect(apply_equipment)
		_state.inventory_changed.connect(_on_inventory_changed)
		_state.leveled_up.connect(_on_leveled_up)
		apply_equipment(_state.get_current_equipment())
	_update_hand_visuals()


func _on_leveled_up(level: int) -> void:
	Sfx.play_ui("levelup", 0.0, -2.0)
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	if hud != null:
		hud.flash("Level %d!  Better shovels are closer now" % level)


## True on the machine that owns this body (always true in single player).
func is_local_player() -> bool:
	if not Net.is_online():
		return true
	return multiplayer.get_unique_id() == get_multiplayer_authority()


## Someone else's body: no input, no camera, no floating first-person hands, and
## it follows the transform streamed by its owner instead of simulating physics.
func _setup_remote() -> void:
	set_physics_process(false)
	set_process_unhandled_input(false)
	set_process(true)
	camera.current = false
	if third_camera != null:
		third_camera.current = false
	spoon_pivot.visible = false
	detector_pivot.visible = false
	item_pivot.visible = false
	if rig != null:
		# The owner hides their own body on layer 2 so their camera never sees it;
		# everybody else must see it, so move it to the default layer.
		_set_layers_recursive(rig, 1)
		rig.set_viewmodel_visible(false)


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


## Swaps which tool the first-person hand holds and moves the hotbar cursor to
## that tool's slot, so the highlight always matches what is in hand.
func set_tool_mode(mode: int) -> void:
	var next := TOOL_DETECTOR if mode == TOOL_DETECTOR else TOOL_SHOVEL
	var changed := next != tool_mode
	tool_mode = next
	if _state != null:
		var slot := PlayerState.SLOT_DETECTOR if next == TOOL_DETECTOR else PlayerState.SLOT_SHOVEL
		if _state.selected_slot != slot:
			_state.select_slot(slot)
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


## Only one thing is ever visible in the hand: the held loot, else the tool of the
## selected tool slot, else nothing at all (an empty bag slot or a sold item).
## The viewmodel hands follow whatever is held, and only the shovel needs both.
func _update_hand_visuals() -> void:
	if spoon_pivot == null:
		return
	var holding := not _held_item.is_empty()
	var tool_in_hand := _state == null or _state.selected_slot < PlayerState.FIRST_BAG_SLOT
	var shovel := not holding and tool_in_hand and tool_mode == TOOL_SHOVEL
	var detector := not holding and tool_in_hand and tool_mode == TOOL_DETECTOR
	spoon_pivot.visible = shovel
	detector_pivot.visible = detector
	item_pivot.visible = holding
	if holding:
		_build_item_visual()
		# A piece of junk is picked up with one hand.
		rig.set_tool_pivot(item_pivot, 0.0, 0.07, false)
	elif detector:
		# The detector is a one-handed wand; the spare arm would clutch air.
		rig.set_tool_pivot(detector_pivot, 0.02, 0.09, false)
	elif shovel:
		# A shovel has a long handle and is swung with both hands.
		rig.set_tool_pivot(spoon_pivot, CharacterRig.RIGHT_GRIP_Z, CharacterRig.LEFT_GRIP_Z, true)
	# Nothing in hand (empty bag slot, or the item was just sold): the viewmodel
	# hands would be gripping thin air, so they are hidden too.
	rig.set_viewmodel_visible(holding or shovel or detector)


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
	if not is_local_player():
		_interpolate_remote(delta)
		return

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
	if not is_local_player():
		return
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

	# Footsteps: only for the body this machine owns, and only while grounded.
	var sprinting := Input.is_action_pressed("sprint")
	if is_on_floor() and direction.length_squared() > 0.01:
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = STEP_INTERVAL_SPRINT if sprinting else STEP_INTERVAL_WALK
			Sfx.play_world("step_sand", global_position + Vector3(0.0, -0.1, 0.0), 0.16, -12.0)
	else:
		_step_timer = minf(_step_timer, 0.12)

	# Safety net: fell off the beach or waded out past the sea floor. The limit
	# sits below the deepest diggable pit (SandTerrain.MAX_DEPTH), or standing at
	# the bottom of a deep hole would teleport the digger home.
	if global_position.y < FALL_LIMIT:
		respawn()

	_net_stream_timer -= delta
	if _net_stream_timer <= 0.0:
		_net_stream_timer = NET_STREAM_INTERVAL
		if Net.is_online():
			_send_net_state()


## Streams this body to everyone who can see it. A client only talks to the
## host; the host relays to the other clients, so nobody gets RPCs for a node
## that has not been spawned on their machine yet.
func _send_net_state() -> void:
	if Net.is_host():
		for id in Net.ready_peers:
			rpc_id(id, "_net_state", global_position, rotation.y, head.rotation.x)
	else:
		rpc_id(1, "_net_state", global_position, rotation.y, head.rotation.x)


## The owner streams where it is and where it looks; everyone else smooths
## toward that instead of running a second physics body.
@rpc("any_peer", "unreliable_ordered", "call_remote")
func _net_state(position: Vector3, yaw: float, pitch: float) -> void:
	if is_local_player():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	_apply_net_state(position, yaw, pitch)
	# Host relay: with three or four players the others need to see this too.
	if Net.is_host() and sender != 1:
		for id in Net.ready_peers:
			if id != sender:
				rpc_id(id, "_net_state_relay", player_id, position, yaw, pitch)


@rpc("any_peer", "unreliable_ordered", "call_remote")
func _net_state_relay(relayed_id: int, position: Vector3, yaw: float, pitch: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if relayed_id != player_id:
		return
	_apply_net_state(position, yaw, pitch)


func _apply_net_state(position: Vector3, yaw: float, pitch: float) -> void:
	_net_target_position = position
	_net_target_yaw = yaw
	_net_target_pitch = pitch
	_has_net_target = true


func _interpolate_remote(delta: float) -> void:
	if not _has_net_target:
		return
	var weight := minf(1.0, delta * 14.0)
	global_position = global_position.lerp(_net_target_position, weight)
	rotation.y = lerp_angle(rotation.y, _net_target_yaw, weight)
	head.rotation.x = lerp_angle(head.rotation.x, _net_target_pitch, weight)


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
