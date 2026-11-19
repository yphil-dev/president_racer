extends CanvasLayer

signal fullscreen_changed(fullscreen: bool)

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const DISPLAY_SETTINGS_PATH := "user://display_settings.cfg"
const DISPLAY_SETTINGS_SECTION := "display"
const POTATO_ROCK_OVERLAY: PackedScene = preload("res://scenes/potato_rock_overlay.tscn")
const SPLASH_TEXTURE: Texture2D = preload("res://splash-screen.png")
const UI_SOUND_VOLUME_DB: float = -15.0

const EXPAND_DURATION: float = 0.7
const REVEAL_DURATION: float = 0.6
const MENU_COVER_DURATION: float = 1.45
const RESTART_FADE_IN_DURATION: float = 0.7
const RESTART_FADE_OUT_DURATION: float = 0.25
const RESTART_FADE_COLOR: Color = Color("#25354c")

var _overlay: Control
var _potato_rock_overlay
var _preview: TextureRect
var _black: ColorRect
var _confirmation_sound: AudioStreamPlayer
var _action_sound: AudioStreamPlayer
var _error_sound: AudioStreamPlayer
var _active: bool = false
var _ui_feedback_armed: bool = false
var _hover_sound_button: BaseButton
var _main_menu_focus_target: StringName = &"default"

func _ready() -> void:
	if not get_tree().node_added.is_connected(_on_ui_node_added):
		get_tree().node_added.connect(_on_ui_node_added)
	for node in get_tree().root.find_children("*", "", true, false):
		_on_ui_node_added(node)

	if OS.has_feature("arm64") or OS.has_feature("arm32"):
		if not get_tree().node_added.is_connected(_on_arm_node_added):
			get_tree().node_added.connect(_on_arm_node_added)
		for node in get_tree().root.find_children("*", "Node", true, false):
			_on_arm_node_added(node)

	layer = 100
	_apply_fullscreen_preference()

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
	_confirmation_sound.volume_db = UI_SOUND_VOLUME_DB
	_confirmation_sound.set_meta(&"ui_interaction_audio", true)
	add_child(_confirmation_sound)

	_action_sound = AudioStreamPlayer.new()
	_action_sound.stream = _create_action_beep()
	_action_sound.volume_db = UI_SOUND_VOLUME_DB
	_action_sound.set_meta(&"ui_interaction_audio", true)
	add_child(_action_sound)

	_error_sound = AudioStreamPlayer.new()
	_error_sound.stream = _create_error_beep()
	_error_sound.volume_db = UI_SOUND_VOLUME_DB
	_error_sound.set_meta(&"ui_interaction_audio", true)
	add_child(_error_sound)

	_potato_rock_overlay = POTATO_ROCK_OVERLAY.instantiate()
	add_child(_potato_rock_overlay)
	_initialize_potato_rock.call_deferred()

func _on_ui_node_added(node: Node) -> void:
	if not node is BaseButton:
		return
	var button := node as BaseButton
	var focus_callback := _play_button_focus.bind(button)
	var hover_callback := _play_button_hover.bind(button)
	var press_callback := _play_button_press.bind(button)
	if not button.focus_entered.is_connected(focus_callback):
		button.focus_entered.connect(focus_callback)
	if not button.mouse_entered.is_connected(hover_callback):
		button.mouse_entered.connect(hover_callback)
	if not button.pressed.is_connected(press_callback):
		button.pressed.connect(press_callback)

func _play_button_focus(button: BaseButton) -> void:
	if _hover_sound_button == button:
		return
	play_selection_beep()

func _play_button_hover(button: BaseButton) -> void:
	_hover_sound_button = button
	play_selection_beep(true)
	_clear_hover_sound_button.call_deferred(button)

func _clear_hover_sound_button(button: BaseButton) -> void:
	if _hover_sound_button == button:
		_hover_sound_button = null

func _play_button_press(button: BaseButton) -> void:
	if button.get_meta(&"honk_on_press", false):
		AudioPlayer.play_honk()
	else:
		play_action_beep()

