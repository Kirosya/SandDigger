extends Node
## Multiplayer proof shots. Run the host WINDOWED and the client headless:
##   godot --path . res://tests/mp_shot.tscn --quit-after 3000 -- --host
##   godot --headless --path . res://tests/mp_shot.tscn --quit-after 3000 -- --client
##
## The host takes two pictures: the joined player standing on the beach, and
## both players around the hole the host just dug (shared sand).

const PORT := 8912
const SCENE := "res://scenes/main.tscn"
const CLIENT_SPOT := Vector3(-1.7, 0.4, 5.4)
const HOST_SPOT := Vector3(2.7, 0.4, 7.6)
const HOLE := Vector3(0.4, 0.0, 5.2)

var _role := ""
var _main: Node3D
var _terrain: SandTerrain
var _player: FirstPersonPlayer


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			_role = "host"
		elif arg == "--client":
			_role = "client"
	if _role.is_empty():
		print("SHOT FAIL: pass --host or --client after --")
		get_tree().quit(1)
		return

	if _role == "host":
		await _run_host()
	else:
		await _run_client()
	get_tree().quit(0)


func _run_host() -> void:
	Net.host_game(PORT)
	await _load_beach()
	_player = await _wait_for_local_player(15.0)
	if _player == null:
		print("SHOT FAIL: no local player")
		return
	_player.global_position = HOST_SPOT

	var client := await _wait_for_remote_player(20.0)
	if client == null:
		print("SHOT FAIL: no client player")
		return

	# 1. Two players on the beach, the host looking at the newcomer.
	await get_tree().create_timer(1.5).timeout
	_face(_player, CLIENT_SPOT, -0.10)
	await get_tree().create_timer(0.6).timeout
	_save("res://proof_multiplayer.png")

	# 2. The host digs a hole between them; both beaches end up with it.
	_terrain.submit_dig(HOLE, 1, 3)
	await get_tree().create_timer(0.6).timeout
	_face(_player, HOLE + Vector3(0.0, 0.0, 0.9), -0.34)
	await get_tree().create_timer(0.5).timeout
	_save("res://proof_multiplayer_dig.png")

	# Keep the session alive until the client has had its own time to look.
	await get_tree().create_timer(6.0).timeout


func _run_client() -> void:
	Net.join_game("127.0.0.1", PORT)
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline and Net.local_id == 0:
		await get_tree().process_frame
	if Net.local_id == 0:
		print("SHOT FAIL: could not connect")
		return

	await _load_beach()
	_player = await _wait_for_local_player(15.0)
	if _player == null:
		print("SHOT FAIL: no local player")
		return
	_player.global_position = CLIENT_SPOT
	_face(_player, HOST_SPOT, -0.05)
	print("SHOT client ready as player %d" % _player.player_id)
	await get_tree().create_timer(20.0).timeout


func _load_beach() -> void:
	_main = load(SCENE).instantiate() as Node3D
	_main.name = "Main"
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_terrain = _main.get_node_or_null("SandTerrain") as SandTerrain


func _wait_for_local_player(timeout: float) -> FirstPersonPlayer:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var player := Net.local_player()
		if player != null:
			return player
		await get_tree().process_frame
	return null


func _wait_for_remote_player(timeout: float) -> FirstPersonPlayer:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		for node in get_tree().get_nodes_in_group("player"):
			if node is FirstPersonPlayer and not node.is_local_player():
				return node
		await get_tree().process_frame
	return null


## Turns the body (yaw) and the head (pitch) toward a world point.
func _face(player: FirstPersonPlayer, target: Vector3, pitch: float) -> void:
	var dir := target - player.global_position
	player.rotation.y = atan2(-dir.x, -dir.z)
	var head := player.get_node_or_null("Head") as Node3D
	if head != null:
		head.rotation.x = pitch


func _save(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("SHOT %s err=%d" % [path, err])
