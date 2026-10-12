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
	return b


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
