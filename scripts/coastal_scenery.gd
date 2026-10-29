class_name CoastalScenery
extends Node3D
## Dresses the three inland edges of the beach so the 64 m sand heightmap never
## ends in open sky, and so the sea is unmistakably on one side only:
##
##   +X  a dense tropical rainforest that keeps going into the distance
##   -X  a windfall barrier of fallen trunks, root balls, stumps and moss
##   +Z  a second windfall barrier closing the back of the beach
##
## The forest is deliberately lush: broadleaf crowns that overlap into a canopy,
## palms leaning over the sand, ferns and big-leaf plants underneath, and a
## hillside of canopy on all three inland sides so the horizon is green instead
## of empty. Distant crowns are drawn with MultiMeshes, so a whole jungle ridge
## costs a handful of draw calls.
##
## Everything is built from primitives at runtime (no imported assets) and is
## deterministic, so screenshots and tests always see the same coast. Invisible
## walls sit just behind the scenery so the player cannot walk off the sand.

## Half-extent of the sand heightmap (64 m / 2, minus half a cell).
const EDGE := 31.75

## The rainforest band on +X.
const FOREST_START_X := 19.5
const FOREST_END_X := 31.0
const FOREST_MIN_Z := -2.5
const FOREST_MAX_Z := 31.0

## The two windfall barriers.
const WEST_LOG_X := -25.0
const NORTH_LOG_Z := 25.0

const TREE_COUNT := 50
const PALM_COUNT := 18
const FERN_COUNT := 84
const BROADLEAF_COUNT := 62
const BUSH_COUNT := 44
const GRASS_COUNT := 90
const ROCK_COUNT := 20
const DRIFTWOOD_COUNT := 9
const STUMP_COUNT := 12
const DEAD_TREE_COUNT := 7
const DEBRIS_COUNT := 18
const BACKDROP_TREE_COUNT := 330
const CANOPY_BLOB_COUNT := 150
const CANOPY_UNDERSTORY_COUNT := 420

const BARK := Color(0.30, 0.22, 0.15)
const BARK_DARK := Color(0.19, 0.13, 0.08)
const CUT_WOOD := Color(0.56, 0.45, 0.29)
const DEAD_WOOD := Color(0.42, 0.37, 0.29)
const PALM_BARK := Color(0.45, 0.37, 0.25)
const LEAF_DARK := Color(0.08, 0.24, 0.10)
const LEAF_MID := Color(0.12, 0.33, 0.12)
const LEAF_LIGHT := Color(0.18, 0.41, 0.15)
const LEAF_SUN := Color(0.28, 0.46, 0.17)
const FERN_GREEN := Color(0.16, 0.40, 0.14)
const BROADLEAF_GREEN := Color(0.23, 0.46, 0.18)
const GRASS_GREEN := Color(0.42, 0.50, 0.24)
const VINE_GREEN := Color(0.18, 0.36, 0.12)
const MOSS := Color(0.27, 0.42, 0.13)
const ROCK := Color(0.37, 0.37, 0.35)
const FOREST_GREEN := Color(0.20, 0.33, 0.13)
const FOREST_DARK := Color(0.11, 0.19, 0.08)
const FOREST_EARTH := Color(0.36, 0.28, 0.17)
const BACKDROP_SAND := Color(0.52, 0.44, 0.30)

var _materials: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _forest: Node3D
var _undergrowth: Node3D
var _windfall: Node3D
var _backdrop: Node3D
var _backdrop_forest: Node3D
var _tree_index := 0


func _ready() -> void:
	add_to_group("coastal_scenery")
	_rng.seed = 20261029
	_build_backdrop()
	_build_backdrop_forest()
	_build_rainforest()
	_build_undergrowth()
	_build_windfall()
	_build_boundaries()


## --- Backdrop -------------------------------------------------------------

## A gently rising, forest-coloured ground mesh beyond the sand. Without it the
## heightmap edge would be a hard cut against the sky on the inland sides.
##
## The sand's own footprint is left completely EMPTY. A ground plane under the
## diggable sand would sit only 10 cm below it, so the moment a hole was carved
## deeper than that the plane showed through as a flat, hard-edged patch at the
## bottom of the hole -- it read as "the sand stops here" even though the
## heightmap kept going down to MAX_DEPTH. Three patches are built around the
## footprint instead, meeting the sand exactly at its edge.
func _build_backdrop() -> void:
	_backdrop = Node3D.new()
	_backdrop.name = "Backdrop"
	add_child(_backdrop)

	var step := 4.0
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	# West of the sand, east of it, and behind it. Between them the heightmap
	# owns the ground, so nothing is drawn under the beach.
	_add_backdrop_patch(vertices, normals, colors, indices,
		-120.0, -EDGE, 0.0, 120.0, step)
	_add_backdrop_patch(vertices, normals, colors, indices,
		EDGE, 120.0, 0.0, 120.0, step)
	_add_backdrop_patch(vertices, normals, colors, indices,
		-EDGE, EDGE, EDGE, 120.0, step)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.metallic = 0.0
	mesh.surface_set_material(0, material)

	var instance := MeshInstance3D.new()
	instance.name = "BackdropGround"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_backdrop.add_child(instance)


## Appends one rectangular piece of backdrop to the shared arrays. Both edges are
## kept exactly on `from`/`to` so a patch can butt up against the sand heightmap
## without a gap or an overhang.
func _add_backdrop_patch(vertices: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, indices: PackedInt32Array,
		x_min: float, x_max: float, z_min: float, z_max: float, step: float) -> void:
	var xs := _axis_values(x_min, x_max, step)
	var zs := _axis_values(z_min, z_max, step)
	var base := vertices.size()

	for z in zs:
		for x in xs:
			vertices.append(Vector3(x, _backdrop_height(x, z), z))
			normals.append(_backdrop_normal(x, z, step))
			colors.append(_backdrop_color(x, z))

	var nx := xs.size()
	var nz := zs.size()
	for iz in nz - 1:
		for ix in nx - 1:
			var a := base + iz * nx + ix
			var b := a + 1
			var c := a + nx
			var d := c + 1
			indices.append(a)
			indices.append(b)
			indices.append(c)
			indices.append(b)
			indices.append(d)
			indices.append(c)


