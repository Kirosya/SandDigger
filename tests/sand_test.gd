extends Node3D
## Deep-sand physics test.
##
## The beach is six metres of sand now, and sand does not stand in a wall: a
## scoop makes the walls slide back into the hole. That behaviour is what the
## whole dig loop is balanced around, so it gets its own regression test:
##
##   1. a narrow shaft cannot be sunk deep - the walls cave in and refill it,
##   2. the collapse conserves sand: the beach only loses what the shovel took,
##   3. the collapse is deterministic, so a client replaying `apply_dig` ends up
##      with exactly the host's heights (multiplayer safety),
##   4. a proper wide excavation does reach the chest band,
##   5. a dig in the surf cannot punch through the sea bed,
##   6. every scoop that really removed sand pays XP, and a fully refilled one
##      pays nothing.

const SPOT := Vector3(0.0, 0.0, 5.0)
const TEASPOON := 0
const TRENCH_SPADE := 4

var _failures := 0


func _ready() -> void:
	await _check_narrow_shaft_fills()
	await _check_volume_conserved()
	await _check_deterministic()
	await _check_wide_pit_reaches_bottom()
	await _check_sea_bed()
	await _check_xp_matches_sand()

	if _failures == 0:
		print("SAND OK")
		get_tree().quit(0)
	else:
		print("SAND FAILED (%d)" % _failures)
		get_tree().quit(1)


func _terrain() -> SandTerrain:
	var terrain := SandTerrain.new()
	terrain.name = "SandTerrain"
	add_child(terrain)
	await get_tree().process_frame
	return terrain


## A teaspoon hole in one spot: the walls slide in, so the surviving pit is a
## shallow dip, not a 1 m shaft, and it is much wider than the shovel's radius.
func _check_narrow_shaft_fills() -> void:
	var terrain := await _terrain()
	var tier := EquipmentData.default_tiers()[TEASPOON]
	for i in 40:
		terrain.dig_at(SPOT, tier.radius, tier.depth)
	var depth := terrain.get_height_at(SPOT)
	print("SAND teaspoon 40 digs -> depth %.2f m" % depth)
	_check("a narrow shaft does not sink far", depth > -1.2)
	# 40 scoops of 0.05 m would be 2 m if nothing slid back in.
	_check("the slide-back is what stops it, not the bite size", depth > -1.0)
	# The rim is pulled in: the crater is wider than the teaspoon itself.
	var edge := 0.0
	while terrain.get_height_at(SPOT + Vector3(edge + 0.5, 0.0, 0.0)) < -0.05:
		edge += 0.5
		if edge > 8.0:
			break
	print("SAND teaspoon crater half-width %.1f m" % edge)
	_check("the crater is much wider than the shovel", edge >= 1.0)
	terrain.queue_free()


## Settling only moves sand around: the whole heightmap must lose exactly the
## volume `dig_at` reported.
func _check_volume_conserved() -> void:
	var terrain := await _terrain()
	var sum_before := _height_sum(terrain)
	var reported := 0.0
	var tier := EquipmentData.default_tiers()[TRENCH_SPADE]
	for i in 12:
		reported += terrain.dig_at(SPOT, tier.radius, tier.depth)
	var sum_after := _height_sum(terrain)
	var measured := (sum_before - sum_after) * SandTerrain.CELL_AREA
	print("SAND volume reported=%.3f measured=%.3f m3" % [reported, measured])
	_check("the collapse created no sand", measured > 0.0)
	_check("reported volume matches the heightmap",
		absf(measured - reported) <= maxf(0.001, reported * 0.001))
	terrain.queue_free()


