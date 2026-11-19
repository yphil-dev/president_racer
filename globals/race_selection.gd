extends Node

const SETTINGS_PATH := "user://race_options.cfg"
const SETTINGS_SECTION := "race_options"
const PILOT_COUNT: int = 6
const PLAYER_SLOT_COUNT: int = 6
const LOCAL_PLAYER_SLOT_COUNT: int = 4
const NO_PLAYER_SLOT: int = -1

enum PilotMode {
	HUMAN,
	CPU,
	OFF,
}

enum InputSource {
	ARROWS,
	WASD,
	PAD_1,
	PAD_2,
	PAD_3,
	PAD_4,
	REMOTE_PEER,
}

const LOCAL_INPUT_SOURCES: Array[int] = [
	InputSource.ARROWS,
	InputSource.WASD,
	InputSource.PAD_1,
	InputSource.PAD_2,
	InputSource.PAD_3,
	InputSource.PAD_4,
]
const DEFAULT_SLOT_INPUTS: Array[int] = [
	InputSource.ARROWS,
	InputSource.WASD,
	InputSource.PAD_1,
	InputSource.PAD_2,
	InputSource.PAD_3,
	InputSource.PAD_4,
]

const WEATHER_FAIR := "fair"
const WEATHER_RAIN := "rain"
const WEATHER_SNOW := "snow"
const WEATHER_TRANSITION_DURATION: float = 45.0

var selected_driver_id: String = "soral"
var selected_laps: int = 2
var night_enabled: bool = false
var selected_weather: String = WEATHER_FAIR
var random_mode: bool = true
var pilot_states: Array[Dictionary] = []
var player_slots: Array[Dictionary] = []
var selected_local_slot: int = 0
var _random_values_prepared: bool = false
var _safe_start_pending: bool = false

func _ready() -> void:
	_reset_roster_to_defaults()
	_load_options()
	_safe_start_pending = random_mode

func prepare_next_race() -> void:
	if not random_mode or _random_values_prepared:
		return

	var driver_index: int = randi_range(0, DriverRoster.DRIVER_IDS.size() - 1)
	selected_driver_id = DriverRoster.DRIVER_IDS[driver_index]
	_reset_roster_to_defaults(selected_driver_id)
	if _safe_start_pending:
		night_enabled = false
		selected_weather = WEATHER_FAIR
		_safe_start_pending = false
	else:
		night_enabled = randf() >= 0.95
		selected_weather = _random_weather()
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
	config.set_value(SETTINGS_SECTION, "pilot_states", pilot_states.duplicate(true))
	config.set_value(SETTINGS_SECTION, "player_slots", player_slots.duplicate(true))
	var error: Error = config.save(SETTINGS_PATH)
	if error != OK:
		push_error("Could not save race options: error %d" % error)
		return false
	return true

func select_driver(driver_id: String) -> void:
	if not DriverRoster.has_driver(driver_id):
		push_error("Cannot select unknown driver_id: %s" % driver_id)
		return
	selected_driver_id = driver_id

func get_pilot_mode(driver_id: String) -> int:
	var index: int = DriverRoster.DRIVER_IDS.find(driver_id)
	if index < 0 or index >= pilot_states.size():
		return PilotMode.OFF
	return int(pilot_states[index].get("mode", PilotMode.OFF))

func get_player_slot_for_driver(driver_id: String) -> int:
	var index: int = DriverRoster.DRIVER_IDS.find(driver_id)
	if index < 0 or index >= pilot_states.size():
		return NO_PLAYER_SLOT
	if get_pilot_mode(driver_id) != PilotMode.HUMAN:
		return NO_PLAYER_SLOT
	return int(pilot_states[index].get("player_slot", NO_PLAYER_SLOT))

