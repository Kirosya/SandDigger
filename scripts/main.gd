extends Node3D
## Scene bootstrap: sun angle and the loot -> HUD announcements.
## Player movement, digging, loot and selling all live in their own scripts.

@onready var _sun: DirectionalLight3D = $Sun


func _ready() -> void:
	_sun.rotation_degrees = Vector3(-55.0, 28.0, 0.0)
	_sun.light_energy = 0.75
	_wire_loot_announcements()


func _wire_loot_announcements() -> void:
	var loot := get_tree().get_first_node_in_group("loot_manager") as LootManager
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	if loot == null or hud == null:
		return
	loot.loot_revealed.connect(_on_loot_revealed.bind(hud))


func _on_loot_revealed(item: Dictionary, hud: Hud) -> void:
	if item.get("kind", "") == "ring":
		hud.announce_ring(str(item.get("name", "Gold Ring")), int(item.get("value", 0)))
		return
	hud.flash("Uncovered: %s  -  walk up and press E" % item.get("name", "loot"))
