extends Control

## SHELF LIFE — main UI. Rule-badge-forward layout (binding park condition):
## badges are the largest, brightest element above the fold; shelf and tray
## subordinate. All game logic lives in ShelfState (pure logic).

const ItemCard := preload("res://scripts/item_card.gd")
const RuleBadge := preload("res://scripts/rule_badge.gd")
const GameAudioScript := preload("res://scripts/game_audio.gd")

const COL_BG := Color("171a21")
const COL_PANEL := Color("232833")
const COL_LINE := Color("39404f")
const COL_INK := Color("e8ecf4")
const COL_DIM := Color("9aa3b5")
const COL_GOOD := Color("3ddc84")
const COL_BAD := Color("ff5c74")
const COL_WARN := Color("ffc857")

var state: ShelfState
var audio: Node            # GameAudio (preloaded by path to dodge class_name race)
var level := 1

var selected := {}          # {"from": "tray"|"shelf", "idx"/"bay"/"row"}
var audited := false

# --- node refs (built in code) ---
var title_lbl: Label
var level_lbl: Label
var badge_row: HBoxContainer
var tray_row: HBoxContainer
var tray_panel: PanelContainer
var shelf_row: HBoxContainer
var status_lbl: Label
var open_btn: Button
var hint_btn: Button
var skip_btn: Button
var next_btn: Button
var reroll_btn: Button
var bay_cells := []         # [bay][row] -> PanelContainer


func _ready() -> void:
	state = ShelfState.new()
	audio = GameAudioScript.new()
	add_child(audio)
	_build_ui()
	_start_level(level)
	var music := AudioStreamPlayer.new()
	music.stream = audio.make_loop_stream()
	music.volume_db = -16.0
	add_child(music)
	music.play()


func _start_level(lv: int) -> void:
	level = lv
	audited = false
	selected = {}
	state.setup_stage(lv)
	status_lbl.text = ""
	next_btn.visible = false
	open_btn.disabled = false
	_render_all()
	print("[SHELF LIFE answer key] ", state.serialize_manifest())
	_publish_debug_state()


## Web-only debug bridge for rule-16 QA: exposes the full game state to
## JavaScript so the CDP playtest can plan REAL UI clicks (it still clicks
## and solves through the actual interface).
func _publish_debug_state() -> void:
	if not OS.has_feature("web"):
		return
	# Rects are only valid after the container pass; measure on a later frame.
	await get_tree().process_frame
	await get_tree().process_frame
	_publish_debug_state_now()


func _publish_debug_state_now() -> void:
	if not OS.has_feature("web"):
		return
	var tray_desc: Array = []
	for it in state.tray:
		tray_desc.append({
			"cat": it["cat"], "w": it["w"], "exp": it["exp"],
			"face_out": it["face_out"], "id": it["id"],
		})
	var shelf_desc: Array = []
	for bay in range(state.bays):
		var col: Array = []
		for row in range(2):
			var it = state.shelf[bay][row]
			col.append(null if it == null else {"cat": it["cat"], "w": it["w"],
					"exp": it["exp"], "face_out": it["face_out"], "id": it["id"]})
		shelf_desc.append(col)
	var btn_rects := {}
	for b in find_children("*", "Button", true, false):
		var btn := b as Button
		var g := btn.get_global_rect()
		btn_rects[btn.text] = {"x": g.position.x + g.size.x / 2.0, "y": g.position.y + g.size.y / 2.0}
	# tray cards + shelf cells: live rects keyed for the QA playtest
	var tray_rects: Array = []
	for c in tray_row.get_children():
		var g2 := (c as Control).get_global_rect()
		tray_rects.append({"x": g2.position.x + g2.size.x / 2.0, "y": g2.position.y + g2.size.y / 2.0})
	var cell_rects: Array = []
	for bay in range(bay_cells.size()):
		var colr: Array = []
		for row in range(2):
			var g3 := (bay_cells[bay][row] as Control).get_global_rect()
			colr.append({"x": g3.position.x + g3.size.x / 2.0, "y": g3.position.y + g3.size.y / 2.0})
		cell_rects.append(colr)
	var payload := JSON.stringify({
		"level": level, "seed": state.seed_value, "bays": state.bays,
		"rules": state.active_rules, "tray": tray_desc, "shelf": shelf_desc,
		"hints_left": state.hints_left, "skips_used": state.skips_used,
		"buttons": btn_rects, "status": status_lbl.text,
		"tray_rects": tray_rects, "cell_rects": cell_rects,
	})
	var eval_js := "
		(window.__shelfLifeState = function(p) { window.__SL_STATE = p; return true; })(%s);
	" % payload
	JavaScriptBridge.eval(eval_js, true)


