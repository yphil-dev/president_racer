extends TextureButton

@export var url: String = "https://yphil.gitlab.io/"

const ROLLOVER_SCALE_MULTIPLIER: float = 1.11

@onready var rollover_target: Control = get_parent() as Control

var _hovered: bool = false
var _rollover_tween: Tween
var _content_scale := Vector2.ONE

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	_content_scale = rollover_target.scale
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	pressed.connect(_on_pressed)

func _on_mouse_entered() -> void:
	_hovered = true
	_update_rollover()

func _on_mouse_exited() -> void:
	_hovered = false
	_update_rollover()

func _update_rollover() -> void:
	if _rollover_tween != null and _rollover_tween.is_valid():
		_rollover_tween.kill()
#
	var active := _hovered
	_rollover_tween = create_tween().set_parallel(true)
	_rollover_tween.tween_property(
		rollover_target,
		"scale",
		_content_scale * ROLLOVER_SCALE_MULTIPLIER if active else _content_scale,
		0.1
	)
	_rollover_tween.tween_property(
		rollover_target,
		"self_modulate",
		Color.WHITE if active else Color(0.6, 0.6, 0.6, 1.0),
		0.1
	)

func _on_pressed() -> void:
	OS.shell_open(url)
