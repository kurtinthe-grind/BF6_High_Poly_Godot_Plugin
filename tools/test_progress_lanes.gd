extends SceneTree

# Getting a map in is more stages than the panel was showing. The download had a
# bar and the scenery build had a bar, but unpacking the archive between them had
# none — 31 s on Dumbo with nothing moving. A long job with no bar is
# indistinguishable from a hang.
#
# What can go wrong with the fix without throwing: a lane that opens and never
# closes leaves a bar stuck on screen for the rest of the session, including on
# the cancel paths.
#
# (The map-lights and FX lanes this test also covered went with the fork's
# lighting and FX removal, F-08.)

const Jobs = preload("res://addons/highpoly_toggle/highpoly_jobs.gd")
const MC = preload("res://addons/highpoly_toggle/highpoly_mapcontext.gd")

var fails := 0


func _init() -> void:
	await process_frame

	# ---- the lane bookkeeping itself --------------------------------------
	var jobs = Jobs.new()
	get_root().add_child(jobs)
	jobs.set_activity("A", 1, 10)
	jobs.set_activity("B", 5, 10)
	_check("two jobs hold two separate lanes", jobs.busy())
	jobs.clear_activity("A")
	_check("clearing one lane leaves the other", jobs.busy())
	jobs.clear_activity("B")
	_check("clearing the last lane frees the bar", not jobs.busy())
	# a label typo would open one lane and close another, stranding a bar
	jobs.set_activity(MC.UNPACK_JOB, 3, 10)
	jobs.clear_activity(MC.UNPACK_JOB)
	_check("the unpack lane closes under the shared constant", not jobs.busy())

	print("\n%s" % ("ALL PASS" if fails == 0 else "%d FAILED" % fails))
	quit(0 if fails == 0 else 1)


func _check(what: String, ok: bool) -> void:
	print("  %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fails += 1
