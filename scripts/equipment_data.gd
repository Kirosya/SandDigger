class_name EquipmentData
extends Resource
## One tier of the digging equipment chain.
##
## A tier is unlocked only when BOTH the player's level and money thresholds are
## met (see PlayerState.can_upgrade_to). Radius/depth are in metres and decide
## how much sand a single dig removes, so every tier must feel physically
## different from the previous one.

@export var tier_index: int = 0
@export var display_name: String = "Teaspoon"
@export var level_required: int = 1
@export var money_required: float = 0.0
@export var radius: float = 0.15
@export var depth: float = 0.05


static func create(p_index: int, p_name: String, p_level: int, p_money: float, p_radius: float, p_depth: float) -> EquipmentData:
	var data := EquipmentData.new()
	data.tier_index = p_index
	data.display_name = p_name
	data.level_required = p_level
	data.money_required = p_money
	data.radius = p_radius
	data.depth = p_depth
	return data


## The fixed progression chain. Ordered from weakest to strongest.
static func default_tiers() -> Array[EquipmentData]:
	var tiers: Array[EquipmentData] = []
	tiers.append(create(0, "Teaspoon", 1, 0.0, 0.15, 0.05))
	tiers.append(create(1, "Sand Shovel", 3, 50.0, 0.30, 0.10))
	tiers.append(create(2, "Garden Shovel", 6, 200.0, 0.45, 0.15))
	tiers.append(create(3, "Earth Shovel", 10, 600.0, 0.70, 0.22))
	return tiers


func describe() -> String:
	return "%s (Lv %d / $%d)" % [display_name, level_required, int(money_required)]
