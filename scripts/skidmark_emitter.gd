class_name SkidmarkEmitter
extends Node3D

@export_range(0.05, 0.4, 0.01) var point_spacing: float = 0.12
@export_range(0.05, 0.3, 0.01) var mark_width: float = 0.16
@export_range(0.005, 0.05, 0.001) var surface_offset: float = 0.018
@export_range(32, 512, 1) var chunk_segment_limit: int = 256
@export_range(128, 4096, 1) var max_segments_per_tire: int = 1024
@export_range(0.5, 5.0, 0.1) var maximum_strip_length: float = 4.5
@export_range(0.1, 2.0, 0.1) var forced_strip_gap: float = 0.6
@export_range(0.2, 2.0, 0.05) var maximum_contact_gap: float = 0.75

const TIRE_COUNT: int = 4

var _material: StandardMaterial3D
var _tire_states: Array[Dictionary] = []

func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.035, 0.03, 0.025, 0.38)
	_material.roughness = 1.0
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.render_priority = 1

	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if OS.has_feature("arm64") or OS.has_feature("arm32"):
		point_spacing = 0.28
		chunk_segment_limit = 64
		max_segments_per_tire = 384

	for tire_index in TIRE_COUNT:
		_tire_states.append(_new_tire_state(tire_index))

func add_contact(
	tire_index: int,
	global_contact: Vector3,
	global_normal: Vector3
) -> void:
	if tire_index < 0 or tire_index >= _tire_states.size():
		return

	var state := _tire_states[tire_index]
	if int(state["total_segments"]) >= max_segments_per_tire:
		state["active"] = false
		return

	var local_normal := (global_basis.inverse() * global_normal).normalized()
	var local_contact := to_local(global_contact + global_normal * surface_offset)

	if bool(state["waiting_for_gap"]):
		var gap_origin := state["gap_origin"] as Vector3
		if gap_origin.distance_to(local_contact) < forced_strip_gap:
			return
		state["waiting_for_gap"] = false

	if not bool(state["active"]):
		_begin_strip(state, local_contact, local_normal)
		return

	var strip := state["current_strip"] as Dictionary
	var points := strip["points"] as Array
	var normals := strip["normals"] as Array
	var previous_point := points.back() as Vector3
	var distance := previous_point.distance_to(local_contact)

	if distance < point_spacing:
		return
	if distance > maximum_contact_gap:
		state["active"] = false
		_begin_strip(state, local_contact, local_normal)
		return

	points.append(local_contact)
	normals.append(local_normal)
	strip["length"] = float(strip["length"]) + distance
	state["chunk_segments"] = int(state["chunk_segments"]) + 1
	state["total_segments"] = int(state["total_segments"]) + 1
	_rebuild_current_chunk(state)

	var strip_complete := float(strip["length"]) >= maximum_strip_length
	var chunk_complete := int(state["chunk_segments"]) >= chunk_segment_limit
	if chunk_complete:
		_prepare_next_chunk(state)
	if strip_complete:
		state["active"] = false
		state["current_strip"] = {}
		state["waiting_for_gap"] = true
		state["gap_origin"] = local_contact
	elif chunk_complete:
		_begin_strip(state, local_contact, local_normal)

func stop_tire(tire_index: int) -> void:
	if tire_index < 0 or tire_index >= _tire_states.size():
		return
	var state := _tire_states[tire_index]
	state["active"] = false
	state["current_strip"] = {}
	state["waiting_for_gap"] = false

func stop_all() -> void:
	for tire_index in _tire_states.size():
		stop_tire(tire_index)

func _new_tire_state(tire_index: int) -> Dictionary:
	return {
		"tire_index": tire_index,
		"active": false,
		"strips": [],
		"current_strip": {},
		"waiting_for_gap": false,
		"gap_origin": Vector3.ZERO,
		"chunk_segments": 0,
		"total_segments": 0,
		"chunk_index": 0,
		"mesh": null,
		"mesh_instance": null,
	}

func _begin_strip(state: Dictionary, point: Vector3, normal: Vector3) -> void:
	if int(state["chunk_segments"]) >= chunk_segment_limit:
		_prepare_next_chunk(state)

	var strip := {
		"points": [point],
		"normals": [normal],
		"length": 0.0,
	}
	var strips := state["strips"] as Array
	strips.append(strip)
	state["current_strip"] = strip
	state["active"] = true

func _prepare_next_chunk(state: Dictionary) -> void:
	state["active"] = false
	state["strips"] = []
	state["current_strip"] = {}
	state["chunk_segments"] = 0
	state["chunk_index"] = int(state["chunk_index"]) + 1
	state["mesh"] = null
	state["mesh_instance"] = null

func _rebuild_current_chunk(state: Dictionary) -> void:
	var mesh := state["mesh"] as ImmediateMesh
	var mesh_instance := state["mesh_instance"] as MeshInstance3D
	if mesh == null:
		mesh = ImmediateMesh.new()
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "Tire%dChunk%d" % [
			int(state["tire_index"]),
			int(state["chunk_index"]),
		]
		mesh_instance.mesh = mesh
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		add_child(mesh_instance)
		state["mesh"] = mesh
		state["mesh_instance"] = mesh_instance

	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)

	for strip_value in state["strips"] as Array:
		var strip := strip_value as Dictionary
		var points := strip["points"] as Array
		var normals := strip["normals"] as Array
		for point_index in range(1, points.size()):
			_add_segment(
				mesh,
				points[point_index - 1] as Vector3,
				points[point_index] as Vector3,
				normals[point_index - 1] as Vector3,
				normals[point_index] as Vector3
			)

	mesh.surface_end()

func _add_segment(
	mesh: ImmediateMesh,
	start: Vector3,
	end: Vector3,
	start_normal: Vector3,
	end_normal: Vector3
) -> void:
	var direction := end - start
	if direction.length_squared() <= 0.000001:
		return
	direction = direction.normalized()

	var start_side := start_normal.cross(direction).normalized() * mark_width * 0.5
	var end_side := end_normal.cross(direction).normalized() * mark_width * 0.5
	if start_side.length_squared() <= 0.000001 or end_side.length_squared() <= 0.000001:
		return

	var start_left := start - start_side
	var start_right := start + start_side
	var end_left := end - end_side
	var end_right := end + end_side

	_add_vertex(mesh, start_left, start_normal, Vector2(0.0, 0.0))
	_add_vertex(mesh, end_left, end_normal, Vector2(0.0, 1.0))
	_add_vertex(mesh, start_right, start_normal, Vector2(1.0, 0.0))

	_add_vertex(mesh, start_right, start_normal, Vector2(1.0, 0.0))
	_add_vertex(mesh, end_left, end_normal, Vector2(0.0, 1.0))
	_add_vertex(mesh, end_right, end_normal, Vector2(1.0, 1.0))

func _add_vertex(
	mesh: ImmediateMesh,
	position: Vector3,
	normal: Vector3,
	uv: Vector2
) -> void:
	mesh.surface_set_normal(normal)
	mesh.surface_set_uv(uv)
	mesh.surface_add_vertex(position)
