extends SceneTree
# Spawners keep the SDK's own marker: with no game source, and with the
# soldier/weapon/vehicle routes gone, no spawner key resolves to an asset.

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("FORKTEST PASS " if cond else "FORKTEST FAIL ") + what)
	if not cond:
		fails += 1


func _init() -> void:
	var lib = load("res://addons/highpoly_toggle/highpoly_lib.gd")
	check(lib != null, "highpoly_lib.gd loads")
	if lib == null:
		quit(1)
		return
	for key in ["SoldierSpawner_Assault", "LootSpawner", "VEH_Abrams"]:
		check(lib._asset_id(key) == "", "%s resolves to no overlay" % key)
	var src: String = (lib as GDScript).source_code
	check(not src.contains("soldier://") and not src.contains("vehicle://"),
		"no spawner asset routes remain in highpoly_lib.gd")
	quit(1 if fails else 0)
