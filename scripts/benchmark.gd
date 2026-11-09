extends Node

# Set this to false to force all Light3D nodes off during the test
@export var force_lights_off := false

var _total_time := 0.0
var _frame_count := 0
var _is_running := false

func _ready() -> void:
	# Disable V-Sync so frame times aren't artificially capped
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func start_lap_test() -> void:
	if force_lights_off:
		_disable_all_lights(get_tree().current_scene)

	_total_time = 0.0
	_frame_count = 0
	_is_running = true
	print("Benchmark started | Lights forced off: ", force_lights_off)

func _process(delta: float) -> void:
	if _is_running:
		_total_time += delta
		_frame_count += 1

func stop_lap_test() -> void:
	if not _is_running:
		return
	_is_running = false

	var avg_ms := (_total_time / _frame_count) * 1000.0
	var avg_fps := _frame_count / _total_time

	print("=== LAP BENCHMARK RESULTS ===")
	print("Track: ", get_tree().current_scene.name)
	print("Night Mode: ", RaceSelection.night_enabled)
	print("Lights Forced Off: ", force_lights_off)
	print("Avg Frame Time: %.2f ms | Avg FPS: %.1f" % [avg_ms, avg_fps])

func _disable_all_lights(node: Node) -> void:
	# Automatically hides DirectionalLight3D, OmniLight3D, and SpotLight3D
	if node is Light3D:
		node.visible = false
	for child in node.get_children():
		_disable_all_lights(child)
