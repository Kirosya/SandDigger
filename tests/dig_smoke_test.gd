extends Node3D
## Headless smoke test for the first-person gameplay loop.
## Verifies: heights change, dig_at returns volume, collision follows the
## heightmap, digging uncovers buried loot, a second claim is rejected, selling
## pays money, and equipment upgrades need BOTH level and money.

func _ready() -> void:
	var terrain: SandTerrain = SandTerrain.new()
	terrain.name = "SandTerrain"
	add_child(terrain)
	await get_tree().process_frame
	await get_tree().physics_frame

	var loot: LootManager = LootManager.new()
	loot.name = "LootManager"
	add_child(loot)
	await get_tree().process_frame

	var center := SandTerrain.GRID_SIZE / 2
	var idx := center * SandTerrain.GRID_SIZE + center
	print("SMOKE chunks=%d h_start=%.4f loot_items=%d" % [
		terrain.get_child_count(), terrain.heights[idx], loot.loot.size()])

	var total := 0.0
	for i in 5:
		total += terrain.dig_at(Vector3(0.0, 0.0, 0.0), 0.15, 0.05)
	var height_center := terrain.get_height_at(Vector3(0.0, 0.0, 0.0))
	print("SMOKE dug_total=%.5f h_center=%.4f get_height=%.4f dirty=%s" % [
		total, terrain.heights[idx], height_center, str(terrain.last_dirty_rect)])

	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(0.0, 2.0, 0.0), Vector3(0.0, -3.0, 0.0))
	var hit := space.intersect_ray(query)
	print("SMOKE collision_hit_y=%s" % ("none" if hit.is_empty() else "%.4f" % hit["position"].y))

	# --- Loot reveal -------------------------------------------------------
	var surface_count := 0
	for item in loot.loot:
		if item.on_surface:
			surface_count += 1
	print("SMOKE loot_split surface=%d buried=%d" % [
		surface_count, loot.loot.size() - surface_count])

	var target: LootManager.LootItem = null
	for item in loot.loot:
		if not item.on_surface:
			target = item
			break
	if target == null:
		print("SMOKE FAIL no buried loot")
		get_tree().quit()
		return
	print("SMOKE loot_target=%s depth=%.2f at %s revealed=%s" % [
		target.display_name, target.depth, str(target.buried_position), str(target.revealed)])
	# Dig in steps until the target is uncovered (depth is random now).
	var digs := 0
	while not target.revealed and digs < 24:
		terrain.dig_at(target.buried_position, 0.3, 0.12)
		digs += 1
	var surface := terrain.get_height_at(target.buried_position)
	print("SMOKE loot_surface=%.4f digs=%d reveal_threshold=%.2f revealed=%s" % [
		surface, digs, -target.depth + LootManager.REVEAL_MARGIN, str(target.revealed)])

	# --- Claim / double claim ---------------------------------------------
	var player_one := PlayerState.new()
	player_one.player_id = 1
	add_child(player_one)
	var player_two := PlayerState.new()
	player_two.player_id = 2
	add_child(player_two)
	await get_tree().process_frame

	var first_claim := loot.take_loot(target.loot_id, player_one.player_id)
	var second_claim := loot.take_loot(target.loot_id, player_two.player_id)
	print("SMOKE claim_p1=%s claim_p2=%s p1_items=%d p2_items=%d" % [
		str(first_claim), str(second_claim),
		player_one.carried_loot.size(), player_two.carried_loot.size()])

	# --- Sell --------------------------------------------------------------
	var carried := player_one.carried_value()
	var earned := player_one.sell_all()
	print("SMOKE sell carried=%.0f earned=%.0f money=%.0f bag=%d" % [
		carried, earned, player_one.current_money, player_one.carried_loot.size()])

	# --- Upgrade needs level AND money -------------------------------------
	player_one.add_dig_volume(2.0)
	var can_before_money := player_one.can_upgrade_to(1)
	player_one.add_money(50.0)
	var can_after_money := player_one.can_upgrade_to(1)
	var upgraded := player_one.try_upgrade()
	print("SMOKE upgrade lv=%d before=%s after=%s ok=%s equip=%s radius=%.2f money=%.0f" % [
		player_one.current_level, str(can_before_money), str(can_after_money),
		str(upgraded), player_one.get_current_equipment().display_name,
		player_one.get_current_equipment().radius, player_one.current_money])

	# Player two must be unaffected by player one's progression.
	print("SMOKE independence p2_xp=%.1f p2_lv=%d p2_tier=%d" % [
		player_two.current_xp, player_two.current_level, player_two.equipment_tier_index])
	print("SMOKE DONE")
	get_tree().quit()
