extends SceneTree
# Cache keys that survive the edits they have nothing to do with.
#
# OPT-03: the texture read-ahead order was rejected unless its first line equal
#   the WHOLE add-on recipe, so every plugin build threw it away; and once an
#   order existed nothing new was ever learned. It is now keyed on its own
#   family recipe, and misses are appended.
# OPT-04: every per-map cache (ground packets ~400 MB, splat, near window,
#   heightfield) was keyed on the whole add-on, so a UI-only edit rewrote them
#   all. Each family now hashes only the files that produce it.

const Cache = preload("res://addons/highpoly_toggle/highpoly_install_cache.gd")

var fails := 0
var tmp := ""


func check(cond: bool, what: String) -> void:
	print(("FORKTEST PASS " if cond else "FORKTEST FAIL ") + what)
	if not cond:
		fails += 1


func put(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _fixture() -> String:
	var base := tmp.path_join("addon")
	for n in Cache.READER_FILES:
		put(base.path_join(n), "reader " + n)
	for n in ["bf6_environment.gd", "bf6_splat.gd", "bf6_terrain.gd", "bf6_terrainlayers.gd",
			"bf6_texture.gd", "highpoly_bctex.gd", "highpoly_gamesource.gd", "bf6_meshset.gd",
			"highpoly_toggle.gd", "highpoly_cachesweep.gd", "highpoly_census.gd",
			"bin/bf6_core.dll", "bin/bf6_oodle.windows.x86_64.dll"]:
		put(base.path_join(n), "v1 " + n)
	# the real dependency contract, so the full-recipe check uses its exclude list
	put(base.path_join("cache_dependencies.json"),
		FileAccess.get_file_as_string("res://addons/highpoly_toggle/cache_dependencies.json"))
	return base


func _init() -> void:
	tmp = OS.get_temp_dir().replace("\\", "/").path_join("hp_keys_%d" % Time.get_ticks_usec())
	var base := _fixture()
	var fams := ["texture_order", "env", "heightfield", "splat", "textures"]
	var before := {}
	for f in fams:
		before[f] = Cache.family_recipe_for_root(base, f)
		check(str(before[f]).length() == 64, "%s family recipe is a sha256" % f)
	check(before["env"] != before["splat"], "families do not collide")
	var full_before := Cache.recipe_for_root(base, "4.6.3")
	check(full_before != "", "full recipe computes on the fixture")

	# ---- a UI-only edit ----
	put(base.path_join("highpoly_toggle.gd"), "v2 a new button")
	put(base.path_join("highpoly_cachesweep.gd"), "v2 sweep")
	put(base.path_join("highpoly_census.gd"), "v2 census")
	for f in fams:
		check(Cache.family_recipe_for_root(base, f) == before[f], "UI edit keeps the %s key" % f)
	check(Cache.recipe_for_root(base, "4.6.3") == full_before, "UI edit keeps the full recipe (excluded files)")

	# ---- an edit to what produces the ground packets ----
	put(base.path_join("bf6_environment.gd"), "v2 env")
	check(Cache.family_recipe_for_root(base, "env") != before["env"], "environment edit re-keys env")
	check(Cache.family_recipe_for_root(base, "texture_order") == before["texture_order"],
		"environment edit keeps the texture order")
	check(Cache.family_recipe_for_root(base, "splat") == before["splat"], "environment edit keeps splat")

	# ---- a reader edit re-keys everything ----
	put(base.path_join("bf6_source.gd"), "v2 reader")
	for f in fams:
		check(Cache.family_recipe_for_root(base, f) != before[f], "reader edit re-keys %s" % f)

	# ---- unknown family / missing file -> no key, never a shared one ----
	check(Cache.family_recipe_for_root(base, "nope") == "", "unknown family has no recipe")
	DirAccess.remove_absolute(base.path_join("bin/bf6_core.dll"))
	check(Cache.family_recipe_for_root(base, "env") == "", "missing producer file means no key")

	# ---- OPT-03: the texture order survives and keeps learning ----
	var GS = load("res://addons/highpoly_toggle/highpoly_gamesource.gd")
	var lvl := "mp_keytest_%d" % (Time.get_ticks_usec() % 100000)
	check(GS.save_texture_order(lvl, PackedStringArray(["tex/a", "tex/b"])), "order saved")
	var head := FileAccess.get_file_as_string(GS.texture_order_path(lvl)).split("\n")[0]
	check(head == Cache.family_recipe("texture_order"), "order header is the texture-order family key")
	var gs = GS.new()
	gs.level = lvl
	gs._load_texture_order()
	check(gs._tex_order.size() == 2, "a saved order loads (not rejected by the full recipe)")
	gs._pc_ready = true
	gs._pc_level = lvl
	gs._learned_level = lvl
	gs._learn_texture("tex/c")
	gs._learn_texture("tex/a")
	check(gs._learned.size() == 1 and gs._learned[0] == "tex/c", "a miss is learned even with an order loaded")
	gs._save_learned()
	var again = GS.new()
	again.level = lvl
	again._load_texture_order()
	check(Array(again._tex_order) == ["tex/a", "tex/b", "tex/c"],
		"the learned miss is appended to the order: %s" % str(again._tex_order))
	put(GS.texture_order_path(lvl), "stale-header\ntex/x")
	var stale = GS.new()
	stale.level = lvl
	stale._load_texture_order()
	check(stale._tex_order.is_empty(), "an order with another header is ignored")
	DirAccess.remove_absolute(GS.texture_order_path(lvl))
	quit(1 if fails else 0)
