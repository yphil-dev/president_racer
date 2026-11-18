extends Control

const ARROW_KEYS_ICON: Texture2D = preload("res://sprites/arrow-keys.svg")
const WASD_KEYS_ICON: Texture2D = preload("res://sprites/wasd-keys.svg")
const GAME_CONTROLLER_ICON: Texture2D = preload("res://sprites/game-controller.svg")
const CPU_ICON: Texture2D = preload("res://sprites/cpu.svg")
const FLOPPY_ICON: Texture2D = preload("res://sprites/floppy.svg")
const FLOPPY_SAVING_ICON: Texture2D = preload("res://sprites/floppy-saving.svg")
const ERROR_SOUND: AudioStream = preload("res://audio/impact.ogg")
const SELECTED_COLOR := Color(1.0, 0.84, 0.28, 1.0)
const NORMAL_BORDER_COLOR := Color(0.30, 0.36, 0.46, 0.95)
const OFF_MODULATE := Color(0.42, 0.42, 0.42, 0.72)
const AVAILABLE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const UNAVAILABLE_COLOR := Color(0.95, 0.25, 0.25, 1.0)
const SLOT_DEFAULT_INPUTS: Array[int] = [
	RaceSelection.InputSource.ARROWS,
	RaceSelection.InputSource.WASD,
	RaceSelection.InputSource.PAD_1,
	RaceSelection.InputSource.PAD_2,
]

@onready var pilot_grid: GridContainer = $Content/PilotGrid
@onready var player_bar: HBoxContainer = $Content/PlayerBar
@onready var content: VBoxContainer = $Content
@onready var day_button: Button = $Content/SettingsBar/Time/Day
@onready var night_button: Button = $Content/SettingsBar/Time/Night
@onready var fair_button: Button = $Content/SettingsBar/Weather/Fair
@onready var rain_button: Button = $Content/SettingsBar/Weather/Rain
@onready var snow_button: Button = $Content/SettingsBar/Weather/Snow
@onready var one_lap_button: Button = $Content/SettingsBar/Laps/One
@onready var two_lap_button: Button = $Content/SettingsBar/Laps/Two
@onready var three_lap_button: Button = $Content/SettingsBar/Laps/Three
@onready var random_button: Button = $Content/SettingsBar/Random
@onready var save_button: Button = $Content/SettingsBar/Save
@onready var race_button: Button = $Content/SettingsBar/Race

var _pilot_buttons: Array[Button] = []
var _pilot_buttons_by_id: Dictionary = {}
var _slot_panels: Array[PanelContainer] = []
var _slot_badges: Array[Button] = []
var _slot_pilot_buttons: Array[Button] = []
var _slot_toggle_buttons: Array[Button] = []
var _slot_input_buttons: Array[Button] = []
var _settings_buttons: Array[Button] = []
var _returning: bool = false
var _save_feedback_tween: Tween
var _error_player: AudioStreamPlayer

func _ready() -> void:
	_create_pilot_cards()
	_create_player_slots()
	_connect_global_settings()
	_configure_focus_navigation()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_error_player = AudioStreamPlayer.new()
	_error_player.stream = ERROR_SOUND
	_error_player.volume_db = -16.0
	_error_player.pitch_scale = 1.45
	add_child(_error_player)
	_refresh_all()
	content.modulate.a = 0.0
	create_tween().tween_property(content, "modulate:a", 1.0, 0.22)
	_grab_initial_focus.call_deferred()

func _unhandled_input(event: InputEvent) -> void:
	if _returning or SceneTransition.is_active():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_return_to_menu()
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.physical_keycode in [
			KEY_W,
			KEY_A,
			KEY_S,
			KEY_D,
			KEY_Z,
			KEY_Q,
		]:
			_try_auto_join(RaceSelection.InputSource.WASD)
	elif event is InputEventJoypadButton:
		var joy_event := event as InputEventJoypadButton
		if joy_event.pressed:
			var connected_pads: Array[int] = Input.get_connected_joypads()
			var pad_index: int = connected_pads.find(joy_event.device)
			if pad_index >= 0 and pad_index < 4:
				_try_auto_join(RaceSelection.InputSource.PAD_1 + pad_index)

