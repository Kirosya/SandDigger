extends Node3D
## Looks out to sea and photographs it, for judging the water colour and the
## horizon, then digs a deep hole at the shore and photographs that too - from
## the rim and from under the water. Run with a window (headless has no
## framebuffer to read back):
##   godot --path . res://tests/sea_shot.tscn

const SHOT := "res://proof_sea.png"
const PITCH := -8.0
const YAW := 0.0
## Centre of the pit and how many scoops it takes. It sits in the surf zone, so
## the tide can reach it and fill it up.
const PIT := Vector3(0.0, 0.0, -9.5)
const DIGS := 90


func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(0.9).timeout

	var player := get_tree().get_first_node_in_group("player") as FirstPersonPlayer
	var sea := get_tree().get_first_node_in_group("sea") as Sea
	var terrain := get_tree().get_first_node_in_group("sand_terrain") as SandTerrain
	if player == null or sea == null or terrain == null:
		print("SEA SHOT FAIL missing nodes")
		get_tree().quit(1)
		return
	sea._time = 0.0
	sea._update_tide(0.0)
	player.global_position = Vector3(0.0, 0.0, -6.0)
	player.rotation.y = deg_to_rad(YAW)
	player.head.rotation.x = deg_to_rad(PITCH)
	await get_tree().create_timer(0.6).timeout

	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(SHOT)
	print("SEA SHOT %s err=%d tide=%.2f shore_z=%.1f" % [
		SHOT, err, sea.level, sea.shoreline_z])

	# A hole dug in the surf at high tide: the sea has to fill it to its own
	# level, and the camera down in it has to look like it is under water.
	sea._time = Sea.TIDE_PERIOD * 0.5
	sea._update_tide(0.0)
	for i in DIGS:
		terrain.dig_at(PIT, 4.0, 2.0)
	sea._update_tide(0.0)
	print("SEA SHOT pit floor=%.2f depth=%.2f flooded=%s" % [
		terrain.get_height_at(PIT), sea.water_depth_at(PIT),
		str(sea.is_flooded_at(PIT))])
	player.global_position = Vector3(PIT.x, 0.2, PIT.z + 6.5)
	player.head.rotation.x = deg_to_rad(-22.0)
	await get_tree().create_timer(0.5).timeout
	_save("res://proof_pit.png")

	player.global_position = Vector3(PIT.x, terrain.get_height_at(PIT) + 0.1, PIT.z)
	player.head.rotation.x = deg_to_rad(30.0)
	await get_tree().create_timer(0.7).timeout
	print("SEA SHOT eye=%.2f level=%.2f veil=%.2f" % [
		player.head.global_position.y, sea.level, sea._veil_alpha])
	_save("res://proof_pit_under.png")
	get_tree().quit(0)


func _save(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("SEA SHOT %s err=%d" % [path, err])
