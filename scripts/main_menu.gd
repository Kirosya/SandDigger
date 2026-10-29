extends Control
## Main menu: single-player entry point, Host/Join placeholders for Phase 3,
## and the settings panel (mouse look, master volume, fullscreen).

const GAME_SCENE := "res://scenes/main.tscn"

@onready var _modal: Control = $Modal
@onready var _modal_title: Label = $Modal/Panel/Margin/VBox/Title
@onready var _modal_body: Label = $Modal/Panel/Margin/VBox/Body
@onready var _settings: Control = $Settings
@onready var _sensitivity: HSlider = $Settings/Panel/Margin/VBox/Sensitivity/Row/Slider
@onready var _sensitivity_value: Label = $Settings/Panel/Margin/VBox/Sensitivity/Row/Value
@onready var _volume: HSlider = $Settings/Panel/Margin/VBox/Volume/Row/Slider
@onready var _volume_value: Label = $Settings/Panel/Margin/VBox/Volume/Row/Value
@onready var _fullscreen: CheckBox = $Settings/Panel/Margin/VBox/Fullscreen


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	$Menu/Play.pressed.connect(_on_play)
	$Menu/Host.pressed.connect(_on_host)
	$Menu/Join.pressed.connect(_on_join)
	$Menu/Settings.pressed.connect(_open_settings)
	$Menu/Quit.pressed.connect(_on_quit)

	$Modal/Panel/Margin/VBox/Close.pressed.connect(_close_modal)
	$Settings/Panel/Margin/VBox/Back.pressed.connect(_close_settings)

	_sensitivity.min_value = GameSettings.MIN_SENSITIVITY
	_sensitivity.max_value = GameSettings.MAX_SENSITIVITY
	_sensitivity.step = 0.0001
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.01

	_sensitivity.value_changed.connect(_on_sensitivity_changed)
	_volume.value_changed.connect(_on_volume_changed)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)

	_sync_widgets()
	_modal.visible = false
	_settings.visible = false
	$Menu/Play.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _settings.visible:
		_close_settings()
		get_viewport().set_input_as_handled()
	elif _modal.visible:
		_close_modal()
		get_viewport().set_input_as_handled()


func _on_play() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


## Host/Join are deliberately visible before the network layer exists: the menu
## is the entry point Phase 3 will plug into.
func _on_host() -> void:
	_show_modal("Host Game",
		"Multiplayer is not wired up yet.\n\nHosting a beach, the host-authoritative dig sync and late-join heightmap sync arrive in Phase 3 (ENet). The button is already in place for it.")


func _on_join() -> void:
	_show_modal("Join Game",
		"Multiplayer is not wired up yet.\n\nJoining a friend's beach over ENet arrives in Phase 3. The button is already in place for it.")


func _on_quit() -> void:
	get_tree().quit()


func _show_modal(title: String, body: String) -> void:
	_modal_title.text = title
	_modal_body.text = body
	_modal.visible = true
	$Modal/Panel/Margin/VBox/Close.grab_focus()


func _close_modal() -> void:
	_modal.visible = false
	$Menu/Play.grab_focus()


func _open_settings() -> void:
	_sync_widgets()
	_settings.visible = true
	$Settings/Panel/Margin/VBox/Back.grab_focus()


func _close_settings() -> void:
	GameSettings.save_settings()
	_settings.visible = false
	$Menu/Play.grab_focus()


func _on_sensitivity_changed(value: float) -> void:
	GameSettings.mouse_sensitivity = value
	_sync_widgets()


func _on_volume_changed(value: float) -> void:
	GameSettings.master_volume = value
	GameSettings.apply()
	_sync_widgets()


func _on_fullscreen_toggled(pressed: bool) -> void:
	GameSettings.fullscreen = pressed
	GameSettings.apply()


func _sync_widgets() -> void:
	_sensitivity.value = GameSettings.mouse_sensitivity
	_sensitivity_value.text = "%.2fx" % (GameSettings.mouse_sensitivity / GameSettings.DEFAULT_SENSITIVITY)
	_volume.value = GameSettings.master_volume
	_volume_value.text = "%d%%" % roundi(GameSettings.master_volume * 100.0)
	_fullscreen.button_pressed = GameSettings.fullscreen
