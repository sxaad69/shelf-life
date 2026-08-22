class_name ShelfState
extends RefCounted

## SHELF LIFE — core simulation (pure logic, zero node deps).
## Feeler semantics carried verbatim (see DECISIONS.md D4/D5):
##   Scan order: per bay FRONT then BACK, bays left -> right.
##   WEIGHT:     front weight >= back weight per bay.
##   ADJACENCY:  each category's scan positions are contiguous.
##   FIFO:       expiry non-decreasing along the scan.
##   FACING:     every placed item faces out.
## Generator = answer key by construction; independent brute-force
## solver must confirm >=1 valid arrangement per seed or seed rejected.

const CATEGORIES := {
	"P": {"name": "Produce", "col": Color("6fce62")},
	"D": {"name": "Dairy", "col": Color("f2b134")},
	"M": {"name": "Meat", "col": Color("e05263")},
	"B": {"name": "Bakery", "col": Color("b78bf0")},
}
const RULES := ["FACING", "WEIGHT", "ADJACENCY", "FIFO"]

## Difficulty stages (pulse caveat D6): rule count x tray size dials.
## stage -> {rules active, bays}
const STAGES := [
	{"level": 1, "rules": ["FACING", "WEIGHT"], "bays": 2},
	{"level": 2, "rules": ["FACING", "WEIGHT"], "bays": 3},
	{"level": 3, "rules": ["FACING", "WEIGHT", "ADJACENCY"], "bays": 3},
	{"level": 4, "rules": ["FACING", "WEIGHT", "ADJACENCY"], "bays": 4},
	{"level": 5, "rules": ["FACING", "WEIGHT", "ADJACENCY", "FIFO"], "bays": 4},
]
const MAX_STAGE := 5
const MAX_HINTS := 3

var seed_value: int = 0
var stage_index: int = 0
var active_rules: Array = []
var bays: int = 2
var rows_per_bay: int = 2

## shelf[bay][row] — row 0 = FRONT. Item = Dictionary or null.
var shelf: Array = []
## Delivery tray (unplaced items).
var tray: Array = []
var hints_left: int = MAX_HINTS
var last_hint_item: Dictionary = {}   # {} when no hint active
const MAX_SKIPS := 1
var skips_used: int = 0
var rng := RandomNumberGenerator.new()


static func make_item(cat: String, weight: int, expiry: int) -> Dictionary:
	return {"cat": cat, "w": weight, "exp": expiry, "face_out": true, "id": "%s%d%d" % [cat, weight, expiry]}


func setup_stage(level_num: int, forced_seed: int = -1) -> void:
	stage_index = clampi(level_num - 1, 0, MAX_STAGE - 1)
	var st: Dictionary = STAGES[stage_index]
	active_rules = st["rules"].duplicate()
	bays = st["bays"]
	seed_value = forced_seed if forced_seed >= 0 else int(Time.get_unix_time_from_system()) % 1000000
	hints_left = MAX_HINTS
	last_hint_item = {}
	_generate_level()


func reroll() -> void:
	setup_stage(stage_index + 1, seed_value + 1)


func next_level() -> void:
	setup_stage(mini(stage_index + 2, MAX_STAGE))


