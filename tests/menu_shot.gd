extends Node
## Renders the main menu, its settings panel and the Host notice, saving one
## PNG each so the layout can be reviewed without launching the editor.

func _ready() -> void:
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().create_timer(0.6).timeout
	_save("res://menu_proof.png")

	menu.get_node("Menu/Settings").pressed.emit()
	await get_tree().create_timer(0.3).timeout
	_save("res://menu_settings_proof.png")
	menu.get_node("Settings/Panel/Margin/VBox/Back").pressed.emit()

	menu.get_node("Menu/Host").pressed.emit()
	await get_tree().create_timer(0.3).timeout
	_save("res://menu_host_proof.png")

	get_tree().quit(0)


func _save(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("MENU SHOT %s err=%d" % [path, err])
