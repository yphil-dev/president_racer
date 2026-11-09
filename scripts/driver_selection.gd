extends Control

const SELECTED_SCALE := Vector2(1.02, 1.02)
const NORMAL_SCALE := Vector2.ONE
const SELECTED_SHADE := Color(0, 0, 0, 0.04)
const NORMAL_SHADE := Color(0, 0, 0, 0.28)
const SELECTED_LABEL_COLOR := Color(1, 0.88, 0.2, 1)
const NORMAL_LABEL_COLOR := Color.WHITE
const CONTROLLER_AVAILABLE_COLOR := Color(0.3, 1.0, 0.4, 1)
const CONTROLLER_UNAVAILABLE_COLOR := Color(1.0, 0.22, 0.18, 1)
const INTRO_DURATION: float = 0.8
const INTRO_STAGGER: float = 0.14
const RACE_BUTTON_SIZE := Vector2(56, 56)
const RACE_BUTTON_MARGIN := Vector2(32, 28)

const DAY_ICON: Texture2D = preload("res://sprites/day-sun.svg")
const NIGHT_ICON: Texture2D = preload("res://sprites/night-moon.svg")
const ARROW_KEYS_ICON: Texture2D = preload("res://sprites/arrow-keys.svg")
const WASD_KEYS_ICON: Texture2D = preload("res://sprites/wasd-keys.svg")
const GAME_CONTROLLER_ICON: Texture2D = preload("res://sprites/game-controller.svg")
const CPU_ICON: Texture2D = preload("res://sprites/cpu.svg")

const SCHEME_ORDER: Array[String] = [
	RaceSelection.CONTROL_COMBO,
	RaceSelection.CONTROL_GAMEPAD_1,
	RaceSelection.CONTROL_ARROW,
	RaceSelection.CONTROL_WASD,
	RaceSelection.CONTROL_GAMEPAD_2,
	RaceSelection.CONTROL_GAMEPAD_3,
	RaceSelection.CONTROL_GAMEPAD_4,
	RaceSelection.CONTROL_CPU,
]

@onready var driver_grid: GridContainer = $DriverGrid
@onready var driver_badge: Panel = $DriverBadge
@onready var lap_badge: Panel = $LapBadge
@onready var time_badge: Panel = $TimeBadge
@onready var time_badge_icon: TextureRect = $TimeBadge/Icon
@onready var lap_selector: VBoxContainer = $LapSelector
@onready var time_selector: HBoxContainer = $TimeSelector
@onready var race_button: Button = $Race
@onready var race_button_icon: TextureRect = $Race/Icon
@onready var time_buttons: Array[Button] = [$TimeSelector/Day, $TimeSelector/Night]
@onready var lap_buttons: Array[Button] = [
	$LapSelector/Bar/Buttons/One,
	$LapSelector/Bar/Buttons/Two,
	$LapSelector/Bar/Buttons/Three,
]
@onready var driver_buttons: Array[Button] = [
	$DriverGrid/Soral,
	$DriverGrid/LePen,
	$DriverGrid/Glucksman,
	$DriverGrid/Melenchon,
]
@onready var scheme_containers: Array[HBoxContainer] = [
	$DriverGrid/Soral/ControlSchemes,
	$DriverGrid/LePen/ControlSchemes,
	$DriverGrid/Glucksman/ControlSchemes,
	$DriverGrid/Melenchon/ControlSchemes,
]
@onready var portraits: Array[TextureRect] = [
	$DriverGrid/Soral/Portrait,
	$DriverGrid/LePen/Portrait,
	$DriverGrid/Glucksman/Portrait,
	$DriverGrid/Melenchon/Portrait,
]
@onready var shades: Array[ColorRect] = [
	$DriverGrid/Soral/Shade,
	$DriverGrid/LePen/Shade,
	$DriverGrid/Glucksman/Shade,
	$DriverGrid/Melenchon/Shade,
]
@onready var color_accents: Array[ColorRect] = [
	$DriverGrid/Soral/ColorAccent,
	$DriverGrid/LePen/ColorAccent,
	$DriverGrid/Glucksman/ColorAccent,
	$DriverGrid/Melenchon/ColorAccent,
]
@onready var name_labels: Array[Label] = [
	$DriverGrid/Soral/NameLabel,
	$DriverGrid/LePen/NameLabel,
	$DriverGrid/Glucksman/NameLabel,
	$DriverGrid/Melenchon/NameLabel,
]