## The host carves and every client replays the same call: same inputs must give
## byte-identical heights or the two beaches drift apart.
func _check_deterministic() -> void:
	var host := await _terrain()
	var client := await _terrain()
	var tier := EquipmentData.default_tiers()[TRENCH_SPADE]
	for i in 9:
		host.dig_at(SPOT + Vector3(0.3 * i, 0.0, 0.0), tier.radius, tier.depth)
		client.dig_at(SPOT + Vector3(0.3 * i, 0.0, 0.0), tier.radius, tier.depth)
	var worst := 0.0
	for i in host.heights.size():
		worst = maxf(worst, absf(host.heights[i] - client.heights[i]))
	print("SAND replay difference %.6f m" % worst)
	_check("a client replay matches the host exactly", worst == 0.0)
	_check("the replay actually dug something",
		host.get_height_at(SPOT) < -0.5)
	host.queue_free()
	client.queue_free()


## The chest hides at 4.6 m: a Trench Spade must be able to get there, and it
## has to take a real excavation rather than one scoop.
func _check_wide_pit_reaches_bottom() -> void:
	var terrain := await _terrain()
	var tier := EquipmentData.default_tiers()[TRENCH_SPADE]
	var digs := 0
	while terrain.get_height_at(SPOT) > -LootManager.TREASURE_DEPTH and digs < 260:
		terrain.dig_at(SPOT, tier.radius, tier.depth)
		digs += 1
	var depth := terrain.get_height_at(SPOT)
	print("SAND trench spade reached %.2f m after %d digs" % [depth, digs])
	_check("the chest band is reachable", depth <= -LootManager.TREASURE_DEPTH)
	_check("it takes a real excavation", digs >= 20)
	_check("no pit can go below the sand floor",
		depth >= -SandTerrain.MAX_DEPTH - 0.001)
	terrain.queue_free()


## In the surf the sand keeps a floor a margin below the natural sea bed, so a
## dig can never open a hole in the water.
func _check_sea_bed() -> void:
	var terrain := await _terrain()
	# Somewhere clearly under water: the beach slopes down toward -Z.
	var wet := Vector3(0.0, 0.0, -22.0)
	var base := terrain.base_heights[
		(int(round(wet.z / SandTerrain.CELL_SIZE)) + SandTerrain.HALF_GRID) * SandTerrain.GRID_SIZE
		+ int(round(wet.x / SandTerrain.CELL_SIZE)) + SandTerrain.HALF_GRID]
	var tier := EquipmentData.default_tiers()[TRENCH_SPADE]
	for i in 30:
		terrain.dig_at(wet, tier.radius, tier.depth)
	var depth := terrain.get_height_at(wet)
	print("SAND surf dig: base=%.2f bottom=%.2f" % [base, depth])
	_check("the surf is wet sand", base < -0.5)
	_check("the sea bed is not punched through",
		depth >= maxf(-SandTerrain.MAX_DEPTH, base - SandTerrain.SEA_DIG_MARGIN) - 0.01)
	terrain.queue_free()


## XP is "net sand gone", so a scoop the collapse undid must pay (almost) nothing
## and a real scoop must pay its volume.
func _check_xp_matches_sand() -> void:
	var terrain := await _terrain()
	var tier := EquipmentData.default_tiers()[TRENCH_SPADE]
	var volume := terrain.dig_at(SPOT, tier.radius, tier.depth)
	_check("a first scoop pays XP", volume > 0.05)
	# Dig the same spot until it is at the floor: the last scoop removes nothing.
	for i in 400:
		terrain.dig_at(SPOT, tier.radius, tier.depth)
	var floor_volume := terrain.dig_at(SPOT, tier.radius, tier.depth)
	print("SAND floor scoop volume %.4f m3" % floor_volume)
	# Not exactly zero: the walls keep creeping in, so every scoop still takes a
	# sliver. It must be negligible next to a real scoop.
	_check("an exhausted pit pays almost nothing", floor_volume < volume * 0.05)
	# Even a scoop that nets nothing has to be broadcast when it moved sand, or
	# the host and a client would end up with different beaches.
	_check("a shape-changing scoop is flagged for broadcast",
		terrain.last_dig_changed)
	terrain.queue_free()


func _height_sum(terrain: SandTerrain) -> float:
	var total := 0.0
	for value in terrain.heights:
		total += value
	return total


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
