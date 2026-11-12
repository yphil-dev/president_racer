extends Node3D

const DIMMING_START := 2.0
const DIMMING_DURATION := 4.5
const WEATHER_DELAY := 5.0
const LIGHTNING_FLASH_MIN := 0.08
const LIGHTNING_FLASH_MAX := 0.16
const LIGHTNING_THUNDER_DELAY := 0.5

var _rain: GPUParticles3D
var _rain_audio: AudioStreamPlayer
var _thunder_audio: AudioStreamPlayer
var _lightning: OmniLight3D
var _sun: DirectionalLight3D
var _world_environment: WorldEnvironment
var _original_sun_energy := 0.0
var _weather_active := false
var _race_finished := false
var _lightning_schedule_started := false

func _ready() -> void:
	var track := get_parent()
	_sun = track.find_child("Sun", true, false) as DirectionalLight3D
	_world_environment = track.find_child("Environment", true, false) as WorldEnvironment
	if _sun != null:
		_original_sun_energy = _sun.light_energy

	_create_rain()
	_rain.emitting = false
	_create_audio()
	_create_lightning()
	_connect_race_signals.call_deferred()

func _process(_delta: float) -> void:
	if _weather_active:
		_anchor_to_camera()

func _connect_race_signals() -> void:
	var race_controller := get_parent().get_node_or_null("RaceController")
	if race_controller == null:
		return
	if race_controller.has_signal("race_started"):
		race_controller.race_started.connect(_on_race_started)
	if race_controller.has_signal("race_finished"):
		race_controller.race_finished.connect(_on_race_finished)

func _on_race_started() -> void:
	if RaceSelection.night_enabled or RaceSelection.selected_weather != RaceSelection.WEATHER_RAIN:
		return

	_start_dimming_sequence()
	_start_rain_sequence()

func _start_dimming_sequence() -> void:
	await get_tree().create_timer(DIMMING_START).timeout
	if not is_inside_tree() or _race_finished:
		return

	_apply_overcast_lighting()

func _start_rain_sequence() -> void:
	await get_tree().create_timer(WEATHER_DELAY).timeout
	if not is_inside_tree() or _race_finished:
		return

	_anchor_to_camera()
	_weather_active = true
	_rain.emitting = true
	_rain_audio.play()
	_rain_audio.volume_db = -9.0
	_start_lightning_schedule()

func _on_race_finished(_standings: Array) -> void:
	_race_finished = true
	_rain.emitting = false
	_rain_audio.stop()
	_thunder_audio.stop()
	_lightning.light_energy = 0.0

func _anchor_to_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	global_position = Vector3(camera.global_position.x, 0.0, camera.global_position.z)

func _apply_overcast_lighting() -> void:
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

	if _world_environment != null and _world_environment.environment != null:
		var overcast_environment := _world_environment.environment.duplicate() as Environment
		_world_environment.environment = overcast_environment
		tween.tween_property(
			overcast_environment,
			"ambient_light_energy",
			overcast_environment.ambient_light_energy * 0.7,
			DIMMING_DURATION
		)
		tween.tween_property(
			overcast_environment,
			"tonemap_exposure",
			overcast_environment.tonemap_exposure * 0.9,
			DIMMING_DURATION
		)

	if _sun != null:
		tween.tween_property(
			_sun,
			"light_energy",
			_original_sun_energy * 0.62,
			DIMMING_DURATION
		)

func _create_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	_rain.amount = 2400
	_rain.lifetime = 1.25
	_rain.preprocess = 1.25
	_rain.visibility_aabb = AABB(Vector3(-70.0, -30.0, -70.0), Vector3(140.0, 80.0, 140.0))
	_rain.position = Vector3(0.0, 28.0, 0.0)

	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(60.0, 0.5, 60.0)
	process_material.direction = Vector3(0.0, -1.0, 0.0)
	process_material.spread = 2.0
	process_material.gravity = Vector3(0.0, -18.0, 0.0)
	process_material.initial_velocity_min = 17.0
	process_material.initial_velocity_max = 23.0
	process_material.scale_min = 0.7
	process_material.scale_max = 1.2
	_rain.process_material = process_material

	var drop_mesh := BoxMesh.new()
	drop_mesh.size = Vector3(0.025, 0.7, 0.025)
	var drop_material := StandardMaterial3D.new()
	drop_material.albedo_color = Color(0.5, 0.7, 0.9, 0.72)
	drop_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_mesh.material = drop_material
	_rain.draw_pass_1 = drop_mesh
	add_child(_rain)

func _create_audio() -> void:
	_rain_audio = AudioStreamPlayer.new()
	_rain_audio.name = "RainAudio"
	_rain_audio.stream = preload("res://audio/rain.ogg")
	add_child(_rain_audio)

	_thunder_audio = AudioStreamPlayer.new()
	_thunder_audio.name = "ThunderAudio"
	_thunder_audio.stream = preload("res://audio/thunder.ogg")
	add_child(_thunder_audio)

func _create_lightning() -> void:
	_lightning = OmniLight3D.new()
	_lightning.name = "Lightning"
	_lightning.position = Vector3(0.0, 18.0, 0.0)
	_lightning.omni_range = 180.0
	_lightning.light_color = Color(0.82, 0.9, 1.0, 1.0)
	_lightning.light_energy = 0.0
	_lightning.shadow_enabled = false
	add_child(_lightning)

func _start_lightning_schedule() -> void:
	if _lightning_schedule_started:
		return
	_lightning_schedule_started = true
	_play_lightning_pairs.call_deferred()

func _play_lightning_pairs() -> void:
	var pair_count := randi_range(2, 3)
	for _index in pair_count:
		await get_tree().create_timer(randf_range(8.0, 18.0)).timeout
		if _race_finished or not is_inside_tree():
			return
		await _play_lightning_pair()

func _play_lightning_pair() -> void:
	var flash_duration := randf_range(LIGHTNING_FLASH_MIN, LIGHTNING_FLASH_MAX)
	_lightning.light_energy = randf_range(6.0, 10.0)
	await get_tree().create_timer(flash_duration).timeout
	_lightning.light_energy = 0.0

	await get_tree().create_timer(maxf(0.0, LIGHTNING_THUNDER_DELAY - flash_duration)).timeout
	if _race_finished or not is_inside_tree():
		return
	_thunder_audio.pitch_scale = randf_range(1.0, 1.05)
	_thunder_audio.volume_db = randf_range(-8.0, -6.0)
	_thunder_audio.play()
