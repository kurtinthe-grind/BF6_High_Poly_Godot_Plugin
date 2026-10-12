@tool
extends VBoxContainer

# ON-DEMAND CACHE SERVICE, ONE MAP AT A TIME.
#
# It used to start the moment a verified install was selected - every launch -
# and cache all ~19 maps behind an exclusive screen that covered the editor,
# with High Poly locked until it finished: about 3 minutes, ~2.9 GB written and
# up to three extra headless editors, for maps nobody was opening
# (2026-10-12-optimization-findings.md, OPT-06). Now nothing runs until the user
# presses "Cache this map" (or turns on the opt-in auto-cache), and then only for
# that map:
#
#   1. game cache - the shared C++ cache (BF6Core precache_*) for that level:
#                   placements, mesh and texture references, terrain.
#   2. map index  - that map's mount index, partition index and placement walk,
#                   in one headless worker (highpoly_prepare_worker.gd).
#
# Progress shows in this panel row. There is no cover screen and nothing is
# locked: an uncached map still builds, it just reads everything from the
# install the first time. The geometry and texture packs that make the NEXT
# build fast are written by that build itself (highpoly_gamesource.gd).
#
# Invalidation is unchanged: the game cache is keyed by the install identity and
# the core recipe; map indexes by the identity and the reader scripts
# (Cache.reader_recipe), and a map's superseded index files are deleted once it
# has been indexed again.
const Cache = preload("highpoly_install_cache.gd")
const Log = preload("highpoly_log.gd")
const API_VERSION := 3
const SERVICE_GROUP := "bf6_highpoly_preparation_v1"
const FORMAT := 3
const POLL_SECONDS := 0.25
const WEIGHTS := {"core": 0.40, "index": 0.60}
const INDEX_SECONDS_GUESS := 12.0   # a map's first index, until one has been measured
const NO_RESULT := "The map index worker exited without a result; the map indexes itself when opened."
# GEOMETRY is the index stage; the name is kept for callers reading stage_name.
enum Stage { IDLE, CHECKING, CORE, GEOMETRY, PREVIEWS, READY, PAUSED, FAILED }

signal ready_changed(is_ready: bool)
signal level_cached(level: String)
# Asks the host to bring the panel forward (BF6 Home's "show progress").
signal focus_requested

# ---- hooks. Defaults do the real work; tests replace them. ----
var current_level := Callable()      # () -> String, the open map
var pack_info := Callable()          # (level) -> {"geom": int, "tex": int}
var check_runner := Callable()       # (install) -> Dictionary, runs on a thread
var core_factory := Callable()       # (install, cache_root) -> core or null
var spawn_worker := Callable()       # (job: Dictionary) -> pid
var process_running := Callable()    # (pid) -> bool
var busy_reason := Callable()        # () -> String; non-empty refuses a start
var record_path := "user://highpoly/preparation.json"
var jobs_dir := "user://highpoly/preparation_jobs"
var poll_seconds := POLL_SECONDS

var install := ""
var identity := ""
var reader := ""
var cache_ready := false   # the last requested map finished; nothing waits on it
var stage := Stage.IDLE
var _levels: Array = []
var _requested: Array = []   # the map(s) asked for - one, in practice
var _record: Dictionary = {}
var _message := ""
var _error := ""

var _core: RefCounted
var _core_status: Dictionary = {}
var _core_done := false
var _index_done := false
var _scan: Thread
var _scan_install := ""
var _queue: Array = []
var _jobs: Array = []           # running index workers: {pid, level, status, cancel, report, started, files}
var _retries := {}
var _cancel_requested := false
var _started_ms := 0
var _overall_floor := 0.0

var _timer: Timer
var _status: Label
var _bar: ProgressBar
var _row: HBoxContainer
var _cache_btn: Button
var _cancel_btn: Button
var auto_chk: Button

func _enter_tree() -> void:
	# Runtime discovery only; never write service membership into a map scene.
	add_to_group(SERVICE_GROUP, false)

