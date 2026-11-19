class_name RaceGridSpawner
extends RefCounted

const PLAYER_CAR_SCENE: PackedScene = preload("res://scenes/player_car.tscn")
const CPU_CAR_SCENE: PackedScene = preload("res://scenes/cpu_car.tscn")
const PRIMARY_GRID_INDEX: int = 1

static func spawn(track: Node3D, preferred_driver_id: String) -> Node3D:
	var existing_cars := track.get_node_or_null("CARS") as Node3D
	if existing_cars != null:
		push_error("%s already contains a CARS node." % track.name)
		return existing_cars

	var active_driver_ids: Array[String] = RaceSelection.get_active_driver_ids()
	if active_driver_ids.is_empty():
		push_error("Cannot spawn a race without an active pilot.")
		return Node3D.new()

	var grid := track.get_node("START_GRID") as Node3D
	var cars := Node3D.new()
	cars.name = "CARS"
	track.add_child(cars)

	var ordered_driver_ids: Array[String] = _ordered_driver_ids(
		active_driver_ids,
		preferred_driver_id
	)
	var spawn_transforms: Array[Transform3D] = _get_spawn_transforms(
		track,
		grid,
		ordered_driver_ids.size()
	)
	var grid_order: Array[int] = _get_grid_order(ordered_driver_ids.size())
	var cpu_index: int = 0

	for car_index in ordered_driver_ids.size():
		var driver_id: String = ordered_driver_ids[car_index]
		var spawn_transform: Transform3D = spawn_transforms[grid_order[car_index]]
		if RaceSelection.is_driver_human(driver_id):
			_spawn_player(cars, driver_id, spawn_transform, car_index)
		else:
			_spawn_cpu(cars, driver_id, spawn_transform, car_index, cpu_index)
			cpu_index += 1

	return cars

static func _ordered_driver_ids(
	active_driver_ids: Array[String],
	preferred_driver_id: String
) -> Array[String]:
	var human_driver_ids: Array[String] = []
	var cpu_driver_ids: Array[String] = []
	for driver_id in active_driver_ids:
		if RaceSelection.is_driver_human(driver_id):
			human_driver_ids.append(driver_id)
		else:
			cpu_driver_ids.append(driver_id)

	var primary_driver_id: String
	var p1_driver_id: String = RaceSelection.get_driver_for_player_slot(0)
	if p1_driver_id in human_driver_ids:
		primary_driver_id = p1_driver_id
	elif preferred_driver_id in human_driver_ids:
		primary_driver_id = preferred_driver_id
	elif not human_driver_ids.is_empty():
		primary_driver_id = human_driver_ids[0]
	elif preferred_driver_id in cpu_driver_ids:
		primary_driver_id = preferred_driver_id
	else:
		primary_driver_id = cpu_driver_ids[0]

	var result: Array[String] = [primary_driver_id]
	for driver_id in human_driver_ids:
		if driver_id != primary_driver_id:
			result.append(driver_id)
	for driver_id in cpu_driver_ids:
		if driver_id != primary_driver_id:
			result.append(driver_id)
	return result

static func _get_grid_order(car_count: int) -> Array[int]:
	var result: Array[int] = []
	if car_count <= 0:
		return result
	if car_count == 1:
		result.append(PRIMARY_GRID_INDEX)
		return result

	result.append(PRIMARY_GRID_INDEX)
	result.append(0)
	for grid_index in range(2, car_count):
		result.append(grid_index)
	return result

static func _get_spawn_transforms(
	track: Node3D,
	grid: Node3D,
	required_count: int
) -> Array[Transform3D]:
	var marker_transforms: Array[Transform3D] = []
	var marker_index: int = 1
	while true:
		var marker := grid.get_node_or_null("GridSlot%d" % marker_index) as Marker3D
		if marker == null:
			break
		marker_transforms.append(marker.transform)
		marker_index += 1

	if marker_transforms.is_empty():
		push_error("%s has no START_GRID markers." % track.name)
		marker_transforms.append(Transform3D.IDENTITY)

	var spacing := Vector3(-1.25, 0.0, 0.0)
	if marker_transforms.size() >= 2:
		spacing = (
			marker_transforms[marker_transforms.size() - 1].origin
			- marker_transforms[marker_transforms.size() - 2].origin
		)

	while marker_transforms.size() < required_count:
		var generated := marker_transforms[marker_transforms.size() - 1]
		generated.origin += spacing
		marker_transforms.append(generated)

	var result: Array[Transform3D] = []
	var track_from_grid: Transform3D = track.global_transform.affine_inverse() * grid.global_transform
	for local_transform in marker_transforms:
		result.append(track_from_grid * local_transform)
	return result

static func _spawn_player(
	cars: Node3D,
	driver_id: String,
	spawn_transform: Transform3D,
	car_index: int
) -> void:
	var player := PLAYER_CAR_SCENE.instantiate() as PlayerCar
	var player_slot: int = RaceSelection.get_player_slot_for_driver(driver_id)
	player.name = "PlayerCar" if player_slot == 0 else "PlayerCar%d" % (player_slot + 1)
	player.driver_id = driver_id
	player.player_slot = player_slot
	player.input_source = RaceSelection.get_input_source(player_slot)
	player.transform = spawn_transform
	player.set_meta(&"race_grid_index", car_index)
	cars.add_child(player)

static func _spawn_cpu(
	cars: Node3D,
	driver_id: String,
	spawn_transform: Transform3D,
	car_index: int,
	behavior_index: int
) -> void:
	var cpu := CPU_CAR_SCENE.instantiate() as CpuCar
	cpu.name = "CpuCar%d" % (car_index + 1)
	cpu.driver_id = driver_id
	cpu.waypoint_generator_path = NodePath("../../PATH/WaypointGenerator")
	var behavior_count: int = CpuBehaviorRoster.BEHAVIOR_IDS.size()
	if behavior_count > 0:
		var behavior_id: String = CpuBehaviorRoster.BEHAVIOR_IDS[behavior_index % behavior_count]
		cpu.configure_behavior(behavior_id)
	cpu.transform = spawn_transform
	cpu.set_meta(&"race_grid_index", car_index)
	cars.add_child(cpu)
