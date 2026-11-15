extends Node
## 鸡舍数据层（Autoload）。
##
## 负责「养鸡系统」的全部数值模拟，不负责画界面：
##   · 3 只鸡的饥饿值随游戏时间上涨；
##   · 玩家往食盆投喂小麦 → 鸡进食 → 饥饿下降、进入产蛋计时；
##   · 鸡不太饿时产蛋计时会走完，但**不会凭空生成蛋**：
##     鸡舍界面会先让鸡走到巢箱、蹲下，再由界面调用 lay_egg()，蛋才出现；
##   · 食盆有上限，地上同时最多 6 枚蛋，避免无限堆积。
##
## 只有鸡舍界面打开（ui_active=true）时本节点才推进时间：
## 关掉页面后鸡、饥饿、产蛋计时全部暂停，避免不在场时「凭空多蛋」。
## 界面负责让鸡走到食盆/巢箱，数据层只做数值与存档。

signal changed
## 新蛋落地（参数：地上现有蛋数）
signal egg_laid(on_ground: int)
## 收蛋成功（参数：累计已收蛋数）
signal egg_collected(total_collected: int)
## 某只鸡吃了一份饲料（参数：鸡的序号）
signal chicken_ate(index: int)
## 某只鸡在巢箱下完了一枚蛋（参数：鸡的序号）
signal chicken_laid(index: int)

const CHICKEN_NAMES: Array[String] = ["小黄", "小白", "小花"]
const TROUGH_MAX: int = 9
const MAX_EGGS_ON_GROUND: int = 6
const HUNGER_MAX: float = 100.0
## 每秒饥饿增长
const HUNGER_RATE: float = 1.1
## 饿到这个值会自己去食盆
const HUNGRY_AT: float = 55.0
## 一份饲料能降多少饥饿
const FEED_RESTORE: float = 32.0
## 太饿（>= 此值）就不下蛋
const LAY_HUNGER_LIMIT: float = 75.0
const LAY_INTERVAL_MIN: float = 20.0
const LAY_INTERVAL_MAX: float = 34.0
const FEED_ITEM_ID: String = "wheat"
const EGG_ITEM_ID: String = "egg"

## 每只鸡：{ name: String, hunger: float, lay_timer: float }
var chickens: Array[Dictionary] = []
var trough_stock: int = 0
var eggs_on_ground: int = 0
var total_eggs: int = 0
var total_collected: int = 0
## 鸡舍窗口打开时为 true：只有这时才推进饥饿/产蛋计时，并由界面驱动鸡去食槽/巢箱。
var ui_active: bool = false

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	reset()


func _process(delta: float) -> void:
	# 只有农场场景在运行时才推进，主菜单里不偷跑
	if get_tree().get_first_node_in_group("day_night_cycle") == null:
		return
	tick(delta)


# ---------------- 时间推进 ----------------

func tick(delta: float) -> void:
	if delta <= 0.0 or chickens.is_empty():
		return
	# 鸡舍页面没开就暂停：蛋必须由玩家看着鸡走到巢箱才出现
	if not ui_active:
		return
	# 切场景 / 掉帧回来时不要一次跳太多
	delta = minf(delta, 0.5)
	for i in range(chickens.size()):
		var chicken: Dictionary = chickens[i]
		chicken["hunger"] = minf(HUNGER_MAX, float(chicken["hunger"]) + HUNGER_RATE * delta)
		if float(chicken["hunger"]) >= LAY_HUNGER_LIMIT:
			continue
		chicken["lay_timer"] = maxf(0.0, float(chicken["lay_timer"]) - delta)
		# 注意：这里只把计时器归零，不生成蛋；界面让鸡走到巢箱后会调 lay_egg()


# ---------------- 投喂 ----------------

## 往食盆里放小麦（从仓库扣，1 小麦 = 1 份饲料）。
## 返回真正倒进食盆的份数：食盆满了 / 仓库没小麦时返回 0。
func fill_trough(amount: int = 3) -> int:
	var room := TROUGH_MAX - trough_stock
	if room <= 0:
		return 0
	var want := mini(maxi(amount, 1), room)
	want = mini(want, Inventory.get_amount(FEED_ITEM_ID))
	if want <= 0:
		return 0
	if not Inventory.consume(FEED_ITEM_ID, want):
		return 0
	trough_stock += want
	changed.emit()
	return want


## 让第 index 只鸡吃一份饲料（界面在鸡走到食槽时调用）。
func feed_chicken(index: int) -> bool:
	return _eat_one(index)


func hungry(index: int) -> bool:
	if index < 0 or index >= chickens.size():
		return false
	return float(chickens[index]["hunger"]) >= HUNGRY_AT


func lay_blocked(index: int) -> bool:
	if index < 0 or index >= chickens.size():
		return true
	return float(chickens[index]["hunger"]) >= LAY_HUNGER_LIMIT


