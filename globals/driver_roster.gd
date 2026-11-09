class_name DriverRoster
extends RefCounted

const DRIVER_IDS: Array[String] = ["soral", "lepen", "glux", "melenchon"]

const PROFILES: Dictionary = {
	"soral": {
		"display_name": "A. Soral",
		"car_number": 0,
		"portrait": preload("res://sprites/Soral.jpg"),
		"selection_portrait": preload("res://sprites/Soral-no-glasses.jpg"),
		"car_color": Color(0, 0, 0, 1), # Pure Vibrant Black
	},
	"lepen": {
		"display_name": "M. Le Pen",
		"car_number": 1,
		"portrait": preload("res://sprites/Lepen.jpg"),
		"selection_portrait": preload("res://sprites/Lepen-no-glasses.jpg"),
		"car_color": Color(0.082, 0.212, 0.761, 1), # Royal Ultramarine

	},
	"glux": {
		"display_name": "R. Glucksman",
		"car_number": 2,
		"portrait": preload("res://sprites/Glux.jpg"),
		"selection_portrait": preload("res://sprites/Glux-no-glasses.jpg"),
		"car_color": Color(1.0, 0.75, 0.8, 1), # Plain Pink
	},
	"melenchon": {
		"display_name": "JL. Mélenchon",
		"car_number": 3,
		"portrait": preload("res://sprites/Melenchon.jpg"),
		"selection_portrait": preload("res://sprites/Melenchon-no-glasses.jpg"),
		"car_color": Color(0.85, 0.08, 0.08, 1), # Red
	},
}


static func has_driver(driver_id: String) -> bool:
	return PROFILES.has(driver_id)

static func get_profile(driver_id: String) -> Dictionary:
	if PROFILES.has(driver_id):
		return PROFILES[driver_id]

	push_error("Unknown driver_id: %s" % driver_id)
	return {}
