extends Node3D

signal lap_completed(car: VehicleSphere, lap_number: int)
signal car_finished(car: VehicleSphere, lap_number: int)

@export var target_laps: int = 1

var _verified_by_car: Dictionary = {}
var _laps_by_car: Dictionary = {}
var _finished_cars: Dictionary = {}

func _ready() -> void:
	if OS.has_feature("web"):
		_adjust_web_exposure()
	_set_city_lights_enabled(RaceSelection.night_enabled)
	if RaceSelection.night_enabled:
		_apply_night_lighting()
	target_laps = RaceSelection.selected_laps
	if Debug.DEBUG_VERBOSE:
		print("START! Target laps set to: ", target_laps)

func _adjust_web_exposure() -> void:
	for node in find_children("*", "WorldEnvironment", true, false):
		var world_environment := node as WorldEnvironment
		if world_environment.environment == null:
			continue
		var local_environment := world_environment.environment.duplicate() as Environment
		local_environment.tonemap_exposure *= 2.0 / 3.0
		world_environment.environment = local_environment

func _set_city_lights_enabled(enabled: bool) -> void:
	var city_lights := get_node_or_null("CITY/LIGHTS") as Node3D
	if city_lights == null:
		return

	for node in city_lights.find_children("*", "Light3D", true, false):
		(node as Light3D).visible = enabled

func _apply_night_lighting() -> void:
	for node in find_children("*", "WorldEnvironment", true, false):
		var world_environment := node as WorldEnvironment
		if world_environment.environment == null:
			continue
		var night_environment := world_environment.environment.duplicate() as Environment
		night_environment.background_mode = Environment.BG_COLOR
		night_environment.background_color = Color(0.012, 0.014, 0.02)
		night_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		night_environment.ambient_light_color = Color(0.36, 0.37, 0.40)
		night_environment.ambient_light_energy = 0.22
		world_environment.environment = night_environment

	for node in find_children("*", "DirectionalLight3D", true, false):
		var moonlight := node as DirectionalLight3D
		moonlight.light_color = Color(0.82, 0.84, 0.9)
		moonlight.light_energy = 0.18

func _on_verif_body_entered(body: Node3D) -> void:
	if not body is VehicleSphere:
		return

	var car := body as VehicleSphere
	if _finished_cars.get(car, false) or _verified_by_car.get(car, false):
		return

	_verified_by_car[car] = true
	if Debug.DEBUG_VERBOSE:
		print("Lap verification complete for %s." % car.car_name)

func _on_finish_body_entered(body: Node3D) -> void:
	if not body is VehicleSphere:
		return

	var car := body as VehicleSphere
	if _finished_cars.get(car, false):
		return

	if not _verified_by_car.get(car, false):
		if Debug.DEBUG_VERBOSE:
			print("%s passed the finish line, but the lap was not verified." % car.car_name)
		return

	var laps_completed := int(_laps_by_car.get(car, 0)) + 1
	_laps_by_car[car] = laps_completed
	_verified_by_car[car] = false
	if Debug.DEBUG_VERBOSE:
		print("Lap completed by %s! Total laps: %d" % [car.car_name, laps_completed])
	lap_completed.emit(car, laps_completed)

	if laps_completed == target_laps:
		_finished_cars[car] = true
		car_finished.emit(car, laps_completed)