var _button_tweens: Dictionary = {}
var _scheme_buttons: Dictionary = {}
var _selected_index: int = 0
var _startup_hover_locked: bool = true
var _returning: bool = false
var _race_button_tween: Tween

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _returning and not SceneTransition.is_active():
		get_viewport().set_input_as_handled()
		_return_to_menu()

func _ready() -> void:
	driver_grid.move_child(driver_buttons[3], 2)

	for index in driver_buttons.size():
		var profile := DriverRoster.get_profile(DriverRoster.DRIVER_IDS[index])
		portraits[index].texture = profile["portrait"]
		color_accents[index].color = profile["car_color"]
		name_labels[index].text = profile["display_name"]
		driver_buttons[index].focus_mode = Control.FOCUS_NONE
		driver_buttons[index].mouse_entered.connect(_hover_driver.bind(index))
		driver_buttons[index].resized.connect(_update_button_pivot.bind(index))
		_create_scheme_buttons(index)

	for index in lap_buttons.size():
		lap_buttons[index].pressed.connect(_select_laps.bind(index + 1))
		lap_buttons[index].focus_entered.connect(_focus_lap)
		lap_buttons[index].mouse_entered.connect(_hover_lap.bind(index))

	for index in time_buttons.size():
		time_buttons[index].pressed.connect(_select_time_of_day.bind(index == 1))
		time_buttons[index].focus_entered.connect(_focus_time)
		time_buttons[index].mouse_entered.connect(_hover_time.bind(index))

	race_button.pressed.connect(_return_to_menu)
	race_button.focus_entered.connect(_focus_race_button)
	race_button.mouse_entered.connect(race_button.grab_focus)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	_apply_lap_selection()
	_apply_time_selection()
	_refresh_controller_assignments()
	_refresh_scheme_buttons()

	resized.connect(_layout_cards)
	_initialize.call_deferred()

func _initialize() -> void:
	await get_tree().process_frame
	_layout_cards()

	for index in driver_buttons.size():
		driver_buttons[index].modulate = Color(1, 1, 1, 0)
		_update_button_pivot(index)

	_selected_index = _first_human_driver_index()
	_focus_driver(_selected_index)
	var driver_id := DriverRoster.DRIVER_IDS[_selected_index]
	var selected_scheme := RaceSelection.get_control_scheme(driver_id)
	var selected_button := _get_scheme_button(driver_id, selected_scheme)
	if selected_button != null:
		selected_button.grab_focus()

	_play_intro()
	_unlock_startup_hover.call_deferred()

func _layout_cards() -> void:
	if not is_node_ready():
		return

	var available_size := Vector2(size.x, maxf(size.y - 250.0, 0.0))
	var card_size := QuadrantLayout.get_card_size(available_size) * 1.56
	var grid_size := Vector2(
		card_size.x * 2.0 + QuadrantLayout.HORIZONTAL_GAP,
		card_size.y * 2.0 + QuadrantLayout.VERTICAL_GAP
	)
	var total_height := grid_size.y + 160.0
	driver_grid.position = Vector2(
		(size.x - grid_size.x) * 0.5,
		maxf(16.0, (size.y - total_height) * 0.5 + 10.0)
	)
	driver_badge.position = driver_grid.position + Vector2(grid_size.x + 8.0, 0.0)
	driver_badge.size = Vector2(32.0, 32.0)
	driver_grid.size = grid_size
	driver_grid.custom_minimum_size = grid_size

	for button in driver_buttons:
		button.custom_minimum_size = card_size

	lap_selector.position = Vector2((size.x - 192.0) * 0.5, driver_grid.position.y + grid_size.y + 20.0)
	lap_selector.size = Vector2(192.0, 36.0)
	lap_badge.position = lap_selector.position + Vector2(200.0, 2.0)
	lap_badge.size = Vector2(32.0, 32.0)
	time_selector.position = lap_selector.position + Vector2(0.0, 76.0)
	time_selector.size = Vector2(192.0, 40.0)
	time_badge.position = time_selector.position + Vector2(200.0, 4.0)
	time_badge.size = Vector2(32.0, 32.0)
	race_button.position = size - RACE_BUTTON_SIZE - RACE_BUTTON_MARGIN
	race_button.size = RACE_BUTTON_SIZE
	race_button.pivot_offset = RACE_BUTTON_SIZE * 0.5

