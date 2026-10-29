class_name LootManager
extends Node
## Loot: trash/scrap and gold rings, both buried and lying on the sand.
##
## Buried items are in the world from the start: they sit at their burial depth
## and the opaque sand surface above them hides them. Digging lowers that
## surface, so an item is uncovered gradually instead of popping into existence.
## Once the sand has been dug down to it the item is revealed (claimable) and it
## rests on / follows the new surface. Surface junk sits on top of the sand and
## follows the terrain down if a player digs underneath it.
##
## Claiming is first-come-first-served through take_loot(), which is the same
## contract the host will validate in Phase 3 (second claim is rejected).

signal loot_revealed(item: Dictionary)
signal loot_claimed(item: Dictionary)

const SIGNAL_RANGE := 8.0
## Signal falls off quadratically so the detector is only "hot" when you are
## nearly on top of something. A linear falloff over 8 m reads ~0.8 almost
## everywhere on a loot-dense beach, which made the beeps meaningless.
const SIGNAL_EXPONENT := 2.0

## Random scatter settings. Most junk is hidden under the sand; only a thin
## layer of litter is left lying on top of it.
const LOOT_COUNT := 200
const SURFACE_CHANCE := 0.06
const RING_CHANCE := 0.12
const SPAWN_RADIUS := 22.0
## Extra items scattered right around the spawn so the beach never looks empty.
const STARTER_COUNT := 10
const STARTER_MIN := 1.2
const STARTER_MAX := 7.5
const MIN_SPACING := 1.2
## When the sand above an item has been dug down to the item's centre it becomes
## claimable. Zero means "half of it is sticking out", so the [E] prompt never
## appears for something you cannot see yet.
const REVEAL_MARGIN := 0.0
const SPAWN_CLEAR := Vector2(0.0, 6.0)
const JUNKYARD_CLEAR := Vector2(2.6, 0.5)

const TRASH_NAMES := [
	"Rusty Can",
	"Plastic Bottle",
	"Old Boot",
	"Scrap Metal",
	"Broken Flip-Flop",
	"Fishing Net",
	"Tin Lid",
]

## Junk that a metal detector also reacts to. It is not the thing you are
## looking for, so it shows up as noise rather than as a clean reading.
const METAL_NAMES := ["Rusty Can", "Scrap Metal", "Tin Lid"]

## How hard metal clutter can wobble the detector reading (0..1 added jitter).
const NOISE_STRENGTH := 0.4
## Metal contributions are summed then divided by this, so a single can is a
## mild wobble and a scrapyard is a mess.
const NOISE_SOFT_CAP := 3.0

## One buried object. `buried_position` is on the surface (y ignored); `depth`
## is how far below the original surface it sits.
class LootItem:
	var loot_id: int = 0
	var kind: String = "trash"
	var display_name: String = "Rusty Can"
	var value: float = 10.0
	var buried_position := Vector3.ZERO
	var depth := 0.3
	var owner_id: int = 0
	var revealed := false
	var claimed := false
	## True for junk a metal detector also picks up (cans, scrap, tin lids).
	var metal := false
	## True for junk that spawns lying on the sand instead of buried in it.
	var on_surface := false
	var node: Node3D


var loot: Array[LootItem] = []

var _terrain: SandTerrain
var _player: PlayerState
var _root: Node3D
var _next_id := 1
var _materials: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _noise_rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("loot_manager")
	_terrain = get_tree().get_first_node_in_group("sand_terrain") as SandTerrain
	_root = Node3D.new()
	_root.name = "LootVisuals"
	add_child(_root)
	_spawn_loot()
	if _terrain != null:
		_terrain.dug.connect(_on_sand_dug)


## First claim wins. Returns false when the item is unknown, still buried, or
## already owned by another player.
func take_loot(loot_id: int, player_id: int) -> bool:
	var item := find_loot(loot_id)
	if item == null or item.claimed or not item.revealed:
		return false
	if item.owner_id != 0:
		return false
	item.owner_id = player_id
	item.claimed = true
	if _player == null:
		_player = get_tree().get_first_node_in_group("player_state") as PlayerState
	if _player != null:
		_player.add_loot({
			"id": item.loot_id,
			"name": item.display_name,
			"kind": item.kind,
			"value": item.value,
		})
	if item.node != null:
		item.node.queue_free()
		item.node = null
	print("[loot] claimed '%s' ($%d) by player %d" % [item.display_name, int(item.value), player_id])
	loot_claimed.emit(_describe(item))
	return true