func _on_arm_node_added(node: Node) -> void:
	if node is Light3D:
		node.shadow_enabled = false
	elif node is WorldEnvironment and node.environment != null:
		var env: Environment = (node as WorldEnvironment).environment
		env.glow_enabled = false
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.sdfgi_enabled = false
		env.fog_enabled = false
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.45, 0.72, 0.95)
	elif node is SubViewport:
		node.render_target_update_mode = SubViewport.UPDATE_ONCE
		node.use_occlusion_culling = false
		node.msaa_3d = Viewport.MSAA_DISABLED
		node.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		node.use_hdr_2d = false
	elif node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		if not _is_player_effect_mesh(node):
			mesh_inst.material_overlay = null
		for i in mesh_inst.get_surface_override_material_count():
			var mat: Material = mesh_inst.get_active_material(i)
			if mat is StandardMaterial3D:
				(mat as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
				(mat as StandardMaterial3D).specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		if mesh_inst.mesh != null:
			for i in mesh_inst.mesh.get_surface_count():
				var smat: Material = mesh_inst.mesh.surface_get_material(i)
				if smat is StandardMaterial3D:
					(smat as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
					(smat as StandardMaterial3D).specular_mode = BaseMaterial3D.SPECULAR_DISABLED

func _is_player_effect_mesh(node: Node) -> bool:
	var current := node
	while current != null:
		if current.name.begins_with("PlayerMarker_"):
			return true
		if current.is_in_group("race_vehicles"):
			var driver_id := str(current.get("driver_id"))
			return not driver_id.is_empty() and RaceSelection.is_driver_human(driver_id)
		current = current.get_parent()
	return false

func _input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.ctrl_pressed
		and event.keycode == KEY_Q
	):
		get_viewport().set_input_as_handled()
		quit_game()
		return

	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and (
			event.physical_keycode == KEY_F11
			or (
				event.physical_keycode == KEY_F
				and not event.alt_pressed
				and not event.meta_pressed
			)
			or (
				event.alt_pressed
				and (
					event.physical_keycode == KEY_ENTER
					or event.physical_keycode == KEY_KP_ENTER
				)
			)
		)
	):
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return

	if _ui_feedback_armed:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_ui_feedback_armed = true
	elif event is InputEventMouseButton and event.pressed:
		_ui_feedback_armed = true
	elif event is InputEventJoypadButton and event.pressed:
		_ui_feedback_armed = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) >= 0.5:
		_ui_feedback_armed = true

func is_active() -> bool:
	return _active

func request_main_menu_quit_focus() -> void:
	_main_menu_focus_target = &"quit"

func consume_main_menu_focus_target() -> StringName:
	var target := _main_menu_focus_target
	_main_menu_focus_target = &"default"
	return target

func show_potato_rock() -> void:
	if _potato_rock_overlay == null:
		return
	_potato_rock_overlay.show()
	_potato_rock_overlay.configure_navigation(get_tree().current_scene)

func _initialize_potato_rock() -> void:
	await get_tree().process_frame
	show_potato_rock()

func _toggle_fullscreen() -> void:
	set_fullscreen_enabled(not is_fullscreen_enabled())

func is_fullscreen_enabled() -> bool:
	return DisplayServer.window_get_mode() in [
		DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
	]

func set_fullscreen_enabled(fullscreen: bool, save_preference: bool = true) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if fullscreen
		else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if save_preference:
		_save_fullscreen_preference(fullscreen)
	fullscreen_changed.emit(fullscreen)

func _apply_fullscreen_preference() -> void:
	var config := ConfigFile.new()
	if config.load(DISPLAY_SETTINGS_PATH) != OK:
		return
	if not config.has_section_key(DISPLAY_SETTINGS_SECTION, "fullscreen"):
		return

	var fullscreen := bool(config.get_value(DISPLAY_SETTINGS_SECTION, "fullscreen"))
	set_fullscreen_enabled(fullscreen, false)

func _save_fullscreen_preference(fullscreen: bool) -> void:
	var config := ConfigFile.new()
	config.set_value(DISPLAY_SETTINGS_SECTION, "fullscreen", fullscreen)
	config.save(DISPLAY_SETTINGS_PATH)

