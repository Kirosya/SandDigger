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
signal detector_changed(detector_tier: int)
## Emitted when digging pushes this player past a level threshold.
signal leveled_up(new_level: int)
## Emitted when this player opens a buried treasure chest.
signal treasure_found(finds: int, payout: float)

## XP awarded per cubic metre of removed sand. Tunable balance knob.
const XP_PER_CUBIC_METER := 150.0

## The bag holds exactly this many loot items. Nothing stacks.
const INVENTORY_SLOTS := 7

## The hotbar is ONE row: the shovel (slot 0) and the detector (slot 1) are
## pinned to the front and can never be moved or swapped, then the bag slots
## follow. Number keys and the mouse wheel walk the whole row, so tools and loot
## are selected the same way.
const SLOT_SHOVEL := 0
const SLOT_DETECTOR := 1
const FIRST_BAG_SLOT := 2
const SLOT_COUNT := FIRST_BAG_SLOT + INVENTORY_SLOTS

## What the market charges for the first metal detector.
const DETECTOR_PRICE := 35.0

## --- Detector upgrades -----------------------------------------------------
##
## The detector is a one-shot sweep on a recharge. Upgrading it does not change
## what a sweep does, it makes waiting for the next one hurt less: a shorter
## recharge and a longer range, which matters now that loot hides metres down
## and the chest gives no marker at all.
##
## Index 0 is "not owned". Buying the detector is tier 1.
const DETECTOR_TIERS := [
	{"name": "No detector", "price": 0.0, "level": 1, "cooldown": 0.0, "range": 0.0},
	{"name": "Metal Detector", "price": 35.0, "level": 1, "cooldown": 15.0, "range": 8.0},
	{"name": "Ground Scanner", "price": 200.0, "level": 4, "cooldown": 11.0, "range": 10.0},
	{"name": "Pulse Inductor", "price": 600.0, "level": 10, "cooldown": 8.0, "range": 11.0},
	{"name": "Deep Sounder", "price": 1400.0, "level": 16, "cooldown": 6.0, "range": 12.0},
]

## --- The treasure hunt (endgame) -----------------------------------------
##
## The map puts a chest far under the sand and says nothing about where: no
## beacon, no marker, no distance. Finding it is the detector's real job, and
## the chest pays far more than the map costs. It is the one money sink that
## also gives the deep shovels a purpose, and it can be repeated, so digging
## never runs out of direction.
const TREASURE_MAP_PRICE := 500.0
## Tier index of the Trench Spade: only a shovel this good can dig a hole deep
## enough to reach a chest at TREASURE_DEPTH without the walls closing it.
const TREASURE_TIER_REQUIRED := 4
## Payout of the first chest ever opened by this profile; later ones are random.
const TREASURE_FIRST_PAYOUT := 2500.0
const TREASURE_PAYOUT_MIN := 1500.0
const TREASURE_PAYOUT_MAX := 2200.0

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
## Detector tier: 0 (none), 1 (bought), up to `DETECTOR_TIERS.size() - 1`.
var detector_tier: int = 0
## True once the metal detector has been bought (any tier).
var has_detector: bool:
	get:
		return detector_tier >= 1
## How many treasure chests this player has opened. Persisted, because the first
## find pays a fixed "legend" amount and the HUD likes to remember it.
var treasure_finds: int = 0

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

## Hotbar cursor: the slot the player has selected, 0..SLOT_COUNT-1. Slots 0 and
## 1 are the tools; every later index is a bag slot, and a bag slot may be empty.
## Selecting an empty slot means genuinely empty hands.
var selected_slot: int = SLOT_SHOVEL

## True when the selected bag slot still holds an item but the player pressed
## that same slot again to stow it. The hand is empty and the cursor stays put.
var _stowed := false

## Bag slot whose item is in hand, or -1 when nothing is in hand (a tool is in
## hand, or the selected bag slot is empty/stowed). Derived from selected_slot,
## so the hand and the highlighted slot can never disagree.
var held_slot: int:
	get:
		if _stowed:
			return -1
		var bag := bag_index_of(selected_slot)
		if bag < 0 or bag >= bag_slots.size():
			return -1
		if bag_slots[bag].is_empty():
			return -1
		return bag


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
## The slot index is kept for as long as the item is in the bag. If that free slot
## happens to be the one already selected, the item goes straight into the hand —
## the player is looking at that slot, so showing the pickup there is what they
## expect. On any other slot the hand is left alone (a tool stays a tool).
func add_loot(item: Dictionary) -> bool:
	_ensure_bag()
	for i in bag_slots.size():
		if bag_slots[i].is_empty():
			bag_slots[i] = item
			if i == bag_index_of(selected_slot):
				# Landed on the slot under the cursor: un-stow so it is visible in
				# hand immediately, without the player re-selecting the slot.
				_stowed = false
			_emit_inventory()
			return true
	return false


## The item currently held in hand, or {} when empty-handed.
func held_item() -> Dictionary:
	_ensure_bag()
	if held_slot < 0 or held_slot >= bag_slots.size():
		return {}
	return bag_slots[held_slot]


## Hotbar slot that is currently in hand. A held bag item always wins; otherwise
## it is the tool in hand. `detector_in_hand` comes from the player body, which
## owns the shovel/detector visual.
static func hotbar_index(held_slot: int, detector_in_hand: bool) -> int:
	if held_slot >= 0:
		return FIRST_BAG_SLOT + held_slot
	return SLOT_DETECTOR if detector_in_hand else SLOT_SHOVEL