## Evenly spaced samples from `from` to `to`, both ends included.
func _axis_values(from: float, to: float, step: float) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	var spans := maxi(1, int(ceil(absf(to - from) / step)))
	var actual := (to - from) / float(spans)
	for i in spans + 1:
		values.append(from + actual * float(i))
	return values


func _backdrop_height(x: float, z: float) -> float:
	var edge := maxf(maxf(absf(x) - EDGE, z - EDGE), 0.0)
	var rise := smoothstep(0.0, 46.0, edge)
	var wave := sin(x * 0.085) * cos(z * 0.10) * 0.55 + sin(x * 0.19 + z * 0.13) * 0.28
	# Just under the sand at the seam so the two meshes meet without z-fighting,
	# then rising away from the beach. Never a plane under the beach itself:
	# _build_backdrop leaves the sand footprint empty.
	return -0.02 + rise * 3.6 + wave * rise * 1.1


func _backdrop_normal(x: float, z: float, step: float) -> Vector3:
	var dx := _backdrop_height(x + step, z) - _backdrop_height(x - step, z)
	var dz := _backdrop_height(x, z + step) - _backdrop_height(x, z - step)
	return Vector3(-dx, 2.0 * step, -dz).normalized()


func _backdrop_color(x: float, z: float) -> Color:
	var patch := 0.5 + 0.5 * sin(x * 0.31 + z * 0.23) * cos(x * 0.13 - z * 0.29)
	var color := FOREST_DARK.lerp(FOREST_GREEN, 0.3 + patch * 0.7)
	var earth := 0.5 + 0.5 * sin(x * 0.07 + 2.0) * cos(z * 0.05 - 1.0)
	color = color.lerp(FOREST_EARTH, earth * 0.45)
	# Fade into sand at the very edge so the heightmap cut is invisible.
	var edge := maxf(maxf(absf(x) - EDGE, z - EDGE), 0.0)
	var near := 1.0 - smoothstep(0.0, 5.5, edge)
	return color.lerp(BACKDROP_SAND, near * 0.55)


## Height a prop stands on: flat sand inside the heightmap, backdrop outside.
func _ground_height(x: float, z: float) -> float:
	if absf(x) <= EDGE and z <= EDGE and z >= -EDGE:
		return 0.0
	return _backdrop_height(x, z)


## --- Hillside jungle ------------------------------------------------------

## The forest does not stop at the sand: it climbs the rise on every inland
## side, so from the beach the horizon is a wall of leaves instead of sky.
## Every crown and trunk is a MultiMesh instance, so the whole ridge is cheap.
func _build_backdrop_forest() -> void:
	_backdrop_forest = Node3D.new()
	_backdrop_forest.name = "BackdropForest"
	add_child(_backdrop_forest)

	var crowns: Array = [[], [], [], []]
	var trunks: Array = []

	# Three ridges: east of the sand, west of it, and the long one behind.
	var ridges := [
		[Vector2(33.0, 116.0), Vector2(0.0, 74.0), 118],
		[Vector2(-116.0, -33.0), Vector2(0.0, 74.0), 118],
		[Vector2(-116.0, 116.0), Vector2(33.0, 116.0), 168],
	]
	for ridge in ridges:
		var x_range: Vector2 = ridge[0]
		var z_range: Vector2 = ridge[1]
		var count: int = ridge[2]
		for i in count:
			var x := _rng.randf_range(x_range.x, x_range.y)
			var z := _rng.randf_range(z_range.x, z_range.y)
			var height := _rng.randf_range(7.0, 16.0)
			if _rng.randf() < 0.15:
				height = _rng.randf_range(18.0, 27.0)
			_add_hillside_tree(x, z, height, crowns, trunks)

	# A low understory layer near the sand: saplings and big leaves filling the
	# gap between the forest floor and the high crowns, so the treeline reads as
	# layered jungle instead of a row of poles with hats on.
	for i in CANOPY_UNDERSTORY_COUNT:
		var x: float
		var z: float
		if i % 3 == 0:
			x = _rng.randf_range(33.0, 52.0)
			z = _rng.randf_range(0.0, 46.0)
		elif i % 3 == 1:
			x = _rng.randf_range(-52.0, -33.0)
			z = _rng.randf_range(0.0, 46.0)
		else:
			x = _rng.randf_range(-52.0, 52.0)
			z = _rng.randf_range(33.0, 52.0)
		var shade := _rng.randi() % 4
		var radius := _rng.randf_range(1.6, 3.4)
		crowns[shade].append(_crown_xform(
			Vector3(x, _backdrop_height(x, z) + _rng.randf_range(1.6, 5.5), z),
			radius, _rng.randf_range(0.6, 1.05)))

	# Extra crown blobs floating in the canopy to fill the gaps between trunks,
	# so no bare ground shows through the treeline.
	for i in CANOPY_BLOB_COUNT:
		var x: float
		var z: float
		if i % 3 == 0:
			x = _rng.randf_range(33.0, 104.0)
			z = _rng.randf_range(2.0, 64.0)
		elif i % 3 == 1:
			x = _rng.randf_range(-104.0, -33.0)
			z = _rng.randf_range(2.0, 64.0)
		else:
			x = _rng.randf_range(-104.0, 104.0)
			z = _rng.randf_range(34.0, 104.0)
		var shade := _rng.randi() % 4
		var radius := _rng.randf_range(2.4, 4.8)
		crowns[shade].append(_crown_xform(
			Vector3(x, _backdrop_height(x, z) + _rng.randf_range(6.0, 13.0), z),
			radius, _rng.randf_range(0.75, 1.2)))

	_add_multimesh(
		"BackdropTrunks", _unit_cylinder(6), trunks,
		_material("bark", BARK, 0.95))
	var shades := [LEAF_DARK, LEAF_MID, LEAF_LIGHT, LEAF_SUN]
	for i in 4:
		_add_multimesh(
			"BackdropCrowns%d" % i, _unit_sphere(8, 4), crowns[i],
			_material("leaf%d" % i, shades[i], 0.94))


