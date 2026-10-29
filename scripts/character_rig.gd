class_name CharacterRig
extends Node3D
## Procedural beachcomber character: a third-person body plus first-person arms.
##
## No imported assets: every part is a primitive with a flat material, matching
## the loot/props style. The rig is a child of the player, so the body turns with
## the player and casts a real shadow on the sand.
##
## `first_person` moves the head/hat and the body arms to a render layer the
## owner's camera skips, because the camera sits inside the head and the
## viewmodel arms replace the body ones. Phase 3 remote players instantiate the
## same rig with first_person = false.

@export var first_person := true

const SKIN := Color(0.84, 0.63, 0.47)
const SHIRT := Color(0.86, 0.38, 0.28)
const SHIRT_DARK := Color(0.63, 0.25, 0.19)
const SHORTS := Color(0.22, 0.33, 0.48)
const STRAW := Color(0.92, 0.82, 0.55)
const SHOES := Color(0.17, 0.17, 0.19)

## Where each viewmodel hand grips the tool, in SpoonPivot local space (z along
## the handle). The tool grows away from the camera, so these points follow it.
const RIGHT_GRIP_Z := -0.02
const LEFT_GRIP_Z := 0.10
## Arm tilt so the forearms run off the bottom corners of the screen.
const RIGHT_ARM_TILT := Vector3(-8.0, 0.0, 20.0)
const LEFT_ARM_TILT := Vector3(-6.0, 0.0, -18.0)
## Render layer used for parts the owner's own camera must not see (head, hat,
## body arms). Other cameras, i.e. remote players, still render them.
const OWNER_HIDDEN_LAYER := 2
## Render layer for the first-person hands. Only the owner's camera renders it;
## the third-person camera skips it so the arms do not float behind the body.
const VIEWMODEL_LAYER := 4

var _pivot: Node3D
var _right_arm: Node3D
var _left_arm: Node3D
var _right_grip_z := RIGHT_GRIP_Z
var _left_grip_z := LEFT_GRIP_Z
var _materials: Dictionary = {}


func _ready() -> void:
	_build_body()

	var player := get_parent() as Node3D
	if player == null:
		return
	_pivot = player.get_node_or_null("Head/Camera3D/SpoonPivot") as Node3D
	var camera := player.get_node_or_null("Head/Camera3D") as Node3D
	if _pivot == null or camera == null:
		return
	if first_person:
		# The owner's camera sits inside the head, so it must not render the
		# head/hat/body arms. Other cameras still do.
		camera.cull_mask = camera.cull_mask & ~OWNER_HIDDEN_LAYER
	_right_arm = _make_arm("RightArm", true)
	camera.add_child(_right_arm)
	_left_arm = _make_arm("LeftArm", false)
	camera.add_child(_left_arm)
	# Viewmodel hands are first-person only; the third-person camera skips them.
	_set_layer_recursive(_right_arm, VIEWMODEL_LAYER)
	_set_layer_recursive(_left_arm, VIEWMODEL_LAYER)
	_place_arms()


## Points the hands at whatever is in hand (shovel, detector or held loot) and
## at the grip points on that model.
func set_tool_pivot(pivot: Node3D, right_grip_z: float = RIGHT_GRIP_Z,
		left_grip_z: float = LEFT_GRIP_Z) -> void:
	if pivot == null:
		return
	_pivot = pivot
	_right_grip_z = right_grip_z
	_left_grip_z = left_grip_z
	_place_arms()


func _process(_delta: float) -> void:
	_place_arms()


## Keeps both hands glued to their point on the handle, at life size, swinging
## with the tool. The pivot's basis is orthonormalised so tier scale never makes
## the hands grow.
func _place_arms() -> void:
	if _pivot == null:
		return
	var basis := _pivot.basis.orthonormalized()
	_place_arm(_right_arm, basis, _right_grip_z, RIGHT_ARM_TILT)
	_place_arm(_left_arm, basis, _left_grip_z, LEFT_ARM_TILT)


func _place_arm(arm: Node3D, pivot_basis: Basis, grip_z: float, tilt_degrees: Vector3) -> void:
	if arm == null:
		return
	var grip_point := _pivot.transform * Vector3(0.0, 0.0, grip_z)
	var tilt := Basis.from_euler(tilt_degrees * (PI / 180.0))
	arm.transform = Transform3D(pivot_basis * tilt, grip_point)


