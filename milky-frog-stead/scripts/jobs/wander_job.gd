class_name WanderJob
extends NpcJob
## 游荡岗位：在出生点周围随机挑点走，走到发呆一会儿再挑下一个。

## 随机取点范围的横纵半径（以 center_offset 为中心的椭圆）
@export var radius: Vector2 = Vector2(180.0, 120.0)
## 游荡中心相对出生点的偏移。想让它只在地图左半边晃就调这个
@export var center_offset: Vector2 = Vector2.ZERO
## 走到一个点之后发呆多久（秒），在 x~y 之间随机取
@export var wait_time_range: Vector2 = Vector2(0.6, 1.8)

var _wait_left := 0.0


func start(_npc: Npc) -> void:
	_wait_left = 0.0


func tick(npc: Npc, delta: float) -> void:
	if npc.locomotion.has_target():
		return
	if _wait_left > 0.0:
		_wait_left -= delta
		return
	npc.locomotion.move_to(_random_point(npc))


func on_arrived(_npc: Npc) -> void:
	_wait_left = _random_wait()


func on_stuck(_npc: Npc) -> void:
	# 随机挑的点落进了死角（比如圈选到了墙里），稍微停一下就换一个
	_wait_left = 0.3


## 椭圆内均匀取一点。
## 半径必须开方（sqrt(randf())）：直接用 randf() 的话点在椭圆里会明显往圆心堆，
## 因为面积是按 r² 涨的 —— 表现出来就是它老在出生点附近打转，不肯走远
func _random_point(npc: Npc) -> Vector2:
	var center := npc.home_position + center_offset
	var angle := randf() * TAU
	var scale := sqrt(randf())
	return center + Vector2(
		cos(angle) * radius.x * scale,
		sin(angle) * radius.y * scale
	)


func _random_wait() -> float:
	return randf_range(wait_time_range.x, wait_time_range.y)
