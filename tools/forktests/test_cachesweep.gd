extends SceneTree
# Keep the newest file of each cache family; drop the superseded ones and
# temp logs a killed session left behind; never touch anything else.

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("FORKTEST PASS " if cond else "FORKTEST FAIL ") + what)
	if not cond:
		fails += 1


func _f(n: String, t: int) -> Dictionary:
	return {"name": n, "mtime": t, "size": 100}


func _init() -> void:
	var cs = load("res://addons/highpoly_toggle/highpoly_cachesweep.gd")
	check(cs != null, "highpoly_cachesweep.gd loads")
	if cs == null:
		quit(1)
		return
	var now := 2000000000
	var files := [
		_f("bf6_index_all_v4_aaaaaaaaaaaaaaaa.idx", 100),
		_f("bf6_index_all_v4_bbbbbbbbbbbbbbbb.idx", 300),
		_f("bf6_index_all_v3_cccccccccccccccc.idx", 50),
		_f("bf6_index_mp_portal_sand_v4_dddddddddddddddd.idx", 10),
		_f("bf6_index_mp_portal_sand_v4_eeeeeeeeeeeeeeee.idx", 20),
		_f("bf6_index_mp_isolated_v4_ffffffffffffffff.idx", 5),
		_f("bf6_pidx_mp_isolated_v4_ffffffffffffffff.idx", 5),
		_f("bf6_walk_mp_granite_v4_1111111111111111.idx", 7),
		_f("highpoly-session.log123.tmp", now - 3 * 86400),
		_f("highpoly-session.log456.tmp", now - 60),
		_f("highpoly-session.log", now - 3 * 86400),
		_f("probe_assets.tres", 1),
	]
	var out: PackedStringArray = cs.outdated(files, now)
	check(out.has("bf6_index_all_v4_aaaaaaaaaaaaaaaa.idx"), "older all-levels index dropped")
	check(out.has("bf6_index_all_v3_cccccccccccccccc.idx"), "older-version all-levels index dropped")
	check(not out.has("bf6_index_all_v4_bbbbbbbbbbbbbbbb.idx"), "newest all-levels index kept")
	check(out.has("bf6_index_mp_portal_sand_v4_dddddddddddddddd.idx"), "older map index dropped")
	check(not out.has("bf6_index_mp_portal_sand_v4_eeeeeeeeeeeeeeee.idx"), "newest map index kept")
	check(not out.has("bf6_index_mp_isolated_v4_ffffffffffffffff.idx"), "only copy of a map kept")
	check(not out.has("bf6_pidx_mp_isolated_v4_ffffffffffffffff.idx"), "families are separate")
	check(not out.has("bf6_walk_mp_granite_v4_1111111111111111.idx"), "walk index kept")
	check(out.has("highpoly-session.log123.tmp"), "day-old temp log dropped")
	check(not out.has("highpoly-session.log456.tmp"), "a live session's temp log kept")
	check(not out.has("highpoly-session.log"), "the real log kept")
	check(not out.has("probe_assets.tres"), "unrelated files untouched")
	check(out.size() == 4, "exactly four files")

	# ---- the pack folders (OPT-01 geometry, OPT-02 textures) ----
	var geom := [
		_f("mp_battery_aaaaaaaaaaaaaaaa_g12", 100),
		_f("mp_battery_bbbbbbbbbbbbbbbb_g12", 300),
		_f("mp_battery_bbbbbbbbbbbbbbbb_g12_vlow", 50),
		_f("mp_isolated_cccccccccccccccc_g11", 10),
		_f("not_a_pack", 1),
	]
	var gd: PackedStringArray = cs.outdated_dirs(geom, cs.GEOM_DIR)
	check(gd.has("mp_battery_aaaaaaaaaaaaaaaa_g12"), "older geometry pack of a map dropped")
	check(not gd.has("mp_battery_bbbbbbbbbbbbbbbb_g12"), "newest geometry pack kept")
	check(not gd.has("mp_battery_bbbbbbbbbbbbbbbb_g12_vlow"), "another VRAM mode is its own family")
	check(not gd.has("mp_isolated_cccccccccccccccc_g11"), "a map's only pack kept")
	check(not gd.has("not_a_pack") and gd.size() == 1, "only pack folders are touched")
	var tex := [
		_f("mp_battery_0123456789abcdef", 10),
		_f("mp_battery_fedcba9876543210", 20),
		_f("mp_dumbo_0000000000000000", 5),
	]
	var td: PackedStringArray = cs.outdated_dirs(tex, cs.TEX_DIR)
	check(td.size() == 1 and td.has("mp_battery_0123456789abcdef"), "older texture pack dropped, newest kept")

	# ---- index-worker job files a crash left behind (OPT-19) ----
	var jobs := [
		_f("123_456.json", now - 3 * 86400),
		_f("123_456.status.json", now - 3 * 86400),
		_f("777_888.json", now - 60),
	]
	var jd: PackedStringArray = cs.stale_jobs(jobs, now)
	check(jd.size() == 2 and not jd.has("777_888.json"), "day-old job files dropped, a live job kept")
	quit(1 if fails else 0)
