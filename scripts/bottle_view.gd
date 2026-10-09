class_name BottleView
extends Control
## A resolution-independent glass vessel. Liquid is clipped to the inner glass
## and measured by polygon area, so the water stays level while the tube tips.

signal tapped(index: int)

var layers: Array = []
var capacity: int = 4
var palette: Array = [Color("ff6298"), Color("43dcd2"), Color("ffd45a"), Color("9874ff")]
var selected: bool = false
var complete: bool = false
var concealed: bool = false
var accessible: bool = false
var style_id: int = 0
var reduced_motion: bool = false
var highlighted: bool = false
var tube_index: int = 0
var pour_out: float = 0.0
var pour_in: float = 0.0
var incoming_color: int = 0
var motion_time: float = 0.0

var _font: Font
var _frame_clock: float = 0.0
var _celebration: float = 0.0
var _rejection: float = 0.0
var _last_tap_ms: int = -1000


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE if mouse_filter == Control.MOUSE_FILTER_IGNORE else Control.FOCUS_ALL
	_font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://assets/fonts/Nunito-ExtraBold.ttf"):
		_font = load("res://assets/fonts/Nunito-ExtraBold.ttf") as Font
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var activate: bool = false
	if event is InputEventMouseButton:
		activate = event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	elif event is InputEventScreenTouch:
		activate = event.pressed
	elif event is InputEventKey:
		activate = event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE)
	if activate:
		accept_event()
		var now: int = Time.get_ticks_msec()
		# A touch may also produce an emulated mouse click on desktop exports.
		if now - _last_tap_ms > 90:
			_last_tap_ms = now
			tapped.emit(tube_index)


func sync(new_layers: Array, new_capacity: int) -> void:
	layers = new_layers.duplicate()
	capacity = maxi(new_capacity, 1)
	pour_out = 0.0
	pour_in = 0.0
	queue_redraw()


func mouth_global() -> Vector2:
	return get_global_transform() * Vector2(size.x * 0.5, size.y * 24.0 / 220.0)


func pulse_complete() -> void:
	_celebration = 1.0
	queue_redraw()


func reject() -> void:
	_rejection = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	motion_time += delta
	_celebration = maxf(0.0, _celebration - delta * 0.66)
	_rejection = maxf(0.0, _rejection - delta * 3.0)
	_frame_clock += delta
	if _frame_clock >= 1.0 / 30.0:
		_frame_clock = 0.0
		queue_redraw()


func _draw() -> void:
	if size.x < 1.0 or size.y < 1.0:
		return
	var shake: float = sin(_rejection * 28.0) * _rejection * 4.0 if not reduced_motion else 0.0
	draw_set_transform(Vector2(shake, 0.0), 0.0, size / Vector2(100.0, 220.0))
	var outer: PackedVector2Array = _outer_shape()
	var inner: PackedVector2Array = _inner_shape()
	var outline: PackedVector2Array = _closed(outer)
	var aqua := Color("7cf8ed")
	var glow: Color = aqua if _rejection <= 0.01 else Color("ff789e")
	# The shadow is deliberately soft and low: vessels appear to stand on a shelf.
	_ellipse(Vector2(50, 211), Vector2(35, 5), Color(0.02, 0.02, 0.12, 0.13))
	_ellipse(Vector2(50, 210), Vector2(26, 3), Color(0.02, 0.02, 0.12, 0.11))
	if selected or highlighted or _rejection > 0.01:
		var breathe: float = 0.8 + sin(motion_time * 3.0) * 0.2 if not reduced_motion else 1.0
		draw_polyline(outline, Color(glow, 0.07 * breathe), 13.0, true)
		draw_polyline(outline, Color(glow, 0.16 * breathe), 7.0, true)
		draw_polyline(outline, Color(glow, 0.72), 2.2, true)
	if complete:
		draw_polyline(outline, Color(0.5, 1.0, 0.85, 0.07), 11.0, true)
	draw_colored_polygon(outer, Color(0.51, 0.74, 1.0, 0.10))
	draw_colored_polygon(inner, Color(0.08, 0.11, 0.25, 0.29))
	_draw_liquid(inner)
	if pour_in > 0.001:
		_draw_incoming_stream(inner)
	_draw_glass(outer, inner)
	_draw_rim()
	if selected:
		# The little pointer remains readable even when ambient animation is off.
		var hover: float = sin(motion_time * 4.0) * 1.5 if not reduced_motion else 0.0
		draw_colored_polygon(PackedVector2Array([Vector2(44, 5 + hover), Vector2(56, 5 + hover), Vector2(50, 12 + hover)]), Color("fff4cf"))
	if complete:
		_draw_complete_seal()
	if _celebration > 0.0:
		_draw_sparkles()
	draw_set_transform(Vector2.ZERO)


