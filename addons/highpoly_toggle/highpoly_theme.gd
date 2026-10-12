@tool
extends RefCounted
class_name HighpolyTheme
# Small styling helpers for the panel. The fork dropped the plugin's own look
# (video backdrop, logo flash, display font, white-on-translucent controls):
# the panel wears the editor's theme like every other dock, so these return
# neutral values and their callers keep working unchanged.

const SharedMenu = preload("highpoly_menu.gd")


# Section headings still want one accent colour; take the editor's own.
static func col(_key: String) -> Color:
	return accent()


static func accent() -> Color:
	if Engine.is_editor_hint():
		var et := EditorInterface.get_editor_theme()
		if et != null and et.has_color("accent_color", "Editor"):
			return et.get_color("accent_color", "Editor")
	return Color(0.44, 0.73, 0.98)


static func base_font_size() -> int:
	if Engine.is_editor_hint():
		var et := EditorInterface.get_editor_theme()
		if et != null and et.has_font_size("main_size", "EditorFonts"):
			return et.get_font_size("main_size", "EditorFonts")
	return 14


# Sizes in the panel were picked against a 14 px base; keep their proportions
# on whatever size the editor uses.
static func fs(base: int) -> int:
	return maxi(8, int(round(float(base) * float(base_font_size()) / 14.0)))


static func status_size() -> int:
	return fs(11)


static func num(_key: String, def: float) -> float:
	return def


static func bar(p: ProgressBar) -> ProgressBar:
	return p


static func chip(text: String, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.tooltip_text = tip
	style_toggle(b)
	return b


# ---------------------------------------------------------------------------
# STATES YOU CAN SEE. The editor theme draws a toggled button only a shade
# lighter than an untoggled one, and the owner could not tell what was on. So
# every interactive state gets its own look, built from the editor's OWN
# colours (accent, base, font) so it still matches any editor theme:
#
#   OFF            flat, thin outline, and an empty check box on the left
#   ON             filled with the accent, a ticked check box, contrasting text
#   hover          the outline turns accent (OFF) or the fill brightens (ON)
#   focus          a 2 px accent ring, for keyboard users
#   disabled       no fill, faint outline, text at 40 %
#
# No images and no fonts: the check box is drawn with two rectangles and a
# polyline on the button's own draw signal.
const META_STYLED := "hp_styled"
const BOX := 12.0          # check box side, in px at a 14 px base font
const BOX_PAD := 7.0       # gap between the left edge and the box


static func palette() -> Dictionary:
	var acc := accent()
	var base := Color(0.13, 0.15, 0.18)
	var font := Color(0.88, 0.89, 0.91)
	if Engine.is_editor_hint():
		var et := EditorInterface.get_editor_theme()
		if et != null:
			if et.has_color("base_color", "Editor"):
				base = et.get_color("base_color", "Editor")
			if et.has_color("font_color", "Editor"):
				font = et.get_color("font_color", "Editor")
	# Text on the accent fill: black or white, whichever reads better.
	var on_font := Color.BLACK if acc.get_luminance() > 0.55 else Color.WHITE
	var dark := base.get_luminance() < 0.5
	return {
		"accent": acc,
		"base": base,
		"font": font,
		"on_font": on_font,
		# a light lift over the panel, so hover is visible on dark AND light themes
		"lift": Color(1, 1, 1, 0.07) if dark else Color(0, 0, 0, 0.06),
		"outline": Color(font.r, font.g, font.b, 0.35),
		"faint": Color(font.r, font.g, font.b, 0.15),
	}


static func _box(bg: Color, border: Color, width: int, draw_bg := true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.draw_center = draw_bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


static func style_toggle(b: Button) -> void:
	if b == null or b.has_meta(META_STYLED):
		return
	b.set_meta(META_STYLED, "toggle")
	var p := palette()
	var acc: Color = p.accent
	var normal := _box(Color(0, 0, 0, 0), p.outline, 1)
	var hover := _box(p.lift, acc, 1)
	var pressed := _box(acc, acc.lightened(0.15), 2)
	var hover_pressed := _box(acc.lightened(0.18), acc.lightened(0.35), 2)
	var disabled := _box(Color(0, 0, 0, 0), p.faint, 1, false)
	var focus := _box(Color(0, 0, 0, 0), acc.lightened(0.25), 2, false)
	var left := BOX_PAD + float(fs(int(BOX))) + 6.0
	for sb in [normal, hover, pressed, hover_pressed, disabled, focus]:
		(sb as StyleBoxFlat).content_margin_left = left
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", hover_pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_color_override("font_color", p.font)
	b.add_theme_color_override("font_hover_color", p.font)
	b.add_theme_color_override("font_focus_color", p.font)
	b.add_theme_color_override("font_pressed_color", p.on_font)
	b.add_theme_color_override("font_hover_pressed_color", p.on_font)
	var fd: Color = p.font
	fd.a = 0.4
	b.add_theme_color_override("font_disabled_color", fd)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.draw.connect(_draw_check.bind(b))


static func style_action(b: Button) -> void:
	if b == null or b.has_meta(META_STYLED):
		return
	b.set_meta(META_STYLED, "action")
	var p := palette()
	var acc: Color = p.accent
	var fill: Color = p.lift
	b.add_theme_stylebox_override("normal", _box(fill, p.outline, 1))
	b.add_theme_stylebox_override("hover", _box(fill * Color(1, 1, 1, 2.2), acc, 1))
	b.add_theme_stylebox_override("pressed", _box(Color(acc.r, acc.g, acc.b, 0.55), acc, 2))
	b.add_theme_stylebox_override("hover_pressed", _box(Color(acc.r, acc.g, acc.b, 0.65), acc, 2))
	b.add_theme_stylebox_override("disabled", _box(Color(0, 0, 0, 0), p.faint, 1, false))
	b.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), acc.lightened(0.25), 2, false))
	var fd: Color = p.font
	fd.a = 0.4
	b.add_theme_color_override("font_disabled_color", fd)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