## Bag index for a hotbar slot, or -1 for the two tool slots.
static func bag_index_of(hotbar: int) -> int:
	if hotbar < FIRST_BAG_SLOT:
		return -1
	return hotbar - FIRST_BAG_SLOT


## Number shown on a hotbar slot in the HUD (1-based, the key that selects it).
static func hotbar_number(hotbar: int) -> int:
	return hotbar + 1


## Puts bag slot `index` in hand. Pressing the same slot again stows the item and
## leaves the hand empty, but the hotbar cursor stays on that slot.
## Empty slots are selectable too: they simply mean empty hands.
func set_held_slot(index: int) -> void:
	if index < 0:
		put_away()
		return
	var bag := bag_index_of(selected_slot)
	if bag >= 0 and index == bag:
		# Already on this bag slot: toggle the item in and out of the hand.
		_stowed = not _stowed
		_emit_inventory()
		return
	select_slot(FIRST_BAG_SLOT + index)


## Moves the hotbar cursor. Pressing the already-selected filled bag slot again
## stows that item; the cursor stays there so selling or stowing leaves the
## player empty-handed on the slot they chose instead of jumping to another item.
func select_slot(index: int) -> void:
	_ensure_bag()
	index = clampi(index, 0, SLOT_COUNT - 1)
	var bag := bag_index_of(index)
	if index == selected_slot and bag >= 0 and not bag_slots[bag].is_empty():
		_stowed = not _stowed
	else:
		_stowed = false
	selected_slot = index
	_emit_inventory()


## Empties the hand without moving the cursor off a bag slot. From a tool slot
## this falls back to the shovel, which is the default hand.
func put_away() -> void:
	_ensure_bag()
	var bag := bag_index_of(selected_slot)
	if bag < 0:
		if selected_slot != SLOT_SHOVEL:
			select_slot(SLOT_SHOVEL)
		return
	if _stowed:
		return
	_stowed = true
	_emit_inventory()


## True when the selected slot is a bag slot with nothing to hold (empty, or the
## item there was stowed). The player is then unarmed: no digging, no detector.
func is_hand_empty() -> bool:
	return bag_index_of(selected_slot) >= 0 and held_slot < 0


## Sells ONLY the item in hand. Returns the sold item, or {} when empty-handed.
## The sold slot becomes empty and the cursor deliberately STAYS on it, so after
## a sale the player is empty-handed on that slot instead of jumping to the
## shovel or to another item.
func sell_held() -> Dictionary:
	var item := held_item()
	if item.is_empty():
		return {}
	bag_slots[held_slot] = {}
	_stowed = false
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

## Next detector tier this player could buy, or -1 when already maxed.
func next_detector_tier() -> int:
	var next := detector_tier + 1
	if next >= DETECTOR_TIERS.size():
		return -1
	return next


## The data block for a detector tier (empty dictionary for an invalid index).
static func detector_info(tier: int) -> Dictionary:
	if tier < 0 or tier >= DETECTOR_TIERS.size():
		return {}
	return DETECTOR_TIERS[tier]


## Seconds between detector sweeps at this player's current detector.
func detector_cooldown() -> float:
	return float(detector_info(detector_tier).get("cooldown", 0.0))


## How far a sweep can hear at this player's current detector.
func detector_range() -> float:
	return float(detector_info(detector_tier).get("range", 0.0))


## Display name of the detector in hand ("No detector" when unowned).
func detector_name() -> String:
	return str(detector_info(detector_tier).get("name", "No detector"))


## True when the next detector tier is affordable and unlocked.
func can_buy_detector() -> bool:
	var next := next_detector_tier()
	if next < 0:
		return false
	var info := detector_info(next)
	return current_level >= int(info["level"]) and current_money >= float(info["price"])


## Buys the next detector tier (the first purchase is the detector itself).
func buy_detector() -> bool:
	var next := next_detector_tier()
	if next < 0 or not can_buy_detector():
		return false
	var info := detector_info(next)
	add_money(-float(info["price"]))
	detector_tier = next
	detector_changed.emit(detector_tier)
	return true


## Next tier this player could buy, or -1 when already maxed.
func next_tier_index() -> int:
	var next_index := equipment_tier_index + 1
	if next_index >= tiers.size():
		return -1
	return next_index


## True when the treasure map is on offer: the shovel chain is finished and the
## player can afford one. Whether a map is already out on the beach is a world
## question, answered by LootManager.has_treasure().
func can_buy_treasure_map() -> bool:
	return equipment_tier_index >= TREASURE_TIER_REQUIRED \
		and current_money >= TREASURE_MAP_PRICE


## Buys a treasure map. Only spends the money; the shop then asks the world to
## put a chest on the beach.
func buy_treasure_map() -> bool:
	if not can_buy_treasure_map():
		return false
	add_money(-TREASURE_MAP_PRICE)
	return true


## Records an opened chest and its payout. Returns the new find count.
func register_treasure_find(payout: float) -> int:
	treasure_finds += 1
	add_money(payout)
	treasure_found.emit(treasure_finds, payout)
	return treasure_finds


## Payout of the next chest: the first one this profile finds is a fixed legend
## amount, everything after it rolls inside a band.
func next_treasure_payout(rng: RandomNumberGenerator) -> float:
	if treasure_finds == 0:
		return TREASURE_FIRST_PAYOUT
	return rng.randf_range(TREASURE_PAYOUT_MIN, TREASURE_PAYOUT_MAX)


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
