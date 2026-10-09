extends Control

const Rules = preload("res://scripts/puzzle_rules.gd")
const Catalog = preload("res://scripts/level_catalog.gd")
const Bottle = preload("res://scripts/bottle_view.gd")
const Backdrop = preload("res://scripts/ambient_backdrop.gd")
const Mascot = preload("res://scripts/droplet_mascot.gd")
const Sounds = preload("res://scripts/sound_bank.gd")
const Storage = preload("res://scripts/save_store.gd")
const Effects = preload("res://scripts/pour_overlay.gd")
const FONT = preload("res://assets/fonts/Nunito-Regular.ttf")
const BOLD = preload("res://assets/fonts/Nunito-ExtraBold.ttf")

const INK := Color("faf5ff")
const MUTED := Color("bcb1da")
const PINK := Color("ff69b6")
const AQUA := Color("67eddf")
const YELLOW := Color("ffda77")
const PURPLE := Color("a88aff")
const PANEL := Color("292049")
const CHAPTERS := ["Sweet beginnings", "Bubble boulevard", "The misty garden", "Sky-high sips", "A little wiggle room", "Prism playground"]
const CHAPTER_NOTES := ["Small pours. Big smiles.", "More colors, more possibilities.", "Reveal the colors, one pour at a time.", "Taller tubes. Deeper thinking.", "One spare bottle. Make it count.", "A wonderfully weird mix of everything."]
const PALETTES := [
	[Color("ff679f"), Color("52e4de"), Color("a886ff"), Color("ffdb63"), Color("75dd8c"), Color("ff984c"), Color("6999ff"), Color("ef78ef"), Color("f05266"), Color("cedcf4")],
	[Color("ff8195"), Color("94eedb"), Color("bca4ff"), Color("ffe5a0"), Color("a5e59b"), Color("ffb995"), Color("98b9ff"), Color("f3a8dd"), Color("e96687"), Color("d7edf9")],
	[Color("ff3879"), Color("00e8dd"), Color("9b62ff"), Color("ffe03b"), Color("57ed76"), Color("ff802a"), Color("4285ff"), Color("eb42e4"), Color("ef4242"), Color("d5ebff")]
]

var save := Storage.new()
var backdrop: Control
var sound: Node
var page: Control
var overlay: Control
var effects: Control
var screen := "home"
var chapter_page := 0
var level: Dictionary = {}
var tubes: Array = []
var initial_tubes: Array = []
var capacity := 4
var selected := -1
var moves := 0
var undo_stack: Array = []
var views: Array = []
var extra_used := false
var busy := false
var run_kind := "campaign"
var certificate_cursor := 0
var certificate_valid := true
var status_label: Label
var move_label: Label
var board: Control
var undo_button: Button
var extra_button: Button
var active_tween: Tween
var resize_pending := false
var toast_label: Label
var toast_timer: SceneTreeTimer
var pending_reward := 0
var won := false
var hint_pair: Array = []
var started := false
var launch_date := ""
var layout_ready := false
var layout_generation := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	save.load_save()
	var ui_theme := Theme.new()
	ui_theme.default_font = FONT
	ui_theme.default_font_size = 18
	theme = ui_theme
	backdrop = Backdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	sound = Sounds.new()
	add_child(sound)
	effects = Effects.new()
	effects.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(effects)
	_apply_preferences()
	resized.connect(_on_resize)
	get_tree().auto_accept_quit = false
	started = true
	_show_home()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_run()
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED and started:
		_save_run()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		if screen == "game" and won:
			_show_home()
		elif overlay != null:
			_close_overlay()
		elif screen == "game" and not busy:
			_save_run()
			_show_home()
		elif screen != "home":
			_show_home()
	elif screen == "game" and not busy and overlay == null:
		if event.keycode == KEY_Z or event.keycode == KEY_U:
			_undo()
		elif event.keycode == KEY_H:
			_hint()
		elif event.keycode == KEY_R:
			_confirm_restart()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			_tap_tube(event.keycode - KEY_1)
		elif event.keycode == KEY_0:
			_tap_tube(9)

func _on_resize() -> void:
	if not started or resize_pending:
		return
	resize_pending = true
	await get_tree().create_timer(0.15).timeout
	while busy:
		await get_tree().process_frame
	resize_pending = false
	_close_overlay()
	match screen:
		"home": _show_home()
		"game":
			_build_game()
			if won: _show_win_dialog.call_deferred()
		"levels": _show_levels(chapter_page)
		"modes": _show_modes()
		"studio": _show_studio()

func _mobile() -> bool:
	return size.x < 720.0

