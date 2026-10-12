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
	quit(1 if fails else 0)
