class_name RecipeBook
extends RefCounted
const IDS: Array[String] = ["egg_bread", "tomato_egg", "veggie_salad", "turnip_stew", "egg_pudding"]

static func all() -> Array[RecipeData]:
	var out: Array[RecipeData] = []
	for id in IDS:
		var recipe := load("res://data/recipes/%s.tres" % id) as RecipeData
		if recipe != null:
			out.append(recipe)
	return out

static func missing(recipe: RecipeData) -> String:
	var parts: PackedStringArray = []
	for id in recipe.ingredients:
		var lack := int(recipe.ingredients[id]) - Inventory.get_amount(id)
		if lack > 0:
			parts.append("%s ×%d" % [ItemDB.display_name(id), lack])
	return "、".join(parts)

static func can_make(recipe: RecipeData) -> bool:
	return Inventory.can_exchange(recipe.ingredients, {recipe.output_id: recipe.output_amount})

static func craft(recipe: RecipeData) -> bool:
	return Inventory.exchange(recipe.ingredients, {recipe.output_id: recipe.output_amount})
