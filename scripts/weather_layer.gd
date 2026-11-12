extends Node3D

const WEATHER_DELAY := 5.0
const DARKNESS_DURATION := 2.5
const RAIN_DELAY_AFTER_DARKNESS := 5.0

var _rain: GPUParticles3D
var _sun: DirectionalLight3D
var _world_environment: WorldEnvironment
var _original_sun_energy := 0.0
var _weather_active := false

func _ready() -> void:
	_sun = get_node_or_null("../View/Sun") as DirectionalLight3D
	_world_environment = get_node_or_null("../View/Environment") as WorldEnvironment
	if _sun != null:
		_original_sun_energy = _sun.light_energy
	_create_rain()
	_rain.emitting = false
	_connect_race_started.call_deferred()

func _process(_delta: float) -> void:
	if _weather_active:
		_anchor_to_camera()

func _connect_race_started() -> void:
	var race_controller := get_parent().get_node_or_null("RaceController")
	if race_controller == null or not race_controller.has_signal("race_started"):
		return
	race_controller.race_started.connect(_on_race_started)

func _on_race_started() -> void:
	if RaceSelection.selected_weather != RaceSelection.WEATHER_RAIN:
		return

	await get_tree().create_timer(WEATHER_DELAY).timeout
	if not is_inside_tree():
		return

	_anchor_to_camera()
	_weather_active = true
	await _apply_overcast_lighting()

	await get_tree().create_timer(RAIN_DELAY_AFTER_DARKNESS).timeout
	if is_inside_tree():
		_rain.emitting = true

func _anchor_to_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	global_position = Vector3(camera.global_position.x, 0.0, camera.global_position.z)

func _apply_overcast_lighting() -> void:
	if _world_environment != null and _world_environment.environment != null:
		var overcast_environment := _world_environment.environment.duplicate() as Environment
		overcast_environment.ambient_light_energy *= 0.7
		overcast_environment.tonemap_exposure *= 0.9
		_world_environment.environment = overcast_environment

	if _sun == null:
		return

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_sun, "light_energy", _original_sun_energy * 0.62, DARKNESS_DURATION)
	await tween.finished

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
