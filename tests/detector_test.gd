extends Node3D
## Detector regression test.
##
## The sweep must (a) only react to loot that is still buried, (b) fall off
## quadratically, and (c) read zero once nothing hidden is left in range.
## Run headless: godot --headless --path . res://tests/detector_test.tscn

var _failures := 0


func _ready() -> void:
	var terrain := SandTerrain.new()
	add_child(terrain)
	await get_tree().process_frame

	var loot := LootManager.new()
	add_child(loot)
	await get_tree().process_frame

	# Replace the random scatter with one controlled item.
	loot.loot.clear()
	var item := LootManager.LootItem.new()
	item.loot_id = 999
	item.buried_position = Vector3.ZERO
	item.depth = 0.3
	loot.loot.append(item)

	_expect("on top of a buried item", loot.signal_strength(Vector3.ZERO), 1.0, 0.001)
	_expect("half range (0.5 -> 0.25)", loot.signal_strength(Vector3(4.0, 0.0, 0.0)), 0.25, 0.01)
	_expect("at range edge", loot.signal_strength(Vector3(LootManager.SIGNAL_RANGE, 0.0, 0.0)), 0.0, 0.001)
	_expect("outside range", loot.signal_strength(Vector3(20.0, 0.0, 0.0)), 0.0, 0.001)

	item.revealed = true
	_expect("revealed item ignored", loot.signal_strength(Vector3.ZERO), 0.0, 0.001)

	item.revealed = false
	item.claimed = true
	_expect("claimed item ignored", loot.signal_strength(Vector3.ZERO), 0.0, 0.001)

	item.claimed = false
	item.on_surface = true
	item.revealed = true
	_expect("surface litter ignored", loot.signal_strength(Vector3.ZERO), 0.0, 0.001)

	# --- metal clutter noise -------------------------------------------------
	loot.loot.clear()
	var target := LootManager.LootItem.new()
	target.loot_id = 1000
	target.buried_position = Vector3.ZERO
	loot.loot.append(target)

	var sample_point := Vector3(4.0, 0.0, 0.0)
	var clean_a := loot.signal_strength(sample_point)
	var clean_b := loot.signal_strength(sample_point)
	_expect("no metal = stable reading", clean_a, clean_b, 0.0001)
	_expect("no metal = no noise", loot.metal_noise(sample_point), 0.0, 0.001)

	var can := LootManager.LootItem.new()
	can.loot_id = 1001
	can.buried_position = Vector3(1.0, 0.0, 0.0)
	can.metal = true
	loot.loot.append(can)
	_check("metal adds noise", loot.metal_noise(sample_point) > 0.05)

	var lowest := 2.0
	var highest := -2.0
	for i in 24:
		var reading := loot.signal_strength(sample_point)
		lowest = minf(lowest, reading)
		highest = maxf(highest, reading)
	_check("noise wobbles the reading", highest - lowest > 0.02)
	_check("reading stays clamped", lowest >= 0.0 and highest <= 1.0)

	can.buried_position = Vector3(30.0, 0.0, 0.0)
	_expect("far metal ignored", loot.metal_noise(sample_point), 0.0, 0.001)

	if _failures == 0:
		print("DETECTOR OK")
		get_tree().quit(0)
	else:
		print("DETECTOR FAILED (%d)" % _failures)
		get_tree().quit(1)


func _expect(label: String, actual: float, expected: float, tolerance: float) -> void:
	var ok := absf(actual - expected) <= tolerance
	if not ok:
		_failures += 1
	print("%s %-26s got=%.4f want=%.4f" % ["PASS" if ok else "FAIL", label, actual, expected])


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