# Every button under `root`: toggles get the chip look, push buttons and
# dropdowns the action look. Colour pickers keep the editor's own swatch.
# Idempotent - a control styled once is skipped.
static func style_all(root: Node) -> void:
	if root == null:
		return
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			stack.append(ch)
		if not (n is Button) or n is ColorPickerButton or n is CheckBox or n is CheckButton:
			continue
		var b := n as Button
		if b.toggle_mode and not (b is OptionButton):
			style_toggle(b)
		else:
			style_action(b)


# The check box: an outline when off, an accent-contrast tick when on, faded
# when the chip is disabled.
static func _draw_check(b: Button) -> void:
	if not is_instance_valid(b):
		return
	var side := float(fs(int(BOX)))
	var r := Rect2(Vector2(BOX_PAD, (b.size.y - side) * 0.5), Vector2(side, side))
	var p := palette()
	var on := b.button_pressed
	var ink: Color = p.on_font if on else p.font
	if b.disabled:
		ink.a = 0.35
	if on:
		b.draw_rect(r, Color(ink.r, ink.g, ink.b, 0.18), true)
		b.draw_rect(r, ink, false, 1.5)
		var pts := PackedVector2Array([
			r.position + Vector2(side * 0.2, side * 0.52),
			r.position + Vector2(side * 0.42, side * 0.75),
			r.position + Vector2(side * 0.82, side * 0.25)])
		b.draw_polyline(pts, ink, 2.0, true)
	else:
		ink.a *= 0.7
		b.draw_rect(r, ink, false, 1.5)


# The hover-description box: the editor's own tooltip panel.
static func tip_box() -> StyleBox:
	if Engine.is_editor_hint():
		var et := EditorInterface.get_editor_theme()
		if et != null and et.has_stylebox("panel", "TooltipPanel"):
			return et.get_stylebox("panel", "TooltipPanel")
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.12, 0.14, 0.97)
	sb.set_corner_radius_all(3)
	return sb
