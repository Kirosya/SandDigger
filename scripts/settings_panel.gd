class_name SettingsPanel
extends Control
## Settings overlay shared by the main menu and the in-game pause menu.
##
## One scene, one script: the two menus cannot drift apart. Every control writes
## straight into the `GameSettings` autoload (so a slider is heard immediately
## while paused) and the file is written when the panel closes, not on every
## pixel of slider drag.
##
## The panel is a plain Control, so the owner decides what Esc means: this node
## only exposes `open()` / `close()` and the `closed` signal.

signal closed()

@onready var _sensitivity: HSlider = $Panel/Margin/VBox/Sensitivity/Row/Slider
@onready var _sensitivity_value: Label = $Panel/Margin/VBox/Sensitivity/Row/Value
@onready var _volume: HSlider = $Panel/Margin/VBox/Volume/Row/Slider
@onready var _volume_value: Label = $Panel/Margin/VBox/Volume/Row/Value
@onready var _fullscreen: CheckBox = $Panel/Margin/VBox/Fullscreen
@onready var _back: Button = $Panel/Margin/VBox/Back


func _ready() -> void:
	# Keeps working while the beach is paused behind it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sensitivity.min_value = GameSettings.MIN_SENSITIVITY
	_sensitivity.max_value = GameSettings.MAX_SENSITIVITY
	_sensitivity.step = 0.0001
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.01

	_sensitivity.value_changed.connect(_on_sensitivity_changed)
	_volume.value_changed.connect(_on_volume_changed)
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	_back.pressed.connect(close)

	_sync_widgets()
	visible = false


## Shows the panel with the values currently in GameSettings.
func open() -> void:
	_sync_widgets()
	visible = true
	_back.grab_focus()


## Saves and hides. Safe to call when already closed.
func close() -> void:
	if not visible:
		return
	GameSettings.save_settings()
	visible = false
	closed.emit()


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
