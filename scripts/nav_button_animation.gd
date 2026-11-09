class_name NavButtonAnimation
extends RefCounted

const PRESSED_SCALE := Vector2(0.97, 0.97)
const PRESS_DURATION: float = 0.08
const RELEASE_DURATION: float = 0.14

static func play(button: Button) -> void:
	button.pivot_offset = button.size * 0.5

	var tween := button.create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(button, "scale", PRESSED_SCALE, PRESS_DURATION)
	tween.tween_property(button, "scale", Vector2.ONE, RELEASE_DURATION)
	await tween.finished
