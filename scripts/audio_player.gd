extends Node

@export var bar: AudioStreamPlayer2D
@export var honk: AudioStreamPlayer2D
@export var victory: AudioStreamPlayer2D
@export var loser: AudioStreamPlayer2D

const SILENT_DB: float = -80.0
const TARGET_DB: float = -18.0  # adjust to taste

var _fade_tween: Tween

func _ready() -> void:
	bar.volume_db = SILENT_DB

func fade_in(duration: float = 2.4) -> void:
	_kill_fade()
	if not bar.playing:
		bar.play()
	_fade_tween = create_tween()
	_fade_tween.tween_property(bar, "volume_db", TARGET_DB, duration)

func fade_out_and_stop(duration: float = 1.0) -> void:
	honk.play()
	_kill_fade()
	_fade_tween = create_tween()
	_fade_tween.tween_property(bar, "volume_db", SILENT_DB, duration)
	_fade_tween.tween_callback(bar.stop)

func play_result(player_won: bool) -> void:
	victory.stop()
	loser.stop()
	if player_won:
		victory.play()
	else:
		loser.play()

func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
