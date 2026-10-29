extends Node
## Persisted player preferences, shared by the main menu and the game.
##
## Lives as an autoload so any scene can read the current values without
## passing them around. Everything is stored in `user://settings.cfg`.

signal changed

const PATH := "user://settings.cfg"

const DEFAULT_SENSITIVITY := 0.0022
const MIN_SENSITIVITY := 0.0004
const MAX_SENSITIVITY := 0.0060
const DEFAULT_VOLUME := 1.0

var mouse_sensitivity := DEFAULT_SENSITIVITY
var master_volume := DEFAULT_VOLUME
var fullscreen := false


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		apply()
		return
	mouse_sensitivity = clampf(
		float(config.get_value("input", "mouse_sensitivity", DEFAULT_SENSITIVITY)),
		MIN_SENSITIVITY, MAX_SENSITIVITY)
	master_volume = clampf(
		float(config.get_value("audio", "master_volume", DEFAULT_VOLUME)), 0.0, 1.0)
	fullscreen = bool(config.get_value("video", "fullscreen", false))
	apply()


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("video", "fullscreen", fullscreen)
	config.save(PATH)
	apply()
	changed.emit()


## Pushes the current values into the engine (audio bus, window mode).
func apply() -> void:
	var master := AudioServer.get_bus_index("Master")
	if master >= 0:
		AudioServer.set_bus_volume_db(master, linear_to_db(maxf(master_volume, 0.0001)))
		AudioServer.set_bus_mute(master, master_volume <= 0.001)

	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
