extends Control

class_name GameUI

@onready var result_background: TextureRect = $ResultBackground
@onready var result_shade: ColorRect = $ResultShade
@onready var live_container: MarginContainer = $MarginContainer
@onready var list: VBoxContainer = $MarginContainer/VBoxContainer
@onready var classification_countdown: Control = $ClassificationCountdown
@onready var classification_label: Label = $ClassificationCountdown/Label
@onready var classification_timer: ProgressBar = $ClassificationCountdown/Timer
@onready var race_again: Button = $RaceAgain

const RESULT_TWEEN_DURATION: float = 1.1
const BACKGROUND_FADE_DURATION: float = 0.8
const ACTION_SIZE := Vector2(56, 56)
const ACTION_MARGIN := Vector2(32, 28)
const REORDER_DURATION: float = 0.22
const COUNTDOWN_CARD_GAP: float = 8.0

var _cards_by_vehicle: Dictionary = {}
var _pending_standings: Array = []
var _reorder_running: bool = false
var _results_active: bool = false
var _restarting: bool = false
var _controller: RaceController
var _classification_duration: float = 0.0
var _classification_countdown_active: bool = false

func setup(controller: RaceController, initial_standings: Array[CarRaceState]) -> void:
	_cards_by_vehicle.clear()
	_controller = controller
	_classification_duration = 0.0
	_classification_countdown_active = false
	classification_countdown.hide()

	var card_nodes := list.get_children()
	for index in initial_standings.size():
		if index >= card_nodes.size():
			break

		var state := initial_standings[index]
		var card := card_nodes[index] as CarUI
		card.setup(state)
		_cards_by_vehicle[state.vehicle] = card

	if not controller.standings_updated.is_connected(_on_standings_updated):
		controller.standings_updated.connect(_on_standings_updated)
	if not controller.classification_started.is_connected(_on_classification_started):
		controller.classification_started.connect(_on_classification_started)
	if not controller.race_finished.is_connected(_on_race_finished):
		controller.race_finished.connect(_on_race_finished)
	if not race_again.pressed.is_connected(_restart_race):
		race_again.pressed.connect(_restart_race)
	if not resized.is_connected(_layout_race_again):
		resized.connect(_layout_race_again)

	_apply_initial_standings(initial_standings)

func _process(_delta: float) -> void:
	if not _classification_countdown_active or _controller == null:
		return

	_position_classification_countdown()
	var remaining := maxf(0.0, _controller.classification_time_remaining)
	var progress := 0.0
	if _classification_duration > 0.0:
		progress = remaining / _classification_duration * 100.0
	classification_timer.value = progress
	classification_label.text = str(ceili(remaining))

func _on_classification_started(duration: float) -> void:
	_classification_duration = duration
	_classification_countdown_active = true
	classification_timer.value = 100.0
	classification_label.text = str(ceili(duration))
	_position_classification_countdown()
	classification_countdown.show()

func _position_classification_countdown() -> void:
	var bottom := list.global_position.y
	for child in list.get_children():
		if child is Control and child.visible:
			bottom = maxf(bottom, child.global_position.y + child.size.y)
	classification_countdown.position.y = bottom - global_position.y + COUNTDOWN_CARD_GAP

func _apply_initial_standings(current_standings: Array) -> void:
	for index in current_standings.size():
		var state := current_standings[index] as CarRaceState
		var card := _cards_by_vehicle.get(state.vehicle) as CarUI
		if card == null:
			continue

		card.update_state(state)
		list.move_child(card, index)

func _on_standings_updated(current_standings: Array) -> void:
	if _results_active:
		return

	for state_value in current_standings:
		var state := state_value as CarRaceState
		var card := _cards_by_vehicle.get(state.vehicle) as CarUI
		if card != null:
			card.update_state(state)

	if not _order_changed(current_standings):
		return

	if _reorder_running:
		_pending_standings = current_standings.duplicate()
		return

	_animate_reorder(current_standings.duplicate())

