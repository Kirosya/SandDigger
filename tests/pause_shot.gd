extends Node
## Renders the in-game pause overlay once so its layout can be reviewed.

func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(0.8).timeout

	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()

	await get_tree().create_timer(0.3).timeout
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png("res://pause_proof.png")
	print("PAUSE SHOT err=%d size=%dx%d" % [err, image.get_width(), image.get_height()])
	get_tree().quit(0)