# The controls are built at construction, not in _ready: the plugin wires them
# (the auto-cache chip's saved state, its toggled signal) while its panel is
# still outside the tree, before _ready has run.
func _init() -> void:
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 3
	add_child(_status)
	_bar = ProgressBar.new()
	_bar.show_percentage = true
	_bar.max_value = 100.0
	_bar.visible = false
	add_child(_bar)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_row)
	_cache_btn = Button.new()
	_cache_btn.text = "Cache this map"
	_cache_btn.tooltip_text = "Prepares the map you have open, and only that map: the game cache and the map's index. Nothing is cached when Godot starts. High-Poly works without it too; the first build then reads everything from your install, and it also writes the geometry and texture packs that make later builds of this map fast."
	_cache_btn.pressed.connect(func(): cache_level(_open_level()))
	_row.add_child(_cache_btn)
	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.tooltip_text = "Stops after the current step. What is already cached is kept."
	_cancel_btn.pressed.connect(func(): cancel())
	_row.add_child(_cancel_btn)
	auto_chk = Button.new()
	auto_chk.toggle_mode = true
	auto_chk.text = "Auto-cache"
	auto_chk.tooltip_text = "Cache the open map automatically when you switch it to High-Poly or turn on a map layer, if it is not cached yet. Off by default."
	_row.add_child(auto_chk)


func _ready() -> void:
	_record = Cache.read_record(record_path)
	if int(_record.get("format", 0)) != FORMAT:
		_record = {"format": FORMAT}
	# CREATED, NOT STARTED. The poll only runs while a requested run is working,
	# so an idle service costs nothing.
	_timer = Timer.new()
	_timer.wait_time = poll_seconds
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_refresh()

func is_polling() -> bool:
	return _timer != null and not _timer.is_stopped()

func _poll(on: bool) -> void:
	if _timer == null:
		return
	if on and _timer.is_stopped() and _timer.is_inside_tree():
		_timer.start()
	elif not on:
		_timer.stop()

# ---- installation -----------------------------------------------------------
# Stored only. The check (identity, recipe, opening the game cache and sweeping
# its stale keys) runs the first time a map is asked for, never at enable.
func set_install(path: String) -> void:
	if install == path:
		return
	_stop_all()
	# Told to cancel above (its .cancel file stays for it to read; the
	# outdated-cache sweep takes the leftovers). A job from the old install must
	# not block, or be recorded by, the next run.
	_jobs.clear()
	_queue.clear()
	_cancel_requested = false
	install = path
	identity = ""
	_core = null
	_levels.clear()
	_requested.clear()
	_set_ready(false)
	stage = Stage.IDLE
	_message = "" if not path.is_empty() else "Waiting for a verified game installation."
	_refresh()

static func cache_root() -> String:
	# One cache for both editors: the Unreal plugin reads the same folder.
	var base := OS.get_environment("LOCALAPPDATA")
	if base.is_empty():
		base = OS.get_user_data_dir()
	return base.replace("\\", "/").path_join("BF6HighPoly")

# ---- the on-demand entry points ------------------------------------------------
# Start caching ONE map. Returns false when nothing can start (no install, no
# map open, or a run is already working on something).
func cache_level(level: String) -> bool:
	level = level.strip_edges().to_lower()
	if install.is_empty():
		_message = "Locate your Battlefield 6 installation first."
		_refresh()
		return false
	if level.is_empty():
		_message = "Open a map scene first, then cache it."
		_refresh()
		return false
	if is_running():
		return _requested.has(level)
	var busy := str(busy_reason.call()) if busy_reason.is_valid() else ""
	if not busy.is_empty():
		_message = busy
		_refresh()
		return false
	if not _levels.is_empty() and level not in _levels:
		_message = "%s is not a Battlefield 6 map this install has, so there is nothing to cache." % level
		_refresh()
		return false
	_requested = [level]
	_cancel_requested = false
	_error = ""
	_overall_floor = 0.0
	_started_ms = Time.get_ticks_msec()
	_set_ready(false)
	_log("cache this map: %s requested" % level)
	if _core != null and not identity.is_empty():
		_begin()
	else:
		_start_check()
	_poll(true)
	_refresh()
	return true

# Map selector / BF6 Home entry point (API 1-3). Only the FIRST map is cached:
# the service never caches more than the map that was asked for.
func prepare_levels(levels: Array, _force := false) -> bool:
	if levels.is_empty():
		return false
	var first := str(levels[0]).strip_edges().to_lower()
	if is_level_cached(first):
		return true
	return cache_level(first)

func is_running() -> bool:
	return stage in [Stage.CHECKING, Stage.CORE, Stage.GEOMETRY]

func cancel() -> void:
	if not is_running():
		return
	_cancel_requested = true
	_stop_all()
	_message = "Stopping after the current step..."
	_refresh()

# Kept for older callers: Home's "show caching progress" brings the panel up.
func show_progress() -> void:
	focus_requested.emit()

