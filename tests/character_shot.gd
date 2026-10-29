extends Node
## Character proof shots: viewmodel hands on the spoon, the body when looking
## down, and a third-person look at the whole beachcomber.

func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(0.9).timeout

	var player := get_tree().get_first_node_in_group("player") as FirstPersonPlayer
	var state := get_tree().get_first_node_in_group("player_state") as PlayerState

	# 1) First person, starting teaspoon.
	player.head.rotation_degrees.x = -12.0
	await get_tree().create_timer(0.2).timeout
	_save("res://character_fp.png")

	# 2) Look down: the body should be visible.
	player.head.rotation_degrees.x = -62.0
	await get_tree().create_timer(0.2).timeout
	_save("res://character_lookdown.png")

	# 3) Big shovel, normal view.
	state.equipment_tier_index = 3
	state.equipment_changed.emit(state.get_current_equipment())
	player.head.rotation_degrees.x = -16.0
	await get_tree().create_timer(0.8).timeout
	_save("res://character_shovel.png")

	# 4) Mid dig-swing: the hands must stay glued to the handle.
	player.play_dig_swing()
	await get_tree().create_timer(0.05).timeout
	await RenderingServer.frame_post_draw
	_save("res://character_swing.png")
	await get_tree().create_timer(0.4).timeout

	# 5) Third person: a camera outside the player looking at the rig.
	var cam := Camera3D.new()
	game.add_child(cam)
	var feet := player.global_position
	cam.global_position = feet + Vector3(1.9, 1.85, 2.4)
	cam.look_at(feet + Vector3(0.0, 1.05, 0.0))
	cam.fov = 55.0
	cam.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_save("res://character_third.png")

	get_tree().quit(0)


func _save(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("CHAR SHOT %s err=%d" % [path, err])
