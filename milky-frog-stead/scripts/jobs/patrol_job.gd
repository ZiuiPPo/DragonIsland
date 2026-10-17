class_name PatrolJob
extends NpcJob
## 巡逻岗位：在若干路点之间循环或原路折返。

## 路点，**相对 NPC 出生点**的偏移（不是世界坐标）。
## 用偏移而不是世界坐标，是为了同一份 .tres 交给地图上任何位置的 NPC，路线都跟着它走
@export var offsets: Array[Vector2] = []
## 走到一个点之后发呆多久（秒），在 x~y 之间随机取
@export var wait_time_range: Vector2 = Vector2(0.6, 1.8)
## true = 走到最后一个点后跳回第一个点；false = 原路折返（走到头掉头）
@export var loop_mode: bool = false

var _index := 0
var _dir := 1
var _wait_left := 0.0


## 上岗 / 指令结束回到岗位。
## **故意不重置 _index**：被玩家叫走一趟回来，接着去原来那个点。
## 重置的话它每次都要横穿整张地图跑回第一个路点，看着像抽风
func start(_npc: Npc) -> void:
	_wait_left = 0.0


func tick(npc: Npc, delta: float) -> void:
	# 已经在路上 → 等移动层的结果：到了走 on_arrived()，走不到走 on_stuck()
	if npc.locomotion.has_target():
		return
	if _wait_left > 0.0:
		_wait_left -= delta
		return
	if offsets.is_empty():
		return
	npc.locomotion.move_to(npc.home_position + offsets[_index])


func on_arrived(_npc: Npc) -> void:
	_advance()
	_wait_left = _random_wait()


func on_stuck(_npc: Npc) -> void:
	# 这个点到不了（落在墙里 / 被家具挡死），跳过它。
	# 少了这句，NPC 会顶着一个永远到不了的点一直推 —— 看起来就是卡死
	_advance()
	_wait_left = _random_wait()


## 走到下一个路点。折返模式到两头要掉头，循环模式直接取模
func _advance() -> void:
	if offsets.size() <= 1:
		_index = 0
		return
	if loop_mode:
		_index = (_index + 1) % offsets.size()
		return
	_index += _dir
	if _index >= offsets.size():
		_dir = -1
		_index = offsets.size() - 2
	elif _index < 0:
		_dir = 1
		_index = 1


func _random_wait() -> float:
	return randf_range(wait_time_range.x, wait_time_range.y)
