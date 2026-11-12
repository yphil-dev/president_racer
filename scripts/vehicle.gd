class_name Vehicle extends Node3D

@export_category("Handling")
@export var max_forward_speed: float = 1.0
@export var max_reverse_speed: float = 0.5
@export var forward_acceleration: float = 6.0
@export var reverse_acceleration: float = 2.0
@export var braking: float = 8.0
@export var steering_strength: float = 4.0
@export var steering_response: float = 4.0
@export var minimum_steering_grip: float = 0.2
@export var drive_torque: float = 100.0
@export var air_input_decay: float = 2.0

const FAIR_BRAKING := 10.0
const FAIR_FRICTION := 6.0
const RAIN_BRAKING := 8.0
const RAIN_FRICTION := 5.0
const SNOW_BRAKING := 5.5
const SNOW_FRICTION := 2.0

@export_category("Skidmarks")
@export var skidmarks_enabled: bool = true
@export_range(0.05, 1.0, 0.05) var rear_skid_threshold: float = 0.3
@export_range(0.1, 1.0, 0.05) var severe_lateral_ratio: float = 0.5
@export_range(0.1, 1.0, 0.05) var skidmark_minimum_speed: float = 0.2
@export_range(0.05, 0.5, 0.01) var wheel_ray_start_offset: float = 0.18
@export_range(0.2, 1.0, 0.05) var wheel_ray_length: float = 0.5

@export_category("Driver")
@export var driver_id: String = ""

var driver_name: String = "Driver"
var car_number: int = -1
var portrait: Texture2D
var car_color: Color = Color.WHITE

@export_category("Race")
@export var driving_enabled: bool = false

# Nodes

# ─── KEY CHANGE: Explicitly typed as your new VehicleSphere class ───
@onready var sphere: VehicleSphere = $Sphere
@onready var raycast: RayCast3D = $Ground

# Vehicle elements

@onready var vehicle_model = $Container
@onready var vehicle_body = _find_visible_model_part("body")

# (Optional) wheels

@onready var wheel_fl = _find_visible_model_part("wheel-front-left")
@onready var wheel_fr = _find_visible_model_part("wheel-front-right")
@onready var wheel_bl = _find_visible_model_part("wheel-back-left")
@onready var wheel_br = _find_visible_model_part("wheel-back-right")

# Effects

@onready var trail_left = get_node_or_null("Container/TrailLeft")
@onready var trail_right = get_node_or_null("Container/TrailRight")
@onready var headlights: Node3D = $Container/Lights/HeadLights
@onready var skidmark_emitter: Node = $SkidmarkEmitter
var rear_lamp_material: StandardMaterial3D
var _rear_lamp_hold_remaining: float = 0.0
var _finish_coast_distance: float = 0.0
var _finish_coast_start: Vector3
var _finish_coast_speed: float = 0.0
var _race_finished: bool = false
const REAR_LAMP_HOLD_DURATION: float = 0.4

# Sounds

@onready var screech_sound: AudioStreamPlayer3D = $Container/ScreechSound
@onready var engine_sound: AudioStreamPlayer3D = $Container/EngineSound
@onready var impact_sound: AudioStreamPlayer3D = $Container/ImpactSound

# Verif

var _verification_count: int = 0
var _verified: bool = false

# Time


var input: Vector3
var normal: Vector3

var acceleration: float
var angular_speed: float
var linear_speed: float

var colliding: bool

var linear_velocity: Vector3
var prev_position: Vector3

var calculated_lean: float

# Public Functions

func get_vehicle_position() -> Vector3: return vehicle_model.global_position

func set_driving_enabled(enabled: bool) -> void:
	driving_enabled = enabled
	if driving_enabled:
		_race_finished = false
		_finish_coast_distance = 0.0
	elif not driving_enabled:
		input = Vector3.ZERO
		linear_speed = 0.0
		angular_speed = 0.0

func begin_finish_coast(distance: float) -> void:
	_race_finished = true
	_finish_coast_distance = maxf(distance, 0.0)
	_finish_coast_start = sphere.global_position
	_finish_coast_speed = maxf(linear_speed, 0.25)
	_rear_lamp_hold_remaining = 0.0
	effect_brake_lights(false)
	driving_enabled = _finish_coast_distance > 0.0
	if not driving_enabled:
		set_driving_enabled(false)

# Functions