func transition_to_track(
	scene_path: String,
	preview_texture: Texture2D,
	start_rect: Rect2
) -> void:
	if _active:
		return

	_active = true
	_potato_rock_overlay.set_interactive(false)
	_potato_rock_overlay.hide()
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

func transition_to_restart(scene_path: String) -> void:
	if _active:
		return

	_active = true
	_potato_rock_overlay.set_interactive(false)
	_potato_rock_overlay.hide()
	_overlay.show()
	_preview.hide()
	var transparent_fade_color := RESTART_FADE_COLOR
	transparent_fade_color.a = 0.0
	_black.color = transparent_fade_color

	var fade_out_tween := create_tween()
	fade_out_tween.set_trans(Tween.TRANS_QUART)
	fade_out_tween.set_ease(Tween.EASE_IN_OUT)
	fade_out_tween.tween_property(_black, "color", RESTART_FADE_COLOR, RESTART_FADE_IN_DURATION)
	await fade_out_tween.finished

	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("Could not restart scene %s: error %d" % [scene_path, error])
		_reset()
		return

	await get_tree().process_frame
	await get_tree().process_frame
	_potato_rock_overlay.show()

	var fade_in_tween := create_tween()
	fade_in_tween.set_trans(Tween.TRANS_QUART)
	fade_in_tween.set_ease(Tween.EASE_OUT)
	fade_in_tween.tween_property(_black, "color", transparent_fade_color, RESTART_FADE_OUT_DURATION)
	await fade_in_tween.finished
	show_potato_rock()
	_reset()

func transition_to_scene(scene_path: String) -> void:
	if _active:
		return

	_active = true
	_potato_rock_overlay.set_interactive(false)
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
	_potato_rock_overlay.show()

	var reveal_tween := create_tween()
	reveal_tween.set_trans(Tween.TRANS_QUART)
	reveal_tween.set_ease(Tween.EASE_OUT)
	reveal_tween.tween_property(_preview, "modulate", Color(1, 1, 1, 0), REVEAL_DURATION)
	await reveal_tween.finished
	show_potato_rock()
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

func play_selection_beep(force: bool = false) -> void:
	if not force and not _ui_feedback_armed:
		return
	_confirmation_sound.stop()
	_confirmation_sound.play()

func play_action_beep() -> void:
	_action_sound.stop()
	_action_sound.play()

func play_error_beep() -> void:
	if not _ui_feedback_armed:
		return
	_error_sound.stop()
	_error_sound.play()

func _create_confirmation_beep() -> AudioStreamWAV:
	const SAMPLE_RATE: int = 22050
	const DURATION: float = 0.16
	const FREQUENCY: float = 120.0
	const AMPLITUDE: float = 0.28
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

func _create_action_beep() -> AudioStreamWAV:
	const SAMPLE_RATE: int = 22050
	const DURATION: float = 0.09
	const FREQUENCY: float = 240.0
	const AMPLITUDE: float = 0.22
	const ATTACK: float = 0.005
	const RELEASE: float = 0.05

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

func _create_error_beep() -> AudioStreamWAV:
	const SAMPLE_RATE: int = 22050
	const DURATION: float = 0.18
	const START_FREQUENCY: float = 220.0
	const END_FREQUENCY: float = 150.0
	const AMPLITUDE: float = 0.24
	const ATTACK: float = 0.01
	const RELEASE: float = 0.08

	var sample_count := int(SAMPLE_RATE * DURATION)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	for sample_index in sample_count:
		var time := float(sample_index) / SAMPLE_RATE
		var envelope := minf(time / ATTACK, 1.0)
		if time > DURATION - RELEASE:
			envelope *= (DURATION - time) / RELEASE
		var frequency := lerpf(START_FREQUENCY, END_FREQUENCY, time / DURATION)
		var wave := sin(TAU * frequency * time) * AMPLITUDE * envelope
		data.encode_s16(sample_index * 2, int(wave * 32767.0))

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	return stream

func _reset() -> void:
	_confirmation_sound.stop()
	_action_sound.stop()
	_error_sound.stop()
	_preview.texture = null
	_preview.modulate = Color.WHITE
	_preview.hide()
	_black.color = Color(0, 0, 0, 0)
	_overlay.hide()
	_active = false
