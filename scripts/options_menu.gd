extends Control

const ARROW_KEYS_ICON: Texture2D = preload("res://sprites/arrow-keys.svg")
const WASD_KEYS_ICON: Texture2D = preload("res://sprites/wasd-keys.svg")
const GAME_CONTROLLER_ICON: Texture2D = preload("res://sprites/game-controller.svg")
const CPU_ICON: Texture2D = preload("res://sprites/cpu.svg")
const FLOPPY_ICON: Texture2D = preload("res://sprites/floppy.svg")
const FLOPPY_SAVING_ICON: Texture2D = preload("res://sprites/floppy-saving.svg")
const SELECTED_COLOR := Color(1.0, 0.84, 0.28, 1.0)
const NORMAL_BORDER_COLOR := Color(0.30, 0.36, 0.46, 0.95)
const OFF_MODULATE := Color(0.42, 0.42, 0.42, 0.72)
const AVAILABLE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const UNAVAILABLE_COLOR := Color(0.95, 0.25, 0.25, 1.0)

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
@onready var _pilot_buttons: Array[Button] = [
	$Content/PilotGrid/Soral,
	$Content/PilotGrid/LePen,
	$Content/PilotGrid/Melenchon,
	$Content/PilotGrid/Macron,
	$Content/PilotGrid/Riner,
	$Content/PilotGrid/Rima,
]
@onready var _slot_buttons: Array[Button] = [
	$Content/PlayerBar/PlayerSlot1,
	$Content/PlayerBar/PlayerSlot2,
	$Content/PlayerBar/PlayerSlot3,
	$Content/PlayerBar/PlayerSlot4,
]
@onready var _slot_portraits: Array[TextureRect] = [
	$Content/PlayerBar/PlayerSlot1/Row/Portrait,
	$Content/PlayerBar/PlayerSlot2/Row/Portrait,
	$Content/PlayerBar/PlayerSlot3/Row/Portrait,
	$Content/PlayerBar/PlayerSlot4/Row/Portrait,
]
@onready var _slot_scheme_icons: Array[TextureRect] = [
	$Content/PlayerBar/PlayerSlot1/Row/Scheme/Icon,
	$Content/PlayerBar/PlayerSlot2/Row/Scheme/Icon,
	$Content/PlayerBar/PlayerSlot3/Row/Scheme/Icon,
	$Content/PlayerBar/PlayerSlot4/Row/Scheme/Icon,
]
@onready var _slot_scheme_numbers: Array[Label] = [
	$Content/PlayerBar/PlayerSlot1/Row/Scheme/Number,
	$Content/PlayerBar/PlayerSlot2/Row/Scheme/Number,
	$Content/PlayerBar/PlayerSlot3/Row/Scheme/Number,
	$Content/PlayerBar/PlayerSlot4/Row/Scheme/Number,
]
@onready var _error_player: AudioStreamPlayer = $ErrorPlayer

var _pilot_buttons_by_id: Dictionary = {}
var _slot_preview_driver_ids: Array[String] = ["", "", "", ""]
var _returning: bool = false
var _save_feedback_tween: Tween

func _ready() -> void:
	_bind_pilot_cards()
	_bind_player_slots()
	_connect_global_settings()
	if RaceSelection.random_mode:
		RaceSelection.prepare_next_race()
	_rebuild_slot_previews(true)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
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

func _bind_pilot_cards() -> void:
	for index in DriverRoster.DRIVER_IDS.size():
		var driver_id: String = DriverRoster.DRIVER_IDS[index]
		var profile: Dictionary = DriverRoster.get_profile(driver_id)
		var button: Button = _pilot_buttons[index]
		(button.get_node("Portrait") as TextureRect).texture = profile["portrait"]
		(button.get_node("Accent") as ColorRect).color = profile["car_color"]
		(button.get_node("Name") as Label).text = profile["display_name"]
		button.tooltip_text = "%s — Enter/Space/A: assign, X/Y/right-click: mode" % profile["display_name"]
		button.pressed.connect(_on_pilot_pressed.bind(driver_id))
		button.gui_input.connect(_on_pilot_gui_input.bind(driver_id, button))
		_pilot_buttons_by_id[driver_id] = button