func _apply_weather_handling() -> void:
	var target_braking := RAIN_BRAKING
	var target_friction := RAIN_FRICTION
	match RaceSelection.selected_weather:
		RaceSelection.WEATHER_FAIR:
			target_braking = FAIR_BRAKING
			target_friction = FAIR_FRICTION
		RaceSelection.WEATHER_SNOW:
			target_braking = SNOW_BRAKING
			target_friction = SNOW_FRICTION

	braking = target_braking
	var weather_material: PhysicsMaterial = sphere.physics_material_override
	if weather_material != null:
		weather_material = weather_material.duplicate() as PhysicsMaterial
	else:
		weather_material = PhysicsMaterial.new()
	weather_material.friction = target_friction
	sphere.physics_material_override = weather_material

func _find_visible_model_part(part_name: String) -> MeshInstance3D:
	var container := get_node_or_null("Container")
	if container == null:
		return null

	var fallback: MeshInstance3D
	for node in container.find_children(part_name, "MeshInstance3D", true, false):
		var mesh_part := node as MeshInstance3D
		if fallback == null:
			fallback = mesh_part
		if mesh_part.is_visible_in_tree():
			return mesh_part

	return fallback

func _enter_tree() -> void:
	add_to_group("race_vehicles")

func _ready() -> void:
	headlights.visible = RaceSelection.night_enabled
	_apply_weather_handling()

	var profile := DriverRoster.get_profile(driver_id)
	if not profile.is_empty():
		driver_name = profile["display_name"]
		car_number = profile["car_number"]
		portrait = profile["portrait"]
		car_color = profile["car_color"]

	sphere.car_name = driver_name
	sphere.car_number = car_number

	if vehicle_body is MeshInstance3D:
		var body_mesh := vehicle_body as MeshInstance3D
		var imported_material := body_mesh.get_active_material(0) as StandardMaterial3D
		if imported_material != null:
			var unique_material := imported_material.duplicate() as StandardMaterial3D
			if imported_material.albedo_texture != null:
				unique_material.albedo_texture = VehiclePaletteTextures.get_texture(car_color)
				unique_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			else:
				unique_material.albedo_color = car_color
			unique_material.metallic = 0.05
			unique_material.roughness = 0.48
			body_mesh.set_surface_override_material(0, unique_material)

		for surface_index in body_mesh.mesh.get_surface_count():
			if body_mesh.mesh.surface_get_name(surface_index) != "Glow-red":
				continue
			var lamp_material := body_mesh.get_active_material(surface_index) as StandardMaterial3D
			if lamp_material != null:
				rear_lamp_material = lamp_material.duplicate() as StandardMaterial3D
				rear_lamp_material.albedo_color = Color(0.24, 0.015, 0.015)
				rear_lamp_material.emission = Color(1.0, 0.015, 0.01)
				rear_lamp_material.emission_energy_multiplier = 3.0
				body_mesh.set_surface_override_material(surface_index, rear_lamp_material)
			break

func _physics_process(delta):

	if _finish_coast_distance > 0.0:
		var finish_offset := sphere.global_position - _finish_coast_start
		finish_offset.y = 0.0
		if finish_offset.length() >= _finish_coast_distance:
			_finish_coast_distance = 0.0
			set_driving_enabled(false)

	handle_input(delta)

	var direction = sign(linear_speed)
	if direction == 0: direction = sign(input.z) if abs(input.z) > 0.1 else 1

	var steering_grip = clamp(abs(linear_speed), minimum_steering_grip, 1.0)

	var target_angular = -input.x * steering_grip * steering_strength * direction
	angular_speed = lerp(angular_speed, target_angular, delta * steering_response)

	vehicle_model.rotate_y(angular_speed * delta)

	# Ground alignment

	if raycast.is_colliding():
		if !colliding:
			if vehicle_body != null: vehicle_body.position = Vector3(0, 0.1, 0) # Bounce
			input.z = 0

		normal = raycast.get_collision_normal()

		# Orient model to colliding normal

		if normal.dot(vehicle_model.global_basis.y) > 0.5:
			var xform = align_with_y(vehicle_model.global_transform, normal)
			vehicle_model.global_transform = vehicle_model.global_transform.interpolate_with(xform, 0.2).orthonormalized()

	colliding = raycast.is_colliding()

	var target_speed = input.z * (max_forward_speed if input.z >= 0.0 else max_reverse_speed)
	var rear_lamps_on := not _race_finished and (
		input.z <= 0.1 or (linear_speed > 0.05 and target_speed < linear_speed - 0.05)
	)
	if _race_finished:
		_rear_lamp_hold_remaining = 0.0
	elif rear_lamps_on:
		_rear_lamp_hold_remaining = REAR_LAMP_HOLD_DURATION
	else:
		_rear_lamp_hold_remaining = maxf(0.0, _rear_lamp_hold_remaining - delta)

	if (target_speed < 0 and linear_speed > 0.01):
		linear_speed = lerp(linear_speed, 0.0, delta * braking)
	else:
		if (target_speed < 0):
			linear_speed = lerp(linear_speed, target_speed, delta * reverse_acceleration)
		else:
			linear_speed = lerp(linear_speed, target_speed, delta * forward_acceleration)

	acceleration = lerpf(acceleration, linear_speed + (abs(sphere.angular_velocity.length() * linear_speed) / 100), delta * 1)

	# Match vehicle model to physics sphere

	vehicle_model.position = sphere.position - Vector3(0, 0.65, 0)
	raycast.position = sphere.position

	# Calculate vehicle model linear velocity

	linear_velocity = (vehicle_model.position - prev_position) / delta
	prev_position = vehicle_model.position

	effect_engine(delta)
	effect_body(delta)
	effect_wheels(delta)
	effect_brake_lights(rear_lamps_on or _rear_lamp_hold_remaining > 0.0)
	var drift_intensity := effect_trails()
	effect_skidmarks(drift_intensity)