func _outer_shape() -> PackedVector2Array:
	if style_id == 1:
		return _rounded_rect_polygon(Rect2(18, 35, 64, 171), 13.0)
	if style_id == 2:
		return PackedVector2Array([
			Vector2(30, 25), Vector2(70, 25), Vector2(70, 53),
			Vector2(90, 161), Vector2(92, 175), Vector2(91, 187),
			Vector2(86, 198), Vector2(76, 205), Vector2(24, 205),
			Vector2(14, 198), Vector2(9, 187), Vector2(8, 175),
			Vector2(10, 161), Vector2(30, 53)])
	var points := PackedVector2Array([Vector2(19, 24), Vector2(81, 24), Vector2(81, 176)])
	for i in range(1, 17):
		var angle: float = float(i) / 16.0 * PI
		points.append(Vector2(50 + cos(angle) * 31, 176 + sin(angle) * 31))
	points.append(Vector2(19, 24))
	return points


func _inner_shape() -> PackedVector2Array:
	if style_id == 1:
		return _rounded_rect_polygon(Rect2(24, 42, 52, 157), 8.0)
	if style_id == 2:
		return PackedVector2Array([
			Vector2(36, 31), Vector2(64, 31), Vector2(64, 54),
			Vector2(84, 164), Vector2(86, 176), Vector2(84, 186),
			Vector2(80, 194), Vector2(73, 199), Vector2(27, 199),
			Vector2(20, 194), Vector2(16, 186), Vector2(14, 176),
			Vector2(16, 164), Vector2(36, 54)])
	var points := PackedVector2Array([Vector2(25, 31), Vector2(75, 31), Vector2(75, 175)])
	for i in range(1, 17):
		var angle: float = float(i) / 16.0 * PI
		points.append(Vector2(50 + cos(angle) * 25, 175 + sin(angle) * 25))
	points.append(Vector2(25, 31))
	return points


