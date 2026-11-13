extends Node3D

const WEATHER_DELAY := 5.0
const DIMMING_DURATION := 4.5
const SNOW_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const SNOW_MESH_LIBRARY: MeshLibrary = preload("res://models/Library/mesh-library-snow.tres")
const SNOW_COVER_SHADER: Shader = preload("res://shaders/snow_cover.gdshader")
const LIGHTNING_FLASH_MIN := 0.08
const LIGHTNING_FLASH_MAX := 0.16
const LIGHTNING_THUNDER_DELAY := 0.5

var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _rain_audio: AudioStreamPlayer
var _thunder_audio: AudioStreamPlayer
var _lightning: OmniLight3D
var _sun: DirectionalLight3D
var _world_environment: WorldEnvironment
var _plane_mesh: MeshInstance3D
var _original_sun_energy := 0.0
var _race_finished := false
var _lightning_schedule_started := false

func _ready() -> void:
	var track := get_parent()
	_sun = track.find_child("Sun", true, false) as DirectionalLight3D
	_world_environment = track.find_child("Environment", true, false) as WorldEnvironment
	_plane_mesh = track.get_node_or_null("Plane/MeshInstance3D") as MeshInstance3D
	if _sun != null:
		_original_sun_energy = _sun.light_energy

	if RaceSelection.selected_weather == RaceSelection.WEATHER_SNOW:
		_snow = _create_snow()
	elif RaceSelection.selected_weather == RaceSelection.WEATHER_RAIN:
		_rain = _create_rain()
		_create_audio()
		_create_lightning()

	_connect_race_signals.call_deferred()

func _connect_race_signals() -> void:
	var race_controller := get_parent().get_node_or_null("RaceController")
	if race_controller == null:
		return
	if race_controller.has_signal("race_started"):
		race_controller.race_started.connect(_on_race_started)
	if race_controller.has_signal("race_finished"):
		race_controller.race_finished.connect(_on_race_finished)

func _on_race_started() -> void:
	if RaceSelection.selected_weather == RaceSelection.WEATHER_FAIR:
		return

	await get_tree().create_timer(WEATHER_DELAY).timeout
	if not is_inside_tree() or _race_finished:
		return

	if RaceSelection.selected_weather == RaceSelection.WEATHER_SNOW:
		_snow.emitting = true
		get_tree().call_group(
			"race_vehicles",
			"start_weather_transition",
			RaceSelection.WEATHER_SNOW,
			RaceSelection.WEATHER_TRANSITION_DURATION
		)
		_start_snow_cover()
		_start_plane_snow_cover()
		_start_building_snow_cover()
		return

	_apply_overcast_lighting()
	_rain.emitting = true
	_rain_audio.play()
	_rain_audio.volume_db = -9.0
	_start_lightning_schedule()

func _on_race_finished(_standings: Array) -> void:
	_race_finished = true
	if _rain != null:
		_rain.emitting = false
	if _snow != null:
		_snow.emitting = false
	if _rain_audio != null:
		_rain_audio.stop()
	if _thunder_audio != null:
		_thunder_audio.stop()
	if _lightning != null:
		_lightning.light_energy = 0.0

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

func _start_snow_cover() -> void:
	var grid_map := get_parent().get_node_or_null("GridMap") as GridMap
	if grid_map == null:
		return

	grid_map.mesh_library = SNOW_MESH_LIBRARY
	var snow_materials: Array[ShaderMaterial] = []
	for item in SNOW_MESH_LIBRARY.get_item_list():
		if not SNOW_MESH_LIBRARY.get_item_name(item).begins_with("track-"):
			continue
		var snow_mesh := SNOW_MESH_LIBRARY.get_item_mesh(item) as ArrayMesh
		if snow_mesh == null:
			continue
		for surface_index in snow_mesh.get_surface_count():
			var snow_material := snow_mesh.surface_get_material(surface_index) as ShaderMaterial
			if snow_material != null and snow_material not in snow_materials:
				snow_materials.append(snow_material)
	_animate_snow_materials(snow_materials)