func _create_scheme_buttons(driver_index: int) -> void:
	var driver_id := DriverRoster.DRIVER_IDS[driver_index]
	var buttons_for_driver: Dictionary = {}
	var container := scheme_containers[driver_index]

	for scheme in SCHEME_ORDER:
		var button := Button.new()
		button.name = scheme.to_pascal_case()
		button.custom_minimum_size = Vector2(0.0, 56.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_stretch_ratio = 1.7 if scheme == RaceSelection.CONTROL_COMBO else 1.0
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(_select_control_scheme.bind(driver_id, scheme))
		button.focus_entered.connect(_focus_driver.bind(driver_index))
		button.mouse_entered.connect(_hover_scheme_button.bind(button))
		container.add_child(button)
		_add_scheme_visual(button, scheme)
		buttons_for_driver[scheme] = button

	_scheme_buttons[driver_id] = buttons_for_driver

func _add_scheme_visual(button: Button, scheme: String) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 1)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(row)

	var controller_icons: Array[TextureRect] = []
	match scheme:
		RaceSelection.CONTROL_COMBO:
			controller_icons.append(_add_controller_icon(row, 1))
			_add_texture_icon(row, ARROW_KEYS_ICON)
		RaceSelection.CONTROL_GAMEPAD_1:
			controller_icons.append(_add_controller_icon(row, 1))
		RaceSelection.CONTROL_ARROW:
			_add_texture_icon(row, ARROW_KEYS_ICON)
		RaceSelection.CONTROL_WASD:
			_add_texture_icon(row, WASD_KEYS_ICON)
		RaceSelection.CONTROL_GAMEPAD_2:
			controller_icons.append(_add_controller_icon(row, 2))
		RaceSelection.CONTROL_GAMEPAD_3:
			controller_icons.append(_add_controller_icon(row, 3))
		RaceSelection.CONTROL_GAMEPAD_4:
			controller_icons.append(_add_controller_icon(row, 4))
		RaceSelection.CONTROL_CPU:
			_add_texture_icon(row, CPU_ICON)

	button.set_meta(&"controller_icons", controller_icons)

	var selection_bar := ColorRect.new()
	selection_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	selection_bar.offset_bottom = 3.0
	selection_bar.color = SELECTED_LABEL_COLOR
	selection_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_bar.hide()
	button.add_child(selection_bar)
	button.set_meta(&"selection_bar", selection_bar)

func _add_texture_icon(parent: HBoxContainer, texture: Texture2D) -> TextureRect:
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(36.0, 36.0)
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	return icon

func _add_controller_icon(parent: HBoxContainer, number: int) -> TextureRect:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(36.0, 38.0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)

	var icon := TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.texture = GAME_CONTROLLER_ICON
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)

	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.text = str(number)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(label)
	return icon

func _select_control_scheme(driver_id: String, scheme: String) -> void:
	if _returning or not _is_scheme_available(scheme):
		return

	SceneTransition.play_selection_beep()
	RaceSelection.assign_control_scheme(driver_id, scheme)
	_refresh_scheme_buttons()

	var button := _get_scheme_button(driver_id, RaceSelection.get_control_scheme(driver_id))
	if button != null:
		button.grab_focus()

func _refresh_controller_assignments() -> void:
	for driver_id in DriverRoster.DRIVER_IDS:
		var scheme := RaceSelection.get_control_scheme(driver_id)
		if _get_gamepad_number(scheme) > 0 and not _is_scheme_available(scheme):
			RaceSelection.assign_control_scheme(driver_id, RaceSelection.CONTROL_CPU)

