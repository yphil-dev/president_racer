class_name PlayerCar
extends Vehicle

var control_scheme: String = RaceSelection.CONTROL_COMBO

func get_control_input() -> Vector2:
	match control_scheme:
		RaceSelection.CONTROL_ARROW:
			return _keyboard_input(KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN)
		RaceSelection.CONTROL_WASD:
			return _keyboard_input(KEY_A, KEY_D, KEY_W, KEY_S)
		RaceSelection.CONTROL_COMBO:
			return _combine_inputs(
				_keyboard_input(KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN),
				_gamepad_input(1)
			)
		RaceSelection.CONTROL_GAMEPAD_1:
			return _gamepad_input(1)
		RaceSelection.CONTROL_GAMEPAD_2:
			return _gamepad_input(2)
		RaceSelection.CONTROL_GAMEPAD_3:
			return _gamepad_input(3)
		RaceSelection.CONTROL_GAMEPAD_4:
			return _gamepad_input(4)
	return Vector2.ZERO

func _keyboard_input(left_key: int, right_key: int, forward_key: int, back_key: int) -> Vector2:
	return Vector2(
		float(Input.is_physical_key_pressed(right_key)) - float(Input.is_physical_key_pressed(left_key)),
		float(Input.is_physical_key_pressed(forward_key)) - float(Input.is_physical_key_pressed(back_key))
	)

func _gamepad_input(controller_number: int) -> Vector2:
	var connected_pads := Input.get_connected_joypads()
	if controller_number < 1 or controller_number > connected_pads.size():
		return Vector2.ZERO

	var device_id: int = connected_pads[controller_number - 1]
	var steering := Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X)
	var forward := maxf(0.0, Input.get_joy_axis(device_id, JOY_AXIS_TRIGGER_RIGHT))
	var reverse := maxf(0.0, Input.get_joy_axis(device_id, JOY_AXIS_TRIGGER_LEFT))
	return Vector2(steering, forward - reverse).clamp(Vector2(-1.0, -1.0), Vector2(1.0, 1.0))

func _combine_inputs(first: Vector2, second: Vector2) -> Vector2:
	return (first + second).clamp(Vector2(-1.0, -1.0), Vector2(1.0, 1.0))
