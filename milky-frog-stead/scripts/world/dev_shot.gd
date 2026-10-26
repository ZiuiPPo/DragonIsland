extends Node
## 开发用截图器：godot ... res://scenes/proto/shot_farm.tscn -- --shot out.png
## 顺便把场景里所有 TileMapLayer 的 used_rect 打出来，方便算岛屿范围。

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--shot":
		_go(args[1])


func _go(path: String) -> void:
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[shot] ", path, " ", img.get_size())
	_dump(get_tree().root)
	# --anim：0.7 秒后再截一张，用来确认水在动、地不动
	if "--anim" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.7).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(path.replace(".png", "_b.png"))
		print("[shot] second frame")
	get_tree().quit()


func _dump(n: Node) -> void:
	for c in n.get_children():
		if c is TileMapLayer:
			var layer := c as TileMapLayer
			var tsz := Vector2i(16, 16)
			if layer.tile_set:
				tsz = layer.tile_set.tile_size
			var counts := {}
			for cell in layer.get_used_cells():
				var src := layer.get_cell_source_id(cell)
				var at := layer.get_cell_atlas_coords(cell)
				var key := "%d:%s" % [src, at]
				counts[key] = int(counts.get(key, 0)) + 1
			var top := counts.keys()
			top.sort_custom(func(a, b): return counts[a] > counts[b])
			print("[layer] %-16s used=%s  tile_size=%s  scale=%s  cells=%d" % [
				String(layer.name), layer.get_used_rect(), tsz, layer.scale,
				layer.get_used_cells().size()])
			print("         atlas coords: ", ", ".join(top.slice(0, 8).map(
					func(k): return "%s x%d" % [k, counts[k]])))
		_dump(c)
