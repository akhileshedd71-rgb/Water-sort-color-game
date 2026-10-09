extends SceneTree
## Scene-level checks exercise real button callbacks and the animated tap flow.
## Each run uses its own save filename so real player progress is never touched.

const MainScene = preload("res://scenes/main.tscn")
const Catalog = preload("res://scripts/level_catalog.gd")
const Rules = preload("res://scripts/puzzle_rules.gd")
const Storage = preload("res://scripts/save_store.gd")
var game: Control
var assertions := 0
var failures := 0


func _initialize() -> void:
	Storage.save_path = "user://prism_test_game_%d.json" % Time.get_ticks_usec()
	Engine.max_fps = 120
	_run.call_deferred()


func check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(description)


func _settle() -> void:
	await process_frame
	await process_frame
	await create_timer(0.22).timeout
	await process_frame


func _wait_for_pour() -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while game.busy and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	check(not game.busy, "Pour animation finishes and releases input")
	await process_frame


func _button_with_text(node: Node, prefix: String) -> Button:
	if node is Button and node.text.begins_with(prefix):
		return node
	for child in node.get_children():
		var found := _button_with_text(child, prefix)
		if found != null:
			return found
	return null


func _press(prefix: String) -> void:
	var button := _button_with_text(game, prefix)
	check(button != null, "Visible action exists: " + prefix)
	if button != null:
		check(not button.disabled, "Action is enabled: " + prefix)
		button.pressed.emit()


func _new_game() -> void:
	game = MainScene.instantiate()
	root.add_child(game)
	await _settle()
	game.save.data.sound = false
	game.save.data.reduced_motion = true
	game._apply_preferences()


func _pour(source: int, destination: int) -> void:
	if game.selected >= 0:
		game._tap_tube(game.selected)
	game._tap_tube(source)
	game._tap_tube(destination)
	await _wait_for_pour()


func _run() -> void:
	await _new_game()
	check(game.screen == "home", "Application opens on its home screen")
	_press("Let's play")
	await _settle()
	check(game.screen == "game" and int(game.level.id) == 1, "Home play button opens the first campaign puzzle")
	check(game.views.size() == game.tubes.size(), "The board creates a clickable view for every tube")
	for view: Control in game.views:
		check(view.size.x > 0 and view.size.y > 0, "Laid-out tube has a usable hit area")
	await _test_invalid_moves()
	await _test_undo_restart_helper()
	await _test_rapid_actions_and_full_animation()
	await _test_resume()
	await _test_win_and_next()
	await _test_screens_and_preferences()
	await _test_modes()
	game.queue_free()
	await process_frame
	await process_frame
	for suffix: String in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Storage.save_path + suffix))
	print("Game integration tests: %d checks, %d failures" % [assertions, failures])
	quit(1 if failures > 0 else 0)


func _test_invalid_moves() -> void:
	var before: Array = game.tubes.duplicate(true)
	game._tap_tube(-1)
	game._tap_tube(999)
	check(game.tubes == before and game.moves == 0, "Out-of-range input cannot change the puzzle")
	for index in game.tubes.size():
		if game.tubes[index].is_empty():
			game._tap_tube(index)
			break
	check(game.selected == -1 and game.moves == 0, "Tapping an empty source does not begin a move")
	var source := -1
	var destination := -1
	for index in game.tubes.size():
		if not game.tubes[index].is_empty():
			if source < 0:
				source = index
			elif game.tubes[index].size() == game.capacity:
				destination = index
				break
	game._tap_tube(source)
	game._tap_tube(destination)
	check(game.tubes == before and game.moves == 0 and game.undo_stack.is_empty(), "Pouring into a full tube preserves liquids, pour count, and undo history")
	check(game.status_label.text.contains("full"), "Rejected full target gives an actionable explanation")
	if game.selected >= 0:
		game._tap_tube(game.selected)


