extends Node

const DEBUG_VERBOSE: bool = false

func _ready() -> void:
	if not DEBUG_VERBOSE:
		print("Verbose debug messages are disabled. Set Debug.DEBUG_VERBOSE to true to see them.")
