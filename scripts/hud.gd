class_name Hud
extends CanvasLayer
## First-person HUD, built in code so the scene file stays readable.
##
## Shows level/XP, money, current equipment, carried loot, a crosshair, the
## contextual [E] prompt and short-lived flash messages. The metal detector is
## audio + a screen-edge colour wash: it beeps higher/louder and the edges glow
## cooler-to-hotter the closer the nearest junk is.
## Reads everything from PlayerState/LootManager groups, so it works unchanged
## when more players are added.

const GOLD := Color(1.0, 0.86, 0.42)

var _player: PlayerState
var _loot: LootManager

var _stats: Label
var _pocket: Label
var _crosshair: Label
var _prompt: Label
var _flash: Label

var _beep: AudioStreamPlayer
var _chime: AudioStreamPlayer
var _pings_left := 0
var _ping_timer := 0.0
var _detector_status: Label
var _status_text := ""

var _banner: Label
var _banner_tween: Tween

## Screen-edge wash that pulses with the detector beeps.
var _edge: TextureRect
var _edge_tween: Tween

var _flash_time := 0.0


func _ready() -> void:
	add_to_group("hud")
	layer = 10
	_build()
	await get_tree().process_frame
	_bind()


func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Detector edge wash is added first so every label draws on top of it.
	_build_edge_overlay(root)

	_stats = _make_label(22, Color.WHITE)
	_stats.name = "Stats"
	_stats.position = Vector2(24, 20)
	_stats.text = "Loading..."
	root.add_child(_stats)

	_pocket = _make_label(18, GOLD)
	_pocket.name = "Pocket"
	_pocket.position = Vector2(24, 116)
	root.add_child(_pocket)

	_detector_status = _make_label(16, Color(0.8, 0.86, 0.95, 0.85))
	_detector_status.name = "DetectorStatus"
	_detector_status.position = Vector2(24, 148)
	root.add_child(_detector_status)

	_crosshair = _make_label(26, Color(1, 1, 1, 0.85))
	_crosshair.name = "Crosshair"
	_crosshair.text = "+"
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crosshair.position += Vector2(-8, -18)
	root.add_child(_crosshair)

	_prompt = _make_label(22, Color.WHITE)
	_prompt.name = "Prompt"
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position += Vector2(-320, -190)
	_prompt.size = Vector2(640, 32)
	root.add_child(_prompt)

	_flash = _make_label(24, GOLD)
	_flash.name = "Flash"
	_flash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flash.set_anchors_preset(Control.PRESET_CENTER)
	_flash.position += Vector2(-320, 40)
	_flash.size = Vector2(640, 32)
	root.add_child(_flash)

	# Big "you found something special" banner, above the crosshair.
	_banner = _make_label(40, GOLD)
	_banner.name = "Banner"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.position += Vector2(-320, -170)
	_banner.size = Vector2(640, 60)
	_banner.pivot_offset = Vector2(320, 30)
	_banner.modulate.a = 0.0
	root.add_child(_banner)

	_build_detector_audio()

	var hint := _make_label(16, Color(1, 1, 1, 0.55))
	hint.name = "Hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position += Vector2(-320, -32)
	hint.size = Vector2(640, 24)
	hint.text = "Click: dig   E: pick up / sell   F: detector (15 s)   U: upgrade   Arrows: look   Esc: pause"
	root.add_child(hint)


## Builds a short sine "beep" in code, so the project needs no audio asset.
func _build_detector_audio() -> void:
	_beep = AudioStreamPlayer.new()
	_beep.name = "DetectorBeep"
	_beep.stream = _make_beep_stream()
	_beep.volume_db = -12.0
	add_child(_beep)

	_chime = AudioStreamPlayer.new()
	_chime.name = "FoundChime"
	_chime.stream = _make_chime_stream()
	_chime.volume_db = -7.0
	add_child(_chime)


## Two-tone rising chime played when a gold ring is uncovered.
func _make_chime_stream() -> AudioStreamWAV:
	var rate := 22050
	var seconds := 0.6
	var sample_count := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / float(rate)
		var envelope := exp(-5.5 * t)
		var sample := (sin(TAU * 1046.5 * t) + 0.7 * sin(TAU * 1568.0 * t)) * envelope * 0.45
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream


func _make_beep_stream() -> AudioStreamWAV:
	var rate := 22050
	var seconds := 0.075
	var sample_count := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for i in sample_count:
		var t := float(i) / float(rate)
		var envelope := sin(PI * float(i) / float(sample_count))
		var sample := sin(TAU * 900.0 * t) * envelope
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Full-screen radial wash that is transparent in the middle and solid at the
## edges, so a detector pulse reads as "the screen is glowing around me".
func _build_edge_overlay(root: Control) -> void:
	_edge = TextureRect.new()
	_edge.name = "DetectorEdge"
	_edge.texture = _make_edge_texture()
	_edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_edge.stretch_mode = TextureRect.STRETCH_SCALE
	_edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.modulate = Color(0.3, 0.62, 1.0, 0.0)
	root.add_child(_edge)


