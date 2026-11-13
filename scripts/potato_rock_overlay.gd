extends Control

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const DRIVER_SELECTION_SCENE := "res://scenes/options_menu.tscn"
const SPRITE_SHEET: Texture2D = preload("res://sprites/potato_rock_tired_roll_32frames_8x4_200x100.png")
const ROLL_SOUND: AudioStream = preload("res://audio/rolling_stone.ogg")
const SPROUT_SOUND: AudioStream = preload("res://audio/sprout.ogg")
const FRAME_SIZE := Vector2(200, 100)
const FRAME_COLUMNS: int = 8
const FRAME_COUNT: int = 32
const LABEL_DELAY: float = 4.0
const LABEL_FADE_DURATION: float = 1.0
const STUDIO_DELAY: float = 5.0
const STUDIO_FADE_DURATION: float = 0.1
const SOUND_DELAY: float = 1.0

@onready var animation: AnimatedSprite2D = $Animation
@onready var roll: AudioStreamPlayer2D = $Roll
@onready var sprout: AudioStreamPlayer2D = $Sprout
@onready var potato_rock_label: Label = $PotatoRock
@onready var studio_label: Label = $Studio
@onready var potato_rock_button: TextureButton = $PotatoRockButton

var _intro_finished: bool = false

func _ready() -> void:
	animation.sprite_frames = _create_sprite_frames()
	roll.stream = ROLL_SOUND
	sprout.stream = SPROUT_SOUND
	potato_rock_label.modulate = Color(1, 1, 1, 0)
	studio_label.modulate = Color(1, 1, 1, 0)
	animation.play(&"default")
	_fade_in_label(potato_rock_label, LABEL_DELAY, LABEL_FADE_DURATION)
	_fade_in_label(studio_label, STUDIO_DELAY, STUDIO_FADE_DURATION)
	set_interactive(false)
	_play_sound_sequence()
	_unlock_interaction_after_intro()

func configure_navigation(scene: Node) -> void:
	potato_rock_button.focus_mode = Control.FOCUS_NONE
	if not _intro_finished:
		set_interactive(false)
		return

	potato_rock_button.mouse_filter = Control.MOUSE_FILTER_STOP
	if scene.scene_file_path == MAIN_MENU_SCENE:
		potato_rock_button.focus_mode = Control.FOCUS_ALL
		_connect_main_menu_navigation(scene)

func set_interactive(interactive: bool) -> void:
	potato_rock_button.mouse_filter = (
		Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	)
	if not interactive:
		potato_rock_button.focus_mode = Control.FOCUS_NONE

func _create_sprite_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.set_animation_loop(&"default", false)
	frames.set_animation_speed(&"default", 5.0)

	for frame_index in FRAME_COUNT:
		var texture := AtlasTexture.new()
		texture.atlas = SPRITE_SHEET
		texture.region = Rect2(
			float(frame_index % FRAME_COLUMNS) * FRAME_SIZE.x,
			float(frame_index / FRAME_COLUMNS) * FRAME_SIZE.y,
			FRAME_SIZE.x,
			FRAME_SIZE.y
		)
		frames.add_frame(&"default", texture)

	return frames

func _fade_in_label(label: Label, delay: float, duration: float) -> void:
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(label, "modulate", Color.WHITE, duration)

func _play_sound_sequence() -> void:
	await get_tree().create_timer(SOUND_DELAY).timeout
	roll.play()
	await roll.finished
	sprout.play()

func _unlock_interaction_after_intro() -> void:
	await get_tree().create_timer(8.0).timeout
	_intro_finished = true
	configure_navigation(get_tree().current_scene)

func _connect_main_menu_navigation(scene: Node) -> void:
	var limoges := scene.get_node_or_null("TrackGrid/Limoges") as Control
	var options := scene.get_node_or_null("Options") as Control
	if limoges == null or options == null:
		return

	limoges.set_focus_neighbor(
		Side.SIDE_BOTTOM,
		limoges.get_path_to(potato_rock_button)
	)
	options.set_focus_neighbor(
		Side.SIDE_LEFT,
		options.get_path_to(potato_rock_button)
	)
	potato_rock_button.set_focus_neighbor(
		Side.SIDE_TOP,
		potato_rock_button.get_path_to(limoges)
	)
	potato_rock_button.set_focus_neighbor(
		Side.SIDE_RIGHT,
		potato_rock_button.get_path_to(options)
	)
