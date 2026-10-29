extends Node
## Sound + feedback test.
##
## Three things are checked:
##   1. every id in Sfx.SOUNDS points at a real, imported stream;
##   2. a dig on the real beach produces both a sand puff and a dig sound, and
##      the sound is chosen by the cut radius (the tier);
##   3. the automatic button click and the looping surf behave.
##
## Sound output itself cannot be heard headless, so the assertions are about the
## stream that was handed to a player and the node that was spawned.

const MAIN_SCENE := "res://scenes/main.tscn"

var _failures := 0


func _ready() -> void:
	_check_streams()
	await _check_wiring()
	_check_buttons()
	_check_ambience()

	print("SFX %s" % ("OK" if _failures == 0 else "FAILED (%d)" % _failures))
	# Let the longest one-shot (0.38 s dig) finish so nothing is left playing.
	await get_tree().create_timer(0.7).timeout
	get_tree().quit(0 if _failures == 0 else 1)


## Every advertised sound must load; a typo in the table would otherwise show up
## as a silent game instead of an error.
func _check_streams() -> void:
	for id in Sfx.SOUNDS:
		var path: String = Sfx.SOUNDS[id]
		_check("file exists: %s" % id, FileAccess.file_exists(path))
		var stream := load(path) as AudioStream
		_check("stream loads: %s" % id, stream != null)
		_check("sfx knows: %s" % id, Sfx.is_available(id))
	_check("unknown id is refused", not Sfx.is_available("no_such_sound"))
	# The surf is the one looping stream; the import must not have dropped that.
	var waves := load(Sfx.SOUNDS["waves"]) as AudioStreamWAV
	_check("waves loop", waves != null and waves.loop_mode == AudioStreamWAV.LOOP_FORWARD)


## Digging in the real beach: one carve -> one puff + one tier-matched sound.
func _check_wiring() -> void:
	var game: Node = load(MAIN_SCENE).instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var terrain := get_tree().get_first_node_in_group("sand_terrain") as SandTerrain
	_check("terrain exists", terrain != null)
	if terrain == null:
		return

	var puffs_before := _puff_count()
	var volume := terrain.host_dig(Vector3(0.0, 0.0, 4.0), 1, 1)
	await get_tree().process_frame

	_check("dig carved sand", volume > 0.0)
	_check("dig spawned a sand puff", _puff_count() > puffs_before)
	var puff := _first_puff()
	if puff != null:
		_check("puff has particles", puff.amount > 0)
		_check("puff starts on the ground", puff.global_position.y > 0.0)
	_delete_puffs()

	# The tier decides the sound: radius 0.15 -> soft, 0.70 -> massive.
	var soft := Sfx.play_dig(Vector3.ZERO, 0.15)
	var massive := Sfx.play_dig(Vector3.ZERO, 0.70)
	_check("teaspoon uses the soft sound",
		soft != null and soft.stream != null
		and soft.stream.resource_path.ends_with("dig_soft.wav"))
	_check("earth shovel uses the massive sound",
		massive != null and massive.stream != null
		and massive.stream.resource_path.ends_with("dig_massive.wav"))

	# A world sound is placed where it happened, so it pans with the camera.
	Sfx.play_world("coin", Vector3(3.0, 0.0, -2.0))
	await get_tree().process_frame
	_check("world sound is spatialised", _any_world_player_at(Vector3(3.0, 0.0, -2.0)))

	game.queue_free()
	await get_tree().process_frame


## Buttons get the click automatically, including ones built at runtime.
func _check_buttons() -> void:
	var button := Button.new()
	button.name = "ProbeButton"
	add_child(button)
	_check("button auto-wired for the click",
		not button.pressed.get_connections().is_empty())
	button.pressed.emit()
	var playing := false
	for player in Sfx.get_children():
		if player is AudioStreamPlayer and player.playing \
			and player.stream != null \
			and player.stream.resource_path.ends_with("ui_click.wav"):
			playing = true
	_check("button press plays the click", playing)
	button.queue_free()


func _check_ambience() -> void:
	Sfx.stop_ambience()
	_check("ambience stopped", not _ambience_playing())
	Sfx.start_ambience()
	_check("ambience starts", _ambience_playing())
	Sfx.stop_ambience()
	_check("ambience stops again", not _ambience_playing())


## --- helpers -------------------------------------------------------------

func _ambience_playing() -> bool:
	var node := Sfx.get_node_or_null("Ambience") as AudioStreamPlayer
	return node != null and node.playing


func _puffs() -> Array[Node]:
	var found: Array[Node] = []
	_collect_puffs(get_tree().root, found)
	return found


func _collect_puffs(node: Node, found: Array[Node]) -> void:
	for child in node.get_children():
		if child is SandPuff:
			found.append(child)
		_collect_puffs(child, found)


func _puff_count() -> int:
	return _puffs().size()


func _first_puff() -> SandPuff:
	var list := _puffs()
	return list[0] as SandPuff if not list.is_empty() else null


func _delete_puffs() -> void:
	for puff in _puffs():
		puff.queue_free()


func _any_world_player_at(position: Vector3) -> bool:
	for player in Sfx.get_children():
		if player is AudioStreamPlayer3D and player.playing \
			and player.global_position.distance_to(position) < 0.01:
			return true
	return false


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
