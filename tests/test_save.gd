extends SceneTree
## Each run uses its own save filename so real player progress is never touched.

const Storage = preload("res://scripts/save_store.gd")
var assertions := 0
var failures := 0


func _initialize() -> void:
	Storage.save_path = "user://prism_test_save_%d.json" % Time.get_ticks_usec()
	_test_rewards()
	_test_side_mode_progress()
	_test_purchases()
	_test_round_trip_and_recovery()
	_remove_saves()
	print("Save tests: %d checks, %d failures" % [assertions, failures])
	quit(1 if failures > 0 else 0)


func check(condition: bool, description: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		push_error(description)


func _remove_saves() -> void:
	for suffix: String in ["", ".bak", ".tmp"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Storage.save_path + suffix))


func _write_raw(text: String) -> void:
	var file := FileAccess.open(Storage.save_path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _test_rewards() -> void:
	_remove_saves()
	var save := Storage.new()
	check(save.finish_level(1, 8, "campaign") == 15, "First campaign completion awards sparkles")
	check(save.data.unlocked == 2 and save.data.completed["1"] == 8, "Campaign completion unlocks next level and records pours")
	check(save.finish_level(1, 11, "campaign") == 0, "Replaying a completed level cannot farm sparkles")
	check(save.data.completed["1"] == 8, "A slower replay preserves personal best")
	save.finish_level(1, 5, "campaign")
	check(save.data.completed["1"] == 5, "A better replay improves personal best")
	check(save.finish_level(10, 12, "campaign") == 35, "Every tenth level has a larger reward")
	save.finish_level(240, 50, "campaign")
	check(save.data.unlocked == 240, "Final completion does not unlock a nonexistent level")
	check(save.finish_level(100, 15, "daily", "2026-10-09") == 30, "Daily puzzle pays its first completion")
	check(save.finish_level(100, 10, "daily", "2026-10-09") == 0, "Same daily date cannot pay twice")
	check(save.finish_level(100, 15, "daily", "2026-10-10") == 30, "A new daily date can earn its own reward")
	var restored := Storage.new()
	restored.load_save()
	check(restored.data.completed.keys() == save.data.completed.keys() and int(restored.data.completed["1"]) == 5 and int(restored.data.completed["240"]) == 50 and restored.data.coins == save.data.coins, "Rewards and best scores survive a reload")


func _test_side_mode_progress() -> void:
	_remove_saves()
	var save := Storage.new()
	var suspended := {"level_id": 3, "moves": 2, "tubes": [[0, 1], []], "extra_used": false}
	save.data.active_run = suspended.duplicate(true)
	save.finish_level(100, 16, "daily", "2026-10-09")
	check(save.data.active_run == suspended, "Winning a daily puzzle preserves suspended campaign progress")
	var before_coins: int = save.data.coins
	save.finish_level(150, 20, "freeplay")
	check(save.data.active_run == suspended, "Winning free play preserves suspended campaign progress")
	check(save.data.coins == before_coins and save.data.unlocked == 1 and save.data.completed.is_empty(), "Free play does not change campaign progression or rewards")
	save.finish_level(3, 20, "campaign")
	check(save.data.active_run.is_empty(), "Finishing the active campaign level clears its resumable run")


func _test_purchases() -> void:
	_remove_saves()
	var save := Storage.new()
	check(not save.buy("theme", 1, 90), "An unaffordable cosmetic purchase fails")
	check(save.data.coins == 0 and save.data.theme == 0 and save.data.owned_themes == [0], "Failed purchase preserves balance and equipped cosmetic")
	save.data.coins = 110
	check(save.buy("theme", 1, 90), "An affordable cosmetic is purchased")
	check(save.data.coins == 20 and save.data.theme == 1 and 1 in save.data.owned_themes, "Purchase deducts price and equips owned theme")
	check(save.buy("theme", 0, 0) and save.buy("theme", 1, 90), "Owned cosmetics can be re-equipped")
	check(save.data.coins == 20 and save.data.owned_themes.count(1) == 1, "Re-equipping never charges again or duplicates ownership")
	var restored := Storage.new()
	restored.load_save()
	check(restored.data.theme == 1 and restored.data.coins == 20, "Equipped cosmetic and balance survive reload")


func _test_round_trip_and_recovery() -> void:
	_remove_saves()
	var save := Storage.new()
	save.data.unlocked = 7
	save.data.coins = 123
	save.data.accessible = true
	save.data.reduced_motion = true
	check(save.persist(), "Initial save writes successfully")
	save.data.coins = 138
	check(save.persist(), "Second save writes and retains a backup")
	var restored := Storage.new()
	restored.load_save()
	check(restored.data.coins == 138 and restored.data.unlocked == 7, "JSON numeric values restore to valid progression")
	check(restored.data.accessible and restored.data.reduced_motion, "Accessibility preferences survive reload")
	_write_raw("{broken partial write")
	var recovered := Storage.new()
	recovered.load_save()
	check(recovered.data.coins == 123 and recovered.data.unlocked == 7, "Corrupt primary save recovers previous complete backup")
	_remove_saves()
	_write_raw(JSON.stringify({"version": 1, "unlocked": 999, "coins": -12, "theme": 55, "bottle": -1, "palette": 50, "sound": "false"}))
	var bounded := Storage.new()
	bounded.load_save()
	check(bounded.data.unlocked == 240 and bounded.data.coins == 0, "Out-of-range progression is clamped safely")
	check(bounded.data.theme == 2 and bounded.data.bottle == 0 and bounded.data.palette == 2, "Out-of-range appearance indices cannot crash rendering")
	check(bounded.data.sound == true, "An incorrectly typed setting retains its default")
	_remove_saves()
	_write_raw("[]")
	var invalid := Storage.new()
	invalid.load_save()
	check(invalid.data == Storage.DEFAULTS, "Unsupported save structures start with safe defaults")