func _bind_player_slots() -> void:
	for slot_index in RaceSelection.LOCAL_PLAYER_SLOT_COUNT:
		var slot_button: Button = _slot_buttons[slot_index]
		slot_button.tooltip_text = "Cycle control for this driver"
		slot_button.pressed.connect(_on_slot_pressed.bind(slot_index))

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

func _on_pilot_pressed(driver_id: String) -> void:
	var target_slot: int = RaceSelection.selected_local_slot
	if not RaceSelection.is_player_slot_active(target_slot):
		var source_slot: int = RaceSelection.get_player_slot_for_driver(driver_id)
		var desired_source: int = RaceSelection.InputSource.REMOTE_PEER
		if source_slot >= 0:
			desired_source = RaceSelection.get_input_source(source_slot)
		else:
			var available_sources: Array[int] = _available_input_sources(target_slot)
			if available_sources.is_empty():
				_play_error()
				return
			desired_source = available_sources[0]
		if not RaceSelection.assign_pilot_to_slot(driver_id, target_slot):
			_play_error()
			return
		RaceSelection.set_input_source(target_slot, desired_source)
	else:
		RaceSelection.assign_pilot_to_slot(driver_id, target_slot)
	_rebuild_slot_previews(false)
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
	var released_slot: int = RaceSelection.get_player_slot_for_driver(driver_id)
	if RaceSelection.is_driver_human(driver_id):
		changed = RaceSelection.release_human_pilot(driver_id)
		if changed and released_slot >= 0 and released_slot < RaceSelection.LOCAL_PLAYER_SLOT_COUNT:
			_slot_preview_driver_ids[released_slot] = driver_id
	else:
		changed = RaceSelection.toggle_cpu_off(driver_id)
	if not changed:
		_play_error()
		return
	_rebuild_slot_previews(false)
	_mark_changed()

func _on_slot_pressed(slot_index: int) -> void:
	RaceSelection.selected_local_slot = slot_index
	var available_sources: Array[int] = _available_input_sources(slot_index)
	if not RaceSelection.is_player_slot_active(slot_index):
		if available_sources.is_empty() or not _activate_slot_with_preview(slot_index):
			_play_error()
			_refresh_all()
			return
		RaceSelection.set_input_source(slot_index, available_sources[0])
	else:
		var current_source: int = RaceSelection.get_input_source(slot_index)
		var current_index: int = available_sources.find(current_source)
		if current_index >= 0 and current_index + 1 < available_sources.size():
			RaceSelection.set_input_source(slot_index, available_sources[current_index + 1])
		elif current_index < 0 and not available_sources.is_empty():
			RaceSelection.set_input_source(slot_index, available_sources[0])
		else:
			var driver_id: String = RaceSelection.get_driver_for_player_slot(slot_index)
			if not RaceSelection.deactivate_local_slot(slot_index):
				_play_error()
				return
			_slot_preview_driver_ids[slot_index] = driver_id
	_rebuild_slot_previews(false)
	_mark_changed()
	_slot_buttons[slot_index].grab_focus()

func _activate_slot_with_preview(slot_index: int) -> bool:
	var preview_driver_id: String = _slot_preview_driver_ids[slot_index]
	if (
		DriverRoster.has_driver(preview_driver_id)
		and not RaceSelection.is_driver_human(preview_driver_id)
	):
		return RaceSelection.assign_pilot_to_slot(preview_driver_id, slot_index)
	return RaceSelection.activate_local_slot(slot_index)

func _available_input_sources(slot_index: int) -> Array[int]:
	var candidates: Array[int] = [
		RaceSelection.InputSource.ARROWS,
		RaceSelection.InputSource.WASD,
	]
	var connected_pad_count: int = mini(Input.get_connected_joypads().size(), 4)
	for pad_index in connected_pad_count:
		candidates.append(RaceSelection.InputSource.PAD_1 + pad_index)

	var result: Array[int] = []
	for candidate in candidates:
		if not _is_input_claimed(candidate, slot_index):
			result.append(candidate)
	return result

