extends Node
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
	Inventory.from_dict({"wheat": 10, "tomato": 10, "pumpkin_seed": 4})
	# Migrate a mixed old layout, including wheat in the former food area.
	Inventory.warehouse_slots.resize(40)
	Inventory.warehouse_slots[0] = {"item_id": "tomato", "amount": 10}
	Inventory.warehouse_slots[25] = {"item_id": "wheat", "amount": 10}
	Inventory.warehouse_slots[26] = {"item_id": "pumpkin_seed", "amount": 4}
	var warehouse = load("res://scenes/ui/menus/menu_warehouse.tscn").instantiate()
	add_child(warehouse)
	await get_tree().process_frame
	var index := -1
	var wheat_index := -1
	var seed_index := -1
	for i in range(warehouse.display_slots().size()):
		var id: String = warehouse.display_slots()[i].get("item_id", "")
		if id == "tomato":
			index = i
		elif id == "wheat":
			wheat_index = i
		elif id == "pumpkin_seed":
			seed_index = i
	check("tomato migrates to food page", index >= warehouse.MATERIAL_SLOT_COUNT)
	check("wheat migrates to material page", wheat_index >= 0 and wheat_index < warehouse.MATERIAL_SLOT_COUNT)
	check("seed migrates to material page", seed_index >= 0 and seed_index < warehouse.MATERIAL_SLOT_COUNT)
	check("migration preserves inventory", Inventory.get_amount("wheat") == 10 and Inventory.get_amount("tomato") == 10 and Inventory.get_amount("pumpkin_seed") == 4)
	check("materials selected by default", warehouse.get_node("MaterialGrid").visible and not warehouse.get_node("FoodGrid").visible)
	warehouse.get_node("CategoryButtons/FoodButton").pressed.emit()
	check("food button switches page", warehouse.get_node("FoodGrid").visible and not warehouse.get_node("MaterialGrid").visible)
	check("food button selected", warehouse.get_node("CategoryButtons/FoodButton").button_pressed and not warehouse.get_node("CategoryButtons/MaterialButton").button_pressed)
	warehouse.get_node("CategoryButtons/MaterialButton").pressed.emit()
	check("materials button switches back", warehouse.get_node("MaterialGrid").visible and not warehouse.get_node("FoodGrid").visible)
	check("food rejected by material slot", not warehouse.can_transfer(warehouse.drag_payload(index, true, false), 10))
	check("raw wheat rejected by food slot", not warehouse.can_transfer(warehouse.drag_payload(wheat_index, true, false), 31))
	warehouse.show_food()
	var payload = warehouse.drag_payload(index, false, true)
	check("half stack", payload.amount == 5)
	warehouse.transfer(payload, 30)
	check("split stack", warehouse.display_slots()[30].amount == 5 and warehouse.display_slots()[index].amount == 5)
	warehouse.transfer(warehouse.drag_payload(30, false, false), index)
	check("merge conserves total", warehouse.display_slots()[index].amount == 10 and Inventory.get_amount("tomato") == 10)
	check("different items rejected", not warehouse.can_transfer(warehouse.drag_payload(index, false, false), 0))
	var member = StaffRegistry.add_member("拖拽测试", null, "", "npc1")
	var npc = load("res://scenes/npc/staff_npc.tscn").instantiate()
	npc.configure(member, Vector2.ZERO)
	# master 2.0 起新员工默认饱腹/体力为 0，这里先喂饱再测大笑收入
	member.satiety = 100.0
	npc.random_spawn = false
	add_child(npc)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var view = npc._care_view
	check("idle starts wandering, not laughing", not member.is_laughing)
	var energy: float = member.satiety
	# Fake active-farm marker lets us test the clock without creating or saving a session.
	var marker := Node.new()
	add_child(marker)
	marker.add_to_group("day_night_cycle")
	StaffCare._process(1.0)
	check("walking does not drain laughter energy", member.satiety == energy)
	view._laugh_cooldown = 0.0
	npc.velocity = Vector2.ZERO
	view.blocks_movement(0.1, false)
	check("stationary cannot trigger laugh", not member.is_laughing)
	npc.velocity = Vector2(40, 0)
	view.blocks_movement(0.1, false)
	check("wandering triggers laugh", member.is_laughing and String(npc.animated_sprite_2d.animation).begins_with("laugh"))
	check("laugh duration in random range", view._laugh_left >= view.LAUGH_DURATION_MIN and view._laugh_left <= view.LAUGH_DURATION_MAX)
	check("laughter audio starts", view._audio.playing and view._audio.stream == view.LAUGH_AUDIO and view.LAUGH_AUDIO.get_length() > 0.0)
	view.blocks_movement(0.25, false)
	check("actual laughter consumes energy", member.satiety < energy)
	view._laugh_left = 0.01
	view.blocks_movement(0.02, false)
	check("laugh ends and stops audio", not member.is_laughing and not view._audio.playing)
	check("random cooldown resets", view._laugh_cooldown >= view.LAUGH_INTERVAL_MIN and view._laugh_cooldown <= view.LAUGH_INTERVAL_MAX)
	npc._wait_left = 0.0
	for step in range(4):
		await get_tree().physics_frame
	check("walking resumes after laughter", npc.velocity.length() > 0.0 and not String(npc.animated_sprite_2d.animation).begins_with("laugh"))
	npc.velocity = Vector2(40, 0)
	view._laugh_cooldown = 0.0
	view.blocks_movement(0.1, false)
	StaffRegistry.set_working(member.id, true)
	energy = member.satiety
	StaffCare._process(1.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("working stops laughter and audio", member.satiety == energy and not member.is_laughing and not view._audio.playing and not String(npc.animated_sprite_2d.animation).begins_with("laugh"))
	member.satiety = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("zero energy overrides work", npc.velocity == Vector2.ZERO and String(npc.animated_sprite_2d.animation).begins_with("sad"))
	StaffRegistry.set_working(member.id, false)
	check("seed cannot feed", not view._can_drop_data(Vector2.ZERO, warehouse.drag_payload(seed_index, true, false)))
	check("raw wheat cannot drag feed", not view._can_drop_data(Vector2.ZERO, warehouse.drag_payload(wheat_index, true, false)))
	check("raw wheat cannot button feed", not StaffCare.feed(member.id, "wheat") and Inventory.get_amount("wheat") == 10)
	Inventory.add("egg", 1)
	check("raw egg cannot feed", not StaffCare.feed(member.id, "egg"))
	check("auto feeding selects edible food", StaffCare.best_food() == "tomato" and not StaffCare.available_foods().has("wheat") and not StaffCare.available_foods().has("egg"))
	check("inventory refresh preserves selected page", warehouse.get_node("FoodGrid").visible and not warehouse.get_node("MaterialGrid").visible)
	warehouse.transfer(warehouse.drag_payload(index, true, false), 30)
	check("split one", warehouse.display_slots()[30].amount == 1)
	view._drop_data(Vector2.ZERO, warehouse.drag_payload(30, true, false))
	check("feeding debits dragged stack", warehouse.display_slots()[30].is_empty() and Inventory.get_amount("tomato") == 9 and member.satiety > 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("fed idle resumes wandering", not member.is_laughing and not String(npc.animated_sprite_2d.animation).begins_with("sad"))
	view._laugh_cooldown = 0.0
	npc.velocity = Vector2(40, 0)
	view.blocks_movement(0.1, false)
	member.satiety = 100.0
	check("full rejects extra food", not view._can_drop_data(Vector2.ZERO, warehouse.drag_payload(index, true, false)))
	var frames := {}
	for i in range(12):
		view.blocks_movement(0.1, false)
		frames[npc.animated_sprite_2d.frame] = true
	check("laugh uses random frames", frames.size() > 1)
	member.satiety = 0.01
	view.blocks_movement(0.1, false)
	check("energy exhaustion interrupts audio", member.satiety == 0.0 and not view._audio.playing and String(npc.animated_sprite_2d.animation).begins_with("sad"))
	var wallet = load("res://scenes/ui/coin_counter.tscn").instantiate()
	add_child(wallet)
	var earner := StaffMember.new(1001, "收入测试")
	earner.satiety = 100.0
	earner.is_laughing = true
	StaffCare.settle_laughter(earner, 1.0)
	check("one laughing staff earns 50 per second", wallet.get_gold() == 50)
	var second_earner := StaffMember.new(1002, "收入测试2")
	second_earner.satiety = 100.0
	second_earner.is_laughing = true
	StaffCare.settle_laughter(second_earner, 1.0)
	check("two laughing staff incomes add up", wallet.get_gold() == 100)
	StaffCare.settle_laughter(earner, 0.25)
	StaffCare.finish_laughter(earner)
	check("partial laughter pays without losing fraction", wallet.get_gold() == 112 and is_equal_approx(earner.laugh_gold_pending, 0.5))
	StaffCare.settle_laughter(earner, 0.25)
	StaffCare.finish_laughter(earner)
	check("fraction carries across laughter sessions", wallet.get_gold() == 125 and is_zero_approx(earner.laugh_gold_pending))
	earner.satiety = 0.2
	StaffCare.settle_laughter(earner, 1.0)
	StaffCare.finish_laughter(earner)
	check("income clamps to remaining satiety time", wallet.get_gold() == 130 and is_zero_approx(earner.satiety))
	StaffCare.settle_laughter(earner, 1.0)
	StaffCare.finish_laughter(earner)
	check("exhausted staff earns nothing", wallet.get_gold() == 130)
	earner.satiety = 60.0
	earner.is_working = true
	StaffCare.settle_laughter(earner, 1.0)
	check("working staff earns no laughter income", wallet.get_gold() == 130)
	earner.is_working = false
	earner.is_laughing = false
	StaffCare.settle_laughter(earner, 1.0)
	check("wandering staff earns nothing", wallet.get_gold() == 130)
	var status_menu = load("res://scenes/ui/menus/menu_npc_status.tscn").instantiate()
	add_child(status_menu)
	check("obsolete work instruction removed", status_menu.get_node_or_null("Hint") == null)
	check("员工列表填满抽屉高度", int(status_menu.get_node("%Scroll").size_flags_vertical) == Control.SIZE_EXPAND_FILL)
	check("员工页不再用底部 Spacer 占位", status_menu.get_node_or_null("Spacer") == null)
	marker.remove_from_group("day_night_cycle")
	energy = member.satiety
	StaffCare._process(2.0)
	check("menu time does not drain", member.satiety == energy)
	earner.is_laughing = true
	StaffCare.settle_laughter(earner, 1.0)
	check("outside farm earns nothing", wallet.get_gold() == 130)
	var legacy := {"version": 1, "gold": 500, "staff": [{"id": 99, "display_name": "旧员工", "look": "npc1"}]}
	StaffRegistry.from_dict(legacy.staff)
	SaveManager._restore_inventory(legacy)
	check("legacy save defaults", StaffRegistry.members[0].satiety == 60.0 and not StaffRegistry.members[0].is_working and Inventory.get_amount("wheat") == 12)
	StaffRegistry.members[0].laugh_gold_pending = 0.5
	SaveManager.begin_session()
	var slots_before := Inventory.warehouse_slots.duplicate(true)
	check("save succeeds", SaveManager.save_game())
	Inventory.clear()
	check("load succeeds", SaveManager.load_save())
	check("stack layout survives load", Inventory.warehouse_slots == slots_before)
	check("energy survives load", StaffRegistry.members[0].satiety == 60.0)
	check("fractional income survives save load", is_equal_approx(StaffRegistry.members[0].laugh_gold_pending, 0.5))
	print("DRAG_CARE_RESULT failures=", failures)
	get_tree().quit(failures)