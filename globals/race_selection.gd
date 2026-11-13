extends Node

const SETTINGS_PATH := "user://race_options.cfg"
const SETTINGS_SECTION := "race_options"

const CONTROL_COMBO := "gamepad_1_arrow"
const CONTROL_GAMEPAD_1 := "gamepad_1"
const CONTROL_ARROW := "arrow"
const CONTROL_WASD := "wasd"
const CONTROL_GAMEPAD_2 := "gamepad_2"
const CONTROL_GAMEPAD_3 := "gamepad_3"
const CONTROL_GAMEPAD_4 := "gamepad_4"
const CONTROL_CPU := "cpu"

const WEATHER_FAIR := "fair"
const WEATHER_RAIN := "rain"
const WEATHER_SNOW := "snow"
const WEATHER_TRANSITION_DURATION: float = 45.0

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
	"macron": CONTROL_CPU,
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
var selected_weather: String = WEATHER_FAIR
var random_mode: bool = true
var driver_control_schemes: Dictionary = DEFAULT_CONTROL_SCHEMES.duplicate(true)
var _random_values_prepared: bool = false
var _safe_start_pending: bool = false

func _ready() -> void:
	_load_options()
	_safe_start_pending = random_mode

func prepare_next_race() -> void:
	if not random_mode or _random_values_prepared:
		return

	var driver_candidates: Array[String] = []
	for driver_id in DriverRoster.DRIVER_IDS:
		driver_candidates.append(driver_id)
	selected_driver_id = driver_candidates[randi_range(0, driver_candidates.size() - 1)]
	if _safe_start_pending:
		night_enabled = false
		selected_weather = WEATHER_FAIR
		_safe_start_pending = false
	else:
		night_enabled = randf() >= 0.95
		selected_weather = _random_weather()
	_configure_default_controls_for_selected_driver()
	_random_values_prepared = true

func set_random_mode() -> bool:
	random_mode = true
	_safe_start_pending = false
	_random_values_prepared = false
	prepare_next_race()
	return save_options()

func mark_options_changed() -> bool:
	random_mode = false
	_random_values_prepared = true
	return save_options()

func mark_race_started() -> void:
	_random_values_prepared = false

func save_options() -> bool:
	var config := ConfigFile.new()
	config.set_value(SETTINGS_SECTION, "random_mode", random_mode)
	config.set_value(SETTINGS_SECTION, "selected_driver_id", selected_driver_id)
	config.set_value(SETTINGS_SECTION, "selected_laps", selected_laps)
	config.set_value(SETTINGS_SECTION, "night_enabled", night_enabled)
	config.set_value(SETTINGS_SECTION, "selected_weather", selected_weather)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_error("Could not save race options: error %d" % error)
		return false
	return true

func _random_weather() -> String:
	var roll := randf()
	if roll < 0.92:
		return WEATHER_FAIR
	if roll < 0.98:
		return WEATHER_RAIN
	return WEATHER_SNOW

func _load_options() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return

	random_mode = bool(config.get_value(SETTINGS_SECTION, "random_mode", true))
	var saved_driver := str(config.get_value(SETTINGS_SECTION, "selected_driver_id", selected_driver_id))
	if DriverRoster.has_driver(saved_driver):
		selected_driver_id = saved_driver
	selected_laps = clampi(int(config.get_value(SETTINGS_SECTION, "selected_laps", selected_laps)), 1, 3)
	night_enabled = bool(config.get_value(SETTINGS_SECTION, "night_enabled", night_enabled))
	var saved_weather := str(config.get_value(SETTINGS_SECTION, "selected_weather", selected_weather))
	if saved_weather in [WEATHER_FAIR, WEATHER_RAIN, WEATHER_SNOW]:
		selected_weather = saved_weather

	if random_mode:
		_random_values_prepared = false
	else:
		_configure_default_controls_for_selected_driver()
		_random_values_prepared = true

func _configure_default_controls_for_selected_driver() -> void:
	driver_control_schemes = DEFAULT_CONTROL_SCHEMES.duplicate(true)
	for driver_id in DriverRoster.DRIVER_IDS:
		driver_control_schemes[driver_id] = CONTROL_CPU
	driver_control_schemes[selected_driver_id] = CONTROL_COMBO

func select_driver(driver_id: String) -> void:
	if not DriverRoster.has_driver(driver_id):
		push_error("Cannot select unknown driver_id: %s" % driver_id)
		return

	selected_driver_id = driver_id

func get_control_scheme(driver_id: String) -> String:
	return str(driver_control_schemes.get(driver_id, CONTROL_CPU))

func ensure_selected_driver_is_player() -> void:
	if DriverRoster.has_driver(selected_driver_id):
		driver_control_schemes[selected_driver_id] = CONTROL_COMBO

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
