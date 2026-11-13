extends Node
const Book := preload("res://scripts/core/recipe_book.gd")
var failures := 0
func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failures += 1
func _find(warehouse: Control, item_id: String) -> int:
	for i in range(warehouse.display_slots().size()):
		if warehouse.display_slots()[i].get("item_id") == item_id:
			return i
	return -1
func stock() -> Dictionary:
	return {"wheat": 40, "egg": 30, "tomato": 30, "lettuce": 20, "turnip": 20, "wheat_seed": 4}
func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--test-save"):
		get_tree().quit(1)
		return
	Inventory.from_dict({"fish": 3, "milk_fruit": 4, "fish_bun": 2, "fruit_salad": 2, "milk_pudding": 3})
	check("removed ingredients cleaned from old saves", not Inventory.to_dict().has("fish") and not Inventory.to_dict().has("milk_fruit") and not Inventory.to_dict().has("fish_bun"))
	check("renamed dishes preserved", Inventory.get_amount("veggie_salad") == 2 and Inventory.get_amount("egg_pudding") == 3)
	var recipes := Book.all()
	check("five recipes", recipes.size() == 5)
	for recipe in recipes:
		check("dish icon and edible " + recipe.id, ItemDB.icon(recipe.output_id) != null and ItemDB.is_edible(recipe.output_id))
	Inventory.from_dict(stock())
	var farm = load("res://scenes/farm.tscn").instantiate()
	add_child(farm)
	await get_tree().process_frame
	var sidebar = farm.get_node("UiLayer/Sidebar")
	var recipes_button = sidebar.get_node("Layout/IconColumn/RecipesButton")
	check("recipe button enabled", not recipes_button.disabled)
	var building_button = sidebar.get_node("Layout/IconColumn/BuildingButton")
	check("original building placeholder restored", building_button.disabled and building_button.tooltip_text == "建筑（尚未开放）")
	check("building does not open workbench", not building_button.pressed.is_connected(sidebar._open_workbench))
	check("recipe button matches active sidebar style", recipes_button.get_theme_stylebox("normal") == sidebar.get_node("Layout/IconColumn/RecruitButton").get_theme_stylebox("normal"))
	recipes_button.pressed.emit()
	await get_tree().process_frame
	var window = sidebar._workbench
	check("recipe button opens full cooking page", window != null and window.visible and window.warehouse != null)
	var before := Inventory.to_dict()
	var warehouse = window.warehouse
	var seed = warehouse.drag_payload(_find(warehouse, "wheat_seed"), false, false)
	check("seed is not a recipe ingredient", not window.can_stage(seed))
	var wheat = warehouse.drag_payload(_find(warehouse, "wheat"), false, false)
	var egg = warehouse.drag_payload(_find(warehouse, "egg"), false, false)
	check("required ingredient slot accepts drag", window.input_slots[0]._can_drop_data(Vector2.ZERO, wheat))
	check("wrong slot rejects drag", not window.input_slots[0]._can_drop_data(Vector2.ZERO, egg))
	window.input_slots[0]._drop_data(Vector2.ZERO, wheat)
	check("whole stack caps at required quantity", window.staged.get("wheat") == 2)
	check("staging does not consume stock", Inventory.to_dict() == before)
	window.stage(egg)
	check("recipe ready after dragging ingredients", window.ready_to_craft())
	window.unstage("wheat")
	check("right click withdrawal", window.staged.wheat == 1 and not window.ready_to_craft())
	window.close()
	check("closing never loses staged items", Inventory.to_dict() == before and window.staged.is_empty())
	recipes_button.pressed.emit()
	check("recipe button reuses same window", sidebar._workbench == window and window.visible)
	window.auto_fill()
	window.craft_selected()
	check("craft consumes correct quantities", Inventory.get_amount("wheat") == 38 and Inventory.get_amount("egg") == 29)
	check("craft deposits edible output", Inventory.get_amount("egg_bread") == 2 and window.warehouse._showing_food)
	before = Inventory.to_dict()
	window.craft_selected()
	check("double click cannot duplicate output", Inventory.to_dict() == before)
	Inventory.from_dict({"wheat": 2})
	window.auto_fill()
	before = Inventory.to_dict()
	window.craft_selected()
	check("missing ingredients consumes nothing", Inventory.to_dict() == before and not window.ready_to_craft())
	Inventory.from_dict({"wheat": 2, "egg": 1, "tomato": 1280})
	window.auto_fill()
	before = Inventory.to_dict()
	check("full food storage blocks craft", not Book.can_make(window.selected))
	window.craft_selected()
	check("capacity failure is atomic", Inventory.to_dict() == before)
	Inventory.from_dict(stock())
	for recipe in recipes:
		window.select_recipe(recipe)
		window.auto_fill()
		before = Inventory.to_dict()
		window.craft_selected()
		var correct := Inventory.get_amount(recipe.output_id) == int(before.get(recipe.output_id, 0)) + recipe.output_amount
		for id in recipe.ingredients:
			correct = correct and Inventory.get_amount(id) == int(before.get(id, 0)) - int(recipe.ingredients[id])
		check("recipe exact quantities " + recipe.id, correct)
	var member = StaffRegistry.add_member("料理喂食测试", null, "", "npc1")
	member.satiety = 0.0
	check("crafted dish feeds NPC", StaffCare.feed(member.id, "egg_pudding") and member.satiety == 70.0 and Inventory.get_amount("egg_pudding") == 1)
	var status := InputEventKey.new()
	status.keycode = KEY_ESCAPE
	status.pressed = true
	window._unhandled_key_input(status)
	check("escape closes workbench", not window.visible)
	before = Inventory.to_dict()
	check("save crafted items", SaveManager.save_game())
	Inventory.clear()
	check("reload crafted items", SaveManager.load_save() and Inventory.to_dict() == before)
	print("COOKING_SMOKE_RESULT failures=", failures)
	get_tree().quit(failures)
