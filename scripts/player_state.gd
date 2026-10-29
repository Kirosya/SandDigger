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
## Emitted when digging pushes this player past a level threshold.
signal leveled_up(new_level: int)

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

## Sparse bag: always INVENTORY_SLOTS entries in slot order. Each filled entry is
## a Dictionary { id, name, kind, value }; an empty slot is {}. Items NEVER shift
## between slots, so a sold item leaves its slot empty instead of pulling the
## later items forward.
var bag_slots: Array[Dictionary] = []

## Compact read-only view of the carried items (only the filled slots, in slot
## order). Handy for code that just wants to loop over what the player has.
var carried_loot: Array[Dictionary]:
	get:
		var items: Array[Dictionary] = []
		for slot in bag_slots:
			if not slot.is_empty():
				items.append(slot)
		return items

## Which bag slot is held in hand. -1 means empty-handed (the tool is in hand).
var held_slot: int = -1


func _ready() -> void:
	add_to_group("player_state")
	if tiers.is_empty():
		tiers = EquipmentData.default_tiers()
	equipment_tier_index = clampi(equipment_tier_index, 0, tiers.size() - 1)
	_ensure_bag()


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
	var previous := current_level
	var new_level := 1
	while current_xp >= xp_required_for_level(new_level + 1):
		new_level += 1
	current_level = new_level
	if current_level > previous:
		leveled_up.emit(current_level)


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

## Fills the bag with exactly INVENTORY_SLOTS empty slots. Called from _ready and
## lazily from the bag API so PlayerState also works before it enters the tree.
func _ensure_bag() -> void:
	while bag_slots.size() < INVENTORY_SLOTS:
		bag_slots.append({})
	if bag_slots.size() > INVENTORY_SLOTS:
		bag_slots.resize(INVENTORY_SLOTS)


## Public form of _ensure_bag, for code that fills the bag from outside (the
## profile loader restores saved items into slot order).
func ensure_bag() -> void:
	_ensure_bag()


## How many slots are actually filled.
func carried_count() -> int:
	var count := 0
	for slot in bag_slots:
		if not slot.is_empty():
			count += 1
	return count


func is_inventory_full() -> bool:
	return carried_count() >= INVENTORY_SLOTS


## Puts a claimed loot item in the first empty slot. Returns false when full.
## The slot index is kept for as long as the item is in the bag.
func add_loot(item: Dictionary) -> bool:
	_ensure_bag()
	for i in bag_slots.size():
		if bag_slots[i].is_empty():
			bag_slots[i] = item
			_emit_inventory()
			return true
	return false


## The item currently held in hand, or {} when empty-handed.
func held_item() -> Dictionary:
	_ensure_bag()
	if held_slot < 0 or held_slot >= bag_slots.size():
		return {}
	return bag_slots[held_slot]


## Puts bag slot `index` in hand. Pressing the same slot again puts it away.
## Empty slots cannot be held.
func set_held_slot(index: int) -> void:
	_ensure_bag()
	if index < 0 or index >= bag_slots.size() or bag_slots[index].is_empty():
		if held_slot != -1:
			held_slot = -1
			_emit_inventory()
		return
	held_slot = -1 if held_slot == index else index
	_emit_inventory()


## Sells ONLY the item in hand. Returns the sold item, or {} when empty-handed.
## The sold item's slot becomes empty and stays empty: the other items keep the
## slots they were picked up into.
func sell_held() -> Dictionary:
	var item := held_item()
	if item.is_empty():
		return {}
	bag_slots[held_slot] = {}
	held_slot = -1
	add_money(float(item.get("value", 0.0)))
	_emit_inventory()
	return item


## Total junkyard value of everything currently carried.
func carried_value() -> float:
	var total := 0.0
	for slot in bag_slots:
		if not slot.is_empty():
			total += float(slot.get("value", 0.0))
	return total


func _emit_inventory() -> void:
	carried_changed.emit(carried_count(), carried_value())
	inventory_changed.emit(bag_slots, held_slot)


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
