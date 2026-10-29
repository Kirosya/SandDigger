extends Node3D
## Phase 2 balance report: measures the digging / XP / money / detector numbers
## the current constants produce, so tuning is based on data instead of guesses.
##
## Run headless:  godot --headless --path . res://tests/balance_report.tscn

const DIG_INTERVAL := 0.4  # DigController.DIG_INTERVAL
const XP_PER_M3 := PlayerState.XP_PER_CUBIC_METER
const SAMPLES := 3000

var _terrain: SandTerrain
var _loot: LootManager


func _ready() -> void:
	await get_tree().process_frame

	print("=== TIERS: one dig on fresh sand ===")
	var prev_volume := 0.0
	for tier in EquipmentData.default_tiers():
		var terrain := SandTerrain.new()
		add_child(terrain)
		await get_tree().process_frame
		var volume := terrain.dig_at(Vector3.ZERO, tier.radius, tier.depth)
		var xp := volume * XP_PER_M3
		var growth := 0.0 if prev_volume <= 0.0 else volume / prev_volume
		print("T%s %-13s r=%.2f d=%.2f | vol=%.4f m3  xp/dig=%6.1f  xp/s=%7.1f  x%.2f vs prev" % [
			tier.tier_index, tier.display_name, tier.radius, tier.depth, volume, xp,
			xp / DIG_INTERVAL, growth])
		prev_volume = volume
		terrain.queue_free()

	print("")
	print("=== LEVELS: XP curve ===")
	for level in range(1, 12):
		var need := PlayerState.xp_required_for_level(level)
		var step := need - PlayerState.xp_required_for_level(level - 1)
		print("L%-2d total=%7.0f  step=%7.0f" % [level, need, step])

	print("")
	print("=== TIME TO LEVEL: continuous digging, per tier ===")
	var tiers := EquipmentData.default_tiers()
	for tier in tiers:
		var terrain := SandTerrain.new()
		add_child(terrain)
		await get_tree().process_frame
		var volume := terrain.dig_at(Vector3.ZERO, tier.radius, tier.depth)
		var xp_per_dig := volume * XP_PER_M3
		var line := "T%s %-13s" % [tier.tier_index, tier.display_name]
		for level in [3, 6, 10]:
			var digs := PlayerState.xp_required_for_level(level) / xp_per_dig
			line += "  L%d:%5.0f digs (%4.0fs)" % [level, digs, digs * DIG_INTERVAL]
		print(line)
		terrain.queue_free()

	print("")
	print("=== LOOT ===")
	_loot = LootManager.new()
	_loot.name = "LootManager"
	add_child(_loot)
	await get_tree().process_frame

	var buried := 0
	var surface := 0
	var rings := 0
	var trash_value := 0.0
	var trash_count := 0
	var ring_value := 0.0
	var depth_sum := 0.0
	var depth_min := 99.0
	var depth_max := 0.0
	for item in _loot.loot:
		if item.on_surface:
			surface += 1
		else:
			buried += 1
			depth_sum += item.depth
			depth_min = minf(depth_min, item.depth)
			depth_max = maxf(depth_max, item.depth)
		if item.kind == "ring":
			rings += 1
			ring_value += item.value
		else:
			trash_count += 1
			trash_value += item.value

	var total_value := trash_value + ring_value
	print("count=%d  buried=%d  surface=%d  rings=%d" % [
		_loot.loot.size(), buried, surface, rings])
	print("trash avg=$%.1f (n=%d)  ring avg=$%.1f (n=%d)" % [
		trash_value / maxf(trash_count, 1.0), trash_count,
		ring_value / maxf(rings, 1.0), rings])
	print("world money total=$%.0f  buried depth avg=%.2f min=%.2f max=%.2f" % [
		total_value, depth_sum / maxf(buried, 1.0), depth_min, depth_max])
	var avg_item := total_value / maxf(_loot.loot.size(), 1.0)
	for tier in tiers:
		if tier.money_required <= 0.0:
			continue
		print("  %-13s needs $%-5d = %5.1f items (avg $%.1f)" % [
			tier.display_name, int(tier.money_required),
			tier.money_required / avg_item, avg_item])

	print("")
	print("=== DETECTOR: nearest hidden item from random spots ===")
	var distances: Array[float] = []
	var strengths: Array[float] = []
	var noises: Array[float] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in SAMPLES:
		var angle := rng.randf() * TAU
		var radius := sqrt(rng.randf()) * 22.0
		var point := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var d := _loot.nearest_distance(point)
		if is_inf(d):
			continue
		distances.append(d)
		strengths.append(_loot.signal_strength(point))
		noises.append(_loot.metal_noise(point))
	distances.sort()
	strengths.sort()
	noises.sort()
	print("range=%.1f m  samples=%d" % [LootManager.SIGNAL_RANGE, distances.size()])
	print("distance  p10=%.2f  p50=%.2f  p90=%.2f  max=%.2f" % [
		_pct(distances, 0.10), _pct(distances, 0.50), _pct(distances, 0.90),
		distances[distances.size() - 1]])
	print("strength  p10=%.2f  p50=%.2f  p90=%.2f" % [
		_pct(strengths, 0.10), _pct(strengths, 0.50), _pct(strengths, 0.90)])
	var saturated := 0
	for s in strengths:
		if s >= 0.75:
			saturated += 1
	print("saturated (>=0.75 strength) = %.1f%% of spots" % [
		100.0 * float(saturated) / float(maxi(strengths.size(), 1))])
	print("metal noise  p10=%.2f  p50=%.2f  p90=%.2f  (max jitter +/-%.2f)" % [
		_pct(noises, 0.10), _pct(noises, 0.50), _pct(noises, 0.90),
		LootManager.NOISE_STRENGTH])

	print("BALANCE DONE")
	get_tree().quit(0)


func _pct(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var index := clampi(int(fraction * float(values.size() - 1)), 0, values.size() - 1)
	return values[index]
