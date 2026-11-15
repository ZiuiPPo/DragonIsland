extends "res://scripts/ui/building_window_base.gd"
## 商店建筑页：买种子、买小鸡、买鸡饲料。
##
## 商店只做一件事：校验价格 → 扣蛙币（CoinCounter.spend_gold）→ 把东西放进仓库 / 鸡舍。
## 价格、库存、鸡舍数量都从真实数据层读取，不写死仓库数据。

const CHICKEN_PRICE: int = 200
const CHICKEN_PRICE_LABEL: String = "200 金币"
const FEED_PRICE: int = 40
const FEED_AMOUNT: int = 5

var _wallet_label: Label = null
var _chicken_panel_status: Label = null
var _chicken_card_status: Label = null
var _chicken_button: Button = null
var _feed_status: Label = null
var _feed_button: Button = null
var _card_stock_labels: Dictionary = {}
var _right_stock_labels: Dictionary = {}
var _chicken_portrait: TextureRect = null


func page_title() -> String:
	return "商店"


func page_hint() -> String:
	return "买种子、买小鸡、买饲料 · 扣蛙币 · Esc 返回建筑"


func _build_body(parent: VBoxContainer) -> void:
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 18)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(main)

	# ---------------- 左边：货架 ----------------
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	main.add_child(left)

	left.add_child(UI.title_label("种子", 22))
	left.add_child(UI.wrapped_label("买种子去农田播种；价格与成熟天数按当前作物配置。", 12))
	var seed_grid := GridContainer.new()
	seed_grid.columns = 2
	seed_grid.add_theme_constant_override("h_separation", 10)
	seed_grid.add_theme_constant_override("v_separation", 10)
	left.add_child(seed_grid)
	for crop in FarmState.crops():
		_build_seed_card(seed_grid, crop)

	left.add_child(UI.divider())
	left.add_child(UI.title_label("动物与饲料", 22))
	_build_animal_card(left)

	# ---------------- 右边：钱包与状态 ----------------
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 320
	right.add_theme_constant_override("separation", 8)
	main.add_child(right)

	right.add_child(UI.title_label("钱包", 22))
	var wallet_card := PanelContainer.new()
	wallet_card.add_theme_stylebox_override("panel", UI.card_style(true))
	right.add_child(wallet_card)
	var wallet_column := VBoxContainer.new()
	wallet_column.add_theme_constant_override("separation", 4)
	wallet_card.add_child(wallet_column)
	_wallet_label = UI.title_label("0 金币", 28)
	wallet_column.add_child(_wallet_label)
	wallet_column.add_child(UI.wrapped_label("付款后立即到账，仓库/鸡舍同步刷新。", 12))

	right.add_child(UI.divider())
	right.add_child(UI.label("鸡舍", 18, UI.INK))
	_chicken_panel_status = UI.wrapped_label("", 14)
	right.add_child(_chicken_panel_status)
	right.add_child(UI.wrapped_label("买鸡在左边「动物与饲料」卡片里操作。", 12))

	right.add_child(UI.label("种子库存", 18, UI.INK))
	_right_stock_labels = {}
	var stock_box := VBoxContainer.new()
	stock_box.add_theme_constant_override("separation", 3)
	right.add_child(stock_box)
	for crop in FarmState.crops():
		var stock_row := HBoxContainer.new()
		stock_row.add_theme_constant_override("separation", 6)
		stock_box.add_child(stock_row)
		stock_row.add_child(UI.label(String(crop.display_name) + "种子", 13, UI.INK_SOFT))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stock_row.add_child(spacer)
		var stock_label := UI.label("×0", 13, UI.INK)
		stock_row.add_child(stock_label)
		_right_stock_labels[String(crop.seed_item_id)] = stock_label

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	right.add_child(UI.wrapped_label(
		"鸡舍最多养 %d 只鸡；买来的小鸡会直接进鸡舍，饿了自己去吃食槽。" % CoopState.MAX_CHICKENS, 12))

	EventBus.inventory_reloaded.connect(_refresh)
	CoopState.changed.connect(_refresh)
	_refresh()


# ---------------- 货架组件 ----------------

func _build_seed_card(parent: GridContainer, crop: CropData) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UI.card_style())
	parent.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	row.add_child(UI.icon_slot(ItemDB.icon(String(crop.seed_item_id)), 44.0))

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 1)
	row.add_child(column)
	var name_label := UI.label("%s种子" % crop.display_name, 15, UI.INK)
	column.add_child(name_label)
	var price_label := UI.label("%d 金币 · 成熟 %d 天" % [int(crop.buy_price), int(crop.grow_days)], 12, UI.GOLD_DARK)
	column.add_child(price_label)
	stock_label_add(column, String(crop.seed_item_id))

	var buy_button := UI.primary_button("买 1", 13, 34)
	buy_button.custom_minimum_size.x = 68
	buy_button.pressed.connect(buy_seed.bind(String(crop.id)))
	row.add_child(buy_button)


func stock_label_add(parent: VBoxContainer, seed_item_id: String) -> void:
	var label := UI.label("库存 ×0", 12, UI.INK_SOFT)
	parent.add_child(label)
	_card_stock_labels[seed_item_id] = label


