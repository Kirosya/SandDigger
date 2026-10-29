extends Node3D
## Scene bootstrap and the multiplayer session glue.
##
## The host spawns one player per peer and owns the world; clients ask for a
## spawn when their beach is loaded and receive a snapshot (heightmap + players +
## loot) so a late join always walks onto the same beach.
##
## Player movement, digging, loot and selling all live in their own scripts.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var _sun: DirectionalLight3D = $Sun
@onready var _players: Node3D = $Players
@onready var _terrain: SandTerrain = $SandTerrain
@onready var _loot: LootManager = $LootManager

## False in the headless tests, which instantiate this scene inside their own
## one; true when the beach is the running game, which is when progress is saved.
var _profile_enabled := false


func _ready() -> void:
	_sun.rotation_degrees = Vector3(-55.0, 28.0, 0.0)
	_sun.light_energy = 0.75
	# Only the real game touches the saved profile. Tests instantiate main.tscn
	# inside their own scene, so current_scene is the test node there.
	_profile_enabled = get_tree().current_scene == self
	_wire_loot_announcements()
	_wire_tide()
	_wire_dig_feedback()
	_start_session()


## --- Session --------------------------------------------------------------

func _start_session() -> void:
	if not Net.is_online():
		# Single player: the beach belongs to this machine.
		_spawn_player(1, Net.spawn_point_for(1))
		return

	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.disconnected.connect(_on_disconnected)
	if Net.is_host():
		_spawn_player(1, Net.spawn_point_for(1))
	else:
		# The host spawns us; announce that our scene is ready for the snapshot.
		rpc_id(1, "_notify_ready")


## A client's beach is loaded: give it a player and the current world.
@rpc("any_peer", "call_remote", "reliable")
func _notify_ready() -> void:
	if not Net.is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	if peer == 0 or peer == 1:
		return
	var spawn := Net.spawn_point_for(peer)
	_spawn_player(peer, spawn)
	# Everyone already on the beach learns about the newcomer.
	for id in Net.peers:
		if id != 1 and id != peer:
			rpc_id(id, "_remote_spawn", peer, spawn)
	_send_snapshot(peer)


## The client has the heightmap and every player node now. Only from this point
## on may it receive transform streams (an unreliable packet for a node that
## does not exist yet is just an error in the console).
@rpc("any_peer", "call_remote", "reliable")
func _snapshot_applied() -> void:
	if not Net.is_host():
		return
	Net.mark_ready(multiplayer.get_remote_sender_id())


func _send_snapshot(peer: int) -> void:
	var spawns := {}
	for player in _players.get_children():
		if player is FirstPersonPlayer:
			spawns[player.player_id] = player.global_position
	var loot_data := _loot.export_snapshot() if _loot != null else {}
	rpc_id(peer, "_receive_snapshot", _terrain.export_heights(), spawns, loot_data)


@rpc("authority", "call_remote", "reliable")
func _receive_snapshot(heights: PackedFloat32Array, spawns: Dictionary, loot_data: Dictionary) -> void:
	print("[net] snapshot on %d: %d heights, players %s" % [
		multiplayer.get_unique_id(), heights.size(), str(spawns.keys())])
	_terrain.set_heights(heights)
	for id in spawns:
		_spawn_player(int(id), spawns[id])
	if _loot != null:
		_loot.apply_snapshot(loot_data)
	# Tell the host we are ready for transform streams now.
	rpc_id(1, "_snapshot_applied")


@rpc("authority", "call_remote", "reliable")
func _remote_spawn(peer_id: int, spawn: Vector3) -> void:
	_spawn_player(peer_id, spawn)


@rpc("authority", "call_remote", "reliable")
func _remote_despawn(peer_id: int) -> void:
	var player := _players.get_node_or_null(str(peer_id))
	if player != null:
		player.queue_free()


func _spawn_player(peer_id: int, spawn: Vector3) -> FirstPersonPlayer:
	var existing := _players.get_node_or_null(str(peer_id)) as FirstPersonPlayer
	if existing != null:
		return existing
	var player := PLAYER_SCENE.instantiate() as FirstPersonPlayer
	player.name = str(peer_id)
	player.player_id = peer_id
	player.spawn_point = spawn
	player.set_multiplayer_authority(peer_id)
	_players.add_child(player)
	# Every machine restores its own beachcomber, host or client alike.
	if _profile_enabled and player.is_local_player():
		_wire_profile(player)
	return player


