extends Node
## 建筑系统回归测试：建筑入口 / 农田种地 / 鸡舍养鸡 / 产出与存档。
##
## 运行方式（和工作区其它 smoke 测试一致，用隔离测试存档）：
##   godot --headless --path <工程> --quit-after 600 res://tests/buildings_smoke.tscn \
##       -- --test-save --test-save-in-workspace
##
## 这里的检查只认「玩家能看到的最终结果」：地块状态、仓库数量、界面打开/关闭、
## 存档读回。不检查内部私有变量，避免测试和实现绑死。

var failures: int = 0


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--test-save"):
		push_error("Run with -- --test-save --test-save-in-workspace to isolate save data")
		get_tree().quit(1)
		return
	await _run()
	print("BUILDINGS_SMOKE_RESULT failures=", failures)
	get_tree().quit(failures)


func _run() -> void:
	# ---------------- 数据层 ----------------
	check("FarmState autoload 已注册", FarmState != null)
	check("CoopState autoload 已注册", CoopState != null)
	check("GameClock autoload 已注册", GameClock != null)
	check("农田 18 块地", FarmState.PLOT_COUNT == 18 and FarmState.plots.size() == 18)
	var crop_ids := FarmState.crop_ids()
	check("作物配置 4 种", crop_ids.size() == 4)
	for expected_id in ["corn", "pumpkin", "wheat", "tomato"]:
		check("作物配置包含 " + expected_id, crop_ids.has(expected_id))
	for crop_id in crop_ids:
		var crop := FarmState.crop_by_id(String(crop_id))
		check("作物 %s 的种子/产物都已注册" % crop_id,
			crop != null and ItemDB.has_item(String(crop.seed_item_id)) and ItemDB.has_item(String(crop.yield_item_id)))

	# 旧存档物品 ID 迁移：生菜/萝卜 → 玉米/南瓜
	Inventory.from_dict({"lettuce": 2, "turnip": 3, "lettuce_seed": 1, "turnip_seed": 1})
	check("旧存档生菜迁移为玉米", Inventory.get_amount("corn") == 2)
	check("旧存档萝卜迁移为南瓜", Inventory.get_amount("pumpkin") == 3)
	check("旧种子迁移为玉米/南瓜种子",
		Inventory.get_amount("corn_seed") == 1 and Inventory.get_amount("pumpkin_seed") == 1)

	# ---------------- 场景与建筑入口 ----------------
	var farm = load("res://scenes/farm.tscn").instantiate()
	add_child(farm)
	await get_tree().process_frame
	await get_tree().process_frame

	var sidebar = farm.get_node("UiLayer/Sidebar")
	var building_button: Button = sidebar.get_node("Layout/IconColumn/BuildingButton")
	check("侧边栏建筑按钮可用", not building_button.disabled)
	check("侧边栏建筑按钮 tooltip 正确", building_button.tooltip_text == "建筑")
	check("侧边栏建筑按钮接的是建筑入口", building_button.pressed.is_connected(sidebar._open_buildings))

	building_button.pressed.emit()
	await get_tree().process_frame
	var hub = sidebar._building_hub
	check("建筑中心页打开", hub != null and hub.visible)

	hub.open_building("farm")
	await get_tree().process_frame
	var farm_window = hub._farm_window
	check("农田页打开", farm_window != null and farm_window.visible)
	check("农田页有 18 块地", farm_window.plot_count() == 18)

	# ---------------- 种地闭环 ----------------
	Inventory.from_dict({"pumpkin_seed": 5, "wheat_seed": 4, "wheat": 10})
	FarmState.reset()
	await get_tree().process_frame

	farm_window.click_plot(0)
	check("点空地可以锄地", FarmState.plot_state(0) == FarmState.State.TILLED)

	farm_window.select_seed("pumpkin")
	farm_window.click_plot(0)
	check("点已锄地可以播种", FarmState.plot_state(0) == FarmState.State.GROWING)
	check("播种扣掉 1 颗种子", Inventory.get_amount("pumpkin_seed") == 4)

	var clock = farm.get_node_or_null("DayNightCycle")
	check("农场里有昼夜时钟", clock != null)
	if clock == null:
		return
	clock.day += 1
	await get_tree().process_frame
	await get_tree().process_frame
	check("南瓜 1 天后成熟", FarmState.plot_state(0) == FarmState.State.RIPE)
	check("成熟地块显示可收标记", farm_window.visible_ripe_marker_count() >= 1)

	var pumpkin_before := Inventory.get_amount("pumpkin")
	farm_window.click_plot(0)
	var pumpkin_gained := Inventory.get_amount("pumpkin") - pumpkin_before
	check("收获南瓜进仓库 1~2 个", pumpkin_gained >= 1 and pumpkin_gained <= 2)
	check("收获后地块回到已锄地", FarmState.plot_state(0) == FarmState.State.TILLED)
	check("同一块地不会重复收获", FarmState.harvest(0).is_empty() and Inventory.get_amount("pumpkin") == pumpkin_before + pumpkin_gained)

	var coin_counter = get_tree().get_first_node_in_group("coin_counter")
	check("农场里有蛙币计数器", coin_counter != null)
	if coin_counter != null:
		coin_counter.set_gold(500, false)
		var seed_before := Inventory.get_amount("pumpkin_seed")
		var bought: bool = farm_window.buy_seed("pumpkin")
		check("窗口内可以花蛙币买种子",
			bought and Inventory.get_amount("pumpkin_seed") == seed_before + 1 and coin_counter.get_gold() == 490)

	FarmState.till(1)
	FarmState.plant(1, "wheat")
	check("小麦播种成功", FarmState.plot_state(1) == FarmState.State.GROWING)
	clock.day += 1
	await get_tree().process_frame
	await get_tree().process_frame
	check("小麦 1 天后仍在生长", FarmState.plot_state(1) == FarmState.State.GROWING)
	clock.day += 1
	await get_tree().process_frame
	await get_tree().process_frame
	check("小麦 2 天后成熟", FarmState.plot_state(1) == FarmState.State.RIPE)
	var wheat_before := Inventory.get_amount("wheat")
	var harvested: Dictionary = farm_window.harvest_all()
	check("一键收获产出小麦并入库", harvested.has("wheat") and Inventory.get_amount("wheat") > wheat_before)
	check("一键收获后没有可收地块", FarmState.ripe_count() == 0)

	# ---------------- 鸡舍 ----------------
	hub._on_window_back()
	await get_tree().process_frame
	check("农田页可以返回建筑中心", hub.visible and not farm_window.visible)

	hub.open_building("coop")
	await get_tree().process_frame
	var coop_window = hub._coop_window
	check("鸡舍页打开", coop_window != null and coop_window.visible)
	check("鸡舍有 3 只鸡", CoopState.chickens.size() == 3 and coop_window.chicken_visual_count() == 3)
	check("鸡舍打开时由界面驱动进食", CoopState.ui_active)

	# 鸡的漫游目标和食槽用餐点都必须夹在活动区内，否则会一直朝墙外走、被 clamp 在墙边
	var walk_bounds: Rect2 = coop_window._walk_bounds()
	var in_bounds := true
	var test_view = coop_window._chickens[0]
	for i in range(40):
		coop_window._pick_wander_target(test_view, walk_bounds)
		if not walk_bounds.grow(0.5).has_point(test_view.target):
			in_bounds = false
			break
	check("漫游目标点不会跑到墙外", in_bounds)
	check("食槽用餐点在活动区内", walk_bounds.grow(0.5).has_point(coop_window._trough_eat_point(0)))

	Inventory.from_dict({"wheat": 10})
	CoopState.reset()
	await get_tree().process_frame
	var filled: int = coop_window.press_trough()
	check("点食盆投喂消耗小麦", filled == 3 and CoopState.trough_stock == 3 and Inventory.get_amount("wheat") == 7)

	CoopState.chickens[0]["hunger"] = 80.0
	var fed := CoopState.feed_chicken(0)
	check("鸡吃一份饲料后饥饿下降",
		fed and CoopState.chickens[0]["hunger"] < 80.0 and CoopState.trough_stock == 2)

	# 下蛋必须由鸡走到地板：计时到点只代表“准备好”，不会凭空多蛋
	CoopState.chickens[1]["hunger"] = 0.0
	CoopState.chickens[1]["lay_timer"] = 0.0
	check("喂饱的鸡准备好下蛋", CoopState.lay_ready(1))
	check("没走到地板前不会凭空多蛋", CoopState.eggs_on_ground == 0)
	await _wait_frames(3)
	check("鸡舍界面会派鸡去地板", coop_window._laying_chicken == 1)
	var laying_view = coop_window._chickens[1]
	check("去地板的鸡进入 TO_NEST 状态", int(laying_view.mode) == 4)
	# 把鸡瞬移到地板前：模拟走到目的地，界面应切到“蹲下下蛋”
	laying_view.pos = coop_window._lay_spot_point(int(laying_view.lay_slot))
	await _wait_frames(3)
	check("到地板后进入下蛋动作", int(laying_view.mode) == 5)
	laying_view.timer = 0.01
	await _wait_frames(4)
	check("下蛋动作结束后蛋才出现", CoopState.eggs_on_ground == 1)
	await _wait_frames(2)
	check("地板里的蛋有可点击控件", coop_window.visible_egg_count() == 1)

	# 第二枚蛋用数据层接口补上，方便验证“点一枚只收一枚”
	CoopState.chickens[2]["hunger"] = 0.0
	CoopState.chickens[2]["lay_timer"] = 0.0
	check("第二只鸡也准备好", CoopState.lay_ready(2))
	check("lay_egg 会真的加一枚蛋", CoopState.lay_egg(2) == 1 and CoopState.eggs_on_ground == 2)
	await _wait_frames(2)
	check("两枚蛋都有可点击控件", coop_window.visible_egg_count() == 2)

	var egg_before := Inventory.get_amount("egg")
	var one: int = coop_window.press_collect_egg_at(0)
	check("点一枚蛋只收一枚", one == 1 and CoopState.eggs_on_ground == 1 \
		and Inventory.get_amount("egg") == egg_before + 1)
	var collected: int = coop_window.press_collect_all()
	check("收蛋进入仓库", collected == 1 and Inventory.get_amount("egg") == egg_before + 2)
	check("收完后地上没有蛋", CoopState.eggs_on_ground == 0 and coop_window.visible_egg_count() == 0)

	# 再产一枚蛋，用来验证存档恢复
	CoopState.chickens[2]["hunger"] = 0.0
	CoopState.chickens[2]["lay_timer"] = 0.0
	check("存档前再下一枚蛋", CoopState.lay_egg(2) == 1 and CoopState.eggs_on_ground == 1)

	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	coop_window._unhandled_input(cancel)
	await get_tree().process_frame
	check("关闭鸡舍后暂停产出", not CoopState.ui_active)
	var eggs_when_closed := CoopState.eggs_on_ground
	CoopState.chickens[0]["hunger"] = 0.0
	CoopState.chickens[0]["lay_timer"] = 0.0
	CoopState.tick(1.0)
	check("关窗期间不会凭空多蛋", CoopState.eggs_on_ground == eggs_when_closed)
	# 关窗后时间仍要走：饿了且食槽有料时，数据层自动进食（但没有走路动画）
	CoopState.trough_stock = 3
	CoopState.chickens[0]["hunger"] = 80.0
	CoopState.tick(1.0)
	check("关窗后饥饿仍在走且鸡会自己吃",
		CoopState.chickens[0]["hunger"] < 80.0 and CoopState.trough_stock == 2)
	check("鸡舍按 Esc 返回建筑中心", hub.visible and not coop_window.visible)

	# ---------------- 存档 ----------------
	Inventory.add("tomato_seed", 2)
	FarmState.till(2)
	FarmState.plant(2, "tomato")
	await get_tree().process_frame
	var plot_crop_before := FarmState.plot_crop_id(2)
	var coop_stock_before := CoopState.trough_stock
	var coop_eggs_before := CoopState.eggs_on_ground
	check("建筑状态可以写进存档", SaveManager.save_game())

	FarmState.reset()
	CoopState.reset()
	check("建筑状态可以从存档读回", SaveManager.load_save())
	check("农田地块存档恢复", FarmState.plot_crop_id(2) == plot_crop_before)
	check("鸡舍饲料存档恢复", CoopState.trough_stock == coop_stock_before)
	check("地上鸡蛋存档恢复", CoopState.eggs_on_ground == coop_eggs_before)

	# ---------------- 关闭建筑层 ----------------
	var cancel_hub := InputEventAction.new()
	cancel_hub.action = "ui_cancel"
	cancel_hub.pressed = true
	hub._unhandled_input(cancel_hub)
	await get_tree().process_frame
	check("建筑中心按 Esc 关闭整层", not sidebar._buildings_layer.visible)


## 等若干帧，给界面 _process / 信号刷新留出时间（无头下帧很快，不浪费真实时间）
func _wait_frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame