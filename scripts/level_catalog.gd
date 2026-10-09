class_name LevelCatalog
extends RefCounted
## The campaign is fully bundled and playable without a network connection.

static var _levels: Array = []


static func all_levels() -> Array:
	if _levels.is_empty():
		var file: FileAccess = FileAccess.open("res://data/levels.json", FileAccess.READ)
		if file == null:
			push_error("Could not read the bundled campaign.")
			return []
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if parsed is Array:
			_levels = parsed
	return _levels


static func get_level(id: int) -> Dictionary:
	var levels: Array = all_levels()
	if levels.is_empty():
		return {}
	var index: int = clampi(id - 1, 0, levels.size() - 1)
	return levels[index].duplicate(true)


static func daily_level() -> Dictionary:
	var date: Dictionary = Time.get_date_dict_from_system(true)
	var seed_value: int = int(date["year"]) * 10000 + int(date["month"]) * 100 + int(date["day"])
	var level: Dictionary = freeplay_level(seed_value)
	if level.is_empty():
		return {}
	level["name"] = "Daily flow"
	level["daily_date"] = "%04d-%02d-%02d" % [date["year"], date["month"], date["day"]]
	level["is_daily"] = true
	return level


static func freeplay_level(seed_value: int = 0) -> Dictionary:
	var levels: Array = all_levels()
	if levels.is_empty():
		return {}
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	var level: Dictionary = get_level(rng.randi_range(21, levels.size()))
	var original: Array = level["tubes"]
	var order: Array[int] = []
	var palette: Array[int] = []
	for index in range(original.size()):
		order.append(index)
	for color in range(10):
		palette.append(color)
	_shuffle(order, rng)
	_shuffle(palette, rng)
	var tubes: Array = []
	var old_to_new: Dictionary = {}
	for index in range(order.size()):
		old_to_new[order[index]] = index
		var tube: Array = []
		for color in original[order[index]]:
			tube.append(palette[int(color)])
		tubes.append(tube)
	var solution: Array = []
	for move in level["solution"]:
		solution.append([old_to_new[int(move[0])], old_to_new[int(move[1])]])
	level["source_id"] = level["id"]
	level["tubes"] = tubes
	level["solution"] = solution
	level["name"] = "Free flow"
	level["is_freeplay"] = true
	level["seed"] = seed_value
	return level


static func _shuffle(values: Array[int], rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var previous: int = values[index]
		values[index] = values[other]
		values[other] = previous