func find_loot(loot_id: int) -> LootItem:
	for item in loot:
		if item.loot_id == loot_id:
			return item
	return null


## Nearest revealed, unclaimed item within `max_distance` (or null).
func nearest_claimable(from: Vector3, max_distance: float) -> LootItem:
	var best: LootItem = null
	var best_distance := max_distance
	for item in loot:
		if item.claimed or not item.revealed:
			continue
		var distance := from.distance_to(item.buried_position)
		if distance < best_distance:
			best_distance = distance
			best = item
	return best


## Closest unclaimed item (buried or on the surface), or null when empty.
func nearest_loot(from: Vector3) -> LootItem:
	var best: LootItem = null
	var best_distance := INF
	for item in loot:
		if item.claimed:
			continue
		var distance := from.distance_to(item.buried_position)
		if distance < best_distance:
			best_distance = distance
			best = item
	return best


## Closest item that is still hidden under the sand (not dug out, not claimed).
## Surface litter is excluded: the detector is for finding buried things, and
## beeping at junk you can already see just made the tool feel broken.
func nearest_hidden(from: Vector3) -> LootItem:
	var best: LootItem = null
	var best_distance := INF
	for item in loot:
		if item.claimed or item.revealed:
			continue
		var distance := from.distance_to(item.buried_position)
		if distance < best_distance:
			best_distance = distance
			best = item
	return best


func nearest_distance(from: Vector3) -> float:
	var item := nearest_hidden(from)
	if item == null:
		return INF
	return from.distance_to(item.buried_position)


## 0..1 detector reading for the closest hidden item, wobbled by metal clutter
## nearby. With no metal around it is a clean, deterministic reading.
func signal_strength(from: Vector3) -> float:
	var target := 0.0
	var distance := nearest_distance(from)
	if not is_inf(distance) and distance <= SIGNAL_RANGE:
		target = pow(1.0 - distance / SIGNAL_RANGE, SIGNAL_EXPONENT)

	var noise := metal_noise(from)
	if noise <= 0.0:
		return target
	var jitter := _noise_rng.randf_range(-1.0, 1.0) * noise * NOISE_STRENGTH
	return clampf(target + jitter, 0.0, 1.0)


## 0..1 amount of metal clutter within detector range. Surface and buried junk
## both count: a real detector does not care whether you can see the can.
func metal_noise(from: Vector3) -> float:
	var weight := 0.0
	for item in loot:
		if item.claimed or not item.metal:
			continue
		var distance := from.distance_to(item.buried_position)
		if distance >= SIGNAL_RANGE:
			continue
		weight += pow(1.0 - distance / SIGNAL_RANGE, SIGNAL_EXPONENT)
	return clampf(weight / NOISE_SOFT_CAP, 0.0, 1.0)


func _spawn_loot() -> void:
	_rng.randomize()
	_noise_rng.randomize()
	var placed: Array[Vector2] = []
	# Starter ring: junk is already lying around when the player spawns.
	for i in STARTER_COUNT:
		var starter := _starter_point()
		placed.append(starter)
		loot.append(_build_item(starter))

	var attempts := 0
	while loot.size() < LOOT_COUNT and attempts < LOOT_COUNT * 60:
		attempts += 1
		var point := _random_point()
		var too_close := false
		for other in placed:
			if other.distance_to(point) < MIN_SPACING:
				too_close = true
				break
		if too_close:
			continue
		placed.append(point)
		loot.append(_build_item(point))


func _starter_point() -> Vector2:
	var angle := _rng.randf() * TAU
	var radius := _rng.randf_range(STARTER_MIN, STARTER_MAX)
	var point := SPAWN_CLEAR + Vector2(cos(angle), sin(angle)) * radius
	if point.distance_to(JUNKYARD_CLEAR) < 2.2:
		point += Vector2(-1.6, 1.6)
	return point


