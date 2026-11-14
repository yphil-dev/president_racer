class_name VehicleSphere extends RigidBody3D

@export var max_angular_velocity: float = 50.0

# Driver identity is assigned by Vehicle from DriverRoster.
var car_name: String = "Driver"
var car_number: int = -1

func _ready() -> void:
	# Ensure contact monitor is on if you still rely on _on_sphere_body_entered
	contact_monitor = true
	max_contacts_reported = 4

func race_completed(num_laps: int, race_time: float) -> void:
	if Debug.DEBUG_VERBOSE:
		print("Race completed by %s! %d laps in %.2f" % [car_name, num_laps, race_time])

func lap_completed(num_lap: int, lap_time: float, race_time: float) -> void:
	var info := LapCompleteData.new(self, num_lap, lap_time, race_time)
	if Debug.DEBUG_VERBOSE:
		print("Lap completed! ", info)
	EventHub.emitOnLapCompleted(info)
