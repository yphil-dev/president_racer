extends TextureButton

@export var url: String = "https://yphil.gitlab.io/"

@onready var rollover_target: Control = get_parent() as Control

var _hovered: bool = false
var _focused: bool = false
var _rollover_tween: Tween

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	pressed.connect(_on_pressed)

func _on_mouse_entered() -> void:
	_hovered = true
	_update_rollover()

func _on_mouse_exited() -> void:
	_hovered = false
	_update_rollover()

func _on_focus_entered() -> void:
	_focused = true
	_update_rollover()

func _on_focus_exited() -> void:
	_focused = false
	_update_rollover()

func _update_rollover() -> void:
	if _rollover_tween != null and _rollover_tween.is_valid():
		_rollover_tween.kill()

	var active := _hovered or _focused
	_rollover_tween = create_tween().set_parallel(true)
	_rollover_tween.tween_property(
		rollover_target,
		"scale",
		Vector2(1.05, 1.05) if active else Vector2.ONE,
		0.1
	)
	_rollover_tween.tween_property(
		rollover_target,
		"self_modulate",
		Color(1.2, 1.2, 1.2, 1.0) if active else Color.WHITE,
		0.1
	)

func _on_pressed() -> void:
	OS.shell_open(url)
