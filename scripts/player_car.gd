class_name PlayerCar
extends Vehicle

var player_slot: int = 0
var input_source: int = RaceSelection.InputSource.ARROWS

func get_control_input() -> Vector2:
	var controls: Vector2 = _input_for_source(input_source)
	if RaceSelection.should_use_solo_input_fallback(driver_id):
		controls = _combine_inputs(
			_input_for_source(RaceSelection.InputSource.ARROWS),
			_input_for_source(RaceSelection.InputSource.PAD_1)
		)
	return controls

func _input_for_source(source: int) -> Vector2:
	if source >= RaceSelection.InputSource.PAD_1 and source <= RaceSelection.InputSource.PAD_4:
		return _gamepad_input(RaceSelection.get_gamepad_number(source))
	match source:
		RaceSelection.InputSource.ARROWS:
			return _keyboard_input(
				[KEY_LEFT],
				[KEY_RIGHT],
				[KEY_UP],
				[KEY_DOWN]
			)
		RaceSelection.InputSource.WASD:
			return _keyboard_input(
				[KEY_A, KEY_Q],
				[KEY_D],
				[KEY_W, KEY_Z],
				[KEY_S]
			)
	return Vector2.ZERO

func _keyboard_input(
	left_keys: Array[int],
	right_keys: Array[int],
	forward_keys: Array[int],
	back_keys: Array[int]
) -> Vector2:
	return Vector2(
		float(_any_physical_key_pressed(right_keys)) - float(_any_physical_key_pressed(left_keys)),
		float(_any_physical_key_pressed(forward_keys)) - float(_any_physical_key_pressed(back_keys))
	)

func _any_physical_key_pressed(keys: Array[int]) -> bool:
	for keycode in keys:
		if Input.is_physical_key_pressed(keycode):
			return true
	return false

func _gamepad_input(controller_number: int) -> Vector2:
	var connected_pads: Array[int] = Input.get_connected_joypads()
	if controller_number < 1 or controller_number > connected_pads.size():
		return Vector2.ZERO

	var device_id: int = connected_pads[controller_number - 1]
	var steering: float = Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X)
	if Input.is_joy_button_pressed(device_id, JOY_BUTTON_DPAD_LEFT):
		steering -= 1.0
	if Input.is_joy_button_pressed(device_id, JOY_BUTTON_DPAD_RIGHT):
		steering += 1.0
	var forward: float = maxf(0.0, Input.get_joy_axis(device_id, JOY_AXIS_TRIGGER_RIGHT))
	var reverse: float = maxf(0.0, Input.get_joy_axis(device_id, JOY_AXIS_TRIGGER_LEFT))
	if Input.is_joy_button_pressed(device_id, JOY_BUTTON_A):
		forward = 1.0
	if Input.is_joy_button_pressed(device_id, JOY_BUTTON_DPAD_UP):
		forward = 1.0
	if Input.is_joy_button_pressed(device_id, JOY_BUTTON_DPAD_DOWN):
		reverse = 1.0
	return Vector2(steering, forward - reverse).clamp(
		Vector2(-1.0, -1.0),
		Vector2(1.0, 1.0)
	)

func _combine_inputs(first: Vector2, second: Vector2) -> Vector2:
	return (first + second).clamp(Vector2(-1.0, -1.0), Vector2(1.0, 1.0))