func _make_edge_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 0.78, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.35),
		Color(1.0, 1.0, 1.0, 1.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


## Cool blue when the nearest junk is far, hot red when it is underfoot.
func _strength_color(strength: float) -> Color:
	var s := clampf(strength, 0.0, 1.0)
	if s < 0.5:
		return Color(0.30, 0.62, 1.0).lerp(Color(0.35, 1.0, 0.45), s * 2.0)
	return Color(0.35, 1.0, 0.45).lerp(Color(1.0, 0.22, 0.12), (s - 0.5) * 2.0)


## Flashes the edge wash for one beep. Colour + brightness both follow strength.
func _pulse_edge(strength: float) -> void:
	if _edge == null:
		return
	var color := _strength_color(strength)
	var peak := 0.10 + 0.55 * clampf(strength, 0.0, 1.0)
	if _edge_tween != null and _edge_tween.is_valid():
		_edge_tween.kill()
	# Start from the current alpha so rapid beeps blend instead of flickering.
	_edge.modulate = Color(color.r, color.g, color.b, _edge.modulate.a)
	_edge_tween = create_tween()
	_edge_tween.tween_property(_edge, "modulate:a", peak, 0.05)
	_edge_tween.tween_property(_edge, "modulate:a", 0.0, 0.40) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player_state") as PlayerState
	_loot = get_tree().get_first_node_in_group("loot_manager") as LootManager
	if _player != null:
		_player.xp_changed.connect(_on_any_changed)
		_player.money_changed.connect(_on_money_changed)
		_player.equipment_changed.connect(_on_equipment_changed)
		_player.carried_changed.connect(_on_carried_changed)
	refresh()


func _process(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time -= delta
		_flash.modulate.a = clampf(_flash_time / 0.4, 0.0, 1.0)
		if _flash_time <= 0.0:
			_flash.text = ""

	if _pings_left > 0:
		_ping_timer -= delta
		if _ping_timer <= 0.0:
			_fire_ping()
			_pings_left -= 1
			_ping_timer = 0.13 if _pings_left > 0 else 0.0


func refresh() -> void:
	if _player == null:
		return
	var equipment := _player.get_current_equipment()
	var next_index := _player.next_tier_index()
	var xp_needed := PlayerState.xp_required_for_level(_player.current_level + 1)
	var next_line := "MAX TIER"
	if next_index >= 0:
		var tier := _player.tiers[next_index]
		next_line = "Next: %s  (Lv %d / $%d)" % [
			tier.display_name, tier.level_required, int(tier.money_required)]
	_stats.text = "\n".join([
		"Lv %d   $%d   %s" % [_player.current_level, int(_player.current_money), equipment.display_name],
		"XP %.0f / %d" % [_player.current_xp, int(xp_needed)],
		next_line,
	])
	_pocket.text = "Pocket: %d item(s)  $%d  %s" % [
		_player.carried_loot.size(), int(_player.carried_value()),
		"(sell at the junkyard)" if not _player.carried_loot.is_empty() else "",
	]


func show_prompt(text: String) -> void:
	_prompt.text = text


func flash(text: String) -> void:
	_flash.text = text
	_flash_time = 2.4
	_flash.modulate.a = 1.0


## Big gold banner + chime when a ring is uncovered. Wired from main.gd.
func announce_ring(display_name: String, value: int) -> void:
	_banner.text = "%s FOUND!    $%d" % [display_name.to_upper(), value]
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.modulate.a = 0.0
	_banner.scale = Vector2(0.7, 0.7)
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.15)
	_banner_tween.parallel().tween_property(_banner, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(1.7)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.5)
	if _chime != null:
		_chime.play()
	flash("Press E to take it before someone else does")


## One detector use = a short three-beep sweep. It never shows a distance or a
## direction: the beeps just get higher and louder the closer the nearest junk.
func ping_detector() -> void:
	_pings_left = 3
	_ping_timer = 0.0
	_fire_ping()
	_pings_left -= 1
	_ping_timer = 0.13


## Bottom-left status line driven by DigController (ready / recharging).
func set_detector_status(text: String) -> void:
	if text == _status_text:
		return
	_status_text = text
	_detector_status.text = text


## 0..1 reading of how close the nearest unclaimed junk is.
func detector_strength() -> float:
	if _loot == null:
		return 0.0
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return 0.0
	return _loot.signal_strength(player.global_position)


func _fire_ping() -> void:
	if _beep == null:
		return
	# Read the strength again for every beep: metal clutter nearby makes the
	# three beeps of one sweep disagree, which is exactly the "noisy" feel.
	var strength := detector_strength()
	# Close = high and loud; nothing in range = a dull, quiet thud.
	_beep.pitch_scale = lerpf(0.7, 2.2, strength)
	_beep.volume_db = lerpf(-20.0, -2.0, strength)
	_beep.play()
	# Same reading drives the screen-edge colour, so sound and colour agree.
	_pulse_edge(strength)


func _on_any_changed(_a: Variant, _b: Variant) -> void:
	refresh()


func _on_money_changed(_money: float) -> void:
	refresh()


func _on_equipment_changed(_equipment: EquipmentData) -> void:
	refresh()


func _on_carried_changed(_count: int, _value: float) -> void:
	refresh()