func _create_pilot_cards() -> void:
	for driver_id in DriverRoster.DRIVER_IDS:
		var profile: Dictionary = DriverRoster.get_profile(driver_id)
		var button := Button.new()
		button.name = driver_id.to_pascal_case()
		button.custom_minimum_size = Vector2(0.0, 142.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.clip_contents = true
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.tooltip_text = "%s — Enter/Space/A: assign, X/Y/right-click: mode" % profile["display_name"]
		pilot_grid.add_child(button)

		var portrait := TextureRect.new()
		portrait.name = "Portrait"
		portrait.texture = profile["portrait"]
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(portrait)
		portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var shade := ColorRect.new()
		shade.name = "Shade"
		shade.color = Color(0.0, 0.0, 0.0, 0.22)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(shade)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var accent := ColorRect.new()
		accent.name = "Accent"
		accent.color = profile["car_color"]
		accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(accent)
		accent.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		accent.offset_right = 8.0

		var name_label := Label.new()
		name_label.name = "Name"
		name_label.text = profile["display_name"]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 24)
		name_label.add_theme_color_override("font_color", Color.WHITE)
		name_label.add_theme_color_override("font_outline_color", Color.BLACK)
		name_label.add_theme_constant_override("outline_size", 6)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(name_label)
		name_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		name_label.offset_top = -38.0

		var status_panel := PanelContainer.new()
		status_panel.name = "Status"
		status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_panel.add_theme_stylebox_override(
			"panel",
			_make_style(Color(0.02, 0.03, 0.05, 0.92), Color.TRANSPARENT, 0)
		)
		button.add_child(status_panel)
		status_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		status_panel.position = Vector2(-68.0, 6.0)
		status_panel.size = Vector2(62.0, 28.0)

		var status_label := Label.new()
		status_label.name = "Label"
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status_label.add_theme_font_size_override("font_size", 16)
		status_label.add_theme_color_override("font_color", SELECTED_COLOR)
		status_label.add_theme_color_override("font_outline_color", Color.BLACK)
		status_label.add_theme_constant_override("outline_size", 3)
		status_panel.add_child(status_label)

		var status_icon := TextureRect.new()
		status_icon.name = "Icon"
		status_icon.texture = CPU_ICON
		status_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		status_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		status_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_icon.hide()
		status_panel.add_child(status_icon)

		button.pressed.connect(_on_pilot_pressed.bind(driver_id))
		button.gui_input.connect(_on_pilot_gui_input.bind(driver_id, button))
		_pilot_buttons.append(button)
		_pilot_buttons_by_id[driver_id] = button

func _create_player_slots() -> void:
	for slot_index in RaceSelection.LOCAL_PLAYER_SLOT_COUNT:
		var panel := PanelContainer.new()
		panel.name = "PlayerSlot%d" % (slot_index + 1)
		panel.custom_minimum_size = Vector2(0.0, 86.0)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		player_bar.add_child(panel)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 5)
		margin.add_theme_constant_override("margin_top", 5)
		margin.add_theme_constant_override("margin_right", 5)
		margin.add_theme_constant_override("margin_bottom", 5)
		panel.add_child(margin)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		margin.add_child(row)

		var badge := Button.new()
		badge.name = "Badge"
		badge.custom_minimum_size = Vector2(34.0, 0.0)
		badge.text = "P%d" % (slot_index + 1)
		badge.focus_mode = Control.FOCUS_ALL
		badge.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		badge.tooltip_text = "Select player slot P%d" % (slot_index + 1)
		badge.pressed.connect(_on_slot_selected.bind(slot_index))
		row.add_child(badge)

		var pilot_button := Button.new()
		pilot_button.name = "Pilot"
		pilot_button.custom_minimum_size = Vector2(46.0, 0.0)
		pilot_button.focus_mode = Control.FOCUS_ALL
		pilot_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		pilot_button.expand_icon = true
		pilot_button.tooltip_text = "Select player slot P%d" % (slot_index + 1)
		pilot_button.pressed.connect(_on_slot_selected.bind(slot_index))
		row.add_child(pilot_button)

		var toggle_button := Button.new()
		toggle_button.name = "Toggle"
		toggle_button.custom_minimum_size = Vector2(42.0, 0.0)
		toggle_button.focus_mode = Control.FOCUS_ALL
		toggle_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		toggle_button.expand_icon = true
		toggle_button.icon = CPU_ICON
		toggle_button.pressed.connect(_on_slot_pilot_toggled.bind(slot_index))
		row.add_child(toggle_button)

		var input_button := Button.new()
		input_button.name = "Input"
		input_button.custom_minimum_size = Vector2(76.0, 0.0)
		input_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input_button.focus_mode = Control.FOCUS_ALL
		input_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		input_button.expand_icon = true
		input_button.pressed.connect(_on_slot_input_pressed.bind(slot_index))
		row.add_child(input_button)

		_slot_panels.append(panel)
		_slot_badges.append(badge)
		_slot_pilot_buttons.append(pilot_button)
		_slot_toggle_buttons.append(toggle_button)
		_slot_input_buttons.append(input_button)

