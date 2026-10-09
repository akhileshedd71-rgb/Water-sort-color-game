class_name DropletMascot
extends Control
## Pip, the little water spirit, and its warm-yellow star companion.

@export var mood: String = "happy":
	set(value):
		mood = value
		queue_redraw()
@export var reduced_motion: bool = false

var _time: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _process(delta: float) -> void:
	if not reduced_motion:
		_time += delta
		queue_redraw()

func _draw() -> void:
	var scale_factor: float = minf(size.x / 200.0, size.y / 200.0)
	if scale_factor <= 0:
		return
	var bob: float = sin(_time * 2.2) * (5.0 if mood == "excited" else 3.0)
	var origin: Vector2 = (size - Vector2(200, 200) * scale_factor) * 0.5
	draw_set_transform(origin, 0, Vector2.ONE * scale_factor)
	draw_set_transform(origin + Vector2(103, 177) * scale_factor, 0, Vector2(1.0, 0.22) * scale_factor)
	draw_circle(Vector2.ZERO, 48.0 - bob * 0.6, Color(0.07, 0.05, 0.17, 0.28))
	draw_set_transform(origin + Vector2(0, bob) * scale_factor, 0, Vector2.ONE * scale_factor)
	# Rounded flippers, body and rim: clean scalable artwork, no textures.
	var left_hand := PackedVector2Array([Vector2(57, 112), Vector2(43, 104), Vector2(33, 108), Vector2(34, 119), Vector2(52, 131), Vector2(62, 130)])
	draw_colored_polygon(left_hand, Color("2fc9d2"))
	draw_circle(Vector2(37, 111), 7, Color("66e7e3"))
	var wave_y: float = sin(_time * 3.0) * 3.0
	draw_line(Vector2(144, 119), Vector2(164, 108 + wave_y), Color("2fc9d2"), 15.0, true)
	draw_circle(Vector2(164, 107 + wave_y), 8.0, Color("76eeea"))
	var body := _droplet(Vector2(100, 99), 1.0)
	draw_colored_polygon(body, Color("157dba"))
	draw_polyline(_closed(body), Color("493a87"), 3.0, true)
	var inner := _droplet(Vector2(100, 93), 0.92)
	draw_colored_polygon(inner, Color("32d9dd"))
	var shine := _droplet(Vector2(100, 84), 0.78)
	draw_colored_polygon(shine, Color("5ce8e4"))
	# Curved glossy highlight along the shoulder.
	var highlight := PackedVector2Array()
	for i in range(14):
		var t: float = float(i) / 13.0
		highlight.append(Vector2(67, 91).bezier_interpolate(Vector2(66, 76), Vector2(81, 58), Vector2(90, 51), t))
	draw_polyline(highlight, Color("c5fff1"), 7.0, true)
	draw_circle(Vector2(67, 91), 3.5, Color("c5fff1"))
	draw_circle(Vector2(64, 103), 3, Color("adfff2"))
	# Soft squashy feet and peach cheeks.
	draw_circle(Vector2(75, 158), 12.0, Color("27b8ce"))
	draw_circle(Vector2(126, 158), 12.0, Color("27b8ce"))
	draw_set_transform(origin + Vector2(0, bob) * scale_factor, 0, Vector2.ONE * scale_factor)
	draw_circle(Vector2(72, 122), 9.0, Color("f592c6"))
	draw_circle(Vector2(128, 122), 9.0, Color("f592c6"))
	var blink: bool = fmod(_time, 4.9) > 4.74
	if mood == "sleepy" or blink:
		draw_arc(Vector2(82, 108), 7.0, 0.1, PI - 0.1, 16, Color("293769"), 3.5, true)
		draw_arc(Vector2(119, 108), 7.0, 0.1, PI - 0.1, 16, Color("293769"), 3.5, true)
	elif mood == "excited":
		draw_polyline(PackedVector2Array([Vector2(77, 113), Vector2(83, 107), Vector2(89, 113)]), Color("293769"), 3.5, true)
		draw_polyline(PackedVector2Array([Vector2(113, 113), Vector2(119, 107), Vector2(125, 113)]), Color("293769"), 3.5, true)
	else:
		for x in [82.0, 119.0]:
			draw_set_transform(origin + Vector2(x, 111 + bob) * scale_factor, 0, Vector2(0.78, 1) * scale_factor)
			draw_circle(Vector2.ZERO, 7.5, Color("283461"))
			draw_circle(Vector2(2, -3), 2.25, Color("f6fffc"))
		draw_set_transform(origin + Vector2(0, bob) * scale_factor, 0, Vector2.ONE * scale_factor)
	if mood == "thinking":
		draw_circle(Vector2(101, 130), 4.0, Color("283461"))
	else:
		draw_arc(Vector2(101, 120), 10.0, 0.10, PI - 0.10, 24, Color("283461"), 3.5, true)
	# Floaty, asymmetric star sidekick gives the character a recognizable silhouette.
	var star_center := Vector2(155, 48 + sin(_time * 1.8 + 2.0) * 4.0)
	var star := PackedVector2Array()
	for i in range(10):
		var angle: float = float(i) * TAU / 10.0 - PI * 0.5 + 0.18
		star.append(star_center + Vector2(cos(angle), sin(angle)) * (17.0 if i % 2 == 0 else 9.0))
	draw_colored_polygon(star, Color("ffcd57"))
	draw_polyline(_closed(star), Color("ffe8a2"), 1.5, true)
	draw_circle(star_center + Vector2(-4, 0), 1.3, Color("946046"))
	draw_circle(star_center + Vector2(4, 0), 1.3, Color("946046"))
	draw_set_transform(Vector2.ZERO)

func _droplet(center: Vector2, body_scale: float) -> PackedVector2Array:
	var outline := PackedVector2Array()
	var segments: Array = [
		[Vector2(0, -68), Vector2(-9, -45), Vector2(-54, -13), Vector2(-54, 17)],
		[Vector2(-54, 17), Vector2(-55, 53), Vector2(-28, 64), Vector2(0, 64)],
		[Vector2(0, 64), Vector2(30, 64), Vector2(57, 47), Vector2(55, 17)],
		[Vector2(55, 17), Vector2(52, -8), Vector2(16, -34), Vector2(0, -68)]
	]
	for segment in segments:
		for i in range(18):
			var p: Vector2 = segment[0].bezier_interpolate(segment[1], segment[2], segment[3], float(i) / 18.0)
			outline.append(center + p * body_scale)
	return outline

func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	result.append(points[0])
	return result
