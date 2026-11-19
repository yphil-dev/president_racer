extends PanelContainer

class_name CarUI

const WINNER_ICON: Texture2D = preload("res://sprites/results-trophy.png")
const FINISHED_ICON: Texture2D = preload("res://sprites/results-finish-flag.svg")
const DNF_ICON: Texture2D = preload("res://sprites/results-dnf.png")
const ARROW_KEYS_ICON: Texture2D = preload("res://sprites/arrow-keys.svg")
const WASD_KEYS_ICON: Texture2D = preload("res://sprites/wasd-keys.svg")
const GAME_CONTROLLER_ICON: Texture2D = preload("res://sprites/game-controller.svg")
const CPU_ICON: Texture2D = preload("res://sprites/cpu.svg")

@onready var margin: MarginContainer = $Margin
@onready var hbox: HBoxContainer = $Margin/HBox
@onready var accent: ColorRect = $Margin/HBox/Accent
@onready var portrait: TextureRect = $Margin/HBox/Portrait
@onready var info: VBoxContainer = $Margin/HBox/Info
@onready var header: HBoxContainer = $Margin/HBox/Info/Header
@onready var rank_label: Label = $Margin/HBox/Info/Header/RankLabel
@onready var name_label: Label = $Margin/HBox/Info/Header/NameLabel
@onready var time_label: Label = $Margin/HBox/Info/TimeLabel
@onready var status_row: HBoxContainer = $Margin/HBox/Info/StatusRow
@onready var status_icon: TextureRect = $Margin/HBox/Info/StatusRow/StatusBadge/StatusIcon
@onready var status_label: Label = $Margin/HBox/Info/StatusRow/StatusLabel
@onready var result_badge: Panel = $ResultBadge
@onready var result_icon: TextureRect = $ResultBadge/ResultIcon
@onready var best_icon: TextureRect = $Margin/HBox/Info/BestRow/Icon
@onready var best_label: Label = $Margin/HBox/Info/BestRow/BestLabel

var race_state: CarRaceState

func _ready() -> void:
	var name_settings := LabelSettings.new()
	name_settings.font = name_label.get_theme_font("font")
	name_settings.font_size = name_label.get_theme_font_size("font_size")
	name_settings.font_color = name_label.get_theme_color("font_color")
	name_settings.shadow_color = Color.BLACK
	name_settings.shadow_offset = Vector2(0.8, 0.8)
	name_label.label_settings = name_settings
	resized.connect(_position_result_badge)

func setup(state: CarRaceState) -> void:
	race_state = state
	rank_label.hide()
	best_icon.hide()
	portrait.texture = state.vehicle.portrait
	accent.color = state.vehicle.car_color
	name_label.text = state.vehicle.driver_name
	update_state(state)
	show()

func update_state(state: CarRaceState) -> void:
	race_state = state
	rank_label.text = "%d." % state.rank
	name_label.text = state.vehicle.driver_name
	accent.color = state.vehicle.car_color

	if state.dnf:
		time_label.text = "--:--.--"
		status_icon.texture = DNF_ICON
		status_label.text = ""
	elif state.finished:
		time_label.text = format_time(state.finish_time)
		status_icon.texture = FINISHED_ICON
		status_label.text = ""
	else:
		time_label.text = format_time(state.current_time)
		status_icon.texture = _control_icon_for_driver(state.vehicle.driver_id)
		status_label.text = "%d / %d" % [state.laps_completed, state.target_laps]

	best_label.text = (
		"%s" % format_time(state.best_lap_time)
		if state.best_lap_time >= 0.0
		else ""
	)

func _control_icon_for_driver(driver_id: String) -> Texture2D:
	if not RaceSelection.is_driver_human(driver_id):
		return CPU_ICON
	var input_source: int = RaceSelection.get_input_source_for_driver(driver_id)
	match input_source:
		RaceSelection.InputSource.ARROWS:
			return ARROW_KEYS_ICON
		RaceSelection.InputSource.WASD:
			return WASD_KEYS_ICON
	return GAME_CONTROLLER_ICON

func prepare_final_layout() -> void:
	rank_label.hide()
	status_row.hide()
	var profile: Dictionary = DriverRoster.get_profile(race_state.vehicle.driver_id)
	name_label.text = str(profile.get("last_name", race_state.vehicle.driver_name))
	best_icon.show()
	custom_minimum_size = Vector2.ZERO
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	hbox.add_theme_constant_override("separation", 12)
	accent.custom_minimum_size = Vector2(10, 0)
	portrait.custom_minimum_size = Vector2(120, 0)
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 5)
	header.add_theme_constant_override("separation", 5)

	rank_label.add_theme_font_size_override("font_size", 22)
	name_label.label_settings.font_size = 22
	time_label.add_theme_font_size_override("font_size", 24)
	status_label.add_theme_font_size_override("font_size", 18)
	best_label.add_theme_font_size_override("font_size", 16)

func show_final_result() -> void:
	prepare_final_layout()
	if race_state.dnf:
		result_icon.texture = DNF_ICON
	elif race_state.winner:
		result_icon.texture = WINNER_ICON
	else:
		result_icon.texture = FINISHED_ICON
	_position_result_badge()
	result_badge.show()

func _position_result_badge() -> void:
	result_badge.global_position = global_position + Vector2(size.x - 44.0, -20.0)

func format_time(seconds: float) -> String:
	var safe_seconds := maxf(0.0, seconds)
	var minutes: int = int(safe_seconds / 60.0)
	var remaining := fmod(safe_seconds, 60.0)
	return "%02d:%05.2f" % [minutes, remaining]
