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
var _lobby_dialog: AcceptDialog
var _lobby_list: VBoxContainer
var _lobby_status: Label


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	$Menu/Play.pressed.connect(_on_play)
	$Menu/Host.pressed.connect(_on_host)
	$Menu/Join.pressed.connect(_on_join)
	$Menu/SteamRow/SteamHost.pressed.connect(_on_steam_host)
	$Menu/SteamRow/SteamJoin.pressed.connect(_on_steam_join)
	$Menu/Settings.pressed.connect(_open_settings)
	$Menu/Quit.pressed.connect(_on_quit)

	$Modal/Panel/Margin/VBox/Close.pressed.connect(_close_modal)
	$Settings/Panel/Margin/VBox/Back.pressed.connect(_close_settings)

	Net.session_started.connect(_on_session_started)
	Net.join_failed.connect(_on_join_failed)
	Net.steam_failed.connect(_on_steam_failed)
	Net.steam_invite.connect(_on_steam_invite)

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


func _try_join() -> void:
	var address := _join_address.text.strip_edges()
	if address.is_empty():
		address = Net.DEFAULT_ADDRESS
	_join_status.text = "Connecting to %s:%d ..." % [address, Net.DEFAULT_PORT]
	var err := Net.join_game(address)
	if err != OK:
		_join_status.text = "Could not start the connection: %s" % error_string(err)


func _on_session_started(hosting: bool) -> void:
	# ENet hosting navigates straight from _on_host; Steam lobbies are
	# asynchronous, so this is the only place that path can navigate from.
	if hosting and not Net.is_steam():
		return
	if _join_dialog != null:
		_join_dialog.hide()
	if _lobby_dialog != null:
		_lobby_dialog.hide()
	_enter_game()


## Switches to the beach. Skipped when the menu is being exercised inside
## another scene (the headless menu test), so the test is not torn down.
func _enter_game() -> void:
	if not is_inside_tree() or get_tree().current_scene != self:
		return
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_join_failed(reason: String) -> void:
	if _lobby_dialog != null and _lobby_dialog.visible:
		_lobby_status.text = reason
	elif _join_dialog != null and _join_dialog.visible:
		_join_status.text = reason
	else:
		_show_modal("Join Game", reason)


## --- Steam ---------------------------------------------------------------

func _on_steam_host() -> void:
	if not _steam_ready_or_explain():
		return
	var err := Net.host_steam(false)
	if err != OK:
		_show_modal("Steam Host", Net.steam_status)
		return
	_show_modal("Steam Host", "Creating a Steam lobby...\n\nFriends can join from the Steam overlay once the beach is up.")


func _on_steam_join() -> void:
	if not _steam_ready_or_explain():
		return
	if _lobby_dialog == null:
		_build_lobby_dialog()
	_lobby_dialog.popup_centered(Vector2i(470, 430))
	_refresh_lobbies()


## Shared gate: the extension must be installed and the Steam client signed in.
func _steam_ready_or_explain() -> bool:
	if not Net.steam_supported():
		_show_modal("Steam",
			("GodotSteam is not installed in this build.\n\n" +
			"Copy the GodotSteam GDExtension into addons/godotsteam, reopen the " +
			"project so the extension is registered, then try again."))
		return false
	if not Net.steam_init():
		_show_modal("Steam",
			("Steam is not ready.\n\n%s\n\nStart the Steam client and sign in. " +
			"This build runs on Spacewar (app id %d), so the Steam client has to " +
			"be logged in before hosting or joining.") % [Net.steam_status, Net.STEAM_APP_ID])
		return false
	return true


func _build_lobby_dialog() -> void:
	_lobby_dialog = AcceptDialog.new()
	_lobby_dialog.name = "LobbyDialog"
	_lobby_dialog.title = "Steam Lobbies"
	_lobby_dialog.ok_button_text = "Refresh"
	_lobby_dialog.dialog_hide_on_ok = false
	_lobby_dialog.add_cancel_button("Close")
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 320)
	box.add_theme_constant_override("separation", 10)
	_lobby_status = Label.new()
	_lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_lobby_status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 240)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lobby_list = VBoxContainer.new()
	_lobby_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lobby_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_lobby_list)
	box.add_child(scroll)
	_lobby_dialog.add_child(box)
	_lobby_dialog.confirmed.connect(_refresh_lobbies)
	add_child(_lobby_dialog)
	Net.steam_lobbies_listed.connect(_on_lobbies_listed)


func _refresh_lobbies() -> void:
	_lobby_status.text = "Looking for open beaches..."
	_clear_children(_lobby_list)
	Net.request_steam_lobbies()


func _on_lobbies_listed(lobbies: Array) -> void:
	_clear_children(_lobby_list)
	if lobbies.is_empty():
		_lobby_status.text = ("No open beaches found. Host one, then invite a friend " +
			"from the Steam overlay (Shift+Tab).")
		return
	_lobby_status.text = "%d beach(es) found - pick one:" % lobbies.size()
	for entry in lobbies:
		var button := Button.new()
		button.text = "%s    %d/%d players" % [
			str(entry.get("name", "Beach")),
			int(entry.get("players", 1)),
			int(entry.get("max", Net.MAX_PLAYERS))]
		button.custom_minimum_size = Vector2(0, 42)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_join_lobby.bind(int(entry.get("id", 0))))
		_lobby_list.add_child(button)


func _join_lobby(id: int) -> void:
	_lobby_status.text = "Joining the beach..."
	var err := Net.join_steam_lobby(id)
	if err != OK:
		_lobby_status.text = "Could not join: %s" % Net.steam_status


func _on_steam_failed(reason: String) -> void:
	if _lobby_dialog != null and _lobby_dialog.visible:
		_lobby_status.text = reason
	else:
		_show_modal("Steam", reason)


## A friend pressed "Invite to game" in the overlay while we sit in the menu.
func _on_steam_invite(id: int) -> void:
	if Net.is_online() or not _steam_ready_or_explain():
		return
	_close_modal()
	if _lobby_dialog == null:
		_build_lobby_dialog()
	_lobby_dialog.popup_centered(Vector2i(470, 430))
	_lobby_status.text = "Joining your friend's beach..."
	Net.join_steam_lobby(id)


func _clear_children(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		child.queue_free()


func _on_quit() -> void:
	Net.leave()
	Net.steam_shutdown()
	Sfx.stop_ambience()
	# Let the last UI click actually finish: quitting in the same frame it starts
	# leaves an audio playback alive while Godot tears the tree down.
	await get_tree().create_timer(0.15).timeout
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
