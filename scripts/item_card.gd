extends PanelContainer

## Item card: colored rounded rect + category glyph + attribute tags +
## VISIBLE FLIP AFFORDANCE (pulse caveat D7). Static factory `make`.

const COL_INK := Color("e8ecf4")
const COL_FLIP_CHIP := Color("10131a")


static func make(item: Dictionary, selected: bool, hinted: bool,
		in_shelf: bool, input_cb: Callable) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = ShelfState.CATEGORIES[item["cat"]]["col"]
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = Color(0, 0, 0, 0.35)
	panel.add_theme_stylebox_override("panel", sb)
	# STOP: the card itself receives gui_input (select/flip). Children stay IGNORE
	# so clicks land on the card, not the labels.
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	if selected:
		sb.border_color = Color.WHITE
		sb.set_border_width_all(3)
	if hinted:
		sb.border_color = Color("ff5c74")
		sb.set_border_width_all(4)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)

	var glyph := Label.new()
	glyph.text = item["cat"] + "->" if item["face_out"] else "?%s?" % item["cat"]
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 26)
	glyph.add_theme_color_override("font_color", Color(0, 0, 0, 0.75))
	v.add_child(glyph)

	if not item["face_out"]:
		glyph.modulate = Color(1, 1, 1, 0.45)
		panel.modulate = Color(1, 1, 1, 0.8)

	# attribute tags row
	var tags := HBoxContainer.new()
	tags.alignment = BoxContainer.ALIGNMENT_CENTER
	tags.add_theme_constant_override("separation", 4)
	tags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for tag_txt in ["W:%s" % _wlabel(item["w"]), "E:%d" % item["exp"]]:
		var chip := Label.new()
		chip.text = tag_txt
		chip.add_theme_font_size_override("font_size", 11)
		chip.add_theme_color_override("font_color", COL_INK)
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(0, 0, 0, 0.55)
		csb.set_corner_radius_all(5)
		csb.content_margin_left = 4
		csb.content_margin_right = 4
		csb.content_margin_top = 1
		csb.content_margin_bottom = 1
		chip.add_theme_stylebox_override("normal", csb)
		tags.add_child(chip)
	v.add_child(tags)

	# FLIP affordance: always visible on unflipped items (D7).
	var flip := Label.new()
	flip.text = "FLIP" if item["face_out"] else "flipped"
	flip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flip.add_theme_font_size_override("font_size", 10)
	if item["face_out"]:
		var fsb := StyleBoxFlat.new()
		fsb.bg_color = COL_FLIP_CHIP
		fsb.set_corner_radius_all(6)
		fsb.set_border_width_all(1)
		fsb.border_color = Color(1, 1, 1, 0.35)
		fsb.content_margin_left = 6
		fsb.content_margin_right = 6
		flip.add_theme_stylebox_override("normal", fsb)
		flip.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	else:
		flip.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	v.add_child(flip)

	panel.gui_input.connect(input_cb)
	return panel


static func _wlabel(w: int) -> String:
	match w:
		1: return "L"
		2: return "M"
		3: return "H"
	return str(w)
