extends PanelContainer
## 仓库 / 背包里的一个格子：图标 + 右下角数量。
## 一格只放同一种物品，最多 MAX_STACK 个（超出部分应该另开一格）。

## 每格堆叠上限
const MAX_STACK: int = 64

@onready var _icon: TextureRect = $Icon
@onready var _count: Label = $Count


## 填入物品。texture 传 null 或 amount <= 0 就是空格子。
## amount 超过 MAX_STACK 会被夹到 64 —— 多出来的部分应该由调用方拆到下一格。
func setup(texture: Texture2D, amount: int) -> void:
	_icon.texture = texture
	_count.text = str(clampi(amount, 0, MAX_STACK)) if amount > 0 else ""


## 清空格子
func clear() -> void:
	setup(null, 0)
