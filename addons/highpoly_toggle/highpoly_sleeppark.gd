@tool
extends RefCounted
class_name HighpolySleepPark
# The editor's idle-sleep settings, put back after a bench run that never
# finished. The bench harness is gone from the fork, but a machine that ran it
# before may still carry a park file: a killed run left both sleeps at 0, and
# the editor then renders at full rate forever, even behind another window.
# Consumed once at boot, then never again.

const K_SLEEP_UNFOCUSED := "interface/editor/unfocused_low_processor_mode_sleep_usec"
const K_SLEEP_FOCUSED := "interface/editor/low_processor_mode_sleep_usec"
const SLEEP_PARK := "user://highpoly/editor_sleep_parked.json"


# Called from the plugin's boot. Returns "" when there was nothing to undo.
static func restore_pending() -> String:
	if not FileAccess.file_exists(SLEEP_PARK):
		return ""
	var f := FileAccess.open(SLEEP_PARK, FileAccess.READ)
	if f == null:
		return ""
	var v = JSON.parse_string(f.get_as_text())
	f.close()
	DirAccess.remove_absolute(SLEEP_PARK)
	if not (v is Dictionary):
		return ""
	var d: Dictionary = v
	var es := EditorInterface.get_editor_settings()
	if es == null:
		return ""
	var put := []
	if d.get("unfocused") != null and es.has_setting(K_SLEEP_UNFOCUSED):
		es.set_setting(K_SLEEP_UNFOCUSED, d["unfocused"])
		put.append("unfocused=%s" % str(d["unfocused"]))
	if d.get("focused") != null and es.has_setting(K_SLEEP_FOCUSED):
		es.set_setting(K_SLEEP_FOCUSED, d["focused"])
		put.append("focused=%s" % str(d["focused"]))
	if put.is_empty():
		return ""
	var msg := ("a bench run did not finish and left the editor's idle sleep "
		+ "at 0, which makes it render at full rate even when it is behind "
		+ "another window. Put back: %s" % ", ".join(put))
	HighpolyLog.warn(msg)
	HighpolyLog.event("editor.sleep_restored",
		{"unfocused": d.get("unfocused"), "focused": d.get("focused"),
		 "parked_at": d.get("at", 0)})
	return msg
