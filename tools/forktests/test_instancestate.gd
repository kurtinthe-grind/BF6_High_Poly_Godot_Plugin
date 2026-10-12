extends SceneTree
# Per-instance preview state lives beside the node, never on it.

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("FORKTEST PASS " if cond else "FORKTEST FAIL ") + what)
	if not cond:
		fails += 1


func _init() -> void:
	var st = load("res://addons/highpoly_toggle/highpoly_instancestate.gd")
	check(st != null, "highpoly_instancestate.gd loads")
	if st == null:
		quit(1)
		return
	var a := Node3D.new()
	var b := Node3D.new()
	check(st.get_value(a, "hp_variant", "") == "", "default when unset")
	st.set_value(a, "hp_variant", "police")
	check(st.get_value(a, "hp_variant", "") == "police", "value stored")
	check(st.get_value(b, "hp_variant", "") == "", "per instance, not shared")
	check(a.get_meta_list().is_empty(), "nothing written onto the node")
	st.erase(a, "hp_variant")
	check(st.get_value(a, "hp_variant", "") == "", "erased")
	st.set_value(a, "hp_door_open", true)
	st.clear()
	check(st.get_value(a, "hp_door_open", false) == false, "clear() forgets everything")
	a.free()
	b.free()
	quit(1 if fails else 0)