func _connect_global_settings() -> void:
	day_button.tooltip_text = "Daytime"
	night_button.tooltip_text = "Nighttime"
	fair_button.tooltip_text = "Fair weather"
	rain_button.tooltip_text = "Rain"
	snow_button.tooltip_text = "Snow"
	one_lap_button.tooltip_text = "One lap"
	two_lap_button.tooltip_text = "Two laps"
	three_lap_button.tooltip_text = "Three laps"
	random_button.tooltip_text = "Random race options"
	save_button.tooltip_text = "Save options"
	race_button.tooltip_text = "Return to track selection"

	day_button.pressed.connect(_select_time.bind(false))
	night_button.pressed.connect(_select_time.bind(true))
	fair_button.pressed.connect(_select_weather.bind(RaceSelection.WEATHER_FAIR))
	rain_button.pressed.connect(_select_weather.bind(RaceSelection.WEATHER_RAIN))
	snow_button.pressed.connect(_select_weather.bind(RaceSelection.WEATHER_SNOW))
	one_lap_button.pressed.connect(_select_laps.bind(1))
	two_lap_button.pressed.connect(_select_laps.bind(2))
	three_lap_button.pressed.connect(_select_laps.bind(3))
	random_button.pressed.connect(_select_random)
	save_button.pressed.connect(_save_options)
	race_button.pressed.connect(_return_to_menu)

	_settings_buttons = [
		day_button,
		night_button,
		fair_button,
		rain_button,
		snow_button,
		one_lap_button,
		two_lap_button,
		three_lap_button,
		random_button,
		save_button,
		race_button,
	]

func _on_pilot_pressed(driver_id: String) -> void:
	RaceSelection.assign_pilot_to_slot(driver_id, RaceSelection.selected_local_slot)
	_mark_changed()

func _on_pilot_gui_input(event: InputEvent, driver_id: String, button: Button) -> void:
	var secondary_action: bool = false
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		secondary_action = mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		secondary_action = (
			key_event.pressed
			and not key_event.echo
			and key_event.physical_keycode == KEY_X
		)
	elif event is InputEventJoypadButton:
		var joy_event := event as InputEventJoypadButton
		secondary_action = joy_event.pressed and joy_event.button_index == JOY_BUTTON_Y
	if not secondary_action:
		return
	button.accept_event()
	_secondary_pilot_action(driver_id)

func _secondary_pilot_action(driver_id: String) -> void:
	var changed: bool
	if RaceSelection.is_driver_human(driver_id):
		changed = RaceSelection.release_human_pilot(driver_id)
	else:
		changed = RaceSelection.toggle_cpu_off(driver_id)
	if not changed:
		_play_error()
		return
	_mark_changed()

func _on_slot_selected(slot_index: int) -> void:
	RaceSelection.selected_local_slot = slot_index
	_refresh_all()

func _on_slot_pilot_toggled(slot_index: int) -> void:
	RaceSelection.selected_local_slot = slot_index
	var changed: bool
	if RaceSelection.is_player_slot_active(slot_index):
		changed = RaceSelection.deactivate_local_slot(slot_index)
	else:
		changed = RaceSelection.activate_local_slot(slot_index)
		if changed:
			RaceSelection.set_input_source(slot_index, SLOT_DEFAULT_INPUTS[slot_index])
	if not changed:
		_play_error()
		return
	_mark_changed()
	_slot_toggle_buttons[slot_index].grab_focus()

