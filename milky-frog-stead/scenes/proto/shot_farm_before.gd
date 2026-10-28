extends Node2D
## A/B 对照用的壳：加载正式场景，把草丛层和地面色块都关掉，截一张"改之前"的图。
##
##   godot --path . res://scenes/proto/shot_farm_before.tscn -- --shot D:/before.png

func _ready() -> void:
	await get_tree().process_frame
	var farm := get_node_or_null("Farm")
	if farm:
		var g := farm.get_node_or_null("GrassField")
		if g:
			g.visible = false
		var grass_layer := farm.get_node_or_null("Level/Layers/GrassLayer")
		if grass_layer:
			grass_layer.material = null
