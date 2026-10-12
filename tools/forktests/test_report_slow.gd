extends SceneTree
# One slow placed object is worth a line of its own; a normal one is not.

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("FORKTEST PASS " if cond else "FORKTEST FAIL ") + what)
	if not cond:
		fails += 1


func _init() -> void:
	var v = load("res://addons/highpoly_toggle/highpoly_vitals.gd")
	check(v.report_slow("Crate_01", v.SLOW_ITEM_MS - 1) == false, "under the threshold: silent")
	check(v.report_slow("Tower_02", v.SLOW_ITEM_MS) == true, "at the threshold: logged")
	v.crumb("swapping placed objects")
	check(v.crumb_now() == "swapping placed objects" and not v.crumb_is_idle(),
		"the swap crumb is not idle")
	# OPT-14: an inner call stamping "idle" must not erase the outer job's label,
	# or every freeze during the swap is reported as "idle, nothing building".
	v.job_begin("swapping placed objects")
	v.crumb("idle, nothing building")
	check(v.crumb_now() == "swapping placed objects" and not v.crumb_is_idle(),
		"idle inside a running job keeps the job's label")
	v.crumb("reading mp_x: walk")
	check(v.crumb_now() == "reading mp_x: walk", "a real inner phase still shows")
	v.job_end("swapping placed objects")
	check(v.crumb_is_idle(), "ending the job hands the crumb back to idle")
	v.crumb("idle, nothing building")
	check(v.crumb_now().begins_with("idle"), "idle with no job is idle")
	quit(1 if fails else 0)
