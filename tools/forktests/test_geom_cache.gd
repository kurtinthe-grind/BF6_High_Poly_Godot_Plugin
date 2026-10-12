extends SceneTree
# OPT-01: the geometry disk cache never served anything - it was skipped
# whenever the precache was active (every prepared map) and its folder was
# deleted on every launch. It is now ONE pack per map (segment files written on
# a worker, read back by name), used with or without the precache.
#
# Pinned here: the pack container round-trips, ignores and deletes corrupt or
# outdated segments without crashing, and the mesh codec plus the game source's
# save/load path give back the same surfaces with the same names.

const Pack = preload("res://addons/highpoly_toggle/highpoly_pack.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("FORKTEST PASS " if cond else "FORKTEST FAIL ") + what)
	if not cond:
		fails += 1


func _bytes(n: int, seed: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	for i in range(n):
		b[i] = (i * 7 + seed) % 256
	return b


func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(d))
	DirAccess.remove_absolute(dir)


func _mesh() -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)])
	arr[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 2, 1, 3])
	var arr2 := []
	arr2.resize(Mesh.ARRAY_MAX)
	arr2[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(0, 1, 1)])
	arr2[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	return [["1234|a", arr], ["5678", arr2]]


func _init() -> void:
	var tmp := OS.get_temp_dir().replace("\\", "/").path_join("hp_pack_%d" % Time.get_ticks_usec())

	# ---- the container ----
	var p = Pack.new()
	check(p.open(tmp, "key-a", 1) == 0, "a new pack opens empty")
	check(p.put("one", _bytes(1000, 1)), "put one")
	check(p.put("two", _bytes(70000, 2)), "put two")
	check(not p.put("one", _bytes(5, 9)), "a name already queued is not written twice")
	p.flush()
	check(p.has("one") and p.has("two") and p.count() == 2, "flushed records are readable")
	p.close()
	var q = Pack.new()
	check(q.open(tmp, "key-a", 1) == 2, "reopened: two records")
	check(q.get_bytes("two") == _bytes(70000, 2), "bytes round-trip exactly")
	check(q.get_bytes("missing").is_empty(), "a missing name is empty, not an error")
	check(Pack.count_in(tmp) == 2, "count_in reads the record count without opening")
	q.put("three", _bytes(10, 3))
	q.close()                       # close flushes
	check(Pack.count_in(tmp) == 3, "a second segment adds to the pack")

	# corrupt segments: garbage, and a valid segment cut short
	var segs := Array(DirAccess.get_files_at(tmp)).filter(func(f): return str(f).ends_with(".hpk"))
	var whole := FileAccess.get_file_as_bytes(tmp.path_join(segs[0]))
	var cut := FileAccess.open(tmp.path_join("seg_1_9.hpk"), FileAccess.WRITE)
	cut.store_buffer(whole.slice(0, whole.size() - 40))
	cut.close()
	var junk := FileAccess.open(tmp.path_join("seg_2_4.hpk"), FileAccess.WRITE)
	junk.store_buffer(_bytes(333, 5))
	junk.close()
	var r = Pack.new()
	var n: int = r.open(tmp, "key-a", 1)
	check(n == 3, "corrupt segments are skipped, good ones still served (%d)" % n)
	check(r.bad_segments == 2, "both corrupt segments were counted")
	check(not FileAccess.file_exists(tmp.path_join("seg_1_9.hpk"))
		and not FileAccess.file_exists(tmp.path_join("seg_2_4.hpk")), "corrupt segments are deleted")
	r.close()
	# another version or key: ignored and deleted, never served
	var v = Pack.new()
	check(v.open(tmp, "key-a", 2) == 0, "a newer pack version ignores the old segments")
	v.close()
	check(Pack.count_in(tmp) == 0, "outdated segments were removed")
	_rm(tmp)

	# ---- the mesh codec ----
	var surfaces := _mesh()
	var blob: PackedByteArray = Pack.encode_surfaces(surfaces)
	var am: ArrayMesh = Pack.decode_mesh(blob)
	check(am != null and am.get_surface_count() == 2, "mesh decodes with both surfaces")
	if am != null and am.get_surface_count() == 2:
		check(am.surface_get_name(0) == "1234|a" and am.surface_get_name(1) == "5678", "surface names survive")
		check(am.surface_get_array_len(0) == 4 and am.surface_get_array_index_len(0) == 6,
			"vertex and index counts survive")
	check(Pack.decode_mesh(_bytes(64, 7)) == null, "garbage does not decode to a mesh")
	check(Pack.decode_mesh(blob.slice(0, blob.size() / 2)) == null, "a truncated mesh does not decode")

	# ---- the game source path: save, flush, a new session loads it ----
	var GS = load("res://addons/highpoly_toggle/highpoly_gamesource.gd")
	var gdir := OS.get_temp_dir().replace("\\", "/").path_join("hp_geom_%d" % Time.get_ticks_usec())
	var gs = GS.new()
	gs._geom_use_dir(gdir)
	var built := ArrayMesh.new()
	for s in surfaces:
		built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s[1])
		built.surface_set_name(built.get_surface_count() - 1, s[0])
	gs._geom_save("mesh/x#0", ["1234|a", "5678"], built, surfaces)
	gs.flush_packs()
	check(int(gs.n_geom_saved) == 1, "one mesh saved")
	var gs2 = GS.new()
	gs2._geom_use_dir(gdir)
	var back = gs2._geom_load("mesh/x#0")
	check(back is ArrayMesh and gs2._keys_of(back) == ["1234|a", "5678"], "the next session loads it with its merge keys")
	check(int(gs2.n_geom_loaded) == 1, "the hit is counted")
	check(gs2._geom_load("mesh/other#0") == null, "a mesh never saved is a miss")
	gs2.flush_packs()
	check(GS.pack_counts_in(gdir) == 1, "the pack reports its size")
	_rm(gdir)
	quit(1 if fails else 0)