func _build_animal_card(parent: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UI.card_style())
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	# 小鸡
	var chicken_row := HBoxContainer.new()
	chicken_row.add_theme_constant_override("separation", 10)
	column.add_child(chicken_row)
	chicken_row.add_child(UI.icon_slot(_chicken_portrait_texture(), 52.0))
	var chicken_info := VBoxContainer.new()
	chicken_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chicken_info.add_theme_constant_override("separation", 2)
	chicken_row.add_child(chicken_info)
	chicken_info.add_child(UI.label("小鸡", 17, UI.INK))
	_chicken_card_status = UI.wrapped_label("", 13)
	chicken_info.add_child(_chicken_card_status)
	_chicken_button = UI.primary_button("买一只 · %s" % CHICKEN_PRICE_LABEL, 14, 38)
	_chicken_button.custom_minimum_size.x = 170
	_chicken_button.pressed.connect(buy_chicken)
	chicken_row.add_child(_chicken_button)

	column.add_child(UI.divider())

	# 饲料
	var feed_row := HBoxContainer.new()
	feed_row.add_theme_constant_override("separation", 10)
	column.add_child(feed_row)
	feed_row.add_child(UI.icon_slot(ItemDB.icon("wheat"), 52.0))
	var feed_info := VBoxContainer.new()
	feed_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed_info.add_theme_constant_override("separation", 2)
	feed_row.add_child(feed_info)
	feed_info.add_child(UI.label("鸡饲料", 17, UI.INK))
	_feed_status = UI.wrapped_label("", 13)
	feed_info.add_child(_feed_status)
	_feed_button = UI.primary_button("买 %d 份小麦 · %d 金币" % [FEED_AMOUNT, FEED_PRICE], 14, 38)
	_feed_button.custom_minimum_size.x = 200
	_feed_button.pressed.connect(buy_feed)
	feed_row.add_child(_feed_button)


func _chicken_portrait_texture() -> Texture2D:
	# 直接复用项目里的小鸡帧图，不额外造素材
	var atlas := AtlasTexture.new()
	atlas.atlas = preload("res://assets/sprites/chickens/chicken_all_left.png")
	atlas.region = Rect2(0, 0, 128, 128)
	return atlas


# ---------------- 购买接口 ----------------

func buy_seed(crop_id: String) -> bool:
	var crop := FarmState.crop_by_id(crop_id)
	if crop == null:
		return false
	var price := int(crop.buy_price)
	if not _spend(price):
		return false
	Inventory.add(String(crop.seed_item_id), 1)
	show_feedback("买了 1 颗「%s」种子（-%d 金币）。" % [crop.display_name, price], UI.GREEN_DARK)
	_refresh()
	return true


func buy_chicken() -> bool:
	if CoopState.chickens.size() >= CoopState.MAX_CHICKENS:
		show_feedback("鸡舍已经满了（最多 %d 只）。" % CoopState.MAX_CHICKENS)
		return false
	if not _spend(CHICKEN_PRICE):
		return false
	if not CoopState.add_chicken():
		return false
	show_feedback("买到一只小鸡，已经住进鸡舍（-%d 金币）。" % CHICKEN_PRICE, UI.GREEN_DARK)
	_refresh()
	return true


func buy_feed() -> bool:
	if not _spend(FEED_PRICE):
		return false
	Inventory.add("wheat", FEED_AMOUNT)
	show_feedback("买了 %d 份小麦饲料（-%d 金币）。" % [FEED_AMOUNT, FEED_PRICE], UI.GREEN_DARK)
	_refresh()
	return true


func _spend(price: int) -> bool:
	var counter := get_tree().get_first_node_in_group("coin_counter")
	if counter == null or not counter.has_method("spend_gold"):
		show_feedback("现在买不了：找不到蛙币计数器。")
		return false
	if not bool(counter.call("spend_gold", price)):
		show_feedback("蛙币不够（需要 %d 金币）。" % price)
		return false
	return true


# ---------------- 刷新 ----------------

func _refresh() -> void:
	var counter := get_tree().get_first_node_in_group("coin_counter")
	var gold := 0
	if counter != null and counter.has_method("get_gold"):
		gold = int(counter.call("get_gold"))
	if _wallet_label != null:
		_wallet_label.text = "%d 金币" % gold

	var bought := CoopState.chickens.size()
	if _chicken_panel_status != null:
		_chicken_panel_status.text = "已有 %d / %d 只鸡" % [bought, CoopState.MAX_CHICKENS]
	if _chicken_card_status != null:
		_chicken_card_status.text = "鸡舍 %d / %d 只" % [bought, CoopState.MAX_CHICKENS]
	if _chicken_button != null:
		_chicken_button.disabled = bought >= CoopState.MAX_CHICKENS
		_chicken_button.text = "鸡舍已满" if bought >= CoopState.MAX_CHICKENS else "买一只 · %s" % CHICKEN_PRICE_LABEL

	if _feed_status != null:
		_feed_status.text = "仓库小麦 %d 份" % Inventory.get_amount("wheat")
	for seed_item_id in _card_stock_labels:
		var card_label: Label = _card_stock_labels[seed_item_id]
		card_label.text = "库存 ×%d" % Inventory.get_amount(String(seed_item_id))
	for seed_item_id in _right_stock_labels:
		var right_label: Label = _right_stock_labels[seed_item_id]
		right_label.text = "×%d" % Inventory.get_amount(String(seed_item_id))


func _on_open() -> void:
	_refresh()


func _on_inventory_changed() -> void:
	_refresh()