func open_preparation() -> void:
	show_progress()

func pause() -> void:
	cancel()

func resume() -> void:
	if stage in [Stage.PAUSED, Stage.FAILED] and not _requested.is_empty():
		var level: String = _requested[0]
		stage = Stage.IDLE
		cache_level(level)

# Is this map's index and game cache ready? Read from the record only, so it is
# cheap enough to ask on every scene switch. A reader change invalidates it.
func is_level_cached(level: String) -> bool:
	level = level.to_lower()
	var entry := _map_entry(level)
	if str(entry.get("state", "")) != "prepared":
		return false
	if not (_record.get("core_levels", {}) as Dictionary).has(level):
		return false
	var current_reader := reader if not reader.is_empty() else Cache.reader_recipe()
	return str(_record.get("reader", "")) == current_reader

# ---- check ---------------------------------------------------------------------
func _start_check() -> void:
	if install.is_empty() or _scan != null:
		return
	stage = Stage.CHECKING
	_message = "Checking Battlefield 6..."
	_scan_install = install
	_scan = Thread.new()
	var captured := install
	var root := cache_root()
	var runner := check_runner if check_runner.is_valid() else _default_check
	var factory := core_factory if core_factory.is_valid() else _default_core
	# Identity, recipe and opening the cache all hash files; keep them off the editor thread.
	if _scan.start(func():
		var checked: Dictionary = runner.call(captured)
		if checked.get("ok", false) and not checked.has("core"):
			var core = factory.call(captured, root)
			if core is Dictionary:
				checked["core_error"] = str(core.get("error", "unknown error"))
			elif core != null:
				checked["core"] = core
		return checked) != OK:
		_scan = null
		_fail("Could not start the game-file check.")

static func _default_check(path: String) -> Dictionary:
	var checked: Dictionary = Cache.inspect(path)
	checked["reader"] = Cache.reader_recipe()
	return checked

# Opening the shared game cache also sweeps its stale keys - which is why it is
# here, on the on-demand path, and not at plugin enable.
static func _default_core(path: String, root: String):
	if not ClassDB.class_exists("BF6Core"):
		return {"error": "The native high-poly reader is missing."}
	var core = ClassDB.instantiate("BF6Core")
	if core == null or not core.has_method("precache_open"):
		return {"error": "Restart Godot after updating the High Poly native reader."}
	DirAccess.make_dir_recursive_absolute(root)
	if not core.precache_open(path, root):
		return {"error": str(core.last_error())}
	core.precache_sweep()
	return core

func _finish_check(result: Dictionary) -> void:
	Cache.accept(install, result)
	if not result.get("ok", false):
		_fail("Game files could not be verified: %s" % str(result.get("error", "")))
		return
	if not result.has("core"):
		_fail("The game cache could not be opened: %s" % str(result.get("core_error", "unknown error")))
		return
	identity = str(result["identity"])
	reader = str(result.get("reader", ""))
	_levels = (result.get("levels", []) as Array).duplicate()
	_core = result["core"]
	if str(_record.get("identity", "")) != identity:
		_record = {"format": FORMAT, "identity": identity}
	if str(_record.get("reader", "")) != reader:
		_record["reader"] = reader
		_record["maps"] = {}          # map indexes follow the reader scripts
	_save()
	# Cancel pressed while the check ran: _stop_all had nothing to stop yet.
	if _cancel_requested:
		_cancelled()
		return
	if _requested.is_empty():
		stage = Stage.IDLE
		_message = ""
		_poll(false)
		return
	_begin()

func _begin() -> void:
	var level: String = _requested[0]
	if level not in _levels:
		_requested.clear()
		stage = Stage.IDLE
		_message = "%s is not a Battlefield 6 map this install has, so there is nothing to cache." % level
		_poll(false)
		_refresh()
		return
	_core_done = false
	_index_done = false
	_start_core()

# ---- stage 1: the game cache, for the requested map only (C4) -------------------
func _start_core() -> void:
	stage = Stage.CORE
	var rc: int = _core.precache_start(",".join(_requested), 0)
	if rc != 0:
		_fail("The game cache could not start (code %d)." % rc)
		return
	_message = "Game cache: %s..." % _requested[0]
	var parsed: Variant = JSON.parse_string(_core.precache_status())
	_core_status = parsed if parsed is Dictionary else {}
	_refresh()