# Override this in player/CPU subclasses to provide steering and throttle.
func get_control_input() -> Vector2:
	return Vector2.ZERO

# Apply controls when the vehicle is colliding with the ground.
func handle_input(delta):

	if _finish_coast_distance > 0.0:
		input.x = 0.0
		input.z = clampf(_finish_coast_speed / maxf(max_forward_speed, 0.001), 0.1, 1.0)
		if raycast.is_colliding():
			sphere.angular_velocity += vehicle_model.get_global_transform().basis.x * (
				linear_speed * drive_torque
			) * delta
		else:
			input = input.lerp(Vector3.ZERO, delta * air_input_decay)
		return

	if not driving_enabled:
		input = Vector3.ZERO
		linear_speed = 0.0
		angular_speed = 0.0
		sphere.angular_velocity = Vector3.ZERO
		var locked_velocity := sphere.linear_velocity
		locked_velocity.x = 0.0
		locked_velocity.z = 0.0
		sphere.linear_velocity = locked_velocity
		return

	if raycast.is_colliding():
		var controls := get_control_input()
		input.x = controls.x
		input.z = controls.y
		sphere.angular_velocity += vehicle_model.get_global_transform().basis.x * (linear_speed * drive_torque) * delta
	else:
		# Gradually clear inputs in the air so physics calculation doesn't skyrocket
		input = input.lerp(Vector3.ZERO, delta * air_input_decay)

func effect_body(delta):

	calculated_lean = lerp_angle(calculated_lean, -input.x / 5 * linear_speed, delta * 5)

	# Slightly tilt (and move) body based on acceleration and steering

	if vehicle_body != null:

		vehicle_body.rotation.x = lerp_angle(vehicle_body.rotation.x, -(linear_speed - acceleration) / 6, delta * 10)
		vehicle_body.rotation.z = calculated_lean

		vehicle_body.position = vehicle_body.position.lerp(Vector3(0, 0.2, 0), delta * 5)

func effect_brake_lights(enabled: bool) -> void:
	if rear_lamp_material != null:
		rear_lamp_material.emission_enabled = enabled

func effect_wheels(delta):

	# Rotate wheels based on acceleration

	for wheel in [wheel_fl, wheel_fr, wheel_bl, wheel_br]:
		if wheel != null:
			wheel.rotation.x += acceleration

	# Rotate front wheels based on steering direction

	if wheel_fl != null: wheel_fl.rotation.y = lerp_angle(wheel_fl.rotation.y, -input.x / 1.5, delta * 10)
	if wheel_fr != null: wheel_fr.rotation.y = lerp_angle(wheel_fr.rotation.y, -input.x / 1.5, delta * 10)

# Engine sounds

