extends Node
## Endgame treasure-hunt test.
##
## Runs on the real main scene and covers the whole loop:
##   - the map is not on offer before the Earth Shovel,
##   - buying one costs money and buries the chest with NO marker at all,
##   - a second map cannot be bought while one is out,
##   - the chest sits near the bottom of the sand (4.6 m) and only opens once a
##     wide, deep pit is dug out,
##   - opening it pays into money (not the bag) and counts as a find,
##   - an unopened chest survives a saved-beach round trip, an opened one does not.

const SCRATCH_PROFILE := "user://test_treasure_profile.cfg"
const SCRATCH_WORLD := "user://test_treasure_beach.save"

var _failures := 0


func _ready() -> void:
	Profile.path_override = SCRATCH_PROFILE
	Profile.world_path_override = SCRATCH_WORLD
	Profile.clear()
	Profile.clear_world()

	await _check_offer_and_price()
	await _check_dig_and_open()
	await _check_saved_chest()

	Profile.clear()
	Profile.clear_world()
	Profile.path_override = ""
	Profile.world_path_override = ""
	print("TREASURE %s" % ("OK" if _failures == 0 else "FAILED (%d)" % _failures))
	await get_tree().create_timer(0.4).timeout
	get_tree().quit(0 if _failures == 0 else 1)


## --- The offer ------------------------------------------------------------

func _check_offer_and_price() -> void:
	var game := await _spawn_beach()
	var loot := game.get_node("LootManager") as LootManager
	var state := get_tree().get_first_node_in_group("player_state") as PlayerState
	var player := get_tree().get_first_node_in_group("player") as FirstPersonPlayer
	var shop := get_tree().get_first_node_in_group("shop_ui") as ShopUI
	_check("the beach has a loot manager", loot != null)
	if loot == null or state == null or shop == null:
		game.queue_free()
		return

	# A starting beachcomber must not be offered a map at all.
	state.current_money = 9999.0
	_check("the map is refused before the Earth Shovel", not state.can_buy_treasure_map())
	_check("a refused map spends nothing", is_equal_approx(state.current_money, 9999.0))
	_check("no chest is in the sand yet", not loot.has_treasure())

	# Max the shovel chain and try again: now it is a real offer.
	state.equipment_tier_index = PlayerState.TREASURE_TIER_REQUIRED
	_check("the map is offered once the Earth Shovel is owned",
		state.can_buy_treasure_map())

	var money_before := state.current_money
	_check("buying a map succeeds", state.buy_treasure_map())
	_check("the map costs its price", is_equal_approx(
		money_before - state.current_money, PlayerState.TREASURE_MAP_PRICE))

	var chest = loot.spawn_treasure(state.next_treasure_payout(_rng()))
	_check("a chest is buried", chest != null and loot.has_treasure())
	_check("the chest sits near the bottom of the sand",
		is_equal_approx(chest.depth, LootManager.TREASURE_DEPTH)
		and chest.depth > 4.0)
	_check("the chest is not surface loot", not chest.on_surface)
	_check("the chest is not claimable while buried", not chest.revealed)
	# "No hint at all": the map may not leave a marker in the world.
	var markers := 0
	for child in loot.get_children():
		if child is MeshInstance3D or child.name.contains("Beacon"):
			markers += 1
	_check("the map leaves no marker in the world", markers == 0)
	_check("the first chest pays the legend amount",
		is_equal_approx(chest.value, PlayerState.TREASURE_FIRST_PAYOUT))

	# A second map is not sold while the first chest is still out.
	var money_now := state.current_money
	state.add_money(PlayerState.TREASURE_MAP_PRICE)
	shop.open(state, player)
	var chest_id: int = chest.loot_id
	shop._buy(ShopUI.TREASURE_ROW)
	_check("no second map while a chest is buried",
		loot.active_treasure() != null and loot.active_treasure().loot_id == chest_id)
	_check("the refused second map costs nothing",
		is_equal_approx(state.current_money, money_now + PlayerState.TREASURE_MAP_PRICE))
	shop.close()

	# The map row must be the last of eight rows: detector, six shovels, map.
	_check("the shop builds eight rows",
		shop._row_names.size() == ShopUI.ROW_COUNT and ShopUI.TREASURE_ROW == 7)

	game.queue_free()
	await get_tree().create_timer(0.3).timeout


## --- Digging it out -------------------------------------------------------

