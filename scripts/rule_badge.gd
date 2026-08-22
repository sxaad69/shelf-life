extends PanelContainer

## Rule badge — the identity element. Must dominate the first visual
## read (binding park condition). Big pill, colored dot, verdict tick.

const COL_DIM := Color("9aa3b5")
const COL_LINE := Color("39404f")
const COL_GOOD := Color("3ddc84")
const COL_BAD := Color("ff5c74")


static func make(label: String, verdict: int) -> Control:
	# verdict: -1 unjudged / 0 violated / 1 ok
	var badge := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(999)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.set_border_width_all(3)
	badge.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(row)

	var dot := Label.new()
	dot.text = "●"
	dot.add_theme_font_size_override("font_size", 18)
	row.add_child(dot)

	var txt := Label.new()
	txt.text = label
	txt.add_theme_font_size_override("font_size", 22)
	row.add_child(txt)

	var mark := Label.new()
	mark.add_theme_font_size_override("font_size", 22)
	row.add_child(mark)

	match verdict:
		1:
			sb.bg_color = Color(GOOD_BG)
			sb.border_color = COL_GOOD
			txt.add_theme_color_override("font_color", COL_GOOD)
			dot.add_theme_color_override("font_color", COL_GOOD)
			mark.text = "✓"
			mark.add_theme_color_override("font_color", COL_GOOD)
		0:
			sb.bg_color = Color(BAD_BG)
			sb.border_color = COL_BAD
			txt.add_theme_color_override("font_color", COL_BAD)
			dot.add_theme_color_override("font_color", COL_BAD)
			mark.text = "✗"
			mark.add_theme_color_override("font_color", COL_BAD)
		_:
			sb.bg_color = Color(UNJUDGED_BG)
			sb.border_color = COL_LINE
			txt.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
			dot.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	return badge


const GOOD_BG := "173425"
const BAD_BG := "3a1720"
const UNJUDGED_BG := "2b3345"
