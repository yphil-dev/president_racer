extends CanvasLayer

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const SPLASH_TEXTURE: Texture2D = preload("res://splash-screen.png")

const EXPAND_DURATION: float = 0.7
const REVEAL_DURATION: float = 0.6
const MENU_COVER_DURATION: float = 0.45

var _overlay: Control
var _preview: TextureRect
var _black: ColorRect
var _confirmation_sound: AudioStreamPlayer
var _active: bool = false
var _ui_feedback_armed: bool = false

func _ready() -> void:
	layer = 100

	_overlay = Control.new()
	_overlay.name = "TransitionOverlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.hide()
	add_child(_overlay)

	_black = ColorRect.new()
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.color = Color(0, 0, 0, 0)
	_overlay.add_child(_black)

	_preview = TextureRect.new()
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_overlay.add_child(_preview)

	_confirmation_sound = AudioStreamPlayer.new()
	_confirmation_sound.stream = _create_confirmation_beep()
	_confirmation_sound.volume_db = -10.0
	add_child(_confirmation_sound)

func _input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.ctrl_pressed
		and event.physical_keycode == KEY_F
	):
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return

	if _ui_feedback_armed:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_ui_feedback_armed = true
	elif event is InputEventJoypadButton and event.pressed:
		_ui_feedback_armed = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= 0.5:
		_ui_feedback_armed = true

func is_active() -> bool:
	return _active

func _toggle_fullscreen() -> void:
	var current_mode := DisplayServer.window_get_mode()
	var is_fullscreen := current_mode in [
		DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
	]
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_WINDOWED
		if is_fullscreen
		else DisplayServer.WINDOW_MODE_FULLSCREEN
	)

func transition_to_track(
	scene_path: String,
	preview_texture: Texture2D,
	start_rect: Rect2
) -> void:
	if _active:
		return

	_active = true
	_overlay.show()
	_black.color = Color(0, 0, 0, 0)
	_preview.show()
	_preview.texture = preview_texture if preview_texture != null else SPLASH_TEXTURE
	_preview.modulate = Color.WHITE
	_preview.position = start_rect.position
	_preview.size = start_rect.size

	var viewport_size := get_viewport().get_visible_rect().size
	var expand_tween := create_tween()
	expand_tween.set_parallel(true)
	expand_tween.set_trans(Tween.TRANS_QUART)
	expand_tween.set_ease(Tween.EASE_IN_OUT)
	expand_tween.tween_property(_preview, "position", Vector2.ZERO, EXPAND_DURATION)
	expand_tween.tween_property(_preview, "size", viewport_size, EXPAND_DURATION)
	await expand_tween.finished

	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("Could not open scene %s: error %d" % [scene_path, error])
		_reset()
		return

	await get_tree().process_frame
	await get_tree().process_frame

	var reveal_tween := create_tween()
	reveal_tween.set_trans(Tween.TRANS_QUART)
	reveal_tween.set_ease(Tween.EASE_OUT)
	reveal_tween.tween_property(_preview, "modulate", Color(1, 1, 1, 0), REVEAL_DURATION)
	await reveal_tween.finished
	_reset()

func transition_to_menu() -> void:
	transition_to_scene(MAIN_MENU_SCENE)

func transition_to_scene(scene_path: String) -> void:
	if _active:
		return

	_active = true
	_overlay.show()
	_black.color = Color(0, 0, 0, 0)
	_preview.show()
	_preview.texture = SPLASH_TEXTURE
	_preview.position = Vector2.ZERO
	_preview.size = get_viewport().get_visible_rect().size
	_preview.modulate = Color(1, 1, 1, 0)

	var cover_tween := create_tween()
	cover_tween.set_trans(Tween.TRANS_QUART)
	cover_tween.set_ease(Tween.EASE_IN_OUT)
	cover_tween.tween_property(_preview, "modulate", Color.WHITE, MENU_COVER_DURATION)
	await cover_tween.finished

	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("Could not open scene %s: error %d" % [scene_path, error])
		_reset()
		return

	await get_tree().process_frame
	await get_tree().process_frame

	var reveal_tween := create_tween()
	reveal_tween.set_trans(Tween.TRANS_QUART)
	reveal_tween.set_ease(Tween.EASE_OUT)
	reveal_tween.tween_property(_preview, "modulate", Color(1, 1, 1, 0), REVEAL_DURATION)
	await reveal_tween.finished
	_reset()

func quit_game() -> void:
	if _active:
		return

	_active = true
	_overlay.show()
	_preview.hide()
	_black.color = Color(0, 0, 0, 0)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_black, "color", Color.BLACK, 0.35)
	await tween.finished
	get_tree().quit()

func play_selection_beep() -> void:
	if not _ui_feedback_armed:
		return
	_confirmation_sound.stop()
	_confirmation_sound.play()

func _create_confirmation_beep() -> AudioStreamWAV:
	const SAMPLE_RATE: int = 22050
	const DURATION: float = 0.12
	const FREQUENCY: float = 220.0
	const AMPLITUDE: float = 0.22
	const ATTACK: float = 0.01
	const RELEASE: float = 0.07

	var sample_count := int(SAMPLE_RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	for sample_index in sample_count:
		var time := float(sample_index) / SAMPLE_RATE
		var envelope := minf(time / ATTACK, 1.0)
		if time > DURATION - RELEASE:
			envelope *= (DURATION - time) / RELEASE
		var wave := sin(TAU * FREQUENCY * time) * AMPLITUDE * envelope
		data.encode_s16(sample_index * 2, int(wave * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream

func _reset() -> void:
	_confirmation_sound.stop()
	_preview.texture = null
	_preview.modulate = Color.WHITE
	_preview.hide()
	_black.color = Color(0, 0, 0, 0)
	_overlay.hide()
	_active = false