# ------------------------------------------------------------------
# GENERATOR = ANSWER KEY (D5)
# Build a valid arrangement by construction for ACTIVE rules only,
# then scramble into the tray.
# ------------------------------------------------------------------
func _generate_level() -> void:
	for _attempt in range(64):
		rng.seed = seed_value + _attempt * 7919
		var items := _construct_valid()
		if items.is_empty():
			continue
		var scrambled := items.duplicate(true)
		# Fisher-Yates with the SAME seeded stream continuation.
		for i in range(scrambled.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = scrambled[i]
			scrambled[i] = scrambled[j]
			scrambled[j] = tmp
		tray = scrambled
		shelf = []
		for _b in range(bays):
			var col: Array = [null, null]
			shelf.append(col)
		# Answer-key proof: independent solver must find >=1 arrangement.
		var sols := solve_all(tray, active_rules)
		if not sols.is_empty():
			return
		seed_value += 1  # degenerate under active rules — advance, retry


func _construct_valid() -> Array:
	# One category pair per bay; categories shuffled.
	var cats: Array = CATEGORIES.keys()
	_shuffle(cats)
	var items: Array = []
	var e := rng.randi_range(1, 4)
	var fifo_active: bool = "FIFO" in active_rules
	var adjacency_active: bool = "ADJACENCY" in active_rules
	for pair in range(bays):
		# With ADJACENCY off we still use one category per pair (harmless);
		# without FIFO, expiries may be non-monotonic.
		var cat: String = cats[pair] if adjacency_active else cats[pair]
		var w_front := rng.randi_range(1, 3)
		if fifo_active and e > 98:
			e = 98
		items.append(make_item(cat, w_front, e))
		if fifo_active:
			e += rng.randi_range(1, 3)
		else:
			e = rng.randi_range(1, 9)
		items.append(make_item(cat, rng.randi_range(1, w_front), e))
		if fifo_active:
			e += rng.randi_range(1, 3)
	return items


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ------------------------------------------------------------------
# AUDIT — checks ONLY the active rules.
# Returns {rule_id: bool} plus "full": all slots filled & tray empty.
# ------------------------------------------------------------------
func audit() -> Dictionary:
	var res := {}
	var expected: int = bays * 2 - skips_used
	var full: bool = tray.is_empty() and _placed_all().size() == expected
	res["full"] = full
	for r in active_rules:
		match r:
			"FACING":
				res[r] = full and _placed_all().all(func(it): return it["face_out"])
			"WEIGHT":
				res[r] = full and _weight_ok()
			"ADJACENCY":
				res[r] = full and _adjacency_ok()
			"FIFO":
				res[r] = full and _fifo_ok()
	return res


func is_solved() -> bool:
	var res := audit()
	if not res.get("full", false):
		return false
	for r in active_rules:
		if not res.get(r, false):
			return false
	return true


func scan_order() -> Array:
	var out: Array = []
	for bay in range(bays):
		out.append(shelf[bay][0])
		out.append(shelf[bay][1])
	return out


func _placed_all() -> Array:
	var out: Array = []
	for cell in scan_order():
		if cell != null:
			out.append(cell)
	return out


func _all_slots_full() -> bool:
	for bay in range(bays):
		if shelf[bay][0] == null or shelf[bay][1] == null:
			return false
	return true


func _weight_ok() -> bool:
	for bay in range(bays):
		var f = shelf[bay][0]
		var b = shelf[bay][1]
		if f == null or b == null or f["w"] < b["w"]:
			return false
	return true


func _adjacency_ok() -> bool:
	var pos := {}
	var scan := scan_order()
	for k in range(scan.size()):
		var it = scan[k]
		if it == null:
			continue
		if not pos.has(it["cat"]):
			pos[it["cat"]] = []
		pos[it["cat"]].append(k)
	for cat in pos:
		var ps: Array = pos[cat]
		if ps[ps.size() - 1] - ps[0] != ps.size() - 1:
			return false
	return true


func _fifo_ok() -> bool:
	var prev: int = -1
	for it in scan_order():
		if it == null:
			continue
		if prev >= 0 and it["exp"] < prev:
			return false
		prev = it["exp"]
	return true


# ------------------------------------------------------------------
# INDEPENDENT SOLVER (answer key proof).
# Brute-force over permutations of tray into scan cells; facing is free
# so FACING never blocks a permutation. Prunes aggressively.
# ------------------------------------------------------------------
func solve_all(items: Array, rules: Array, max_found: int = 3) -> Array:
	var found: Array = []
	var n := items.size()
	# Accept full boards (bays*2) or one-short sets (skip-delivery).
	if n != bays * 2 and n != bays * 2 - 1:
		return found
	# Pad a one-short set with a null "empty slot" that satisfies every
	# rule wherever it lands (it occupies one scan cell).
	var padded: Array = items.duplicate()
	while padded.size() < bays * 2:
		padded.append(null)
	items = padded
	n = items.size()
	var used: Array = []
	var cur: Array = []   # item indices in scan order
	var weights: Array = []
	var exps: Array = []
	var cats: Array = []
	for it in items:
		if it == null:
			weights.append(-1)
			exps.append(-1)
			cats.append("~NULL~")   # never matches a real category
		else:
			weights.append(it["w"])
			exps.append(it["exp"])
			cats.append(it["cat"])
	var need_weight: bool = "WEIGHT" in rules
	var need_fifo: bool = "FIFO" in rules
	var need_adj: bool = "ADJACENCY" in rules
	var cat_positions := {}
	_recurse(cur, used, n, found, items, weights, exps, cats,
			need_weight, need_fifo, need_adj, max_found, cat_positions)
	cat_positions.clear()
	return found


func _recurse(cur: Array, used: Array, n: int, found: Array, items: Array,
		weights: Array, exps: Array, cats: Array, need_weight: bool,
		need_fifo: bool, need_adj: bool, max_found: int,
		cat_positions: Dictionary) -> void:
	if found.size() >= max_found:
		return
	var k := cur.size()
	if k == n:
		found.append(_manifest(items, cur))
		return
	var remaining: Array = []
	for i in range(n):
		if not used.has(i):
			remaining.append(i)
	for idx in remaining:
		# WEIGHT prune: candidate would be BACK of bay (k even -> pairs with next).
		if need_weight and k % 2 == 0 and k + 1 < n:
			# can't know back yet — defer; instead prune when candidate is BACK.
			pass
		if need_weight and k % 2 == 1:
			if weights[cur[k - 1]] < weights[idx]:
				continue  # front heavier than this back — invalid pair
		# FIFO prune: expiry must not decrease vs previous scan cell.
		if need_fifo and k > 0:
			if exps[cur[k - 1]] > exps[idx]:
				continue
		# ADJACENCY prune: a category whose block was already closed may not
		# reappear; also the candidate must not close its own block while an
		# item of that category remains unused elsewhere.
		if need_adj:
			var c_now: String = cats[idx]
			var c_prev: String = cats[cur[k - 1]] if k > 0 else ""
			if cat_positions.get(c_now, true) == false:
				continue  # block closed, category re-appearing
			if k > 0 and c_now != c_prev:
				cat_positions[c_prev] = false  # close previous block
		used.append(idx)
		cur.append(idx)
		_recurse(cur, used, n, found, items, weights, exps, cats,
				need_weight, need_fifo, need_adj, max_found, cat_positions)
		cur.pop_back()
		used.pop_back()
		if need_adj and k > 0:
			cat_positions.erase(cats[idx])
			cat_positions[cats[cur[k - 1]]] = true  # reopen previous block


func _manifest(items: Array, cur: Array) -> String:
	var parts: Array = []
	for idx in cur:
		var it = items[idx]
		if it == null:
			parts.append("__")
		else:
			parts.append("%s(W%d,E%d)" % [it["cat"], it["w"], it["exp"]])
	return " | ".join(parts)


# ------------------------------------------------------------------
# MOVES
# ------------------------------------------------------------------
func place_from_tray(tray_idx: int, bay: int, row: int) -> void:
	var cur = shelf[bay][row]
	shelf[bay][row] = tray[tray_idx]
	if cur == null:
		tray.remove_at(tray_idx)
	else:
		tray[tray_idx] = cur
	last_hint_item = {}


func swap_shelf(bay_a: int, row_a: int, bay_b: int, row_b: int) -> void:
	var tmp = shelf[bay_a][row_a]
	shelf[bay_a][row_a] = shelf[bay_b][row_b]
	shelf[bay_b][row_b] = tmp
	last_hint_item = {}


func flip_item(bay: int, row: int) -> void:
	var it = shelf[bay][row]
	if it != null:
		it["face_out"] = not it["face_out"]
		last_hint_item = {}


func flip_tray_item(tray_idx: int) -> void:
	tray[tray_idx]["face_out"] = not tray[tray_idx]["face_out"]
	last_hint_item = {}


# ------------------------------------------------------------------
# HINT (rewarded placement hook, D9): highlight ONE violating item.
# Priority: first rule broken -> report its most-offending placed item;
# falls back to any wrong slot vs. answer key reconstruction.
# ------------------------------------------------------------------
func use_hint() -> Dictionary:
	if hints_left <= 0 or is_solved():
		return {}
	hints_left -= 1
	var res := audit()
	var target := {}
	for r in active_rules:
		if res.get(r, false):
			continue
		match r:
			"FACING":
				target = _first_unflipped_placed()
			"WEIGHT":
				target = _worst_weight_pair()
			"FIFO":
				target = _worst_fifo_step()
			"ADJACENCY":
				target = _stray_category_item()
		if not target.is_empty():
			break
	if target.is_empty():
		target = _misplaced_vs_key()
	if target.is_empty():
		target = _any_placed_or_tray()
	if not target.is_empty():
		target["rule"] = target.get("rule", "")
		last_hint_item = target
	return target


func _item_ref(it: Dictionary) -> String:
	return str(it.get("id", "")) + "|" + str(it.get("exp", "")) + "|" + str(it.get("w", ""))


func _locate_placed(it: Dictionary) -> Dictionary:
	for bay in range(bays):
		for row in range(2):
			var c = shelf[bay][row]
			if c != null and _item_ref(c) == _item_ref(it):
				return {"bay": bay, "row": row}
	return {}


func _first_unflipped_placed() -> Dictionary:
	for bay in range(bays):
		for row in range(2):
			var c = shelf[bay][row]
			if c != null and not c["face_out"]:
				var loc := {"bay": bay, "row": row}
				loc["rule"] = "FACING"
				return loc
	return {}


func _worst_weight_pair() -> Dictionary:
	for bay in range(bays):
		var f = shelf[bay][0]
		var b = shelf[bay][1]
		if f != null and b != null and f["w"] < b["w"]:
			return {"bay": bay, "row": 1, "rule": "WEIGHT"}  # heavy one sits on top-row-back wrongly
	return {}


func _worst_fifo_step() -> Dictionary:
	var scan := scan_order()
	for k in range(1, scan.size()):
		if scan[k] != null and scan[k - 1] != null and scan[k]["exp"] < scan[k - 1]["exp"]:
			var loc := _locate_placed(scan[k])
			if not loc.is_empty():
				loc["rule"] = "FIFO"
				return loc
	return {}


func _stray_category_item() -> Dictionary:
	var scan := scan_order()
	var runs := {}   # cat -> [start,end]
	for k in range(scan.size()):
		var it = scan[k]
		if it == null:
			continue
		if not runs.has(it["cat"]):
			runs[it["cat"]] = [k, k]
		else:
			runs[it["cat"]][1] = k
	var worst_cat := ""
	var worst_span := -1
	for cat in runs:
		var span: int = runs[cat][1] - runs[cat][0]
		if span > runs[cat].count(cat):  # always true placeholder; pick widest span
			pass
		if span > worst_span and span > 0:
			# broken iff other categories inside its span
			var inner_other := false
			for k in range(runs[cat][0], runs[cat][1] + 1):
				var s_it = scan[k]
				if s_it != null and s_it["cat"] != cat:
					inner_other = true
					break
			if inner_other:
				worst_cat = cat
				worst_span = span
	if worst_cat == "":
		return {}
	# point at the intruder inside that category's span
	for k in range(runs[worst_cat][0], runs[worst_cat][1] + 1):
		var it = scan[k]
		if it != null and it["cat"] != worst_cat:
			var loc := _locate_placed(it)
			if not loc.is_empty():
				loc["rule"] = "ADJACENCY"
				return loc
	return {}


func _misplaced_vs_key() -> Dictionary:
	# Reconstruct one valid arrangement from the CURRENT multiset and
	# flag the first placed item whose scan cell differs.
	var sols := solve_all(_placed_all(), active_rules, 1)
	if sols.is_empty():
		return {}
	var want: Array = []
	for part in sols[0].split(" | "):
		want.append(part)
	var scan := scan_order()
	for k in range(scan.size()):
		var it = scan[k]
		if it == null:
			continue
		var tag: String = "%s(W%d,E%d)" % [it["cat"], it["w"], it["exp"]]
		if k < want.size() and want[k] != tag:
			var loc := _locate_placed(it)
			if not loc.is_empty():
				loc["rule"] = "PLACEMENT"
				return loc
	return {}


func _any_placed_or_tray() -> Dictionary:
	for bay in range(bays):
		for row in range(2):
			if shelf[bay][row] != null:
				return {"bay": bay, "row": row, "rule": "CHECK"}
	return {"tray_idx": 0, "rule": "CHECK"} if not tray.is_empty() else {}


# ------------------------------------------------------------------
# SKIP DELIVERY (rewarded placement hook, D9): remove one tray item
# from play (max 1/level). The audit then expects one empty slot.
# Refused when the remaining set has no valid arrangement over the
# active rules.
# ------------------------------------------------------------------
func can_skip_delivery(idx: int) -> bool:
	if skips_used >= MAX_SKIPS:
		return false
	if tray.is_empty() or idx < 0 or idx >= tray.size():
		return false
	var combined: Array = _placed_all() + tray.duplicate()
	combined.remove_at(_placed_all().size() + idx)
	return not solve_all(combined, active_rules, 1).is_empty()


func skip_delivery(idx: int) -> bool:
	if not can_skip_delivery(idx):
		return false
	tray.remove_at(idx)
	skips_used += 1
	last_hint_item = {}
	return true


func serialize_manifest() -> String:
	var sols := solve_all(tray, active_rules, 1)
	return "seed=%d stage=%d rules=%s\nanswer_key[0]: %s" % [
		seed_value, stage_index + 1, ",".join(active_rules),
		sols[0] if not sols.is_empty() else "NONE"]