## Loads this machine's saved XP/money/gear into the player it controls, and
## saves again whenever something worth keeping changes.
func _wire_profile(player: FirstPersonPlayer) -> void:
	var state := player.get_node_or_null("PlayerState") as PlayerState
	if state == null:
		return
	Profile.load_into(state)
	state.money_changed.connect(_save_profile)
	state.leveled_up.connect(_on_level_up_save)
	state.equipment_changed.connect(_on_equipment_save)
	state.detector_changed.connect(_on_detector_save)
	state.carried_changed.connect(_on_carried_save)


func _on_level_up_save(_level: int) -> void:
	_save_profile(0.0)


func _on_equipment_save(_equipment: EquipmentData) -> void:
	_save_profile(0.0)


func _on_detector_save(_has_detector: bool) -> void:
	_save_profile(0.0)


func _on_carried_save(_count: int, _value: float) -> void:
	_save_profile(0.0)


func _save_profile(_money: float) -> void:
	if not _profile_enabled:
		return
	var state := Net.local_state()
	if state != null:
		Profile.save_state(state)


## Leaving the beach (to the menu or out of the game) flushes the profile.
func _exit_tree() -> void:
	if not _profile_enabled:
		return
	var state := Net.local_state()
	if state != null:
		Profile.save_state(state)


func _on_peer_joined(_peer_id: int) -> void:
	# The player itself is created when the peer reports its scene is ready.
	pass


func _on_peer_left(peer_id: int) -> void:
	Net.unmark_ready(peer_id)
	if not Net.is_host():
		return
	_remote_despawn(peer_id)
	for id in Net.peers:
		if id != 1:
			rpc_id(id, "_remote_despawn", peer_id)


func _on_disconnected(reason: String) -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	if hud != null:
		hud.flash(reason)
	# Only the beach itself owns the session transition; a test that instanced
	# the beach inside another scene must not be torn down.
	if get_tree().current_scene != self:
		return
	await get_tree().create_timer(1.2).timeout
	get_tree().change_scene_to_file(MENU_SCENE)


## --- World dressing -------------------------------------------------------

func _wire_tide() -> void:
	var sea := get_tree().get_first_node_in_group("sea") as Sea
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	if sea != null and hud != null:
		sea.tide_turned.connect(_on_tide_turned.bind(hud))
	# Surf, once per beach. It loops, so nothing else has to touch it. Skipped in
	# the headless tests, which tear the tree down mid-loop.
	if _profile_enabled:
		Sfx.start_ambience()


func _on_tide_turned(rising: bool, hud: Hud) -> void:
	if rising:
		hud.flash("The tide is coming in - fresh trash is washing ashore")
	else:
		hud.flash("The tide is going out")


func _wire_loot_announcements() -> void:
	var loot := get_tree().get_first_node_in_group("loot_manager") as LootManager
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	if loot == null:
		return
	# Sound and sparkle happen on every peer, because every peer already gets
	# the same `loot_revealed` broadcast. No extra RPC.
	loot.loot_revealed.connect(_on_loot_revealed_sfx)
	if hud != null:
		loot.loot_revealed.connect(_on_loot_revealed.bind(hud))


func _on_loot_revealed_sfx(item: Dictionary) -> void:
	var at: Vector3 = item.get("position", Vector3.ZERO)
	if item.get("kind", "") == "ring":
		Sfx.play_world("loot_reveal", at, 0.0, 2.0)
	else:
		Sfx.play_world("loot_reveal", at, 0.08, -2.0)


## A dig only produces feedback where the sand actually changed: this listens to
## the terrain, so a client hears its own dig when the host's carve comes back.
func _wire_dig_feedback() -> void:
	if _terrain == null:
		return
	_terrain.dug.connect(_on_dug)


func _on_dug(world_position: Vector3, radius: float, _depth: float) -> void:
	Fx.dig(world_position, radius)


func _on_loot_revealed(item: Dictionary, hud: Hud) -> void:
	if item.get("kind", "") == "ring":
		hud.announce_ring(str(item.get("name", "Gold Ring")), int(item.get("value", 0)))
		return
	hud.flash("Uncovered: %s  -  walk up and press E" % item.get("name", "loot"))

