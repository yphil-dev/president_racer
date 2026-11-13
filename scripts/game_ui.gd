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
@onready var player_intro_bubble: Panel = $PlayerIntroBubble
@onready var intro_tail: Polygon2D = $PlayerIntroBubble/Tail
@onready var intro_scheme_icons: HBoxContainer = $PlayerIntroBubble/Content/Row/DetailsFrame/Details/SchemeIcons
@onready var intro_driver_name: Label = $PlayerIntroBubble/Content/Row/DetailsFrame/Details/DriverName
@onready var intro_model_viewport: SubViewport = $PlayerIntroBubble/Content/Row/ModelFrame/ModelViewportContainer/ModelViewport

const RESULT_TWEEN_DURATION: float = 1.1
const BACKGROUND_FADE_DURATION: float = 0.8
const ACTION_SIZE := Vector2(56, 56)
const ACTION_MARGIN := Vector2(32, 28)
const REORDER_DURATION: float = 0.22
const COUNTDOWN_CARD_GAP: float = 8.0
const PLAYER_INTRO_FADE_DURATION: float = 0.5
const PLAYER_INTRO_SWAY_DISTANCE: float = 10.0
const PLAYER_INTRO_SWAY_DURATION: float = 0.16
const PLAYER_INTRO_SWAY_COUNT: int = 2
const PLAYER_INTRO_HOLD_DURATION: float = 0.6
const PLAYER_INTRO_MODEL_SCALE: float = 1.5
const PLAYER_INTRO_MODEL_ROTATION_SPEED: float = 0.15
const ARROW_KEYS_ICON: Texture2D = preload("res://sprites/arrow-keys.svg")
const WASD_KEYS_ICON: Texture2D = preload("res://sprites/wasd-keys.svg")
const GAME_CONTROLLER_ICON: Texture2D = preload("res://sprites/game-controller.svg")
const CPU_ICON: Texture2D = preload("res://sprites/cpu.svg")

var _cards_by_vehicle: Dictionary = {}
var _pending_standings: Array = []
var _reorder_running: bool = false
var _results_active: bool = false
var _restarting: bool = false
var _controller: RaceController
var _classification_duration: float = 0.0
var _classification_countdown_active: bool = false
var _intro_model_root: Node3D

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
	if not controller.race_started.is_connected(_on_race_started):
		controller.race_started.connect(_on_race_started)
	if not controller.race_finished.is_connected(_on_race_finished):
		controller.race_finished.connect(_on_race_finished)
	if not race_again.pressed.is_connected(_restart_race):
		race_again.pressed.connect(_restart_race)
	if not resized.is_connected(_layout_race_again):
		resized.connect(_layout_race_again)

	_apply_initial_standings(initial_standings)
	_setup_player_intro(initial_standings)

func _setup_player_intro(initial_standings: Array) -> void:
	var human_driver_id := ""
	for state_value in initial_standings:
		var state := state_value as CarRaceState
		if RaceSelection.get_control_scheme(state.vehicle.driver_id) == RaceSelection.CONTROL_CPU:
			continue
		if not human_driver_id.is_empty():
			player_intro_bubble.hide()
			return
		human_driver_id = state.vehicle.driver_id

	if human_driver_id.is_empty():
		player_intro_bubble.hide()
		return

	var player_vehicle: Vehicle
	for state_value in initial_standings:
		var state := state_value as CarRaceState
		if state.vehicle.driver_id == human_driver_id:
			player_vehicle = state.vehicle
			break

	if player_vehicle == null:
		player_intro_bubble.hide()
		return

	_apply_intro_bubble_color()
	intro_driver_name.text = player_vehicle.driver_name
	_populate_intro_scheme_icons(RaceSelection.get_control_scheme(player_vehicle.driver_id))
	_setup_intro_model(player_vehicle)
	player_intro_bubble.modulate = Color.WHITE
	player_intro_bubble.show()
	_position_player_intro_bubble.call_deferred()
	_animate_player_intro.call_deferred()

func _apply_intro_bubble_color() -> void:
	var panel_style := player_intro_bubble.get_theme_stylebox("panel") as StyleBoxFlat
	if panel_style != null:
		var local_style := panel_style.duplicate() as StyleBoxFlat
		local_style.bg_color = UIColors.PLAYER_INTRO_BUBBLE_COLOR
		player_intro_bubble.add_theme_stylebox_override("panel", local_style)
	intro_tail.color = UIColors.PLAYER_INTRO_BUBBLE_COLOR

func _populate_intro_scheme_icons(scheme: String) -> void:
	for child in intro_scheme_icons.get_children():
		child.queue_free()

	var textures: Array[Texture2D] = []
	match scheme:
		RaceSelection.CONTROL_COMBO:
			textures = [ARROW_KEYS_ICON, GAME_CONTROLLER_ICON]
		RaceSelection.CONTROL_ARROW:
			textures = [ARROW_KEYS_ICON]
		RaceSelection.CONTROL_WASD:
			textures = [WASD_KEYS_ICON]
		RaceSelection.CONTROL_GAMEPAD_1, RaceSelection.CONTROL_GAMEPAD_2, RaceSelection.CONTROL_GAMEPAD_3, RaceSelection.CONTROL_GAMEPAD_4:
			textures = [GAME_CONTROLLER_ICON]
		RaceSelection.CONTROL_CPU:
			textures = [CPU_ICON]

	for texture in textures:
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(64, 64)
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		intro_scheme_icons.add_child(icon)

