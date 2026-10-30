extends Node
## Held-tool growth test: each equipment tier must make the tool in hand bigger
## while keeping the hand end in front of the camera (no clipping through it).

var _failures := 0


func _ready() -> void:
	var player: Node3D = load("res://scenes/player.tscn").instantiate()
	add_child(player)
	await get_tree().process_frame

	var pivot: Node3D = player.get_node("Head/Camera3D/SpoonPivot")
	var tiers := EquipmentData.default_tiers()

	player.apply_equipment(tiers[0])
	await get_tree().create_timer(0.45).timeout
	var scale_t0: float = pivot.scale.x

	player.apply_equipment(tiers[3])
	await get_tree().create_timer(0.45).timeout
	var scale_t3: float = pivot.scale.x

	_check("earth shovel is much bigger", scale_t3 > scale_t0 * 1.8)

	var near_end := pivot.position.z + FirstPersonPlayer.TOOL_HANDLE_NEAR_Z * scale_t3
	_check("hand end stays in front of the camera", near_end < -0.05 and near_end > -0.35)

	player.apply_equipment(tiers[1])
	await get_tree().create_timer(0.45).timeout
	var scale_t1: float = pivot.scale.x
	_check("tier 1 sits between tier 0 and 3", scale_t1 > scale_t0 and scale_t1 < scale_t3)

	# The last tier of the seven-step chain must still be holdable.
	player.apply_equipment(tiers[tiers.size() - 1])
	await get_tree().create_timer(0.45).timeout
	var scale_top: float = pivot.scale.x
	_check("the Dune Excavator is the biggest tool", scale_top > scale_t3)
	var top_near := pivot.position.z + FirstPersonPlayer.TOOL_HANDLE_NEAR_Z * scale_top
	_check("the biggest tool still clears the camera",
		top_near < -0.05 and top_near > -0.4)
	_check("the tool list covers all seven shovels", FirstPersonPlayer.TOOL_SCALES.size() == 7)

	if _failures == 0:
		print("TOOL OK")
		get_tree().quit(0)
	else:
		print("TOOL FAILED (%d)" % _failures)
		get_tree().quit(1)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
