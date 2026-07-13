class_name AppTheme
extends RefCounted
## The single source of UI styling. Built programmatically (no .tres to drift out
## of sync) and applied to each view's root Control. Palette: dark slate with a
## brass accent to match the steam-era rolling stock.

const BG := Color(0.094, 0.102, 0.129)          # panels
const BG_RAISED := Color(0.145, 0.155, 0.19)    # buttons at rest
const BG_HOVER := Color(0.19, 0.205, 0.25)
const BORDER := Color(0.27, 0.29, 0.35)
const TEXT := Color(0.88, 0.89, 0.93)
const TEXT_DIM := Color(0.55, 0.57, 0.64)
const ACCENT := Color(0.85, 0.62, 0.24)         # brass
const ACCENT_PRESSED := Color(0.42, 0.31, 0.13)

# Canvas (2D editor) colors, used by the map's _draw code.
const CANVAS_BG := Color(0.062, 0.068, 0.086)
const GRID_MINOR := Color(1.0, 1.0, 1.0, 0.045)
const GRID_MAJOR := Color(1.0, 1.0, 1.0, 0.10)
const RAIL := Color(0.72, 0.75, 0.82)
const TIE := Color(0.42, 0.30, 0.18)
const GHOST_FREE := Color(1.0, 1.0, 1.0, 0.55)
const GHOST_SNAP := Color(0.35, 1.0, 0.55, 0.8)
const ENDPOINT := Color(0.30, 1.0, 0.45)

static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 13

	t.set_stylebox("panel", "PanelContainer", _flat(BG, BORDER, 8, 8))

	t.set_stylebox("normal", "Button", _flat(BG_RAISED, BORDER, 6, 5, 10))
	t.set_stylebox("hover", "Button", _flat(BG_HOVER, BORDER, 6, 5, 10))
	t.set_stylebox("pressed", "Button", _flat(ACCENT_PRESSED, ACCENT, 6, 5, 10))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", _flat(BG, BORDER * Color(1, 1, 1, 0.4), 6, 5, 10))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)

	t.set_color("font_color", "Label", TEXT)
	return t

## A rounded StyleBoxFlat with border and content margins.
static func _flat(bg: Color, border: Color, radius: int, vpad: int = 6, hpad: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_top = vpad
	s.content_margin_bottom = vpad
	s.content_margin_left = hpad
	s.content_margin_right = hpad
	return s

## Section header style for palette groups ("TRACK", "TRAINS").
static func style_section_label(l: Label) -> void:
	l.add_theme_color_override("font_color", TEXT_DIM)
	l.add_theme_font_size_override("font_size", 11)
