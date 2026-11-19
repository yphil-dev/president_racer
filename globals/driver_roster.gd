class_name DriverRoster
extends RefCounted

const DRIVER_IDS: Array[String] = [
	"soral",
	"lepen",
	"melenchon",
	"macron",
	"riner",
	"rima",
]

const PROFILES: Dictionary = {
	"soral": {
		"display_name": "A. Soral",
		"last_name": "Soral",
		"car_number": 0,
		"portrait": preload("res://sprites/Soral.jpg"),
		"car_color": Color(0.05, 0.06, 0.1, 1.0)
	},
	"lepen": {
		"display_name": "M. Le Pen",
		"last_name": "Le Pen",
		"car_number": 1,
		"portrait": preload("res://sprites/Lepen.jpg"),
		"car_color": Color(0.082, 0.212, 0.761, 1), # Royal Ultramarine

	},
	"melenchon": {
		"display_name": "JL. Mélenchon",
		"last_name": "Mélenchon",
		"car_number": 3,
		"portrait": preload("res://sprites/Melenchon.jpg"),
		"car_color": Color(0.85, 0.08, 0.08, 1), # Red
	},
	"macron": {
		"display_name": "B. Macron",
		"last_name": "Macron",
		"car_number": 2,
		"portrait": preload("res://sprites/Macron.jpg"),
		"car_color": Color(1.0, 0.0, 0.498, 1.0), # Classic Rose
	},
	"riner": {
		"display_name": "T. Riner",
		"last_name": "Riner",
		"car_number": 4,
		"portrait": preload("res://sprites/riner.jpg"),
		"car_color": Color(0.65, 0.65, 0.65, 1.0),
	},
	"rima": {
		"display_name": "R. Hassan",
		"last_name": "Hassan",
		"car_number": 5,
		"portrait": preload("res://sprites/rima.jpg"),
		"car_color": Color(0.09, 0.40, 0.20, 1.0),
	},
}


static func has_driver(driver_id: String) -> bool:
	return PROFILES.has(driver_id)

static func get_profile(driver_id: String) -> Dictionary:
	if PROFILES.has(driver_id):
		return PROFILES[driver_id]

	push_error("Unknown driver_id: %s" % driver_id)
	return {}
