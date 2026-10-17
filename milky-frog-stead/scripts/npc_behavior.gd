class_name NpcBehavior extends Node2D
var npc : Npc

func _ready() -> void:
	var p = get_parent()
	if p is Npc:
		npc = p as Npc
		#connect to signal
