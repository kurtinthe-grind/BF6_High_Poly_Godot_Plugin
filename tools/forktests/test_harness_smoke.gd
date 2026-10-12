extends SceneTree
# The runner itself: a test can load an addon script from the sandbox copy and
# report through the FORKTEST protocol.

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("FORKTEST PASS " if cond else "FORKTEST FAIL ") + what)
	if not cond:
		fails += 1


func _init() -> void:
	var lib = load("res://addons/highpoly_toggle/highpoly_lib.gd")
	check(lib != null, "highpoly_lib.gd loads in the sandbox")
	check(lib != null and str(lib.HP_NODE) != "", "HighpolyLib.HP_NODE is readable")
	quit(1 if fails else 0)
