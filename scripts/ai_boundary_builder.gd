class_name AIBoundaryBuilder
extends Node3D

signal boundaries_ready

const AI_BOUNDARY_LAYER: int = 1 << 4

@export_range(0.1, 10.0, 0.1, "or_greater") var segment_spacing: float = 1.0
@export_range(0.01, 2.0, 0.01, "or_greater") var wall_thickness: float = 0.15
@export_range(0.1, 10.0, 0.1, "or_greater") var wall_height: float = 1.0

@export_category("Track Height Alignment")
@export var align_height_to_track_path: bool = false
@export_range(1.0, 30.0, 0.5, "or_greater") var height_search_window: float = 12.0
@export_range(0.05, 1.0, 0.05, "or_greater") var height_search_step: float = 0.1

@onready var interior_wall: Path3D = $InteriorWall
@onready var exterior_wall: Path3D = $ExteriorWall
@onready var track_path: Path3D = get_node_or_null("TrackPath") as Path3D

var is_ready: bool = false
var segment_count: int = 0

func _ready() -> void:
	if align_height_to_track_path and (
		track_path == null
		or track_path.curve == null
		or track_path.curve.point_count < 2
	):
		push_error("%s requires TrackPath for height alignment." % get_path())
		return

	segment_count = _build_wall(interior_wall, "GeneratedInteriorWall")
	segment_count += _build_wall(exterior_wall, "GeneratedExteriorWall")

	await get_tree().physics_frame
	is_ready = true
	boundaries_ready.emit()
	if Debug.DEBUG_VERBOSE:
		print("AI boundaries ready: %d segments" % segment_count)

func _build_wall(path: Path3D, wall_name: String) -> int:
	var curve := path.curve
	if curve == null or curve.point_count < 2:
		push_error("%s requires a Curve3D with at least two points." % path.get_path())
		return 0

	var curve_length := curve.get_baked_length()
	if curve_length <= 0.0:
		push_error("%s has no baked length." % path.get_path())
		return 0

	var sample_count := maxi(3, ceili(curve_length / segment_spacing))
	var points: Array[Vector3] = []
	points.resize(sample_count)
	var track_curve: Curve3D = track_path.curve if align_height_to_track_path else null
	var track_length: float = track_curve.get_baked_length() if track_curve != null else 0.0

	for index in sample_count:
		var distance := curve_length * float(index) / float(sample_count)
		var path_point := curve.sample_baked(distance, true)
		var global_point := path.to_global(path_point)
		if track_curve != null:
			var expected_track_distance := track_length * distance / curve_length
			global_point.y = _find_track_height(
				global_point,
				track_curve,
				track_length,
				expected_track_distance
			)
		points[index] = to_local(global_point)

	var body := StaticBody3D.new()
	body.name = wall_name
	body.collision_layer = AI_BOUNDARY_LAYER
	body.collision_mask = 0
	add_child(body)

	for index in sample_count:
		var start := points[index]
		var end := points[(index + 1) % sample_count]
		_add_segment(body, start, end, index)

	return sample_count

func _find_track_height(
	wall_point: Vector3,
	curve: Curve3D,
	curve_length: float,
	expected_distance: float
) -> float:
	var best_height := wall_point.y
	var best_horizontal_distance := INF
	var search_steps := ceili(height_search_window / height_search_step)

	for step in range(-search_steps, search_steps + 1):
		var distance := fposmod(
			expected_distance + step * height_search_step,
			curve_length
		)
		var candidate := track_path.to_global(curve.sample_baked(distance, true))
		var horizontal_distance := Vector2(
			candidate.x - wall_point.x,
			candidate.z - wall_point.z
		).length_squared()
		if horizontal_distance < best_horizontal_distance:
			best_horizontal_distance = horizontal_distance
			best_height = candidate.y

	return best_height

func _add_segment(body: StaticBody3D, start: Vector3, end: Vector3, index: int) -> void:
	var segment := end - start
	var length := segment.length()
	if length <= 0.001:
		return

	var forward := segment / length
	var right := Vector3.UP.cross(forward)
	if right.length_squared() <= 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	var up := forward.cross(right).normalized()

	var shape := BoxShape3D.new()
	shape.size = Vector3(wall_thickness, wall_height, length + wall_thickness)

	var collision := CollisionShape3D.new()
	collision.name = "Segment%04d" % index
	collision.shape = shape
	collision.transform = Transform3D(
		Basis(right, up, forward),
		(start + end) * 0.5
	)
	body.add_child(collision)