func _order_changed(current_standings: Array) -> bool:
	for index in current_standings.size():
		var state := current_standings[index] as CarRaceState
		var desired_card := _cards_by_vehicle.get(state.vehicle) as CarUI
		if list.get_child(index) != desired_card:
			return true
	return false

func _animate_reorder(current_standings: Array) -> void:
	_reorder_running = true
	var old_positions: Dictionary = {}

	for child in list.get_children():
		old_positions[child] = (child as Control).global_position

	for index in current_standings.size():
		var state := current_standings[index] as CarRaceState
		var card := _cards_by_vehicle.get(state.vehicle) as CarUI
		if card != null:
			list.move_child(card, index)

	await get_tree().process_frame
	if _results_active:
		_reorder_running = false
		_pending_standings.clear()
		return

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)

	for child in list.get_children():
		var card := child as CarUI
		var target_position := card.global_position
		card.global_position = old_positions[card]
		tween.tween_property(card, "global_position", target_position, REORDER_DURATION)

	await tween.finished
	_reorder_running = false

	if not _pending_standings.is_empty():
		var pending := _pending_standings.duplicate()
		_pending_standings.clear()
		_on_standings_updated(pending)

func _on_race_finished(final_standings: Array) -> void:
	_results_active = true
	for state_value in final_standings:
		var state := state_value as CarRaceState
		if state.vehicle != null:
			state.vehicle.fade_engine_sound()
	_classification_countdown_active = false
	classification_countdown.hide()
	var result_rects := QuadrantLayout.get_rects(size)
	result_background.show()
	result_shade.show()
	SceneTransition.show_potato_rock()
	AudioPlayer.play_result(_did_player_win(final_standings))

	var background_tween := create_tween()
	background_tween.set_parallel(true)
	background_tween.set_trans(Tween.TRANS_QUART)
	background_tween.set_ease(Tween.EASE_OUT)
	background_tween.tween_property(
		result_background,
		"modulate",
		Color.WHITE,
		BACKGROUND_FADE_DURATION
	)
	background_tween.tween_property(
		result_shade,
		"modulate",
		Color.WHITE,
		BACKGROUND_FADE_DURATION
	)

	_show_race_again()

	for index in final_standings.size():
		var state := final_standings[index] as CarRaceState
		var card := _cards_by_vehicle.get(state.vehicle) as CarUI
		if card == null:
			continue

		var start_position: Vector2 = card.global_position - global_position
		var start_size := card.size
		var target_rect := result_rects[index]

		card.update_state(state)
		card.reparent(self, false)
		card.position = start_position
		card.size = start_size
		card.show()

		var tween := card.create_tween()
		tween.set_trans(Tween.TRANS_QUART)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.set_parallel(true)
		tween.tween_property(card, "position", target_rect.position, RESULT_TWEEN_DURATION)
		tween.tween_property(card, "size", target_rect.size, RESULT_TWEEN_DURATION)
		tween.chain().tween_callback(card.show_final_result)

	live_container.hide()

func _did_player_win(final_standings: Array) -> bool:
	for state_value in final_standings:
		var state := state_value as CarRaceState
		if state.vehicle is PlayerCar:
			return state.winner
	return false

func _show_race_again() -> void:
	_layout_race_again()
	race_again.modulate = Color(1, 1, 1, 0)
	race_again.show()
	race_again.grab_focus()

	var intro_tween := create_tween()
	intro_tween.tween_interval(0.6)
	intro_tween.tween_property(race_again, "modulate", Color.WHITE, 0.6).set_trans(
		Tween.TRANS_QUART
	).set_ease(Tween.EASE_OUT)

func _layout_race_again() -> void:
	if not is_node_ready():
		return

	race_again.position = size - ACTION_SIZE - ACTION_MARGIN
	race_again.size = ACTION_SIZE
	race_again.pivot_offset = ACTION_SIZE * 0.5

func _restart_race() -> void:
	if _restarting:
		return

	_restarting = true
	SceneTransition.play_selection_beep()
	race_again.disabled = true
	await NavButtonAnimation.play(race_again)
	SceneTransition.transition_to_menu()