func _start_plane_snow_cover() -> void:
	if _plane_mesh == null or _plane_mesh.mesh == null or _plane_mesh.mesh.get_surface_count() == 0:
		return

	var source_material := _plane_mesh.get_active_material(0) as StandardMaterial3D
	var snow_material := StandardMaterial3D.new()
	if source_material != null:
		snow_material = source_material.duplicate() as StandardMaterial3D
	snow_material.albedo_texture = null
	snow_material.roughness = 1.0
	_plane_mesh.material_override = snow_material

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(
		snow_material,
		"albedo_color",
		SNOW_COLOR,
		RaceSelection.WEATHER_TRANSITION_DURATION
	)

func _start_building_snow_cover() -> void:
	var buildings := get_parent().get_node_or_null("CITY/BUILDINGS") as Node3D
	if buildings == null:
		return

	var snow_materials: Array[ShaderMaterial] = []
	for block_node in buildings.find_children("Block*", "MeshInstance3D", true, false):
		var block := block_node as MeshInstance3D
		if block == null or block.mesh == null or block.mesh.get_surface_count() == 0:
			continue

		var snow_material := ShaderMaterial.new()
		snow_material.shader = SNOW_COVER_SHADER
		snow_material.set_shader_parameter("snow_color", SNOW_COLOR)
		snow_material.set_shader_parameter("snow_upward_only", true)

		var source_material := block.get_active_material(0) as StandardMaterial3D
		if source_material != null:
			snow_material.set_shader_parameter("base_color", source_material.albedo_color)
			if source_material.albedo_texture != null:
				snow_material.set_shader_parameter("base_texture", source_material.albedo_texture)
				snow_material.set_shader_parameter("use_base_texture", true)

		block.material_override = snow_material
		snow_materials.append(snow_material)

	if not snow_materials.is_empty():
		_animate_snow_materials(snow_materials)

func _animate_snow_materials(materials: Array[ShaderMaterial]) -> void:
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	for material in materials:
		tween.tween_method(
			_set_snow_amount.bind(material),
			0.0,
			1.0,
			RaceSelection.WEATHER_TRANSITION_DURATION
		)
	await tween.finished
	for material in materials:
		material.set_shader_parameter("snow_amount", 1.0)

func _set_snow_amount(amount: float, material: ShaderMaterial) -> void:
	material.set_shader_parameter("snow_amount", amount)

func _create_rain() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Rain"
	particles.amount = 2400
	particles.lifetime = 1.25
	particles.preprocess = 1.25
	particles.visibility_aabb = AABB(Vector3(-70.0, -30.0, -70.0), Vector3(140.0, 80.0, 140.0))
	particles.position = Vector3(0.0, 28.0, 0.0)

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
	particles.process_material = process_material

	var drop_mesh := BoxMesh.new()
	drop_mesh.size = Vector3(0.025, 0.7, 0.025)
	var drop_material := StandardMaterial3D.new()
	drop_material.albedo_color = Color(0.5, 0.7, 0.9, 0.72)
	drop_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop_mesh.material = drop_material
	particles.draw_pass_1 = drop_mesh
	particles.emitting = false
	add_child(particles)
	return particles

func _create_snow() -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Snow"
	particles.amount = 1200
	particles.lifetime = 3.5
	particles.preprocess = 3.5
	particles.visibility_aabb = AABB(Vector3(-70.0, -30.0, -70.0), Vector3(140.0, 80.0, 140.0))
	particles.position = Vector3(0.0, 28.0, 0.0)

	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(60.0, 0.5, 60.0)
	process_material.direction = Vector3(0.0, -1.0, 0.0)
	process_material.spread = 12.0
	process_material.gravity = Vector3(0.0, -1.8, 0.0)
	process_material.initial_velocity_min = 1.5
	process_material.initial_velocity_max = 3.0
	process_material.scale_min = 0.55
	process_material.scale_max = 1.4
	particles.process_material = process_material

	var flake_mesh := SphereMesh.new()
	flake_mesh.radius = 0.08
	flake_mesh.height = 0.16
	flake_mesh.radial_segments = 8
	flake_mesh.rings = 4
	var flake_material := StandardMaterial3D.new()
	flake_material.albedo_color = Color(0.94, 0.98, 1.0, 1.0)
	flake_material.roughness = 0.85
	flake_mesh.material = flake_material
	particles.draw_pass_1 = flake_mesh
	particles.emitting = false
	add_child(particles)
	return particles

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
	_thunder_audio.volume_db = randf_range(-12.0, -10.0)
	_thunder_audio.play()