func _on_slot_input_pressed(slot_index: int) -> void:
	RaceSelection.selected_local_slot = slot_index
	RaceSelection.cycle_local_input_source(slot_index)
	_mark_changed()

func _try_auto_join(input_source: int) -> void:
	if _is_input_claimed(input_source):
		return
	for slot_index in range(1, RaceSelection.LOCAL_PLAYER_SLOT_COUNT):
		if RaceSelection.is_player_slot_active(slot_index):
			continue
		if not RaceSelection.activate_local_slot(slot_index):
			return
		RaceSelection.set_input_source(slot_index, input_source)
		RaceSelection.selected_local_slot = slot_index
		get_viewport().set_input_as_handled()
		_mark_changed()
		return

func _is_input_claimed(input_source: int) -> bool:
	for slot_index in RaceSelection.LOCAL_PLAYER_SLOT_COUNT:
		if (
			RaceSelection.is_player_slot_active(slot_index)
			and RaceSelection.get_input_source(slot_index) == input_source
		):
			return true
	return false

func _select_time(night: bool) -> void:
	RaceSelection.night_enabled = night
	_mark_changed()

func _select_weather(weather: String) -> void:
	RaceSelection.selected_weather = weather
	_mark_changed()

func _select_laps(laps: int) -> void:
	RaceSelection.selected_laps = laps
	_mark_changed()

func _select_random() -> void:
	if not RaceSelection.set_random_mode():
		_play_error()
	_refresh_all()
	_show_save_feedback()

func _save_options() -> void:
	if not RaceSelection.save_options():
		_play_error()
	_show_save_feedback()

func _mark_changed() -> void:
	if not RaceSelection.mark_options_changed():
		_play_error()
	_refresh_all()
	_show_save_feedback()

func _refresh_all() -> void:
	_refresh_pilot_cards()
	_refresh_player_slots()
	_refresh_global_settings()

func _refresh_pilot_cards() -> void:
	for driver_id in DriverRoster.DRIVER_IDS:
		var button := _pilot_buttons_by_id[driver_id] as Button
		var profile: Dictionary = DriverRoster.get_profile(driver_id)
		var mode: int = RaceSelection.get_pilot_mode(driver_id)
		var status_label := button.get_node("Status/Label") as Label
		var status_icon := button.get_node("Status/Icon") as TextureRect
		var shade := button.get_node("Shade") as ColorRect
		var border_color: Color = NORMAL_BORDER_COLOR
		if mode == RaceSelection.PilotMode.HUMAN:
			var slot_index: int = RaceSelection.get_player_slot_for_driver(driver_id)
			status_label.text = "P%d" % (slot_index + 1)
			status_label.show()
			status_icon.hide()
			status_label.modulate = SELECTED_COLOR
			shade.color = Color(0.0, 0.0, 0.0, 0.08)
			button.modulate = Color.WHITE
			border_color = profile["car_color"]
		elif mode == RaceSelection.PilotMode.CPU:
			status_label.hide()
			status_icon.show()
			status_icon.modulate = Color.WHITE
			shade.color = Color(0.0, 0.0, 0.0, 0.24)
			button.modulate = Color.WHITE
		else:
			status_label.hide()
			status_icon.show()
			status_icon.modulate = Color(0.45, 0.45, 0.45, 0.8)
			shade.color = Color(0.0, 0.0, 0.0, 0.62)
			button.modulate = OFF_MODULATE
		if (
			mode == RaceSelection.PilotMode.HUMAN
			and RaceSelection.get_player_slot_for_driver(driver_id) == RaceSelection.selected_local_slot
		):
			border_color = SELECTED_COLOR
		_apply_card_styles(button, border_color)