func _draw_liquid(inner: PackedVector2Array) -> void:
	var remaining: float = maxf(0.0, float(layers.size()) - pour_out)
	if remaining + pour_in < 0.001:
		return
	# Keep the liquid surface horizontal in world space as the vessel rotates.
	# Limiting the slope prevents singularities at the far end of the pour arc.
	var slope: float = clampf(-tan(rotation), -2.25, 2.25)
	var fill_area: float = _polygon_area(_clip_surface(inner, 51.0, 0.0, true))
	var unit_area: float = fill_area / maxf(float(capacity), 1.0)
	var hidden_before: int = 0
	if concealed and not complete and not layers.is_empty():
		hidden_before = layers.size() - 1
		while hidden_before > 0 and layers[hidden_before - 1] == layers[-1]:
			hidden_before -= 1
	var runs: Array = []
	for i in range(layers.size()):
		var amount: float = clampf(remaining - float(i), 0.0, 1.0)
		if amount <= 0.001:
			continue
		_append_run(runs, int(layers[i]), amount, i < hidden_before)
	if pour_in > 0.001:
		_append_run(runs, incoming_color, pour_in, false)
	var cumulative: float = 0.0
	var lower_line: float = 360.0
	for r in range(runs.size()):
		var run: Dictionary = runs[r]
		var amount: float = float(run.amount)
		cumulative += amount
		var upper_line: float = _surface_for_area(inner, cumulative * unit_area, slope)
		var liquid_polygon: PackedVector2Array = _clip_surface(inner, upper_line, slope, true)
		liquid_polygon = _clip_surface(liquid_polygon, lower_line, slope, false)
		var color_id: int = int(run.color)
		var mystery: bool = bool(run.mystery)
		var base: Color = Color("586187") if mystery else _color(color_id)
		if liquid_polygon.size() >= 3:
			draw_colored_polygon(liquid_polygon, base)
			# Multiple bands give candy-bright depth without a shader or texture.
			var span: float = maxf(1.0, minf(lower_line, 225.0) - upper_line)
			for band in range(7):
				var y0: float = upper_line + span * float(band) / 7.0
				var y1: float = upper_line + span * float(band + 1) / 7.0
				var strip: PackedVector2Array = _clip_surface(liquid_polygon, y0, slope, true)
				strip = _clip_surface(strip, y1, slope, false)
				if strip.size() >= 3:
					var brightness: float = 0.12 - float(band) * 0.032
					var shade: Color = base.lightened(brightness) if brightness > 0.0 else base.darkened(-brightness)
					draw_colored_polygon(strip, shade)
			# A shaded right edge and bright left bevel make each fill dimensional.
			var shade_strip: PackedVector2Array = _clip_axis(liquid_polygon, 66.0, true)
			if shade_strip.size() >= 3:
				draw_colored_polygon(shade_strip, Color(0.07, 0.02, 0.20, 0.10))
			_draw_meniscus(inner, upper_line, slope, base, r == runs.size() - 1)
			if mystery or accessible:
				var center_y: float = _surface_for_area(inner, (cumulative - amount * 0.5) * unit_area, slope)
				_draw_layer_label("?" if mystery else str(color_id + 1), Vector2(50, center_y), base)
		lower_line = upper_line


func _append_run(runs: Array, color_id: int, amount: float, mystery: bool) -> void:
	if not runs.is_empty() and runs[-1].color == color_id and runs[-1].mystery == mystery:
		runs[-1].amount += amount
	else:
		runs.append({"color": color_id, "amount": amount, "mystery": mystery})


func _draw_incoming_stream(inner: PackedVector2Array) -> void:
	# The outside stream meets this one just under the opening. Its landing
	# point follows the rising surface rather than stopping in empty air.
	var fill_area: float = _polygon_area(_clip_surface(inner, 51.0, 0.0, true))
	var amount: float = clampf(float(layers.size()) - pour_out + pour_in, 0.0, float(capacity))
	var surface_y: float = _surface_for_area(inner, fill_area * amount / maxf(float(capacity), 1.0), 0.0)
	if surface_y < 33.0:
		return
	var color: Color = _color(incoming_color)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var shine := PackedVector2Array()
	for i in range(19):
		var t: float = float(i) / 18.0
		var y: float = lerpf(27.0, surface_y + 1.0, t)
		var wiggle: float = sin(t * TAU * 2.0 + motion_time * 17.0) * 0.65 if not reduced_motion else 0.0
		var half_width: float = 2.7 - t * 0.75
		left.append(Vector2(50.0 + wiggle - half_width, y))
		right.append(Vector2(50.0 + wiggle + half_width, y))
		shine.append(Vector2(49.0 + wiggle, y))
	right.reverse()
	left.append_array(right)
	# The stream begins at the open neck and is clipped at every vessel edge.
	var intersections: Array[PackedVector2Array] = Geometry2D.intersect_polygons(left, inner)
	for part: PackedVector2Array in intersections:
		draw_colored_polygon(part, color.lightened(0.08))
	# The narrow open neck sits above the body's fill polygon.
	draw_line(Vector2(50, 27), Vector2(50, minf(44, surface_y)), color.lightened(0.08), 5.2, true)
	if shine.size() > 1:
		draw_polyline(shine, Color(1, 1, 1, 0.42), 1.1, true)
	# Concentric landing rings and tiny droplets give the pour a soft splash.
	var phase: float = fmod(motion_time * 2.8, 1.0) if not reduced_motion else 0.5
	_ellipse(Vector2(50, surface_y + 1), Vector2(4.0 + phase * 12.0, 1.0 + phase * 2.0), Color(color.lightened(0.5), (1.0 - phase) * 0.55))
	if not reduced_motion:
		for i in range(4):
			var splash_phase: float = fmod(motion_time * 2.3 + float(i) * 0.27, 1.0)
			var side: float = -1.0 if i % 2 == 0 else 1.0
			var point := Vector2(50 + side * (3 + splash_phase * 9.0), surface_y - sin(splash_phase * PI) * 9.0)
			if Geometry2D.is_point_in_polygon(point, inner):
				draw_circle(point, (1.0 - splash_phase) * 1.6, Color(color.lightened(0.5), 1.0 - splash_phase), true, -1, true)