func _build_body() -> void:
	# Legs, feet, shorts.
	for side in [-1.0, 1.0]:
		var suffix := "L" if side < 0.0 else "R"
		_add("Leg" + suffix, _cylinder(0.068, 0.075, 0.62), "skin",
			Vector3(side * 0.11, 0.42, 0.0))
		_add("Shoe" + suffix, _box(Vector3(0.14, 0.075, 0.25)), "shoes",
			Vector3(side * 0.11, 0.04, 0.045))
	_add("Hips", _box(Vector3(0.32, 0.26, 0.24)), "shorts", Vector3(0.0, 0.83, 0.0))

	# Torso and neck. The neck lives with the head visual so the owner's camera,
	# which sits inside the head, does not see the top of the neck as a plate.
	_add("Torso", _capsule(0.15, 0.48), "shirt", Vector3(0.0, 1.13, 0.0))
	_add("Collar", _cylinder(0.085, 0.1, 0.05), "shirt_dark", Vector3(0.0, 1.365, 0.0))

	var head_group := Node3D.new()
	head_group.name = "HeadVisual"
	add_child(head_group)
	_add("Neck", _cylinder(0.05, 0.055, 0.1), "skin", Vector3(0.0, 1.42, 0.0), head_group)
	_add("Head", _sphere(0.115), "skin", Vector3(0.0, 1.56, 0.0), head_group)
	var brim := _add("HatBrim", _cylinder(0.24, 0.24, 0.02), "straw",
		Vector3(0.0, 1.65, 0.0), head_group)
	var crown := _add("HatCrown", _cylinder(0.1, 0.12, 0.1), "straw",
		Vector3(0.0, 1.71, 0.0), head_group)
	# The brim would otherwise throw the whole head into shadow and make the
	# character look headless from behind.
	brim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Body arms: replaced by the viewmodel hands for the local player.
	var arms_group := Node3D.new()
	arms_group.name = "ArmsVisual"
	add_child(arms_group)
	for side in [-1.0, 1.0]:
		var suffix := "L" if side < 0.0 else "R"
		var arm := _add("UpperArm" + suffix, _capsule(0.052, 0.42), "skin",
			Vector3(side * 0.225, 1.14, 0.0), arms_group)
		arm.rotation_degrees.z = -side * 6.0
		_add("Sleeve" + suffix, _cylinder(0.07, 0.06, 0.14), "shirt",
			Vector3(side * 0.218, 1.31, 0.0), arms_group)
		_add("BodyHand" + suffix, _sphere(0.055), "skin",
			Vector3(side * 0.245, 0.93, 0.0), arms_group)

	if first_person:
		_set_layer_recursive(head_group, OWNER_HIDDEN_LAYER)
		_set_layer_recursive(arms_group, OWNER_HIDDEN_LAYER)


func _set_layer_recursive(node: Node, layer: int) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).layers = layer
		_set_layer_recursive(child, layer)


## One viewmodel arm: a mitt around the handle plus a forearm and rolled sleeve
## running off the bottom of the screen.
func _make_arm(arm_name: String, right: bool) -> Node3D:
	var root := Node3D.new()
	root.name = arm_name
	# The mitt grips from below the shaft, so the tool head stays visible above it.
	_add("Hand", _box(Vector3(0.062, 0.068, 0.058)), "skin", Vector3(0.0, -0.05, 0.0), root)
	_add("Thumb", _box(Vector3(0.024, 0.042, 0.026)), "skin",
		Vector3(-0.034 if right else 0.034, -0.026, -0.024), root)
	# Fingers curl up over the near side of the handle.
	for i in 3:
		_add("Finger%d" % i, _box(Vector3(0.016, 0.03, 0.018)), "skin",
			Vector3(-0.018 + float(i) * 0.018, -0.014, -0.032), root)
	_add("Forearm", _cylinder(0.04, 0.033, 0.3), "skin",
		Vector3(0.0, -0.22, 0.0), root)
	_add("Sleeve", _cylinder(0.052, 0.048, 0.14), "shirt",
		Vector3(0.0, -0.34, 0.0), root)
	return root


func _add(part_name: String, mesh: Mesh, material_name: String, position: Vector3,
		parent: Node3D = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.material_override = _material(material_name)
	instance.position = position
	if parent == null:
		parent = self
	parent.add_child(instance)
	return instance


func _material(material_name: String) -> StandardMaterial3D:
	if _materials.has(material_name):
		return _materials[material_name]
	var material := StandardMaterial3D.new()
	material.roughness = 0.85
	material.metallic = 0.0
	match material_name:
		"shirt":
			material.albedo_color = SHIRT
		"shirt_dark":
			material.albedo_color = SHIRT_DARK
		"shorts":
			material.albedo_color = SHORTS
		"straw":
			material.albedo_color = STRAW
		"shoes":
			material.albedo_color = SHOES
			material.roughness = 0.6
		_:
			material.albedo_color = SKIN
	_materials[material_name] = material
	return material


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _cylinder(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.height = height
	mesh.radial_segments = 12
	return mesh


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	return mesh


func _sphere(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return mesh
