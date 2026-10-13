extends SceneTree
# Caching is ON DEMAND and for ONE map (owner request, findings §3 C1-C15):
#   * enabling the plugin with a verified install starts no check, no game-cache
#     run, no worker process and no cover screen;
#   * cache_level(x) runs the game cache for x only, then one index worker for x
#     only, and deletes that worker's job files once it has read them;
#   * prepare_levels([a, b]) caches only the first map;
#   * an uncached map does not lock anything: cache_ready is about the map that
#     was asked for, and nothing else waits on it.
# The native core and the worker process are replaced through the service's own
# hooks; nothing touches the real install or the live user:// folder.

const Preparation = preload("res://addons/highpoly_toggle/highpoly_preparation.gd")

var fails := 0
var checks := 0
var cores_made := 0
var spawned: Array = []
var tmp := ""


class FakeCore extends RefCounted:
	var started: Array = []
	var polls := 0
	func precache_start(list: String, _flags: int) -> int:
		started.append(list)
		polls = 0
		return 0
	func precache_status() -> String:
		polls += 1
		if polls < 3:
			return JSON.stringify({"state": 2, "overall": 0.5, "current_map": started[-1]})
		return JSON.stringify({"state": 3, "ready": true, "overall": 1.0, "key": "k1"})
	func precache_cancel() -> bool:
		return true


var core := FakeCore.new()


func check(cond: bool, what: String) -> void:
	print(("FORKTEST PASS " if cond else "FORKTEST FAIL ") + what)
	if not cond:
		fails += 1


# The service's timer is not relied on here: --quit-after bounds the frames a
# test may take, so the loops below drive _tick() themselves, once a frame.
func pump(n := 1) -> void:
	for i in range(n):
		await process_frame


func _initialize() -> void:
	run()


func run() -> void:
	tmp = OS.get_temp_dir().replace("\\", "/").path_join("hp_prep_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var prep = Preparation.new()
	prep.record_path = tmp.path_join("preparation.json")
	prep.jobs_dir = tmp.path_join("jobs")
	prep.check_runner = func(_install: String) -> Dictionary:
		checks += 1
		return {"ok": true, "identity": "id-1", "reader": "rd-1",
			"levels": ["mp_a", "mp_b", "mp_c"], "core": core}
	prep.core_factory = func(_install: String, _root: String):
		cores_made += 1
		return core
	prep.spawn_worker = func(job: Dictionary) -> int:
		spawned.append(job)
		# the worker's whole life: write a final status and exit
		var status := {"state": "prepared", "identity": job["identity"], "recipe": job["recipe"],
			"level": job["level"], "signature": "", "placements": 10}
		Preparation.Cache.write_record(str(job["status_local"]), status)
		return 4242
	prep.process_running = func(_pid: int) -> bool: return false
	root.add_child(prep)
	await pump(2)

	# ---- enable: nothing runs ----
	prep.set_install("C:/fake/Battlefield 6")
	await pump(20)
	check(checks == 0, "enabling with an install runs no game-file check")
	check(cores_made == 0 and core.started.is_empty(), "enabling starts no game-cache run")
	check(spawned.is_empty(), "enabling starts no worker process")
	check(prep.stage == Preparation.Stage.IDLE, "service stays idle")
	check(not prep.is_polling(), "no poll timer is running while idle")
	var windows := 0
	for c in root.get_children():
		if c is Window:
			windows += 1
	check(windows == 0, "no cover screen is created")
	check(not prep.is_level_cached("mp_a"), "nothing claims to be cached")

	# ---- the button: this map only ----
	check(prep.cache_level("mp_a"), "cache_level accepts the open map")
	var guard := 0
	while prep.stage != Preparation.Stage.READY and prep.stage != Preparation.Stage.FAILED and guard < 150:
		prep._tick()
		await pump()
		guard += 1
	check(prep.stage == Preparation.Stage.READY, "the run finishes (stage %s, %s)" % [prep.stage, prep._message])
	check(checks == 1, "the check ran once, on request")
	check(core.started == ["mp_a"], "the game cache ran for mp_a only: %s" % str(core.started))
	check(spawned.size() == 1 and str(spawned[0]["level"]) == "mp_a", "one index worker, for mp_a")
	check(prep.is_level_cached("mp_a"), "mp_a now reports cached")
	check(not prep.is_level_cached("mp_b"), "mp_b is untouched")
	check(prep.cache_ready, "cache_ready is true for the requested map")
	check(DirAccess.get_files_at(prep.jobs_dir).is_empty(), "the worker's job files were deleted after reading")
	check(not prep.is_polling(), "the poll timer stops when the run ends")

	# ---- a map selector asking for several maps gets one ----
	spawned.clear()
	check(prep.prepare_levels(["mp_b", "mp_c"]), "prepare_levels accepts a request")
	guard = 0
	while prep.stage != Preparation.Stage.READY and guard < 150:
		prep._tick()
		await pump()
		guard += 1
	await pump(5)
	check(core.started[-1] == "mp_b", "prepare_levels caches only the first map: %s" % str(core.started))
	check(not prep.is_level_cached("mp_c"), "the second map is not cached")

	# ---- an unknown map is refused, nothing runs ----
	var before: int = core.started.size()
	prep.cache_level("not_a_map")
	await pump(20)
	check(core.started.size() == before, "an unknown map starts nothing")

	prep.queue_free()
	await pump(2)
	for f in DirAccess.get_files_at(tmp):
		DirAccess.remove_absolute(tmp.path_join(f))
	DirAccess.remove_absolute(tmp.path_join("jobs"))
	DirAccess.remove_absolute(tmp)
	quit(1 if fails else 0)
