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
@onready var pause_overlay: Control = $PauseOverlay
@onready var pause_back_button: Button = $PauseOverlay/Panel/Back
@onready var pause_restart_button: Button = $PauseOverlay/Panel/Restart
@onready var pause_resume_button: Button = $PauseOverlay/Panel/Resume

const CAR_UI_SCENE: PackedScene = preload("res://scenes/CarUI/car_ui.tscn")
const RESULT_TWEEN_DURATION: float = 1.1
const BACKGROUND_FADE_DURATION: float = 0.8
const REORDER_DURATION: float = 0.22

var _cards_by_vehicle: Dictionary = {}
var _active_cards: Array[CarUI] = []
var _reorder_tween: Tween
var _reorder_generation: int = 0
var _results_active: bool = false
var _restarting: bool = false
var _controller: RaceController
var _classification_duration: float = 0.0
var _classification_countdown_active: bool = false
var _paused: bool = false

func _ready() -> void:
	pause_overlay.hide()
	pause_back_button.pressed.connect(_return_to_menu_from_pause)
	pause_restart_button.pressed.connect(_restart_from_pause)
	pause_resume_button.pressed.connect(_resume_from_pause)

func setup(controller: RaceController, initial_standings: Array[CarRaceState]) -> void:
	_cards_by_vehicle.clear()
	_set_pause_audio(false)
	_paused = false
	get_tree().paused = false
	pause_overlay.hide()
	_controller = controller
	_classification_duration = 0.0
	_classification_countdown_active = false
	classification_countdown.hide()

	_active_cards.clear()
	_ensure_card_count(initial_standings.size())
	var card_nodes: Array[Node] = list.get_children()
	for card_node in card_nodes:
		(card_node as CarUI).hide()
	for index in initial_standings.size():
		var state: CarRaceState = initial_standings[index]
		var card := card_nodes[index] as CarUI
		card.setup(state)
		_active_cards.append(card)
		_cards_by_vehicle[state.vehicle] = card
		list.move_child(card, index)

	if not controller.standings_updated.is_connected(_on_standings_updated):
		controller.standings_updated.connect(_on_standings_updated)
	if not controller.classification_started.is_connected(_on_classification_started):
		controller.classification_started.connect(_on_classification_started)
	if not controller.race_finished.is_connected(_on_race_finished):
		controller.race_finished.connect(_on_race_finished)
	if not race_again.pressed.is_connected(_restart_race):
		race_again.pressed.connect(_restart_race)
	_apply_initial_standings(initial_standings)

func _ensure_card_count(required_count: int) -> void:
	while list.get_child_count() < required_count:
		var card := CAR_UI_SCENE.instantiate() as CarUI
		card.name = "CarUI%d" % (list.get_child_count() + 1)
		card.hide()
		list.add_child(card)

func is_results_active() -> bool:
	return _results_active

func toggle_pause() -> void:
	if _results_active or _restarting:
		return

	_paused = not _paused
	_set_pause_audio(_paused)
	get_tree().paused = _paused
	if _paused:
		pause_overlay.show()
		pause_resume_button.grab_focus()
	else:
		pause_overlay.hide()

func _resume_from_pause() -> void:
	if not _paused:
		return

	_set_pause_audio(false)
	_paused = false
	get_tree().paused = false
	pause_overlay.hide()

func _return_to_menu_from_pause() -> void:
	if not _paused:
		return

	_set_pause_audio(false)
	_paused = false
	get_tree().paused = false
	pause_overlay.hide()
	_controller.return_to_menu()

func _restart_from_pause() -> void:
	if not _paused:
		return

	_set_pause_audio(false)
	_paused = false
	get_tree().paused = false
	_controller.restart_race()



func _set_pause_audio(paused: bool) -> void:
	for node in get_tree().root.find_children("*", "", true, false):
		if node.get_meta(&"ui_interaction_audio", false):
			continue
		if node is AudioStreamPlayer:
			(node as AudioStreamPlayer).stream_paused = paused
		elif node is AudioStreamPlayer2D:
			(node as AudioStreamPlayer2D).stream_paused = paused
		elif node is AudioStreamPlayer3D:
			(node as AudioStreamPlayer3D).stream_paused = paused

func _process(_delta: float) -> void:
	if not _classification_countdown_active or _controller == null:
		return

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
	classification_countdown.show()

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

	if _order_changed(current_standings):
		_animate_reorder(current_standings.duplicate())

