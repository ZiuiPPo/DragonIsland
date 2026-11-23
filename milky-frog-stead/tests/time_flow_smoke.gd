extends Node
## 时间统一冒烟测试：时间菜单跳时段/跨天，以及直接补算游戏小时，
## 都必须让鸡舍的饥饿/产蛋计时按游戏时间推进；但蛋仍然要打开鸡舍让鸡自己走才生成。

var failures := 0


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--test-save"):
		get_tree().quit(1)
		return
	var farm: Node = load("res://scenes/farm.tscn").instantiate()
	add_child(farm)
	await get_tree().process_frame
	await get_tree().process_frame
	var clock = farm.get_node_or_null("DayNightCycle")
	check("农场里有昼夜时钟", clock != null)
	if clock != null:
		clock.auto_advance = false
	CoopState.reset()
	CoopState.trough_stock = 0
	Inventory.from_dict({"wheat": 0})
	for chicken in CoopState.chickens:
		chicken["hunger"] = 30.0
		chicken["lay_timer"] = 8.0
	# 先让 CoopState 静默对齐一次时钟，再模拟时间菜单跳时段
	await get_tree().process_frame
	var eggs_before := CoopState.eggs_on_ground
	var hunger_before: float = float(CoopState.chickens[0]["hunger"])

	# 时间菜单连点几次：应该按跳过的游戏小时结算鸡舍，而不是完全不动
	if clock != null:
		clock.advance_phase()
		clock.advance_phase()
		clock.advance_phase()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	check("跳时段后鸡舍时间也走了", float(CoopState.chickens[0]["hunger"]) > hunger_before)
	check("跳时段不会凭空多蛋", CoopState.eggs_on_ground == eggs_before)
	check("跳过 8 小时后三只鸡都准备好下蛋",
		CoopState.lay_ready(0) and CoopState.lay_ready(1) and CoopState.lay_ready(2))

	# 直接补算 2 天：鸡蛋仍然不自动生成，只准备好。
	# 给食槽补料，否则 2 天后会饿到 75+ 而无法产蛋（这是游戏规则）。
	CoopState.trough_stock = 9
	Inventory.from_dict({"wheat": 10})
	for chicken in CoopState.chickens:
		chicken["hunger"] = 30.0
		chicken["lay_timer"] = 8.0
	CoopState.advance_game_hours(48.0)
	check("补算 2 天后仍然没有凭空生蛋", CoopState.eggs_on_ground == eggs_before)
	check("补算 2 天后三只鸡都准备好",
		CoopState.lay_ready(0) and CoopState.lay_ready(1) and CoopState.lay_ready(2))

	# 打开鸡舍后，界面应派鸡去落蛋点，蛋才会出现
	var sidebar = farm.get_node("UiLayer/Sidebar")
	sidebar._open_buildings()
	await get_tree().process_frame
	var hub = sidebar._building_hub
	hub.open_building("coop")
	await get_tree().process_frame
	await get_tree().process_frame
	var coop = hub._coop_window
	check("鸡舍页打开", coop != null and coop.visible)
	CoopState.chickens[0]["hunger"] = 0.0
	CoopState.chickens[0]["lay_timer"] = 0.0
	coop._laying_chicken = -1
	for view in coop._chickens:
		view.mode = 3
		view.timer = 0.2
	check("打开鸡舍后鸡才去下蛋", coop._laying_chicken >= 0 or CoopState.lay_ready(0))
	await get_tree().process_frame
	check("下蛋流程由鸡舍界面接管", coop._laying_chicken >= 0)
	check("还没走到地板前不会凭空多蛋", CoopState.eggs_on_ground == eggs_before)

	print("TIME_FLOW_SMOKE_RESULT failures=", failures)
	get_tree().quit(failures)