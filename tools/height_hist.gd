extends SceneTree
## 量一下高度分布，用来定 h_water / h_sand 两个阈值。
## godot --headless --path <project> --script tools/height_hist.gd


func _init() -> void:
	var low := FastNoiseLite.new()
	low.noise_type = FastNoiseLite.TYPE_PERLIN
	low.fractal_type = FastNoiseLite.FRACTAL_FBM
	low.fractal_octaves = 3
	low.frequency = 0.0021
	low.seed = 20261026

	var mid := FastNoiseLite.new()
	mid.noise_type = FastNoiseLite.TYPE_PERLIN
	mid.fractal_type = FastNoiseLite.FRACTAL_FBM
	mid.fractal_octaves = 2
	mid.frequency = 0.0085
	mid.seed = 20261026

	var warp := FastNoiseLite.new()
	warp.noise_type = FastNoiseLite.TYPE_PERLIN
	warp.fractal_type = FastNoiseLite.FRACTAL_FBM
	warp.fractal_octaves = 2
	warp.frequency = 0.0045
	warp.seed = 20261026 + 7777

	var vals := PackedFloat32Array()
	for ty in range(-300, 300):
		for tx in range(-300, 300):
			var world := Vector2(tx * 16, ty * 16)
			var wx := warp.get_noise_2d(world.x, world.y) * 40.0
			var wy := warp.get_noise_2d(world.x + 1371.0, world.y - 571.0) * 40.0
			var p := world + Vector2(wx, wy)
			var n := low.get_noise_2d(p.x, p.y) * 0.75 + mid.get_noise_2d(p.x, p.y) * 0.25
			vals.append(n)

	vals.sort()
	var n := vals.size()
	print("样本 ", n)
	for q in [0.01, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95, 0.99]:
		print("  p%02d = %+.4f" % [int(q * 100), vals[int(n * q)]])
	print("min %+.4f  max %+.4f" % [vals[0], vals[n - 1]])

	# 用 0.5 + n*k 映射后，各阈值对应的水面占比
	for k in [0.62, 0.85, 1.0, 1.2]:
		var below := 0
		for v in vals:
			if 0.5 + v * k < 0.45:
				below += 1
		print("k=%.2f  水面占比 %.1f%%" % [k, 100.0 * below / n])
	quit()
