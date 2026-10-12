@tool
extends RefCounted
# ONE PACK PER MAP: the on-disk store behind the geometry pack (OPT-01) and the
# texture pack (OPT-02).
#
# WHY NOT ONE FILE PER ITEM. The old geometry cache wrote one .res per mesh and
# loaded each with ResourceLoader on the main thread; thousands of small files
# per map cost enough that a warm build measured 17-33 s against 13 s for the
# native cold path, and the cache was switched off under the precache - and
# then deleted at every launch. A pack is a handful of segment files read by
# offset: one open per segment, one seek and one read per item.
#
# LAYOUT. A pack is a folder of segment files, seg_<usec>_<count>.hpk:
#   header   u32 MAGIC, u32 FORMAT, u32 version, u32 key length, key (utf8)
#   records  u32 REC, u32 name length, name (utf8), u64 data length, data
# A build appends to ONE new segment (put); flush() closes it and renames it
# from *.part into place, so a crash - or a pack dropped without flush() -
# leaves only a .part (discarded by the next open), never a short segment that
# reads as valid. Appends are synchronous and buffered: a few hundred KB per
# item, timed by the callers (t_geom_save, the pack line in the session log).
# A writer THREAD was tried and dropped: a pack released mid-build left it
# calling into a freed object. The record count is in the file
# name so the panel can report a pack's size without opening it.
#
# SAFETY. Every length is bounds-checked against the file. A segment with a bad
# header, another FORMAT/version/key, or a record running past its end is
# deleted whole and counted in bad_segments - its items are simply rebuilt.
# Nothing here can crash on bad bytes: a damaged pack is a cold build.

const MAGIC := 0x4B504848       # "HHPK"
const REC := 0x31434552         # "REC1"
const FORMAT := 1
const EXT := ".hpk"
const MAX_NAME := 4096

var dir := ""
var key := ""
var version := 0
var bad_segments := 0
var bytes_read := 0
var _index := {}                # name -> [segment path, data offset, length]
var _files := {}                # segment path -> FileAccess (read handles)
var _mutex := Mutex.new()

# the writer
var _queued := {}               # names accepted this session
var _part := ""
var _out: FileAccess
var _out_count := 0
var _out_entries: Array = []    # [name, offset, length] written to the open segment
var _write_error := false


# Opens (or creates) the pack folder and indexes every valid segment. Returns
# the number of records it can serve.
func open(p_dir: String, p_key: String, p_version: int) -> int:
	close()
	dir = p_dir
	key = p_key
	version = p_version
	bad_segments = 0
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		dir = ""
		return 0
	var now := int(Time.get_unix_time_from_system())
	for f in DirAccess.get_files_at(dir):
		var name := str(f)
		var path := dir.path_join(name)
		if name.ends_with(".part"):
			# a writer that died; an hour is far longer than any live flush
			if now - int(FileAccess.get_modified_time(path)) > 3600:
				DirAccess.remove_absolute(path)
		elif name.ends_with(EXT):
			if not _scan(path):
				bad_segments += 1
				DirAccess.remove_absolute(path)
	return _index.size()


