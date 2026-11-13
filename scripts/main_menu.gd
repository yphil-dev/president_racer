extends Control

const DRIVER_SELECTION_SCENE := "res://scenes/options_menu.tscn"
const DAY_ICON: Texture2D = preload("res://sprites/daytime-day.svg")
const NIGHT_ICON: Texture2D = preload("res://sprites/daytime-night.svg")
const WEATHER_ICONS: Dictionary = {
	RaceSelection.WEATHER_FAIR: preload("res://sprites/weather-fair.svg"),
	RaceSelection.WEATHER_RAIN: preload("res://sprites/weather-rain.svg"),
	RaceSelection.WEATHER_SNOW: preload("res://sprites/weather-snow.svg"),
}
const LAPS_ICONS: Dictionary = {
	1: preload("res://sprites/laps-one.svg"),
	2: preload("res://sprites/laps-two.svg"),
	3: preload("res://sprites/laps-three.svg"),
}
const CPU_ICON: Texture2D = preload("res://sprites/cpu.svg")

const TRACK_SCENES: Array[String] = [
	"res://scenes/tracks/paris.tscn",
	"res://scenes/tracks/marseille.tscn",
	"res://scenes/tracks/limoges.tscn",
	"res://scenes/tracks/lyon.tscn",
]

const SELECTED_SCALE := Vector2(1.02, 1.02)
const NORMAL_SCALE := Vector2.ONE
const SELECTED_SHADE := Color(0, 0, 0, 0.04)
const NORMAL_SHADE := Color(0, 0, 0, 0.28)
const SELECTED_LABEL_COLOR := UIColors.SELECTED_LABEL_COLOR
const NORMAL_LABEL_COLOR := UIColors.NORMAL_LABEL_COLOR
const INTRO_DURATION: float = 0.8
const INTRO_STAGGER: float = 0.14
const OPTIONS_SIZE := Vector2(240, 56)
const OPTIONS_MARGIN := Vector2(32, 28)

@onready var track_grid: GridContainer = $TrackGrid
@onready var options_button: Button = $Options
@onready var selected_driver_portrait: TextureRect = $Options/Portrait
@onready var selected_laps_icon: TextureRect = $Options/LapIcon
@onready var selected_time_icon: TextureRect = $Options/TimeIcon
@onready var selected_weather_icon: TextureRect = $Options/WeatherIcon
@onready var preview_viewport: SubViewport = $PreviewViewport
@onready var track_buttons: Array[Button] = [
	$TrackGrid/Paris,
	$TrackGrid/Marseille,
	$TrackGrid/Limoges,
	$TrackGrid/Lyon,
]
@onready var selectable_buttons: Array[Button] = [
	$TrackGrid/Paris,
	$TrackGrid/Marseille,
	$TrackGrid/Limoges,
	$TrackGrid/Lyon,
	$Options,
]
@onready var previews: Array[TextureRect] = [
	$TrackGrid/Paris/Preview,
	$TrackGrid/Marseille/Preview,
	$TrackGrid/Limoges/Preview,
	$TrackGrid/Lyon/Preview,
]
@onready var selection_shades: Array[ColorRect] = [
	$TrackGrid/Paris/Shade,
	$TrackGrid/Marseille/Shade,
	$TrackGrid/Limoges/Shade,
	$TrackGrid/Lyon/Shade,
	$Options/Shade,
]
@onready var selection_labels: Array[Control] = [
	$TrackGrid/Paris/CityLabel,
	$TrackGrid/Marseille/CityLabel,
	$TrackGrid/Limoges/CityLabel,
	$TrackGrid/Lyon/CityLabel,
	$Options/LapIcon,
]
@onready var loading_labels: Array[Label] = [
	$TrackGrid/Paris/LoadingLabel,
	$TrackGrid/Marseille/LoadingLabel,
	$TrackGrid/Limoges/LoadingLabel,
	$TrackGrid/Lyon/LoadingLabel,
]

var _button_tweens: Dictionary = {}
var _selected_index: int = 0
var _startup_hover_locked: bool = true
var _launching: bool = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _launching and not SceneTransition.is_active():
		get_viewport().set_input_as_handled()
		SceneTransition.quit_game()