func effect_engine(delta):

	var speed_factor = clamp(abs(linear_speed), 0.0, 1.0)
	var throttle_factor = clamp(abs(input.z), 0.0, 1.0)

	var target_volume = remap(speed_factor + (throttle_factor * 0.5), 0.0, 1.5, -15.0, -5.0)
	engine_sound.volume_db = lerp(engine_sound.volume_db, target_volume, delta * 5.0)

	var target_pitch = remap(speed_factor, 0.0, 1.0, 0.5, 3)
	if throttle_factor > 0.1: target_pitch += 0.2

	engine_sound.pitch_scale = lerp(engine_sound.pitch_scale, target_pitch, delta * 2.0)

func effect_trails() -> float:
	if not raycast.is_colliding():
		# if trail_left != null: trail_left.emitting = false
		# if trail_right != null: trail_right.emitting = false
		screech_sound.volume_db = -80.0
		return 0.0

	var turn_intensity := absf(input.x) * absf(linear_speed)
	var speed_change_intensity := absf(linear_speed - acceleration)
	var drift_intensity := maxf(turn_intensity, speed_change_intensity)
	var should_emit := absf(linear_speed) > 0.2 and drift_intensity > 0.2

	if trail_left != null: trail_left.emitting = should_emit
	if trail_right != null: trail_right.emitting = should_emit

	var target_volume := -80.0
	if should_emit:
		target_volume = remap(clampf(drift_intensity, 0.2, 1.0), 0.2, 1.0, -6.0, 2.0)

	screech_sound.pitch_scale = lerp(screech_sound.pitch_scale, clamp(abs(linear_speed), 1.0, 3.0), 0.1)
	screech_sound.volume_db = lerp(screech_sound.volume_db, target_volume, 10.0 * get_physics_process_delta_time())
	return drift_intensity

func effect_skidmarks(drift_intensity: float) -> void:
	if not skidmarks_enabled or not driving_enabled or not raycast.is_colliding():
		skidmark_emitter.stop_all()
		return

	var up: Vector3 = vehicle_model.global_basis.y.normalized()
	var right: Vector3 = vehicle_model.global_basis.x.normalized()
	var planar_velocity: Vector3 = sphere.linear_velocity - up * sphere.linear_velocity.dot(up)
	var actual_speed: float = planar_velocity.length()
	var lateral_speed: float = absf(planar_velocity.dot(right))
	var lateral_ratio: float = lateral_speed / maxf(actual_speed, 0.1)
	var moving_fast_enough := absf(linear_speed) >= skidmark_minimum_speed
	var rear_marking := moving_fast_enough and (
		drift_intensity >= rear_skid_threshold or lateral_ratio >= rear_skid_threshold
	)
	var hard_braking := input.z < -0.1 and linear_speed > skidmark_minimum_speed
	var front_marking := rear_marking and (
		hard_braking or lateral_ratio >= severe_lateral_ratio
	)

	_update_wheel_skidmark(0, wheel_fl, front_marking)
	_update_wheel_skidmark(1, wheel_fr, front_marking)
	_update_wheel_skidmark(2, wheel_bl, rear_marking)
	_update_wheel_skidmark(3, wheel_br, rear_marking)

func _update_wheel_skidmark(
	tire_index: int,
	wheel: MeshInstance3D,
	marking: bool
) -> void:
	if not marking or wheel == null:
		skidmark_emitter.stop_tire(tire_index)
		return

	var up: Vector3 = vehicle_model.global_basis.y.normalized()
	var origin: Vector3 = wheel.global_position + up * wheel_ray_start_offset
	var destination: Vector3 = origin - up * wheel_ray_length
	var query := PhysicsRayQueryParameters3D.create(origin, destination, 1)
	query.exclude = [sphere.get_rid()]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		skidmark_emitter.stop_tire(tire_index)
		return

	skidmark_emitter.add_contact(tire_index, hit.position, hit.normal)

# Align vehicle with normal

func align_with_y(xform, new_y):

	xform.basis.y = new_y
	xform.basis.x = -xform.basis.z.cross(new_y)
	xform.basis = xform.basis.orthonormalized()
	return xform

# Detect collisions and play impact sound

func _on_sphere_body_entered(_body: Node) -> void:

	if vehicle_body == null or not driving_enabled or impact_sound.playing:
		return

	var impact_velocity := maxf(linear_velocity.length(), sphere.linear_velocity.length())
	if impact_velocity < 1.0:
		return

	impact_sound.volume_db = clampf(
		remap(impact_velocity, 1.0, 8.0, -10.0, 2.0),
		-10.0,
		2.0
	)
	impact_sound.play()