func get_driver_for_player_slot(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= player_slots.size():
		return ""
	return str(player_slots[slot_index].get("driver_id", ""))

func get_input_source(slot_index: int) -> int:
	if slot_index < 0 or slot_index >= player_slots.size():
		return InputSource.REMOTE_PEER
	return int(player_slots[slot_index].get("input_source", InputSource.REMOTE_PEER))

func get_input_source_for_driver(driver_id: String) -> int:
	return get_input_source(get_player_slot_for_driver(driver_id))

func is_player_slot_active(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= player_slots.size():
		return false
	var driver_id: String = get_driver_for_player_slot(slot_index)
	return (
		bool(player_slots[slot_index].get("active", false))
		and not driver_id.is_empty()
		and get_pilot_mode(driver_id) == PilotMode.HUMAN
	)

func is_driver_human(driver_id: String) -> bool:
	return get_pilot_mode(driver_id) == PilotMode.HUMAN

func is_driver_active(driver_id: String) -> bool:
	return get_pilot_mode(driver_id) != PilotMode.OFF

func get_active_driver_ids() -> Array[String]:
	var result: Array[String] = []
	for driver_id in DriverRoster.DRIVER_IDS:
		if is_driver_active(driver_id):
			result.append(driver_id)
	return result

func get_human_driver_ids() -> Array[String]:
	var result: Array[String] = []
	for driver_id in DriverRoster.DRIVER_IDS:
		if is_driver_human(driver_id):
			result.append(driver_id)
	return result

func get_cpu_driver_ids() -> Array[String]:
	var result: Array[String] = []
	for driver_id in DriverRoster.DRIVER_IDS:
		if get_pilot_mode(driver_id) == PilotMode.CPU:
			result.append(driver_id)
	return result

func has_human_driver() -> bool:
	return not get_human_driver_ids().is_empty()

func assign_pilot_to_slot(driver_id: String, slot_index: int) -> bool:
	if not DriverRoster.has_driver(driver_id):
		push_error("Cannot assign unknown driver_id: %s" % driver_id)
		return false
	if slot_index < 0 or slot_index >= PLAYER_SLOT_COUNT:
		push_error("Invalid player slot: %d" % slot_index)
		return false

	var source_slot: int = get_player_slot_for_driver(driver_id)
	if source_slot == slot_index:
		selected_driver_id = driver_id
		return true

	var target_driver_id: String = get_driver_for_player_slot(slot_index)
	if source_slot >= 0:
		if not target_driver_id.is_empty():
			_assign_human_state(target_driver_id, source_slot)
		else:
			_clear_player_slot(source_slot)
	elif not target_driver_id.is_empty():
		_set_pilot_state(target_driver_id, PilotMode.CPU, NO_PLAYER_SLOT)

	_assign_human_state(driver_id, slot_index)
	_ensure_unique_local_input(slot_index)
	selected_driver_id = driver_id
	return true

func activate_local_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= LOCAL_PLAYER_SLOT_COUNT:
		return false
	if is_player_slot_active(slot_index):
		selected_local_slot = slot_index
		return true

	var candidate_id: String = _first_unclaimed_driver(PilotMode.CPU)
	if candidate_id.is_empty():
		candidate_id = _first_unclaimed_driver(PilotMode.OFF)
	if candidate_id.is_empty():
		return false

	selected_local_slot = slot_index
	return assign_pilot_to_slot(candidate_id, slot_index)

func deactivate_local_slot(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= LOCAL_PLAYER_SLOT_COUNT:
		return false
	var driver_id: String = get_driver_for_player_slot(slot_index)
	if driver_id.is_empty():
		_clear_player_slot(slot_index)
		return true

	_set_pilot_state(driver_id, PilotMode.CPU, NO_PLAYER_SLOT)
	_clear_player_slot(slot_index)
	_sync_selected_driver()
	return true

func release_human_pilot(driver_id: String) -> bool:
	var slot_index: int = get_player_slot_for_driver(driver_id)
	if slot_index < 0:
		return false
	_set_pilot_state(driver_id, PilotMode.CPU, NO_PLAYER_SLOT)
	_clear_player_slot(slot_index)
	_sync_selected_driver()
	return true

func toggle_cpu_off(driver_id: String) -> bool:
	if not DriverRoster.has_driver(driver_id) or is_driver_human(driver_id):
		return false

	var current_mode: int = get_pilot_mode(driver_id)
	if current_mode == PilotMode.CPU:
		if get_active_driver_ids().size() <= 1:
			return false
		_set_pilot_state(driver_id, PilotMode.OFF, NO_PLAYER_SLOT)
	else:
		_set_pilot_state(driver_id, PilotMode.CPU, NO_PLAYER_SLOT)
	_sync_selected_driver()
	return true

func set_input_source(slot_index: int, input_source: int) -> bool:
	if slot_index < 0 or slot_index >= PLAYER_SLOT_COUNT:
		return false
	if input_source < InputSource.ARROWS or input_source > InputSource.REMOTE_PEER:
		return false
	if input_source != InputSource.REMOTE_PEER and _input_source_claimed(input_source, slot_index):
		return false
	player_slots[slot_index]["input_source"] = input_source
	return true

func cycle_local_input_source(slot_index: int) -> int:
	if slot_index < 0 or slot_index >= LOCAL_PLAYER_SLOT_COUNT:
		return InputSource.REMOTE_PEER
	var current_source: int = get_input_source(slot_index)
	var current_index: int = LOCAL_INPUT_SOURCES.find(current_source)
	for offset in range(1, LOCAL_INPUT_SOURCES.size() + 1):
		var candidate_index: int = posmod(current_index + offset, LOCAL_INPUT_SOURCES.size())
		var candidate: int = LOCAL_INPUT_SOURCES[candidate_index]
		if not _input_source_claimed(candidate, slot_index):
			player_slots[slot_index]["input_source"] = candidate
			return candidate
	return current_source

func get_input_source_label(input_source: int) -> String:
	match input_source:
		InputSource.ARROWS:
			return "Arrows"
		InputSource.WASD:
			return "WASD / ZQSD"
		InputSource.PAD_1:
			return "Pad 1"
		InputSource.PAD_2:
			return "Pad 2"
		InputSource.PAD_3:
			return "Pad 3"
		InputSource.PAD_4:
			return "Pad 4"
		InputSource.REMOTE_PEER:
			return "Remote"
	return "Unknown"

func get_gamepad_number(input_source: int) -> int:
	match input_source:
		InputSource.PAD_1:
			return 1
		InputSource.PAD_2:
			return 2
		InputSource.PAD_3:
			return 3
		InputSource.PAD_4:
			return 4
	return 0

func should_use_solo_input_fallback(driver_id: String) -> bool:
	var slot_index: int = get_player_slot_for_driver(driver_id)
	if slot_index < 0 or get_human_driver_ids().size() != 1:
		return false
	var source: int = get_input_source(slot_index)
	return source == InputSource.ARROWS or source == InputSource.PAD_1

func reset_roster() -> void:
	_reset_roster_to_defaults()
	selected_driver_id = DriverRoster.DRIVER_IDS[0]

func _random_weather() -> String:
	var roll: float = randf()
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
	var saved_driver: String = str(
		config.get_value(SETTINGS_SECTION, "selected_driver_id", selected_driver_id)
	)
	if DriverRoster.has_driver(saved_driver):
		selected_driver_id = saved_driver
	selected_laps = clampi(
		int(config.get_value(SETTINGS_SECTION, "selected_laps", selected_laps)),
		1,
		3
	)
	night_enabled = bool(config.get_value(SETTINGS_SECTION, "night_enabled", night_enabled))
	var saved_weather: String = str(
		config.get_value(SETTINGS_SECTION, "selected_weather", selected_weather)
	)
	if saved_weather in [WEATHER_FAIR, WEATHER_RAIN, WEATHER_SNOW]:
		selected_weather = saved_weather

	var has_saved_pilots: bool = config.has_section_key(SETTINGS_SECTION, "pilot_states")
	if has_saved_pilots:
		var saved_pilot_value: Variant = config.get_value(SETTINGS_SECTION, "pilot_states")
		var saved_slot_value: Variant = []
		if config.has_section_key(SETTINGS_SECTION, "player_slots"):
			saved_slot_value = config.get_value(SETTINGS_SECTION, "player_slots")
		if saved_pilot_value is Array:
			_load_saved_roster(saved_pilot_value as Array, saved_slot_value)
		else:
			_migrate_legacy_roster(config, saved_driver)
	else:
		_migrate_legacy_roster(config, saved_driver)

	_enforce_roster_invariants()
	if random_mode:
		_random_values_prepared = false
	else:
		_random_values_prepared = true

func _load_saved_roster(saved_pilots: Array, saved_slot_value: Variant) -> void:
	_reset_all_pilots_to_cpu()
	for index in mini(saved_pilots.size(), PILOT_COUNT):
		var saved_state_value: Variant = saved_pilots[index]
		var mode: int = PilotMode.CPU
		var player_slot: int = NO_PLAYER_SLOT
		if saved_state_value is Dictionary:
			var saved_state: Dictionary = saved_state_value as Dictionary
			mode = clampi(int(saved_state.get("mode", PilotMode.CPU)), PilotMode.HUMAN, PilotMode.OFF)
			player_slot = int(saved_state.get("player_slot", NO_PLAYER_SLOT))
		elif saved_state_value is int:
			mode = clampi(int(saved_state_value), PilotMode.HUMAN, PilotMode.OFF)
		pilot_states[index] = {"mode": mode, "player_slot": player_slot}

	if saved_slot_value is Array:
		var saved_slots: Array = saved_slot_value as Array
		for index in mini(saved_slots.size(), PLAYER_SLOT_COUNT):
			var saved_slot_value_at_index: Variant = saved_slots[index]
			if not saved_slot_value_at_index is Dictionary:
				continue
			var saved_slot: Dictionary = saved_slot_value_at_index as Dictionary
			var input_source: int = clampi(
				int(saved_slot.get("input_source", DEFAULT_SLOT_INPUTS[index])),
				InputSource.ARROWS,
				InputSource.REMOTE_PEER
			)
			player_slots[index]["input_source"] = input_source

	_rebuild_slots_from_pilot_states()

func _migrate_legacy_roster(config: ConfigFile, saved_driver: String) -> void:
	_reset_all_pilots_to_cpu()
	var legacy_controls_value: Variant = {}
	if config.has_section_key(SETTINGS_SECTION, "driver_control_schemes"):
		legacy_controls_value = config.get_value(SETTINGS_SECTION, "driver_control_schemes")
	if legacy_controls_value is Dictionary and not (legacy_controls_value as Dictionary).is_empty():
		var legacy_controls: Dictionary = legacy_controls_value as Dictionary
		var next_slot: int = 0
		for driver_id in DriverRoster.DRIVER_IDS:
			if next_slot >= LOCAL_PLAYER_SLOT_COUNT:
				break
			var legacy_scheme: String = str(legacy_controls.get(driver_id, "cpu"))
			if legacy_scheme == "cpu":
				continue
			_assign_human_state(driver_id, next_slot)
			player_slots[next_slot]["input_source"] = _legacy_input_source(legacy_scheme)
			next_slot += 1
		return

	var migrated_driver: String = saved_driver
	if not DriverRoster.has_driver(migrated_driver):
		migrated_driver = DriverRoster.DRIVER_IDS[0]
	_assign_human_state(migrated_driver, 0)

func _legacy_input_source(legacy_scheme: String) -> int:
	match legacy_scheme:
		"wasd":
			return InputSource.WASD
		"gamepad_1":
			return InputSource.PAD_1
		"gamepad_2":
			return InputSource.PAD_2
		"gamepad_3":
			return InputSource.PAD_3
		"gamepad_4":
			return InputSource.PAD_4
	return InputSource.ARROWS

func _reset_roster_to_defaults(human_driver_id: String = "soral") -> void:
	_reset_all_pilots_to_cpu()
	if not DriverRoster.has_driver(human_driver_id):
		human_driver_id = DriverRoster.DRIVER_IDS[0]
	_assign_human_state(human_driver_id, 0)
	selected_driver_id = human_driver_id

func _reset_all_pilots_to_cpu() -> void:
	pilot_states.clear()
	for _index in PILOT_COUNT:
		pilot_states.append({"mode": PilotMode.CPU, "player_slot": NO_PLAYER_SLOT})
	player_slots.clear()
	for index in PLAYER_SLOT_COUNT:
		player_slots.append({
			"active": false,
			"driver_id": "",
			"input_source": DEFAULT_SLOT_INPUTS[index],
		})

func _rebuild_slots_from_pilot_states() -> void:
	for slot_index in player_slots.size():
		player_slots[slot_index]["active"] = false
		player_slots[slot_index]["driver_id"] = ""

	for driver_index in pilot_states.size():
		var state: Dictionary = pilot_states[driver_index]
		if int(state.get("mode", PilotMode.CPU)) != PilotMode.HUMAN:
			state["player_slot"] = NO_PLAYER_SLOT
			continue
		var desired_slot: int = int(state.get("player_slot", NO_PLAYER_SLOT))
		if (
			desired_slot < 0
			or desired_slot >= PLAYER_SLOT_COUNT
			or bool(player_slots[desired_slot]["active"])
		):
			desired_slot = _first_empty_player_slot()
		if desired_slot < 0:
			state["mode"] = PilotMode.CPU
			state["player_slot"] = NO_PLAYER_SLOT
			continue
		_assign_human_state(DriverRoster.DRIVER_IDS[driver_index], desired_slot)

func _assign_human_state(driver_id: String, slot_index: int) -> void:
	var driver_index: int = DriverRoster.DRIVER_IDS.find(driver_id)
	if driver_index < 0:
		return
	pilot_states[driver_index] = {"mode": PilotMode.HUMAN, "player_slot": slot_index}
	player_slots[slot_index]["active"] = true
	player_slots[slot_index]["driver_id"] = driver_id

func _set_pilot_state(driver_id: String, mode: int, player_slot: int) -> void:
	var driver_index: int = DriverRoster.DRIVER_IDS.find(driver_id)
	if driver_index < 0:
		return
	pilot_states[driver_index] = {"mode": mode, "player_slot": player_slot}

func _clear_player_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= player_slots.size():
		return
	player_slots[slot_index]["active"] = false
	player_slots[slot_index]["driver_id"] = ""

func _first_unclaimed_driver(mode: int) -> String:
	for driver_id in DriverRoster.DRIVER_IDS:
		if get_pilot_mode(driver_id) == mode:
			return driver_id
	return ""

func _first_empty_player_slot() -> int:
	for slot_index in player_slots.size():
		if not bool(player_slots[slot_index]["active"]):
			return slot_index
	return NO_PLAYER_SLOT

func _input_source_claimed(input_source: int, ignored_slot: int) -> bool:
	for slot_index in LOCAL_PLAYER_SLOT_COUNT:
		if slot_index == ignored_slot or not is_player_slot_active(slot_index):
			continue
		if get_input_source(slot_index) == input_source:
			return true
	return false

func _ensure_unique_local_input(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= LOCAL_PLAYER_SLOT_COUNT:
		return
	var current_source: int = get_input_source(slot_index)
	if not _input_source_claimed(current_source, slot_index):
		return
	for candidate in LOCAL_INPUT_SOURCES:
		if not _input_source_claimed(candidate, slot_index):
			player_slots[slot_index]["input_source"] = candidate
			return

func _enforce_roster_invariants() -> void:
	while pilot_states.size() < PILOT_COUNT:
		pilot_states.append({"mode": PilotMode.CPU, "player_slot": NO_PLAYER_SLOT})
	if pilot_states.size() > PILOT_COUNT:
		pilot_states.resize(PILOT_COUNT)
	while player_slots.size() < PLAYER_SLOT_COUNT:
		var slot_index: int = player_slots.size()
		player_slots.append({
			"active": false,
			"driver_id": "",
			"input_source": DEFAULT_SLOT_INPUTS[slot_index],
		})
	if player_slots.size() > PLAYER_SLOT_COUNT:
		player_slots.resize(PLAYER_SLOT_COUNT)
	if get_active_driver_ids().is_empty():
		_set_pilot_state(DriverRoster.DRIVER_IDS[0], PilotMode.CPU, NO_PLAYER_SLOT)
	_rebuild_slots_from_pilot_states()
	_resolve_duplicate_local_inputs()
	_sync_selected_driver()

func _resolve_duplicate_local_inputs() -> void:
	var claimed: Array[int] = []
	for slot_index in LOCAL_PLAYER_SLOT_COUNT:
		if not is_player_slot_active(slot_index):
			continue
		var source: int = get_input_source(slot_index)
		if source not in LOCAL_INPUT_SOURCES or source in claimed:
			for candidate in LOCAL_INPUT_SOURCES:
				if candidate not in claimed:
					source = candidate
					break
			player_slots[slot_index]["input_source"] = source
		claimed.append(source)

func _sync_selected_driver() -> void:
	if is_driver_human(selected_driver_id):
		return
	var human_drivers: Array[String] = get_human_driver_ids()
	if not human_drivers.is_empty():
		selected_driver_id = human_drivers[0]
		return
	var active_drivers: Array[String] = get_active_driver_ids()
	if not active_drivers.is_empty():
		selected_driver_id = active_drivers[0]
