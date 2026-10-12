extends SceneTree
# The save guard's two halves on plain nodes: stocking records only overlays
# that were showing and puts the SDK proxy back; reshowing puts exactly those
# back, and leaves an overlay that was hidden before the save hidden.

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("FORKTEST PASS " if cond else "FORKTEST FAIL ") + what)
	if not cond:
		fails += 1


func _proxy(lib, name: String, overlay_visible: bool) -> Node3D:
	var p := Node3D.new()
	p.name = name
	var proxy_mesh := MeshInstance3D.new()
	proxy_mesh.name = "Mesh"
	p.add_child(proxy_mesh)
	var hp := Node3D.new()
	hp.name = lib.HP_NODE
	hp.add_child(MeshInstance3D.new())
	p.add_child(hp)
	hp.visible = overlay_visible
	if overlay_visible:
		lib._set_proxy_visible(p, false, p)    # as an active overlay leaves it
	return p


func _init() -> void:
	var lib = load("res://addons/highpoly_toggle/highpoly_lib.gd")
	var root := Node3D.new()
	var shown := _proxy(lib, "Shown", true)
	var hidden := _proxy(lib, "Hidden", false)
	root.add_child(shown)
	root.add_child(hidden)
	var shown_mesh := shown.get_node("Mesh") as MeshInstance3D
	check(shown_mesh.material_override == lib.invisible_material(), "setup: proxy draws nothing")

	var rec: Array = lib.restore_visible(root)
	check(rec.size() == 1 and rec[0] == shown, "only the visible overlay is recorded")
	check(not (shown.get_node(lib.HP_NODE) as Node3D).visible, "overlay hidden for the save")
	check(shown_mesh.material_override == null, "proxy material back for the save")
	check(not shown_mesh.has_meta("hp_prev_override"), "no plugin meta left on the proxy")

	var n: int = lib.reshow(rec, root)
	check(n == 1, "one overlay reshown")
	check((shown.get_node(lib.HP_NODE) as Node3D).visible, "overlay visible again")
	check(shown_mesh.material_override == lib.invisible_material(), "proxy draws nothing again")
	check(not (hidden.get_node(lib.HP_NODE) as Node3D).visible, "hidden overlay stays hidden")

	shown.free()
	check(lib.reshow(rec, root) == 0, "a freed node in the record is skipped")
	root.free()
	quit(1 if fails else 0)
