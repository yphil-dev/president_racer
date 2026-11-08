extends TextureButton

@export var url: String = "https://yphil.gitlab.io/projects/"

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Center the pivot point so it grows perfectly from the middle
	pivot_offset = size * 0.5

	# Connect the hover effects (no extra images needed!)
	mouse_entered.connect(_on_hover)
	mouse_exited.connect(_on_unhover)
	pressed.connect(_on_pressed)

func _on_hover() -> void:
	# Make it grow slightly and brighten up
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.05, 1.05), 0.1)
	tween.tween_property(self, "self_modulate", Color(1.2, 1.2, 1.2, 1.0), 0.1) # Glowing boost

func _on_unhover() -> void:
	# Shrink back to normal scale and normal color tint
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE, 0.1)
	tween.tween_property(self, "self_modulate", Color.WHITE, 0.1)

func _on_pressed() -> void:
	OS.shell_open(url)