func _refresh_player_slots() -> void:
	for slot_index in RaceSelection.LOCAL_PLAYER_SLOT_COUNT:
		var active: bool = RaceSelection.is_player_slot_active(slot_index)
		var driver_id: String = RaceSelection.get_driver_for_player_slot(slot_index)
		var pilot_button: Button = _slot_pilot_buttons[slot_index]
		var toggle_button: Button = _slot_toggle_buttons[slot_index]
		var input_button: Button = _slot_input_buttons[slot_index]
		if active and DriverRoster.has_driver(driver_id):
			var profile: Dictionary = DriverRoster.get_profile(driver_id)
			pilot_button.icon = profile["portrait"]
			pilot_button.text = ""
			pilot_button.tooltip_text = "%s — select P%d" % [
				profile["display_name"],
				slot_index + 1,
			]
		else:
			pilot_button.icon = null
			pilot_button.text = ""
			pilot_button.tooltip_text = "Select P%d" % (slot_index + 1)

		toggle_button.text = ""
		toggle_button.icon = GAME_CONTROLLER_ICON if active else CPU_ICON
		toggle_button.tooltip_text = "%s P%d" % [
			"Turn OFF" if active else "Turn ON",
			slot_index + 1,
		]
		toggle_button.modulate = SELECTED_COLOR if active else Color.WHITE

		var source: int = RaceSelection.get_input_source(slot_index)
		var pad_number: int = RaceSelection.get_gamepad_number(source)
		input_button.text = str(pad_number) if pad_number > 0 else ""
		input_button.icon = _input_source_icon(source)
		input_button.tooltip_text = "Cycle P%d input: %s" % [
			slot_index + 1,
			RaceSelection.get_input_source_label(source),
		]
		input_button.modulate = (
			AVAILABLE_COLOR if _input_source_available(source) else UNAVAILABLE_COLOR
		)
		var selected: bool = slot_index == RaceSelection.selected_local_slot
		_slot_panels[slot_index].add_theme_stylebox_override(
			"panel",
			_make_style(
				Color(0.035, 0.05, 0.075, 0.92),
				SELECTED_COLOR if selected else NORMAL_BORDER_COLOR,
				3 if selected else 2
			)
		)
		_slot_badges[slot_index].modulate = SELECTED_COLOR if selected else Color.WHITE

func _refresh_global_settings() -> void:
	_style_setting_button(day_button, not RaceSelection.night_enabled)
	_style_setting_button(night_button, RaceSelection.night_enabled)
	_style_setting_button(fair_button, RaceSelection.selected_weather == RaceSelection.WEATHER_FAIR)
	_style_setting_button(rain_button, RaceSelection.selected_weather == RaceSelection.WEATHER_RAIN)
	_style_setting_button(snow_button, RaceSelection.selected_weather == RaceSelection.WEATHER_SNOW)
	_style_setting_button(one_lap_button, RaceSelection.selected_laps == 1)
	_style_setting_button(two_lap_button, RaceSelection.selected_laps == 2)
	_style_setting_button(three_lap_button, RaceSelection.selected_laps == 3)
	_style_setting_button(random_button, RaceSelection.random_mode)

func _style_setting_button(button: Button, selected: bool) -> void:
	button.modulate = SELECTED_COLOR if selected else Color.WHITE

func _input_source_icon(input_source: int) -> Texture2D:
	if input_source >= RaceSelection.InputSource.PAD_1 and input_source <= RaceSelection.InputSource.PAD_4:
		return GAME_CONTROLLER_ICON
	match input_source:
		RaceSelection.InputSource.ARROWS:
			return ARROW_KEYS_ICON
		RaceSelection.InputSource.WASD:
			return WASD_KEYS_ICON
	return null

func _input_source_available(input_source: int) -> bool:
	var pad_number: int = RaceSelection.get_gamepad_number(input_source)
	return pad_number == 0 or Input.get_connected_joypads().size() >= pad_number

func _apply_card_styles(button: Button, border_color: Color) -> void:
	button.add_theme_stylebox_override(
		"normal",
		_make_style(Color(0.035, 0.05, 0.075, 0.94), border_color, 2)
	)
	button.add_theme_stylebox_override(
		"hover",
		_make_style(Color(0.06, 0.075, 0.11, 0.96), SELECTED_COLOR, 3)
	)
	button.add_theme_stylebox_override(
		"focus",
		_make_style(Color(0.06, 0.075, 0.11, 0.96), SELECTED_COLOR, 4)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_make_style(Color(0.08, 0.095, 0.13, 0.98), SELECTED_COLOR, 4)
	)

