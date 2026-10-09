class_name PuzzleRules
extends RefCounted
## Pure puzzle operations. Tubes store colors from their bottom to their top.


static func can_pour(tubes: Array, source: int, target: int, capacity: int) -> bool:
	if capacity <= 0 or source == target or source < 0 or target < 0:
		return false
	if source >= tubes.size() or target >= tubes.size():
		return false
	var from_tube: Array = tubes[source]
	var into_tube: Array = tubes[target]
	if from_tube.is_empty() or into_tube.size() >= capacity:
		return false
	return into_tube.is_empty() or int(from_tube.back()) == int(into_tube.back())


static func pour(tubes: Array, source: int, target: int, capacity: int) -> Dictionary:
	if not can_pour(tubes, source, target, capacity):
		return {}
	var next: Array = tubes.duplicate(true)
	var from_tube: Array = next[source]
	var into_tube: Array = next[target]
	var color: int = int(from_tube.back())
	var amount: int = mini(_top_run(from_tube), capacity - into_tube.size())
	for _unit in range(amount):
		into_tube.append(from_tube.pop_back())
	return {"tubes": next, "amount": amount, "color": color}


static func is_complete(tube: Array, capacity: int) -> bool:
	if capacity <= 0 or tube.size() != capacity:
		return false
	var color: int = int(tube[0])
	for value in tube:
		if int(value) != color:
			return false
	return true


static func is_solved(tubes: Array, capacity: int) -> bool:
	if tubes.is_empty() or capacity <= 0:
		return false
	var contains_liquid: bool = false
	for tube in tubes:
		if not tube.is_empty():
			contains_liquid = true
			if not is_complete(tube, capacity):
				return false
	return contains_liquid


static func _top_run(tube: Array) -> int:
	if tube.is_empty():
		return 0
	var count: int = 1
	var color: int = int(tube.back())
	for i in range(tube.size() - 2, -1, -1):
		if int(tube[i]) != color:
			break
		count += 1
	return count


static func _canonical_key(tubes: Array) -> String:
	var parts: Array[String] = []
	for tube in tubes:
		var part: String = ""
		for color in tube:
			part += str(int(color)) + ","
		parts.append(part)
	parts.sort()
	return "|".join(parts)


static func _estimate(tubes: Array, capacity: int) -> int:
	# Count separated blocks; a solved board has one block per color.
	var blocks: int = 0
	var colors: Dictionary = {}
	var almost_full: int = 0
	for tube in tubes:
		var previous: int = -1
		for value in tube:
			var color: int = int(value)
			colors[color] = true
			if color != previous:
				blocks += 1
			previous = color
		if not tube.is_empty() and not is_complete(tube, capacity):
			almost_full += 1
	return (blocks - colors.size()) * 5 + almost_full


static func _heap_push(heap: Array, node: Dictionary) -> void:
	heap.append(node)
	var position: int = heap.size() - 1
	while position > 0:
		var parent: int = (position - 1) / 2
		if float(heap[parent]["priority"]) <= float(node["priority"]):
			break
		heap[position] = heap[parent]
		position = parent
	heap[position] = node


static func _heap_pop(heap: Array) -> Dictionary:
	var result: Dictionary = heap[0]
	var tail: Dictionary = heap.pop_back()
	if heap.is_empty():
		return result
	var position: int = 0
	while position * 2 + 1 < heap.size():
		var child: int = position * 2 + 1
		if child + 1 < heap.size() and float(heap[child + 1]["priority"]) < float(heap[child]["priority"]):
			child += 1
		if float(tail["priority"]) <= float(heap[child]["priority"]):
			break
		heap[position] = heap[child]
		position = child
	heap[position] = tail
	return result


static func find_hint(tubes: Array, capacity: int, max_nodes: int = 30000) -> Array:
	## A bounded best-first search. Return only a move on a proven path to a win.
	## The caller can use the bundled certificate before invoking this fallback.
	if max_nodes <= 0 or is_solved(tubes, capacity):
		return []
	var start: Array = tubes.duplicate(true)
	var heap: Array = []
	var seen: Dictionary = {_canonical_key(start): 0}
	_heap_push(heap, {"board": start, "first": [], "depth": 0, "priority": _estimate(start, capacity)})
	var expanded: int = 0
	var deadline: int = Time.get_ticks_msec() + 1700
	while not heap.is_empty() and expanded < max_nodes:
		if expanded % 32 == 0 and Time.get_ticks_msec() > deadline:
			return []
		var current: Dictionary = _heap_pop(heap)
		var board: Array = current["board"]
		var depth: int = int(current["depth"])
		expanded += 1
		for source in range(board.size()):
			var from_tube: Array = board[source]
			if from_tube.is_empty() or is_complete(from_tube, capacity):
				continue
			var visited_empty: bool = false
			var source_homogeneous: bool = _top_run(from_tube) == from_tube.size()
			for target in range(board.size()):
				if not can_pour(board, source, target, capacity):
					continue
				var into_tube: Array = board[target]
				if into_tube.is_empty():
					if visited_empty or source_homogeneous:
						continue
					visited_empty = true
				var move_result: Dictionary = pour(board, source, target, capacity)
				var next: Array = move_result["tubes"]
				var state_key: String = _canonical_key(next)
				var next_depth: int = depth + 1
				if seen.has(state_key) and int(seen[state_key]) <= next_depth:
					continue
				seen[state_key] = next_depth
				var first: Array = [source, target] if depth == 0 else current["first"]
				if is_solved(next, capacity):
					return first
				_heap_push(heap, {"board": next, "first": first, "depth": next_depth, "priority": float(_estimate(next, capacity)) + next_depth * 0.4})
	return []