func _add_hillside_tree(
		x: float, z: float, height: float, crowns: Array, trunks: Array) -> void:
	var base := Vector3(x, _backdrop_height(x, z) - 0.15, z)
	var trunk_h := height * 0.6
	var radius := height * 0.055
	trunks.append(Transform3D(
		Basis().scaled(Vector3(radius, trunk_h, radius)),
		base + Vector3(0.0, trunk_h * 0.5, 0.0)))

	var crown_r := height * 0.34
	for i in 4:
		var angle := _rng.randf() * TAU
		var dist := _rng.randf_range(0.0, crown_r * 0.8)
		var lobe_r := crown_r * _rng.randf_range(0.62, 1.1)
		var shade := _rng.randi() % 4
		crowns[shade].append(_crown_xform(
			base + Vector3(
				cos(angle) * dist,
				trunk_h + _rng.randf_range(-0.3, 1.4),
				sin(angle) * dist),
			lobe_r, _rng.randf_range(0.7, 1.35)))


func _unit_cylinder(segments: int) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.75
	mesh.bottom_radius = 1.0
	mesh.height = 1.0
	mesh.radial_segments = segments
	mesh.rings = 2
	return mesh


func _unit_sphere(segments: int, rings: int) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = segments
	mesh.rings = rings
	return mesh


func _crown_xform(center: Vector3, radius: float, squash: float) -> Transform3D:
	return Transform3D(
		Basis().scaled(Vector3(radius, radius * squash, radius)), center)


func _add_multimesh(
		node_name: String, mesh: Mesh, transforms: Array, material: Material) -> void:
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	var origins := PackedVector3Array()
	origins.resize(transforms.size())
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		origins[i] = transforms[i].origin
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The dummy renderer used by headless tests keeps no instance buffer, so the
	# origins are mirrored here for the test to inspect.
	instance.set_meta("origins", origins)
	_backdrop_forest.add_child(instance)


## --- Rainforest -----------------------------------------------------------

func _build_rainforest() -> void:
	_forest = Node3D.new()
	_forest.name = "Forest"
	add_child(_forest)

	# Big broadleaf trees inside the sand band. Placement is biased toward the
	# back of the band so the crowns overlap into a canopy wall.
	var placed: Array[Vector2] = []
	var attempts := 0
	while placed.size() < TREE_COUNT and attempts < TREE_COUNT * 60:
		attempts += 1
		var point := Vector2(
			FOREST_START_X + pow(_rng.randf(), 0.5) * (FOREST_END_X - FOREST_START_X),
			_rng.randf_range(FOREST_MIN_Z, FOREST_MAX_Z))
		var too_close := false
		for other in placed:
			if other.distance_to(point) < 1.9:
				too_close = true
				break
		if too_close:
			continue
		placed.append(point)
		var tree := _make_jungle_tree(_rng.randf_range(7.0, 12.5))
		tree.name = "JungleTree%d" % _tree_index
		_tree_index += 1
		tree.position = Vector3(point.x, _ground_height(point.x, point.y) - 0.08, point.y)
		tree.rotation.y = _rng.randf() * TAU
		_forest.add_child(tree)

	# Palms stand in front of the treeline and lean over the sand, which is what
	# makes the coast read tropical instead of just wooded.
	for i in PALM_COUNT:
		var point := Vector2(
			_rng.randf_range(15.5, 20.5),
			_rng.randf_range(FOREST_MIN_Z, FOREST_MAX_Z))
		var palm := _make_palm(_rng.randf_range(6.0, 9.5))
		palm.name = "Palm%d" % i
		palm.position = Vector3(point.x, _ground_height(point.x, point.y) - 0.06, point.y)
		palm.rotation.y = _rng.randf() * TAU
		_forest.add_child(palm)


