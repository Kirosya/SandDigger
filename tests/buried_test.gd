extends Node3D
## "Loot is always in the sand" test.
##
## Buried items must exist in the world from the first frame, sit at their burial
## depth under the opaque sand surface, and be uncovered gradually: each dig may
## only move an item down by the amount of sand that was removed above it. There
## must be no invisible-then-visible pop and no floating above the surface.

var _failures := 0
var _step_failures := 0


func _ready() -> void:
	var terrain := SandTerrain.new()
	terrain.name = "SandTerrain"
	add_child(terrain)
	await get_tree().process_frame
	await get_tree().physics_frame

	var loot := LootManager.new()
	loot.name = "LootManager"
	add_child(loot)
	await get_tree().process_frame

	var item: LootManager.LootItem = null
	for candidate in loot.loot:
		if candidate.on_surface:
			continue
		if item == null or candidate.depth < item.depth:
			item = candidate
	_check("buried item exists", item != null)
	if item == null:
		_finish()
		return

	# The scatter is deep now, and sand collapses: check the shallowest buried
	# item so the test stays about reveal behaviour, not about digging power.
	var antique: LootManager.LootItem = null
	var antique_count := 0
	for candidate in loot.loot:
		if candidate.kind == "antique":
			antique_count += 1
			antique = candidate
	_check("the beach has antiques", antique != null and antique_count >= 3)
	if antique != null:
		_check("an antique is a deep find", antique.kind == "antique"
			and antique.depth >= LootManager.ANTIQUE_DEPTH_MIN - 0.001
			and antique.depth <= LootManager.ANTIQUE_DEPTH_MAX + 0.001)
		_check("an antique is worth a fortune", antique.value >= 400.0)

	print("BURIED target=%s depth=%.2f at %s" % [
		item.display_name, item.depth, str(item.buried_position)])

	_check("in the world from the start", item.node != null and item.node.visible)
	_expect("starts at its burial depth", item.node.position.y, -item.depth, 0.001)
	_check("starts buried (not claimable)", not item.revealed)

	var previous_y := item.node.position.y
	var reveal_surface := 0.0
	var steps := 0
	while steps < 60:
		steps += 1
		terrain.dig_at(item.buried_position, 0.45, 0.12)
		var y := item.node.position.y
		var surface := terrain.get_height_at(item.buried_position)

		# The sand above the item was removed this dig, so the item may only
		# move by (at most) that much. Anything bigger is a pop.
		if absf(y - previous_y) > 0.125:
			_step_failures += 1
			print("FAIL step %d jumped %.4f -> %.4f" % [steps, previous_y, y])
		# It must never hover above the sand it is lying in.
		if y > surface + 0.021:
			_step_failures += 1
			print("FAIL step %d floats y=%.4f surface=%.4f" % [steps, y, surface])
		# Still fully covered: the item must not move at all.
		if surface > -item.depth + 0.0001 and not is_equal_approx(y, -item.depth):
			_step_failures += 1
			print("FAIL step %d drifted while buried y=%.4f" % [steps, y])
		# Claimable only once the sand reached it.
		if not item.revealed and surface <= -item.depth:
			_step_failures += 1
			print("FAIL step %d exposed but not revealed" % steps)
		if not item.node.visible:
			_step_failures += 1
			print("FAIL step %d item went invisible" % steps)

		previous_y = y
		if item.revealed:
			reveal_surface = surface
			break

	_check("no pop-in jumps / drifting", _step_failures == 0)
	_check("revealed once the sand reached it", item.revealed)
	_check("revealed at its burial depth", reveal_surface <= -item.depth + 0.001)
	_check("still visible after reveal", item.node.visible)
	_expect("rests on the new sand surface", item.node.position.y,
		minf(-item.depth, reveal_surface + 0.02), 0.001)

	# Digging further must keep it on the sand, not leave it hanging in the air.
	var before := item.node.position.y
	terrain.dig_at(item.buried_position, 0.45, 0.12)
	var after_surface := terrain.get_height_at(item.buried_position)
	_check("follows the sand down", item.node.position.y < before)
	_expect("still rests on the sand", item.node.position.y,
		minf(-item.depth, after_surface + 0.02), 0.001)

	_finish()


func _finish() -> void:
	if _failures == 0:
		print("BURIED OK")
		get_tree().quit(0)
	else:
		print("BURIED FAILED (%d)" % _failures)
		get_tree().quit(1)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])


func _expect(label: String, actual: float, expected: float, tolerance: float) -> void:
	var ok := absf(actual - expected) <= tolerance
	if not ok:
		_failures += 1
	print("%s %-32s got=%.4f want=%.4f" % ["PASS" if ok else "FAIL", label, actual, expected])
