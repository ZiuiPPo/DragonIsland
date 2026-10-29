extends CharacterBody2D
## 原型用的走路小方块。只为验证"玩家移动 → 跨区块 → 重烤高度图"这条链路。

@export var speed: float = 260.0
@export var sprint_mult: float = 2.2


func _physics_process(_delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var s := speed
	if Input.is_action_pressed("sprint"):
		s *= sprint_mult
	velocity = dir * s
	move_and_slide()