## A tall rainforest tree: flared roots, a leaning trunk, epiphytes on the
## trunk, a broad overlapping crown and a few vines hanging out of it.
func _make_jungle_tree(height: float) -> Node3D:
	var tree := Node3D.new()
	var trunk_h := height * _rng.randf_range(0.48, 0.6)
	var trunk_r := 0.15 + height * 0.022
	var lean := Vector3(_rng.randf_range(-0.5, 0.5), 0.0, _rng.randf_range(-0.5, 0.5))

	var trunk := MeshInstance3D.new()
	trunk.name = "Trunk"
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = trunk_r * 0.5
	trunk_mesh.bottom_radius = trunk_r
	trunk_mesh.height = trunk_h
	trunk_mesh.radial_segments = 8
	trunk_mesh.rings = 3
	trunk.mesh = trunk_mesh
	trunk.position = lean * 0.5 + Vector3(0.0, trunk_h * 0.5, 0.0)
	trunk.rotation = Vector3(lean.z * 0.05, 0.0, -lean.x * 0.05)
	trunk.material_override = _material("bark", BARK, 0.95)
	tree.add_child(trunk)

	# Buttress roots flaring out at the base.
	for i in 4 + _rng.randi() % 3:
		var angle := TAU * float(i) / 5.0 + _rng.randf() * 0.4
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var root := MeshInstance3D.new()
		var root_mesh := CylinderMesh.new()
		root_mesh.top_radius = trunk_r * 0.14
		root_mesh.bottom_radius = trunk_r * 0.55
		root_mesh.height = trunk_r * _rng.randf_range(3.0, 4.5)
		root_mesh.radial_segments = 5
		root.mesh = root_mesh
		root.basis = Basis(Quaternion(Vector3.UP, (dir + Vector3.UP * 0.5).normalized()))
		root.position = dir * root_mesh.height * 0.42 + Vector3(0.0, root_mesh.height * 0.16, 0.0)
		root.material_override = _material("bark", BARK, 0.95)
		tree.add_child(root)

	# A couple of limbs reaching into the crown.
	for i in 2 + _rng.randi() % 2:
		var angle := _rng.randf() * TAU
		var dir := Vector3(cos(angle), _rng.randf_range(0.35, 0.8), sin(angle)).normalized()
		var limb := MeshInstance3D.new()
		var limb_mesh := CylinderMesh.new()
		limb_mesh.top_radius = 0.03
		limb_mesh.bottom_radius = trunk_r * 0.4
		limb_mesh.height = _rng.randf_range(1.4, 2.6)
		limb_mesh.radial_segments = 5
		limb.mesh = limb_mesh
		limb.basis = Basis(Quaternion(Vector3.UP, dir))
		limb.position = Vector3(0.0, trunk_h * _rng.randf_range(0.7, 0.95), 0.0) \
			+ dir * limb_mesh.height * 0.5
		limb.material_override = _material("bark", BARK, 0.95)
		tree.add_child(limb)

	# Epiphytes: leaf clusters growing straight out of the trunk, which breaks
	# up the bare-pole look and fills the gap between ground and canopy.
	for i in 3 + _rng.randi() % 2:
		var angle := _rng.randf() * TAU
		var dir := Vector3(cos(angle), _rng.randf_range(-0.25, 0.45), sin(angle)).normalized()
		var clump := MeshInstance3D.new()
		var clump_mesh := SphereMesh.new()
		var clump_r := trunk_r * _rng.randf_range(2.0, 3.4)
		clump_mesh.radius = clump_r
		clump_mesh.height = clump_r * _rng.randf_range(0.5, 0.9)
		clump_mesh.radial_segments = 7
		clump_mesh.rings = 3
		clump.mesh = clump_mesh
		clump.basis = Basis(Quaternion(Vector3.UP, dir))
		clump.position = Vector3(0.0, trunk_h * _rng.randf_range(0.35, 0.75), 0.0) \
			+ dir * trunk_r * 1.4
		clump.material_override = _material(
			"epiphyte%d" % (i % 2), LEAF_MID if i % 2 == 0 else LEAF_DARK, 0.95)
		clump.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tree.add_child(clump)

	var crown_y := trunk_h * 0.98
	var crown_r := height * 0.36
	var lobes := 6 + _rng.randi() % 4
	for i in lobes:
		var lobe := MeshInstance3D.new()
		lobe.name = "Crown%d" % i
		var mesh := SphereMesh.new()
		var radius := crown_r * _rng.randf_range(0.62, 1.0)
		mesh.radius = radius
		mesh.height = radius * _rng.randf_range(0.9, 1.35)
		mesh.radial_segments = 8
		mesh.rings = 4
		lobe.mesh = mesh
		var angle := _rng.randf() * TAU
		var dist := _rng.randf_range(0.0, crown_r * 0.85)
		lobe.position = Vector3(
			cos(angle) * dist,
			crown_y + _rng.randf_range(-0.8, 1.4) + radius * 0.2,
			sin(angle) * dist)
		lobe.rotation.y = _rng.randf() * TAU
		lobe.material_override = _material(
			"leaf%d" % (i % 4), [LEAF_DARK, LEAF_MID, LEAF_LIGHT, LEAF_SUN][i % 4], 0.94)
		tree.add_child(lobe)

	# Vines hanging out of the crown.
	for i in 2 + _rng.randi() % 3:
		var vine := MeshInstance3D.new()
		var vine_mesh := CylinderMesh.new()
		vine_mesh.top_radius = 0.015
		vine_mesh.bottom_radius = 0.025
		vine_mesh.height = _rng.randf_range(1.6, 3.8)
		vine_mesh.radial_segments = 4
		vine.mesh = vine_mesh
		var angle := _rng.randf() * TAU
		var dist := _rng.randf_range(crown_r * 0.55, crown_r * 0.95)
		vine.position = Vector3(
			cos(angle) * dist, crown_y - vine_mesh.height * 0.5, sin(angle) * dist)
		vine.material_override = _material("vine", VINE_GREEN, 0.95)
		tree.add_child(vine)

	return tree


## A palm: a leaning segmented trunk, a crown of drooping fronds and coconuts.
func _make_palm(height: float) -> Node3D:
	var palm := Node3D.new()
	var segments := 4
	var segment_h := height / float(segments)
	var lean_dir := Vector3(
		_rng.randf_range(-0.5, 0.5), 0.0, _rng.randf_range(-0.5, 0.5)).normalized()
	var offset := Vector3.ZERO
	for i in segments:
		var seg := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.15 - 0.022 * float(i)
		mesh.bottom_radius = 0.16 - 0.022 * float(i)
		mesh.height = segment_h * 1.06
		mesh.radial_segments = 7
		seg.mesh = mesh
		offset += lean_dir * (float(i) / float(segments)) * 0.6
		seg.position = offset + Vector3(0.0, segment_h * (float(i) + 0.5), 0.0)
		seg.rotation = Vector3(lean_dir.z * 0.09, 0.0, -lean_dir.x * 0.09)
		seg.material_override = _material("palm_bark", PALM_BARK, 0.9)
		palm.add_child(seg)

	var crown := offset + Vector3(0.0, height, 0.0)
	for i in 7 + _rng.randi() % 3:
		var angle := TAU * float(i) / 8.0 + _rng.randf() * 0.3
		var dir := Vector3(cos(angle), _rng.randf_range(-0.65, -0.12), sin(angle)).normalized()
		var frond := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.44, 0.03, _rng.randf_range(2.1, 3.2))
		frond.mesh = mesh
		frond.basis = Basis(Quaternion(Vector3(0.0, 0.0, 1.0), dir))
		frond.position = crown + dir * mesh.size.z * 0.45
		frond.material_override = _material(
			"palm_leaf%d" % (i % 2), LEAF_LIGHT if i % 2 == 0 else LEAF_MID, 0.9)
		palm.add_child(frond)

	for i in 3:
		var coconut := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.12
		mesh.height = 0.22
		mesh.radial_segments = 6
		mesh.rings = 4
		coconut.mesh = mesh
		var angle := _rng.randf() * TAU
		coconut.position = crown + Vector3(cos(angle) * 0.16, -0.16, sin(angle) * 0.16)
		coconut.material_override = _material("coconut", Color(0.36, 0.26, 0.13), 0.95)
		palm.add_child(coconut)

	return palm


