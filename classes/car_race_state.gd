class_name CarRaceState
extends RefCounted

var vehicle: Vehicle
var car: VehicleSphere

var laps_completed: int = 0
var target_laps: int = 1
var track_progress: float = 0.0
var total_progress: float = 0.0
var waypoint_segment_index: int = -1
var current_time: float = 0.0
var last_lap_time: float = 0.0
var best_lap_time: float = -1.0
var finish_time: float = -1.0
var rank: int = 0
var finished: bool = false
var winner: bool = false
var dnf: bool = false

var _last_lap_timestamp: float = 0.0

func _init(p_vehicle: Vehicle, p_target_laps: int) -> void:
	vehicle = p_vehicle
	car = vehicle.get_node("Sphere") as VehicleSphere
	target_laps = maxi(1, p_target_laps)

func record_lap(lap_number: int, race_time: float) -> void:
	laps_completed = lap_number
	last_lap_time = race_time - _last_lap_timestamp
	if best_lap_time < 0.0 or last_lap_time < best_lap_time:
		best_lap_time = last_lap_time
	_last_lap_timestamp = race_time
	current_time = race_time

func record_finish(race_time: float) -> void:
	finished = true
	finish_time = race_time
	current_time = race_time

func mark_dnf(race_time: float) -> void:
	dnf = true
	current_time = race_time
