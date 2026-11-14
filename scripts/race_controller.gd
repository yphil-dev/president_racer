extends Node

class_name RaceController

signal race_started
signal standings_updated(standings: Array)
signal car_finished(state: CarRaceState)
signal classification_started(duration: float)
signal race_finished(standings: Array)

@export_range(0.1, 2.0, 0.1) var blink_interval: float = 0.5
@export_range(1.0, 60.0, 1.0) var classification_window: float = 15.0
@export_range(0.05, 1.0, 0.05) var standings_update_interval: float = 0.1
@export_range(1.0, 2.0, 0.1) var post_finish_coast_distance: float = 1.5
@export_node_path("RaceTrafficLight") var traffic_light_path: NodePath


@onready var traffic_light: RaceTrafficLight = get_node(traffic_light_path)
@onready var game_ui: GameUI = get_node("../UI/GameUI")
@onready var track_path: Path3D = get_node("../PATH/TrackPath")
@onready var player_spawn: Marker3D = get_node("../START_GRID/GridSlot2")
@onready var race_track = get_parent()

var cars: Node3D
var standings: Array[CarRaceState] = []
var race_elapsed: float = 0.0
var classification_time_remaining: float = 0.0

var _states_by_car: Dictionary = {}
var _winner: CarRaceState
var _race_running: bool = false
var _classification_active: bool = false
var _standings_accumulator: float = 0.0
var _path_length: float = 0.0
var _start_offset: float = 0.0
var _orange_enabled: bool = true
var _red_enabled: bool = false
var _blink_timer: Timer
var _classification_light_timer: Timer
var _countdown_audio: AudioStreamPlayer
var _finish_audio: AudioStreamPlayer
var _low_tone: AudioStreamWAV
var _high_tone: AudioStreamWAV

const TONE_SAMPLE_RATE: int = 22050
const TONE_DURATION: float = 1.0
const TONE_BODY_DURATION: float = 0.46
const LOW_TONE_FREQUENCY: float = 440.0
const HIGH_TONE_FREQUENCY: float = 880.0
const BEEPS_VOLUME: float = -12.0

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not SceneTransition.is_active():
		get_viewport().set_input_as_handled()
		_race_running = false
		_set_vehicles_enabled(false)
		SceneTransition.transition_to_menu()

func _ready() -> void:
	if race_track.get_meta(&"menu_preview", false):
		return

	race_track.connect("lap_completed", _on_track_lap_completed)
	race_track.connect("car_finished", _on_track_car_finished)

	await get_tree().process_frame
	cars = RaceGridSpawner.spawn(race_track, RaceSelection.selected_driver_id)
	var camera_target := cars.get_node_or_null("PlayerCar") as Vehicle
	if camera_target == null:
		for child in cars.get_children():
			var vehicle := child as Vehicle
			if vehicle != null and vehicle.driver_id == RaceSelection.selected_driver_id:
				camera_target = vehicle
				break
	get_node("../View").set("target", camera_target)

	_setup_race_states()
	game_ui.setup(self, standings)
	_set_vehicles_enabled(false)

	_blink_timer = Timer.new()
	_blink_timer.wait_time = blink_interval
	_blink_timer.timeout.connect(_toggle_orange)
	add_child(_blink_timer)

	_classification_light_timer = Timer.new()
	_classification_light_timer.wait_time = 1.0
	_classification_light_timer.timeout.connect(_toggle_red)
	add_child(_classification_light_timer)
	_setup_race_audio()

	await _play_countdown_tones()

func _process(delta: float) -> void:
	if not _race_running:
		return

	race_elapsed += delta
	for value in _states_by_car.values():
		var state := value as CarRaceState
		if not state.finished and not state.dnf:
			state.current_time = race_elapsed
			_update_state_progress(state)

	_standings_accumulator += delta
	if _standings_accumulator >= standings_update_interval:
		_standings_accumulator = 0.0
		_update_standings()

	if _classification_active:
		classification_time_remaining = maxf(0.0, classification_time_remaining - delta)
		if classification_time_remaining <= 0.0:
			_finalize_race()

func _setup_race_states() -> void:
	_states_by_car.clear()
	standings.clear()
	var target_laps := int(race_track.get("target_laps"))

	for child in cars.get_children():
		if child is Vehicle:
			var state := CarRaceState.new(child as Vehicle, target_laps)
			_states_by_car[state.car] = state
			standings.append(state)

	_path_length = track_path.curve.get_baked_length()
	_start_offset = track_path.curve.get_closest_offset(
		track_path.to_local(player_spawn.global_position)
	)
	_update_standings(true)

func _start_race() -> void:
	race_elapsed = 0.0
	classification_time_remaining = 0.0
	_classification_active = false
	_race_running = true
	_standings_accumulator = 0.0

	for state in standings:
		state.current_time = 0.0
		_update_state_progress(state)

	_update_standings(true)
	_set_vehicles_enabled(true)
	race_started.emit()
	print("Race started!")

func _on_track_lap_completed(car: VehicleSphere, lap_number: int) -> void:
	if not _race_running or not _states_by_car.has(car):
		return

	var state := _states_by_car[car] as CarRaceState
	state.record_lap(lap_number, race_elapsed)
	_update_state_progress(state)
	car.lap_completed(lap_number, state.last_lap_time, race_elapsed)
	_update_standings(true)

