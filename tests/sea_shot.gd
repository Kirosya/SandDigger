extends Node3D
## Looks out to sea and photographs it, for judging the water colour, the tide
## range and the flooding, then digs a deep hole at the shore and photographs
## that too - while it fills, full, and from under the water. Run with a window
## (headless has no framebuffer to read back):
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

	# Low water: the sea should be well out, leaving a wide wet beach.
	sea._time = 0.0
	sea._update_tide(0.0)
	player.global_position = Vector3(0.0, 0.0, -6.0)
	player.rotation.y = deg_to_rad(YAW)
	player.head.rotation.x = deg_to_rad(PITCH)
	await get_tree().create_timer(0.6).timeout
	print("SEA SHOT low tide=%.2f shore_z=%.1f" % [sea.level, sea.shoreline_z])
	_save(SHOT)

	# High water from the same spot, to show how far the sea came in.
	sea._time = Sea.TIDE_PERIOD * 0.5
	sea._update_tide(0.0)
	await get_tree().create_timer(0.5).timeout
	print("SEA SHOT high tide=%.2f shore_z=%.1f" % [sea.level, sea.shoreline_z])
	_save("res://proof_tide.png")

	# A hole dug in the surf at high tide. Water has to pour in over the rim and
	# fill it from the bottom up, so grab a frame while it is still climbing, then
	# one when it has settled.
	for i in DIGS:
		terrain.dig_at(PIT, 4.0, 2.0)
	sea._refresh_water()
	player.global_position = Vector3(PIT.x, 0.2, PIT.z + 6.5)
	player.head.rotation.x = deg_to_rad(-22.0)
	sea.settle_water(0.7)
	await get_tree().create_timer(0.2).timeout
	print("SEA SHOT filling floor=%.2f depth=%.2f flooded=%s" % [
		terrain.get_height_at(PIT), sea.water_depth_at(PIT),
		str(sea.is_flooded_at(PIT))])
	_save("res://proof_pit_filling.png")

	sea.settle_water(60.0)
	print("SEA SHOT pit floor=%.2f depth=%.2f flooded=%s" % [
		terrain.get_height_at(PIT), sea.water_depth_at(PIT),
		str(sea.is_flooded_at(PIT))])
	await get_tree().create_timer(0.3).timeout
	_save("res://proof_pit.png")

	player.global_position = Vector3(PIT.x, terrain.get_height_at(PIT) + 0.1, PIT.z)
	player.head.rotation.x = deg_to_rad(30.0)
	await get_tree().create_timer(0.7).timeout
	print("SEA SHOT eye=%.2f level=%.2f veil=%.2f" % [
		player.head.global_position.y, sea.level, sea._veil_alpha])
	_save("res://proof_pit_under.png")

	# The tide goes out and cuts the hole off. What was up on the walls has to run
	# down to the bottom, and the sand then slowly drinks it away.
	sea._time = 0.0
	sea._update_tide(0.0)
	sea.settle_water(16.0)
	player.global_position = Vector3(PIT.x, 0.2, PIT.z + 6.5)
	player.head.rotation.x = deg_to_rad(-22.0)
	await get_tree().create_timer(0.4).timeout
	print("SEA SHOT cut off tide=%.2f depth=%.2f" % [sea.level, sea.water_depth_at(PIT)])
	_save("res://proof_pit_cut_off.png")
	get_tree().quit(0)


func _save(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("SEA SHOT %s err=%d" % [path, err])