## --- Undergrowth ----------------------------------------------------------

func _build_undergrowth() -> void:
	_undergrowth = Node3D.new()
	_undergrowth.name = "Undergrowth"
	add_child(_undergrowth)

	for i in FERN_COUNT:
		var point := _edge_point(i, 0.0)
		var fern := _make_fern(_rng.randf_range(0.7, 1.6))
		fern.name = "Fern%d" % i
		fern.position = Vector3(point.x, _ground_height(point.x, point.y) - 0.03, point.y)
		fern.rotation.y = _rng.randf() * TAU
		_undergrowth.add_child(fern)

	for i in BROADLEAF_COUNT:
		var point := _edge_point(i, 1.0)
		var plant := _make_broadleaf(_rng.randf_range(0.6, 1.4))
		plant.name = "Broadleaf%d" % i
		plant.position = Vector3(point.x, _ground_height(point.x, point.y), point.y)
		plant.rotation.y = _rng.randf() * TAU
		_undergrowth.add_child(plant)

	for i in BUSH_COUNT:
		var point := _edge_point(i, 2.0)
		var bush := _make_bush(_rng.randf_range(0.4, 0.9))
		bush.name = "Bush%d" % i
		bush.position = Vector3(point.x, _ground_height(point.x, point.y) - 0.06, point.y)
		_undergrowth.add_child(bush)

	for i in ROCK_COUNT:
		var point := _edge_point(i, 3.0)
		var rock := _make_rock(_rng.randf_range(0.35, 0.95))
		rock.name = "Rock%d" % i
		rock.position = Vector3(point.x, _ground_height(point.x, point.y) - 0.12, point.y)
		_undergrowth.add_child(rock)

	# Grass tufts creeping onto the sand: they soften the hard line between the
	# beach and the jungle and keep the middle of the beach clear for digging.
	for i in GRASS_COUNT:
		var point := _beach_edge_point(i)
		var tuft := _make_grass_tuft(_rng.randf_range(0.25, 0.55))
		tuft.name = "Grass%d" % i
		tuft.position = Vector3(point.x, _ground_height(point.x, point.y), point.y)
		tuft.rotation.y = _rng.randf() * TAU
		_undergrowth.add_child(tuft)

	# Sun-bleached driftwood stranded near the waterline.
	for i in DRIFTWOOD_COUNT:
		var x := _rng.randf_range(-29.0, 28.0)
		var z := _rng.randf_range(-9.0, -6.5)
		var piece := _make_driftwood(
			_rng.randf_range(0.6, 1.6), _rng.randf_range(0.06, 0.12))
		piece.name = "Driftwood%d" % i
		piece.position = Vector3(x, 0.02, z)
		piece.rotation.y = _rng.randf() * TAU
		_undergrowth.add_child(piece)


## Picks a spot in the vegetation band that matches `lane`:
## 0 the +X jungle, 1 the -X windfall, 2 the +Z windfall, 3 any of them.
func _edge_point(index: int, lane: float) -> Vector2:
	var roll := index % 3
	if lane >= 2.5:
		roll = index % 3
	elif lane >= 1.5:
		roll = index % 2
	if roll == 0:
		return Vector2(
			_rng.randf_range(19.0, 31.0), _rng.randf_range(-2.0, 31.0))
	if roll == 1:
		return Vector2(
			_rng.randf_range(-30.0, -21.5), _rng.randf_range(-5.0, 30.5))
	return Vector2(
		_rng.randf_range(-30.0, 19.0), _rng.randf_range(21.0, 30.5))


## Grass only grows within a couple of metres of the treeline or the log piles.
func _beach_edge_point(index: int) -> Vector2:
	var roll := index % 4
	if roll == 0:
		return Vector2(_rng.randf_range(13.5, 19.5), _rng.randf_range(-2.0, 31.0))
	if roll == 1:
		return Vector2(_rng.randf_range(-24.0, -18.0), _rng.randf_range(-5.0, 30.5))
	if roll == 2:
		return Vector2(_rng.randf_range(-24.0, 17.0), _rng.randf_range(19.0, 24.0))
	return Vector2(_rng.randf_range(19.0, 30.0), _rng.randf_range(-2.0, 31.0))


func _make_fern(size: float) -> Node3D:
	var fern := Node3D.new()
	for i in 7:
		var angle := TAU * float(i) / 7.0 + _rng.randf() * 0.2
		var frond := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.10, 0.02, size * _rng.randf_range(0.8, 1.2))
		frond.mesh = mesh
		var dir := Vector3(
			cos(angle), _rng.randf_range(0.25, 0.55), sin(angle)).normalized()
		frond.basis = Basis(Quaternion(Vector3(0.0, 0.0, 1.0), dir))
		frond.position = dir * mesh.size.z * 0.45
		frond.material_override = _material("fern", FERN_GREEN, 0.95)
		frond.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fern.add_child(frond)
	return fern


