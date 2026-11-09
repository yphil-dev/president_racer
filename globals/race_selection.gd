extends Node

const CONTROL_COMBO := "gamepad_1_arrow"
const CONTROL_GAMEPAD_1 := "gamepad_1"
const CONTROL_ARROW := "arrow"
const CONTROL_WASD := "wasd"
const CONTROL_GAMEPAD_2 := "gamepad_2"
const CONTROL_GAMEPAD_3 := "gamepad_3"
const CONTROL_GAMEPAD_4 := "gamepad_4"
const CONTROL_CPU := "cpu"

const CONTROL_SCHEMES: Array[String] = [
	CONTROL_COMBO,
	CONTROL_GAMEPAD_1,
	CONTROL_ARROW,
	CONTROL_WASD,
	CONTROL_GAMEPAD_2,
	CONTROL_GAMEPAD_3,
	CONTROL_GAMEPAD_4,
	CONTROL_CPU,
]

const DEFAULT_CONTROL_SCHEMES: Dictionary = {
	"soral": CONTROL_COMBO,
	"lepen": CONTROL_CPU,
	"glux": CONTROL_CPU,
	"melenchon": CONTROL_CPU,
}

const SCHEME_SOURCES: Dictionary = {
	CONTROL_COMBO: [CONTROL_GAMEPAD_1, CONTROL_ARROW],
	CONTROL_GAMEPAD_1: [CONTROL_GAMEPAD_1],
	CONTROL_ARROW: [CONTROL_ARROW],
	CONTROL_WASD: [CONTROL_WASD],
	CONTROL_GAMEPAD_2: [CONTROL_GAMEPAD_2],
	CONTROL_GAMEPAD_3: [CONTROL_GAMEPAD_3],
	CONTROL_GAMEPAD_4: [CONTROL_GAMEPAD_4],
	CONTROL_CPU: [],
}

var selected_driver_id: String = "soral"
var selected_laps: int = 2
var night_enabled: bool = false
var driver_control_schemes: Dictionary = DEFAULT_CONTROL_SCHEMES.duplicate(true)

func select_driver(driver_id: String) -> void:
	if not DriverRoster.has_driver(driver_id):
		push_error("Cannot select unknown driver_id: %s" % driver_id)
		return

	selected_driver_id = driver_id

func get_control_scheme(driver_id: String) -> String:
	return str(driver_control_schemes.get(driver_id, CONTROL_CPU))

func assign_control_scheme(driver_id: String, scheme: String) -> void:
	if not DriverRoster.has_driver(driver_id):
		push_error("Cannot assign controls to unknown driver_id: %s" % driver_id)
		return
	if scheme not in CONTROL_SCHEMES:
		push_error("Unknown control scheme: %s" % scheme)
		return

	var claimed_sources := get_scheme_sources(scheme)
	for other_driver_id in DriverRoster.DRIVER_IDS:
		if other_driver_id == driver_id:
			continue

		var other_scheme := get_control_scheme(other_driver_id)
		var remaining_sources := get_scheme_sources(other_scheme)
		var had_conflict := false
		for source in claimed_sources:
			if source in remaining_sources:
				remaining_sources.erase(source)
				had_conflict = true

		if had_conflict:
			driver_control_schemes[other_driver_id] = _scheme_for_sources(remaining_sources)

	driver_control_schemes[driver_id] = scheme
	if scheme != CONTROL_CPU:
		selected_driver_id = driver_id

func get_scheme_sources(scheme: String) -> Array[String]:
	var sources: Array[String] = []
	for source in SCHEME_SOURCES.get(scheme, []):
		sources.append(str(source))
	return sources

func reset_control_schemes() -> void:
	driver_control_schemes = DEFAULT_CONTROL_SCHEMES.duplicate(true)
	selected_driver_id = "soral"

func _scheme_for_sources(sources: Array[String]) -> String:
	if CONTROL_GAMEPAD_1 in sources and CONTROL_ARROW in sources:
		return CONTROL_COMBO
	if CONTROL_GAMEPAD_1 in sources:
		return CONTROL_GAMEPAD_1
	if CONTROL_ARROW in sources:
		return CONTROL_ARROW
	if CONTROL_WASD in sources:
		return CONTROL_WASD
	if CONTROL_GAMEPAD_2 in sources:
		return CONTROL_GAMEPAD_2
	if CONTROL_GAMEPAD_3 in sources:
		return CONTROL_GAMEPAD_3
	if CONTROL_GAMEPAD_4 in sources:
		return CONTROL_GAMEPAD_4
	return CONTROL_CPU
