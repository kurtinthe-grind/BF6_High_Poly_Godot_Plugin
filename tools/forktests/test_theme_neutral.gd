extends SceneTree
# The panel wears the editor theme: the helpers return neutral values and no
# longer build a theme of their own.

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("FORKTEST PASS " if cond else "FORKTEST FAIL ") + what)
	if not cond:
		fails += 1


func _init() -> void:
	var th = load("res://addons/highpoly_toggle/highpoly_theme.gd")
	check(th != null, "highpoly_theme.gd loads")
	if th == null:
		quit(1)
		return
	# Script.has_method() does not see a script's own static functions; the
	# source text is the reliable check.
	var src: String = (th as GDScript).source_code
	check(not src.contains("func build_ui_theme"), "no custom panel theme")
	check(not src.contains("func ui_font"), "no custom font")
	var b: Button = th.chip("Water", "tip")
	check(b.toggle_mode and b.theme_type_variation == &"", "chip is a plain toggle button")
	b.free()
	check(th.num("tint", 0.5) == 0.5, "palette numbers fall back to the default")
	var p := ProgressBar.new()
	check(th.bar(p) == p and not p.has_theme_stylebox_override("fill"), "bars keep editor styling")
	p.free()
	check(th.fs(14) == th.base_font_size(), "font sizes track the editor size")
	quit(1 if fails else 0)
