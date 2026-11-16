extends Node
## 商店冒烟测试：买种子/饲料/小鸡、商店入口、主场景无散养鸡、鸡舍动态 6 只、存档恢复。

var failures := 0


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1


func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--test-save"):
		push_error("Run with -- --test-save to isolate save data")
		get_tree().quit(1)
		return

	CoopState.reset()
	Inventory.from_dict({})
	var farm: Node = load("res://scenes/farm.tscn").instantiate()
	add_child(farm)
	await get_tree().process_frame
	await get_tree().process_frame

	# ---------------- 主场景不再有散养鸡 ----------------
	check("主场景没有 Chicken 节点", farm.get_node_or_null("Level/Chicken") == null)
	check("场景里没有 chicken 组节点", get_tree().get_nodes_in_group("chicken").is_empty())

	var sidebar = farm.get_node("UiLayer/Sidebar")
	var shop_button: Button = sidebar.get_node("Layout/IconColumn/ShopButton")
	check("侧栏商店按钮已启用", not shop_button.disabled)
	check("侧栏商店按钮提示", shop_button.tooltip_text == "商店")

	var counter := get_tree().get_first_node_in_group("coin_counter")
	check("有蛙币计数器", counter != null)
	counter.call("set_gold", 1000, false)

	# ---------------- 打开商店 ----------------
	shop_button.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	check("侧栏商店不经过建筑层", sidebar._buildings_layer == null or not sidebar._buildings_layer.visible)
	var shop = sidebar._shop_window
	check("侧栏商店打开独立商店页", shop != null and shop.visible)

	# ---------------- 买种子 ----------------
	var corn_before := Inventory.get_amount("corn_seed")
	check("买玉米种子成功", shop.buy_seed("corn"))
	check("玉米种子入库", Inventory.get_amount("corn_seed") == corn_before + 1)
	check("买种子扣蛙币", counter.get_gold() == 985)
	check("买南瓜种子成功", shop.buy_seed("pumpkin") and Inventory.get_amount("pumpkin_seed") == 1)
	check("第二次扣蛙币", counter.get_gold() == 975)

	# ---------------- 买饲料 ----------------
	var wheat_before := Inventory.get_amount("wheat")
	check("买饲料成功", shop.buy_feed())
	check("饲料小麦入库 5 份", Inventory.get_amount("wheat") == wheat_before + 5)
	check("饲料扣蛙币", counter.get_gold() == 935)

	# ---------------- 买鸡 ----------------
	check("初始鸡舍 3 只", CoopState.chickens.size() == 3)
	check("买一只鸡成功", shop.buy_chicken())
	check("鸡舍变为 4 只", CoopState.chickens.size() == 4)
	check("买鸡扣蛙币", counter.get_gold() == 735)
	check("买鸡会自动起名", String(CoopState.chickens[3]["name"]) != "")

	while CoopState.chickens.size() < CoopState.MAX_CHICKENS:
		check("继续买鸡到满", shop.buy_chicken())
	check("鸡舍最多 6 只", CoopState.chickens.size() == CoopState.MAX_CHICKENS)
	var gold_at_full: int = int(counter.call("get_gold"))
	check("满员后不能再买", not shop.buy_chicken())
	check("满员失败不扣钱", counter.get_gold() == gold_at_full)
	check("满员按钮禁用", shop._chicken_button.disabled)

	# ---------------- 鸡舍显示 6 只 ----------------
	shop.close()
	sidebar._on_shop_closed()
	sidebar._open_buildings()
	await get_tree().process_frame
	await get_tree().process_frame
	var hub = sidebar._building_hub
	check("建筑中心不再有商店卡片", hub != null and hub.get("_shop_status") == null)
	check("建筑中心仍可打开鸡舍", hub != null)
	hub.open_building("coop")
	await get_tree().process_frame
	await get_tree().process_frame
	var coop = hub._coop_window
	check("鸡舍页打开", coop != null and coop.visible)
	check("鸡舍数据层 6 只", CoopState.chickens.size() == CoopState.MAX_CHICKENS)
	check("鸡舍画面有 6 只", coop.chicken_visual_count() == CoopState.MAX_CHICKENS)
	check("鸡舍 6 个鸡卡片", coop._chicken_card_panels.size() == CoopState.MAX_CHICKENS)
	var visible_cards := 0
	for card in coop._chicken_card_panels:
		if card.visible:
			visible_cards += 1
	check("6 个鸡卡片全部显示", visible_cards == CoopState.MAX_CHICKENS)
	var visible_sprites := 0
	for view in coop._chickens:
		if view.sprite.visible:
			visible_sprites += 1
	check("6 只鸡画面全部显示", visible_sprites == CoopState.MAX_CHICKENS)

	# ---------------- 存档恢复 6 只 ----------------
	check("保存 6 只鸡", SaveManager.save_game())
	CoopState.reset()
	check("重置后回到 3 只", CoopState.chickens.size() == 3)
	check("读档恢复 6 只鸡", SaveManager.load_save() and CoopState.chickens.size() == CoopState.MAX_CHICKENS)
	var names: Array[String] = []
	for chicken in CoopState.chickens:
		names.append(String(chicken["name"]))
	check("读档后名字不重复", names.size() == 6 and names[0] != names[5])

	print("SHOP_SMOKE_RESULT failures=", failures)
	get_tree().quit(failures)