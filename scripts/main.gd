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

## True when this machine owns the beach it is walking on: single player, or the
## host of a session. Clients receive the world in their snapshot and never read
## or write the local beach file, so a guest cannot overwrite the host's island.
var _owns_world := false
## Set by digs and by loot changes; the saved beach is only rewritten when
## something actually changed.
var _world_dirty := false
var _world_save_timer := 0.0

## How often a changed beach is written while playing. Digging every shovelful
## would be wasteful, but waiting for a clean exit loses the session on a crash.
const WORLD_AUTOSAVE_SECONDS := 20.0


func _ready() -> void:
	_sun.rotation_degrees = Vector3(-55.0, 28.0, 0.0)
	_sun.light_energy = 0.75
	# Only the real game touches the saved profile. Tests instantiate main.tscn
	# inside their own scene, so current_scene is the test node there.
	_profile_enabled = get_tree().current_scene == self
	_owns_world = Net.is_host()
	_wire_loot_announcements()
	_wire_tide()
	_wire_dig_feedback()
	_wire_world_tracking()
	_load_world()
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
	state.treasure_found.connect(_on_treasure_save)
	state.quest_changed.connect(_on_quest_progress_save)
	state.quest_completed.connect(_on_quest_completed_save)


func _on_level_up_save(_level: int) -> void:
	_save_profile(0.0)


func _on_equipment_save(_equipment: EquipmentData) -> void:
	_save_profile(0.0)


func _on_detector_save(_detector_tier: int) -> void:
	_save_profile(0.0)


func _on_carried_save(_count: int, _value: float) -> void:
	_save_profile(0.0)


## A completed quest moves the chain index and pays money and XP, both of which
## belong in the profile: the story must not restart next session.
func _on_quest_completed_save(_index: int, _title: String, _money: float, _xp: float) -> void:
	_save_profile(0.0)


## Half-finished quests are saved too, so a pickup counted toward "3 antiques"
## survives a quit.
func _on_quest_progress_save(_index: int, _progress: int) -> void:
	_save_profile(0.0)


## A chest was opened: the find count and the payout belong in the profile, and
## the world no longer has a chest to point at.
func _on_treasure_save(_finds: int, _payout: float) -> void:
	_save_profile(0.0)
	_world_dirty = true
	_save_world()


func _save_profile(_money: float) -> void:
	if not _profile_enabled:
		return
	var state := Net.local_state()
	if state != null:
		Profile.save_state(state)


## Leaving the beach (to the menu or out of the game) flushes the profile and,
## on the world owner, the dug beach.
func _exit_tree() -> void:
	if not _profile_enabled:
		return
	var state := Net.local_state()
	if state != null:
		Profile.save_state(state)
	_save_world()


## --- Saved beach ----------------------------------------------------------
##
## The heightmap and the changed loot belong to the world owner. Restoring them
## happens before the first player spawns, so nobody ever sees the pristine beach
## for a frame and then watches it change.

func _wire_world_tracking() -> void:
	if _terrain != null:
		_terrain.dug.connect(_on_world_dug)
	if _loot != null:
		_loot.world_changed.connect(_on_loot_world_changed)


func _on_world_dug(_position: Vector3, _radius: float, _depth: float) -> void:
	_world_dirty = true


func _on_loot_world_changed() -> void:
	# Loot changes are saved at once rather than on the dig timer: the bag is
	# written the moment an item is picked up, so a crash in between must not
	# leave the same item both in the bag and back in the sand.
	_world_dirty = true
	_save_world()


func _process(delta: float) -> void:
	if not _world_dirty or not _profile_enabled or not _owns_world:
		return
	_world_save_timer += delta
	if _world_save_timer < WORLD_AUTOSAVE_SECONDS:
		return
	_save_world()


## Loads this machine's saved beach, if it owns one. A missing or damaged file
## simply leaves the freshly generated beach in place.
func _load_world() -> void:
	if not _profile_enabled or not _owns_world or _terrain == null:
		return
	var data := Profile.load_world()
	if data.is_empty():
		return
	var heights: PackedFloat32Array = data.get("heights", PackedFloat32Array())
	if heights.size() != _terrain.heights.size():
		return
	_terrain.set_heights(heights)
	var loot_data: Dictionary = data.get("loot", {})
	if _loot != null:
		_loot.restore_world(loot_data)
	print("[beach] restored %d heights, %d claimed items, %d tide items" % [
		heights.size(), loot_data.get("claimed", []).size(), loot_data.get("sea", []).size()])


## Writes the beach once the world owner has changed it. Clients never get here:
## their beach is a mirror of the host's and would only be a stale copy.
func _save_world() -> void:
	if not _profile_enabled or not _owns_world or _terrain == null:
		return
	_world_save_timer = 0.0
	var loot_data := _loot.export_snapshot() if _loot != null else {}
	# Only clear the dirty flag once the bytes are actually on disk, so a failed
	# write (a lock, a full disk) is retried on the next autosave tick.
	if Profile.save_world(_terrain.export_heights(), loot_data):
		_world_dirty = false


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
	loot.treasure_opened.connect(_on_treasure_opened_sfx)
	if hud != null:
		loot.loot_revealed.connect(_on_loot_revealed.bind(hud))
		loot.treasure_opened.connect(_on_treasure_opened.bind(hud))
		_wire_quests(hud)


## A finished quest is worth its own fanfare, and the sound belongs on the peer
## that actually completed it.
func _wire_quests(hud: Hud) -> void:
	var quests := get_tree().get_first_node_in_group("quests") as Quests
	if quests == null:
		return
	quests.quest_completed.connect(_on_quest_completed.bind(hud))


func _on_quest_completed(_index: int, title: String, money: float, xp: float,
		hud: Hud) -> void:
	# The HUD owns the banner, chime and payout line; no second fanfare here.
	hud.announce_quest(title, int(money), int(xp))


func _on_treasure_opened_sfx(item: Dictionary) -> void:
	Sfx.play_world("loot_reveal", item.get("position", Vector3.ZERO), 0.0, 4.0)


func _on_treasure_opened(item: Dictionary, hud: Hud) -> void:
	var state := Net.local_state()
	if state == null or int(item.get("owner", 0)) != state.player_id:
		return
	hud.announce_treasure(int(item.get("value", 0)), state.treasure_finds)


func _on_loot_revealed_sfx(item: Dictionary) -> void:
	var at: Vector3 = item.get("position", Vector3.ZERO)
	match str(item.get("kind", "trash")):
		"antique":
			Sfx.play_world("upgrade", at, 0.0, 2.0)
		"ring":
			Sfx.play_world("loot_reveal", at, 0.0, 2.0)
		_:
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
	match str(item.get("kind", "trash")):
		"antique":
			hud.announce_antique(str(item.get("name", "Antique")), int(item.get("value", 0)))
		"ring":
			hud.announce_ring(str(item.get("name", "Gold Ring")), int(item.get("value", 0)))
		_:
			hud.flash("Uncovered: %s  -  walk up and press E" % item.get("name", "loot"))