func _rebuild_slot_previews(randomize: bool) -> void:
	var used_driver_ids: Array[String] = []
	for slot_index in RaceSelection.LOCAL_PLAYER_SLOT_COUNT:
		if not RaceSelection.is_player_slot_active(slot_index):
			continue
		var driver_id: String = RaceSelection.get_driver_for_player_slot(slot_index)
		_slot_preview_driver_ids[slot_index] = driver_id
		used_driver_ids.append(driver_id)

	var candidates: Array[String] = []
	for driver_id in DriverRoster.DRIVER_IDS:
		if not RaceSelection.is_driver_human(driver_id):
			candidates.append(driver_id)
	if randomize:
		candidates.shuffle()

	for slot_index in RaceSelection.LOCAL_PLAYER_SLOT_COUNT:
		if RaceSelection.is_player_slot_active(slot_index):
			continue
		var preview_driver_id: String = _slot_preview_driver_ids[slot_index]
		if (
			not randomize
			and DriverRoster.has_driver(preview_driver_id)
			and not RaceSelection.is_driver_human(preview_driver_id)
			and preview_driver_id not in used_driver_ids
		):
			used_driver_ids.append(preview_driver_id)
			continue
		_slot_preview_driver_ids[slot_index] = ""
		for candidate_id in candidates:
			if candidate_id in used_driver_ids:
				continue
			_slot_preview_driver_ids[slot_index] = candidate_id
			used_driver_ids.append(candidate_id)
			break

func _try_auto_join(input_source: int) -> void:
	if _is_input_claimed(input_source):
		return
	for slot_index in range(1, RaceSelection.LOCAL_PLAYER_SLOT_COUNT):
		if RaceSelection.is_player_slot_active(slot_index):
			continue
		if not _activate_slot_with_preview(slot_index):
			return
		RaceSelection.set_input_source(slot_index, input_source)
		RaceSelection.selected_local_slot = slot_index
		get_viewport().set_input_as_handled()
		_rebuild_slot_previews(false)
		_mark_changed()
		return

func _is_input_claimed(input_source: int, ignored_slot: int = -1) -> bool:
	for slot_index in RaceSelection.LOCAL_PLAYER_SLOT_COUNT:
		if slot_index == ignored_slot:
			continue
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
	_rebuild_slot_previews(true)
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
		if not active:
			driver_id = _slot_preview_driver_ids[slot_index]
		var profile: Dictionary = DriverRoster.get_profile(driver_id)
		_slot_portraits[slot_index].texture = profile.get("portrait") as Texture2D

		var scheme_icon: TextureRect = _slot_scheme_icons[slot_index]
		var scheme_number: Label = _slot_scheme_numbers[slot_index]
		if active:
			var source: int = RaceSelection.get_input_source(slot_index)
			var pad_number: int = RaceSelection.get_gamepad_number(source)
			scheme_icon.texture = _input_source_icon(source)
			scheme_icon.modulate = (
				AVAILABLE_COLOR if _input_source_available(source) else UNAVAILABLE_COLOR
			)
			scheme_number.text = str(pad_number) if pad_number > 0 else ""
			_slot_buttons[slot_index].tooltip_text = "%s — %s" % [
				profile.get("display_name", driver_id),
				RaceSelection.get_input_source_label(source),
			]
		else:
			scheme_icon.texture = CPU_ICON
			scheme_icon.modulate = Color.WHITE
			scheme_number.text = ""
			_slot_buttons[slot_index].tooltip_text = "%s — CPU" % profile.get(
				"display_name",
				driver_id
			)

		_apply_slot_styles(_slot_buttons[slot_index])

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

func _apply_slot_styles(button: Button) -> void:
	button.add_theme_stylebox_override(
		"normal",
		_make_style(Color(0.035, 0.05, 0.075, 0.92), NORMAL_BORDER_COLOR, 2)
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

func _grab_initial_focus() -> void:
	_slot_buttons[0].grab_focus()

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
