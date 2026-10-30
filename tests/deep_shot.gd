extends Node3D
## Visual proof for the deep-sand rework.
##
## 1. Digs a deep pit with the Trench Spade exactly like a player would (the same
##    `dig_at` the shovel calls) until it reaches the chest depth band, then
##    photographs the crater from its rim. The walls caved in on the way, so the
##    failure mode this proves is "narrow shaft collapses", not "clean tube".
## 2. Photographs the eight-row market with a detector upgrade on offer.
##
## Run with a window (not --headless):
##   godot --path . res://tests/deep_shot.tscn

const TIER := 4
const PIT_SHOT := "res://proof_deep_pit.png"
const SHOP_SHOT := "res://proof_shop_deep.png"
const SPOT := Vector3(2.0, 0.0, 6.0)
const TARGET_DEPTH := 4.5
const MAX_DIGS := 260


func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(0.9).timeout

	var state := get_tree().get_first_node_in_group("player_state") as PlayerState
	var terrain := get_tree().get_first_node_in_group("sand_terrain") as SandTerrain
	var player := get_tree().get_first_node_in_group("player") as FirstPersonPlayer
	var shop := get_tree().get_first_node_in_group("shop_ui") as ShopUI
	if state == null or terrain == null or player == null or shop == null:
		print("DEEP SHOT FAIL missing nodes")
		get_tree().quit(1)
		return

	state.equipment_tier_index = TIER
	state.equipment_changed.emit(state.get_current_equipment())
	state.detector_tier = 2
	state.detector_changed.emit(2)
	await get_tree().create_timer(0.6).timeout

	var digs := 0
	while terrain.get_height_at(SPOT) > -TARGET_DEPTH and digs < MAX_DIGS:
		terrain.dig_at(SPOT, 0.9, 0.3)
		digs += 1
	var depth := terrain.get_height_at(SPOT)
	var width := 0.0
	while terrain.get_height_at(SPOT + Vector3(width + 0.5, 0.0, 0.0)) < -0.3:
		width += 0.5
		if width > 12.0:
			break
	print("DEEP SHOT tier=%s digs=%d depth=%.2f half_width=%.1f" % [
		state.get_current_equipment().display_name, digs, depth, width])

	player.global_position = SPOT + Vector3(0.0, 0.2, 3.6)
	player.head.rotation_degrees.x = -34.0
	# Let the dig dust settle so the shot shows the sand, not the particles.
	await get_tree().create_timer(2.5).timeout
	_save(PIT_SHOT)

	state.add_money(4000.0)
	shop.open(state, player)
	await get_tree().create_timer(0.5).timeout
	_save(SHOP_SHOT)

	print("DEEP SHOT DONE")
	get_tree().quit(0)


func _save(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		print("DEEP SHOT FAIL no viewport image")
		return
	var err := image.save_png(path)
	print("DEEP SHOT %s err=%d size=%dx%d" % [
		path, err, image.get_width(), image.get_height()])
