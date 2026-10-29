class_name PlayerState
extends Node
## Per-player progression state.
##
## One instance exists per player (1..4). Everything here is local to that
## player: XP, level, money, equipment tier, owned tools and the inventory are
## never shared. The host owns the authoritative instance for each player_id and
## will replicate the relevant fields to that peer in Phase 3; nothing in this
## script assumes a single global player.

signal xp_changed(current_xp: float, current_level: int)
signal money_changed(current_money: float)
signal equipment_changed(equipment: EquipmentData)
signal carried_changed(carried_count: int, carried_value: float)
## Emitted whenever the bag or the held slot changes, so the HUD can redraw.
signal inventory_changed(slots: Array[Dictionary], held_slot: int)
signal detector_changed(has_detector: bool)

## XP awarded per cubic metre of removed sand. Tunable balance knob.
const XP_PER_CUBIC_METER := 150.0

## The bag holds exactly this many loot items. Nothing stacks.
const INVENTORY_SLOTS := 7

## What the market charges for the metal detector.
const DETECTOR_PRICE := 35.0

## Unique id assigned by the host when the player joins. 0 = offline/prototype.
@export var player_id: int = 0

## Lifetime XP earned from digging (never spent).
var current_xp: float = 0.0
## Level derived from current_xp; 1 = starting level.
var current_level: int = 1
## Money earned by selling trash/scrap at the junkyard.
var current_money: float = 0.0
## Index into `tiers`. Every player starts with the Teaspoon.
var equipment_tier_index: int = 0
## True once the metal detector has been bought at the market.
var has_detector: bool = false

## Ordered equipment chain for THIS player.
var tiers: Array[EquipmentData] = []

## Loot this player has claimed but not yet sold. Each entry is a Dictionary:
## { id: int, name: String, kind: String, value: float }.
var carried_loot: Array[Dictionary] = []

## Which bag slot is held in hand. -1 means empty-handed (the tool is in hand).
var held_slot: int = -1


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


## --- Inventory ---------------------------------------------------------

func is_inventory_full() -> bool:
	return carried_loot.size() >= INVENTORY_SLOTS


## Puts a claimed loot item in the bag. Returns false when the bag is full.
func add_loot(item: Dictionary) -> bool:
	if is_inventory_full():
		return false
	carried_loot.append(item)
	_emit_inventory()
	return true


## The item currently held in hand, or {} when empty-handed.
func held_item() -> Dictionary:
	if held_slot < 0 or held_slot >= carried_loot.size():
		return {}
	return carried_loot[held_slot]


## Puts bag slot `index` in hand. Pressing the same slot again puts it away.
func set_held_slot(index: int) -> void:
	if index < 0 or index >= carried_loot.size():
		if held_slot != -1:
			held_slot = -1
			_emit_inventory()
		return
	held_slot = -1 if held_slot == index else index
	_emit_inventory()


## Sells ONLY the item in hand. Returns the sold item, or {} when empty-handed.
func sell_held() -> Dictionary:
	var item := held_item()
	if item.is_empty():
		return {}
	carried_loot.remove_at(held_slot)
	if carried_loot.is_empty():
		held_slot = -1
	else:
		held_slot = mini(held_slot, carried_loot.size() - 1)
	add_money(float(item.get("value", 0.0)))
	_emit_inventory()
	return item


## Total junkyard value of everything currently carried.
func carried_value() -> float:
	var total := 0.0
	for item in carried_loot:
		total += float(item.get("value", 0.0))
	return total


func _emit_inventory() -> void:
	carried_changed.emit(carried_loot.size(), carried_value())
	inventory_changed.emit(carried_loot, held_slot)


## --- Tools / upgrades --------------------------------------------------

## Buys the metal detector from the market.
func buy_detector() -> bool:
	if has_detector or current_money < DETECTOR_PRICE:
		return false
	add_money(-DETECTOR_PRICE)
	has_detector = true
	detector_changed.emit(true)
	return true


## Next tier this player could buy, or -1 when already maxed.
func next_tier_index() -> int:
	var next_index := equipment_tier_index + 1
	if next_index >= tiers.size():
		return -1
	return next_index


## Spends the tier's money cost and equips it. Requires BOTH thresholds.
func try_upgrade() -> bool:
	return buy_tier(equipment_tier_index + 1)


## Buys one specific tier from the market. Upgrades are sequential, so only the
## next tier in the chain can be bought.
func buy_tier(tier_index: int) -> bool:
	if tier_index != equipment_tier_index + 1:
		return false
	if not can_upgrade_to(tier_index):
		return false
	var cost := tiers[tier_index].money_required
	equipment_tier_index = tier_index
	if cost > 0.0:
		add_money(-cost)
	equipment_changed.emit(get_current_equipment())
	return true
