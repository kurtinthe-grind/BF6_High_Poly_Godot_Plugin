extends SceneTree
# An overlay dressed once is not walked again for the same dress, and a changed
# dress (textured flag, shadow switch) is applied in full.

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("FORKTEST PASS " if cond else "FORKTEST FAIL ") + what)
	if not cond:
		fails += 1


func _overlay() -> Node3D:
	var hp := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	hp.add_child(mi)
	return hp


func _init() -> void:
	var lib = load("res://addons/highpoly_toggle/highpoly_lib.gd")
	var lighting = load("res://addons/highpoly_toggle/highpoly_lighting.gd")
	lighting.cast_shadows = false
	var hp := _overlay()
	var mi := hp.get_child(0) as MeshInstance3D

	lib._set_textured(hp, true)
	check(mi.layers == lib.TEXTURED_LAYER, "first dress applies the overlay layer")
	check(str(hp.get_meta("hp_dress", "")) == lib.dress_key(true), "dress key recorded")

	var sentinel := StandardMaterial3D.new()
	mi.material_override = sentinel
	lib._set_textured(hp, true)
	check(mi.material_override == sentinel, "same dress again is skipped")

	lib._set_textured(hp, false)
	check(mi.material_override == lib.gray_material(), "untextured dress is applied")

	# A shadow-rule change re-dresses. shadow_min_size is part of the key just
	# like cast_shadows; it is the one changed here because cast_shadows = true
	# makes _set_textured call _merged_aabb -> EditorInterface, which a headless
	# run does not have.
	var was: float = lighting.shadow_min_size
	lighting.shadow_min_size = was + 0.5
	mi.material_override = sentinel
	lib._set_textured(hp, false)
	check(mi.material_override != sentinel, "shadow rule change changes the key and re-dresses")
	lighting.shadow_min_size = was
	hp.free()
	quit(1 if fails else 0)
