extends SceneTree
## Run with a graphical display; all screenshots use an isolated demo save.
var app: Control

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 800)
	app = load("res://scenes/main.tscn").instantiate()
	root.add_child(app)
	app.save.data = app.Storage.DEFAULTS.duplicate(true)
	app.save.data.sound = false
	app._apply_preferences()
	app._show_home()
	await _capture("home")
	app._start_level(app.Catalog.get_level(32), "campaign")
	await _capture("gameplay")
	var move: Array = app.level.solution[0]
	app._execute_pour(int(move[0]), int(move[1]))
	await create_timer(0.49).timeout
	await _capture("pouring", false)
	while app.busy: await process_frame
	app._show_modes()
	await _capture("modes")
	root.size = Vector2i(480, 800)
	await create_timer(0.4).timeout
	app._show_home()
	await _capture("home-portrait")
	app._start_level(app.Catalog.get_level(96), "freeplay")
	app.save.data.accessible = true
	app._apply_preferences()
	await _capture("portrait-mystery")
	root.size = Vector2i(1280, 800)
	await create_timer(0.4).timeout
	app._show_studio()
	await _capture("studio")
	quit()

func _capture(file_name: String, settle: bool = true) -> void:
	if settle:
		for frame in 5: await process_frame
		await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://docs/screenshots")
	var result := image.save_png("res://docs/screenshots/" + file_name + ".png")
	print("SCREENSHOT ", file_name, " ", image.get_size(), " result=", result)