## Uniform-ish scatter over the beach, kept clear of the spawn and the stall.
func _random_point() -> Vector2:
	var angle := _rng.randf() * TAU
	var radius := sqrt(_rng.randf()) * SPAWN_RADIUS + 1.2
	var point := Vector2(cos(angle), sin(angle)) * radius
	if point.distance_to(SPAWN_CLEAR) < 1.2:
		point += Vector2(1.4, -0.6)
	if point.distance_to(JUNKYARD_CLEAR) < 2.2:
		point += Vector2(-1.8, 1.8)
	point.x = clampf(point.x, -29.0, 29.0)
	point.y = clampf(point.y, -29.0, 29.0)
	return point


func _build_item(point: Vector2) -> LootItem:
	var item := LootItem.new()
	item.loot_id = _next_id
	_next_id += 1
	item.on_surface = _rng.randf() < SURFACE_CHANCE
	item.buried_position = Vector3(point.x, 0.0, point.y)

	# Gold rings only hide under the sand; surface junk is always scrap.
	var roll := _rng.randf()
	if not item.on_surface and roll < RING_CHANCE:
		item.kind = "ring"
		item.display_name = "Gold Ring"
		item.value = _rng.randf_range(80.0, 140.0)
		item.depth = _rng.randf_range(0.45, 0.75)
	else:
		item.kind = "trash"
		var trash_names := TRASH_NAMES
		item.display_name = trash_names[_rng.randi() % trash_names.size()]
		item.metal = item.display_name in METAL_NAMES
		item.value = _rng.randf_range(18.0, 40.0)
		item.depth = 0.0 if item.on_surface else _rng.randf_range(0.12, 0.65)

	item.node = _make_visual(item)
	if item.on_surface:
		item.revealed = true
		_place_on_surface(item)
	return item


## Puts a surface item back on top of the current sand height.
func _place_on_surface(item: LootItem) -> void:
	if item.node == null:
		return
	var height := 0.0
	if _terrain != null:
		height = _terrain.get_height_at(item.buried_position)
	item.node.position.y = height + 0.1
	item.node.visible = true


func _make_visual(item: LootItem) -> Node3D:
	var root := Node3D.new()
	root.name = "Loot%d" % item.loot_id
	root.position = Vector3(item.buried_position.x, -item.depth, item.buried_position.z)
	# Buried loot is always in the world; the sand surface above it is what
	# hides it. That way digging uncovers it instead of spawning it.
	root.visible = true
	# Surface junk reads better a little chunkier than a buried fragment.
	if item.on_surface:
		var size := 1.25 + float(item.loot_id % 6) * 0.07
		root.scale = Vector3(size, size, size)
	root.add_child(_make_piece(item))
	_root.add_child(root)
	return root


## Builds a recognisable bit of beach junk instead of a generic box.
func _make_piece(item: LootItem) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Piece"
	var label := item.display_name.to_lower()
	var tilt := float(item.loot_id * 29 % 360)
	var material_kind := "trash"

	if item.kind == "ring":
		var torus := TorusMesh.new()
		torus.inner_radius = 0.075
		torus.outer_radius = 0.13
		torus.rings = 20
		torus.ring_segments = 10
		mesh_instance.mesh = torus
		mesh_instance.rotation_degrees = Vector3(90.0, tilt, 0.0)
		material_kind = "ring"
	elif "bottle" in label:
		var bottle := CylinderMesh.new()
		bottle.top_radius = 0.03
		bottle.bottom_radius = 0.055
		bottle.height = 0.3
		mesh_instance.mesh = bottle
		mesh_instance.rotation_degrees = Vector3(0.0, tilt, 90.0)
		material_kind = "bottle"
	elif "can" in label:
		var can := CylinderMesh.new()
		can.top_radius = 0.058
		can.bottom_radius = 0.058
		can.height = 0.18
		mesh_instance.mesh = can
		mesh_instance.rotation_degrees = Vector3(0.0, tilt, 90.0)
		material_kind = "can"
	elif "boot" in label:
		var boot := BoxMesh.new()
		boot.size = Vector3(0.13, 0.12, 0.3)
		mesh_instance.mesh = boot
		mesh_instance.rotation_degrees = Vector3(0.0, tilt, -8.0)
		material_kind = "leather"
	elif "flip" in label:
		var sandal := BoxMesh.new()
		sandal.size = Vector3(0.09, 0.025, 0.26)
		mesh_instance.mesh = sandal
		mesh_instance.rotation_degrees = Vector3(0.0, tilt, 0.0)
		material_kind = "flipflop"
	elif "net" in label:
		var net := BoxMesh.new()
		net.size = Vector3(0.3, 0.02, 0.24)
		mesh_instance.mesh = net
		mesh_instance.rotation_degrees = Vector3(0.0, tilt, 4.0)
		material_kind = "net"
	elif "tin" in label:
		var lid := CylinderMesh.new()
		lid.top_radius = 0.1
		lid.bottom_radius = 0.1
		lid.height = 0.012
		mesh_instance.mesh = lid
		mesh_instance.rotation_degrees = Vector3(0.0, tilt, 0.0)
		material_kind = "tin"
	else:
		var scrap := BoxMesh.new()
		scrap.size = Vector3(0.24, 0.035, 0.18)
		mesh_instance.mesh = scrap
		mesh_instance.rotation_degrees = Vector3(0.0, tilt, 6.0)
		material_kind = "scrap"
	mesh_instance.material_override = _get_material(material_kind)
	return mesh_instance


