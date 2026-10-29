extends Control
## Main menu: single-player entry point, ENet host/join, and the settings panel
## (mouse look, master volume, fullscreen).

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

var _join_dialog: AcceptDialog
var _join_address: LineEdit
var _join_status: Label


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
	Net.leave()
	_enter_game()


func _on_host() -> void:
	var err := Net.host_game()
	if err != OK:
		_show_modal("Host Game", "Could not open a beach on port %d.\n\n%s" % [
			Net.DEFAULT_PORT, error_string(err)])
		return
	_enter_game()


func _on_join() -> void:
	if _join_dialog == null:
		_build_join_dialog()
	_join_status.text = "Address of the host (they must press Host Game first):"
	_join_address.text = Net.DEFAULT_ADDRESS
	_join_dialog.popup_centered(Vector2i(420, 160))
	_join_address.grab_focus()
	_join_address.select_all()


## Small modal with a single address field. Built in code so the menu scene
## stays one Control with no extra nodes to keep in sync.
func _build_join_dialog() -> void:
	_join_dialog = AcceptDialog.new()
	_join_dialog.name = "JoinDialog"
	_join_dialog.title = "Join Game"
	_join_dialog.ok_button_text = "Join"
	_join_dialog.dialog_hide_on_ok = false
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override("separation", 8)
	_join_status = Label.new()
	_join_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_join_status)
	_join_address = LineEdit.new()
	_join_address.placeholder_text = "127.0.0.1"
	box.add_child(_join_address)
	_join_dialog.add_child(box)
	_join_dialog.register_text_enter(_join_address)
	_join_dialog.confirmed.connect(_try_join)
	add_child(_join_dialog)
	Net.join_failed.connect(_on_join_failed)
	Net.session_started.connect(_on_session_started)


func _try_join() -> void:
	var address := _join_address.text.strip_edges()
	if address.is_empty():
		address = Net.DEFAULT_ADDRESS
	_join_status.text = "Connecting to %s:%d ..." % [address, Net.DEFAULT_PORT]
	var err := Net.join_game(address)
	if err != OK:
		_join_status.text = "Could not start the connection: %s" % error_string(err)


func _on_session_started(hosting: bool) -> void:
	if hosting:
		return
	if _join_dialog != null:
		_join_dialog.hide()
	_enter_game()


## Switches to the beach. Skipped when the menu is being exercised inside
## another scene (the headless menu test), so the test is not torn down.
func _enter_game() -> void:
	if not is_inside_tree() or get_tree().current_scene != self:
		return
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_join_failed(reason: String) -> void:
	if _join_dialog != null and _join_dialog.visible:
		_join_status.text = reason
	else:
		_show_modal("Join Game", reason)


func _on_quit() -> void:
	Net.leave()
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