func _scan(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var size := int(f.get_length())
	if size < 16 or f.get_32() != MAGIC or f.get_32() != FORMAT or int(f.get_32()) != version:
		f.close()
		return false
	var klen := int(f.get_32())
	if klen < 0 or klen > MAX_NAME or 16 + klen > size \
			or f.get_buffer(klen).get_string_from_utf8() != key:
		f.close()
		return false
	var found: Array = []
	while f.get_position() < size:
		var at := int(f.get_position())
		if at + 8 > size or f.get_32() != REC:
			f.close()
			return false
		var nlen := int(f.get_32())
		if nlen <= 0 or nlen > MAX_NAME or at + 8 + nlen + 8 > size:
			f.close()
			return false
		var nm := f.get_buffer(nlen).get_string_from_utf8()
		var dlen := int(f.get_64())
		var data_at := int(f.get_position())
		if dlen < 0 or data_at + dlen > size:
			f.close()
			return false
		found.append([nm, data_at, dlen])
		f.seek(data_at + dlen)
	f.close()
	_mutex.lock()
	for e in found:
		if not _index.has(e[0]):
			_index[e[0]] = [path, e[1], e[2]]
	_mutex.unlock()
	return true


func has(name: String) -> bool:
	_mutex.lock()
	var h := _index.has(name)
	_mutex.unlock()
	return h


func count() -> int:
	_mutex.lock()
	var n := _index.size()
	_mutex.unlock()
	return n


# The item's bytes, or empty on a miss or a read that comes up short.
func get_bytes(name: String) -> PackedByteArray:
	_mutex.lock()
	var e: Variant = _index.get(name)
	if e == null:
		_mutex.unlock()
		return PackedByteArray()
	var path := str(e[0])
	var f: FileAccess = _files.get(path)
	if f == null:
		f = FileAccess.open(path, FileAccess.READ)
		if f == null:
			_index.erase(name)
			_mutex.unlock()
			return PackedByteArray()
		_files[path] = f
	f.seek(int(e[1]))
	var out := f.get_buffer(int(e[2]))
	if out.size() != int(e[2]):
		_index.erase(name)
		out = PackedByteArray()
	bytes_read += out.size()
	_mutex.unlock()
	return out


# Append an item to the current segment. False when the pack is closed, the
# write failed, or the name is already in it - first write wins. Readable after
# flush().
func put(name: String, bytes: PackedByteArray) -> bool:
	if dir.is_empty() or name.is_empty() or name.length() > MAX_NAME:
		return false
	_mutex.lock()
	if _index.has(name) or _queued.has(name) or _write_error:
		_mutex.unlock()
		return false
	_queued[name] = true
	_write_one(name, bytes)
	var ok := not _write_error
	_mutex.unlock()
	return ok


func _write_one(name: String, data: PackedByteArray) -> void:
	if _write_error:
		return
	if _out == null:
		_part = dir.path_join("seg_%d%s.%d.part" % [
			Time.get_ticks_usec(), EXT, OS.get_process_id()])
		_out = FileAccess.open(_part, FileAccess.WRITE)
		if _out == null:
			_write_error = true
			return
		var kb := key.to_utf8_buffer()
		_out.store_32(MAGIC)
		_out.store_32(FORMAT)
		_out.store_32(version)
		_out.store_32(kb.size())
		_out.store_buffer(kb)
		_out_count = 0
		_out_entries.clear()
	var nb := name.to_utf8_buffer()
	_out.store_32(REC)
	_out.store_32(nb.size())
	_out.store_buffer(nb)
	_out.store_64(data.size())
	var at := int(_out.get_position())
	_out.store_buffer(data)
	if _out.get_error() != OK:
		_write_error = true
		return
	_out_count += 1
	_out_entries.append([name, at, data.size()])


# Finish the current segment: wait for the writer, close the file and move it
# into place. Items become readable here. Safe to call when nothing was put.
func flush() -> void:
	_mutex.lock()
	_flush_locked()
	_mutex.unlock()


func _flush_locked() -> void:
	if _out == null:
		return
	_out.flush()
	var ok := _out.get_error() == OK and not _write_error
	_out.close()
	_out = null
	if not ok or _out_count == 0:
		DirAccess.remove_absolute(_part)
		_part = ""
		return
	var final := dir.path_join("seg_%d_%d%s" % [Time.get_ticks_usec(), _out_count, EXT])
	if DirAccess.rename_absolute(_part, final) != OK:
		DirAccess.remove_absolute(_part)
		_part = ""
		return
	_part = ""
	for e in _out_entries:
		if not _index.has(e[0]):
			_index[e[0]] = [final, e[1], e[2]]
	_out_entries.clear()


func close() -> void:
	flush()
	_mutex.lock()
	for f in _files.values():
		(f as FileAccess).close()
	_files.clear()
	_index.clear()
	_queued.clear()
	_write_error = false
	_mutex.unlock()


# Records in a pack folder, from the segment names alone.
static func count_in(path: String) -> int:
	if not DirAccess.dir_exists_absolute(path):
		return 0
	var n := 0
	for f in DirAccess.get_files_at(path):
		var name := str(f)
		if name.begins_with("seg_") and name.ends_with(EXT):
			n += maxi(0, int(name.trim_suffix(EXT).get_slice("_", 2)))
	return n


# ---------------------------------------------------------------------------
# MESH CODEC. A mesh is its surfaces as [name, arrays] pairs, captured while the
# reader builds them - never read back from the RenderingServer, which on the
# GPU backends is a synchronous buffer download. The arrays go through
# var_to_bytes (packed arrays are stored raw) and come back through
# bytes_to_var, which never instantiates objects.
#   u32 surface count, then per surface:
#   u32 name length, name, u32 primitive, u64 length, var_to_bytes(arrays)
static func encode_surfaces(surfaces: Array) -> PackedByteArray:
	var sp := StreamPeerBuffer.new()
	sp.put_u32(surfaces.size())
	for s in surfaces:
		var nb := str(s[0]).to_utf8_buffer()
		var vb := var_to_bytes(s[1])
		sp.put_u32(nb.size())
		sp.put_data(nb)
		sp.put_u32(Mesh.PRIMITIVE_TRIANGLES)
		sp.put_u64(vb.size())
		sp.put_data(vb)
	return sp.data_array


static func decode_mesh(bytes: PackedByteArray) -> ArrayMesh:
	var size := bytes.size()
	if size < 4:
		return null
	var count := int(bytes.decode_u32(0))
	if count <= 0 or count > 4096:
		return null
	var at := 4
	var am := ArrayMesh.new()
	for i in range(count):
		if at + 4 > size:
			return null
		var nlen := int(bytes.decode_u32(at))
		at += 4
		if nlen < 0 or nlen > MAX_NAME or at + nlen + 12 > size:
			return null
		var sname := bytes.slice(at, at + nlen).get_string_from_utf8()
		at += nlen
		var prim := int(bytes.decode_u32(at))
		var vlen := int(bytes.decode_u64(at + 4))
		at += 12
		if prim < 0 or prim > Mesh.PRIMITIVE_TRIANGLE_STRIP or vlen <= 0 or at + vlen > size:
			return null
		var arrays: Variant = bytes_to_var(bytes.slice(at, at + vlen))
		at += vlen
		if not (arrays is Array) or (arrays as Array).size() != Mesh.ARRAY_MAX \
				or not ((arrays as Array)[Mesh.ARRAY_VERTEX] is PackedVector3Array) \
				or ((arrays as Array)[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			return null
		am.add_surface_from_arrays(prim, arrays)
		am.surface_set_name(am.get_surface_count() - 1, sname)
	return am if at == size else null


# ---------------------------------------------------------------------------
# IMAGE CODEC, for the texture pack: the decoded, capped, compressed image the
# build would have uploaded, so a hit is one read + create_from_data.
#   u32 format, u32 width, u32 height, u32 mipmaps, u64 length, data
const MAX_DIM := 16384

static func encode_image(img: Image) -> PackedByteArray:
	var data := img.get_data()
	var sp := StreamPeerBuffer.new()
	sp.put_u32(int(img.get_format()))
	sp.put_u32(img.get_width())
	sp.put_u32(img.get_height())
	sp.put_u32(1 if img.has_mipmaps() else 0)
	sp.put_u64(data.size())
	sp.put_data(data)
	return sp.data_array


static func decode_image(bytes: PackedByteArray) -> Image:
	if bytes.size() < 24:
		return null
	var fmt := int(bytes.decode_u32(0))
	var w := int(bytes.decode_u32(4))
	var h := int(bytes.decode_u32(8))
	var mips := int(bytes.decode_u32(12))
	var n := int(bytes.decode_u64(16))
	if fmt < 0 or fmt >= Image.FORMAT_MAX or w <= 0 or h <= 0 or w > MAX_DIM or h > MAX_DIM \
			or mips > 1 or n <= 0 or 24 + n != bytes.size():
		return null
	var img := Image.create_from_data(w, h, mips == 1, fmt, bytes.slice(24))
	if img == null or img.is_empty():
		return null
	return img
