extends Node3D
## Deep-sand physics test.
##
## The beach is eight metres of sand now, and sand does not stand in a wall: a
## scoop makes the walls slide back into the hole, and the deeper the hole gets
## the harder the sand packs, so the same swing takes a smaller bite down there.
## That behaviour is what the whole dig loop is balanced around, so it gets its
## own regression test:
##
##   1. a narrow shaft cannot be sunk deep - the walls cave in and refill it,
##   2. the collapse conserves sand: the beach only loses what the shovel took,
##   3. the collapse is deterministic, so a client replaying `apply_dig` ends up
##      with exactly the host's heights (multiplayer safety),
##   4. a proper wide excavation does reach the chest band,
##   5. deep sand really is harder than surface sand, and the surface keeps full
##      power,
##   6. a dig in the surf cannot punch through the sea bed,
##   7. every scoop that really removed sand pays XP, and a fully refilled one
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
	await _check_depth_hardness()
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
## has to take a real excavation rather than one scoop. Below that, the top tier
## must still be able to open the rest of the eight metres of sand.
func _check_wide_pit_reaches_bottom() -> void:
	var terrain := await _terrain()
	var tier := EquipmentData.default_tiers()[TRENCH_SPADE]
	var digs := 0
	while terrain.get_height_at(SPOT) > -LootManager.TREASURE_DEPTH and digs < 400:
		terrain.dig_at(SPOT, tier.radius, tier.depth)
		digs += 1
	var depth := terrain.get_height_at(SPOT)
	print("SAND trench spade reached %.2f m after %d digs" % [depth, digs])
	_check("the chest band is reachable", depth <= -LootManager.TREASURE_DEPTH)
	_check("it takes a real excavation", digs >= 20)
	_check("no pit can go below the sand floor",
		depth >= -SandTerrain.MAX_DEPTH - 0.001)

	# The endgame shovel keeps going once the chest band is behind it: there is
	# more beach under the chest than above it.
	var top := EquipmentData.default_tiers()[EquipmentData.default_tiers().size() - 1]
	var extra := 0
	while terrain.get_height_at(SPOT) > -SandTerrain.MAX_DEPTH + 0.01 and extra < 500:
		terrain.dig_at(SPOT, top.radius, top.depth)
		extra += 1
	var bottom := terrain.get_height_at(SPOT)
	print("SAND %s reached %.2f m after %d more digs" % [top.display_name, bottom, extra])
	_check("the top tier can open the deep sand", bottom <= -SandTerrain.MAX_DEPTH + 0.05)
	_check("even the top tier stops at the sand floor", bottom >= -SandTerrain.MAX_DEPTH - 0.001)
	_check("the sand is deeper than the chest band by a good margin",
		SandTerrain.MAX_DEPTH >= LootManager.TREASURE_DEPTH + 2.0)
	terrain.queue_free()


## Sand packs harder the deeper the hole: the same swing takes a smaller scoop
## at 4 m than it does on the surface, but it never stops biting entirely, and
## the surface is always at full power.
func _check_depth_hardness() -> void:
	var surface := await _terrain()
	var tier := EquipmentData.default_tiers()[TRENCH_SPADE]
	var surface_power := surface.dig_power_at(SPOT)
	var surface_volume := surface.dig_at(SPOT, tier.radius, tier.depth)
	_check("the surface is dug at full power", is_equal_approx(surface_power, 1.0))

	var deep := await _terrain()
	var digs := 0
	while deep.get_height_at(SPOT) > -4.0 and digs < 400:
		deep.dig_at(SPOT, tier.radius, tier.depth)
		digs += 1
	var deep_power := deep.dig_power_at(SPOT)
	var deep_volume := deep.dig_at(SPOT, tier.radius, tier.depth)
	print("SAND power %.2f at %.2f m | scoop %.3f vs %.3f m3" % [
		deep_power, deep.get_height_at(SPOT), surface_volume, deep_volume])
	_check("the sand hardens with depth", deep_power <= 0.6)
	_check("a deep scoop is much smaller than a surface one",
		deep_volume < surface_volume * 0.5)
	_check("the shovel still bites at depth", deep_volume > 0.0)
	_check("hardening never stops the dig completely", SandTerrain.HARDEN_MIN > 0.0)
	_check("hardening only starts below the surface", SandTerrain.HARDEN_DEPTH > 0.0)
	surface.queue_free()
	deep.queue_free()


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
	# Dig the same spot all the way to the sand floor with the best shovel: once
	# the pit is exhausted the walls have nowhere left to fall from.
	var top := EquipmentData.default_tiers()[EquipmentData.default_tiers().size() - 1]
	var digs := 0
	while terrain.get_height_at(SPOT) > -SandTerrain.MAX_DEPTH + 0.01 and digs < 600:
		terrain.dig_at(SPOT, top.radius, top.depth)
		digs += 1
	for i in 200:
		terrain.dig_at(SPOT, top.radius, top.depth)
	var floor_volume := terrain.dig_at(SPOT, top.radius, top.depth)
	print("SAND floor scoop volume %.4f m3 after %d digs to %.2f m" % [
		floor_volume, digs + 201, terrain.get_height_at(SPOT)])
	# Not exactly zero while the walls are still creeping in, but an exhausted
	# pit must not be a sand farm: it has to pay (nearly) nothing.
	_check("an exhausted pit pays almost nothing",
		floor_volume < volume * 0.05)
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