func _get_material(kind: String) -> StandardMaterial3D:
	if _materials.has(kind):
		return _materials[kind]
	var material := StandardMaterial3D.new()
	match kind:
		"ring":
			material.albedo_color = Color(0.98, 0.78, 0.22)
			material.metallic = 0.9
			material.roughness = 0.22
		"bottle":
			material.albedo_color = Color(0.42, 0.72, 0.62)
			material.metallic = 0.0
			material.roughness = 0.35
		"can":
			material.albedo_color = Color(0.58, 0.32, 0.17)
			material.metallic = 0.25
			material.roughness = 0.7
		"tin":
			material.albedo_color = Color(0.74, 0.74, 0.7)
			material.metallic = 0.5
			material.roughness = 0.35
		"scrap":
			material.albedo_color = Color(0.33, 0.36, 0.4)
			material.metallic = 0.45
			material.roughness = 0.55
		"leather":
			material.albedo_color = Color(0.24, 0.16, 0.11)
			material.metallic = 0.0
			material.roughness = 0.9
		"flipflop":
			material.albedo_color = Color(0.86, 0.34, 0.28)
			material.metallic = 0.0
			material.roughness = 0.7
		"net":
			material.albedo_color = Color(0.8, 0.79, 0.71)
			material.metallic = 0.0
			material.roughness = 0.95
		_:
			material.albedo_color = Color(0.46, 0.28, 0.16)
			material.metallic = 0.2
			material.roughness = 0.8
	_materials[kind] = material
	return material


func _on_sand_dug(world_position: Vector3, radius: float, _depth: float) -> void:
	if _terrain == null:
		return
	for item in loot:
		if item.claimed:
			continue
		var flat := Vector2(
			item.buried_position.x - world_position.x,
			item.buried_position.z - world_position.z)
		if flat.length() > radius + 1.4:
			continue
		# Surface junk rides the sand down when someone digs under it.
		if item.on_surface:
			_place_on_surface(item)
			continue

		# Buried items sit still inside the sand until the surface drops past
		# them, then rest on the new surface. No pop-in, no floating: the sand
		# is simply removed from on top of them.
		var height := _terrain.get_height_at(item.buried_position)
		_set_buried_height(item, height)
		if not item.revealed and height <= -item.depth + REVEAL_MARGIN:
			_reveal(item, height)


## Keeps a buried item at its depth while the sand is still above it, and lets
## it settle onto the surface once the sand has been dug past it.
func _set_buried_height(item: LootItem, surface_height: float) -> void:
	if item.node == null:
		return
	item.node.position.y = minf(-item.depth, surface_height + 0.02)


func _reveal(item: LootItem, surface_height: float) -> void:
	item.revealed = true
	if item.node == null:
		return
	item.node.visible = true
	_set_buried_height(item, surface_height)

	var label := Label3D.new()
	label.text = "[E] %s" % item.display_name
	label.font_size = 40
	label.pixel_size = 0.0045
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(1.0, 0.95, 0.55)
	label.position = Vector3(0.0, 0.42, 0.0)
	item.node.add_child(label)

	print("[loot] revealed '%s' at %s" % [item.display_name, str(item.buried_position)])
	loot_revealed.emit(_describe(item))


func _describe(item: LootItem) -> Dictionary:
	return {
		"id": item.loot_id,
		"name": item.display_name,
		"kind": item.kind,
		"value": item.value,
		"owner": item.owner_id,
		"position": item.buried_position,
	}