func _poll_core() -> void:
	var parsed: Variant = JSON.parse_string(_core.precache_status())
	if not parsed is Dictionary:
		return
	_core_status = parsed
	var state := int(_core_status.get("state", 0))
	if state == 1 or state == 2:
		# Progress only - no cover screen, no editing lock (C5).
		_message = _core_line()
		return
	if _cancel_requested:
		_cancelled()
		return
	if state == 4:
		_fail("Game cache failed: %s" % str(_core_status.get("error", "")))
		return
	if state == 3 and bool(_core_status.get("ready", false)):
		_core_done = true
		var core_levels: Dictionary = _record.get("core_levels", {})
		for level in _requested:
			core_levels[level] = str(_core_status.get("key", ""))
		_record["core_levels"] = core_levels
		_save()
		_log("cache this map: game cache ready for %s after %.1f s"
			% [_requested[0], (Time.get_ticks_msec() - _started_ms) / 1000.0])
		_start_index()

func _core_line() -> String:
	var map := str(_core_status.get("current_map", ""))
	if map.is_empty():
		return "Game cache: finishing shared data..."
	var line := "Game cache: %s  ·  %s" % [map, str(_core_status.get("current_layer", ""))]
	var quiet := float(_core_status.get("since_update", 0.0))
	if quiet >= 3.0:
		line += "  (working, %d s)" % int(quiet)
	return line

func _map_entry(level: String) -> Dictionary:
	var maps: Dictionary = _record.get("maps", {})
	var entry = maps.get(level, {})
	return entry if entry is Dictionary else {}

# ---- stage 2: the map index, for the requested map only (C6, C7) ----------------
# No user://bf6_geom deletion here any more: the geometry pack is real cache now.
func _start_index() -> void:
	stage = Stage.GEOMETRY
	_queue.clear()
	_retries.clear()
	for level in _requested:
		var entry := _map_entry(level)
		var interrupted := str(entry.get("state", "")) == "failed" and str(entry.get("error", "")) == NO_RESULT
		if interrupted or str(entry.get("state", "")) != "prepared":
			_queue.append(level)
	if _queue.is_empty():
		_finish()
		return
	_next_index()

func _next_index() -> void:
	if _cancel_requested:
		if _jobs.is_empty():
			_cancelled()
		return
	if _queue.is_empty() and _jobs.is_empty():
		_finish()
		return
	while not _queue.is_empty() and _jobs.is_empty():
		if int(OS.get_memory_info().get("free", 1 << 40)) < 4 * 1024 * 1024 * 1024:
			_fail("Caching stopped: free at least 4 GB of memory, then press Cache this map again.")
			return
		var level := str(_queue.pop_front())
		var id := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
		var job_path := "%s/%s.json" % [jobs_dir, id]
		var status_path := "%s/%s.status.json" % [jobs_dir, id]
		var job := {"level": level, "status": status_path, "cancel": "%s/%s.cancel" % [jobs_dir, id],
			"report": {}, "started": Time.get_ticks_msec(), "pid": -1,
			"files": [job_path, status_path, "%s/%s.cancel" % [jobs_dir, id],
				status_path + ".engine.log", status_path.trim_suffix(".json") + ".logs"]}
		var data := {"install": install, "identity": identity, "recipe": reader, "level": level, "force": false,
			"index_only": true, "record_textures": false, "foreground": true, "memory_reserve_bytes": 4 * 1024 * 1024 * 1024,
			"parent_pid": OS.get_process_id(),
			"status": ProjectSettings.globalize_path(status_path),
			"cancel": ProjectSettings.globalize_path(str(job.cancel))}
		if not Cache.write_record(job_path, data):
			_fail("Could not write the map index job. Check cache-folder permissions.")
			return
		var spawn_data := data.duplicate()
		spawn_data["job_path"] = job_path
		spawn_data["status_local"] = status_path
		job.pid = spawn_worker.call(spawn_data) if spawn_worker.is_valid() else _default_spawn(spawn_data)
		if int(job.pid) < 0:
			_fail("Could not start the map index worker.")
			return
		_jobs.append(job)
	_message = _index_line()

func _default_spawn(data: Dictionary) -> int:
	var script: String = get_script().resource_path.get_base_dir().path_join("highpoly_prepare_worker.gd")
	return OS.create_process(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--log-file", ProjectSettings.globalize_path(str(data["status_local"]) + ".engine.log"),
		"--script", ProjectSettings.globalize_path(script), "--",
		ProjectSettings.globalize_path(str(data["job_path"]))]), false)

func _is_running(pid: int) -> bool:
	return process_running.call(pid) if process_running.is_valid() else OS.is_process_running(pid)