func _draw_meniscus(inner: PackedVector2Array, line_y: float, slope: float, base: Color, topmost: bool) -> void:
	var intersections: Array[Vector2] = []
	for i in range(inner.size()):
		var a: Vector2 = inner[i]
		var b: Vector2 = inner[(i + 1) % inner.size()]
		var da: float = a.y - line_y - slope * (a.x - 50.0)
		var db: float = b.y - line_y - slope * (b.x - 50.0)
		if (da <= 0.0 and db > 0.0) or (da > 0.0 and db <= 0.0):
			intersections.append(a.lerp(b, da / (da - db)))
	if intersections.size() < 2:
		return
	intersections.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var left: Vector2 = intersections.front()
	var right: Vector2 = intersections.back()
	var surface := PackedVector2Array()
	var shimmer := PackedVector2Array()
	var amplitude: float = 0.0 if reduced_motion else (1.1 if topmost else 0.32)
	if topmost and (pour_in > 0.001 or pour_out > 0.001):
		amplitude *= 2.0
	for step in range(17):
		var t: float = float(step) / 16.0
		var point: Vector2 = left.lerp(right, t)
		point.y += sin(t * TAU * 1.4 + motion_time * 3.0 + tube_index) * sin(t * PI) * amplitude
		surface.append(point)
		if step > 2 and step < 12:
			shimmer.append(point + Vector2(0, 0.8))
	if topmost:
		draw_polyline(surface, Color(base.lightened(0.4), 0.85), 2.3, true)
		draw_polyline(shimmer, Color(1.0, 1.0, 1.0, 0.66), 1.0, true)
	else:
		draw_polyline(surface, Color(base.lightened(0.35), 0.42), 1.2, true)


func _draw_layer_label(text_value: String, center: Vector2, base: Color) -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	var text_size: Vector2 = _font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	var light: bool = base.get_luminance() > 0.4
	var ink: Color = Color("282448") if light else Color("ffffff")
	var outline: Color = Color(1, 1, 1, 0.16) if light else Color(0.04, 0.04, 0.15, 0.34)
	_ellipse(center, Vector2(11, 10), outline)
	draw_string(_font, center + Vector2(-text_size.x / 2.0, 5.5), text_value, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ink)


