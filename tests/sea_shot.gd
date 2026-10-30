extends Node3D
## Looks out to sea and photographs it, for judging the water colour and the
## horizon. Run with a window:
##   godot --path . res://tests/sea_shot.tscn

const SHOT := "res://proof_sea.png"
const PITCH := -8.0
const YAW := 0.0


func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(0.9).timeout

	var player := get_tree().get_first_node_in_group("player") as FirstPersonPlayer
	var sea := get_tree().get_first_node_in_group("sea") as Sea
	if player == null or sea == null:
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
	get_tree().quit(0)
