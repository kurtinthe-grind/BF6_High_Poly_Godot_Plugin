extends SceneTree
# Cancel is honoured in every stage of "Cache this map":
#   * pressed while the game-file check is still running, the run stops when the
#     check returns - no game-cache run and no worker start afterwards;
#   * a new install path drops the old run's index workers, so a later run is
#     not blocked behind a job that belongs to the previous install.
# The native core and the worker process are replaced through the service's own
# hooks; nothing touches the real install or the live user:// folder.

const Preparation = preload("res://addons/highpoly_toggle/highpoly_preparation.gd")

var fails := 0
var spawned: Array = []
var running_pids := {}


class FakeCore extends RefCounted:
	var started: Array = []
	func precache_start(list: String, _flags: int) -> int:
		started.append(list)
		return 0
	func precache_status() -> String:
		return JSON.stringify({"state": 3, "ready": true, "overall": 1.0, "key": "k1"})
	func precache_cancel() -> bool:
		return true


var core := FakeCore.new()


func check(cond: bool, what: String) -> void:
	print(("FORKTEST PASS " if cond else "FORKTEST FAIL ") + what)
	if not cond:
		fails += 1


func pump(n := 1) -> void:
	for i in range(n):
		await process_frame


func _initialize() -> void:
	run()


func run() -> void:
	var tmp := OS.get_temp_dir().replace("\\", "/").path_join("hp_prep_cancel_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp)
	var prep = Preparation.new()
	prep.record_path = tmp.path_join("preparation.json")
	prep.jobs_dir = tmp.path_join("jobs")
	prep.check_runner = func(_install: String) -> Dictionary:
		OS.delay_msec(300)          # still checking when Cancel is pressed
		return {"ok": true, "identity": "id-1", "reader": "rd-1",
			"levels": ["mp_a", "mp_b"], "core": core}
	prep.spawn_worker = func(job: Dictionary) -> int:
		spawned.append(job)
		running_pids[4242 + spawned.size()] = true   # this worker keeps running
		return 4242 + spawned.size()
	prep.process_running = func(pid: int) -> bool: return running_pids.has(pid)
	root.add_child(prep)
	await pump(2)
	prep.set_install("C:/fake/Battlefield 6")

	# ---- Cancel during the check ----
	check(prep.cache_level("mp_a"), "cache_level starts the check")
	check(prep.stage == Preparation.Stage.CHECKING, "the run is in the check stage")
	prep.cancel()
	var guard := 0
	while prep._scan != null and guard < 200:
		prep._tick()
		await pump()
		guard += 1
	prep._tick()
	check(core.started.is_empty(), "no game-cache run starts after Cancel: %s" % str(core.started))
	check(spawned.is_empty(), "no index worker starts after Cancel")
	check(prep.stage == Preparation.Stage.PAUSED, "the run reports cancelled (stage %s)" % prep.stage)
	check(not prep.is_running(), "nothing is running")

	# ---- a new install drops the previous run's workers ----
	check(prep.cache_level("mp_a"), "a new run starts")
	guard = 0
	while spawned.is_empty() and guard < 200:
		prep._tick()
		await pump()
		guard += 1
	check(spawned.size() == 1, "its index worker started")
	prep.set_install("D:/other/Battlefield 6")
	check(prep._jobs.is_empty(), "the old install's workers are dropped")
	check(FileAccess.file_exists(str(spawned[0]["cancel"])), "the old worker was told to cancel")

	prep.queue_free()
	await pump(2)
	for d in [tmp.path_join("jobs"), tmp]:
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
		DirAccess.remove_absolute(d)
	quit(1 if fails else 0)
