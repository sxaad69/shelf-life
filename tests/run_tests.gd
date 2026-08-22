extends SceneTree

## Headless test harness: godot --headless --script tests/run_tests.gd
## Determinism, solver soundness, audit agreement, difficulty stages.

var failures := 0
var checks := 0


func check(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL: ", label)


func _init() -> void:
	var S := load("res://scripts/shelf_state.gd")
	_test_determinism(S)
	_test_solver_finds_solutions(S)
	_test_audit_agreement(S)
	_test_stages(S)
	_test_moves_and_flip(S)
	_test_hint(S)
	_test_skip(S)
	print("---")
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _mk(S, level: int, seedv: int):
	var st = S.new()
	st.setup_stage(level, seedv)
	return st


func _test_determinism(S) -> void:
	for level in range(1, 6):
		for seedv in [7, 42, 1337]:
			var a = _mk(S, level, seedv)
			var b = _mk(S, level, seedv)
			var ta := []
			for it in a.tray:
				ta.append("%s%d%d%s" % [it["cat"], it["w"], it["exp"], "T" if it["face_out"] else "F"])
			var tb := []
			for it in b.tray:
				tb.append("%s%d%d%s" % [it["cat"], it["w"], it["exp"], "T" if it["face_out"] else "F"])
			check(str(ta) == str(tb), "determinism L%d s%d (%s vs %s)" % [level, seedv, str(ta), str(tb)])


func _test_solver_finds_solutions(S) -> void:
	for level in range(1, 6):
		for seedv in range(3, 13):
			var st = _mk(S, level, seedv)
			var sols = st.solve_all(st.tray, st.active_rules)
			check(not sols.is_empty(),
					"solver >=1 solution L%d s%d (seed advanced to %d)" % [level, seedv, st.seed_value])


func _solve_bruteforce(st, items: Array, rules: Array) -> Array:
	# Independent reference implementation (no pruning shortcuts shared
	# with ShelfState beyond the same rule semantics).
	var found: Array = []
	var n := items.size()
	var perm := []
	for i in range(n):
		perm.append(i)
	while true:
		var ok := true
		# WEIGHT per bay
		if "WEIGHT" in rules:
			for bay in range(n / 2):
				if items[perm[bay * 2]]["w"] < items[perm[bay * 2 + 1]]["w"]:
					ok = false
					break
		# FIFO along scan
		if ok and "FIFO" in rules:
			for k in range(1, n):
				if items[perm[k]]["exp"] < items[perm[k - 1]]["exp"]:
					ok = false
					break
		# ADJACENCY contiguous
		if ok and "ADJACENCY" in rules:
			var pos := {}
			for k in range(n):
				var c = items[perm[k]]["cat"]
				if not pos.has(c):
					pos[c] = [k, k]
				else:
					pos[c][1] = k
			for c in pos:
				if pos[c][1] - pos[c][0] != pos[c].size() - 1:
					ok = false
					break
		if ok:
			found.append(perm.duplicate())
			if found.size() >= 1:
				break
		# next permutation (lexicographic)
		var i := n - 2
		while i >= 0 and perm[i] >= perm[i + 1]:
			i -= 1
		if i < 0:
			break
		var j := n - 1
		while perm[j] <= perm[i]:
			j -= 1
		var tmpv = perm[i]
		perm[i] = perm[j]
		perm[j] = tmpv
		var lo := i + 1
		var hi := n - 1
		while lo < hi:
			var t2 = perm[lo]
			perm[lo] = perm[hi]
			perm[hi] = t2
			lo += 1
			hi -= 1
	return found


func _test_audit_agreement(S) -> void:
	for level in range(1, 6):
		for seedv in range(3, 8):
			var st = _mk(S, level, seedv)
			# Fresh state must NOT be solved (tray non-empty).
			check(not st.is_solved(), "fresh not solved L%d s%d" % [level, seedv])
			# Place everything according to the reference brute-force solution.
			var items: Array = st.tray.duplicate(true)
			var sols := _solve_bruteforce(st, items, st.active_rules)
			check(sols.size() > 0, "reference solver solution L%d s%d" % [level, seedv])
			if sols.is_empty():
				continue
			var perm: Array = sols[0]
			# Rebuild tray order so placing sequentially matches perm.
			var ordered := []
			for idx in perm:
				ordered.append(items[idx])
			st.tray = ordered
			for bay in range(st.bays):
				st.place_from_tray(0, bay, 0)
				st.place_from_tray(0, bay, 1)
			check(st.tray.is_empty(), "tray emptied L%d s%d" % [level, seedv])
			check(st.is_solved(), "constructed solve audits true L%d s%d res=%s" % [level, seedv, str(st.audit())])
			# Break one rule and confirm the audit catches it.
			if "WEIGHT" in st.active_rules and st.bays >= 1:
				var f = st.shelf[0][0]
				var b = st.shelf[0][1]
				st.shelf[0][0] = b
				st.shelf[0][1] = f
				if f["w"] != b["w"]:
					check(not st.audit().get("WEIGHT", false), "swap breaks WEIGHT L%d s%d" % [level, seedv])


func _test_stages(S) -> void:
	var st = _mk(S, 1, 5)
	check(st.active_rules == ["FACING", "WEIGHT"], "L1 two rules")
	check(st.bays == 2, "L1 two bays")
	check(st.tray.size() == 4, "L1 four items")
	st = _mk(S, 3, 5)
	check("ADJACENCY" in st.active_rules, "L3 three rules")
	check(st.bays == 3 and st.tray.size() == 6, "L3 six items")
	st = _mk(S, 5, 5)
	check(st.active_rules.size() == 4, "L5 all rules")
	check(st.bays == 4 and st.tray.size() == 8, "L5 eight items")


func _test_moves_and_flip(S) -> void:
	var st = _mk(S, 1, 11)
	st.place_from_tray(0, 0, 0)
	check(st.shelf[0][0] != null, "place lands item")
	check(st.tray.size() == 3, "tray shrinks")
	var before = st.shelf[0][0]["face_out"]
	st.flip_item(0, 0)
	check(st.shelf[0][0]["face_out"] != before, "flip toggles")
	st.swap_shelf(0, 0, 0, 1)
	check(st.shelf[0][1] != null, "swap moves item")


func _test_hint(S) -> void:
	var st = _mk(S, 1, 9)
	var h = st.use_hint()
	# Empty shelf: hint should still return something pointing at tray.
	check(not h.is_empty(), "hint returns target on empty shelf")
	check(st.hints_left == 2, "hint decrements")
	# Exhaust hints.
	while st.hints_left > 0:
		st.use_hint()
	check(st.use_hint().is_empty(), "hint refused at zero")


func _test_skip(S) -> void:
	var st = _mk(S, 1, 21)
	var ok: bool = st.can_skip_delivery(0)
	check(ok, "skip legal while solvable L1 s21")
	if ok:
		check(st.skip_delivery(0), "skip executes")
		check(st.tray.size() == 3, "skip removes one")
