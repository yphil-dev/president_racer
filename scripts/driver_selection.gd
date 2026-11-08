extends Control

const SELECTED_SCALE := Vector2(1.02, 1.02)
const NORMAL_SCALE := Vector2.ONE
const SELECTED_SHADE := Color(0, 0, 0, 0.04)
const NORMAL_SHADE := Color(0, 0, 0, 0.28)
const SELECTED_LABEL_COLOR := Color(1, 0.88, 0.2, 1)
const NORMAL_LABEL_COLOR := Color.WHITE
const DAY_ICON: Texture2D = preload("res://sprites/day-sun.svg")
const NIGHT_ICON: Texture2D = preload("res://sprites/night-moon.svg")
const INTRO_DURATION: float = 0.8
const INTRO_STAGGER: float = 0.14

@onready var driver_grid: GridContainer = $DriverGrid
@onready var driver_badge: Panel = $DriverBadge
@onready var lap_badge: Panel = $LapBadge
@onready var time_badge: Panel = $TimeBadge
@onready var time_badge_icon: TextureRect = $TimeBadge/Icon
@onready var lap_selector: VBoxContainer = $LapSelector
@onready var time_selector: HBoxContainer = $TimeSelector
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
var _selected_index: int = 0
var _startup_hover_locked: bool = true
var _selecting: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _selecting and not SceneTransition.is_active():
		get_viewport().set_input_as_handled()
		_selecting = true
		_disable_buttons()
		SceneTransition.transition_to_menu()

func _ready() -> void:
	driver_grid.move_child(driver_buttons[3], 2)

	for index in driver_buttons.size():
		var profile := DriverRoster.get_profile(DriverRoster.DRIVER_IDS[index])
		portraits[index].texture = profile["selection_portrait"]
		color_accents[index].color = profile["car_color"]
		name_labels[index].text = profile["display_name"]
		driver_buttons[index].pressed.connect(_select_driver.bind(index))
		driver_buttons[index].focus_entered.connect(_focus_driver.bind(index))
		driver_buttons[index].mouse_entered.connect(_hover_driver.bind(index))
		driver_buttons[index].resized.connect(_update_button_pivot.bind(index))

	for index in lap_buttons.size():
		lap_buttons[index].pressed.connect(_select_laps.bind(index + 1))
		lap_buttons[index].focus_entered.connect(_focus_lap.bind(index))
		lap_buttons[index].mouse_entered.connect(_hover_lap.bind(index))
	var selected_lap_button := lap_buttons[RaceSelection.selected_laps - 1]
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		selected_lap_button.add_theme_color_override(color_name, SELECTED_LABEL_COLOR)
	for index in time_buttons.size():
		time_buttons[index].pressed.connect(_select_time_of_day.bind(index == 1))
		time_buttons[index].focus_entered.connect(_focus_time)
		time_buttons[index].mouse_entered.connect(_hover_time.bind(index))
	var selected_time := 1 if RaceSelection.night_enabled else 0
	time_badge_icon.texture = NIGHT_ICON if RaceSelection.night_enabled else DAY_ICON
	for color_name in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		time_buttons[selected_time].add_theme_color_override(color_name, SELECTED_LABEL_COLOR)

	resized.connect(_layout_cards)
	_initialize.call_deferred()

func _initialize() -> void:
	await get_tree().process_frame
	_layout_cards()

	for index in driver_buttons.size():
		driver_buttons[index].modulate = Color(1, 1, 1, 0)
		_update_button_pivot(index)

	_selected_index = DriverRoster.DRIVER_IDS.find(RaceSelection.selected_driver_id)
	if _selected_index < 0:
		_selected_index = 0

	_focus_driver(_selected_index)
	driver_buttons[_selected_index].grab_focus()
	_play_intro()
	_unlock_startup_hover.call_deferred()