func _on_track_car_finished(car: VehicleSphere, lap_number: int) -> void:
	if not _race_running or not _states_by_car.has(car):
		return

	var state := _states_by_car[car] as CarRaceState
	if state.finished:
		return
	if lap_number != state.target_laps:
		push_error("Rejected finish for %s: lap %d does not match target %d." % [
			state.vehicle.driver_name,
			lap_number,
			state.target_laps,
		])
		return

	state.record_finish(race_elapsed)
	_update_state_progress(state)
	state.vehicle.begin_finish_coast(post_finish_coast_distance)
	_finish_audio.play()
	car.race_completed(lap_number, race_elapsed)
	car_finished.emit(state)

	if _winner == null:
		_winner = state
		state.winner = true
		_classification_active = true
		classification_time_remaining = classification_window
		classification_started.emit(classification_window)
		_start_classification_light()
		print("Winner: %s. Classification closes in %.0f seconds." % [
			state.vehicle.driver_name,
			classification_window,
		])

	_update_standings(true)
	if _all_cars_finished():
		_finalize_race()

func _update_state_progress(state: CarRaceState) -> void:
	if _path_length <= 0.0:
		return

	var local_position := track_path.to_local(state.car.global_position)
	var curve_offset := track_path.curve.get_closest_offset(local_position)
	state.track_progress = fposmod(curve_offset - _start_offset, _path_length)
	state.total_progress = state.laps_completed * _path_length + state.track_progress

func _update_standings(force_emit: bool = false) -> void:
	standings.sort_custom(_is_state_ahead)
	for index in standings.size():
		standings[index].rank = index + 1

	if force_emit or _race_running:
		standings_updated.emit(standings.duplicate())

func _is_state_ahead(a: CarRaceState, b: CarRaceState) -> bool:
	if a.finished and b.finished:
		return a.finish_time < b.finish_time
	if a.finished != b.finished:
		return a.finished
	if a.dnf != b.dnf:
		return not a.dnf
	if a.laps_completed != b.laps_completed:
		return a.laps_completed > b.laps_completed
	return a.total_progress > b.total_progress

func _all_cars_finished() -> bool:
	for state in standings:
		if not state.finished:
			return false
	return true

func _finalize_race() -> void:
	if not _race_running:
		return

	_race_running = false
	_classification_active = false
	classification_time_remaining = 0.0
	_classification_light_timer.stop()
	traffic_light.show_off()

	for state in standings:
		if not state.finished:
			state.mark_dnf(race_elapsed)
		state.vehicle.set_driving_enabled(false)

	_update_standings(true)
	race_finished.emit(standings.duplicate())

func _setup_race_audio() -> void:
	_low_tone = _create_tone_stream(LOW_TONE_FREQUENCY)
	_high_tone = _create_tone_stream(HIGH_TONE_FREQUENCY)

	_countdown_audio = AudioStreamPlayer.new()
	_countdown_audio.name = "CountdownAudio"
	add_child(_countdown_audio)

	_finish_audio = AudioStreamPlayer.new()
	_finish_audio.name = "FinishAudio"
	_finish_audio.stream = _high_tone
	_finish_audio.max_polyphony = 4
	_countdown_audio.volume_db = BEEPS_VOLUME
	_finish_audio.volume_db = BEEPS_VOLUME

	add_child(_finish_audio)

func _play_countdown_tones() -> void:
	_blink_timer.stop()
	traffic_light.show_off()

	_countdown_audio.stream = _low_tone
	_countdown_audio.play()
	traffic_light.set_orange_enabled(true)
	await get_tree().create_timer(0.5).timeout
	traffic_light.show_off()
	await get_tree().create_timer(0.5).timeout

	_countdown_audio.play()
	traffic_light.set_orange_enabled(true)
	await get_tree().create_timer(0.5).timeout
	traffic_light.show_off()
	await get_tree().create_timer(0.5).timeout

	_countdown_audio.stream = _high_tone
	_countdown_audio.play()
	traffic_light.show_start()
	_start_race()
	await _countdown_audio.finished

func _create_tone_stream(frequency: float) -> AudioStreamWAV:
	var sample_count := int(TONE_SAMPLE_RATE * TONE_DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	for sample_index in sample_count:
		var time := float(sample_index) / TONE_SAMPLE_RATE
		var sample := _tone_sample(time, frequency)
		sample += _tone_sample(time - 0.17, frequency) * 0.16
		sample += _tone_sample(time - 0.34, frequency) * 0.09
		sample += _tone_sample(time - 0.52, frequency) * 0.05
		data.encode_s16(sample_index * 2, int(clampf(sample, -1.0, 1.0) * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = TONE_SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream

func _tone_sample(time: float, frequency: float) -> float:
	if time < 0.0 or time >= TONE_BODY_DURATION:
		return 0.0

	var attack := minf(time / 0.018, 1.0)
	var release := minf((TONE_BODY_DURATION - time) / 0.16, 1.0)
	var envelope := attack * release
	var fundamental := sin(TAU * frequency * time)
	var soft_harmonic := sin(TAU * frequency * 2.0 * time) * 0.12
	return (fundamental + soft_harmonic) * envelope * 0.28

func _start_classification_light() -> void:
	_red_enabled = true
	traffic_light.set_red_enabled(true)
	_classification_light_timer.start()

func _toggle_red() -> void:
	_red_enabled = not _red_enabled
	traffic_light.set_red_enabled(_red_enabled)

func _toggle_orange() -> void:
	_orange_enabled = not _orange_enabled
	traffic_light.set_orange_enabled(_orange_enabled)

func _set_vehicles_enabled(enabled: bool) -> void:
	for node in get_tree().get_nodes_in_group("race_vehicles"):
		if node is Vehicle:
			node.set_driving_enabled(enabled)
