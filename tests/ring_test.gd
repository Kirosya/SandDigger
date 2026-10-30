extends Node
## Gold ring notification test: uncovering a ring shows the big banner and the
## pickup prompt; ordinary trash keeps using the small flash line.

var _failures := 0


func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var loot := get_tree().get_first_node_in_group("loot_manager") as LootManager
	var hud := get_tree().get_first_node_in_group("hud") as Hud
	_check("world loaded", loot != null and hud != null)
	if loot == null or hud == null:
		_finish()
		return

	var ring: LootManager.LootItem = null
	var trash: LootManager.LootItem = null
	var antique: LootManager.LootItem = null
	for item in loot.loot:
		if item.revealed or item.claimed:
			continue
		if item.kind == "ring" and ring == null:
			ring = item
		elif item.kind == "antique" and antique == null:
			antique = item
		elif item.kind == "trash" and trash == null:
			trash = item
	_check("a buried ring exists", ring != null)
	_check("a buried trash item exists", trash != null)
	_check("a buried antique exists", antique != null)
	if ring == null or trash == null:
		_finish()
		return

	hud._banner.text = ""
	loot._reveal(ring, -0.25)
	await get_tree().process_frame
	_check("banner names the ring", "GOLD RING" in hud._banner.text)
	_check("banner shows the value", "$" in hud._banner.text)
	_check("flash asks to pick it up", "Press E" in hud._flash.text)
	_check("found chime is ready", hud._chime != null and hud._chime.stream != null)

	hud._banner.text = ""
	loot._reveal(trash, -0.25)
	await get_tree().process_frame
	_check("trash leaves the banner empty", hud._banner.text == "")
	_check("trash uses the flash line", "Uncovered" in hud._flash.text)

	if antique != null:
		hud._banner.text = ""
		loot._reveal(antique, -0.25)
		await get_tree().process_frame
		_check("the antique gets its own banner", "ANTIQUE" in hud._banner.text)
		_check("the antique banner shows its name",
			antique.display_name.to_upper() in hud._banner.text)
		_check("the antique banner shows the value", "$" in hud._banner.text)

	_finish()


func _finish() -> void:
	if _failures == 0:
		print("RING OK")
		get_tree().quit(0)
	else:
		print("RING FAILED (%d)" % _failures)
		get_tree().quit(1)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