func _index_line() -> String:
	if _jobs.is_empty():
		return "Map index: waiting"
	var job: Dictionary = _jobs[0]
	var report: Dictionary = job.report
	return "Map index: %s (%s, %d s)" % [job.level, str(report.get("stage", "starting")),
		int((Time.get_ticks_msec() - int(job.started)) / 1000)]

func _index_seconds() -> float:
	var total := 0.0
	var n := 0
	for entry in _record.get("maps", {}).values():
		if entry is Dictionary and float(entry.get("seconds", 0.0)) > 0.0:
			total += float(entry.seconds)
			n += 1
	return total / n if n > 0 else INDEX_SECONDS_GUESS

func _job_fraction(job: Dictionary) -> float:
	return minf(0.95, (Time.get_ticks_msec() - int(job.started)) / 1000.0 / maxf(1.0, _index_seconds()))

func _poll_index() -> void:
	var finished: Array = []
	for job in _jobs:
		if _is_running(int(job.pid)):
			var status := Cache.read_record(str(job.status))
			if not status.is_empty():
				job.report = status
		else:
			finished.append(job)
	for job in finished:
		_jobs.erase(job)
		# Read after exit so the report is final rather than a mid-run snapshot.
		var status := Cache.read_record(str(job.status))
		_delete_job_files(job)      # OPT-19: they were never removed (457 left on one machine)
		var level := str(job.level)
		var state := str(status.get("state", ""))
		var why := str(status.get("error", ""))
		if _cancel_requested or state in ["paused", "stale"]:
			if state == "stale":
				_fail(why if not why.is_empty() else "The game or the add-on changed; press Cache this map again.")
				identity = ""
				_core = null
				return
			if state == "paused" and not _cancel_requested:
				_fail(why if not why.is_empty() else "The index worker paused.")
				return
			continue
		var complete: bool = state == "prepared" and status.get("identity", "") == identity \
			and status.get("recipe", "") == reader and status.get("level", "") == level
		# INTERRUPTED IS NOT FAILED: a worker that ends without a final state runs once more.
		if not complete and not state in ["failed", "prepared"] and int(_retries.get(level, 0)) < 1:
			_retries[level] = int(_retries.get(level, 0)) + 1
			_queue.push_back(level)
			continue
		if not complete:
			state = "failed"
			if why.is_empty():
				why = NO_RESULT
		var maps: Dictionary = _record.get("maps", {})
		var secs := (Time.get_ticks_msec() - int(job.started)) / 1000.0
		maps[level] = {"state": state, "error": why, "placements": int(status.get("placements", 0)),
			"seconds": secs}
		_record["maps"] = maps
		_save()
		_log("cache this map: %s index %s in %.1f s%s" % [level, state, secs,
			"" if why.is_empty() else " (%s)" % why])
		if complete:
			_sweep_index_files(level, str(status.get("signature", "")))
	if not _jobs.is_empty() or not finished.is_empty():
		_message = _index_line()
	if _cancel_requested and _jobs.is_empty():
		_cancelled()
		return
	if not finished.is_empty():
		_next_index()

static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		DirAccess.remove_absolute(path)
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)

static func _delete_job_files(job: Dictionary) -> void:
	for f in job.get("files", []):
		var p := str(f)
		if DirAccess.dir_exists_absolute(p):
			_remove_tree(p)
		elif FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

# Superseded index files for one map: every bf6_index/pidx/walk file of that map
# whose signature is not the one its worker just built or verified.
static func _sweep_index_files(level: String, signature: String) -> int:
	if signature.is_empty():
		return 0
	var removed := 0
	var dir := DirAccess.open("user://")
	if dir == null:
		return 0
	for f in dir.get_files():
		var n := str(f)
		if not n.ends_with(".idx") or n.ends_with("_%s.idx" % signature):
			continue
		for kind in ["bf6_index_", "bf6_pidx_", "bf6_walk_"]:
			if n.begins_with(kind + level + "_v"):
				if DirAccess.remove_absolute("user://" + n) == OK:
					removed += 1
				break
	return removed

func _finish() -> void:
	_index_done = true
	stage = Stage.READY
	var level: String = _requested[0] if not _requested.is_empty() else ""
	_message = "%s is cached (%.1f s)." % [level, (Time.get_ticks_msec() - _started_ms) / 1000.0]
	_log("cache this map: " + _message)
	_poll(false)
	_set_ready(true)
	level_cached.emit(level)
	_refresh()

