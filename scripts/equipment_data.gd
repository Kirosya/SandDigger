class_name EquipmentData
extends Resource
## One tier of the digging equipment chain.
##
## A tier is unlocked only when BOTH the player's level and money thresholds are
## met (see PlayerState.can_upgrade_to). Radius/depth are in metres and decide
## how much sand a single dig removes, so every tier must feel physically
## different from the previous one. `reach` is how far the shovel can touch:
## a deep pit is dug from its rim, so a better shovel does not only take more
## sand per swing, it can also work further down.

@export var tier_index: int = 0
@export var display_name: String = "Teaspoon"
@export var level_required: int = 1
@export var money_required: float = 0.0
@export var radius: float = 0.15
@export var depth: float = 0.05
@export var reach: float = 3.6


static func create(p_index: int, p_name: String, p_level: int, p_money: float, p_radius: float, p_depth: float, p_reach: float) -> EquipmentData:
	var data := EquipmentData.new()
	data.tier_index = p_index
	data.display_name = p_name
	data.level_required = p_level
	data.money_required = p_money
	data.radius = p_radius
	data.depth = p_depth
	data.reach = p_reach
	return data


## The fixed progression chain. Ordered from weakest to strongest.
##
## The chain is deliberately long: the beach is eight metres deep now, so a hole
## that reaches the bottom is an excavation. Each step buys a wider bowl, a
## deeper bite and a longer reach, which together are what allows the next
## half metre of depth to hold. Sand also packs harder with depth, so a shovel
## only works at full strength on the surface.
static func default_tiers() -> Array[EquipmentData]:
	var tiers: Array[EquipmentData] = []
	tiers.append(create(0, "Teaspoon", 1, 0.0, 0.15, 0.05, 3.6))
	tiers.append(create(1, "Sand Shovel", 3, 50.0, 0.30, 0.10, 4.2))
	tiers.append(create(2, "Garden Shovel", 6, 180.0, 0.45, 0.15, 4.8))
	tiers.append(create(3, "Earth Shovel", 10, 500.0, 0.70, 0.22, 5.5))
	tiers.append(create(4, "Trench Spade", 14, 1100.0, 0.90, 0.30, 6.2))
	tiers.append(create(5, "Auger Shovel", 18, 2400.0, 1.15, 0.42, 6.8))
	tiers.append(create(6, "Dune Excavator", 24, 4500.0, 1.45, 0.58, 7.4))
	return tiers


## Name of the chain's last tier, for shop text that says "maxed".
static func max_tier_index() -> int:
	return 6


func describe() -> String:
	return "%s (Lv %d / $%d)" % [display_name, level_required, int(money_required)]