func _make_style(background: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(7)
	return style

func _configure_focus_navigation() -> void:
	for index in _pilot_buttons.size():
		var column: int = index % 3
		var row: int = int(index / 3)
		var left_index: int = row * 3 + posmod(column - 1, 3)
		var right_index: int = row * 3 + posmod(column + 1, 3)
		var vertical_index: int = posmod(row + 1, 2) * 3 + column
		_set_focus_neighbor(_pilot_buttons[index], "left", _pilot_buttons[left_index])
		_set_focus_neighbor(_pilot_buttons[index], "right", _pilot_buttons[right_index])
		if row == 0:
			_set_focus_neighbor(_pilot_buttons[index], "top", _settings_buttons[column * 3])
			_set_focus_neighbor(_pilot_buttons[index], "bottom", _pilot_buttons[vertical_index])
		else:
			_set_focus_neighbor(_pilot_buttons[index], "top", _pilot_buttons[vertical_index])
			_set_focus_neighbor(_pilot_buttons[index], "bottom", _slot_badges[mini(column, 3)])

	var slot_controls: Array[Button] = []
	for slot_index in RaceSelection.LOCAL_PLAYER_SLOT_COUNT:
		slot_controls.append(_slot_badges[slot_index])
		slot_controls.append(_slot_pilot_buttons[slot_index])
		slot_controls.append(_slot_toggle_buttons[slot_index])
		slot_controls.append(_slot_input_buttons[slot_index])
	for index in slot_controls.size():
		var slot_index: int = int(index / 4)
		var pilot_column: int = mini(slot_index, 2)
		_set_focus_neighbor(slot_controls[index], "left", slot_controls[posmod(index - 1, slot_controls.size())])
		_set_focus_neighbor(slot_controls[index], "right", slot_controls[posmod(index + 1, slot_controls.size())])
		_set_focus_neighbor(slot_controls[index], "top", _pilot_buttons[3 + pilot_column])
		_set_focus_neighbor(
			slot_controls[index],
			"bottom",
			_settings_buttons[mini(slot_index * 3, _settings_buttons.size() - 1)]
		)

	for index in _settings_buttons.size():
		var slot_index: int = mini(int(float(index) / float(_settings_buttons.size()) * 4.0), 3)
		var pilot_column: int = mini(int(float(index) / float(_settings_buttons.size()) * 3.0), 2)
		_set_focus_neighbor(
			_settings_buttons[index],
			"left",
			_settings_buttons[posmod(index - 1, _settings_buttons.size())]
		)
		_set_focus_neighbor(
			_settings_buttons[index],
			"right",
			_settings_buttons[posmod(index + 1, _settings_buttons.size())]
		)
		_set_focus_neighbor(_settings_buttons[index], "top", _slot_badges[slot_index])
		_set_focus_neighbor(_settings_buttons[index], "bottom", _pilot_buttons[pilot_column])

func _set_focus_neighbor(source: Control, direction: String, target: Control) -> void:
	var path: NodePath = source.get_path_to(target)
	match direction:
		"left":
			source.focus_neighbor_left = path
		"right":
			source.focus_neighbor_right = path
		"top":
			source.focus_neighbor_top = path
		"bottom":
			source.focus_neighbor_bottom = path

func _grab_initial_focus() -> void:
	var driver_id: String = RaceSelection.get_driver_for_player_slot(
		RaceSelection.selected_local_slot
	)
	if driver_id.is_empty():
		driver_id = RaceSelection.selected_driver_id
	var button := _pilot_buttons_by_id.get(driver_id) as Button
	if button == null:
		button = _pilot_buttons[0]
	button.grab_focus()

func _show_save_feedback() -> void:
	save_button.icon = FLOPPY_SAVING_ICON
	if _save_feedback_tween != null and _save_feedback_tween.is_valid():
		_save_feedback_tween.kill()
	_save_feedback_tween = create_tween()
	_save_feedback_tween.tween_interval(0.35)
	_save_feedback_tween.tween_callback(func() -> void: save_button.icon = FLOPPY_ICON)

func _play_error() -> void:
	_error_player.stop()
	_error_player.play()
	var tween := create_tween()
	tween.tween_property(content, "modulate", Color(1.0, 0.65, 0.65, 1.0), 0.05)
	tween.tween_property(content, "modulate", Color.WHITE, 0.12)

func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh_player_slots()

func _return_to_menu() -> void:
	if _returning or SceneTransition.is_active():
		return
	_returning = true
	RaceSelection.save_options()
	AudioPlayer.fade_out_and_stop(0.45)
	SceneTransition.transition_to_menu()