func _make_broadleaf(size: float) -> Node3D:
	var plant := Node3D.new()
	for i in 4 + _rng.randi() % 3:
		var angle := TAU * float(i) / 5.0 + _rng.randf() * 0.3
		var leaf := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = size * _rng.randf_range(0.5, 0.8)
		mesh.height = mesh.radius * 0.16
		mesh.radial_segments = 7
		mesh.rings = 2
		leaf.mesh = mesh
		var dir := Vector3(
			cos(angle), _rng.randf_range(0.45, 0.95), sin(angle)).normalized()
		leaf.basis = Basis(Quaternion(Vector3.UP, dir))
		leaf.position = dir * size * 0.55 + Vector3(0.0, size * 0.3, 0.0)
		leaf.material_override = _material("broadleaf", BROADLEAF_GREEN, 0.9)
		leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plant.add_child(leaf)
	return plant


func _make_bush(size: float) -> Node3D:
	var bush := Node3D.new()
	var lobes := 2 + _rng.randi() % 2
	for i in lobes:
		var lobe := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = size * _rng.randf_range(0.7, 1.0)
		mesh.height = mesh.radius * _rng.randf_range(1.1, 1.5)
		mesh.radial_segments = 7
		mesh.rings = 4
		lobe.mesh = mesh
		lobe.position = Vector3(
			_rng.randf_range(-0.35, 0.35) * size,
			mesh.height * 0.35,
			_rng.randf_range(-0.35, 0.35) * size)
		lobe.material_override = _material(
			"bush%d" % (i % 2), LEAF_MID if i % 2 == 0 else LEAF_DARK, 0.95)
		lobe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bush.add_child(lobe)
	return bush


func _make_rock(size: float) -> MeshInstance3D:
	var rock := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 1.3
	mesh.radial_segments = 6
	mesh.rings = 3
	rock.mesh = mesh
	rock.scale = Vector3(1.0, 0.7, _rng.randf_range(0.8, 1.3))
	rock.rotation = Vector3(
		_rng.randf_range(-0.3, 0.3), _rng.randf() * TAU, _rng.randf_range(-0.3, 0.3))
	rock.material_override = _material("rock", ROCK, 0.95)
	return rock


func _make_grass_tuft(size: float) -> Node3D:
	var tuft := Node3D.new()
	for i in 5:
		var blade := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.06, size * _rng.randf_range(0.7, 1.4), 0.02)
		blade.mesh = mesh
		var angle := _rng.randf() * TAU
		var tilt := _rng.randf_range(0.12, 0.45)
		blade.rotation = Vector3(cos(angle) * tilt, _rng.randf() * TAU, sin(angle) * tilt)
		blade.position = Vector3(
			cos(angle) * size * 0.2, mesh.size.y * 0.42, sin(angle) * size * 0.2)
		blade.material_override = _material("grass", GRASS_GREEN, 0.95)
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tuft.add_child(blade)
	return tuft


func _make_driftwood(length: float, radius: float) -> Node3D:
	var piece := Node3D.new()
	var trunk := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.6
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 7
	mesh.rings = 2
	trunk.mesh = mesh
	trunk.rotation_degrees.x = 90.0
	trunk.rotation_degrees.z = _rng.randf_range(-4.0, 4.0)
	trunk.position.y = radius * 0.8
	trunk.material_override = _material("driftwood", Color(0.52, 0.47, 0.38), 0.98)
	piece.add_child(trunk)

	# Weathered knots rather than branch stubs, so it reads as a log on the sand
	# instead of something sticking out of it.
	for i in 2:
		var knot := MeshInstance3D.new()
		var knot_mesh := SphereMesh.new()
		knot_mesh.radius = radius * _rng.randf_range(1.1, 1.6)
		knot_mesh.height = knot_mesh.radius * 0.8
		knot_mesh.radial_segments = 6
		knot_mesh.rings = 3
		knot.mesh = knot_mesh
		knot.position = Vector3(
			0.0, radius * 1.1, _rng.randf_range(-length * 0.35, length * 0.35))
		knot.material_override = _material("driftwood", Color(0.52, 0.47, 0.38), 0.98)
		knot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piece.add_child(knot)
	return piece


## --- Windfall barriers ----------------------------------------------------

