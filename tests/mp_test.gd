extends Node
## Two-process ENet test: one instance hosts, the other joins over localhost.
##
## Run the host first, then the client:
##   godot --headless --path . res://tests/mp_test.tscn --quit-after 3000 -- --host
##   godot --headless --path . res://tests/mp_test.tscn --quit-after 3000 -- --client
##
## What it proves:
##   - a client joins, gets its own player and sees the host's player
##   - late join: sand the host dug BEFORE the client connected is already dug
##     on the client (full heightmap snapshot)
##   - live: the host's dig is broadcast and carves the client's sand
##   - the client's dig request is accepted by the host and carves both beaches

const PORT := 8911
const SCENE := "res://scenes/main.tscn"
## Three flat sand points on grid vertices, within reach of the spawn and far
## enough apart (0.5 m cells) not to share vertices.
const POINT_A := Vector3(2.0, 0.0, 4.0)
const POINT_B := Vector3(-2.0, 0.0, 4.0)
const POINT_C := Vector3(0.0, 0.0, 3.5)
## Sand Shovel: a 0.10 m bite, so a single dig is easy to measure.
const TIER := 1
## The inland beach starts at exactly 0.0, so anything below this is a dig.
const DUG := -0.01

var _role := ""
var _failures := 0
var _main: Node3D
var _terrain: SandTerrain


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			_role = "host"
		elif arg == "--client":
			_role = "client"
	if _role.is_empty():
		print("MP FAILED: pass --host or --client after --")
		get_tree().quit(1)
		return

	if _role == "host":
		await _run_host()
	else:
		await _run_client()

	if _failures == 0:
		print("MP %s OK" % _role.to_upper())
		get_tree().quit(0)
	else:
		print("MP %s FAILED (%d)" % [_role.to_upper(), _failures])
		get_tree().quit(1)


## --- Host -----------------------------------------------------------------

func _run_host() -> void:
	var err := Net.host_game(PORT)
	if err != OK:
		print("MP FAILED: could not host: %s" % error_string(err))
		_failures += 1
		return
	await _load_beach()
	_check("beach loaded", _main != null and _terrain != null)
	if _terrain == null:
		return

	# Dig before anyone joins: the client must inherit this through the snapshot.
	_terrain.submit_dig(POINT_A, 1, TIER)
	_check("pre-join dig carved the sand", _terrain.get_height_at(POINT_A) < DUG)

	var client_id := await _wait_for_client_player(15.0)
	if client_id == 0:
		print("MP FAILED: no client joined in time")
		_failures += 1
		return
	_check("client player spawned", Net.player_by_id(client_id) != null)

	# Live dig after the client is on the beach: must reach it as a broadcast.
	await get_tree().create_timer(1.5).timeout
	_terrain.submit_dig(POINT_C, 1, TIER)

	# The client digs POINT_B about 1.5 s after its player appeared.
	await get_tree().create_timer(8.0).timeout
	_check("host dig carved the sand", _terrain.get_height_at(POINT_C) < DUG)
	_check("client dig reached the host", _terrain.get_height_at(POINT_B) < DUG)


## --- Client ---------------------------------------------------------------

func _run_client() -> void:
	var err := Net.join_game("127.0.0.1", PORT)
	if err != OK:
		print("MP FAILED: could not start the client: %s" % error_string(err))
		_failures += 1
		return
	if not await _wait_until(func() -> bool: return Net.local_id != 0, 15.0):
		print("MP FAILED: could not connect to the host")
		_failures += 1
		return

	await _load_beach()
	_check("beach loaded", _main != null and _terrain != null)
	if _terrain == null:
		return

	var player := await _wait_for_local_player(15.0)
	if player == null:
		print("MP FAILED: no local player was spawned")
		_failures += 1
		return
	_check("local player spawned", true)
	_check("local player has a client id", player.player_id != 1)
	_check("host player is visible", Net.player_by_id(1) != null)
	_check("client is not the authority", not _terrain.is_authority())
	# The snapshot arrives with the player spawn, so this is already dug.
	_check("late join inherited the dug sand", _terrain.get_height_at(POINT_A) < DUG)

	# Ask the host for a dig. The host validates it and broadcasts the result.
	await get_tree().create_timer(1.5).timeout
	_check("still connected before digging", Net.is_online() and not Net.is_host())
	_terrain.submit_dig(POINT_B, player.player_id, TIER)

	await get_tree().create_timer(3.0).timeout
	_check("host dig reached the client", _terrain.get_height_at(POINT_C) < DUG)
	_check("own dig was accepted and applied", _terrain.get_height_at(POINT_B) < DUG)


## --- Helpers --------------------------------------------------------------

func _load_beach() -> void:
	# Instantiate the beach under the test node instead of replacing the current
	# scene: the test node itself must survive to assert anything. Both peers run
	# this same test scene, so the node path (/root/MpTest/Main) matches and RPCs
	# line up.
	_main = load(SCENE).instantiate() as Node3D
	_main.name = "Main"
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_terrain = _main.get_node_or_null("SandTerrain") as SandTerrain


func _wait_for_client_player(timeout: float) -> int:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		for id in Net.peers:
			if id != 1 and Net.player_by_id(id) != null:
				return id
		await get_tree().process_frame
	return 0


func _wait_for_local_player(timeout: float) -> FirstPersonPlayer:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var player := Net.local_player()
		if player != null:
			return player
		await get_tree().process_frame
	return null


func _wait_until(condition: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
