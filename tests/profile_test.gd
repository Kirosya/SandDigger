extends Node
## Profile persistence test.
##
## Uses a scratch file, never the real `user://profile.cfg`, and covers:
##   - a full round trip (write, load into a fresh PlayerState, all fields equal);
##   - a missing file and a corrupt file falling back to a fresh profile;
##   - level and tier being recomputed instead of trusted, so an edited file
##     cannot hand out an unearned shovel;
##   - the bag surviving a round trip, empty slots included.

const SCRATCH := "user://test_profile.cfg"

var _failures := 0


func _ready() -> void:
	Profile.path_override = SCRATCH
	Profile.clear()

	_check_round_trip()
	_check_missing_file()
	_check_corrupt_file()
	_check_unreadable_file()
	_check_derived_values()
	_check_bag()

	Profile.clear()
	Profile.path_override = ""
	print("PROFILE %s" % ("OK" if _failures == 0 else "FAILED (%d)" % _failures))
	await get_tree().create_timer(0.2).timeout
	get_tree().quit(0 if _failures == 0 else 1)


func _make_state() -> PlayerState:
	var state := PlayerState.new()
	state.tiers = EquipmentData.default_tiers()
	add_child(state)
	return state


func _check_round_trip() -> void:
	var state := _make_state()
	state.current_xp = 640.0
	state.current_money = 275.0
	state.equipment_tier_index = 2
	state.has_detector = true
	Profile.save_state(state)
	_check("file was written", FileAccess.file_exists(Profile.profile_path()))

	var loaded := _make_state()
	var ok := Profile.load_into(loaded)
	_check("load reports success", ok)
	_check("xp restored", is_equal_approx(loaded.current_xp, 640.0))
	_check("money restored", is_equal_approx(loaded.current_money, 275.0))
	_check("tier restored", loaded.equipment_tier_index == 2)
	_check("detector restored", loaded.has_detector)
	# 640 XP is level 4 on the 50 * n * (n-1) curve (level 4 starts at 600).
	_check("level derived from xp", loaded.current_level == 4)
	state.queue_free()
	loaded.queue_free()


func _check_missing_file() -> void:
	Profile.clear()
	var fresh := _make_state()
	var ok := Profile.load_into(fresh)
	_check("missing file loads nothing", not ok)
	_check("missing file leaves defaults", fresh.current_xp == 0.0
		and fresh.current_money == 0.0 and fresh.current_level == 1
		and fresh.equipment_tier_index == 0 and not fresh.has_detector)
	fresh.queue_free()


## A damaged file must not brick the game: valid INI, garbage values.
func _check_corrupt_file() -> void:
	var file := FileAccess.open(Profile.profile_path(), FileAccess.WRITE)
	file.store_string("[local]\nxp=\"banana\"\nmoney=-999\ntier=\"NaN\"\nhas_detector=7\nslots=99\n")
	file.close()
	var state := _make_state()
	Profile.load_into(state)
	_check("damaged file does not crash", true)
	_check("garbage xp falls back to a number", state.current_xp >= 0.0)
	_check("negative money is clamped", state.current_money >= 0.0)
	_check("garbage tier is clamped",
		state.equipment_tier_index >= 0 and state.equipment_tier_index < state.tiers.size())
	_check("level stays consistent with xp", state.current_level == _level_for(state.current_xp))
	_check("oversized slot count is ignored",
		state.bag_slots.size() == PlayerState.INVENTORY_SLOTS)
	state.queue_free()
	Profile.clear()


func _level_for(xp: float) -> int:
	var level := 1
	while xp >= PlayerState.xp_required_for_level(level + 1):
		level += 1
	return level


## A file that is not even INI must be refused outright.
func _check_unreadable_file() -> void:
	var file := FileAccess.open(Profile.profile_path(), FileAccess.WRITE)
	file.store_string("this is not a config file at all\n[[[ = = =")
	file.close()
	var state := _make_state()
	var ok := Profile.load_into(state)
	_check("unreadable file is refused", not ok)
	_check("unreadable file leaves defaults", state.current_xp == 0.0 and state.current_level == 1)
	state.queue_free()
	Profile.clear()


## Level is recomputed from XP and the tier is clamped, so a tampered file
## cannot grant progress the player did not earn.
func _check_derived_values() -> void:
	var config := ConfigFile.new()
	config.set_value(Profile.PROFILE_KEY, "xp", 0.0)
	config.set_value(Profile.PROFILE_KEY, "money", 0.0)
	config.set_value(Profile.PROFILE_KEY, "tier", 99)
	config.set_value(Profile.PROFILE_KEY, "has_detector", false)
	config.save(Profile.profile_path())

	var state := _make_state()
	Profile.load_into(state)
	_check("stale level is recomputed", state.current_level == 1)
	_check("wild tier is clamped to the last one",
		state.equipment_tier_index == state.tiers.size() - 1)
	state.queue_free()

	# And the other way round: enough XP for level 6 but an old tier on disk.
	config.set_value(Profile.PROFILE_KEY, "xp", PlayerState.xp_required_for_level(6))
	config.set_value(Profile.PROFILE_KEY, "tier", 0)
	config.save(Profile.profile_path())
	var leveled := _make_state()
	Profile.load_into(leveled)
	_check("level follows the xp on disk", leveled.current_level == 6)
	_check("tier stays what was bought", leveled.equipment_tier_index == 0)
	leveled.queue_free()
	Profile.clear()


func _check_bag() -> void:
	var state := _make_state()
	state.bag_slots[0] = {"id": 7, "name": "Gold Ring", "kind": "ring", "value": 120.0}
	state.bag_slots[3] = {"id": 9, "name": "Rusty Can", "kind": "trash", "value": 10.0}
	Profile.save_state(state)

	var loaded := _make_state()
	Profile.load_into(loaded)
	_check("bag keeps slot count", loaded.bag_slots.size() == PlayerState.INVENTORY_SLOTS)
	_check("bag item restored",
		str(loaded.bag_slots[0].get("name", "")) == "Gold Ring"
		and is_equal_approx(float(loaded.bag_slots[0].get("value", 0.0)), 120.0))
	_check("bag item keeps its slot", str(loaded.bag_slots[3].get("name", "")) == "Rusty Can")
	_check("empty slots stay empty",
		loaded.bag_slots[1].is_empty() and loaded.bag_slots[2].is_empty())
	_check("held slot starts empty-handed", loaded.held_slot == -1)
	state.queue_free()
	loaded.queue_free()


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
