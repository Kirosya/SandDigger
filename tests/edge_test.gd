extends Node
## Detector edge-wash test: the overlay must exist, run cool blue when the
## nearest junk is far and hot red when it is underfoot, and every detector ping
## must flash it before it fades back to transparent.

var _failures := 0


func _ready() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	var hud := get_tree().get_first_node_in_group("hud") as Hud
	_check("hud exists", hud != null)
	if hud == null:
		_finish()
		return

	var edge := hud.get_node_or_null("Root/DetectorEdge") as TextureRect
	_check("edge overlay exists", edge != null)
	if edge == null:
		_finish()
		return

	_check("overlay ignores the mouse", edge.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("overlay starts transparent", edge.modulate.a <= 0.001)

	# Colour ramp: blue far away -> green mid -> red underfoot.
	var far := hud._strength_color(0.0)
	var mid := hud._strength_color(0.5)
	var near := hud._strength_color(1.0)
	_check("far strength is blue", far.b > far.r and far.b > far.g)
	_check("mid strength is green", mid.g > mid.r and mid.g > mid.b)
	_check("near strength is red", near.r > near.g and near.r > near.b)

	# A strong ping flashes bright and takes the hot colour. Sampled 0.10 s in,
	# past the 0.05 s ramp: sampling at 0.06 s raced the tween on slow frames.
	hud._pulse_edge(1.0)
	await get_tree().create_timer(0.10).timeout
	var strong_alpha := edge.modulate.a
	_check("strong ping lights the edge", strong_alpha > 0.4)
	_check("strong ping uses the hot colour", edge.modulate.r > edge.modulate.g)
	await get_tree().create_timer(0.55).timeout
	_check("edge fades back to clear", edge.modulate.a <= 0.02)

	# A weak ping is a much dimmer wash.
	hud._pulse_edge(0.0)
	await get_tree().create_timer(0.10).timeout
	_check("weak ping is dimmer than strong", edge.modulate.a < strong_alpha * 0.5)

	# The real detector path (audio beep) must drive the overlay too.
	await get_tree().create_timer(0.55).timeout
	hud._fire_ping()
	await get_tree().create_timer(0.10).timeout
	_check("detector beep drives the edge", edge.modulate.a > 0.05)

	_finish()


func _finish() -> void:
	if _failures == 0:
		print("EDGE OK")
		get_tree().quit(0)
	else:
		print("EDGE FAILED (%d)" % _failures)
		get_tree().quit(1)


func _check(label: String, ok: bool) -> void:
	if not ok:
		_failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
