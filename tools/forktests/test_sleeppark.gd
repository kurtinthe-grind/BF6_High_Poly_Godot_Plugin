extends SceneTree
# The sleep-setting repair that outlives the bench harness: with no park file it
# must report nothing and touch nothing (the headless run has no
# EditorInterface, so the file check has to come first).

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("FORKTEST PASS " if cond else "FORKTEST FAIL ") + what)
	if not cond:
		fails += 1


func _init() -> void:
	var sp = load("res://addons/highpoly_toggle/highpoly_sleeppark.gd")
	check(sp != null, "highpoly_sleeppark.gd loads")
	if sp == null:
		quit(1)
		return
	check(sp.K_SLEEP_UNFOCUSED == "interface/editor/unfocused_low_processor_mode_sleep_usec",
		"unfocused sleep key is the editor setting")
	if FileAccess.file_exists(sp.SLEEP_PARK):
		DirAccess.remove_absolute(sp.SLEEP_PARK)
	check(sp.restore_pending() == "", "nothing parked -> nothing restored")
	quit(1 if fails else 0)
