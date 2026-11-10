extends PanelContainer

class_name CarUI

const WINNER_ICON: Texture2D = preload("res://sprites/results-trophy.png")
const FINISHED_ICON: Texture2D = preload("res://sprites/results-finish-flag.svg")
const DNF_ICON: Texture2D = preload("res://sprites/results-dnf.png")
const RACING_ICON: Texture2D = preload("res://sprites/steering-wheel.png")

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
		status_icon.texture = RACING_ICON
		status_label.text = "%d / %d" % [state.laps_completed, state.target_laps]

	best_label.text = (
		"%s" % format_time(state.best_lap_time)
		if state.best_lap_time >= 0.0
		else ""
	)

func show_final_result() -> void:
	rank_label.hide()
	status_row.hide()
	best_icon.show()
	if race_state.dnf:
		result_icon.texture = DNF_ICON
	elif race_state.winner:
		result_icon.texture = WINNER_ICON
	else:
		result_icon.texture = FINISHED_ICON
	_position_result_badge()
	result_badge.show()
	custom_minimum_size = Vector2.ZERO
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	hbox.add_theme_constant_override("separation", 12)
	accent.custom_minimum_size = Vector2(10, 0)
	portrait.custom_minimum_size = Vector2(160, 0)
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 5)
	header.add_theme_constant_override("separation", 5)

	rank_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_font_size_override("font_size", 26)
	time_label.add_theme_font_size_override("font_size", 30)
	status_label.add_theme_font_size_override("font_size", 18)
	best_label.add_theme_font_size_override("font_size", 16)

func _position_result_badge() -> void:
	result_badge.global_position = global_position + Vector2(size.x - 44.0, -20.0)

func format_time(seconds: float) -> String:
	var safe_seconds := maxf(0.0, seconds)
	var minutes: int = int(safe_seconds / 60.0)
	var remaining := fmod(safe_seconds, 60.0)
	return "%02d:%05.2f" % [minutes, remaining]
