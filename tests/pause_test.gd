extends Node
## Pause overlay test: Esc pauses the game and shows the menu, Esc again resumes,
## and the in-game settings panel applies + persists while the tree is paused.
## Run headless: godot --headless --path . res://tests/pause_test.tscn

var _failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var volume_before := GameSettings.master_volume

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

	# --- Settings from inside the game -------------------------------------
	# Same panel as the main menu, and it has to keep working while the beach is
	# paused behind it.
	var settings: SettingsPanel = pause.get_node("Settings")
	var settings_button: Button = root.get_node("Panel/Margin/VBox/Settings")
	_check("pause menu has a settings button", settings_button != null)
	_check("in-game settings start hidden", not settings.visible)

	_send_cancel()
	await get_tree().process_frame
	settings_button.pressed.emit()
	await get_tree().process_frame
	_check("settings open over the paused beach", settings.visible and get_tree().paused)

	var volume: HSlider = settings.get_node("Panel/Margin/VBox/Volume/Row/Slider")
	volume.value = 0.4
	await get_tree().process_frame
	_check("in-game volume slider is live",
		is_equal_approx(GameSettings.master_volume, 0.4))

	var sensitivity: HSlider = settings.get_node("Panel/Margin/VBox/Sensitivity/Row/Slider")
	sensitivity.value = 0.0035
	await get_tree().process_frame
	_check("in-game sensitivity slider is live",
		is_equal_approx(GameSettings.mouse_sensitivity, 0.0035))

	# Esc must close only the settings panel, not the whole pause menu.
	_send_cancel()
	await get_tree().process_frame
	_check("esc closes settings first", not settings.visible)
	_check("the pause menu is still up", root.visible and get_tree().paused)

	# The Back button is the other way out.
	settings_button.pressed.emit()
	await get_tree().process_frame
	settings.get_node("Panel/Margin/VBox/Back").pressed.emit()
	await get_tree().process_frame
	_check("back closes settings too", not settings.visible and root.visible)
	_check("settings are written to disk", FileAccess.file_exists(GameSettings.PATH))

	_send_cancel()
	await get_tree().process_frame
	_check("resume still works after settings", not root.visible and not get_tree().paused)

	# Leave the machine as it was found.
	GameSettings.master_volume = volume_before
	GameSettings.mouse_sensitivity = GameSettings.DEFAULT_SENSITIVITY
	GameSettings.save_settings()

	get_tree().paused = false
	if _failures == 0:
		print("PAUSE OK")
		await get_tree().create_timer(0.2).timeout
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