func _draw_glass(outer: PackedVector2Array, inner: PackedVector2Array) -> void:
	# Silvery blue outline, with a fine warm reflection on the upper left edge.
	draw_polyline(_closed(outer), Color(0.64, 0.82, 1.0, 0.53), 2.0, true)
	draw_polyline(_closed(inner), Color(0.9, 0.96, 1.0, 0.20), 0.8, true)
	if style_id == 2:
		draw_polyline(PackedVector2Array([Vector2(33, 34), Vector2(33, 53), Vector2(14, 162), Vector2(13, 177)]), Color(0.94, 0.98, 1.0, 0.78), 2.6, true)
		draw_polyline(PackedVector2Array([Vector2(68, 68), Vector2(86, 168), Vector2(87, 180)]), Color(0.66, 0.87, 1.0, 0.30), 2.0, true)
		draw_line(Vector2(30, 72), Vector2(22, 115), Color(1, 1, 1, 0.28), 3.5, true)
	elif style_id == 1:
		draw_polyline(PackedVector2Array([Vector2(22, 61), Vector2(22, 187), Vector2(25, 196), Vector2(32, 201)]), Color(0.94, 0.98, 1.0, 0.73), 2.2, true)
		draw_line(Vector2(78, 64), Vector2(78, 185), Color(0.71, 0.87, 1.0, 0.34), 1.8, true)
		draw_line(Vector2(28, 60), Vector2(28, 96), Color(1, 1, 1, 0.33), 3.5, true)
	else:
		draw_line(Vector2(22, 37), Vector2(22, 170), Color(0.94, 0.98, 1.0, 0.83), 2.3, true)
		draw_line(Vector2(78, 44), Vector2(78, 174), Color(0.7, 0.86, 1.0, 0.36), 1.7, true)
		draw_line(Vector2(29, 57), Vector2(29, 97), Color(1, 1, 1, 0.36), 3.0, true)
		draw_line(Vector2(29, 103), Vector2(29, 111), Color(1, 1, 1, 0.23), 3.0, true)
		draw_arc(Vector2(50, 175), 28.0, 0.20, PI - 0.28, 24, Color(0.73, 0.88, 1.0, 0.40), 2.1, true)
	# Subtle measuring marks help read capacity without cluttering the colors.
	for i in range(1, capacity):
		var y: float = 199.0 - 148.0 * float(i) / maxf(float(capacity), 1.0)
		if style_id != 2:
			draw_line(Vector2(72, y), Vector2(77, y), Color(1, 1, 1, 0.32), 1.0, true)


func _draw_rim() -> void:
	var width: float = 35.0 if style_id == 0 else (30.0 if style_id == 1 else 25.0)
	if style_id == 1:
		var neck := _rounded_rect_polygon(Rect2(26, 24, 48, 22), 5.0)
		draw_colored_polygon(neck, Color(0.57, 0.77, 1.0, 0.10))
		draw_polyline(_closed(neck), Color(0.7, 0.88, 1.0, 0.44), 1.5, true)
	_ellipse(Vector2(50, 26), Vector2(width, 6.2), Color(0.55, 0.76, 0.97, 0.19))
	_ellipse(Vector2(50, 23), Vector2(width, 5.0), Color(0.73, 0.9, 1.0, 0.55))
	_ellipse(Vector2(50, 22.5), Vector2(width - 5.0, 2.8), Color(0.13, 0.19, 0.34, 0.9))
	var rim_points := PackedVector2Array()
	for i in range(21):
		var angle: float = float(i) / 20.0 * PI
		rim_points.append(Vector2(50 + cos(angle) * width, 23 + sin(angle) * 5.0))
	draw_polyline(rim_points, Color(0.92, 0.98, 1.0, 0.88), 1.8, true)
	draw_line(Vector2(50 - width + 9, 20.7), Vector2(46, 19.3), Color(1, 1, 1, 0.54), 1.4, true)