func _setup_intro_model(vehicle: Vehicle) -> void:
	for child in intro_model_viewport.get_children():
		child.queue_free()

	var world := World3D.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	intro_model_viewport.transparent_bg = true
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(1.0, 1.0, 1.0, 1.0)
	environment.ambient_light_energy = 1.4
	world.environment = environment
	intro_model_viewport.world_3d = world
	intro_model_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var model_root := Node3D.new()
	model_root.rotation.y = deg_to_rad(25.0)
	model_root.scale = Vector3.ONE * PLAYER_INTRO_MODEL_SCALE
	intro_model_viewport.add_child(model_root)
	_intro_model_root = model_root

	var model_added := false
	for child in vehicle.vehicle_model.get_children():
		if not child is Node3D:
			continue
		var source := child as Node3D
		if not source.visible or source is GPUParticles3D or source is Light3D:
			continue
		if source is AudioStreamPlayer3D or source.name == "Lights":
			continue
		var model_copy := source.duplicate()
		model_root.add_child(model_copy)
		_apply_intro_model_color(model_copy, vehicle.car_color)
		model_added = true

	if not model_added and vehicle.vehicle_body != null:
		var body_copy := vehicle.vehicle_body.duplicate()
		model_root.add_child(body_copy)
		_apply_intro_model_color(body_copy, vehicle.car_color)

	var camera := Camera3D.new()
	intro_model_viewport.add_child(camera)
	camera.position = Vector3(2.5, 1.25, 3.2)
	camera.fov = 40.0
	camera.look_at(Vector3(0.0, 0.55, 0.0), Vector3.UP)
	camera.current = true

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	light.light_energy = 1.6
	intro_model_viewport.add_child(light)

	var fill_light := OmniLight3D.new()
	fill_light.position = Vector3(-2.0, 2.0, 2.0)
	fill_light.light_energy = 1.0
	fill_light.omni_range = 8.0
	intro_model_viewport.add_child(fill_light)

func _apply_intro_model_color(model_root: Node, car_color: Color) -> void:
	for node in model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.name != "body":
			continue
		var material := mesh_instance.get_active_material(0) as StandardMaterial3D
		if material == null:
			continue
		var unique_material := material.duplicate() as StandardMaterial3D
		if material.albedo_texture != null:
			unique_material.albedo_texture = VehiclePaletteTextures.get_texture(car_color)
		else:
			unique_material.albedo_color = car_color
		mesh_instance.set_surface_override_material(0, unique_material)

func _position_player_intro_bubble() -> void:
	if not player_intro_bubble.visible or list.get_child_count() == 0:
		return

	var top_card := list.get_child(0) as Control
	if top_card == null:
		return

	var card_position := top_card.global_position - global_position
	var bubble_position := Vector2(
		card_position.x + top_card.size.x + 16.0,
		card_position.y + (top_card.size.y - player_intro_bubble.size.y) * 0.5
	)
	bubble_position.x = minf(bubble_position.x, size.x - player_intro_bubble.size.x - 16.0)
	bubble_position.y = clampf(bubble_position.y, 16.0, size.y - player_intro_bubble.size.y - 16.0)
	player_intro_bubble.position = bubble_position

func _animate_player_intro() -> void:
	if not player_intro_bubble.visible:
		return

	var base_position := player_intro_bubble.position
	var right_position := base_position + Vector2(PLAYER_INTRO_SWAY_DISTANCE, 0.0)
	var left_position := base_position - Vector2(PLAYER_INTRO_SWAY_DISTANCE, 0.0)
	var tween := create_tween()
	for _index in PLAYER_INTRO_SWAY_COUNT:
		tween.tween_property(
			player_intro_bubble,
			"position",
			right_position,
			PLAYER_INTRO_SWAY_DURATION
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(
			player_intro_bubble,
			"position",
			left_position,
			PLAYER_INTRO_SWAY_DURATION
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(
		player_intro_bubble,
		"position",
		base_position,
		PLAYER_INTRO_SWAY_DURATION
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_interval(PLAYER_INTRO_HOLD_DURATION)

func _on_race_started() -> void:
	if not player_intro_bubble.visible:
		return

	var tween := create_tween()
	tween.tween_property(
		player_intro_bubble,
		"modulate",
		Color(1, 1, 1, 0),
		PLAYER_INTRO_FADE_DURATION
	).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tween.tween_callback(_clear_player_intro)

func _clear_player_intro() -> void:
	player_intro_bubble.hide()
	_intro_model_root = null
	for child in intro_model_viewport.get_children():
		child.queue_free()
	intro_model_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for child in intro_scheme_icons.get_children():
		child.queue_free()

func _process(delta: float) -> void:
	if is_instance_valid(_intro_model_root) and player_intro_bubble.visible:
		_intro_model_root.rotate_y(PLAYER_INTRO_MODEL_ROTATION_SPEED * delta)

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
		if RaceSelection.get_control_scheme(state.vehicle.driver_id) == RaceSelection.CONTROL_CPU:
			continue
		has_human_driver = true
		return state.winner
	return not has_human_driver

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
