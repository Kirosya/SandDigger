class_name Market
extends Node3D
## The little beach market: a striped-awning stall that sells the metal detector
## and the shovel upgrades.
##
## It only owns its look, the interaction radius and the handle to the shop UI;
## prices and level requirements live in PlayerState so they stay per-player.

const INTERACT_RADIUS := 3.2

const WOOD := Color(0.52, 0.36, 0.2)
const WOOD_DARK := Color(0.36, 0.24, 0.13)
const RED := Color(0.78, 0.24, 0.2)
const CREAM := Color(0.94, 0.9, 0.78)
const ORANGE_COIL := Color(0.93, 0.52, 0.16)

var _materials: Dictionary = {}


func _ready() -> void:
	add_to_group("market")
	_build()


## Opens the shop panel for the local player.
func open_shop() -> void:
	var shop := get_tree().get_first_node_in_group("shop_ui") as ShopUI
	var state := Net.local_state()
	var player := Net.local_player() as Node3D
	if shop != null and state != null:
		shop.open(state, player)


func _build() -> void:
	# Counter.
	_box("Counter", Vector3(2.6, 0.95, 1.1), WOOD, Vector3(0.0, 0.475, 0.0))
	_box("CounterTop", Vector3(2.75, 0.09, 1.25), WOOD_DARK, Vector3(0.0, 0.98, 0.0))

	# Four posts holding the awning.
	for x in [-1.2, 1.2]:
		for z in [-0.55, 0.55]:
			_box("Post", Vector3(0.09, 2.5, 0.09), WOOD_DARK,
				Vector3(float(x), 1.25, float(z)))

	# Red / cream striped awning, sloping a little toward the front.
	for i in 6:
		var x := -1.15 + float(i) * 0.46
		var stripe := _box("Stripe", Vector3(0.46, 0.07, 1.75),
			RED if i % 2 == 0 else CREAM, Vector3(x, 2.55, 0.0))
		stripe.rotation_degrees.x = -6.0

	# Goods on the counter: a shovel and a detector, so the stall reads at a glance.
	var handle := _box("ShovelHandle", Vector3(0.05, 0.05, 0.85), WOOD,
		Vector3(-0.7, 1.11, 0.0))
	handle.rotation_degrees = Vector3(0.0, 18.0, 90.0)
	_box("ShovelBlade", Vector3(0.26, 0.03, 0.3), Color(0.5, 0.52, 0.55),
		Vector3(-0.36, 1.14, 0.18))
	_box("DetectorBox", Vector3(0.34, 0.1, 0.24), Color(0.2, 0.21, 0.24),
		Vector3(0.72, 1.07, 0.0))
	_box("DetectorCoil", Vector3(0.26, 0.03, 0.26), ORANGE_COIL,
		Vector3(0.72, 1.03, 0.42))

	# Sign.
	var sign_label := Label3D.new()
	sign_label.text = "MARKET\n[E] shop"
	sign_label.font_size = 48
	sign_label.pixel_size = 0.003
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.modulate = Color(1.0, 0.94, 0.72)
	sign_label.outline_modulate = Color(0, 0, 0, 1)
	sign_label.position = Vector3(0.0, 2.05, 0.0)
	add_child(sign_label)


func _box(part_name: String, size: Vector3, color: Color, position: Vector3) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = _material(color)
	instance.position = position
	add_child(instance)
	return instance


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	_materials[key] = material
	return material
