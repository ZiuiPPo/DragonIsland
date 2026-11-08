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
	Inventory.from_dict({"wheat": 10, "turnip_seed": 4})
	var warehouse = load("res://scenes/ui/menus/menu_warehouse.tscn").instantiate()
	add_child(warehouse)
	await get_tree().process_frame
	var index := -1
	for i in range(warehouse.display_slots().size()):
		if warehouse.display_slots()[i].get("item_id") == "wheat":
			index = i
	check("wheat visible", index >= 0)
	var payload = warehouse.drag_payload(index, false, true)
	check("half stack", payload.amount == 5)
	warehouse.transfer(payload, 10)
	check("split stack", warehouse.display_slots()[10].amount == 5 and warehouse.display_slots()[index].amount == 5)
	warehouse.transfer(warehouse.drag_payload(10, false, false), index)
	check("merge conserves total", warehouse.display_slots()[index].amount == 10 and Inventory.get_amount("wheat") == 10)
	check("different items rejected", not warehouse.can_transfer(warehouse.drag_payload(index, false, false), 0))
	var member = StaffRegistry.add_member("拖拽测试", null, "", "npc1")
	var npc = load("res://scenes/npc/staff_npc.tscn").instantiate()
	npc.configure(member, Vector2.ZERO)
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
	check("seed cannot feed", not view._can_drop_data(Vector2.ZERO, warehouse.drag_payload(0, true, false)))
	warehouse.transfer(warehouse.drag_payload(index, true, false), 10)
	check("split one", warehouse.display_slots()[10].amount == 1)
	view._drop_data(Vector2.ZERO, warehouse.drag_payload(10, true, false))
	check("feeding debits dragged stack", warehouse.display_slots()[10].is_empty() and Inventory.get_amount("wheat") == 9 and member.satiety > 0.0)
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
	marker.remove_from_group("day_night_cycle")
	energy = member.satiety
	StaffCare._process(2.0)
	check("menu time does not drain", member.satiety == energy)
	var legacy := {"version": 1, "gold": 500, "staff": [{"id": 99, "display_name": "旧员工", "look": "npc1"}]}
	StaffRegistry.from_dict(legacy.staff)
	SaveManager._restore_inventory(legacy)
	check("legacy save defaults", StaffRegistry.members[0].satiety == 60.0 and not StaffRegistry.members[0].is_working and Inventory.get_amount("wheat") == 12)
	SaveManager.begin_session()
	var slots_before := Inventory.warehouse_slots.duplicate(true)
	check("save succeeds", SaveManager.save_game())
	Inventory.clear()
	check("load succeeds", SaveManager.load_save())
	check("stack layout survives load", Inventory.warehouse_slots == slots_before)
	check("energy survives load", StaffRegistry.members[0].satiety == 60.0)
	print("DRAG_CARE_RESULT failures=", failures)
	get_tree().quit(failures)
