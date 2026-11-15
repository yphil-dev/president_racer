class_name RaceGridSpawner
extends RefCounted

const PLAYER_CAR_SCENE: PackedScene = preload("res://scenes/player_car.tscn")
const CPU_CAR_SCENE: PackedScene = preload("res://scenes/cpu_car.tscn")

const PLAYER_SLOT := "GridSlot2"
const CPU_SLOTS: Array[String] = ["GridSlot1", "GridSlot3", "GridSlot4"]

static func spawn(track: Node3D, selected_driver_id: String) -> Node3D:
	if not DriverRoster.has_driver(selected_driver_id):
		push_error("Unknown selected driver %s; using Soral." % selected_driver_id)
		selected_driver_id = "soral"

	var existing_cars := track.get_node_or_null("CARS") as Node3D
	if existing_cars != null:
		push_error("%s already contains a CARS node." % track.name)
		return existing_cars

	var grid := track.get_node("START_GRID") as Node3D
	var cars := Node3D.new()
	cars.name = "CARS"
	track.add_child(cars)

	var human_driver_ids: Array[String] = []
	var cpu_driver_ids: Array[String] = []
	for driver_id in DriverRoster.DRIVER_IDS:
		if RaceSelection.get_control_scheme(driver_id) == RaceSelection.CONTROL_CPU:
			cpu_driver_ids.append(driver_id)
		else:
			human_driver_ids.append(driver_id)

	if _all_drivers_cpu():
		_spawn_cpu(cars, track, grid, selected_driver_id, PLAYER_SLOT, 1, 0)
		for index in CPU_SLOTS.size():
			_spawn_cpu(
				cars,
				track,
				grid,
				cpu_driver_ids[index],
				CPU_SLOTS[index],
				index + 2,
				index
			)
	else:
		var primary_human_id := selected_driver_id
		if RaceSelection.get_control_scheme(primary_human_id) == RaceSelection.CONTROL_CPU:
			primary_human_id = human_driver_ids[0]
		_spawn_player(cars, track, grid, primary_human_id, PLAYER_SLOT, 1, true)

		var remaining_slot_index := 0
		var next_car_number := 2
		for driver_id in human_driver_ids:
			if driver_id == primary_human_id:
				continue
			_spawn_player(
				cars,
				track,
				grid,
				driver_id,
				CPU_SLOTS[remaining_slot_index],
				next_car_number,
				false
			)
			remaining_slot_index += 1
			next_car_number += 1

		for index in cpu_driver_ids.size():
			_spawn_cpu(
				cars,
				track,
				grid,
				cpu_driver_ids[index],
				CPU_SLOTS[remaining_slot_index],
				next_car_number,
				index
			)
			remaining_slot_index += 1
			next_car_number += 1

	return cars

static func _all_drivers_cpu() -> bool:
	for driver_id in DriverRoster.DRIVER_IDS:
		if RaceSelection.get_control_scheme(driver_id) != RaceSelection.CONTROL_CPU:
			return false
	return true

static func _spawn_player(
	cars: Node3D,
	track: Node3D,
	grid: Node3D,
	driver_id: String,
	slot_name: String,
	car_number: int,
	primary: bool
) -> void:
	var player := PLAYER_CAR_SCENE.instantiate() as PlayerCar
	player.name = "PlayerCar" if primary else "PlayerCar%d" % car_number
	player.driver_id = driver_id
	player.control_scheme = RaceSelection.get_control_scheme(driver_id)
	player.transform = _spawn_transform(track, grid.get_node(slot_name) as Marker3D)
	cars.add_child(player)

static func _spawn_cpu(
	cars: Node3D,
	track: Node3D,
	grid: Node3D,
	driver_id: String,
	slot_name: String,
	car_number: int,
	behavior_index: int
) -> void:
	var cpu := CPU_CAR_SCENE.instantiate() as CpuCar
	cpu.name = "CpuCar%d" % car_number
	cpu.driver_id = driver_id
	cpu.waypoint_generator_path = NodePath("../../PATH/WaypointGenerator")
	cpu.configure_behavior(CpuBehaviorRoster.BEHAVIOR_IDS[behavior_index])
	cpu.transform = _spawn_transform(track, grid.get_node(slot_name) as Marker3D)
	cars.add_child(cpu)

static func _spawn_transform(track: Node3D, marker: Marker3D) -> Transform3D:
	return track.global_transform.affine_inverse() * marker.global_transform
