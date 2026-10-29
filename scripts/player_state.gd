class_name PlayerState
extends Node
## Per-player progression state.
##
## One instance exists per player (1..4). Everything here is local to that
## player: XP, level, money and equipment tier are never shared. The host owns
## the authoritative instance for each player_id and will replicate the
## relevant fields to that peer in Phase 3; nothing in this script assumes a
## single global player.

signal xp_changed(current_xp: float, current_level: int)
signal money_changed(current_money: float)
signal equipment_changed(equipment: EquipmentData)
signal carried_changed(carried_count: int, carried_value: float)

## XP awarded per cubic metre of removed sand. Tunable balance knob.
const XP_PER_CUBIC_METER := 150.0

## Unique id assigned by the host when the player joins. 0 = offline/prototype.
@export var player_id: int = 0

## Lifetime XP earned from digging (never spent).
var current_xp: float = 0.0
## Level derived from current_xp; 1 = starting level.
var current_level: int = 1
## Money earned by selling trash/scrap. Unused in Phase 2.
var current_money: float = 0.0
## Index into `tiers`. Every player starts with the Teaspoon.
var equipment_tier_index: int = 0

## Ordered equipment chain for THIS player.
var tiers: Array[EquipmentData] = []

## Loot this player has claimed but not yet sold. Each entry is a Dictionary:
## { id: int, name: String, kind: String, value: float }.
var carried_loot: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("player_state")
	if tiers.is_empty():
		tiers = EquipmentData.default_tiers()
	equipment_tier_index = clampi(equipment_tier_index, 0, tiers.size() - 1)


## Adds sand volume removed by a dig and converts it to XP.
## Returns the XP gained by this call.
func add_dig_volume(volume_m3: float) -> float:
	if volume_m3 <= 0.0:
		return 0.0
	var gained := volume_m3 * XP_PER_CUBIC_METER
	current_xp += gained
	_refresh_level()
	xp_changed.emit(current_xp, current_level)
	return gained


## Total lifetime XP required to reach `level`. Level 1 starts at 0 XP.
static func xp_required_for_level(level: int) -> float:
	if level <= 1:
		return 0.0
	return 50.0 * float(level) * float(level - 1)


## XP still required to reach the next level.
func xp_to_next_level() -> float:
	return xp_required_for_level(current_level + 1) - current_xp


func _refresh_level() -> void:
	var new_level := 1
	while current_xp >= xp_required_for_level(new_level + 1):
		new_level += 1
	current_level = new_level


func add_money(amount: float) -> void:
	current_money = maxf(0.0, current_money + amount)
	money_changed.emit(current_money)


## True only when THIS player satisfies BOTH the level and money thresholds.
func can_upgrade_to(tier_index: int) -> bool:
	if tier_index < 0 or tier_index >= tiers.size():
		return false
	if tier_index <= equipment_tier_index:
		return false
	var tier := tiers[tier_index]
	return current_level >= tier.level_required and current_money >= tier.money_required


## Applies an upgrade if it is actually affordable; returns success.
func upgrade_to(tier_index: int) -> bool:
	if not can_upgrade_to(tier_index):
		return false
	equipment_tier_index = tier_index
	equipment_changed.emit(get_current_equipment())
	return true


func get_current_equipment() -> EquipmentData:
	if tiers.is_empty():
		tiers = EquipmentData.default_tiers()
	equipment_tier_index = clampi(equipment_tier_index, 0, tiers.size() - 1)
	return tiers[equipment_tier_index]


## Puts a claimed loot item in this player's bag.
func add_loot(item: Dictionary) -> void:
	carried_loot.append(item)
	carried_changed.emit(carried_loot.size(), carried_value())


## Total junkyard value of everything currently carried.
func carried_value() -> float:
	var total := 0.0
	for item in carried_loot:
		total += float(item.get("value", 0.0))
	return total


## Sells everything carried. Returns the money earned (0 when empty).
func sell_all() -> float:
	var earned := carried_value()
	if carried_loot.is_empty():
		return 0.0
	carried_loot.clear()
	add_money(earned)
	carried_changed.emit(0, 0.0)
	return earned


## Next tier this player could buy, or -1 when already maxed.
func next_tier_index() -> int:
	var next_index := equipment_tier_index + 1
	if next_index >= tiers.size():
		return -1
	return next_index


## Spends the tier's money cost and equips it. Requires BOTH thresholds.
func try_upgrade() -> bool:
	var next_index := next_tier_index()
	if next_index < 0 or not can_upgrade_to(next_index):
		return false
	var cost := tiers[next_index].money_required
	equipment_tier_index = next_index
	if cost > 0.0:
		add_money(-cost)
	equipment_changed.emit(get_current_equipment())
	return true
