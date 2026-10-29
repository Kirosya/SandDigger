extends Node
## Sound effect player for the whole game.
##
## Every sound is a short .wav synthesised by tools/gen_sfx.gd. There is no
## "play sound on every peer" RPC: the world signals that already reach every
## machine (the terrain's `dug`, the loot broadcasts) are the trigger, so each
## peer hears exactly the digs and finds that happened on its own beach.
##
## Players are pooled instead of created per sound, so digging while sprinting
## cannot allocate an AudioStreamPlayer3D per frame.

## id -> res:// path. Keep this in sync with tools/gen_sfx.gd.
const SOUNDS := {
	"dig_soft": "res://assets/audio/dig_soft.wav",
	"dig_sand": "res://assets/audio/dig_sand.wav",
	"dig_deep": "res://assets/audio/dig_deep.wav",
	"dig_massive": "res://assets/audio/dig_massive.wav",
	"loot_reveal": "res://assets/audio/loot_reveal.wav",
	"pickup": "res://assets/audio/pickup.wav",
	"coin": "res://assets/audio/coin.wav",
	"levelup": "res://assets/audio/levelup.wav",
	"upgrade": "res://assets/audio/upgrade.wav",
	"ui_click": "res://assets/audio/ui_click.wav",
	"ui_open": "res://assets/audio/ui_open.wav",
	"denied": "res://assets/audio/denied.wav",
	"step_sand": "res://assets/audio/step_sand.wav",
	"waves": "res://assets/audio/waves.wav",
}

const WORLD_POOL := 12
const UI_POOL := 5
## Holder for 3D sounds: one node at the origin, players are positioned in it.
const WORLD_MAX_DISTANCE := 45.0

var _streams: Dictionary = {}
var _world: Array[AudioStreamPlayer3D] = []
var _ui: Array[AudioStreamPlayer] = []
var _next_world := 0
var _next_ui := 0
var _ambience: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for id in SOUNDS:
		var path: String = SOUNDS[id]
		var stream := load(path)
		if stream == null:
			push_warning("[sfx] missing sound: %s" % path)
			continue
		_streams[id] = stream
	# The surf loops forever; the .wav import drops loop settings, so set them
	# on the loaded stream once here.
	var waves := _streams.get("waves") as AudioStreamWAV
	if waves != null:
		waves.loop_mode = AudioStreamWAV.LOOP_FORWARD
		waves.loop_begin = 0
		waves.loop_end = int(waves.get_length() * waves.mix_rate)

	for i in WORLD_POOL:
		var player := AudioStreamPlayer3D.new()
		player.name = "World%d" % i
		player.max_distance = WORLD_MAX_DISTANCE
		player.unit_size = 6.0
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		player.bus = "Master"
		add_child(player)
		_world.append(player)

	for i in UI_POOL:
		var player := AudioStreamPlayer.new()
		player.name = "Ui%d" % i
		player.bus = "Master"
		add_child(player)
		_ui.append(player)

	_ambience = AudioStreamPlayer.new()
	_ambience.name = "Ambience"
	_ambience.stream = _streams.get("waves")
	_ambience.volume_db = -20.0
	_ambience.bus = "Master"
	add_child(_ambience)

	# Every button in the game clicks, including ones built at runtime (the
	# lobby list, shop rows), without each screen remembering to ask for it.
	get_tree().node_added.connect(_on_node_added)


## Auto-wires the click sound onto any button that enters the tree.
func _on_node_added(node: Node) -> void:
	var button := node as BaseButton
	if button == null:
		return
	if not button.pressed.is_connected(_on_button_pressed):
		button.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	play_ui("ui_click", 0.05, -8.0)


## Plays a one-shot at a world position. A small random pitch keeps repeated
## digs from sounding like a machine gun.
func play_world(id: String, position: Vector3, pitch_jitter := 0.10, volume_db := 0.0) -> AudioStreamPlayer3D:
	var stream := _streams.get(id) as AudioStream
	if stream == null:
		return null
	var player := _world[_next_world]
	_next_world = (_next_world + 1) % _world.size()
	player.stream = stream
	player.global_position = position
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.volume_db = volume_db
	player.play()
	return player


## Plays a one-shot with no spatialisation (menus, UI feedback).
func play_ui(id: String, pitch_jitter := 0.04, volume_db := 0.0) -> AudioStreamPlayer:
	var stream := _streams.get(id) as AudioStream
	if stream == null:
		return null
	var player := _ui[_next_ui]
	_next_ui = (_next_ui + 1) % _ui.size()
	player.stream = stream
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.volume_db = volume_db
	player.play()
	return player


## Picks the dig sound from the cut radius, which is what tells the tiers
## apart (0.15 / 0.30 / 0.45 / 0.70 m). No protocol change needed.
func play_dig(position: Vector3, radius: float) -> AudioStreamPlayer3D:
	var id := "dig_soft"
	var pitch := 0.08
	if radius >= 0.60:
		id = "dig_massive"
	elif radius >= 0.38:
		id = "dig_deep"
	elif radius >= 0.22:
		id = "dig_sand"
	else:
		# The teaspoon is tiny; lift it slightly so it still reads.
		pitch = 0.14
	return play_world(id, position, pitch)


func start_ambience() -> void:
	if _ambience == null or _ambience.playing:
		return
	_ambience.play()


## Stops every voice and drops the streams when the game closes, so no playback
## or AudioStreamWAV is still alive while Godot tears the tree down. The players
## are freed here as well: a stopped playback can otherwise outlive the tree for
## one mix, which Godot reports as a leaked resource at exit.
func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	for player in _world:
		player.stop()
		player.stream = null
		player.free()
	for player in _ui:
		player.stop()
		player.stream = null
		player.free()
	if _ambience != null:
		_ambience.stop()
		_ambience.stream = null
		_ambience.free()
	_world.clear()
	_ui.clear()
	_ambience = null
	_streams.clear()


func stop_ambience() -> void:
	if _ambience != null:
		_ambience.stop()


func is_available(id: String) -> bool:
	return _streams.has(id)
