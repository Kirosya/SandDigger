class_name DetectorModel
extends Node3D
## Procedural metal detector held in the first-person hand.
##
## Same primitive + flat-material style as the character and the loot. The model
## is built around the grip: the handle sits at local +z (toward the camera) and
## the search coil at -z, so the pivot transform is also where the hands grip.

const DARK := Color(0.16, 0.17, 0.2)
const METAL := Color(0.55, 0.57, 0.6)
const ORANGE := Color(0.93, 0.52, 0.16)
const SCREEN := Color(0.32, 0.95, 0.5)

var _materials: Dictionary = {}


func _ready() -> void:
	_build()


func _build() -> void:
	# Rubber grip and arm cuff where the hand closes around the shaft.
	_box("Grip", Vector3(0.05, 0.075, 0.15), DARK, Vector3(0.0, 0.01, 0.02))
	_box("Cuff", Vector3(0.065, 0.03, 0.1), DARK, Vector3(0.0, 0.085, 0.0))

	# Telescopic shaft running forward and slightly down.
	_box("Shaft", Vector3(0.024, 0.024, 0.8), METAL, Vector3(0.0, -0.01, -0.36))

	# Control box with a little green readout.
	_box("ControlBox", Vector3(0.085, 0.05, 0.13), DARK, Vector3(0.0, 0.045, -0.16))
	_box("Screen", Vector3(0.055, 0.006, 0.045), SCREEN, Vector3(0.0, 0.071, -0.16), true)

	# Coil mount and the round search head.
	_box("CoilMount", Vector3(0.03, 0.03, 0.12), DARK, Vector3(0.0, -0.02, -0.78))
	var coil := MeshInstance3D.new()
	coil.name = "Coil"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.08
	torus.outer_radius = 0.12
	torus.rings = 20
	torus.ring_segments = 8
	coil.mesh = torus
	coil.material_override = _material("orange", ORANGE, 0.0, 0.55)
	coil.position = Vector3(0.0, -0.035, -0.83)
	# Torus lies in XY by default; turn it flat so it reads as a search coil.
	coil.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	add_child(coil)


func _box(part_name: String, size: Vector3, color: Color, position: Vector3,
		emissive: bool = false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	var key := part_name if emissive else color.to_html()
	instance.material_override = _material(key, color, 0.0, 0.6, emissive)
	instance.position = position
	add_child(instance)
	return instance


func _material(key: String, color: Color, metallic: float, roughness: float,
		emissive: bool = false) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic if not emissive else 0.0
	material.roughness = roughness
	if key == "metal":
		material.metallic = 0.65
		material.roughness = 0.32
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.35
	_materials[key] = material
	return material
