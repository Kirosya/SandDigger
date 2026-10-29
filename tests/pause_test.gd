extends Node
## Pause overlay test: Esc pauses the game and shows the menu, Esc again resumes.
## Run headless: godot --headless --path . res://tests/pause_test.tscn

var _failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().physics_frame

	var pause: CanvasLayer = game.get_node("PauseMenu")
	var root: Control = pause.get_node("Root")
	_check("overlay hidden at start", not root.visible)
	_check("tree running at start", not get_tree().paused)

	_send_cancel()
	await get_tree().process_frame
	_check("esc opens overlay", root.visible)
	_check("esc pauses tree", get_tree().paused)

	_send_cancel()
	await get_tree().process_frame
	_check("esc closes overlay", not root.visible)
	_check("esc resumes tree", not get_tree().paused)

	get_tree().paused = false
	if _failures == 0:
		print("PAUSE OK")
		get_tree().quit(0)
	else:
		print("PAUSE FAILED (%d)" % _failures)
		get_tree().quit(1)


func _send_cancel() -> void:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)
	# Input events are buffered; flush so the overlay sees them this frame.
	Input.flush_buffered_events()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