func _debug_state_refresh() -> void:
	_publish_debug_state()


# =====================================================================
# UI CONSTRUCTION
# =====================================================================
func _panel_style(bg: Color, border: Color, radius := 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	return sb


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 20
	root.offset_right = -20
	root.offset_top = 10
	root.offset_bottom = -10
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# --- header: title + level ---
	var head := HBoxContainer.new()
	title_lbl = Label.new()
	title_lbl.text = "SHELF LIFE"
	title_lbl.add_theme_font_size_override("font_size", 30)
	title_lbl.add_theme_color_override("font_color", COL_INK)
	head.add_child(title_lbl)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	level_lbl = Label.new()
	level_lbl.add_theme_font_size_override("font_size", 16)
	level_lbl.add_theme_color_override("font_color", COL_DIM)
	head.add_child(level_lbl)
	root.add_child(head)

	# --- RULE BADGES: dominant visual band (park condition) ---
	badge_row = HBoxContainer.new()
	badge_row.alignment = BoxContainer.ALIGNMENT_CENTER
	badge_row.add_theme_constant_override("separation", 12)
	root.add_child(badge_row)

	# --- shelf panel ---
	var shelf_panel := PanelContainer.new()
	shelf_panel.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, COL_LINE))
	shelf_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(shelf_panel)
	var sv := VBoxContainer.new()
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	sv.add_theme_constant_override("separation", 6)
	shelf_panel.add_child(sv)
	shelf_row = HBoxContainer.new()
	shelf_row.alignment = BoxContainer.ALIGNMENT_CENTER
	shelf_row.add_theme_constant_override("separation", 16)
	sv.add_child(shelf_row)

	# --- action row (OPEN SHOP + rewarded hooks) ---
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 14)
	root.add_child(actions)
	open_btn = _big_button("OPEN SHOP", COL_WARN, Color("241a00"))
	open_btn.pressed.connect(_on_open_shop)
	actions.add_child(open_btn)
	hint_btn = _big_button("HINT (3)", Color("3d6ea5"), COL_INK)
	hint_btn.tooltip_text = "Highlight one item that breaks a rule"
	hint_btn.pressed.connect(_on_hint)
	actions.add_child(hint_btn)
	skip_btn = _big_button("SKIP DELIVERY", Color("5a4a78"), COL_INK)
	skip_btn.tooltip_text = "Send one delivery back (1 per day)"
	skip_btn.pressed.connect(_on_skip)
	actions.add_child(skip_btn)
	reroll_btn = _big_button("NEW SEED", Color("333a48"), COL_DIM)
	reroll_btn.pressed.connect(func(): _start_level(level))
	actions.add_child(reroll_btn)
	next_btn = _big_button("NEXT DAY >", COL_GOOD, Color("00240f"))
	next_btn.visible = false
	next_btn.pressed.connect(func():
		if level < ShelfState.MAX_STAGE:
			_start_level(level + 1)
		else:
			status_lbl.text = "All days restocked. Shop thrives."
	)
	actions.add_child(next_btn)

	# --- status line ---
	status_lbl = Label.new()
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_lbl.add_theme_font_size_override("font_size", 18)
	status_lbl.custom_minimum_size.y = 30
	root.add_child(status_lbl)

	# --- tray panel at bottom ---
	tray_panel = PanelContainer.new()
	tray_panel.add_theme_stylebox_override("panel", _panel_style(COL_PANEL, COL_LINE))
	root.add_child(tray_panel)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 6)
	tray_panel.add_child(tv)
	var tray_head := Label.new()
	tray_head.text = "DELIVERY TRAY — TODAY'S STOCK   (click item, click slot · FLIP chip or right-click to flip)"
	tray_head.add_theme_font_size_override("font_size", 12)
	tray_head.add_theme_color_override("font_color", COL_DIM)
	tv.add_child(tray_head)
	tray_row = HBoxContainer.new()
	tray_row.add_theme_constant_override("separation", 10)
	tv.add_child(tray_row)


func _big_button(txt: String, bg: Color, fg: Color) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", fg)
	var sb := _panel_style(bg, bg.darkened(0.35), 12)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	b.add_theme_stylebox_override("normal", sb)
	var sbh: StyleBoxFlat = sb.duplicate()
	sbh.bg_color = bg.lightened(0.12)
	b.add_theme_stylebox_override("hover", sbh)
	var sbp: StyleBoxFlat = sb.duplicate()
	sbp.bg_color = bg.darkened(0.15)
	b.add_theme_stylebox_override("pressed", sbp)
	return b