func _layout_cards() -> void:
	if not is_node_ready():
		return

	var available_size := Vector2(size.x, maxf(size.y - 250.0, 0.0))
	var card_size := QuadrantLayout.get_card_size(available_size)
	var grid_size := QuadrantLayout.get_grid_size(available_size)
	var total_height := grid_size.y + 160.0
	driver_grid.position = Vector2((size.x - grid_size.x) * 0.5, (size.y - total_height) * 0.5 + 20.0)
	driver_badge.position = driver_grid.position + Vector2(grid_size.x + 8.0, -14.0)
	driver_badge.size = Vector2(64.0, 64.0)
	driver_grid.size = grid_size
	driver_grid.custom_minimum_size = grid_size

	for button in driver_buttons:
		button.custom_minimum_size = card_size

	lap_selector.position = Vector2((size.x - 192.0) * 0.5, driver_grid.position.y + grid_size.y + 20.0)
	lap_selector.size = Vector2(192.0, 36.0)
	lap_badge.position = lap_selector.position + Vector2(200.0, -14.0)
	lap_badge.size = Vector2(64.0, 64.0)
	time_selector.position = lap_selector.position + Vector2(0.0, 76.0)
	time_selector.size = Vector2(192.0, 40.0)
	time_badge.position = time_selector.position + Vector2(200.0, -14.0)
	time_badge.size = Vector2(64.0, 64.0)

func _play_intro() -> void:
	for index in driver_buttons.size():
		var tween := create_tween()
		tween.tween_interval(index * INTRO_STAGGER)
		tween.tween_property(
			driver_buttons[index],
			"modulate",
			Color.WHITE,
			INTRO_DURATION
		).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

func _unlock_startup_hover() -> void:
	await get_tree().create_timer(0.8).timeout
	_startup_hover_locked = false

func _hover_driver(index: int) -> void:
	if _selecting or _startup_hover_locked:
		return
	driver_buttons[index].grab_focus()

func _focus_driver(index: int) -> void:
	if _selecting:
		return

	if index != _selected_index:
		SceneTransition.play_selection_beep()
	_selected_index = index
	for button_index in driver_buttons.size():
		_animate_button(button_index, button_index == _selected_index)

func _animate_button(index: int, selected: bool) -> void:
	var previous_tween := _button_tweens.get(index) as Tween
	if previous_tween != null and previous_tween.is_valid():
		previous_tween.kill()

	var button := driver_buttons[index]
	button.z_index = 1 if selected else 0

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(
		button,
		"scale",
		SELECTED_SCALE if selected else NORMAL_SCALE,
		0.14
	)
	tween.tween_property(
		shades[index],
		"color",
		SELECTED_SHADE if selected else NORMAL_SHADE,
		0.14
	)
	tween.tween_property(
		name_labels[index],
		"modulate",
		SELECTED_LABEL_COLOR if selected else NORMAL_LABEL_COLOR,
		0.14
	)
	_button_tweens[index] = tween

func _update_button_pivot(index: int) -> void:
	driver_buttons[index].pivot_offset = driver_buttons[index].size * 0.5

func _select_driver(index: int) -> void:
	if _selecting:
		return

	_selecting = true
	SceneTransition.play_selection_beep()
	_disable_buttons()
	RaceSelection.select_driver(DriverRoster.DRIVER_IDS[index])

	var button := driver_buttons[index]
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(button, "scale", Vector2(0.97, 0.97), 0.08)
	tween.tween_property(button, "scale", Vector2(1.04, 1.04), 0.1)
	await tween.finished
	SceneTransition.transition_to_menu()

func _focus_lap(_index: int) -> void:
	if not _selecting:
		SceneTransition.play_selection_beep()

func _hover_lap(index: int) -> void:
	if not _selecting and not _startup_hover_locked:
		lap_buttons[index].grab_focus()

func _select_laps(laps: int) -> void:
	if _selecting:
		return
	_selecting = true
	SceneTransition.play_selection_beep()
	_disable_buttons()
	RaceSelection.selected_laps = laps
	SceneTransition.transition_to_menu()

func _focus_time() -> void:
	if not _selecting:
		SceneTransition.play_selection_beep()

func _hover_time(index: int) -> void:
	if not _selecting and not _startup_hover_locked:
		time_buttons[index].grab_focus()

func _select_time_of_day(night: bool) -> void:
	if _selecting:
		return
	_selecting = true
	SceneTransition.play_selection_beep()
	_disable_buttons()
	RaceSelection.night_enabled = night
	SceneTransition.transition_to_menu()

func _disable_buttons() -> void:
	for button in driver_buttons:
		button.disabled = true
	for button in lap_buttons:
		button.disabled = true
	for button in time_buttons:
		button.disabled = true
