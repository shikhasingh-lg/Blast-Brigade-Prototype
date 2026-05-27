extends Node
## Boot scene. Routes to MetaHub so the full meta loop is reachable.
## To jump straight into combat for prototype testing, hold SHIFT at boot.

func _ready() -> void:
	var skip_meta: bool = Input.is_key_pressed(KEY_SHIFT)
	var target: String = "res://scenes/MatchScene.tscn" if skip_meta \
		else "res://scenes/MetaHub.tscn"
	get_tree().change_scene_to_file.call_deferred(target)
