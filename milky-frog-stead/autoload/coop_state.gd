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
## 时间一直推进（只要农场场景在跑）：关掉鸡舍页面后饥饿/产蛋计时继续走。
## 但蛋仍然只能由界面驱动鸡走到落蛋点后调用 lay_egg() 才出现，不会凭空多蛋；
## 关窗期间鸡会自动从食槽进食（不播走路动画），避免玩家看别的页面时饿死。

signal changed
## 新蛋落地（参数：地上现有蛋数）
signal egg_laid(on_ground: int)
## 收蛋成功（参数：累计已收蛋数）
signal egg_collected(total_collected: int)
## 某只鸡吃了一份饲料（参数：鸡的序号）
signal chicken_ate(index: int)
## 某只鸡在巢箱下完了一枚蛋（参数：鸡的序号）
signal chicken_laid(index: int)

const CHICKEN_NAMES: Array[String] = ["小黄", "小白", "小花", "小橙", "小灰", "小黑"]
const STARTING_CHICKENS: int = 3
## 鸡舍最多养几只（商店买鸡的上限）
const MAX_CHICKENS: int = 6
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
## 鸡舍窗口打开时为 true：此时由界面驱动鸡走到食槽/巢箱；关窗时数据层自动进食。
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
	# 切场景 / 掉帧回来时不要一次跳太多
	delta = minf(delta, 0.5)
	var did_eat := false
	for i in range(chickens.size()):
		var chicken: Dictionary = chickens[i]
		chicken["hunger"] = minf(HUNGER_MAX, float(chicken["hunger"]) + HUNGER_RATE * delta)
		# 鸡舍关着时无人驱动走路：饿了直接从食槽吃一份，避免挂机回来全饿死。
		# 打开页面后仍然必须由界面让鸡走到食槽才吃，保留「看着它吃」的表现。
		if not ui_active and trough_stock > 0 and float(chicken["hunger"]) >= HUNGRY_AT:
			trough_stock -= 1
			chicken["hunger"] = maxf(0.0, float(chicken["hunger"]) - FEED_RESTORE)
			chicken["lay_timer"] = _rng.randf_range(6.0, 12.0)
			chicken_ate.emit(i)
			did_eat = true
		if float(chicken["hunger"]) >= LAY_HUNGER_LIMIT:
			continue
		chicken["lay_timer"] = maxf(0.0, float(chicken["lay_timer"]) - delta)
		# 注意：这里只把计时器归零，不生成蛋；界面让鸡走到巢箱后会调 lay_egg()
	if did_eat:
		changed.emit()


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
	_reset_counters_only()
	var rows: Variant = data.get("chickens", [])
	var target_count := STARTING_CHICKENS
	if rows is Array and not (rows as Array).is_empty():
		target_count = clampi((rows as Array).size(), 1, MAX_CHICKENS)
	for i in range(target_count):
		var chicken := _new_chicken_data(CHICKEN_NAMES[i] if i < CHICKEN_NAMES.size() else "小鸡%d" % (i + 1))
		if rows is Array and i < (rows as Array).size() and (rows as Array)[i] is Dictionary:
			var row: Dictionary = (rows as Array)[i]
			if not String(row.get("name", "")).is_empty():
				chicken["name"] = String(row["name"])
			chicken["hunger"] = clampf(float(row.get("hunger", 30.0)), 0.0, HUNGER_MAX)
			chicken["lay_timer"] = clampf(float(row.get("lay_timer", 20.0)), 0.0, LAY_INTERVAL_MAX)
		chickens.append(chicken)
	trough_stock = clampi(int(data.get("trough_stock", 0)), 0, TROUGH_MAX)
	eggs_on_ground = clampi(int(data.get("eggs_on_ground", 0)), 0, MAX_EGGS_ON_GROUND)
	total_eggs = maxi(0, int(data.get("total_eggs", 0)))
	total_collected = maxi(0, int(data.get("total_collected", 0)))
	changed.emit()


func reset() -> void:
	chickens.clear()
	for i in range(mini(STARTING_CHICKENS, CHICKEN_NAMES.size())):
		chickens.append(_new_chicken_data(CHICKEN_NAMES[i]))
	trough_stock = 0
	eggs_on_ground = 0
	total_eggs = 0
	total_collected = 0
	ui_active = false
	changed.emit()


## 商店买鸡时调用：往鸡舍里加一只，满员返回 false。
func add_chicken(display_name: String = "") -> bool:
	if chickens.size() >= MAX_CHICKENS:
		return false
	var used_names: Array[String] = []
	for chicken in chickens:
		used_names.append(String(chicken["name"]))
	var name := display_name.strip_edges()
	if name.is_empty():
		for candidate in CHICKEN_NAMES:
			if not used_names.has(candidate):
				name = candidate
				break
	if name.is_empty():
		name = "小鸡%d" % (chickens.size() + 1)
	chickens.append(_new_chicken_data(name))
	changed.emit()
	return true


func _new_chicken_data(chicken_name: String) -> Dictionary:
	return {
		"name": chicken_name,
		"hunger": _rng.randf_range(18.0, 42.0),
		"lay_timer": _rng.randf_range(12.0, 24.0),
	}


func _reset_counters_only() -> void:
	# from_dict 内部用：先清空鸡只与计数，但不发信号，最后统一 emit
	chickens.clear()
	trough_stock = 0
	eggs_on_ground = 0
	total_eggs = 0
	total_collected = 0
	ui_active = false
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