func _order_changed(current_standings: Array) -> bool:
	for index in current_standings.size():
		var state := current_standings[index] as CarRaceState
		var desired_card := _cards_by_vehicle.get(state.vehicle) as CarUI
		if list.get_child(index) != desired_card:
			return true
	return false

func _animate_reorder(current_standings: Array) -> void:
	_reorder_generation += 1
	var generation: int = _reorder_generation
	var current_positions: Dictionary = {}
	for card in _active_cards:
		current_positions[card] = card.global_position

	if _reorder_tween != null and _reorder_tween.is_valid():
		_reorder_tween.kill()
	_reorder_tween = null

	for index in current_standings.size():
		var state := current_standings[index] as CarRaceState
		var card := _cards_by_vehicle.get(state.vehicle) as CarUI
		if card != null:
			list.move_child(card, index)

	await get_tree().process_frame
	if _results_active or generation != _reorder_generation:
		return

	_reorder_tween = create_tween()
	_reorder_tween.set_parallel(true)
	_reorder_tween.set_trans(Tween.TRANS_QUART)
	_reorder_tween.set_ease(Tween.EASE_OUT)

	for card in _active_cards:
		var target_position := card.global_position
		card.global_position = current_positions[card]
		_reorder_tween.tween_property(
			card,
			"global_position",
			target_position,
			REORDER_DURATION
		)

func _on_race_finished(final_standings: Array) -> void:
	_results_active = true
	_reorder_generation += 1
	if _reorder_tween != null and _reorder_tween.is_valid():
		_reorder_tween.kill()
	_reorder_tween = null
	for state_value in final_standings:
		var state := state_value as CarRaceState
		if state.vehicle != null:
			state.vehicle.fade_engine_sound()
	_classification_countdown_active = false
	classification_countdown.hide()
	var result_rects: Array[Rect2] = QuadrantLayout.get_result_rects(
		size,
		final_standings.size()
	)
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

	var card_animations: Array[Dictionary] = []
	for index in final_standings.size():
		var state := final_standings[index] as CarRaceState
		var card := _cards_by_vehicle.get(state.vehicle) as CarUI
		if card == null:
			continue

		card_animations.append({
			"card": card,
			"state": state,
			"start_position": card.global_position - global_position,
			"start_size": card.size,
			"target_rect": result_rects[index],
		})

	for animation in card_animations:
		var card := animation["card"] as CarUI
		card.update_state(animation["state"] as CarRaceState)
		card.prepare_final_layout()

	for animation in card_animations:
		var card := animation["card"] as CarUI
		var start_position: Vector2 = animation["start_position"]
		var start_size: Vector2 = animation["start_size"]
		var target_rect: Rect2 = animation["target_rect"]
		var start_scale := Vector2(
			start_size.x / target_rect.size.x,
			start_size.y / target_rect.size.y
		)

		card.reparent(self, false)
		card.size = target_rect.size
		card.pivot_offset = target_rect.size * 0.5
		card.scale = start_scale
		card.position = start_position - (Vector2.ONE - start_scale) * card.pivot_offset
		card.show()

		var tween := card.create_tween()
		tween.set_trans(Tween.TRANS_QUART)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.set_parallel(true)
		tween.tween_property(card, "position", target_rect.position, RESULT_TWEEN_DURATION)
		tween.tween_property(card, "scale", Vector2.ONE, RESULT_TWEEN_DURATION)
		tween.chain().tween_callback(card.show_final_result)

	live_container.hide()

func _did_player_win(final_standings: Array) -> bool:
	var has_human_driver := false
	for state_value in final_standings:
		var state := state_value as CarRaceState
		if not RaceSelection.is_driver_human(state.vehicle.driver_id):
			continue
		has_human_driver = true
		return state.winner
	return not has_human_driver

func _show_race_again() -> void:
	race_again.modulate = Color(1, 1, 1, 0)
	race_again.show()
	race_again.grab_focus()

	var intro_tween := create_tween()
	intro_tween.tween_interval(0.6)
	intro_tween.tween_property(race_again, "modulate", Color.WHITE, 0.6).set_trans(
		Tween.TRANS_QUART
	).set_ease(Tween.EASE_OUT)

func _restart_race() -> void:
	if _restarting:
		return

	_restarting = true
	race_again.disabled = true
	await NavButtonAnimation.play(race_again)
	SceneTransition.transition_to_menu()