func _draw_complete_seal() -> void:
	var center := Vector2(78, 49)
	draw_circle(center + Vector2(0, 2), 11.0, Color(0.05, 0.12, 0.25, 0.2), true, -1.0, true)
	draw_circle(center, 11.0, Color("6aefce"), true, -1.0, true)
	draw_arc(center, 10.0, PI * 1.05, PI * 1.85, 16, Color(1, 1, 1, 0.62), 1.3, true)
	draw_polyline(PackedVector2Array([center + Vector2(-4.5, 0), center + Vector2(-1.2, 3.5), center + Vector2(5, -3)]), Color("19475c"), 2.5, true)


func _draw_sparkles() -> void:
	var progress: float = 1.0 - _celebration
	var fade: float = minf(1.0, _celebration * 2.5)
	for i in range(12):
		var angle: float = float(i) * TAU / 12.0 + float(tube_index) * 0.7
		var travel: float = 6.0 if reduced_motion else progress * 31.0
		var center := Vector2(50, 119) + Vector2(cos(angle) * (38 + travel), sin(angle) * (79 + travel))
		center.y += progress * progress * 16.0 if not reduced_motion else 0.0
		var color: Color = Color("fff0a6") if i % 2 == 0 else Color("95fff0")
		color.a = fade
		var radius: float = (2.5 + float(i % 3)) * fade
		if i % 3 == 0:
			_draw_star(center, radius, color)
		else:
			draw_circle(center, radius * 0.65, color, true, -1.0, true)


func _draw_star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(8):
		var angle: float = float(i) * PI / 4.0
		var r: float = radius if i % 2 == 0 else radius * 0.32
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, color)


func _color(index: int) -> Color:
	if palette.is_empty():
		return Color("ff70a2")
	return palette[posmod(index, palette.size())]


func _ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(40):
		var angle: float = TAU * float(i) / 40.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_colored_polygon(points, color)


func _rounded_rect_polygon(rect: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var centers: Array[Vector2] = [
		rect.position + Vector2(rect.size.x - radius, radius),
		rect.end - Vector2(radius, radius),
		rect.position + Vector2(radius, rect.size.y - radius),
		rect.position + Vector2(radius, radius)]
	for corner in range(4):
		for i in range(7):
			var angle: float = -PI * 0.5 + float(corner) * PI * 0.5 + float(i) / 6.0 * PI * 0.5
			points.append(centers[corner] + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = points.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result


func _polygon_area(points: PackedVector2Array) -> float:
	var area: float = 0.0
	for i in range(points.size()):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		area += a.x * b.y - b.x * a.y
	return absf(area) * 0.5


func _surface_for_area(shape: PackedVector2Array, target: float, slope: float) -> float:
	var low: float = -180.0
	var high: float = 390.0
	for iteration in range(13):
		var midpoint: float = (low + high) * 0.5
		if _polygon_area(_clip_surface(shape, midpoint, slope, true)) > target:
			low = midpoint
		else:
			high = midpoint
	return (low + high) * 0.5


func _clip_surface(points: PackedVector2Array, line_y: float, slope: float, below: bool) -> PackedVector2Array:
	var output := PackedVector2Array()
	if points.is_empty():
		return output
	var direction: float = 1.0 if below else -1.0
	for i in range(points.size()):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		var da: float = direction * (a.y - line_y - slope * (a.x - 50.0))
		var db: float = direction * (b.y - line_y - slope * (b.x - 50.0))
		if da >= 0.0:
			output.append(a)
		if (da >= 0.0 and db < 0.0) or (da < 0.0 and db >= 0.0):
			output.append(a.lerp(b, da / (da - db)))
	return output


func _clip_axis(points: PackedVector2Array, x: float, right: bool) -> PackedVector2Array:
	var output := PackedVector2Array()
	var direction: float = 1.0 if right else -1.0
	for i in range(points.size()):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % points.size()]
		var da: float = direction * (a.x - x)
		var db: float = direction * (b.x - x)
		if da >= 0.0:
			output.append(a)
		if (da >= 0.0 and db < 0.0) or (da < 0.0 and db >= 0.0):
			output.append(a.lerp(b, da / (da - db)))
	return output
