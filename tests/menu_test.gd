extends Node
## Main menu smoke test: buttons exist, Host opens an ENet session, Join opens
## the address dialog, and the settings panel applies + persists values.
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
	_check("steam host button", menu.get_node_or_null("Menu/SteamRow/SteamHost") != null)
	_check("steam join button", menu.get_node_or_null("Menu/SteamRow/SteamJoin") != null)
	_check("steam host wired",
		not menu.get_node("Menu/SteamRow/SteamHost").pressed.get_connections().is_empty())
	_check("steam join wired",
		not menu.get_node("Menu/SteamRow/SteamJoin").pressed.get_connections().is_empty())
	_check("quit button", menu.get_node_or_null("Menu/Quit") != null)
	_check("modal hidden at start", not menu.get_node("Modal").visible)
	_check("settings hidden at start", not menu.get_node("Settings").visible)
	_check("play button wired", not menu.get_node("Menu/Play").pressed.get_connections().is_empty())
	_check("game scene exists", ResourceLoader.exists("res://scenes/main.tscn"))

	menu.get_node("Menu/Host").pressed.emit()
	await get_tree().process_frame
	_check("host starts a session", Net.is_online() and Net.hosting)
	Net.leave()
	await get_tree().process_frame
	_check("leaving clears the session", not Net.is_online())

	menu.get_node("Menu/Join").pressed.emit()
	await get_tree().process_frame
	var dialog := menu.get_node_or_null("JoinDialog") as AcceptDialog
	_check("join opens the address dialog", dialog != null and dialog.visible)
	if dialog != null:
		dialog.hide()
	await get_tree().process_frame
	_check("join dialog closes", dialog == null or not dialog.visible)

	# Steam gate: when Steam cannot start, "Steam Host" must explain the reason
	# instead of starting a bogus session or crashing. When Steam is signed in
	# the test does not press it, so no real lobby is created.
	if not Net.steam_init():
		menu.get_node("Menu/SteamRow/SteamHost").pressed.emit()
		await get_tree().process_frame
		_check("steam gate shows a modal", menu.get_node("Modal").visible)
		_check("steam gate starts no session", not Net.is_online())
		menu.get_node("Modal/Panel/Margin/VBox/Close").pressed.emit()
		await get_tree().process_frame
		_check("steam modal closes", not menu.get_node("Modal").visible)

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
		# Let the last UI click finish; quitting in its first millisecond leaves
		# a playback alive while the tree is torn down.
		await get_tree().create_timer(0.2).timeout
		get_tree().quit(0)
	else:
		print("MENU FAILED (%d)" % _failures)
		get_tree().quit(1)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