func _ready() -> void:
	for index in track_buttons.size():
		track_buttons[index].pressed.connect(_launch_track.bind(index))

	options_button.pressed.connect(_open_options)
	for index in selectable_buttons.size():
		selectable_buttons[index].focus_entered.connect(_select_button.bind(index))
		if index < track_buttons.size():
			selectable_buttons[index].mouse_entered.connect(_hover_button.bind(index))
		selectable_buttons[index].resized.connect(_update_button_pivot.bind(index))

	resized.connect(_layout_menu)
	_initialize_selection.call_deferred()
	_generate_previews.call_deferred()

func _initialize_selection() -> void:
	await get_tree().process_frame
	RaceSelection.prepare_next_race()
	_layout_menu()
	for index in selectable_buttons.size():
		selectable_buttons[index].modulate = Color(1, 1, 1, 0)
		_update_button_pivot(index)

	if _all_drivers_cpu():
		selected_driver_portrait.texture = CPU_ICON
	else:
		var selected_profile := DriverRoster.get_profile(RaceSelection.selected_driver_id)
		selected_driver_portrait.texture = selected_profile["portrait"]
	selected_laps_icon.texture = LAPS_ICONS.get(RaceSelection.selected_laps, LAPS_ICONS[2])
	selected_time_icon.texture = NIGHT_ICON if RaceSelection.night_enabled else DAY_ICON
	selected_weather_icon.texture = WEATHER_ICONS.get(
		RaceSelection.selected_weather,
		WEATHER_ICONS[RaceSelection.WEATHER_FAIR]
	)

	_select_button(0)
	selectable_buttons[0].grab_focus()
	AudioPlayer.fade_in(2.5)
	_play_intro()
	_unlock_startup_hover.call_deferred()

func _all_drivers_cpu() -> bool:
	for driver_id in DriverRoster.DRIVER_IDS:
		if RaceSelection.get_control_scheme(driver_id) != RaceSelection.CONTROL_CPU:
			return false
	return true

func _layout_menu() -> void:
	if not is_node_ready():
		return

	var card_size := QuadrantLayout.get_card_size(size)
	var grid_size := QuadrantLayout.get_grid_size(size)
	track_grid.position = (size - grid_size) * 0.5
	track_grid.size = grid_size
	track_grid.custom_minimum_size = grid_size

	for button in track_buttons:
		button.custom_minimum_size = card_size

	options_button.position = size - OPTIONS_SIZE - OPTIONS_MARGIN
	options_button.size = OPTIONS_SIZE
	options_button.custom_minimum_size = OPTIONS_SIZE

func _play_intro() -> void:
	for index in selectable_buttons.size():
		var tween := create_tween()
		tween.tween_interval(index * INTRO_STAGGER)
		tween.tween_property(
			selectable_buttons[index],
			"modulate",
			Color.WHITE,
			INTRO_DURATION
		).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

func _unlock_startup_hover() -> void:
	var intro_end := INTRO_DURATION + INTRO_STAGGER * (selectable_buttons.size() - 1)
	await get_tree().create_timer(intro_end + 0.1).timeout
	_startup_hover_locked = false

func _hover_button(index: int) -> void:
	if _launching or _startup_hover_locked:
		return
	selectable_buttons[index].grab_focus()

func _select_button(index: int) -> void:
	if _launching:
		return

	if index != _selected_index:
		SceneTransition.play_selection_beep()
	_selected_index = index
	for button_index in selectable_buttons.size():
		_animate_button(button_index, button_index == _selected_index)

