class_name AIWaypointGenerator
extends Node3D

signal waypoints_ready

const AI_BOUNDARY_MASK: int = 1 << 4

@export_range(0.5, 20.0, 0.5, "or_greater") var waypoint_spacing: float = 3.0
@export_range(1.0, 100.0, 0.5, "or_greater") var ray_length: float = 20.0
@export_range(0.0, 5.0, 0.1, "or_greater") var ray_height: float = 0.5
@export_range(0.5, 20.0, 0.5, "or_greater") var fallback_half_width: float = 3.0
@export var show_debug_lines: bool = true
@export var show_debug_labels: bool = false
@export_range(1.0, 30.0, 0.5, "or_greater") var debug_wide_threshold: float = 10.0

@onready var boundary_builder: AIBoundaryBuilder = get_parent()
@onready var track_path: Path3D = $"../TrackPath"

var waypoints: Array[TrackWaypoint] = []
var is_ready: bool = false
var ray_miss_count: int = 0

func _ready() -> void:
	if not boundary_builder.is_ready:
		await boundary_builder.boundaries_ready

	_generate_waypoints()
	if show_debug_lines:
		_create_debug_lines()
		if show_debug_labels:
			_create_debug_labels()

	is_ready = true
	waypoints_ready.emit()
	print("AI waypoints ready: %d waypoints, %d ray misses" % [waypoints.size(), ray_miss_count])

func _generate_waypoints() -> void:
	waypoints.clear()
	ray_miss_count = 0

	var curve := track_path.curve
	if curve == null or curve.point_count < 2:
		push_error("%s requires a Curve3D with at least two points." % track_path.get_path())
		return

	var curve_length := curve.get_baked_length()
	if curve_length <= 0.0:
		push_error("%s has no baked length." % track_path.get_path())
		return

	var sample_count := maxi(3, ceili(curve_length / waypoint_spacing))
	var tangent_distance := minf(waypoint_spacing * 0.25, 0.5)
	var space_state := get_world_3d().direct_space_state

	for index in sample_count:
		var distance := curve_length * float(index) / float(sample_count)
		var center := _sample_global_position(curve, distance, curve_length)
		var before := _sample_global_position(curve, distance - tangent_distance, curve_length)
		var after := _sample_global_position(curve, distance + tangent_distance, curve_length)
		var forward := (after - before).normalized()
		var right := Vector3.UP.cross(forward).normalized()

		var left_hit := _cast_boundary(space_state, center, -right)
		var right_hit := _cast_boundary(space_state, center, right)

		var waypoint := TrackWaypoint.new()
		waypoint.index = index
		waypoint.distance = distance
		waypoint.center = center
		waypoint.forward = forward
		waypoint.left_valid = not left_hit.is_empty()
		waypoint.right_valid = not right_hit.is_empty()
		waypoint.left_edge = _edge_position(left_hit, center, -right)
		waypoint.right_edge = _edge_position(right_hit, center, right)

		if not waypoint.left_valid:
			ray_miss_count += 1
		if not waypoint.right_valid:
			ray_miss_count += 1

		waypoints.append(waypoint)

func _sample_global_position(curve: Curve3D, distance: float, curve_length: float) -> Vector3:
	var wrapped_distance := fposmod(distance, curve_length)
	return track_path.to_global(curve.sample_baked(wrapped_distance, true))

func _cast_boundary(
	space_state: PhysicsDirectSpaceState3D,
	center: Vector3,
	direction: Vector3
) -> Dictionary:
	var origin := center + Vector3.UP * ray_height
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * ray_length,
		AI_BOUNDARY_MASK
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space_state.intersect_ray(query)

func _edge_position(hit: Dictionary, center: Vector3, direction: Vector3) -> Vector3:
	if hit.is_empty():
		return center + direction * fallback_half_width

	var position: Vector3 = hit.position
	position.y = center.y
	return position

func _create_debug_lines() -> void:
	var debug_mesh := ImmediateMesh.new()

	var corridor_material := _debug_material(Color(0.1, 0.9, 1.0, 1.0))
	debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, corridor_material)
	for waypoint in waypoints:
		if waypoint.is_valid():
			debug_mesh.surface_add_vertex(to_local(waypoint.left_edge + Vector3.UP * 0.05))
			debug_mesh.surface_add_vertex(to_local(waypoint.right_edge + Vector3.UP * 0.05))
	debug_mesh.surface_end()

	var center_material := _debug_material(Color(1.0, 0.85, 0.1, 1.0))
	debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, center_material)
	for index in waypoints.size():
		var current := waypoints[index]
		var next := waypoints[(index + 1) % waypoints.size()]
		debug_mesh.surface_add_vertex(to_local(current.center + Vector3.UP * 0.08))
		debug_mesh.surface_add_vertex(to_local(next.center + Vector3.UP * 0.08))
	debug_mesh.surface_end()

	if ray_miss_count > 0:
		var invalid_material := _debug_material(Color(1.0, 0.1, 0.1, 1.0))
		debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, invalid_material)
		for waypoint in waypoints:
			if not waypoint.is_valid():
				debug_mesh.surface_add_vertex(to_local(waypoint.left_edge + Vector3.UP * 0.1))
				debug_mesh.surface_add_vertex(to_local(waypoint.right_edge + Vector3.UP * 0.1))
		debug_mesh.surface_end()

	var debug_instance := MeshInstance3D.new()
	debug_instance.name = "WaypointDebugLines"
	debug_instance.mesh = debug_mesh
	add_child(debug_instance)

func _create_debug_labels() -> void:
	for waypoint in waypoints:
		var label := Label3D.new()
		var width := waypoint.left_edge.distance_to(waypoint.right_edge)
		label.text = str(waypoint.index)
		label.modulate = Color.WHITE

		if not waypoint.is_valid():
			var missing_sides: Array[String] = []
			if not waypoint.left_valid:
				missing_sides.append("L")
			if not waypoint.right_valid:
				missing_sides.append("R")
			label.text += "\nMISS %s" % "".join(missing_sides)
			label.modulate = Color(1.0, 0.15, 0.1, 1.0)
		elif width > debug_wide_threshold:
			label.text += "\nW %.1f" % width
			label.modulate = Color(1.0, 0.55, 0.05, 1.0)

		label.name = "WaypointLabel%03d" % waypoint.index
		label.position = to_local(waypoint.center + Vector3.UP * 0.45)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = false
		label.font_size = 32
		label.outline_size = 4
		label.outline_modulate = Color.BLACK
		label.pixel_size = 0.02
		add_child(label)

func _debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	return material