func _check_dig_and_open() -> void:
	var game := await _spawn_beach()
	var terrain := game.get_node("SandTerrain") as SandTerrain
	var loot := game.get_node("LootManager") as LootManager
	var state := get_tree().get_first_node_in_group("player_state") as PlayerState
	state.equipment_tier_index = PlayerState.TREASURE_TIER_REQUIRED
	state.current_money = 5000.0
	state.buy_treasure_map()

	var chest = loot.spawn_treasure(PlayerState.TREASURE_FIRST_PAYOUT)
	var spot := Vector3(chest.buried_position.x, 0.0, chest.buried_position.z)
	var money_before := state.current_money
	var bag_before := state.carried_count()

	# Ordinary shallow digging must not open it: the chest sits far below the
	# reach of a couple of scoops.
	terrain.dig_at(spot, 0.7, 0.35)
	terrain.dig_at(spot, 0.7, 0.35)
	_check("a shallow hole does not uncover the chest", not chest.revealed)

	# Dig it out properly, with the shovel the map requires (Trench Spade): the
	# sand caves in, so reaching 4.6 m takes a long excavation, not three digs.
	var digs := 0
	while digs < 400 and not chest.revealed:
		terrain.dig_at(spot, 0.9, 0.3)
		digs += 1
	print("TREASURE chest uncovered after %d digs" % digs)
	_check("digging deep enough uncovers the chest", chest.revealed)
	var depth := terrain.get_height_at(spot)
	_check("the chest sits at the bottom of a real pit",
		depth <= -LootManager.TREASURE_DEPTH + 0.02)

	_check("an uncovered chest can be claimed", loot.take_loot(chest.loot_id, state.player_id))
	_check("the chest paid its payout into money",
		is_equal_approx(state.current_money - money_before, PlayerState.TREASURE_FIRST_PAYOUT))
	_check("the chest did not go into the bag", state.carried_count() == bag_before)
	_check("the find was counted", state.treasure_finds == 1)
	_check("no chest is left in the sand", not loot.has_treasure())
	_check("the chest is remembered as claimed",
		chest.loot_id in loot.export_snapshot()["claimed"])
	_check("no treasure is packed after the find",
		(loot.export_snapshot()["treasure"] as Dictionary).is_empty())

	# The next map is on offer again and rolls a normal payout.
	_check("the next map can be bought", state.can_buy_treasure_map())
	var second := state.next_treasure_payout(_rng())
	_check("later chests roll inside the normal band",
		second >= PlayerState.TREASURE_PAYOUT_MIN - 0.01
		and second <= PlayerState.TREASURE_PAYOUT_MAX + 0.01)
	state.treasure_finds = 0

	game.queue_free()
	await get_tree().create_timer(0.3).timeout


## --- Saved beach ----------------------------------------------------------

func _check_saved_chest() -> void:
	var game := await _spawn_beach()
	var terrain := game.get_node("SandTerrain") as SandTerrain
	var loot := game.get_node("LootManager") as LootManager
	var state := get_tree().get_first_node_in_group("player_state") as PlayerState
	state.current_money = 5000.0
	state.equipment_tier_index = PlayerState.TREASURE_TIER_REQUIRED
	state.buy_treasure_map()

	var chest = loot.spawn_treasure(1234.0)
	var chest_pos: Vector3 = chest.buried_position
	var chest_id: int = chest.loot_id
	var local_id := state.player_id
	var packed := loot.export_snapshot()
	_check("an unopened chest is written into the snapshot",
		not (packed["treasure"] as Dictionary).is_empty())
	_check("the snapshot keeps the chest position",
		(packed["treasure"]["pos"] as Vector3).distance_to(chest_pos) < 0.001)
	_check("an unopened chest is not in the claimed list",
		chest_id not in packed["claimed"])
	_check("the beach save succeeds",
		Profile.save_world(terrain.export_heights(), packed))

	# Simulate the restart: fresh beach, then the saved world on top.
	game.queue_free()
	await get_tree().create_timer(0.3).timeout
	var again := await _spawn_beach()
	var terrain2 := again.get_node("SandTerrain") as SandTerrain
	var loot2 := again.get_node("LootManager") as LootManager
	again._profile_enabled = true
	again._owns_world = true
	again._load_world()

	var restored = loot2.active_treasure()
	_check("the chest is still buried after a restart", restored != null)
	if restored != null:
		_check("the restored chest keeps its spot",
			restored.buried_position.distance_to(chest_pos) < 0.001)
		_check("the restored chest keeps its payout",
			is_equal_approx(restored.value, 1234.0))
		_check("the restored chest stays hidden",
			not restored.revealed and restored.depth > 4.0)
	_check("the restored world is still diggable",
		terrain2.heights.size() == SandTerrain.GRID_SIZE * SandTerrain.GRID_SIZE)

	# And a claimed chest must not come back.
	if restored != null:
		var spot2 := Vector3(restored.buried_position.x, 0.0, restored.buried_position.z)
		var digs2 := 0
		while digs2 < 260 and not restored.revealed:
			terrain2.dig_at(spot2, 0.9, 0.3)
			digs2 += 1
		loot2.take_loot(restored.loot_id, local_id)
		var after := loot2.export_snapshot()
		_check("an opened chest is not packed as treasure again",
			(after["treasure"] as Dictionary).is_empty())
		_check("an opened chest is packed as claimed",
			chest_id in after["claimed"])
	again.queue_free()
	await get_tree().create_timer(0.3).timeout


## --- Helpers --------------------------------------------------------------

func _spawn_beach() -> Node:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(0.3).timeout
	return game


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	return rng


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
