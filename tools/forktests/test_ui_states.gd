extends SceneTree
# The owner could not tell what was on and what was off. Every interactive state
# must now look different from its neighbours: a chip that is ON is filled with
# the accent and carries a check box; OFF is flat with an outline; hover, focus
# and disabled each have their own look. Section headers look clickable.

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("FORKTEST PASS " if cond else "FORKTEST FAIL ") + what)
	if not cond:
		fails += 1


func _bg(b: Control, style: String) -> Color:
	var sb := b.get_theme_stylebox(style) as StyleBoxFlat
	return sb.bg_color if sb != null else Color(0, 0, 0, -1)


func _border(b: Control, style: String) -> int:
	var sb := b.get_theme_stylebox(style) as StyleBoxFlat
	return sb.border_width_left if sb != null else -1


static func _diff(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a)


func _init() -> void:
	var th = load("res://addons/highpoly_toggle/highpoly_theme.gd")
	check(th != null, "highpoly_theme.gd loads")
	if th == null:
		quit(1)
		return
	var accent: Color = th.accent()

	# ---- chips (toggles) ----
	var c: Button = th.chip("Grass", "tip")
	root.add_child(c)
	check(c.toggle_mode, "chip is a toggle")
	for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		check(c.has_theme_stylebox_override(s), "chip has its own '%s' look" % s)
	check(_diff(_bg(c, "normal"), _bg(c, "pressed")) > 0.5, "ON is clearly a different fill from OFF")
	check(_diff(_bg(c, "pressed"), accent) < 0.05, "ON is filled with the editor accent")
	check(_bg(c, "normal").a < 0.35, "OFF is flat (little or no fill)")
	check(_border(c, "normal") >= 1, "OFF keeps an outline so it still reads as a button")
	check(_diff(_bg(c, "hover"), _bg(c, "normal")) > 0.05 or _border(c, "hover") > _border(c, "normal"),
		"hovering an OFF chip changes its look")
	check(_diff(_bg(c, "hover_pressed"), _bg(c, "pressed")) > 0.03, "hovering an ON chip changes its look")
	check(_border(c, "focus") >= 2, "keyboard focus draws a visible ring")
	check(c.get_theme_color("font_disabled_color").a <= 0.5, "disabled text is clearly dimmed")
	var dis := c.get_theme_stylebox("disabled") as StyleBoxFlat
	check(dis != null and dis.draw_center == false or (dis != null and dis.bg_color.a < 0.2),
		"disabled chip has no fill")
	check((c.get_theme_stylebox("normal") as StyleBoxFlat).content_margin_left >= 18,
		"room on the left for the on/off check box")
	check(c.draw.get_connections().size() > 0, "chip draws its on/off check box")
	check(c.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND, "chip shows a hand cursor")
	c.set_pressed_no_signal(true)
	check(c.button_pressed, "chip toggles")

	# ---- plain action buttons ----
	var a := Button.new()
	a.text = "Cache this map"
	root.add_child(a)
	th.style_action(a)
	check(not a.toggle_mode, "action stays a push button")
	check(a.has_theme_stylebox_override("hover") and a.has_theme_stylebox_override("pressed")
		and a.has_theme_stylebox_override("focus") and a.has_theme_stylebox_override("disabled"),
		"action has hover, pressed, focus and disabled looks")
	check(_diff((a.get_theme_stylebox("hover") as StyleBoxFlat).border_color, accent) < 0.05,
		"hovering an action outlines it in the accent")
	check(_diff(_bg(a, "pressed"), _bg(a, "normal")) > 0.1, "pressing an action changes its fill")

	# ---- style_all walks a panel ----
	var box := VBoxContainer.new()
	root.add_child(box)
	var t := Button.new(); t.toggle_mode = true; box.add_child(t)
	var p := Button.new(); box.add_child(p)
	var o := OptionButton.new(); box.add_child(o)
	th.style_all(box)
	check(t.has_theme_stylebox_override("pressed") and t.draw.get_connections().size() > 0,
		"style_all gives a toggle the chip look")
	check(p.has_theme_stylebox_override("hover"), "style_all gives a push button the action look")
	check(o.has_theme_stylebox_override("hover"), "style_all gives a dropdown the action look")
	var n_before := t.draw.get_connections().size()
	th.style_all(box)
	check(t.draw.get_connections().size() == n_before, "style_all is idempotent")

	# ---- section headers ----
	var sec_script = load("res://addons/highpoly_toggle/highpoly_section.gd")
	var sec = sec_script.new()
	root.add_child(sec)
	sec.setup("Storage", "what is kept")
	check(sec.head.mouse_default_cursor_shape == Control.CURSOR_POINTING_HAND, "header shows a hand cursor")
	check(sec.head.focus_mode == Control.FOCUS_ALL, "header can take keyboard focus")
	check(sec.title_lbl.text.begins_with("▸"), "closed header shows a right arrow")
	var ev := InputEventKey.new()
	ev.keycode = KEY_ENTER
	ev.pressed = true
	sec._head_input(ev)
	check(sec.is_open(), "Enter on a focused header opens it")
	check(sec.title_lbl.text.begins_with("▾"), "open header shows a down arrow")
	check(sec.title_lbl.text.ends_with("Storage"), "header keeps its title")
	quit(1 if fails else 0)
