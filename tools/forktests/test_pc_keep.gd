extends SceneTree
# OPT-13: the kept precache records are evicted oldest-first in O(1) - the old
# code built the whole key array on every eviction. Same order, same budget.

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("FORKTEST PASS " if cond else "FORKTEST FAIL ") + what)
	if not cond:
		fails += 1


func _init() -> void:
	var GS = load("res://addons/highpoly_toggle/highpoly_gamesource.gd")
	var gs = GS.new()
	var big := PackedByteArray()
	big.resize(int(GS.PRECACHE_KEEP_BUDGET * 0.35))
	gs._pc_keep("a", big)
	gs._pc_keep("b", big)
	check(gs._pc_kept.has("a") and gs._pc_kept.has("b"), "under the budget nothing is evicted")
	gs._pc_keep("c", big)
	check(not gs._pc_kept.has("a") and gs._pc_kept.has("b") and gs._pc_kept.has("c"),
		"over the budget the oldest goes first")
	gs._pc_keep("d", big)
	check(not gs._pc_kept.has("b") and gs._pc_kept.has("c") and gs._pc_kept.has("d"),
		"and then the next oldest")
	check(gs._pc_kept_bytes <= GS.PRECACHE_KEEP_BUDGET, "the byte count stays within budget")
	var huge := PackedByteArray()
	huge.resize(GS.PRECACHE_KEEP_BUDGET + 16)
	gs._pc_keep("e", huge)
	check(gs._pc_kept.has("e"), "what was just asked for is never evicted")
	gs._pc_kept.clear()
	gs._pc_kept_bytes = 0
	gs._pc_keep("f", big)
	check(gs._pc_kept.size() == 1 and gs._pc_fifo.size() == 1, "a cleared cache starts a fresh order")
	quit(1 if fails else 0)