func _apply_preferences() -> void:
	backdrop.theme_id = int(save.data.theme)
	backdrop.reduced_motion = bool(save.data.reduced_motion)
	sound.enabled = bool(save.data.sound)
	effects.reduced_motion = bool(save.data.reduced_motion)
	for view: Control in views:
		if is_instance_valid(view):
			view.accessible = bool(save.data.accessible)
			view.reduced_motion = bool(save.data.reduced_motion)
			view.style_id = int(save.data.bottle)
			view.palette = PALETTES[int(save.data.palette)]
			view.queue_redraw()
	# Decorative bottles and Pip also respond immediately to accessibility changes.
	for visual: Node in find_children("*", "Control", true, false):
		if visual is Mascot or visual is Backdrop:
			visual.reduced_motion = bool(save.data.reduced_motion)
			visual.queue_redraw()
		elif visual is Bottle:
			visual.reduced_motion = bool(save.data.reduced_motion)
			visual.accessible = bool(save.data.accessible)
			visual.queue_redraw()

func _clear_page(next_screen: String) -> VBoxContainer:
	layout_generation += 1
	layout_ready = false
	_close_overlay()
	if is_instance_valid(page):
		remove_child(page)
		page.queue_free()
	views.clear()
	screen = next_screen
	page = MarginContainer.new()
	page.name = "Page_" + next_screen
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := 22 if _mobile() else 48
	for side: String in ["left", "right"]:
		page.add_theme_constant_override("margin_" + side, margin)
	page.add_theme_constant_override("margin_top", 22)
	page.add_theme_constant_override("margin_bottom", 18)
	add_child(page)
	move_child(effects, get_child_count() - 1)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	page.add_child(column)
	return column

func _style(color: Color, radius: int = 20, border: Color = Color.TRANSPARENT, bottom_shadow: bool = false) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(14)
	if border.a > 0:
		box.set_border_width_all(1)
		box.border_color = border
	if bottom_shadow:
		box.shadow_color = color.darkened(0.6)
		box.shadow_size = 1
		box.shadow_offset = Vector2(0, 5)
	return box

func _label(text_value: String, font_size: int = 20, color: Color = INK, heavy: bool = false) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	if heavy:
		label.add_theme_font_override("font", BOLD)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _wrap_label(text_value: String, font_size: int = 20, color: Color = MUTED) -> Label:
	var label := _label(text_value, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _icon(name_value: String) -> Texture2D:
	return load("res://assets/icons/" + name_value + ".svg") as Texture2D

func _button(text_value: String, callback: Callable, color: Color = PANEL, icon_name: String = "", height: int = 58) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = height
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", BOLD)
	button.add_theme_font_size_override("font_size", 18 if _mobile() else 19)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("786c96"))
	button.add_theme_stylebox_override("normal", _style(color, 18, color.lightened(0.2), true))
	button.add_theme_stylebox_override("hover", _style(color.lightened(0.12), 18, Color(color.lightened(0.5), 0.6), true))
	button.add_theme_stylebox_override("pressed", _style(color.darkened(0.14), 18, color.lightened(0.1)))
	button.add_theme_stylebox_override("disabled", _style(Color("201936"), 18, Color("39304c")))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, 18, AQUA))
	button.add_theme_constant_override("h_separation", 10)
	if not icon_name.is_empty():
		button.icon = _icon(icon_name)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 23)
	button.pressed.connect(func() -> void:
		sound.play("click")
		callback.call())
	return button

func _icon_button(icon_name: String, tooltip: String, callback: Callable) -> Button:
	var button := _button("", callback, Color("2c224b"), icon_name, 48)
	button.custom_minimum_size.x = 48
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.tooltip_text = tooltip
	return button

func _space(parent: Node, expand: bool = true, height: float = 0.0) -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size.y = height
	parent.add_child(spacer)
	return spacer

func _topbar(column: VBoxContainer, show_back: bool = true) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	if show_back:
		row.add_child(_icon_button("back", "Back to home", func() -> void:
			if busy: return
			_save_run()
			_show_home()))
	var mark := TextureRect.new()
	mark.texture = load("res://assets/icon.svg")
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(38, 42)
	row.add_child(mark)
	var logo := _label("prism", 32, INK, true)
	logo.add_theme_constant_override("outline_size", 0)
	row.add_child(logo)
	_space(row)
	var coin := _button(str(int(save.data.coins)), _show_studio, Color("352649"), "gem", 46)
	coin.custom_minimum_size.x = 82
	coin.add_theme_color_override("icon_normal_color", YELLOW)
	coin.add_theme_color_override("font_color", YELLOW)
	coin.tooltip_text = "Sparkles — earned by completing new levels"
	if screen == "game": coin.disabled = true
	row.add_child(coin)
	row.add_child(_icon_button("settings", "Settings & accessibility", _show_settings))

func _pill(text_value: String, color: Color = AQUA) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color(color, 0.10), 16, Color(color, 0.22)))
	var label := _label(text_value, 13, color, true)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel

func _show_home() -> void:
	var column := _clear_page("home")
	_topbar(column, false)
	var hero: BoxContainer = HBoxContainer.new() if not _mobile() else VBoxContainer.new()
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero.add_theme_constant_override("separation", 36 if not _mobile() else 8)
	column.add_child(hero)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_stretch_ratio = 1.0
	words.add_theme_constant_override("separation", 16 if not _mobile() else 10)
	hero.add_child(words)
	if not _mobile(): _space(words)
	var tag := HBoxContainer.new()
	words.add_child(tag)
	tag.add_child(_pill("A HAPPY LITTLE BRAIN BREAK", AQUA))
	var heading := _label("Good things\ncome in colors.", 62 if not _mobile() else 42, INK, true)
	heading.add_theme_constant_override("line_spacing", -5)
	words.add_child(heading)
	words.add_child(_wrap_label("A splash of color. A spark of joy.\nFind your flow, one lovely pour at a time.", 21 if not _mobile() else 18))
	_space(words, false, 10)
	var has_run: bool = not save.data.active_run.is_empty()
	var start := _button("Keep pouring" if has_run else "Let's play", _continue_campaign, Color("dc4b96"), "play", 68)
	start.add_theme_font_size_override("font_size", 24)
	start.custom_minimum_size.x = 270
	words.add_child(start)
	var completed_count: int = save.data.completed.size()
	var sub := _label("LEVEL %03d  ·  %d / 240 COMPLETE" % [int(save.data.unlocked), completed_count], 13, MUTED, true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.add_child(sub)
	if not _mobile(): _space(words)
	var art := Control.new()
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.custom_minimum_size = Vector2(0, 168 if _mobile() else 390)
	hero.add_child(art)
	_draw_home_art.call_deferred(art)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 14)
	column.add_child(nav)
	for item: Array in [["Levels", "grid", _show_levels.bind(-1)], ["Play modes", "infinity", _show_modes], ["Color studio", "palette", _show_studio]]:
		var button := _button(item[0], item[2], Color("30244f"), item[1], 62)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _mobile():
			button.text = {"Levels":"Levels", "Play modes":"Modes", "Color studio":"Studio"}[item[0]]
			button.add_theme_font_size_override("font_size", 16)
		nav.add_child(button)
	var footer := _label("240 colorful puzzles  /  no timers  /  just one more pour", 13, MUTED)
	if _mobile(): footer.text = "240 colorful puzzles. Zero pressure."
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(footer)

