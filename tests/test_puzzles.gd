extends SceneTree

const Rules = preload("res://scripts/puzzle_rules.gd")
const Catalog = preload("res://scripts/level_catalog.gd")
var failures: int = 0
var assertions: int = 0


func _initialize() -> void:
	_test_rules()
	_test_campaign()
	_test_variants()
	_test_hints()
	print("Puzzle tests: %d checks, %d failures" % [assertions, failures])
	quit(1 if failures > 0 else 0)


func check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(description)


func _test_rules() -> void:
	var board: Array = [[0, 1, 1], [1], [2, 2, 2, 2], []]
	check(not Rules.can_pour(board, 0, 0, 4), "A bottle cannot pour into itself")
	check(not Rules.can_pour(board, -1, 1, 4), "Negative index is rejected")
	check(not Rules.can_pour(board, 0, 99, 4), "Out-of-range index is rejected")
	check(not Rules.can_pour(board, 3, 0, 4), "Empty source is rejected")
	check(not Rules.can_pour(board, 0, 2, 4), "Full destination is rejected")
	check(not Rules.can_pour([[0], [1]], 0, 1, 4), "Different top colors are rejected")
	check(Rules.pour(board, 0, 2, 4).is_empty(), "Invalid move returns empty result")
	var result: Dictionary = Rules.pour(board, 0, 1, 4)
	check(int(result["amount"]) == 2, "All consecutive top layers pour at once")
	check(int(result["color"]) == 1, "Pour reports the moved color")
	check(result["tubes"] == [[0], [1, 1, 1], [2, 2, 2, 2], []], "Resulting board is correct")
	check(board == [[0, 1, 1], [1], [2, 2, 2, 2], []], "Pour never mutates its input")
	var limited: Dictionary = Rules.pour([[0, 0, 0], [0, 0, 0]], 0, 1, 4)
	check(int(limited["amount"]) == 1, "Available space limits the transfer")
	check(Rules.is_complete([3, 3, 3, 3], 4), "A full uniform bottle is complete")
	check(not Rules.is_complete([3, 3], 4), "A partial uniform bottle is incomplete")
	check(not Rules.is_solved([[0, 0], [0, 0]], 4), "Split partial bottles are not a win")
	check(not Rules.is_solved([[], []], 4), "An empty board is not a level win")
	check(Rules.is_solved([[0, 0, 0, 0], [], [1, 1, 1, 1]], 4), "Sorted full bottles win")


func _verify_certificate(level: Dictionary, label: String) -> void:
	var board: Array = level["tubes"].duplicate(true)
	var capacity: int = int(level["capacity"])
	check(not Rules.is_solved(board, capacity), "%s starts unsolved" % label)
	for move in level["solution"]:
		var result: Dictionary = Rules.pour(board, int(move[0]), int(move[1]), capacity)
		check(not result.is_empty(), "%s has a legal solution move" % label)
		if result.is_empty():
			return
		board = result["tubes"]
	check(Rules.is_solved(board, capacity), "%s solution wins" % label)


func _test_campaign() -> void:
	var levels: Array = Catalog.all_levels()
	check(levels.size() == 240, "Campaign contains 240 levels")
	for level in levels:
		_verify_certificate(level, "Level %d" % int(level["id"]))
	var copy: Dictionary = Catalog.get_level(1)
	copy["tubes"][0].clear()
	check(not Catalog.get_level(1)["tubes"][0].is_empty(), "Catalog returns independent level copies")


func _test_variants() -> void:
	for seed_value in range(1, 21):
		var level: Dictionary = Catalog.freeplay_level(seed_value)
		_verify_certificate(level, "Free flow %d" % seed_value)
		check(level == Catalog.freeplay_level(seed_value), "Seeded Free flow is deterministic")
	var daily: Dictionary = Catalog.daily_level()
	_verify_certificate(daily, "Daily flow")
	check(daily == Catalog.daily_level(), "Today's puzzle is deterministic")


func _test_hints() -> void:
	var board: Array = [[0, 0, 0, 1], [1, 1, 1, 0], [], []]
	var hint: Array = Rules.find_hint(board, 4, 2000)
	check(hint.size() == 2, "Hint solver finds a proven opening")
	if hint.size() == 2:
		check(Rules.can_pour(board, int(hint[0]), int(hint[1]), 4), "Hint move is legal")
	check(Rules.find_hint(board, 4, 0).is_empty(), "Zero-budget search returns immediately")
	check(Rules.find_hint([[0, 1], [1, 0]], 2, 100).is_empty(), "Deadlocked boards do not invent a hint")
	check(Rules.find_hint([[0, 0, 0, 0], []], 4).is_empty(), "A solved board has no hint")
