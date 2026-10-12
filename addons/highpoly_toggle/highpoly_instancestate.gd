@tool
extends RefCounted
class_name HighpolyInstanceState
# Per-instance editor preview state - which variant a prop is showing, whether
# a door is swung open - kept BESIDE the node rather than on it. set_meta() on a
# node the scene owns is written into the user's .tscn on the next save, and
# this plugin promises to leave saved scenes alone. Lives for the session,
# keyed by instance id, like HighpolySdkHide's remembered visibility.

static var _vals: Dictionary = {}    # instance id -> {key: value}


static func get_value(node: Object, key: String, default: Variant = null) -> Variant:
	if node == null:
		return default
	var d: Variant = _vals.get(node.get_instance_id())
	if d == null:
		return default
	return (d as Dictionary).get(key, default)


static func set_value(node: Object, key: String, value: Variant) -> void:
	if node == null:
		return
	var id := node.get_instance_id()
	var d: Dictionary = _vals.get(id, {})
	d[key] = value
	_vals[id] = d


static func erase(node: Object, key: String) -> void:
	if node == null:
		return
	var id := node.get_instance_id()
	if not _vals.has(id):
		return
	var d: Dictionary = _vals[id]
	d.erase(key)
	if d.is_empty():
		_vals.erase(id)


static func clear() -> void:
	_vals.clear()
