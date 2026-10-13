extends SceneTree
# OPT-05: the native heightfield (134-537 MB) was decoded by the core and
# written to height_game.r16 on EVERY open, with no read-back. It is now read
# back when its meta matches the heightfield family key and the file is whole;
# anything else - another key, a short file, broken meta - is a miss.

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("FORKTEST PASS " if cond else "FORKTEST FAIL ") + what)
	if not cond:
		fails += 1


func _init() -> void:
	var GS = load("res://addons/highpoly_toggle/highpoly_gamesource.gd")
	var dir := OS.get_temp_dir().replace("\\", "/").path_join("hp_hf_%d" % Time.get_ticks_usec())
	var heights := PackedByteArray()
	heights.resize(64 * 64 * 2)
	for i in range(heights.size()):
		heights[i] = i % 251
	var meta := {"res": 64, "world_min": -100.0, "world_max": 100.0, "world_min_z": -90.0,
		"world_max_z": 110.0, "scale": 321.5}
	check(GS.read_native_heightfield(dir, "k1").is_empty(), "nothing on disk is a miss")
	check(GS.write_native_heightfield(dir, "k1", heights, meta), "heightfield written")
	var back: Dictionary = GS.read_native_heightfield(dir, "k1")
	check(not back.is_empty(), "same key reads back")
	check(back.get("bytes", PackedByteArray()) == heights, "bytes round-trip exactly")
	var m: Dictionary = back.get("meta", {})
	check(int(m.get("res", 0)) == 64 and is_equal_approx(float(m.get("scale", 0)), 321.5)
		and is_equal_approx(float(m.get("world_min_z", 0)), -90.0), "meta round-trips")
	check(GS.read_native_heightfield(dir, "k2").is_empty(), "another key is a miss")
	# a short file (crashed writer) must not be served
	var f := FileAccess.open(dir.path_join("height_game.r16"), FileAccess.WRITE)
	f.store_buffer(heights.slice(0, 100))
	f.close()
	check(GS.read_native_heightfield(dir, "k1").is_empty(), "a truncated heightfield is a miss")
	check(GS.write_native_heightfield(dir, "k1", heights, meta), "rewritten")
	var j := FileAccess.open(dir.path_join(GS.NATIVE_HF_META), FileAccess.WRITE)
	j.store_string("{not json")
	j.close()
	check(GS.read_native_heightfield(dir, "k1").is_empty(), "broken meta is a miss, not a crash")
	check(GS.read_native_heightfield(dir, "").is_empty(), "an empty key never hits")
	for n in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(n))
	DirAccess.remove_absolute(dir)
	quit(1 if fails else 0)