func _test_undo_restart_helper() -> void:
	var initial: Array = game.tubes.duplicate(true)
	var move: Array = game.level.solution[0]
	await _pour(int(move[0]), int(move[1]))
	check(game.moves == 1 and game.tubes != initial, "A legal tap pair transfers liquid and counts one pour")
	check(not game.undo_button.disabled, "A legal move enables undo")
	_press("Undo")
	await _settle()
	check(game.tubes == initial and game.moves == 0, "Undo restores the exact board and pour count")
	check(game.undo_stack.is_empty(), "Undo consumes its history entry")
	var original_count: int = game.tubes.size()
	_press("+ Tube")
	await _settle()
	check(game.tubes.size() == original_count + 1 and game.extra_used, "Helper action adds one empty tube")
	check(game.extra_button.disabled, "Only one helper tube is offered per attempt")
	game._add_tube()
	check(game.tubes.size() == original_count + 1, "Repeated helper requests cannot add more tubes")
	_press("Undo")
	await _settle()
	check(game.tubes == initial and not game.extra_used and not game.extra_button.disabled, "Undoing a helper restores the board and helper availability")
	await _pour(int(move[0]), int(move[1]))
	var after_move: Array = game.tubes.duplicate(true)
	_press("Restart")
	check(game.overlay != null, "Restart asks before discarding an attempt")
	_press("Keep playing")
	check(game.overlay == null and game.tubes == after_move, "Canceling restart preserves the attempt")
	_press("Restart")
	_press("Restart this puzzle")
	await _settle()
	check(game.tubes == initial and game.moves == 0 and game.undo_stack.is_empty(), "Confirmed restart restores the opening puzzle and clears undo")


func _test_resume() -> void:
	var initial: Array = game.tubes.duplicate(true)
	var move: Array = game.level.solution[0]
	await _pour(int(move[0]), int(move[1]))
	var saved_board: Array = game.tubes.duplicate(true)
	game._save_run()
	game.queue_free()
	await process_frame
	await _new_game()
	_press("Keep pouring")
	await _settle()
	check(game.screen == "game" and game.moves == 1 and game.tubes == saved_board, "Reopening restores the exact unfinished campaign board and pours")
	_press("Undo")
	await _settle()
	check(game.tubes == initial and game.moves == 0, "Undo history remains usable after reopening")


func _test_rapid_actions_and_full_animation() -> void:
	var initial: Array = game.tubes.duplicate(true)
	var move: Array = game.level.solution[0]
	await _pour(int(move[0]), int(move[1]))
	# These intentionally happen within one frame. A deferred helper/undo layout
	# used to destroy the source view after the following pour had already begun.
	_press("Undo")
	_press("+ Tube")
	check(game.extra_button.disabled, "Rapid helper action immediately disables a second helper")
	_press("Undo")
	await _pour(int(move[0]), int(move[1]))
	check(game.moves == 1 and game.tubes != initial, "Rapid undo/helper/undo/pour leaves animation and state usable")
	_press("Undo")
	await _settle()
	check(game.tubes == initial and game.moves == 0, "Rapid-action sequence remains fully reversible")
	game.save.data.reduced_motion = false
	game._apply_preferences()
	var expected: Dictionary = Rules.pour(initial, int(move[0]), int(move[1]), game.capacity)
	game._tap_tube(int(move[0]))
	game._tap_tube(int(move[1]))
	await create_timer(0.4).timeout
	check(game.busy and absf(game.views[int(move[0])].rotation) > 0.1, "Standard animation lifts and tips the pouring bottle")
	check(game.effects.stream_active, "Standard animation shows a flowing stream during transfer")
	game._tap_tube(int(move[0]))
	check(game.selected == -1, "Taps during a pour cannot start a competing move")
	game._on_resize()
	await _wait_for_pour()
	await _settle()
	check(game.tubes == expected.tubes and game.moves == 1, "Resizing during a full animation preserves the exact transfer")
	check(game.views.size() == game.tubes.size(), "A resize rebuilds every tube after the active pour finishes")
	_press("Undo")
	await _settle()
	game.save.data.reduced_motion = true
	game._apply_preferences()


