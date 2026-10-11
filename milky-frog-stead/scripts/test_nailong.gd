extends Node2D
## 奶龙测试场景：纯色地面 + 网格
##
## 为什么要有网格：**这是验证 walk_speed 和 walk_fps 配平没有的唯一办法**。
## 站定看网格，按 A/D 走起来，盯着落地的脚——脚相对地面基本不动就是配平了；
## 脚明显往前/往后蹭，就是 walk_speed 和 walk_fps 不匹配（见 nailong.gd 里 walk_fps 的说明）。
##
## 节点自己是父节点，_draw() 先画、子节点后画，所以地面天然在奶龙背后，不用管 z_index。

## 地面半径（像素）。整个可走范围是 2 倍这个值的正方形。
@export var ground_half_size: float = 2000.0
## 地面颜色（草地绿，和黄色奶龙对比够）
@export var ground_color: Color = Color("5b8c4a")
## 细网格线颜色
@export var grid_color: Color = Color(0.0, 0.0, 0.0, 0.10)
## 粗网格线颜色（每 grid_major_every 格一条）
@export var major_color: Color = Color(0.0, 0.0, 0.0, 0.22)
## 网格间距（像素）
@export var grid_step: float = 64.0
## 每隔几格画一条粗线
@export var grid_major_every: int = 4


func _draw() -> void:
	var half := ground_half_size
	draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0), ground_color)

	var lines := int(half / grid_step)
	for i in range(-lines, lines + 1):
		var offset := float(i) * grid_step
		var is_major := i % grid_major_every == 0
		var color := major_color if is_major else grid_color
		var width := 2.0 if is_major else 1.0
		draw_line(Vector2(offset, -half), Vector2(offset, half), color, width)
		draw_line(Vector2(-half, offset), Vector2(half, offset), color, width)
