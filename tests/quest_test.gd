extends Node
## Story quest + gold ring test.
##
## Covers:
##   - the beach holds exactly one gold ring, and it is the deepest legendary find;
##   - the chain advances only on this player's claims, and only on findings that
##     match the open quest;
##   - every quest pays its money and XP exactly once;
##   - the last quest is the gold ring, and bringing it up finishes the story;
##   - a ring found before its quest is remembered, so the last quest can still
##     complete afterwards;
##   - the chain index, partial progress and the ring flag survive the profile.

const SCRATCH := "user://test_quest_profile.cfg"

var _failures := 0


func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var loot := get_tree().get_first_node_in_group("loot_manager") as LootManager
	var quests := get_tree().get_first_node_in_group("quests") as Quests
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	var state := Net.local_state()
	_check("world loaded", loot != null and quests != null and hud != null and state != null)
	if loot == null or quests == null or hud == null or state == null:
		_finish()
		return

	_check_ring(loot)
	_check_chain(loot, quests, hud, state)
	_check_early_ring(quests, state)
	_check_profile(state)

	_finish()


func _check_ring(loot: LootManager) -> void:
	var rings := 0
	for item in loot.loot:
		if item.kind == "ring":
			rings += 1
	_check("the beach has exactly one gold ring", rings == 1)

	var ring := loot.gold_ring()
	_check("a gold ring exists", ring != null)
	if ring == null:
		return
	_check("the ring is the legend item", ring.display_name == LootManager.RING_NAME)
	_check("the ring is worth a fortune",
		is_equal_approx(ring.value, LootManager.RING_VALUE))
	_check("the ring is deeper than any ordinary find", ring.depth >= 4.0)
	_check("the ring lies buried, not on the sand", not ring.on_surface)
	_check("the ring starts hidden below the surface",
		ring.node != null and ring.node.position.y <= -4.0)


func _check_chain(loot: LootManager, quests: Quests, hud: Hud, state: PlayerState) -> void:
	_check("the story starts at the first quest", quests.quest_index() == 0)
	_check("the first quest needs 3 finds", quests.current_quest()["count"] == 3)

	var money := state.current_money
	var xp := state.current_xp

	# Another player digging the same junk up must not move this player's chain.
	_claim(loot, "trash", "Old Boot", state.player_id + 1)
	_check("another player's find does not count", quests.quest_progress() == 0)

	_claim(loot, "trash", "Old Boot", state.player_id)
	_claim(loot, "trash", "Plastic Bottle", state.player_id)
	_check("first haul counts findings", quests.quest_progress() == 2)
	# Wrong kind for this quest: an antique is not junk.
	_claim(loot, "antique", "Carved Idol", state.player_id)
	_check("the wrong kind does not count", quests.quest_progress() == 2)

	hud._banner.text = ""
	_claim(loot, "trash", "Tin Lid", state.player_id)
	_check("the third find completes First Haul", quests.quest_index() == 1)
	_check("First Haul pays its money", is_equal_approx(state.current_money, money + 80.0))
	_check("First Haul pays its XP", is_equal_approx(state.current_xp, xp + 150.0))
	_check("the HUD announces the quest", "QUEST COMPLETE" in hud._banner.text)
	_check("the banner names the quest", "FIRST HAUL" in hud._banner.text)

	# Detector Practice wants metal junk only.
	money = state.current_money
	xp = state.current_xp
	_claim(loot, "trash", "Old Boot", state.player_id)
	_check("plain junk does not satisfy the metal quest", quests.quest_progress() == 0)
	_claim(loot, "trash", "Rusty Can", state.player_id)
	_claim(loot, "antique", "Bronze Lantern", state.player_id)
	_check("metal counts, antiques do not", quests.quest_progress() == 1)
	_claim(loot, "trash", "Scrap Metal", state.player_id)
	_check("metal practice completes", quests.quest_index() == 2)
	_check("metal practice pays", is_equal_approx(state.current_money, money + 160.0))
	_check("metal practice gives XP", is_equal_approx(state.current_xp, xp + 300.0))

	# The Deep Band: one antique.
	money = state.current_money
	xp = state.current_xp
	_claim(loot, "antique", "Antique Amphora", state.player_id)
	_check("the deep band completes on one antique", quests.quest_index() == 3)
	_check("the deep band pays", is_equal_approx(state.current_money, money + 450.0))
	_check("the deep band gives XP", is_equal_approx(state.current_xp, xp + 800.0))

	# Keeper of the Deep: three antiques.
	money = state.current_money
	xp = state.current_xp
	for i in 2:
		_claim(loot, "antique", "Carved Idol", state.player_id)
	_check("keeper counts antiques", quests.quest_index() == 3)
	_claim(loot, "antique", "Carved Idol", state.player_id)
	_check("keeper completes on the third antique", quests.quest_index() == 4)
	_check("keeper pays", is_equal_approx(state.current_money, money + 900.0))
	_check("keeper gives XP", is_equal_approx(state.current_xp, xp + 1500.0))

	_check("the last quest is the ring", quests.current_quest()["match"] == "ring")

	money = state.current_money
	xp = state.current_xp
	_claim(loot, "ring", LootManager.RING_NAME, state.player_id)
	_check("the gold ring finishes the story", quests.is_finished())
	_check("the ring is remembered", state.gold_ring_found)
	_check("the ring quest pays", is_equal_approx(state.current_money, money + 2500.0))
	_check("the ring quest gives XP", is_equal_approx(state.current_xp, xp + 5000.0))


## The ring is unique, so a player can find it before the last quest opens. That
## must not strand the chain: the flag settles the last quest when it comes up.
func _check_early_ring(quests: Quests, state: PlayerState) -> void:
	state.quest_index = 4
	state.quest_progress = 0
	state.gold_ring_found = true
	var money := state.current_money
	quests._sync_ring_quest()
	_check("an early ring find settles the last quest", quests.is_finished())
	_check("the early ring find pays once", is_equal_approx(state.current_money, money + 2500.0))
	# Settling again must not pay a second time.
	var again := state.current_money
	quests._sync_ring_quest()
	_check("the last quest cannot pay twice", is_equal_approx(state.current_money, again))


func _check_profile(state: PlayerState) -> void:
	Profile.path_override = SCRATCH
	Profile.clear()
	Profile.save_state(state)
	var fresh := PlayerState.new()
	fresh.tiers = EquipmentData.default_tiers()
	add_child(fresh)
	Profile.load_into(fresh)
	_check("the profile keeps the chain index", fresh.quest_index == state.quest_index)
	_check("the profile keeps partial progress", fresh.quest_progress == state.quest_progress)
	_check("the profile keeps the ring flag", fresh.gold_ring_found)
	Profile.clear()
	Profile.path_override = ""


## Emits a claim exactly the way LootManager does, so the quest listener is
## exercised through its real signal instead of a private shortcut.
func _claim(loot: LootManager, kind: String, display_name: String, owner: int) -> void:
	loot.loot_claimed.emit({
		"id": 1,
		"name": display_name,
		"kind": kind,
		"value": 10.0,
		"owner": owner,
		"position": Vector3.ZERO,
		"treasure": false,
	})


func _finish() -> void:
	if _failures == 0:
		print("QUEST OK")
		get_tree().quit(0)
	else:
		print("QUEST FAILED (%d)" % _failures)
		get_tree().quit(1)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
