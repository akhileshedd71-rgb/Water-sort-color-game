class_name PourOverlay
extends Control

var stream_active := false
var stream_start := Vector2.ZERO
var stream_end := Vector2.ZERO
var stream_color := Color.WHITE
var stream_progress := 0.0
var reduced_motion := false
var clock := 0.0
var particles: Array = []
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	rng.randomize()

func burst(at: Vector2, color: Color, count: int = 24) -> void:
	if reduced_motion:
		return
	for i in count:
		var angle := rng.randf_range(-PI, 0.0)
		var speed := rng.randf_range(75.0, 260.0)
		particles.append({"p": at, "v": Vector2(cos(angle), sin(angle)) * speed,
			"life": rng.randf_range(0.6, 1.5), "max": 1.5, "c": color.lerp(Color.WHITE, rng.randf() * 0.4),
			"s": rng.randf_range(2.0, 6.0), "r": rng.randf() * TAU})

func celebrate(view_size: Vector2) -> void:
	for x in [0.2, 0.5, 0.8]:
		burst(Vector2(view_size.x * x, view_size.y * 0.5), [Color("ff72b8"), Color("69f3df"), Color("ffdb75")][int(x * 3.0)], 40)

func _process(delta: float) -> void:
	clock += delta
	for p: Dictionary in particles:
		p.life -= delta
		p.v.y += 240.0 * delta
		p.p += p.v * delta
		p.r += delta * 2.0
	particles = particles.filter(func(p: Dictionary) -> bool: return p.life > 0.0)
	if stream_active or not particles.is_empty():
		queue_redraw()
	elif stream_progress != 0.0:
		stream_progress = 0.0
		queue_redraw()

func _draw() -> void:
	if stream_active:
		var points := PackedVector2Array()
		for i in 25:
			var t := float(i) / 24.0
			var p := stream_start.lerp(stream_end, t)
			p.x += sin(t * PI) * 9.0 + sin(t * TAU * 2.0 + clock * 16.0) * 1.2
			points.append(p)
		draw_polyline(points, Color(stream_color, 0.12), 22.0, true)
		draw_polyline(points, Color(stream_color, 0.28), 13.0, true)
		draw_polyline(points, stream_color, 7.0, true)
		var shine := points.duplicate()
		for i in shine.size():
			shine[i].x -= 1.5
		draw_polyline(shine, Color(1, 1, 1, 0.48), 2.0, true)
		for i in 5:
			var phase := fmod(clock * 2.0 + float(i) / 5.0, 1.0)
			var splash := stream_end + Vector2(sin(float(i) * 2.4) * 22.0 * phase, -sin(phase * PI) * 22.0)
			draw_circle(splash, 2.5 * (1.0 - phase), Color(stream_color, 1.0 - phase))
	for p: Dictionary in particles:
		var color: Color = p.c
		color.a = minf(float(p.life) * 2.0, 1.0)
		var pos: Vector2 = p.p
		var radius: float = p.s
		var poly := PackedVector2Array()
		for i in 4:
			poly.append(pos + Vector2.from_angle(float(p.r) + i * PI / 2.0) * radius)
		draw_colored_polygon(poly, color)