func _cancelled() -> void:
	_cancel_requested = false
	stage = Stage.PAUSED
	_message = "Caching cancelled. What finished is kept; press Cache this map to continue."
	_poll(false)
	_refresh()

func _fail(why: String) -> void:
	stage = Stage.FAILED
	_error = why
	_message = why
	_log("cache this map FAILED: " + why, true)
	_poll(false)
	_refresh()

func _set_ready(value: bool) -> void:
	if cache_ready == value:
		return
	cache_ready = value
	ready_changed.emit(value)

func _stop_all() -> void:
	if _core != null and _core.has_method("precache_cancel") and stage == Stage.CORE:
		_core.precache_cancel()
	for job in _jobs:
		if _is_running(int(job.pid)):
			var file := FileAccess.open(str(job.cancel), FileAccess.WRITE)
			if file != null:
				file.store_string("cancel")
				file.close()

func _save() -> void:
	Cache.write_record(record_path, _record)

static func _log(msg: String, warn := false) -> void:
	if warn:
		Log.warn(msg)
	else:
		Log.info(msg)

# ---- progress (C13: the requested map only) ---------------------------------------
func overall_fraction() -> float:
	if _requested.is_empty():
		return 0.0
	var core := 1.0 if _core_done else float(_core_status.get("overall", 0.0))
	var index := 1.0 if _index_done else 0.0
	if not _index_done:
		for job in _jobs:
			index = maxf(index, _job_fraction(job))
	var value: float = WEIGHTS.core * core + WEIGHTS.index * index
	_overall_floor = maxf(_overall_floor, value)
	return _overall_floor

func snapshot() -> Dictionary:
	return {"stage": stage, "stage_name": Stage.keys()[stage], "install": install, "message": _message,
		"error": _error, "overall": overall_fraction(), "levels": _requested.duplicate(),
		"core_done": _core_done, "geometry_done": _index_done, "index_jobs": _jobs.size(),
		"ready": cache_ready, "running": is_running(), "stopping": _cancel_requested,
		"cache_root": cache_root()}

func _open_level() -> String:
	return str(current_level.call()).to_lower() if current_level.is_valid() else ""

# What the panel says about the open map. Cheap: the record plus the pack
# counts the host reports (directory listings only).
func status_line() -> String:
	var level := _open_level()
	if install.is_empty():
		return "Battlefield 6 is not located, so nothing can be cached."
	if level.is_empty():
		return "Open a map to see whether it is cached."
	var parts := PackedStringArray()
	parts.append("%s: %s" % [level, "index cached" if is_level_cached(level) else "not cached"])
	if pack_info.is_valid():
		var info: Dictionary = pack_info.call(level)
		parts.append("geometry pack %s" % (("%d meshes" % int(info.get("geom", 0))) if int(info.get("geom", 0)) > 0 else "empty"))
		parts.append("texture pack %s" % (("%d textures" % int(info.get("tex", 0))) if int(info.get("tex", 0)) > 0 else "empty"))
	var line := "  ·  ".join(parts)
	if not is_level_cached(level):
		line += "\nHigh-Poly still works; the first build reads from your install."
	return line

func refresh_status() -> void:
	_refresh()

func _refresh() -> void:
	if not is_node_ready():
		return
	var running := is_running()
	_bar.visible = running
	_bar.value = overall_fraction() * 100.0
	var text := status_line()
	if not _message.is_empty() and (running or stage in [Stage.FAILED, Stage.PAUSED, Stage.READY]):
		text = _message + "\n" + text if stage != Stage.READY else text + "\n" + _message
	_status.text = text
	_status.tooltip_text = text
	_cache_btn.disabled = running or install.is_empty() or _open_level().is_empty()
	_cache_btn.text = "Caching…" if running else "Cache this map"
	_cancel_btn.visible = running

func _tick() -> void:
	if _scan != null and not _scan.is_alive():
		var result: Dictionary = _scan.wait_to_finish()
		_scan = null
		if _scan_install != install:
			if not _requested.is_empty():
				_start_check()
			return
		_finish_check(result)
	match stage:
		Stage.CORE: _poll_core()
		Stage.GEOMETRY: _poll_index()
	_refresh()

func _exit_tree() -> void:
	remove_from_group(SERVICE_GROUP)
	_stop_all()
	if _scan != null:
		_scan.wait_to_finish()
		_scan = null
	# Joins the core's build thread; completed maps are kept and verified next time.
	_core = null
