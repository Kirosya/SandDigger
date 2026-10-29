class_name ShopUI
extends CanvasLayer
## The market panel: buy the metal detector and the next shovel upgrade.
##
## Pauses the tree while it is open (like the pause menu) so the player cannot
## walk around behind the panel. Keys 1-4 buy, E or Esc closes. Prices and
## requirements are read from PlayerState, so this works unchanged per player.

const GOLD := Color(1.0, 0.86, 0.42)
const GREEN := Color(0.5, 0.95, 0.55)
const DIM := Color(0.55, 0.55, 0.58)
const PANEL_SIZE := Vector2(700, 540)

var _state: PlayerState
var _player: Node3D
var _root: Control
var _money: Label
var _message: Label
var _row_names: Array[Label] = []
var _row_status: Array[Label] = []
var _rows: Array[Button] = []
var _ignore_until := 0


func _ready() -> void:
	add_to_group("shop_ui")
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root != null and _root.visible


func open(state: PlayerState, player: Node3D) -> void:
	_state = state
	_player = player
	_message.text = ""
	_root.visible = true
	# The same E press that opened the stall must not close it again.
	_ignore_until = Time.get_ticks_msec() + 180
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	if _root == null or not _root.visible:
		return
	_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if Time.get_ticks_msec() < _ignore_until:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key >= KEY_1 and key <= KEY_4:
			_buy(key - KEY_1)
			get_viewport().set_input_as_handled()


func _buy(index: int) -> void:
	if _state == null:
		return
	if index == 0:
		_buy_detector()
	else:
		_buy_tier(index)
	_refresh()


## A click / tap on a row buys it, exactly like the number keys.
func _on_row_pressed(index: int) -> void:
	_buy(index)


func _buy_detector() -> void:
	if _state.has_detector:
		_message.text = "You already own the metal detector."
		return
	if _state.buy_detector():
		_message.text = "Bought the Metal Detector!  [Q] swaps it into your hand."
		if _player != null and _player.has_method("set_tool_mode"):
			_player.set_tool_mode(1)
	else:
		_message.text = "The detector costs $%d - keep digging!" % int(PlayerState.DETECTOR_PRICE)


func _buy_tier(index: int) -> void:
	var tier := _state.tiers[index]
	if index <= _state.equipment_tier_index:
		_message.text = "You already own the %s." % tier.display_name
		return
	var next_index := _state.equipment_tier_index + 1
	if index != next_index:
		_message.text = "Upgrade in order - next is the %s." % _state.tiers[next_index].display_name
		return
	if _state.buy_tier(index):
		_message.text = "Bought the %s!  radius %.2f m" % [tier.display_name, tier.radius]
		return
	var missing: Array[String] = []
	if _state.current_level < tier.level_required:
		missing.append("Lv %d" % tier.level_required)
	if _state.current_money < tier.money_required:
		missing.append("$%d" % int(tier.money_required))
	_message.text = "The %s needs %s." % [tier.display_name, " and ".join(missing)]


func _refresh() -> void:
	if _state == null:
		return
	_money.text = "Money  $%d          Level %d" % [
		int(_state.current_money), _state.current_level]

	# Row 0: the detector.
	var owns_detector := _state.has_detector
	if owns_detector:
		_set_row(0, "[1]  Metal Detector", "OWNED", GREEN, DIM)
	else:
		var can_buy := _state.current_money >= PlayerState.DETECTOR_PRICE
		_set_row(0, "[1]  Metal Detector",
			("BUY  $%d" if can_buy else "$%d") % int(PlayerState.DETECTOR_PRICE),
			GREEN if can_buy else GOLD, Color.WHITE)

	# Rows 1..3: the shovel chain.
	for i in range(1, _row_names.size()):
		if i >= _state.tiers.size():
			_row_names[i].text = ""
			_row_status[i].text = ""
			continue
		var tier := _state.tiers[i]
		var label := "[%d]  %s" % [i + 1, tier.display_name]
		if i <= _state.equipment_tier_index:
			_set_row(i, label, "OWNED", GREEN, DIM)
		elif i == _state.equipment_tier_index + 1:
			var affordable := _state.current_level >= tier.level_required \
				and _state.current_money >= tier.money_required
			_set_row(i, label,
				("BUY  $%d  ·  Lv %d" if affordable else "$%d  ·  Lv %d") % [
					int(tier.money_required), tier.level_required],
				GREEN if affordable else GOLD, Color.WHITE)
		else:
			_set_row(i, label, "LOCKED  ·  Lv %d" % tier.level_required,
				DIM, DIM)


func _set_row(index: int, name_text: String, status_text: String,
		status_color: Color, name_color: Color) -> void:
	_row_names[index].text = name_text
	_row_names[index].add_theme_color_override("font_color", name_color)
	_row_status[index].text = status_text
	_row_status[index].add_theme_color_override("font_color", status_color)


func _build() -> void:
	_root = Control.new()
	_root.name = "ShopRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.12, 0.97)
	style.border_color = Color(1.0, 0.86, 0.42, 0.85)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := _make_label(34, GOLD)
	title.text = "BEACH MARKET"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_money = _make_label(18, Color(0.85, 0.9, 1.0))
	_money.text = "Money  $0          Level 1"
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_money)

	var rule := HSeparator.new()
	box.add_child(rule)

	for i in 4:
		# The whole row is a Button, so a mouse click or a touch tap buys it.
		# The labels inside ignore the mouse so the click always reaches the row.
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 52)
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_stylebox_override("normal",
			_row_style(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.12)))
		button.add_theme_stylebox_override("hover",
			_row_style(Color(1.0, 0.86, 0.42, 0.16), Color(1.0, 0.86, 0.42, 0.7)))
		button.add_theme_stylebox_override("pressed",
			_row_style(Color(1.0, 0.86, 0.42, 0.32), GOLD))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.pressed.connect(_on_row_pressed.bind(i))

		var margin := MarginContainer.new()
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_theme_constant_override("margin_left", 16)
		margin.add_theme_constant_override("margin_right", 16)

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 12)
		var name_label := _make_label(21, Color.WHITE)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var status_label := _make_label(19, GOLD)
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status_label.custom_minimum_size = Vector2(240, 0)
		row.add_child(name_label)
		row.add_child(status_label)
		margin.add_child(row)
		button.add_child(margin)

		box.add_child(button)
		_rows.append(button)
		_row_names.append(name_label)
		_row_status.append(status_label)

	_message = _make_label(17, GOLD)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.custom_minimum_size = Vector2(0, 28)
	box.add_child(_message)

	var footer := _make_label(15, Color(1, 1, 1, 0.55))
	footer.text = "Click a row to buy   ·   1-4: buy   ·   E / Esc: leave"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(footer)


func _row_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	return style


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
