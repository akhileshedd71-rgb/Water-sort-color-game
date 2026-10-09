class_name AmbientBackdrop
extends Control
## Original vector scenery. The quiet middle keeps liquid colours easy to read.

@export var theme_id: int = 0:
	set(value):
		theme_id = clampi(value, 0, 2)
		queue_redraw()
@export var reduced_motion: bool = false

var _time: float = 0.0
var _frame_time: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()

func _process(delta: float) -> void:
	if reduced_motion:
		return
	_time += delta
	_frame_time += delta
	if _frame_time >= 1.0 / 30.0:
		_frame_time = 0.0
		queue_redraw()

func _draw() -> void:
	if size.x < 1.0 or size.y < 1.0:
		return
	var palettes: Array = [
		[Color("201640"), Color("34215d"), Color("673d93"), Color("a25fcd"), Color("f774c4"), Color("72e5dc")],
		[Color("301a44"), Color("583054"), Color("994c76"), Color("dc7396"), Color("ffae82"), Color("ffd477")],
		[Color("102e49"), Color("14495b"), Color("26778a"), Color("39aeb2"), Color("83e6d2"), Color("b6a1ff")]
	]
	var colors: Array = palettes[theme_id]
	for band in range(48):
		var amount: float = float(band) / 47.0
		draw_rect(Rect2(0, size.y * amount, size.x, size.y / 47.0 + 2.0), colors[0].lerp(colors[1], amount))
	# Gentle colour at the edges, leaving the play space dark and untextured.
	_glow(Vector2(size.x * 0.04, size.y * 0.28), size.x * 0.30, Color(colors[3], 0.018))
	_glow(Vector2(size.x * 0.97, size.y * 0.48), size.x * 0.22, Color(colors[5], 0.010))
	for i in range(30):
		var x: float = fmod(float(i * 137 + 29), 997.0) / 997.0 * size.x
		var y: float = fmod(float(i * 89 + 51), 613.0) / 613.0 * size.y * 0.82
		var phase: float = float(i) * 1.83
		var alpha: float = 0.18 + 0.15 * (0.5 + 0.5 * sin(_time * 0.65 + phase))
		var radius: float = 1.0 + float(i % 3) * 0.55
		var p := Vector2(x, y + sin(_time * 0.18 + phase) * 3.0)
		if theme_id == 2:
			draw_arc(p, radius + 2.0, 0, TAU, 18, Color(colors[5], alpha), 1.0, true)
		elif i % 5 == 0:
			_star(p, radius * 3.0, Color("b9a1e6") * Color(1, 1, 1, alpha))
		else:
			draw_circle(p, radius, Color("ded2ff") * Color(1, 1, 1, alpha))
	# A small original orbiting candy planet, kept out near the margin.
	var planet := Vector2(size.x * 0.90, size.y * 0.18)
	var planet_radius: float = minf(size.x * 0.035, 28.0)
	draw_circle(planet, planet_radius, Color(colors[2], 0.50))
	draw_circle(planet + Vector2(-planet_radius * 0.3, -planet_radius * 0.32), planet_radius * 0.60, Color(colors[3], 0.19))
	draw_set_transform(planet, -0.30, Vector2(1.65, 0.42))
	draw_arc(Vector2.ZERO, planet_radius, 0.0, TAU, 48, Color(colors[4], 0.24), 2.0, true)
	draw_set_transform(Vector2.ZERO)
	# Layers of soft candy dunes anchor the screen without crowding the board.
	_hill(size.y * 0.91, size.y * 0.027, 2.0, 1.6, Color(colors[2], 0.44))
	_hill(size.y * 0.955, size.y * 0.024, 3.0, 3.1, Color(colors[3], 0.38))
	_hill(size.y * 0.997, size.y * 0.022, 2.3, 0.8, Color(colors[2], 0.96))
	var scenery_scale: float = clampf(size.x / 950.0, 0.65, 1.2)
	_crystal(Vector2(size.x * 0.065, size.y * 0.995), 24.0 * scenery_scale, 74.0 * scenery_scale, colors[5])
	_crystal(Vector2(size.x * 0.097, size.y * 1.012), 21.0 * scenery_scale, 50.0 * scenery_scale, colors[3])
	_crystal(Vector2(size.x * 0.91, size.y * 1.012), 22.0 * scenery_scale, 54.0 * scenery_scale, colors[4])
	_crystal(Vector2(size.x * 0.945, size.y * 1.008), 25.0 * scenery_scale, 81.0 * scenery_scale, colors[3])
	_cloud(Vector2(size.x * 0.0, size.y * 0.93), 36.0 * scenery_scale, Color(colors[3], 0.34))
	_cloud(Vector2(size.x, size.y * 0.91), 31.0 * scenery_scale, Color(colors[3], 0.32))

func _glow(center: Vector2, radius: float, color: Color) -> void:
	for step in range(12, 0, -1):
		draw_circle(center, radius * float(step) / 12.0, color)

func _hill(height: float, amplitude: float, frequency: float, phase: float, color: Color) -> void:
	var points := PackedVector2Array([Vector2(-5, size.y + amplitude + 30.0)])
	for i in range(65):
		var x: float = float(i) / 64.0 * (size.x + 10.0) - 5.0
		var y: float = height + sin(float(i) / 64.0 * TAU * frequency + phase) * amplitude
		points.append(Vector2(x, y))
	points.append(Vector2(size.x + 5, size.y + amplitude + 30.0))
	draw_colored_polygon(points, color)

func _crystal(base: Vector2, width: float, height: float, color: Color) -> void:
	var points := PackedVector2Array([
		base + Vector2(-width * 0.6, 0), base + Vector2(-width, -height * 0.65),
		base + Vector2(-width * 0.1, -height), base + Vector2(width * 0.75, -height * 0.66), base + Vector2(width * 0.55, 0)
	])
	draw_colored_polygon(points, Color(color, 0.57))
	draw_colored_polygon(PackedVector2Array([points[0], points[1], points[2], base + Vector2(0, -height * 0.1)]), Color(color.lightened(0.30), 0.36))
	draw_polyline(PackedVector2Array([points[1], points[2], points[3]]), Color(color.lightened(0.45), 0.57), 2.0, true)

func _cloud(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center, radius, color)
	draw_circle(center + Vector2(-radius * 0.86, radius * 0.28), radius * 0.65, color)
	draw_circle(center + Vector2(radius * 0.88, radius * 0.40), radius * 0.72, color)

func _star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(8):
		var angle: float = float(i) * TAU / 8.0 - PI * 0.5
		points.append(center + Vector2(cos(angle), sin(angle)) * radius * (1.0 if i % 2 == 0 else 0.26))
	draw_colored_polygon(points, color)
