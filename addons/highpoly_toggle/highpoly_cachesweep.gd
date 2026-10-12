@tool
extends RefCounted
class_name HighpolyCacheSweep
# Superseded caches in user://. The readers name each index after what it was
# built from (bf6_index_<level>_v<version>_<signature>.idx and the pidx/walk
# siblings) and never delete the one they stop using, so every install change
# or reader bump leaves the old file behind - ten all-levels indexes, 1.65 GB,
# on one machine. The signature varies per level, so "current" cannot be
# recognised from outside; the newest file of each family is the one the
# reader wrote last, and keeping only that is safe: anything else rebuilds on
# demand. Only ever run from the button, never on its own.

const _IDX := "^(bf6_(?:index|pidx|walk)_.+)_v\\d+_[0-9a-f]{16}\\.idx$"
const _TMP := "^highpoly-session\\.log\\d+\\.tmp$"
const TMP_MAX_AGE := 86400     # a temp log this old belongs to a session that is gone


static func outdated(files: Array, now_unix: int) -> PackedStringArray:
	var idx := RegEx.create_from_string(_IDX)
	var tmp := RegEx.create_from_string(_TMP)
	var newest := {}            # family -> {name, mtime}
	var out := PackedStringArray()
	for f in files:
		var name := str(f["name"])
		var m := idx.search(name)
		if m != null:
			var fam := m.get_string(1)
			var cur: Variant = newest.get(fam)
			if cur == null:
				newest[fam] = f
			elif int(f["mtime"]) > int(cur["mtime"]):
				out.append(str(cur["name"]))
				newest[fam] = f
			else:
				out.append(name)
		elif tmp.search(name) != null and now_unix - int(f["mtime"]) > TMP_MAX_AGE:
			out.append(name)
	return out


static func scan(dir := "user://") -> Array:
	var out: Array = []
	for name in DirAccess.get_files_at(dir):
		var p := dir.path_join(name)
		var fa := FileAccess.open(p, FileAccess.READ)
		var size := fa.get_length() if fa != null else 0
		if fa != null:
			fa.close()
		out.append({"name": name, "mtime": FileAccess.get_modified_time(p), "size": size})
	return out


static func remove(names: PackedStringArray, dir := "user://") -> int:
	var sizes := {}
	for f in scan(dir):
		sizes[f["name"]] = int(f["size"])
	var freed := 0
	for name in names:
		if DirAccess.remove_absolute(dir.path_join(name)) == OK:
			freed += int(sizes.get(name, 0))
	return freed


# ---------------------------------------------------------------------------
# THE PACK FOLDERS. user://bf6_geom/<level>_<sig>_g<epoch>[_l<n>][_v<mode>] and
# user://bf6_tex/<level>_<key16> are one folder per map and key; a game patch,
# an epoch bump or a new texture key leaves the previous folder behind. The
# newest folder of each map (and, for geometry, of each LOD/VRAM variant) is the
# one the reader uses; the rest rebuild on demand if ever wanted again.
const GEOM_DIR := "user://bf6_geom"
const TEX_DIR := "user://bf6_tex"
const _GEOM := "^(.+)_[0-9a-f]{16}_g\\d+((?:_l\\d+)?(?:_v[a-z]+)?)$"
const _TEX := "^(.+)_[0-9a-f]{16}$"
const JOBS_DIR := "user://highpoly/preparation_jobs"


static func outdated_dirs(dirs: Array, root: String) -> PackedStringArray:
	var re := RegEx.create_from_string(_GEOM if root == GEOM_DIR else _TEX)
	var newest := {}
	var out := PackedStringArray()
	for d in dirs:
		var name := str(d["name"])
		var m := re.search(name)
		if m == null:
			continue
		var fam := m.get_string(1) + ("|" + m.get_string(2) if root == GEOM_DIR else "")
		var cur: Variant = newest.get(fam)
		if cur == null:
			newest[fam] = d
		elif int(d["mtime"]) > int(cur["mtime"]):
			out.append(str(cur["name"]))
			newest[fam] = d
		else:
			out.append(name)
	return out


# Folders under `root` with the newest modification time of anything in them
# and their total size.
static func scan_dirs(root: String) -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(root):
		return out
	for name in DirAccess.get_directories_at(root):
		var p := root.path_join(name)
		var t := int(FileAccess.get_modified_time(p))
		var size := 0
		for f in DirAccess.get_files_at(p):
			var fp := p.path_join(f)
			t = maxi(t, int(FileAccess.get_modified_time(fp)))
			var fa := FileAccess.open(fp, FileAccess.READ)
			if fa != null:
				size += int(fa.get_length())
				fa.close()
		out.append({"name": name, "mtime": t, "size": size})
	return out


static func remove_dirs(names: PackedStringArray, root: String) -> int:
	var freed := 0
	for name in names:
		var p := root.path_join(name)
		for f in DirAccess.get_files_at(p):
			var fp := p.path_join(f)
			var fa := FileAccess.open(fp, FileAccess.READ)
			var size := int(fa.get_length()) if fa != null else 0
			if fa != null:
				fa.close()
			if DirAccess.remove_absolute(fp) == OK:
				freed += size
		DirAccess.remove_absolute(p)
	return freed


# Index-worker job files that outlived their job (a killed editor). The service
# deletes them after reading a finished job, so anything a day old is orphaned.
static func stale_jobs(files: Array, now_unix: int) -> PackedStringArray:
	var out := PackedStringArray()
	for f in files:
		if now_unix - int(f["mtime"]) > TMP_MAX_AGE:
			out.append(str(f["name"]))
	return out
