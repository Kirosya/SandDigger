extends Node
## Saves the local player's progress between sessions.
##
## The beach is regenerated on every launch, but a beachcomber's XP, money and
## equipment should survive. Only the state this machine owns is written: in
## multiplayer every peer keeps its own `PlayerState`, so saving on each machine
## is already the correct per-player behaviour and the host's world is untouched.
##
## The file is a plain ConfigFile at `user://profile.cfg`. One profile per
## machine for now; the key is a constant so a per-Steam-account profile is just
## a different key later (`steam_<id>`), with no format change.
##
## Loads are defensive: a missing, truncated or hand-edited file falls back to a
## fresh profile instead of blocking the game, and derived values (level, tier)
## are recomputed rather than trusted.

signal saved()

const PATH := "user://profile.cfg"
const PROFILE_KEY := "local"

## Tests point this at a scratch file so they never touch the real profile.
var path_override := ""

var _loaded := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func profile_path() -> String:
	return path_override if not path_override.is_empty() else PATH


## Fills `state` from disk. Safe to call on a fresh PlayerState; on a corrupt
## file the state is left at its defaults.
func load_into(state: PlayerState) -> bool:
	if state == null:
		return false
	var config := ConfigFile.new()
	if config.load(profile_path()) != OK:
		_loaded = true
		return false
	if not config.has_section(PROFILE_KEY):
		_loaded = true
		return false

	var section := PROFILE_KEY
	state.current_xp = maxf(0.0, float(config.get_value(section, "xp", 0.0)))
	state.current_money = maxf(0.0, float(config.get_value(section, "money", 0.0)))
	state.has_detector = bool(config.get_value(section, "has_detector", false))

	# Level and tier are derived, never trusted: a stale or edited file cannot
	# hand out a shovel the player did not earn.
	state.current_level = _level_for(state.current_xp)
	var tier := int(config.get_value(section, "tier", 0))
	state.equipment_tier_index = clampi(tier, 0, state.tiers.size() - 1)

	_read_bag(state, config)

	_loaded = true
	# Let the HUD redraw from the restored numbers.
	state.xp_changed.emit(state.current_xp, state.current_level)
	state.money_changed.emit(state.current_money)
	state.detector_changed.emit(state.has_detector)
	state.equipment_changed.emit(state.get_current_equipment())
	state.inventory_changed.emit(state.bag_slots, state.held_slot)
	state.carried_changed.emit(state.carried_count(), state.carried_value())
	return true


## Writes `state` to disk. Called on the events that actually change progress
## (sale, upgrade, level up, pickup), never per dug shovelful.
func save_state(state: PlayerState) -> void:
	if state == null:
		return
	var config := ConfigFile.new()
	var section := PROFILE_KEY
	config.set_value(section, "xp", state.current_xp)
	config.set_value(section, "money", state.current_money)
	config.set_value(section, "tier", state.equipment_tier_index)
	config.set_value(section, "has_detector", state.has_detector)
	config.set_value(section, "slots", state.bag_slots.size())
	for i in state.bag_slots.size():
		var slot: Dictionary = state.bag_slots[i]
		var prefix := "slot_%d_" % i
		config.set_value(section, prefix + "id", int(slot.get("id", 0)))
		config.set_value(section, prefix + "name", str(slot.get("name", "")))
		config.set_value(section, prefix + "kind", str(slot.get("kind", "trash")))
		config.set_value(section, prefix + "value", float(slot.get("value", 0.0)))
	var err := config.save(profile_path())
	if err != OK:
		push_warning("[profile] could not save %s (err %d)" % [profile_path(), err])
		return
	saved.emit()


## Wipes the saved progress (used by tests and, later, a "reset" button).
func clear() -> void:
	if FileAccess.file_exists(profile_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(profile_path()))
	_loaded = false


func has_profile() -> bool:
	return FileAccess.file_exists(profile_path())


func _read_bag(state: PlayerState, config: ConfigFile) -> void:
	state.ensure_bag()
	var slots := int(config.get_value(PROFILE_KEY, "slots", 0))
	for i in mini(slots, state.bag_slots.size()):
		var prefix := "slot_%d_" % i
		var name := str(config.get_value(PROFILE_KEY, prefix + "name", ""))
		if name.is_empty():
			state.bag_slots[i] = {}
			continue
		state.bag_slots[i] = {
			"id": int(config.get_value(PROFILE_KEY, prefix + "id", 0)),
			"name": name,
			"kind": str(config.get_value(PROFILE_KEY, prefix + "kind", "trash")),
			"value": float(config.get_value(PROFILE_KEY, prefix + "value", 0.0)),
		}
	state.held_slot = -1


## Level implied by a lifetime XP total. Kept in sync with
## PlayerState.xp_required_for_level, which is the single source of truth.
func _level_for(xp: float) -> int:
	var level := 1
	while xp >= PlayerState.xp_required_for_level(level + 1):
		level += 1
	return level
