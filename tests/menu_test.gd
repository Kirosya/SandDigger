extends Node
## Main menu smoke test: buttons exist, Host/Join open the Phase 3 notice,
## Esc closes it, and the settings panel applies + persists values.
##
## Run headless: godot --headless --path . res://tests/menu_test.tscn

var _failures := 0


func _ready() -> void:
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame

	_check("play button", menu.get_node_or_null("Menu/Play") != null)
	_check("host button", menu.get_node_or_null("Menu/Host") != null)
	_check("join button", menu.get_node_or_null("Menu/Join") != null)
	_check("settings button", menu.get_node_or_null("Menu/Settings") != null)
	_check("quit button", menu.get_node_or_null("Menu/Quit") != null)
	_check("modal hidden at start", not menu.get_node("Modal").visible)
	_check("settings hidden at start", not menu.get_node("Settings").visible)
	_check("play button wired", not menu.get_node("Menu/Play").pressed.get_connections().is_empty())
	_check("game scene exists", ResourceLoader.exists("res://scenes/main.tscn"))

	menu.get_node("Menu/Host").pressed.emit()
	await get_tree().process_frame
	_check("host opens modal", menu.get_node("Modal").visible)
	_check("host modal title", menu.get_node("Modal/Panel/Margin/VBox/Title").text == "Host Game")
	_check("host modal mentions Phase 3", "Phase 3" in menu.get_node("Modal/Panel/Margin/VBox/Body").text)

	menu.get_node("Modal/Panel/Margin/VBox/Close").pressed.emit()
	_check("back closes modal", not menu.get_node("Modal").visible)

	menu.get_node("Menu/Join").pressed.emit()
	await get_tree().process_frame
	_check("join opens modal", menu.get_node("Modal").visible)
	_check("join modal title", menu.get_node("Modal/Panel/Margin/VBox/Title").text == "Join Game")

	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	Input.parse_input_event(cancel)
	await get_tree().process_frame
	_check("esc closes modal", not menu.get_node("Modal").visible)

	menu.get_node("Menu/Settings").pressed.emit()
	await get_tree().process_frame
	_check("settings opens", menu.get_node("Settings").visible)

	var slider: HSlider = menu.get_node("Settings/Panel/Margin/VBox/Sensitivity/Row/Slider")
	slider.value = 0.0044
	await get_tree().process_frame
	_check("sensitivity applied", is_equal_approx(GameSettings.mouse_sensitivity, 0.0044))

	var volume: HSlider = menu.get_node("Settings/Panel/Margin/VBox/Volume/Row/Slider")
	volume.value = 0.5
	await get_tree().process_frame
	_check("volume applied", is_equal_approx(GameSettings.master_volume, 0.5))

	menu.get_node("Settings/Panel/Margin/VBox/Back").pressed.emit()
	await get_tree().process_frame
	_check("back closes settings", not menu.get_node("Settings").visible)
	_check("settings file written", FileAccess.file_exists(GameSettings.PATH))

	# Leave the machine on defaults again.
	GameSettings.mouse_sensitivity = GameSettings.DEFAULT_SENSITIVITY
	GameSettings.master_volume = GameSettings.DEFAULT_VOLUME
	GameSettings.save_settings()

	if _failures == 0:
		print("MENU OK")
		get_tree().quit(0)
	else:
		print("MENU FAILED (%d)" % _failures)
		get_tree().quit(1)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