func _animate_button(index: int, selected: bool) -> void:
	var previous_tween := _button_tweens.get(index) as Tween
	if previous_tween != null and previous_tween.is_valid():
		previous_tween.kill()

	var button := selectable_buttons[index]
	button.z_index = 1 if selected else 0
	if selection_labels[index] is Label:
		_style_title_label(selection_labels[index] as Label, selected)
	var target_scale := NORMAL_SCALE
	if selected and index < track_buttons.size():
		target_scale = SELECTED_SCALE

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", target_scale, 0.14)
	if index < track_buttons.size():
		tween.tween_property(
			selection_shades[index],
			"color",
			SELECTED_SHADE if selected else NORMAL_SHADE,
			0.14
		)
	tween.tween_property(
		selection_labels[index],
		"modulate",
		SELECTED_LABEL_COLOR if selected else NORMAL_LABEL_COLOR,
		0.14
	)
	_button_tweens[index] = tween

func _style_title_label(label: Label, selected: bool) -> void:
	if not label.has_meta(&"local_label_settings"):
		var settings := label.label_settings
		label.label_settings = settings.duplicate() if settings != null else LabelSettings.new()
		label.set_meta(&"local_label_settings", true)

	var settings := label.label_settings
	settings.outline_color = (
		UIColors.SELECTED_LABEL_OUTLINE_COLOR
		if selected
		else UIColors.NORMAL_LABEL_OUTLINE_COLOR
	)
	settings.outline_size = (
		UIColors.SELECTED_LABEL_OUTLINE_SIZE
		if selected
		else UIColors.NORMAL_LABEL_OUTLINE_SIZE
	)

func _update_button_pivot(index: int) -> void:
	selectable_buttons[index].pivot_offset = selectable_buttons[index].size * 0.5

func _generate_previews() -> void:
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		for label in loading_labels:
			label.text = "PREVIEW REQUIRES DISPLAY"
		return

	for index in TRACK_SCENES.size():
		await _capture_preview(TRACK_SCENES[index], previews[index], loading_labels[index])

func _capture_preview(
	scene_path: String,
	preview: TextureRect,
	loading_label: Label
) -> void:
	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		loading_label.text = "PREVIEW UNAVAILABLE"
		return

	var track := packed_scene.instantiate()
	track.set_meta(&"menu_preview", true)
	track.process_mode = Node.PROCESS_MODE_DISABLED

	var track_ui := track.get_node_or_null("UI") as CanvasLayer
	if track_ui != null:
		track_ui.hide()

	var waypoint_generator := track.get_node_or_null("PATH/WaypointGenerator")
	if waypoint_generator != null:
		waypoint_generator.set("show_debug_lines", false)

	preview_viewport.add_child(track)
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	await get_tree().process_frame
	await get_tree().process_frame

	var image := preview_viewport.get_texture().get_image()
	if not image.is_empty():
		preview.texture = ImageTexture.create_from_image(image)
		loading_label.hide()
	else:
		loading_label.text = "PREVIEW UNAVAILABLE"

	preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	track.queue_free()
	await get_tree().process_frame

func _launch_track(index: int) -> void:
	if _launching:
		return

	_launching = true
	_selected_index = index
	for button in selectable_buttons:
		button.disabled = true

	AudioPlayer.fade_out_and_stop(1.0)

	var button := track_buttons[index]
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(button, "scale", Vector2(0.97, 0.97), 0.08)
	tween.tween_property(button, "scale", Vector2(1.04, 1.04), 0.1)
	await tween.finished

	button.scale = SELECTED_SCALE
	RaceSelection.mark_race_started()
	var start_rect := _get_control_global_rect(button)
	SceneTransition.transition_to_track(
		TRACK_SCENES[index],
		previews[index].texture,
		start_rect
	)

func _get_control_global_rect(control: Control) -> Rect2:
	var global_transform := control.get_global_transform()
	var top_left := global_transform * Vector2.ZERO
	var bottom_right := global_transform * control.size
	return Rect2(top_left, bottom_right - top_left)

func _open_options() -> void:
	if _launching:
		return

	_launching = true
	SceneTransition.play_selection_beep()
	for button in selectable_buttons:
		button.disabled = true

	var index := selectable_buttons.size() - 1
	var previous_tween := _button_tweens.get(index) as Tween
	if previous_tween != null and previous_tween.is_valid():
		previous_tween.kill()

	await NavButtonAnimation.play(options_button)
	SceneTransition.transition_to_scene(DRIVER_SELECTION_SCENE)