func _build_windfall() -> void:
	_windfall = Node3D.new()
	_windfall.name = "Windfall"
	add_child(_windfall)

	# West edge: two overlapping rows of trunks lying roughly north-south, root
	# balls facing the sea. The chain is continuous so it reads as a wall.
	for row in 2:
		var x := WEST_LOG_X - float(row) * 3.1
		var z := -7.0 + _rng.randf_range(0.0, 1.0)
		var index := 0
		while z < 31.0 and index < 14:
			var length := _rng.randf_range(4.6, 7.2)
			var radius := _rng.randf_range(0.22, 0.36)
			var log_node := _make_fallen_log(length, radius)
			log_node.name = "WestLog%d_%d" % [row, index]
			log_node.position = Vector3(
				x + _rng.randf_range(-0.5, 0.5), 0.0, z + length * 0.5)
			log_node.rotation.y = _rng.randf_range(-0.28, 0.28)
			if _rng.randf() < 0.2:
				log_node.rotation.y += _rng.randf_range(0.45, 0.85)
			_windfall.add_child(log_node)
			index += 1
			z += length * _rng.randf_range(0.42, 0.58)

	# North edge: the same treatment, trunks lying east-west.
	for row in 2:
		var z := NORTH_LOG_Z + float(row) * 3.1
		var x := -31.0 + _rng.randf_range(0.0, 1.0)
		var index := 0
		while x < 19.0 and index < 15:
			var length := _rng.randf_range(4.6, 7.2)
			var radius := _rng.randf_range(0.22, 0.36)
			var log_node := _make_fallen_log(length, radius)
			log_node.name = "NorthLog%d_%d" % [row, index]
			log_node.position = Vector3(
				x + length * 0.5, 0.0, z + _rng.randf_range(-0.5, 0.5))
			log_node.rotation.y = PI * 0.5 + _rng.randf_range(-0.28, 0.28)
			if _rng.randf() < 0.2:
				log_node.rotation.y += _rng.randf_range(0.45, 0.85)
			_windfall.add_child(log_node)
			index += 1
			x += length * _rng.randf_range(0.42, 0.58)

	# Trunks thrown on top of the piles so they read as a real tangle, not a row.
	for i in 7:
		var length := _rng.randf_range(4.0, 6.5)
		var radius := _rng.randf_range(0.18, 0.28)
		var log_node := _make_fallen_log(length, radius)
		log_node.name = "WestTopLog%d" % i
		log_node.position = Vector3(
			_rng.randf_range(-28.5, -24.0), _rng.randf_range(0.22, 0.5),
			_rng.randf_range(-2.0, 28.0))
		log_node.rotation.y = _rng.randf_range(-0.5, 0.5)
		log_node.rotation.x = _rng.randf_range(-0.12, 0.12)
		_windfall.add_child(log_node)

	for i in 6:
		var length := _rng.randf_range(4.0, 6.5)
		var radius := _rng.randf_range(0.18, 0.28)
		var log_node := _make_fallen_log(length, radius)
		log_node.name = "NorthTopLog%d" % i
		log_node.position = Vector3(
			_rng.randf_range(-26.0, 16.0), _rng.randf_range(0.22, 0.5),
			_rng.randf_range(25.5, 30.0))
		log_node.rotation.y = PI * 0.5 + _rng.randf_range(-0.5, 0.5)
		log_node.rotation.x = _rng.randf_range(-0.12, 0.12)
		_windfall.add_child(log_node)

	# Loose branches scattered in front of the piles.
	for i in DEBRIS_COUNT:
		if i % 2 == 0:
			_add_debris(
				_rng.randf_range(-24.0, -19.5), _rng.randf_range(-4.0, 28.0),
				_rng.randf_range(0.8, 2.2), _rng.randf_range(0.04, 0.09),
				"Debris%d" % i)
		else:
			_add_debris(
				_rng.randf_range(-24.0, 17.0), _rng.randf_range(20.5, 24.0),
				_rng.randf_range(0.8, 2.2), _rng.randf_range(0.04, 0.09),
				"Debris%d" % i)

	# Stumps poking out of the front of both barriers.
	for i in STUMP_COUNT:
		if i % 2 == 0:
			_add_stump(
				_rng.randf_range(-24.5, -21.5), _rng.randf_range(-5.0, 30.0),
				_rng.randf_range(0.35, 0.9), _rng.randf_range(0.28, 0.48),
				"Stump%d" % i)
		else:
			_add_stump(
				_rng.randf_range(-29.0, 18.0), _rng.randf_range(21.5, 24.5),
				_rng.randf_range(0.35, 0.9), _rng.randf_range(0.28, 0.48),
				"Stump%d" % i)

	# A few bare, dead trees leaning out of the tangle behind the logs.
	for i in DEAD_TREE_COUNT:
		var x := _rng.randf_range(-30.0, -24.0)
		var z := _rng.randf_range(2.0, 29.0)
		if i % 3 == 0:
			x = _rng.randf_range(-14.0, 16.0)
			z = _rng.randf_range(27.0, 30.5)
		_add_dead_tree(x, z, _rng.randf_range(3.4, 6.0), "DeadTree%d" % i)


func _make_fallen_log(length: float, radius: float) -> Node3D:
	var log_node := Node3D.new()

	# Trunk, lying along local Z.
	var trunk := MeshInstance3D.new()
	trunk.name = "Trunk"
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = radius * 0.78
	trunk_mesh.bottom_radius = radius
	trunk_mesh.height = length
	trunk_mesh.radial_segments = 9
	trunk_mesh.rings = 3
	trunk.mesh = trunk_mesh
	trunk.rotation_degrees.x = 90.0
	trunk.position.y = radius
	trunk.material_override = _material("bark", BARK, 0.95)
	log_node.add_child(trunk)

	# Lighter end grain where the trunk snapped off.
	var cut := MeshInstance3D.new()
	var cut_mesh := CylinderMesh.new()
	cut_mesh.top_radius = radius * 0.8
	cut_mesh.bottom_radius = radius * 0.8
	cut_mesh.height = 0.05
	cut_mesh.radial_segments = 9
	cut.mesh = cut_mesh
	cut.rotation_degrees.x = 90.0
	cut.position = Vector3(0.0, radius, length * 0.5)
	cut.material_override = _material("cut", CUT_WOOD, 0.95)
	log_node.add_child(cut)

	# Root ball with gnarled roots radiating out of it.
	var root := MeshInstance3D.new()
	root.name = "RootBall"
	var root_mesh := CylinderMesh.new()
	root_mesh.top_radius = radius * 2.4
	root_mesh.bottom_radius = radius * 2.0
	root_mesh.height = radius * 1.8
	root_mesh.radial_segments = 10
	root_mesh.rings = 2
	root.mesh = root_mesh
	root.rotation_degrees.x = 90.0
	root.position = Vector3(0.0, radius * 1.15, -length * 0.5 - radius * 0.3)
	root.material_override = _material("bark_dark", BARK_DARK, 0.98)
	log_node.add_child(root)

	for i in 7:
		var angle := TAU * float(i) / 7.0 + _rng.randf() * 0.35
		var dir := Vector3(cos(angle), sin(angle), _rng.randf_range(-0.3, 0.3)).normalized()
		var spike := MeshInstance3D.new()
		var spike_mesh := CylinderMesh.new()
		spike_mesh.top_radius = 0.0
		spike_mesh.bottom_radius = radius * 0.26
		spike_mesh.height = radius * _rng.randf_range(1.5, 2.4)
		spike_mesh.radial_segments = 5
		spike.mesh = spike_mesh
		spike.basis = Basis(Quaternion(Vector3.UP, dir))
		spike.position = Vector3(
			0.0, radius * 1.15, -length * 0.5 - radius * 0.3) + dir * spike_mesh.height * 0.45
		spike.material_override = _material("bark_dark", BARK_DARK, 0.98)
		log_node.add_child(spike)

	# Broken branch stubs along the trunk.
	for i in 2 + _rng.randi() % 2:
		var branch := MeshInstance3D.new()
		var branch_mesh := CylinderMesh.new()
		branch_mesh.top_radius = 0.03
		branch_mesh.bottom_radius = radius * 0.28
		branch_mesh.height = radius * _rng.randf_range(2.2, 4.0)
		branch_mesh.radial_segments = 5
		branch.mesh = branch_mesh
		var dir := Vector3(
			_rng.randf_range(-0.7, 0.7),
			_rng.randf_range(0.4, 1.0),
			_rng.randf_range(-0.4, 0.4)).normalized()
		branch.basis = Basis(Quaternion(Vector3.UP, dir))
		var along := _rng.randf_range(-length * 0.35, length * 0.4)
		branch.position = Vector3(0.0, radius, along) + dir * branch_mesh.height * 0.5
		branch.material_override = _material("bark", BARK, 0.95)
		log_node.add_child(branch)

	# Moss cushions on the sunny top of the trunk.
	for i in 2 + _rng.randi() % 2:
		var moss := MeshInstance3D.new()
		var moss_mesh := SphereMesh.new()
		moss_mesh.radius = radius * _rng.randf_range(0.55, 0.9)
		moss_mesh.height = moss_mesh.radius * 0.5
		moss_mesh.radial_segments = 7
		moss_mesh.rings = 3
		moss.mesh = moss_mesh
		moss.position = Vector3(
			_rng.randf_range(-0.1, 0.1), radius * 1.9,
			_rng.randf_range(-length * 0.35, length * 0.35))
		moss.material_override = _material("moss", MOSS, 0.95)
		moss.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		log_node.add_child(moss)

	# Solid enough that the pile actually blocks the player.
	var body := StaticBody3D.new()
	body.name = "Collision"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(radius * 2.2, radius * 2.2, length)
	shape.shape = box
	body.add_child(shape)
	body.position.y = radius
	log_node.add_child(body)
	return log_node