func _draw_home_art(art: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(art): return
	var center := art.size * Vector2(0.5, 0.48)
	var mascot := Mascot.new()
	mascot.size = Vector2(160, 160) if _mobile() else Vector2(250, 250)
	mascot.position = center - mascot.size * Vector2(0.45, 0.85)
	mascot.reduced_motion = bool(save.data.reduced_motion)
	mascot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(mascot)
	var samples: Array = [[0, 2, 1, 3], [1, 0, 2, 0], [3, 3, 3, 3]]
	for i in 3:
		var tube := Bottle.new()
		tube.size = Vector2(58, 132) if _mobile() else Vector2(102, 235)
		tube.position = center + Vector2((i - 1) * (77 if _mobile() else 126) - tube.size.x / 2.0, -20 if _mobile() else 32)
		tube.layers = samples[i]
		tube.palette = PALETTES[int(save.data.palette)]
		tube.capacity = 4
		tube.style_id = int(save.data.bottle)
		tube.complete = i == 2
		tube.reduced_motion = bool(save.data.reduced_motion)
		tube.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tube.rotation = (-0.12 if i == 0 else 0.1) if i != 1 else 0.0
		art.add_child(tube)
	if not _mobile():
		var note := _pill("MEET PIP. YOUR POURING PAL.", YELLOW)
		note.position = Vector2(center.x - 145, art.size.y - 35)
		art.add_child(note)

func _continue_campaign() -> void:
	var run: Dictionary = save.data.active_run
	if not run.is_empty() and _valid_saved_run(run):
		level = Catalog.get_level(int(run.level_id))
		capacity = int(level.capacity)
		tubes = run.tubes.duplicate(true)
		initial_tubes = level.tubes.duplicate(true)
		moves = int(run.moves)
		extra_used = bool(run.extra_used)
		undo_stack = run.get("undo", []).duplicate(true)
		certificate_cursor = int(run.get("certificate_cursor", 0))
		certificate_valid = bool(run.get("certificate_valid", false))
		run_kind = "campaign"
		selected = -1
		busy = false
		won = false
		_build_game()
	else:
		_start_level(Catalog.get_level(int(save.data.unlocked)), "campaign")

func _valid_saved_run(run: Dictionary) -> bool:
	if not run.has_all(["level_id", "tubes", "moves", "extra_used"]): return false
	if not run.tubes is Array or int(run.level_id) < 1 or int(run.level_id) > 240: return false
	var original: Dictionary = Catalog.get_level(int(run.level_id))
	var counts: Dictionary = {}
	for tube: Array in original.tubes:
		for color: Variant in tube: counts[int(color)] = counts.get(int(color), 0) + 1
	for tube: Variant in run.tubes:
		if not tube is Array or tube.size() > int(original.capacity): return false
		for color: Variant in tube:
			if not (color is float or color is int): return false
			counts[int(color)] = counts.get(int(color), 0) - 1
	for count: int in counts.values():
		if count != 0: return false
	return not Rules.is_solved(run.tubes, int(original.capacity))

func _start_level(next_level: Dictionary, kind: String) -> void:
	if busy: return
	level = next_level.duplicate(true)
	capacity = int(level.capacity)
	tubes = level.tubes.duplicate(true)
	initial_tubes = tubes.duplicate(true)
	run_kind = kind
	launch_date = str(level.get("daily_date", Time.get_date_string_from_system(true)))
	won = false
	moves = 0
	selected = -1
	undo_stack.clear()
	extra_used = false
	certificate_cursor = 0
	certificate_valid = true
	hint_pair.clear()
	_build_game()
	_save_run()

func _build_game() -> void:
	var column := _clear_page("game")
	_topbar(column)
	var titles := HBoxContainer.new()
	titles.add_theme_constant_override("separation", 18)
	column.add_child(titles)
	var title_column := VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.add_theme_constant_override("separation", 0)
	titles.add_child(title_column)
	var heading := "Level %03d" % int(level.id)
	if run_kind == "daily": heading = "Daily splash"
	elif run_kind == "freeplay": heading = "Just for the joy"
	title_column.add_child(_label(heading, 38 if not _mobile() else 32, INK, true))
	var chapter: int = clampi(int(level.get("chapter", 0)), 0, 5)
	title_column.add_child(_label(CHAPTERS[chapter] if run_kind == "campaign" else (launch_date if run_kind == "daily" else "A fresh little color adventure"), 16, MUTED))
	var info := VBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_child(info)
	var mode_name: String = {"classic":"CLASSIC", "mist":"MYSTERY", "tall":"SKY HIGH", "tight":"TIGHT SPACE"}.get(str(level.mode), "REMIX")
	info.add_child(_pill(mode_name, AQUA if level.mode == "classic" else PURPLE))
	move_label = _label("%d pours" % moves, 15, MUTED)
	move_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info.add_child(move_label)
	board = Control.new()
	board.name = "PuzzleBoard"
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.custom_minimum_size.y = 260
	column.add_child(board)
	status_label = _label(_initial_tip(), 16 if _mobile() else 18, MUTED)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size.y = 45
	column.add_child(status_label)
	var tools_row := HBoxContainer.new()
	tools_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tools_row.add_theme_constant_override("separation", 10 if _mobile() else 18)
	column.add_child(tools_row)
	undo_button = _button("Undo", _undo, PANEL, "undo", 60)
	var hint_button := _button("Hint", _hint, Color("41315f"), "hint", 60)
	var restart_button := _button("Restart", _confirm_restart, PANEL, "restart", 60)
	extra_button = _button("+ Tube", _add_tube, PANEL, "plus", 60)
	for button: Button in [undo_button, hint_button, restart_button, extra_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.x = 78 if _mobile() else 130
		button.add_theme_font_size_override("font_size", 15 if _mobile() else 18)
		if _mobile(): button.add_theme_constant_override("icon_max_width", 18)
		tools_row.add_child(button)
	undo_button.tooltip_text = "Unlimited undo · Z / U"
	hint_button.tooltip_text = "Find a move toward the solution · H"
	restart_button.tooltip_text = "Restart this puzzle · R"
	extra_button.tooltip_text = "One free helper bottle per attempt"
	var bottom := _label("No rush. You've got this." if _mobile() else "TAKE YOUR TIME     ·     Z  undo     ·     H  hint     ·     1–9 / 0  select a tube", 12, Color("897ca6"))
	bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(bottom)
	_layout_after_build.call_deferred(layout_generation)

func _initial_tip() -> String:
	if int(level.id) == 1 and run_kind == "campaign": return "Tap a bottle, then an empty bottle or a matching top color."
	if level.mode == "mist": return "A little mystery! Lower colors reveal as you pour."
	if level.mode == "tight": return "One spare bottle. Think a few pours ahead."
	if level.mode == "tall": return "Five layers of possibility. Sort each color into its own bottle."
	return "One color per bottle. Find your flow."

func _layout_after_build(generation: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if generation != layout_generation or screen != "game": return
	_layout_bottles()
	layout_ready = true

func _layout_bottles() -> void:
	if screen != "game" or not is_instance_valid(board): return
	for child: Node in board.get_children():
		board.remove_child(child)
		child.queue_free()
	views.clear()
	var n := tubes.size()
	var columns: int = mini(n, 7)
	if _mobile():
		columns = mini(n, 3) if n <= 6 else (5 if n <= 10 else 6)
	var rows: int = ceili(float(n) / columns)
	var cell_width: float = minf((board.size.x - 12.0) / columns, 138.0 if not _mobile() else 102.0)
	var cell_height: float = minf((board.size.y - 12.0) / rows, 254.0)
	var bottle_height: float = minf(cell_height - 28.0, cell_width * 2.1)
	var bottle_width: float = bottle_height / 2.22
	var start_y: float = maxf(2.0, (board.size.y - rows * cell_height) / 2.0)
	for i in n:
		var row: int = i / columns
		var count_in_row: int = mini(columns, n - row * columns)
		var col: int = i % columns
		var x: float = (board.size.x - count_in_row * cell_width) / 2.0 + col * cell_width + (cell_width - bottle_width) / 2.0
		var y: float = start_y + row * cell_height
		var view := Bottle.new()
		view.name = "Tube_%d" % i
		view.size = Vector2(bottle_width, bottle_height)
		view.position = Vector2(x, y)
		view.pivot_offset = Vector2(bottle_width / 2.0, bottle_height * 0.22)
		view.layers = tubes[i].duplicate()
		view.capacity = capacity
		view.palette = PALETTES[int(save.data.palette)]
		view.tube_index = i
		view.selected = i == selected
		view.complete = Rules.is_complete(tubes[i], capacity)
		view.concealed = level.mode == "mist"
		view.accessible = bool(save.data.accessible)
		view.style_id = int(save.data.bottle)
		view.reduced_motion = bool(save.data.reduced_motion)
		view.highlighted = i in hint_pair
		view.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		view.tapped.connect(_tap_tube)
		board.add_child(view)
		views.append(view)
		var number := _label("%02d" % (i + 1), 12, AQUA if view.complete else Color("82759d"), true)
		number.position = Vector2(x, y + bottle_height + 2)
		number.size.x = bottle_width
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		board.add_child(number)
	_update_controls()

func _update_controls() -> void:
	if not is_instance_valid(undo_button): return
	undo_button.disabled = undo_stack.is_empty() or busy
	extra_button.disabled = extra_used or busy
	move_label.text = "%d pour%s" % [moves, "" if moves == 1 else "s"]
	for i in views.size():
		views[i].selected = i == selected
		views[i].highlighted = i in hint_pair
		views[i].queue_redraw()

func _tap_tube(index: int) -> void:
	if busy or won or not layout_ready or overlay != null or index < 0 or index >= tubes.size() or screen != "game": return
	if selected == index:
		selected = -1
		_update_controls()
		return
	if selected < 0:
		if tubes[index].is_empty():
			status_label.text = "Pick a bottle with color in it first."
			return
		selected = index
		sound.play("select")
		status_label.text = "Now tap an empty bottle or the same top color."
		_update_controls()
		return
	if Rules.can_pour(tubes, selected, index, capacity):
		_execute_pour(selected, index)
	else:
		sound.play("invalid")
		views[index].reject()
		if tubes[index].size() >= capacity:
			status_label.text = "That bottle is full. Try one with a little room."
		else:
			status_label.text = "Top colors need to match. Empty bottles take any color."
		# Tapping another filled bottle switches the selection without trapping input.
		if not tubes[index].is_empty(): selected = index
		_update_controls()

func _snapshot() -> Dictionary:
	return {"tubes": tubes.duplicate(true), "moves": moves, "extra_used": extra_used,
		"certificate_cursor": certificate_cursor, "certificate_valid": certificate_valid}

func _execute_pour(source: int, target: int) -> void:
	if busy or won or not layout_ready: return
	var result: Dictionary = Rules.pour(tubes, source, target, capacity)
	if result.is_empty(): return
	busy = true
	undo_stack.append(_snapshot())
	selected = -1
	hint_pair.clear()
	_update_controls()
	var amount: int = int(result.amount)
	var color: int = int(result.color)
	var source_view: Control = views[source]
	var target_view: Control = views[target]
	var origin := source_view.position
	var original_z: int = source_view.z_index
	source_view.z_index = 5
	var short_motion: bool = bool(save.data.reduced_motion)
	if not short_motion:
		var direction := 1.0 if target_view.position.x >= source_view.position.x else -1.0
		var angle := direction * 1.13
		var local_mouth: Vector2 = source_view.mouth_global() - source_view.global_position
		var destination_mouth: Vector2 = target_view.mouth_global() - board.global_position
		var rotated_mouth: Vector2 = source_view.pivot_offset + (local_mouth - source_view.pivot_offset).rotated(angle)
		var destination_position: Vector2 = destination_mouth + Vector2(-direction * 14.0, -52.0) - rotated_mouth
		active_tween = create_tween().set_parallel(true)
		active_tween.tween_property(source_view, "position", destination_position, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		active_tween.tween_property(source_view, "rotation", angle, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		await active_tween.finished
		effects.stream_start = source_view.mouth_global() - effects.global_position
		effects.stream_end = target_view.mouth_global() - effects.global_position + Vector2(0, 5)
		effects.stream_color = PALETTES[int(save.data.palette)][color % 10]
		effects.stream_active = true
		effects.stream_progress = 1.0
	target_view.incoming_color = color
	sound.play("pour")
	active_tween = create_tween().set_parallel(true)
	var pour_time := 0.14 if short_motion else (0.35 + amount * 0.13)
	active_tween.tween_property(source_view, "pour_out", float(amount), pour_time)
	active_tween.tween_property(target_view, "pour_in", float(amount), pour_time)
	await active_tween.finished
	effects.stream_active = false
	effects.queue_redraw()
	tubes = result.tubes
	source_view.pour_out = 0.0
	target_view.pour_in = 0.0
	source_view.layers = tubes[source].duplicate()
	target_view.layers = tubes[target].duplicate()
	if not short_motion:
		active_tween = create_tween().set_parallel(true)
		active_tween.tween_property(source_view, "position", origin, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		active_tween.tween_property(source_view, "rotation", 0.0, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		await active_tween.finished
	source_view.z_index = original_z
	moves += 1
	if certificate_valid:
		var certificate: Array = level.get("solution", [])
		if certificate_cursor < certificate.size() and int(certificate[certificate_cursor][0]) == source and int(certificate[certificate_cursor][1]) == target:
			certificate_cursor += 1
		else:
			certificate_valid = false
	for i in [source, target]:
		views[i].complete = Rules.is_complete(tubes[i], capacity)
		if views[i].complete:
			views[i].pulse_complete()
			effects.burst(views[i].global_position + views[i].size * Vector2(0.5, 0.3), PALETTES[int(save.data.palette)][int(tubes[i][0]) % 10])
			sound.play("complete")
	busy = false
	_update_controls()
	if Rules.is_solved(tubes, capacity):
		_win()
	else:
		status_label.text = "Lovely. Keep the colors flowing."
		if not _any_moves(): status_label.text = "A little tangle! Undo a pour, or add your free helper tube."
		_save_run()

func _any_moves() -> bool:
	for i in tubes.size():
		for j in tubes.size():
			if Rules.can_pour(tubes, i, j, capacity): return true
	return false

func _undo() -> void:
	if busy or undo_stack.is_empty(): return
	var previous: Dictionary = undo_stack.pop_back()
	tubes = previous.tubes
	moves = int(previous.moves)
	extra_used = bool(previous.extra_used)
	certificate_cursor = int(previous.certificate_cursor)
	certificate_valid = bool(previous.certificate_valid)
	selected = -1
	hint_pair.clear()
	sound.play("undo")
	_layout_bottles()
	status_label.text = "A fresh perspective. Undo is always free."
	_save_run()

func _confirm_restart() -> void:
	if busy: return
	var body := _dialog("A fresh start?", "Reset this puzzle and try another path. Your completed levels stay safe.")
	body.add_child(_button("Restart this puzzle", func() -> void: _start_level(level, run_kind), Color("d54d92"), "restart"))
	body.add_child(_button("Keep playing", _close_overlay))

func _add_tube() -> void:
	if busy or extra_used: return
	undo_stack.append(_snapshot())
	tubes.append([])
	extra_used = true
	selected = -1
	_layout_bottles()
	sound.play("complete")
	status_label.text = "A little breathing room. Your helper bottle is free!"
	_save_run()

func _hint() -> void:
	if busy: return
	selected = -1
	var hint: Array = []
	var certificate: Array = level.get("solution", [])
	if certificate_valid and certificate_cursor < certificate.size():
		hint = certificate[certificate_cursor]
	else:
		status_label.text = "Pip is looking for a path…"
		await get_tree().process_frame
		hint = Rules.find_hint(tubes, capacity, 14000)
	if screen != "game" or not is_instance_valid(status_label): return
	if hint.size() == 2 and Rules.can_pour(tubes, int(hint[0]), int(hint[1]), capacity):
		hint_pair = hint.duplicate()
		selected = int(hint[0])
		status_label.text = "Try bottle %02d → %02d. Tap the glowing destination." % [int(hint[0]) + 1, int(hint[1]) + 1]
		sound.play("select")
	else:
		status_label.text = "This tangle needs a rethink. Undo a few pours or try a helper tube."
	_update_controls()

func _save_run() -> void:
	if screen != "game" or run_kind != "campaign" or tubes.is_empty() or busy: return
	if Rules.is_solved(tubes, capacity): return
	var run := _snapshot()
	run["level_id"] = int(level.id)
	run["undo"] = undo_stack.duplicate(true)
	save.data.active_run = run
	save.persist()

func _win() -> void:
	won = true
	pending_reward = save.finish_level(int(level.id), moves, run_kind, launch_date)
	sound.play("win")
	effects.celebrate(size)
	status_label.text = "Every color found its happy place."
	_show_win_dialog()

func _show_win_dialog() -> void:
	var milestone: bool = int(level.id) % 40 == 0 and run_kind == "campaign"
	var title := "Beautifully sorted!"
	if milestone: title = "A whole world of color!"
	var body := _dialog(title, ("Chapter complete. That's something to sparkle about!" if milestone else "A little patience. A little magic. All you.") + "\n%d lovely pours" % moves)
	var mascot := Mascot.new()
	mascot.mood = "excited"
	mascot.custom_minimum_size = Vector2(140, 125)
	mascot.reduced_motion = bool(save.data.reduced_motion)
	body.add_child(mascot)
	if pending_reward > 0:
		var reward := _label("+%d sparkles" % pending_reward, 25, YELLOW, true)
		reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(reward)
	if run_kind == "campaign" and int(level.id) < 240:
		body.add_child(_button("Next little adventure", func() -> void: _start_level(Catalog.get_level(int(level.id) + 1), "campaign"), Color("d54d92"), "play"))
	elif run_kind == "freeplay":
		body.add_child(_button("Another splash", func() -> void: _start_level(Catalog.freeplay_level(), "freeplay"), Color("d54d92"), "play"))
	else:
		body.add_child(_button("Explore more colors", _show_modes, Color("d54d92"), "infinity"))
	body.add_child(_button("Back to home", _show_home, PANEL, "home"))

func _dialog(title: String, description: String) -> VBoxContainer:
	_close_overlay()
	overlay = Control.new()
	overlay.name = "Dialog"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.035, 0.018, 0.09, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = minf(size.x - 36.0, 480.0)
	panel.add_theme_stylebox_override("panel", _style(Color("31234f"), 30, Color("795995")))
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 15)
	margin.add_child(body)
	var heading := _label(title, 30 if not _mobile() else 26, INK, true)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(heading)
	if not description.is_empty():
		var label := _wrap_label(description, 17)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(label)
	return body

func _close_overlay() -> void:
	if is_instance_valid(overlay):
		remove_child(overlay)
		overlay.queue_free()
	overlay = null

func _show_settings() -> void:
	if busy: return
	var body := _dialog("Make yourself comfy", "Your game. Your kind of happy.")
	for option: Array in [["sound", "Sound effects", "Soft chimes and bubbly pours"], ["accessible", "Color labels", "Numbers on every color layer"], ["reduced_motion", "Gentle motion", "Short pours, still scenery, fewer effects"]]:
		var key: String = option[0]
		var button := _button(option[1] + ("   ON" if save.data[key] else "   OFF"), func() -> void:
			save.data[key] = not save.data[key]
			save.persist()
			_apply_preferences()
			_show_settings(), Color("443260"), "check" if save.data[key] else "plus", 54)
		button.tooltip_text = option[2]
		body.add_child(button)
	body.add_child(_button("How to play", _show_help, PANEL, "book", 52))
	body.add_child(_button("All comfy", _close_overlay, Color("c94f96"), "check", 54))
	var note := _label("Progress saves automatically on this device.", 12, MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(note)

func _show_help() -> void:
	var body := _dialog("A few drops of wisdom", "Your goal: one full bottle for each color.")
	for line: String in ["1   Tap a bottle to pick it up.", "2   Tap an empty bottle or a matching top color.", "3   A matching group pours until the target is full.", "4   Sort every color. Empty spare bottles are fine."]:
		body.add_child(_wrap_label(line, 17, INK))
	body.add_child(_wrap_label("Mystery hides lower layers until you uncover them. Tall bottles hold five layers. Tight Space gives you only one spare. Undo and hints are always free.", 15))
	body.add_child(_button("Let's make a splash", _close_overlay, Color("d54d92"), "play"))

func _show_levels(chapter: int = -1) -> void:
	if busy: return
	chapter_page = clampi(chapter if chapter >= 0 else (int(save.data.unlocked) - 1) / 40, 0, 5)
	var column := _clear_page("levels")
	_topbar(column)
	var head := HBoxContainer.new()
	column.add_child(head)
	head.add_child(_icon_button("back", "Previous chapter", func() -> void: _show_levels(maxi(chapter_page - 1, 0))))
	var label := _label("%02d  /  %s" % [chapter_page + 1, CHAPTERS[chapter_page]], 29 if not _mobile() else 21, INK, true)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(label)
	head.add_child(_icon_button("chevron", "Next chapter", func() -> void: _show_levels(mini(chapter_page + 1, 5))))
	var note := _label(CHAPTER_NOTES[chapter_page], 17, MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5 if _mobile() else 8
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	for offset in 40:
		var id: int = chapter_page * 40 + offset + 1
		var done: bool = save.data.completed.has(str(id))
		var locked: bool = id > int(save.data.unlocked)
		var button := _button(str(id), func() -> void: _start_level(Catalog.get_level(id), "campaign"), Color("266360") if done else (Color("c34d98") if id == int(save.data.unlocked) else PANEL), "check" if done else ("lock" if locked else ""), 72 if _mobile() else 86)
		button.disabled = locked
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 20 if _mobile() else 25)
		if _mobile(): button.add_theme_constant_override("icon_max_width", 13)
		button.tooltip_text = "Complete level %d to unlock" % (id - 1) if locked else "Play level %d" % id
		grid.add_child(button)
	var footer := _label("%d / 240 little victories  ·  complete a level to unlock the next" % save.data.completed.size(), 14, MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(footer)

func _show_modes() -> void:
	if busy: return
	var column := _clear_page("modes")
	_topbar(column)
	column.add_child(_label("Pick your kind of play.", 42 if not _mobile() else 31, INK, true))
	column.add_child(_wrap_label("A tiny escape, a daily ritual, or a delightfully tricky twist.", 19))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 1 if _mobile() else 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 18)
	scroll.add_child(grid)
	var items: Array = [
		["Daily splash", "One shared puzzle each day. A fresh splash of joy.", "calendar", AQUA, "daily"],
		["Endless play", "Fresh color remixes. No unlocking. Just play.", "infinity", PINK, "freeplay"],
		["Mystery mix", "Hidden layers. Lovely little surprises.", "moon", PURPLE, "mist"],
		["Sky high", "Five layers to sort. A taller kind of challenge.", "spark", YELLOW, "tall"],
		["Tight space", "One spare tube. A deliciously clever squeeze.", "hint", AQUA, "tight"],
		["The color journey", "240 levels, six chapters, one colorful adventure.", "grid", PINK, "campaign"]]
	for item: Array in items:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", _style(Color(item[3], 0.09), 24, Color(item[3], 0.3)))
		grid.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		panel.add_child(box)
		box.add_child(_label(item[0], 25, item[3], true))
		box.add_child(_wrap_label(item[1], 17))
		var mode_key: String = item[4]
		box.add_child(_button("Let's go", func() -> void: _start_mode(mode_key), Color("403159"), item[2], 49))

func _start_mode(key: String) -> void:
	match key:
		"campaign": _continue_campaign()
		"daily": _start_level(Catalog.daily_level(), "daily")
		"freeplay": _start_level(Catalog.freeplay_level(), "freeplay")
		_:
			var candidates: Array = Catalog.all_levels().filter(func(entry: Dictionary) -> bool: return entry.mode == key)
			if not candidates.is_empty():
				_start_level(candidates[randi() % candidates.size()], "freeplay")

func _show_studio() -> void:
	if busy: return
	if screen == "game": _save_run()
	var column := _clear_page("studio")
	_topbar(column)
	column.add_child(_label("A splash of you.", 42 if not _mobile() else 32, INK, true))
	column.add_child(_wrap_label("Spend earned sparkles on a world that feels like yours.", 18))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var items := VBoxContainer.new()
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items.add_theme_constant_override("separation", 16)
	scroll.add_child(items)
	for category: Array in [["theme", "Your happy place", ["Candy cosmos", "Peach daydream", "Bubble lagoon"]], ["bottle", "A little glass magic", ["Classic curves", "Pocket vials", "Potion party"]], ["palette", "Pick your colors", ["Candy pop", "Soft sorbet", "Electric joy"]]]:
		items.add_child(_label(category[1], 23, INK, true))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		items.add_child(row)
		for i in 3:
			var card := VBoxContainer.new()
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(card)
			var preview := Control.new()
			preview.custom_minimum_size.y = 95
			preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(preview)
			_preview_item.call_deferred(preview, category[0], i)
			var key: String = category[0]
			var price := 0 if i == 0 else (90 if i == 1 else 180)
			var owned: bool = i in save.data["owned_" + key + "s"]
			var active: bool = int(save.data[key]) == i
			var label: String = category[2][i] + "\n" + ("Selected" if active else ("Use this" if owned else "%d sparkles" % price))
			var button := _button(label, func() -> void:
				if save.buy(key, i, price):
					_apply_preferences()
					_show_studio()
				else:
					var body := _dialog("A little more sparkle", "Complete new levels to earn 15 sparkles. Every tenth level earns 35, and the daily puzzle earns 30.")
					body.add_child(_button("Got it", _close_overlay, Color("c94f96"))), Color("39525b") if active else PANEL, "", 65)
			button.add_theme_font_size_override("font_size", 13 if _mobile() else 17)
			card.add_child(button)

func _preview_item(preview: Control, category: String, item: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(preview): return
	if category == "theme":
		var art := Backdrop.new()
		art.theme_id = item
		art.reduced_motion = true
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.clip_contents = true
		preview.add_child(art)
	elif category == "bottle":
		var bottle := Bottle.new()
		bottle.size = Vector2(43, 95)
		bottle.position.x = (preview.size.x - 43) / 2.0
		bottle.layers = [0, 2, 1, 3]
		bottle.palette = PALETTES[int(save.data.palette)]
		bottle.capacity = 4
		bottle.style_id = item
		bottle.reduced_motion = true
		bottle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.add_child(bottle)
	else:
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.add_theme_constant_override("separation", 5)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		preview.add_child(row)
		for color: Color in PALETTES[item].slice(0, 5):
			var swatch := Panel.new()
			swatch.custom_minimum_size = Vector2(12 if _mobile() else 25, 70)
			swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			swatch.add_theme_stylebox_override("panel", _style(color, 10))
			row.add_child(swatch)
