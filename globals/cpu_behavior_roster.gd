class_name CpuBehaviorRoster
extends RefCounted

const BEHAVIOR_IDS: Array[String] = [
	"right_balanced",
	"left_fast",
	"left_cautious",
]

const PROFILES: Dictionary = {
	"right_balanced": {
		"waypoint_look_ahead": 3,
		"lane_offset": -0.45,
		"cpu_steering_gain": 1.5,
		"cruise_throttle": 0.85,
		"corner_throttle": 0.5,
		"full_corner_angle": 0.8,
		"avoidance_distance": 3.0,
		"avoidance_spread_degrees": 25.0,
		"avoidance_strength": 1.25,
		"blocked_throttle_multiplier": 0.35,
		"prefer_right_pass": true,
	},
	"left_fast": {
		"waypoint_look_ahead": 3,
		"lane_offset": 0.0,
		"cpu_steering_gain": 1.6,
		"cruise_throttle": 0.92,
		"corner_throttle": 0.55,
		"full_corner_angle": 0.8,
		"avoidance_distance": 3.25,
		"avoidance_spread_degrees": 25.0,
		"avoidance_strength": 1.3,
		"blocked_throttle_multiplier": 0.35,
		"prefer_right_pass": false,
	},
	"left_cautious": {
		"waypoint_look_ahead": 3,
		"lane_offset": 0.45,
		"cpu_steering_gain": 1.35,
		"cruise_throttle": 0.78,
		"corner_throttle": 0.45,
		"full_corner_angle": 0.75,
		"avoidance_distance": 3.0,
		"avoidance_spread_degrees": 28.0,
		"avoidance_strength": 1.2,
		"blocked_throttle_multiplier": 0.3,
		"prefer_right_pass": false,
	},
}

static func get_profile(behavior_id: String) -> Dictionary:
	if PROFILES.has(behavior_id):
		return PROFILES[behavior_id]

	push_error("Unknown CPU behavior_id: %s" % behavior_id)
	return {}