func _refresh_scheme_buttons() -> void:
	for driver_id in DriverRoster.DRIVER_IDS:
		var selected_scheme := RaceSelection.get_control_scheme(driver_id)
		var buttons_for_driver: Dictionary = _scheme_buttons[driver_id]
		for scheme in SCHEME_ORDER:
			var button := buttons_for_driver[scheme] as Button
			var available := _is_scheme_available(scheme)
			button.disabled = not available
			button.tooltip_text = _get_scheme_tooltip(scheme, available)
			_style_scheme_button(button, scheme, scheme == selected_scheme, available)
			_update_controller_icon_colors(button, scheme)

func _style_scheme_button(
	button: Button,
	_scheme: String,
	selected: bool,
	_available: bool
) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.25, 0.2, 0.035, 0.96)
		if selected
		else Color(0.08, 0.08, 0.09, 0.88)
	)
	style.border_width_right = 0

	var selection_bar := button.get_meta(&"selection_bar") as ColorRect
	selection_bar.visible = selected

	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("disabled", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_stylebox_override("focus", style)
	button.add_theme_stylebox_override("hover", style)

func _update_controller_icon_colors(button: Button, scheme: String) -> void:
	var controller_number := _get_gamepad_number(scheme)
	if controller_number == 0 and scheme != RaceSelection.CONTROL_COMBO:
		return

	var connected := _is_gamepad_connected(1 if scheme == RaceSelection.CONTROL_COMBO else controller_number)
	var color := CONTROLLER_AVAILABLE_COLOR if connected else CONTROLLER_UNAVAILABLE_COLOR
	var icons: Array = button.get_meta(&"controller_icons", [])
	for icon_value in icons:
		var icon := icon_value as TextureRect
		icon.modulate = color

func _is_scheme_available(scheme: String) -> bool:
	if scheme == RaceSelection.CONTROL_COMBO:
		return true
	var gamepad_number := _get_gamepad_number(scheme)
	return gamepad_number == 0 or _is_gamepad_connected(gamepad_number)

func _is_gamepad_connected(number: int) -> bool:
	return Input.get_connected_joypads().size() >= number

func _get_gamepad_number(scheme: String) -> int:
	match scheme:
		RaceSelection.CONTROL_GAMEPAD_1:
			return 1
		RaceSelection.CONTROL_GAMEPAD_2:
			return 2
		RaceSelection.CONTROL_GAMEPAD_3:
			return 3
		RaceSelection.CONTROL_GAMEPAD_4:
			return 4
	return 0

func _get_scheme_tooltip(scheme: String, available: bool) -> String:
	if scheme == RaceSelection.CONTROL_COMBO:
		return (
			"Game controller 1 + Arrow keys"
			if _is_gamepad_connected(1)
			else "Plug in a 1st game controller; Arrow keys remain available"
		)
	if scheme == RaceSelection.CONTROL_ARROW:
		return "Arrow keys"
	if scheme == RaceSelection.CONTROL_WASD:
		return "WASD keys"
	if scheme == RaceSelection.CONTROL_CPU:
		return "CPU driver"

	var number := _get_gamepad_number(scheme)
	if available:
		return "Game controller %d" % number
	return "Plug in a %s game controller" % _ordinal(number)

func _ordinal(number: int) -> String:
	match number:
		1:
			return "1st"
		2:
			return "2nd"
		3:
			return "3rd"
		4:
			return "4th"
	return str(number)

func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_refresh_controller_assignments()
	_refresh_scheme_buttons()

func _play_intro() -> void:
	for index in driver_buttons.size():
		var tween := create_tween()
		tween.tween_interval(index * INTRO_STAGGER)
		tween.tween_property(driver_buttons[index], "modulate", Color.WHITE, INTRO_DURATION).set_trans(
			Tween.TRANS_QUART
		).set_ease(Tween.EASE_OUT)

func _unlock_startup_hover() -> void:
	await get_tree().create_timer(0.8).timeout
	_startup_hover_locked = false

func _hover_driver(index: int) -> void:
	if _returning or _startup_hover_locked:
		return
	_focus_driver(index)

func _hover_scheme_button(button: Button) -> void:
	if not _returning and not _startup_hover_locked and not button.disabled:
		button.grab_focus()

func _focus_driver(index: int) -> void:
	if _returning:
		return
	if index != _selected_index:
		SceneTransition.play_selection_beep()
	_selected_index = index
	for button_index in driver_buttons.size():
		_animate_driver_card(button_index, button_index == _selected_index)

func _animate_driver_card(index: int, selected: bool) -> void:
	var previous_tween := _button_tweens.get(index) as Tween
	if previous_tween != null and previous_tween.is_valid():
		previous_tween.kill()

	var button := driver_buttons[index]
	button.z_index = 1 if selected else 0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", SELECTED_SCALE if selected else NORMAL_SCALE, 0.14)
	tween.tween_property(shades[index], "color", SELECTED_SHADE if selected else NORMAL_SHADE, 0.14)
	tween.tween_property(
		name_labels[index],
		"modulate",
		SELECTED_LABEL_COLOR if selected else NORMAL_LABEL_COLOR,
		0.14
	)
	_button_tweens[index] = tween

func _update_button_pivot(index: int) -> void:
	driver_buttons[index].pivot_offset = driver_buttons[index].size * 0.5

func _focus_lap() -> void:
	if not _returning:
		SceneTransition.play_selection_beep()

func _hover_lap(index: int) -> void:
	if not _returning and not _startup_hover_locked:
		lap_buttons[index].grab_focus()

func _select_laps(laps: int) -> void:
	if _returning:
		return
	SceneTransition.play_selection_beep()
	RaceSelection.selected_laps = laps
	_apply_lap_selection()

func _apply_lap_selection() -> void:
	for index in lap_buttons.size():
		var selected := index == RaceSelection.selected_laps - 1
		for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			if selected:
				lap_buttons[index].add_theme_color_override(color_name, SELECTED_LABEL_COLOR)
			else:
				lap_buttons[index].remove_theme_color_override(color_name)

func _focus_time() -> void:
	if not _returning:
		SceneTransition.play_selection_beep()

func _hover_time(index: int) -> void:
	if not _returning and not _startup_hover_locked:
		time_buttons[index].grab_focus()

func _select_time_of_day(night: bool) -> void:
	if _returning:
		return
	SceneTransition.play_selection_beep()
	RaceSelection.night_enabled = night
	_apply_time_selection()

func _apply_time_selection() -> void:
	var selected_time := 1 if RaceSelection.night_enabled else 0
	time_badge_icon.texture = NIGHT_ICON if RaceSelection.night_enabled else DAY_ICON
	for index in time_buttons.size():
		var selected := index == selected_time
		for color_name in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			if selected:
				time_buttons[index].add_theme_color_override(color_name, SELECTED_LABEL_COLOR)
			else:
				time_buttons[index].remove_theme_color_override(color_name)

func _focus_race_button() -> void:
	if _returning:
		return
	SceneTransition.play_selection_beep()
	if _race_button_tween != null and _race_button_tween.is_valid():
		_race_button_tween.kill()
	_race_button_tween = create_tween()
	_race_button_tween.tween_property(race_button_icon, "modulate", SELECTED_LABEL_COLOR, 0.14)

func _return_to_menu() -> void:
	if _returning:
		return
	_returning = true
	SceneTransition.play_selection_beep()
	_disable_buttons()
	SceneTransition.transition_to_menu()

func _disable_buttons() -> void:
	for driver_id in DriverRoster.DRIVER_IDS:
		var buttons_for_driver: Dictionary = _scheme_buttons[driver_id]
		for button in buttons_for_driver.values():
			(button as Button).disabled = true
	for button in lap_buttons:
		button.disabled = true
	for button in time_buttons:
		button.disabled = true
	race_button.disabled = true

func _get_scheme_button(driver_id: String, scheme: String) -> Button:
	var buttons_for_driver: Dictionary = _scheme_buttons.get(driver_id, {})
	return buttons_for_driver.get(scheme) as Button

func _first_human_driver_index() -> int:
	for index in DriverRoster.DRIVER_IDS.size():
		if RaceSelection.get_control_scheme(DriverRoster.DRIVER_IDS[index]) != RaceSelection.CONTROL_CPU:
			return index
	return 0
