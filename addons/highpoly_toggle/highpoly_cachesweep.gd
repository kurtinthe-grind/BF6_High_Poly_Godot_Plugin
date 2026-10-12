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