# =====================================================================
# RENDERING
# =====================================================================
func _render_all() -> void:
	_render_badges(null)
	_render_shelf()
	_render_tray()
	_render_header()


func _render_header() -> void:
	level_lbl.text = "DAY %d / %d    seed %d    hints %d" % [
			level, ShelfState.MAX_STAGE, state.seed_value, state.hints_left]
	hint_btn.text = "HINT (%d)" % state.hints_left
	hint_btn.disabled = state.hints_left <= 0
	skip_btn.visible = true


func _rule_label(r: String) -> String:
	match r:
		"FACING": return "LABELS FACE OUT"
		"WEIGHT": return "HEAVY BELOW LIGHT"
		"ADJACENCY": return "CATEGORY ADJACENCY"
		"FIFO": return "FIFO OLDEST FRONT"
	return r


func _render_badges(res) -> void:
	for c in badge_row.get_children():
		c.queue_free()
	for r in state.active_rules:
		var verdict: int = -1   # -1 unjudged, 0 violated, 1 ok
		if res != null:
			verdict = 1 if res.get(r, false) else 0
		var badge: Control = RuleBadge.make(_rule_label(r), verdict)
		badge_row.add_child(badge)


func _render_shelf() -> void:
	for c in shelf_row.get_children():
		c.queue_free()
	bay_cells.clear()
	for bay in range(state.bays):
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		var head := Label.new()
		head.text = "BAY %d" % (bay + 1)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_font_size_override("font_size", 11)
		head.add_theme_color_override("font_color", COL_DIM)
		col.add_child(head)
		var cells := []
		for row in range(2):
			var cell := _make_cell(bay, row)
			col.add_child(cell)
			cells.append(cell)
		shelf_row.add_child(col)
		bay_cells.append(cells)
	_fill_cells()


func _make_cell(bay: int, row: int) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(190, 78)
	var sb := _panel_style(Color(0, 0, 0, 0), COL_LINE, 12)
	if row == 1:
		sb.set_corner_radius_all(10)
	cell.add_theme_stylebox_override("panel", sb)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.gui_input.connect(func(ev: InputEvent): _on_cell_input(ev, bay, row))
	return cell


func _fill_cells() -> void:
	for bay in range(state.bays):
		for row in range(2):
			var cell: PanelContainer = bay_cells[bay][row]
			for c in cell.get_children():
				c.queue_free()
			var it = state.shelf[bay][row]
			var is_sel: bool = selected.get("from", "") == "shelf" \
					and selected.get("bay") == bay and selected.get("row") == row
			var hinted := _is_hinted_cell(it, bay, row)
			if it != null:
				var card: Control = ItemCard.make(it, is_sel, hinted, true,
						func(ev: InputEvent): _on_card_input_in_cell(ev, bay, row))
				cell.add_child(card)
				var sb: StyleBoxFlat = cell.get_theme_stylebox("panel")
				sb.bg_color = ShelfState.CATEGORIES[it["cat"]]["col"].darkened(0.55)
			else:
				var ph := Label.new()
				ph.text = "FRONT" if row == 0 else "BACK"
				ph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				ph.modulate = Color(1, 1, 1, 0.25)
				cell.add_child(ph)
				if is_sel:
					var sb2: StyleBoxFlat = cell.get_theme_stylebox("panel")
					sb2.border_color = Color.WHITE


func _is_hinted_cell(it, bay: int, row: int) -> bool:
	if it == null or state.last_hint_item.is_empty():
		return false
	var h: Dictionary = state.last_hint_item
	return h.get("bay") == bay and h.get("row") == row


func _render_tray() -> void:
	for c in tray_row.get_children():
		c.queue_free()
	if state.tray.is_empty():
		var empty := Label.new()
		empty.text = "tray empty — all items shelved"
		empty.modulate = Color(1, 1, 1, 0.3)
		tray_row.add_child(empty)
		return
	for i in range(state.tray.size()):
		var it: Dictionary = state.tray[i]
		var is_sel: bool = selected.get("from", "") == "tray" and selected.get("idx") == i
		var hinted: bool = state.last_hint_item.get("tray_idx") == i
		var card: Control = ItemCard.make(it, is_sel, hinted, false,
				func(ev: InputEvent): _on_tray_card_input(ev, i))
		card.custom_minimum_size = Vector2(110, 76)
		tray_row.add_child(card)


