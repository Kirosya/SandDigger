extends Node
## Character rig test: the player must build a visible body and first-person
## hands, the owner's own camera must skip the head/body arms (it sits inside the
## head), and the hands must stay life-size and glued to the handle as the tool
## grows through the tiers.

var _failures := 0


func _ready() -> void:
	var player: Node3D = load("res://scenes/player.tscn").instantiate()
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame

	var rig := player.get_node_or_null("Body") as CharacterRig
	_check("character rig exists", rig != null)
	if rig == null:
		_finish()
		return

	_check("torso built", rig.get_node_or_null("Torso") != null)
	_check("hips built", rig.get_node_or_null("Hips") != null)
	_check("legs built",
		rig.get_node_or_null("LegL") != null and rig.get_node_or_null("LegR") != null)
	_check("shoes built",
		rig.get_node_or_null("ShoeL") != null and rig.get_node_or_null("ShoeR") != null)
	_check("hat built", rig.get_node_or_null("HeadVisual/HatBrim") != null)

	var camera := player.get_node("Head/Camera3D") as Camera3D
	var head_mesh := rig.get_node("HeadVisual/Head") as MeshInstance3D
	var body_arm := rig.get_node("ArmsVisual/UpperArmR") as MeshInstance3D
	_check("owner camera skips the hidden layer",
		(camera.cull_mask & CharacterRig.OWNER_HIDDEN_LAYER) == 0)
	_check("head sits on the hidden layer",
		head_mesh.layers == CharacterRig.OWNER_HIDDEN_LAYER)
	_check("body arms sit on the hidden layer",
		body_arm.layers == CharacterRig.OWNER_HIDDEN_LAYER)

	var right := camera.get_node_or_null("RightArm") as Node3D
	var left := camera.get_node_or_null("LeftArm") as Node3D
	_check("right viewmodel arm exists", right != null)
	_check("left viewmodel arm exists", left != null)
	if right == null or left == null:
		_finish()
		return
	_check("right hand has a mitt", right.get_node_or_null("Hand") != null)
	_check("right hand has fingers", right.get_node_or_null("Finger0") != null)
	_check("right hand has a sleeve", right.get_node_or_null("Sleeve") != null)
	_check("hands render for the owner",
		(right.get_node("Hand") as MeshInstance3D).layers == 1)

	var pivot := player.get_node("Head/Camera3D/SpoonPivot") as Node3D
	var tiers := EquipmentData.default_tiers()

	player.apply_equipment(tiers[0])
	await get_tree().create_timer(0.45).timeout
	var t0_z := right.position.z
	var grip0 := pivot.transform * Vector3(0.0, 0.0, CharacterRig.RIGHT_GRIP_Z)
	_check("hand grips the handle at tier 0", right.position.distance_to(grip0) < 0.001)
	_check("hand stays in front of the camera", right.position.z < -0.3)

	player.apply_equipment(tiers[3])
	await get_tree().create_timer(0.45).timeout
	var grip3 := pivot.transform * Vector3(0.0, 0.0, CharacterRig.RIGHT_GRIP_Z)
	_check("hand follows the longer handle", right.position.z < t0_z - 0.15)
	_check("hand still grips the handle at tier 3",
		right.position.distance_to(grip3) < 0.001)
	_check("hands stay life-size", right.scale.is_equal_approx(Vector3.ONE))
	_check("tool really did grow", pivot.scale.x > 1.8)

	# The left hand grips further back on the shaft, so it sits nearer the camera.
	_check("left hand is nearer than the right", left.position.z > right.position.z)

	_finish()


func _finish() -> void:
	if _failures == 0:
		print("CHARACTER OK")
		get_tree().quit(0)
	else:
		print("CHARACTER FAILED (%d)" % _failures)
		get_tree().quit(1)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