func _test_win_and_next() -> void:
	var solution: Array = game.level.solution.duplicate(true)
	for move: Array in solution:
		await _pour(int(move[0]), int(move[1]))
	check(Rules.is_solved(game.tubes, game.capacity), "The real tap flow can solve the opening puzzle")
	check(game.overlay != null and _button_with_text(game, "Next little adventure") != null, "Completing a puzzle displays a next-level action")
	check(game.save.data.completed.has("1") and game.save.data.unlocked == 2, "Winning records completion and unlocks level two")
	check(game.save.data.coins == 15 and game.save.data.active_run.is_empty(), "Winning awards sparkles once and clears the finished run")
	var before: Array = game.tubes.duplicate(true)
	game._tap_tube(0)
	check(game.tubes == before and game.selected == -1, "The victory dialog blocks board input")
	game._on_resize()
	await _settle()
	check(game.overlay != null and _button_with_text(game, "Next little adventure") != null, "Resizing after victory preserves the next-level action")
	check(game.save.data.coins == 15, "Rebuilding the victory dialog does not award duplicate sparkles")
	_press("Next little adventure")
	await _settle()
	check(int(game.level.id) == 2 and game.moves == 0 and game.overlay == null, "Next-level action starts a fresh second puzzle")
	game._start_level(Catalog.get_level(1), "campaign")
	await _settle()
	for move: Array in solution:
		await _pour(int(move[0]), int(move[1]))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	game._unhandled_key_input(escape)
	await _settle()
	check(game.screen == "home" and game.overlay == null, "Escape after victory returns to a navigable home screen")
	check(game.save.data.coins == 15, "Replaying a solved level does not award duplicate sparkles")
	game._continue_campaign()
	await _settle()


func _test_screens_and_preferences() -> void:
	game._show_settings()
	check(game.overlay != null, "Settings opens over the current puzzle")
	_press("Color labels")
	check(game.save.data.accessible, "Color label setting toggles on")
	for view: Control in game.views:
		check(view.accessible, "Every gameplay tube receives color accessibility labels")
	_press("Gentle motion")
	check(not game.save.data.reduced_motion and not game.backdrop.reduced_motion, "Motion setting updates active scenery")
	_press("Gentle motion")
	check(game.save.data.reduced_motion and game.effects.reduced_motion, "Gentle motion updates animation effects")
	_press("All comfy")
	check(game.overlay == null, "Settings can return to the current puzzle")
	game._show_levels(0)
	await _settle()
	check(game.screen == "levels", "Chapter selection builds")
	var unlocked := _button_with_text(game, "2")
	var locked := _button_with_text(game, "3")
	check(unlocked != null and not unlocked.disabled and locked != null and locked.disabled, "Chapter selection enforces campaign unlocks")
	game._show_levels(5)
	await _settle()
	check(_button_with_text(game, "240") != null, "The final chapter exposes level 240")
	game._show_modes()
	await _settle()
	check(game.screen == "modes" and _button_with_text(game, "Let's go") != null, "Modes screen exposes play actions")
	game._show_studio()
	await _settle()
	check(game.screen == "studio" and _button_with_text(game, "Candy cosmos") != null, "Color studio builds its appearance choices")
	game._show_home()
	await _settle()
	check(game.screen == "home", "Navigation can return to home")


func _test_modes() -> void:
	var campaign_before: Dictionary = game.save.data.active_run.duplicate(true)
	game._start_mode("daily")
	await _settle()
	check(game.screen == "game" and game.run_kind == "daily", "Daily mode starts a playable puzzle")
	check(game.launch_date == game.level.daily_date, "Daily reward key matches the generated puzzle's UTC day")
	check(not game.level.solution.is_empty() and game.views.size() == game.tubes.size(), "Daily puzzle has visible tubes and a certified solution")
	check(game.save.data.active_run == campaign_before, "Starting daily mode preserves a suspended campaign attempt")
	game._start_mode("freeplay")
	await _settle()
	check(game.run_kind == "freeplay" and not game.level.solution.is_empty(), "Endless mode starts a certified remix")
	for mode: String in ["mist", "tall", "tight"]:
		game._start_mode(mode)
		await _settle()
		check(game.run_kind == "freeplay" and game.level.mode == mode, "Special mode launches its matching puzzle: " + mode)
		if mode == "mist":
			check(game.views[0].concealed, "Mystery mode marks hidden layers for rendering")
		elif mode == "tall":
			check(game.capacity == 5, "Sky high uses five-layer bottles")
	check(game.save.data.active_run == campaign_before, "Exploring play modes never overwrites campaign progress")