## 距离下一枚蛋的进度（0~1），给状态面板画进度条用。
func lay_progress(index: int) -> float:
	if index < 0 or index >= chickens.size():
		return 0.0
	if float(chickens[index]["hunger"]) >= LAY_HUNGER_LIMIT:
		return 0.0
	var timer := float(chickens[index]["lay_timer"])
	return clampf(1.0 - timer / maxf(LAY_INTERVAL_MAX, 1.0), 0.0, 1.0)


func chicken_name(index: int) -> String:
	if index < 0 or index >= chickens.size():
		return ""
	return String(chickens[index]["name"])


# ---------------- 下蛋（由鸡舍界面驱动） ----------------

## 这只鸡是否已经「憋到巢箱下蛋」：计时走完、不太饿、巢箱还有空位。
## 只有界面看到 true 后让鸡走过去，走到再调用 lay_egg() 才会真的多一枚蛋。
func lay_ready(index: int) -> bool:
	if index < 0 or index >= chickens.size():
		return false
	if eggs_on_ground >= MAX_EGGS_ON_GROUND:
		return false
	if float(chickens[index]["hunger"]) >= LAY_HUNGER_LIMIT:
		return false
	return float(chickens[index]["lay_timer"]) <= 0.0


## 在巢箱下蛋（界面在鸡走到巢箱、蹲下动画结束后调用）。
## 返回实际新增的蛋数：0 或 1。调用后重置这只鸡的下一轮产蛋计时。
func lay_egg(index: int) -> int:
	if not lay_ready(index):
		return 0
	eggs_on_ground += 1
	total_eggs += 1
	var chicken: Dictionary = chickens[index]
	chicken["lay_timer"] = _rng.randf_range(LAY_INTERVAL_MIN, LAY_INTERVAL_MAX)
	egg_laid.emit(eggs_on_ground)
	chicken_laid.emit(index)
	changed.emit()
	return 1


# ---------------- 收蛋 ----------------

## 收一枚地上的蛋：成功入味仓库，返回入库数量（一次 1 枚蛋）。
func collect_egg() -> int:
	if eggs_on_ground <= 0:
		return 0
	var produced := FarmOutput.produce(EGG_ITEM_ID, 1)
	if produced <= 0:
		return 0
	eggs_on_ground -= 1
	total_collected += produced
	egg_collected.emit(total_collected)
	changed.emit()
	return produced


func collect_all() -> int:
	var collected := 0
	while eggs_on_ground > 0:
		var got := collect_egg()
		if got <= 0:
			break
		collected += got
	return collected


# ---------------- 存档 ----------------

func to_dict() -> Dictionary:
	var rows: Array = []
	for chicken in chickens:
		rows.append({
			"name": String(chicken["name"]),
			"hunger": float(chicken["hunger"]),
			"lay_timer": float(chicken["lay_timer"]),
		})
	return {
		"chickens": rows,
		"trough_stock": trough_stock,
		"eggs_on_ground": eggs_on_ground,
		"total_eggs": total_eggs,
		"total_collected": total_collected,
	}


func from_dict(data: Dictionary) -> void:
	reset()
	var rows: Variant = data.get("chickens", [])
	if rows is Array:
		for i in range(mini((rows as Array).size(), chickens.size())):
			var row: Variant = (rows as Array)[i]
			if not (row is Dictionary):
				continue
			if not String(row.get("name", "")).is_empty():
				chickens[i]["name"] = String(row["name"])
			chickens[i]["hunger"] = clampf(float(row.get("hunger", 30.0)), 0.0, HUNGER_MAX)
			chickens[i]["lay_timer"] = clampf(float(row.get("lay_timer", 20.0)), 0.0, LAY_INTERVAL_MAX)
	trough_stock = clampi(int(data.get("trough_stock", 0)), 0, TROUGH_MAX)
	eggs_on_ground = clampi(int(data.get("eggs_on_ground", 0)), 0, MAX_EGGS_ON_GROUND)
	total_eggs = maxi(0, int(data.get("total_eggs", 0)))
	total_collected = maxi(0, int(data.get("total_collected", 0)))
	changed.emit()


func reset() -> void:
	chickens.clear()
	for i in range(CHICKEN_NAMES.size()):
		chickens.append({
			"name": CHICKEN_NAMES[i],
			"hunger": _rng.randf_range(18.0, 42.0),
			"lay_timer": _rng.randf_range(12.0, 24.0),
		})
	trough_stock = 0
	eggs_on_ground = 0
	total_eggs = 0
	total_collected = 0
	ui_active = false
	changed.emit()


# ---------------- 内部 ----------------

func _eat_one(index: int) -> bool:
	if index < 0 or index >= chickens.size():
		return false
	if trough_stock <= 0:
		return false
	trough_stock -= 1
	var chicken: Dictionary = chickens[index]
	chicken["hunger"] = maxf(0.0, float(chicken["hunger"]) - FEED_RESTORE)
	# 吃饱后不久就会开始下蛋
	chicken["lay_timer"] = _rng.randf_range(6.0, 12.0)
	chicken_ate.emit(index)
	changed.emit()
	return true