func _add_stump(x: float, z: float, height: float, radius: float, node_name: String) -> void:
	var stump := Node3D.new()
	stump.name = node_name
	stump.position = Vector3(x, _ground_height(x, z) - 0.05, z)
	stump.rotation.y = _rng.randf() * TAU
	stump.rotation.z = _rng.randf_range(-0.08, 0.08)

	var body := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.9
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	body.mesh = mesh
	body.position.y = height * 0.5
	body.material_override = _material("bark", BARK, 0.95)
	stump.add_child(body)

	var top := MeshInstance3D.new()
	var top_mesh := CylinderMesh.new()
	top_mesh.top_radius = radius * 0.9
	top_mesh.bottom_radius = radius * 0.9
	top_mesh.height = 0.04
	top_mesh.radial_segments = 8
	top.mesh = top_mesh
	top.position.y = height + 0.02
	top.material_override = _material("cut", CUT_WOOD, 0.95)
	stump.add_child(top)

	_windfall.add_child(stump)


func _add_debris(x: float, z: float, length: float, radius: float, node_name: String) -> void:
	var node := Node3D.new()
	node.name = node_name
	node.position = Vector3(x, _ground_height(x, z) + radius, z)
	node.rotation.y = _rng.randf() * TAU

	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.65
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 6
	mesh_instance.mesh = mesh
	mesh_instance.rotation_degrees.x = 90.0
	mesh_instance.material_override = _material("dead", DEAD_WOOD, 0.98)
	node.add_child(mesh_instance)
	_windfall.add_child(node)


func _add_dead_tree(x: float, z: float, height: float, node_name: String) -> void:
	var tree := Node3D.new()
	tree.name = node_name
	tree.position = Vector3(x, _ground_height(x, z) - 0.05, z)
	tree.rotation.y = _rng.randf() * TAU
	tree.rotation.z = _rng.randf_range(-0.07, 0.07)

	var trunk := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.07
	mesh.bottom_radius = 0.22
	mesh.height = height
	mesh.radial_segments = 7
	trunk.mesh = mesh
	trunk.position.y = height * 0.5
	trunk.material_override = _material("dead", DEAD_WOOD, 0.98)
	tree.add_child(trunk)

	for i in 4:
		var branch := MeshInstance3D.new()
		var branch_mesh := CylinderMesh.new()
		branch_mesh.top_radius = 0.015
		branch_mesh.bottom_radius = 0.06
		branch_mesh.height = _rng.randf_range(0.9, 1.9)
		branch_mesh.radial_segments = 5
		branch.mesh = branch_mesh
		var dir := Vector3(
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(0.3, 0.9),
			_rng.randf_range(-1.0, 1.0)).normalized()
		branch.basis = Basis(Quaternion(Vector3.UP, dir))
		var y := height * _rng.randf_range(0.45, 0.92)
		branch.position = Vector3(0.0, y, 0.0) + dir * branch_mesh.height * 0.5
		branch.material_override = _material("dead", DEAD_WOOD, 0.98)
		tree.add_child(branch)

	_windfall.add_child(tree)


## --- Boundaries -----------------------------------------------------------

## Invisible walls tucked behind the forest and the log piles so the player is
## stopped by the scenery instead of walking off the edge of the heightmap.
func _build_boundaries() -> void:
	var walls := StaticBody3D.new()
	walls.name = "Boundaries"
	add_child(walls)

	_add_wall(walls, Vector3(31.3, 3.0, 14.0), Vector3(0.6, 6.0, 37.0))
	_add_wall(walls, Vector3(-31.3, 3.0, 12.5), Vector3(0.6, 6.0, 43.0))
	_add_wall(walls, Vector3(0.0, 3.0, 31.3), Vector3(66.0, 6.0, 0.6))


func _add_wall(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	parent.add_child(body)


## --- Materials ------------------------------------------------------------

func _material(key: String, color: Color, roughness: float) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.0
	material.roughness = roughness
	_materials[key] = material
	return material
