class_name CropData
extends Resource
## 一种可种植作物的全部数值。
##
## 这是「种地系统」的唯一配置来源：加一种作物只需要往 data/crops/ 放一个 .tres，
## 农田窗口和存档都会自动认出来，不需要改界面脚本。
##
## 字段约定：
##   id              作物 id，小写英文，和产物物品 id 保持一致
##   seed_item_id    种子物品 id，必须能在 ItemDB 里查到
##   yield_item_id   产物物品 id，必须能在 ItemDB 里查到
##   grow_days       播种后经过几个「早晨结算」成熟，最小 1
##   yield_min/max   收获数量范围（含两端），实际取随机整数
##   buy_price       商店里 1 颗种子的价格（蛙币）
##   plant_texture   田里的植株贴图（横排 plant_frames 帧，幼苗 → 成熟）
##   plant_tint      给植株叠加的颜色，让同一份素材能区分不同作物

@export var id: String = ""
@export var display_name: String = "作物"
@export var seed_item_id: String = ""
@export var yield_item_id: String = ""
@export_range(1, 30, 1) var grow_days: int = 1
@export var yield_min: int = 1
@export var yield_max: int = 2
@export var buy_price: int = 10
@export var plant_texture: Texture2D
@export_range(1, 16, 1) var plant_frames: int = 4
@export var plant_tint: Color = Color.WHITE