# =====================================================================
# INPUT
# =====================================================================
func _on_tray_card_input(ev: InputEvent, idx: int) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_RIGHT:
			state.flip_tray_item(idx)
			audited = false
			status_lbl.text = ""
			audio.play("ping", -14.0)
			_render_all()
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			selected = {} if _same_selection({"from": "tray", "idx": idx}) else {"from": "tray", "idx": idx}
			audited = false
			_render_all()
			_debug_state_refresh()


func _on_card_input_in_cell(ev: InputEvent, bay: int, row: int) -> void:
	_on_cell_input(ev, bay, row)


func _on_cell_input(ev: InputEvent, bay: int, row: int) -> void:
	if not (ev is InputEventMouseButton and ev.pressed):
		return
	if ev.button_index == MOUSE_BUTTON_RIGHT:
		if state.shelf[bay][row] != null:
			state.flip_item(bay, row)
			audited = false
			status_lbl.text = ""
			audio.play("ping", -14.0)
			_render_all()
		return
	if ev.button_index != MOUSE_BUTTON_LEFT:
		return
	if selected.is_empty():
		if state.shelf[bay][row] != null:
			selected = {"from": "shelf", "bay": bay, "row": row}
			_render_all()
		return
	if selected["from"] == "tray":
		state.place_from_tray(selected["idx"], bay, row)
		audio.play("thock")
		_after_move()
	else:
		state.swap_shelf(selected["bay"], selected["row"], bay, row)
		audio.play("thock", -10.0)
		_after_move()


func _same_selection(sel: Dictionary) -> bool:
	return selected.get("from") == sel.get("from") \
			and selected.get("idx") == sel.get("idx") \
			and selected.get("bay") == sel.get("bay") \
			and selected.get("row") == sel.get("row")


func _after_move() -> void:
	selected = {}
	audited = false
	status_lbl.text = ""
	_render_all()
	_debug_state_refresh()


# =====================================================================
# ACTIONS
# =====================================================================
func _on_open_shop() -> void:
	audited = true
	var res := state.audit()
	_render_badges(res)
	var broken: Array = []
	for r in state.active_rules:
		if not res.get(r, false):
			broken.append(_rule_label(r))
	if res.get("full", false) and broken.is_empty() and state.is_solved():
		status_lbl.text = "SHOP OPEN — every rule satisfied. Tidy."
		status_lbl.add_theme_color_override("font_color", COL_GOOD)
		audio.play("bell")
		open_btn.disabled = true
		next_btn.visible = level < ShelfState.MAX_STAGE
		if level >= ShelfState.MAX_STAGE:
			status_lbl.text = "FINAL DAY RESTOCKED — every rule satisfied. The shop thrives."
	else:
		var msg := "VIOLATION — " + " · ".join(broken) if not broken.is_empty() else "Shelve everything before opening."
		status_lbl.text = msg
		status_lbl.add_theme_color_override("font_color", COL_BAD)
		audio.play("buzz")
	_publish_debug_state()


func _on_hint() -> void:
	var h := state.use_hint()
	if h.is_empty():
		status_lbl.text = "No hints left."
		status_lbl.add_theme_color_override("font_color", COL_BAD)
		return
	audio.play("ping")
	audited = false
	_render_all()
	match h.get("rule", ""):
		"FACING":
			status_lbl.text = "This label faces the wrong way — flip it."
		"WEIGHT":
			status_lbl.text = "Heavy below light: check this pair."
		"FIFO":
			status_lbl.text = "Earliest expiry belongs at the front."
		"ADJACENCY":
			status_lbl.text = "Same category sits together — this one strays."
		_:
			status_lbl.text = "Check this one."
	status_lbl.add_theme_color_override("font_color", COL_WARN)


func _on_skip() -> void:
	if state.skips_used >= ShelfState.MAX_SKIPS:
		status_lbl.text = "No more skips today."
		status_lbl.add_theme_color_override("font_color", COL_BAD)
		return
	if state.tray.is_empty():
		status_lbl.text = "Tray already empty."
		status_lbl.add_theme_color_override("font_color", COL_BAD)
		return
	# Skip the first tray item that keeps the board solvable.
	for i in range(state.tray.size()):
		if state.can_skip_delivery(i):
			state.skip_delivery(i)
			audio.play("thock", -4.0)
			status_lbl.text = "Delivery skipped — one less box."
			status_lbl.add_theme_color_override("font_color", COL_DIM)
			_render_header()
			_render_all()
			return
	status_lbl.text = "Skipping would break a rule — refused."
	status_lbl.add_theme_color_override("font_color", COL_BAD)
