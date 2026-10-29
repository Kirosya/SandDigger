class_name Junkyard
extends Node3D
## The junkyard stall where the item in hand is sold for money.
##
## It only owns its look and a trading radius; the actual sale goes through
## PlayerState.sell_held() so each player's money stays independent and only
## the one item being held leaves the bag.

const SELL_RADIUS := 3.5

var _materials: Dictionary = {}


func _ready() -> void:
	add_to_group("junkyard")
	_build()


func _build() -> void:
	# Wooden counter.
	var counter := MeshInstance3D.new()
	var counter_mesh := BoxMesh.new()
	counter_mesh.size = Vector3(2.2, 0.9, 1.2)
	counter.mesh = counter_mesh
	counter.position = Vector3(0.0, 0.45, 0.0)
	counter.material_override = _get_material("wood", Color(0.42, 0.29, 0.16), 0.0, 0.85)
	add_child(counter)

	# Scrap pile behind the counter.
	var scrap_positions := [
		Vector3(-0.7, 0.3, -0.9), Vector3(0.1, 0.35, -1.1), Vector3(0.8, 0.28, -0.8),
		Vector3(-0.2, 0.15, -0.6), Vector3(0.55, 0.12, -0.45),
	]
	for i in scrap_positions.size():
		var scrap := MeshInstance3D.new()
		var box := BoxMesh.new()
		var size := 0.35 + 0.12 * float(i % 3)
		box.size = Vector3(size, size * 0.8, size)
		scrap.mesh = box
		scrap.position = scrap_positions[i]
		scrap.rotation_degrees = Vector3(0.0, float(i * 43), float(i * 11))
		scrap.material_override = _get_material("scrap", Color(0.35, 0.36, 0.34), 0.55, 0.75)
		add_child(scrap)

	# Sign.
	var sign_label := Label3D.new()
	sign_label.text = "JUNKYARD\n[E] sell held"
	sign_label.font_size = 48
	sign_label.pixel_size = 0.003
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.modulate = Color(1.0, 0.92, 0.6)
	sign_label.outline_modulate = Color(0, 0, 0, 1)
	sign_label.position = Vector3(0.0, 1.8, 0.0)
	add_child(sign_label)

	var pole := MeshInstance3D.new()
	var pole_mesh := BoxMesh.new()
	pole_mesh.size = Vector3(0.1, 1.6, 0.1)
	pole.mesh = pole_mesh
	pole.position = Vector3(0.0, 1.0, -0.5)
	pole.material_override = _get_material("wood", Color(0.42, 0.29, 0.16), 0.0, 0.85)
	add_child(pole)


func _get_material(key: String, color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	_materials[key] = material
	return material
