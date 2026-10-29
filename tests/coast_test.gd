extends Node
## Coast dressing test on the real main scene.
##
## Verifies the three inland edges are closed: a pine forest on +X, fallen-log
## windfalls on -X and +Z, a rising backdrop behind them, invisible boundary
## walls, and the terrain colours that blend the sand into each edge. Run:
##   godot --headless --path . res://tests/coast_test.tscn

var _failures := 0


func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().create_timer(0.4).timeout

	var terrain := get_tree().get_first_node_in_group("sand_terrain") as SandTerrain
	var scenery := get_tree().get_first_node_in_group("coastal_scenery") as CoastalScenery
	_check("main scene has coastal scenery", scenery != null)
	_check("main scene has the terrain", terrain != null)
	if scenery == null or terrain == null:
		_finish()
		return

	# --- Backdrop -----------------------------------------------------------
	var backdrop := scenery.get_node_or_null("Backdrop")
	var ground := backdrop.get_node_or_null("BackdropGround") as MeshInstance3D
	_check("scenery has a backdrop", backdrop != null and ground != null)
	if ground != null:
		_check("backdrop is a real mesh", ground.mesh != null and ground.mesh.get_surface_count() == 1)

		# The regression that made digging feel broken: a ground plane sitting
		# 10 cm under the sand. Any hole deeper than that showed it as a flat,
		# hard-edged patch in the bottom of the pit. No backdrop vertex may stand
		# over the sand heightmap's footprint.
		var verts := ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var inside := 0
		var furthest := 0.0
		for vertex in verts:
			if absf(vertex.x) < CoastalScenery.EDGE - 0.001 \
					and vertex.z < CoastalScenery.EDGE - 0.001:
				inside += 1
			furthest = maxf(furthest, maxf(absf(vertex.x), vertex.z))
		print("COAST backdrop_vertices=%d inside_sand=%d furthest=%.1f" % [
			verts.size(), inside, furthest])
		_check("backdrop never covers the diggable sand", inside == 0)
		_check("backdrop still closes the horizon", furthest > 90.0)
		_check("backdrop meets the sand at its edge, not below it",
			absf(scenery._backdrop_height(CoastalScenery.EDGE, 4.0)) < 0.05)

	# --- Forest on +X -------------------------------------------------------
	var forest := scenery.get_node_or_null("Forest")
	_check("scenery has a forest", forest != null)
	if forest != null:
		var trees := 0
		var palms := 0
		var palms_on_sand := 0
		var forest_side := true
		var sea_side := true
		for child in forest.get_children():
			var node_name := str(child.name)
			if node_name.begins_with("JungleTree"):
				trees += 1
				if child.position.x < CoastalScenery.FOREST_START_X - 0.6:
					forest_side = false
				if child.position.z < CoastalScenery.FOREST_MIN_Z - 0.6:
					sea_side = false
			elif node_name.begins_with("Palm"):
				palms += 1
				if child.position.x < CoastalScenery.FOREST_START_X:
					palms_on_sand += 1
		print("COAST jungle_trees=%d palms=%d palms_on_sand=%d" % [
			trees, palms, palms_on_sand])
		_check("the rainforest is dense", trees >= 40)
		_check("the beach edge has palms", palms >= 12)
		_check("palms stand in front of the treeline", palms_on_sand >= 6)
		_check("every jungle tree stands on the +X side", forest_side)
		_check("no jungle tree stands in the sea", sea_side)

	# --- Hillside jungle on all three inland sides --------------------------
	var backdrop_forest := scenery.get_node_or_null("BackdropForest")
	var crowns := 0
	var trunks := 0
	var east := false
	var west := false
	var north := false
	if backdrop_forest != null:
		for child in backdrop_forest.get_children():
			var instance := child as MultiMeshInstance3D
			if instance == null or instance.multimesh == null:
				continue
			var node_name := str(instance.name)
			if node_name.begins_with("BackdropCrowns"):
				crowns += instance.multimesh.instance_count
			elif node_name == "BackdropTrunks":
				trunks = instance.multimesh.instance_count
				var origins: PackedVector3Array = instance.get_meta(
					"origins", PackedVector3Array())
				for origin in origins:
					if origin.x > 33.0:
						east = true
					if origin.x < -33.0:
						west = true
					if origin.z > 33.0:
						north = true
	print("COAST backdrop_forest crowns=%d trunks=%d east=%s west=%s north=%s" % [
		crowns, trunks, str(east), str(west), str(north)])
	_check("the hillside jungle keeps going into the distance", crowns >= 900)
	_check("the hillside jungle has trunks", trunks >= 300)
	_check("the jungle climbs the east ridge", east)
	_check("the jungle climbs the west ridge", west)
	_check("the jungle climbs the back ridge", north)

	# --- Windfall on -X and +Z ---------------------------------------------
	var windfall := scenery.get_node_or_null("Windfall")
	_check("scenery has a windfall", windfall != null)
	if windfall != null:
		var west_logs := 0
		var north_logs := 0
		var stumps := 0
		var dead_trees := 0
		var west_ok := true
		var north_ok := true
		for child in windfall.get_children():
			var node_name := str(child.name)
			if node_name.begins_with("WestLog"):
				west_logs += 1
				if child.position.x > CoastalScenery.WEST_LOG_X + 1.0:
					west_ok = false
			elif node_name.begins_with("NorthLog"):
				north_logs += 1
				if child.position.z < CoastalScenery.NORTH_LOG_Z - 1.0:
					north_ok = false
			elif node_name.begins_with("Stump"):
				stumps += 1
			elif node_name.begins_with("DeadTree"):
				dead_trees += 1
		print("COAST west_logs=%d north_logs=%d stumps=%d dead=%d" % [
			west_logs, north_logs, stumps, dead_trees])
		_check("the west edge is closed with fallen trees", west_logs >= 14 and west_ok)
		_check("the back edge is closed with fallen trees", north_logs >= 14 and north_ok)
		_check("the windfall has stumps", stumps >= 8)
		_check("the windfall has dead trees", dead_trees >= 5)

	# --- Boundary walls -----------------------------------------------------
	var walls := scenery.get_node_or_null("Boundaries")
	var wall_count := 0
	if walls != null:
		for child in walls.get_children():
			if child is StaticBody3D and child.get_child_count() > 0:
				wall_count += 1
	print("COAST walls=%d" % wall_count)
	_check("invisible walls keep the player on the beach", wall_count >= 3)

	# --- Terrain colours blend into the edges ------------------------------
	var sand := terrain._color_at(0.0, 0.0, 6.0)
	var forest_floor := terrain._color_at(0.0, 27.0, 12.0)
	var litter := terrain._color_at(0.0, -27.0, 12.0)
	var wet := terrain._color_at(0.0, 0.0, -22.0)
	print("COAST colours sand=%s forest=%s litter=%s wet=%s" % [
		str(sand), str(forest_floor), str(litter), str(wet)])
	_check("the forest edge is greener than the sand",
		forest_floor.g / maxf(forest_floor.r, 0.001) > 1.0
		and sand.g / maxf(sand.r, 0.001) < 0.9)
	_check("the log barrier edge is earthy, not sand",
		litter.get_luminance() < sand.get_luminance() - 0.15)
	_check("the sand below the waterline is darker and wet",
		wet.get_luminance() < sand.get_luminance() - 0.08)

	# The colours must actually reach the terrain mesh, not just the helper.
	var painted_green := false
	var painted_dark := false
	for chunk in terrain._chunks:
		for color in chunk.colors:
			if color.g > color.r * 1.1 and color.g > 0.2:
				painted_green = true
			if color.get_luminance() < 0.3:
				painted_dark = true
	print("COAST mesh painted_green=%s painted_dark=%s" % [
		str(painted_green), str(painted_dark)])
	_check("the forest floor is painted into the sand mesh", painted_green)
	_check("the wet / deep sand is painted into the sand mesh", painted_dark)

	_finish()


func _finish() -> void:
	if _failures == 0:
		print("COAST OK")
		get_tree().quit(0)
	else:
		print("COAST FAILED (%d)" % _failures)
		get_tree().quit(1)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
