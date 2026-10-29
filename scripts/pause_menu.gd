extends CanvasLayer
## Esc pause overlay: resume, jump back to the main menu, or quit.
##
## Runs with PROCESS_MODE_ALWAYS so it keeps responding while the tree is paused.

@onready var _root: Control = $Root


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	$Root/Panel/Margin/VBox/Resume.pressed.connect(_resume)
	$Root/Panel/Margin/VBox/MainMenu.pressed.connect(_to_main_menu)
	$Root/Panel/Margin/VBox/Quit.pressed.connect(_quit)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# The market panel owns Esc while it is open.
	var shop := get_tree().get_first_node_in_group("shop_ui") as ShopUI
	if shop != null and shop.is_open():
		return
	if _root.visible:
		_resume()
	else:
		_pause()
	get_viewport().set_input_as_handled()


func _pause() -> void:
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$Root/Panel/Margin/VBox/Resume.grab_focus()


func _resume() -> void:
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _to_main_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _quit() -> void:
	get_tree().quit()
