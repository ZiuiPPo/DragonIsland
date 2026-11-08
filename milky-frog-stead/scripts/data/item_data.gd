class_name ItemData
extends Resource
## 一种物品的统一数据（种子 / 作物 / 畜牧产物 / 渔获 / 果树产物）。
##
## 这是「统一食物物品 ID」的唯一真相：id 一律小写英文 snake_case，
## 任何系统（种地、养鸡、钓鱼、种树、仓库、喂食、合成）都只用这个 id 字符串。
## 改 .tres 即可改数值/图标/堆叠，不要把 id 写死在脚本里。

enum Category { SEED, CROP, ANIMAL, FISH, FRUIT }

@export var id: String = ""
@export var display_name: String = "物品"
@export var icon: Texture2D
## 分类：种子 / 作物 / 畜牧产物 / 渔获 / 果树产物
@export var category: Category = Category.CROP
## 能否作餐厅食材
@export var is_ingredient: bool = false
## 是否种子（商店/播种用它判断）
@export var is_seed: bool = false
## 是否饲料（养鸡等投喂用）
@export var is_feed: bool = false
@export var buy_price: int = 0
@export var sell_price: int = 0
## 仓库单格堆叠上限（仓库 UI 一格最多 64）
@export var stack_max: int = 64
## 喂给奶蛙能恢复多少饱腹度；0 = 不能喂（种子/饲料原料）
@export var satiety_restore: float = 0.0
@export_multiline var description: String = ""
