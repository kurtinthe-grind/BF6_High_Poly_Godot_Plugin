extends SceneTree
# OPT-02: textures had no disk cache. Every miss of the in-memory cache read
# the resource header, read and Oodle-decompressed the CAS chunk, maybe
# compressed, and uploaded - 12-13 s per Isolated objects build, every build.
# The decoded images now go into a per-map texture pack keyed on the TOC
# signature, the texture family recipe, the texture cap and the VRAM mode.

const Pack = preload("res://addons/highpoly_toggle/highpoly_pack.gd")

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("FORKTEST PASS " if cond else "FORKTEST FAIL ") + what)
	if not cond:
		fails += 1


func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _img(w: int, h: int, c: Color, mips: bool) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c)
	img.set_pixel(1, 2, Color.RED)
	if mips:
		img.generate_mipmaps()
	return img


func _init() -> void:
	# ---- the image codec ----
	var a := _img(16, 8, Color(0.2, 0.4, 0.6, 1.0), true)
	var back: Image = Pack.decode_image(Pack.encode_image(a))
	check(back != null, "an RGBA8 image with mipmaps decodes")
	if back != null:
		check(back.get_width() == 16 and back.get_height() == 8 and back.has_mipmaps()
			and back.get_format() == Image.FORMAT_RGBA8, "size, format and mips survive")
		check(back.get_data() == a.get_data(), "pixels survive exactly")
	var bc := _img(32, 32, Color(0.9, 0.1, 0.1, 1.0), false)
	bc.compress(Image.COMPRESS_S3TC)
	var bcb: Image = Pack.decode_image(Pack.encode_image(bc))
	check(bcb != null and bcb.is_compressed() and bcb.get_data() == bc.get_data(),
		"a block-compressed image survives")
	var junk := PackedByteArray()
	junk.resize(40)
	junk.fill(0xEE)
	check(Pack.decode_image(junk) == null, "garbage is not an image")
	var bad := Pack.encode_image(a)
	bad.encode_u32(0, 9999)            # an impossible format id
	check(Pack.decode_image(bad) == null, "an unknown format is refused")
	var short := Pack.encode_image(a)
	check(Pack.decode_image(short.slice(0, short.size() - 10)) == null, "a short image is refused")

	# ---- the key: cap and VRAM mode are part of it ----
	var GS = load("res://addons/highpoly_toggle/highpoly_gamesource.gd")
	var k1: String = GS.texpack_dir_name("mp_t", "sig1", "rec", 1024, 0)
	check(k1.begins_with("mp_t_"), "the pack folder is named after the map")
	check(k1 == GS.texpack_dir_name("mp_t", "sig1", "rec", 1024, 0), "the key is stable")
	check(k1 != GS.texpack_dir_name("mp_t", "sig1", "rec", 2048, 0), "another texture cap is another pack")
	check(k1 != GS.texpack_dir_name("mp_t", "sig1", "rec", 1024, 1), "another VRAM mode is another pack")
	check(k1 != GS.texpack_dir_name("mp_t", "sig2", "rec", 1024, 0), "a game patch is another pack")
	check(k1 != GS.texpack_dir_name("mp_t", "sig1", "rec2", 1024, 0), "a decoder change is another pack")

	# ---- the game source path: store, flush, a new session serves it ----
	var dir := OS.get_temp_dir().replace("\\", "/").path_join("hp_tex_%d" % Time.get_ticks_usec())
	var gs = GS.new()
	gs._texpack_use_dir(dir)
	gs._texpack_store("textures/a/b_d", a)
	gs._texpack_store("textures/a/c_n@1024", bc)
	gs.flush_packs()
	check(int(gs.n_texpack_saved) == 2, "two textures saved")
	var gs2 = GS.new()
	gs2._texpack_use_dir(dir)
	var hit = gs2._texpack_fetch("textures/a/b_d")
	check(hit is Image and (hit as Image).get_data() == a.get_data(), "the next session reads it back")
	check(gs2._texpack_fetch("textures/never") == null, "a texture never stored is a miss")
	check(int(gs2.n_texpack_hits) == 1, "only the hit is counted")
	gs2.flush_packs()
	check(GS.pack_counts_in(dir) == 2, "the pack reports its size")
	_rm(dir)
	quit(1 if fails else 0)
