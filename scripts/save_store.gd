class_name SaveStore
extends RefCounted

const PATH := "user://prism_save.json"
static var save_path: String = PATH

const DEFAULTS := {
	"version": 1, "unlocked": 1, "completed": {}, "coins": 0,
	"theme": 0, "bottle": 0, "palette": 0,
	"owned_themes": [0], "owned_bottles": [0], "owned_palettes": [0],
	"sound": true, "accessible": false, "reduced_motion": false,
	"daily_wins": {}, "tutorial_seen": false, "active_run": {}
}
var data: Dictionary = DEFAULTS.duplicate(true)

func load_save() -> void:
	for path: String in [save_path, save_path + ".bak"]:
		if not FileAccess.file_exists(path):
			continue
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK:
			continue
		var parsed: Variant = parser.data
		if parsed is Dictionary and parsed.get("version") == 1:
			for key: String in DEFAULTS:
				if parsed.has(key) and typeof(parsed[key]) == typeof(DEFAULTS[key]):
					data[key] = parsed[key]
				# JSON numbers are floats, even when the defaults are integers.
				elif parsed.has(key) and DEFAULTS[key] is int and (parsed[key] is float or parsed[key] is int):
					data[key] = int(parsed[key])
			data.unlocked = clampi(int(data.unlocked), 1, 240)
			data.coins = maxi(int(data.coins), 0)
			data.theme = clampi(int(data.theme), 0, 2)
			data.bottle = clampi(int(data.bottle), 0, 2)
			data.palette = clampi(int(data.palette), 0, 2)
			return

func persist() -> bool:
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if file == null:
		push_warning("Could not save progress: " + error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	var absolute: String = ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(save_path):
		DirAccess.copy_absolute(absolute, absolute + ".bak")
	return DirAccess.rename_absolute(absolute + ".tmp", absolute) == OK

func finish_level(level_id: int, move_count: int, kind: String, date_key: String = "") -> int:
	var reward := 0
	if kind == "campaign":
		var key := str(level_id)
		if not data.completed.has(key):
			reward = 15 if level_id % 10 != 0 else 35
			data.completed[key] = move_count
		else:
			data.completed[key] = mini(int(data.completed[key]), move_count)
		data.unlocked = maxi(int(data.unlocked), mini(level_id + 1, 240))
	elif kind == "daily" and not data.daily_wins.has(date_key):
		data.daily_wins[date_key] = true
		reward = 30
	data.coins += reward
	if kind == "campaign":
		data.active_run = {}
	persist()
	return reward

func buy(category: String, item: int, price: int) -> bool:
	var owned_key := "owned_" + category + "s"
	if item not in data[owned_key]:
		if int(data.coins) < price:
			return false
		data.coins -= price
		data[owned_key].append(item)
	data[category] = item
	return persist()
