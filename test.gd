extends Node3D

var index : int = 0

func send_new_value() -> void:
	index += 1
	Globals.change_index.emit(index)
