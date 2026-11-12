extends Node3D

const WEATHER_DELAY := 5.0
const DIMMING_DURATION := 4.5
const SNOW_COVER_DURATION := 3.0
const SNOW_COLOR := Color(0.94, 0.96, 1.0, 1.0)
const SNOW_WASH_COLOR := Color(4.0, 4.0, 4.0, 1.0)
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
var _weather_active := false
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
	if RaceSelection.selected_weather == RaceSelection.WEATHER_FAIR:
		return

	await get_tree().create_timer(WEATHER_DELAY).timeout
	if not is_inside_tree() or _race_finished:
		return

	_anchor_to_camera()
	_weather_active = true
	if RaceSelection.selected_weather == RaceSelection.WEATHER_SNOW:
		_snow.emitting = true
		_start_snow_cover()
		_start_plane_snow_cover()
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

func _start_snow_cover() -> void:
	var grid_map := get_parent().get_node_or_null("GridMap") as GridMap
	if grid_map == null or grid_map.mesh_library == null:
		return

	var snow_library := grid_map.mesh_library.duplicate(true) as MeshLibrary
	var snow_materials: Array[StandardMaterial3D] = []
	for item in snow_library.get_item_list():
		if not snow_library.get_item_name(item).begins_with("track-"):
			continue

		var snow_mesh := snow_library.get_item_mesh(item).duplicate(true) as ArrayMesh
		if snow_mesh == null:
			continue
		for surface_index in snow_mesh.get_surface_count():
			var source_material := snow_mesh.surface_get_material(surface_index) as StandardMaterial3D
			var snow_material := StandardMaterial3D.new()
			if source_material != null:
				snow_material = source_material.duplicate() as StandardMaterial3D
			snow_material.roughness = 1.0
			snow_mesh.surface_set_material(surface_index, snow_material)
			snow_materials.append(snow_material)
		snow_library.set_item_mesh(item, snow_mesh)

	var cells: Array[Dictionary] = []
	for cell in grid_map.get_used_cells():
		cells.append({
			"position": cell,
			"item": grid_map.get_cell_item(cell),
			"orientation": grid_map.get_cell_item_orientation(cell),
		})

	grid_map.clear()
	grid_map.mesh_library = snow_library
	for cell_data in cells:
		grid_map.set_cell_item(
			cell_data["position"],
			cell_data["item"],
			cell_data["orientation"]
		)
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
	tween.tween_property(snow_material, "albedo_color", SNOW_COLOR, SNOW_COVER_DURATION)

func _animate_snow_materials(materials: Array[StandardMaterial3D]) -> void:
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	for material in materials:
		tween.tween_property(material, "albedo_color", SNOW_WASH_COLOR, SNOW_COVER_DURATION)
	await tween.finished
	for material in materials:
		material.albedo_texture = null
		material.albedo_color = SNOW_COLOR

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
	_thunder_audio.volume_db = randf_range(-8.0, -6.0)
	_thunder_audio.play()
