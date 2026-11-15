extends RefCounted
## 建筑界面的共用样式工具。
##
## 只放「看起来要一致」的东西：配色、面板圆角、标题/正文/按钮的默认字号。
## 建筑中心页、农田页、鸡舍页都从这里取样式，避免三个界面各写一套颜色。

const TEXT_DARK := Color("473b28")
const TEXT_SOFT := Color("6b5b3e")
const TEXT_LIGHT := Color("f3ecd2")
const PANEL_BG := Color("d7cfac")
const PANEL_BORDER := Color("8f865f")
const DIM_COLOR := Color(0.06, 0.05, 0.03, 0.72)
const CARD_BG := Color("cfc39a")
const CARD_BORDER := Color("a99a70")
const TILE_SIZE := 16


## 整页底板：和料理台保持同一套浅色木纹配色
static func page_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = PANEL_BORDER
	style.set_border_width_all(3)
	style.set_corner_radius_all(20)
	style.set_content_margin_all(24)
	return style


## 卡片 / 内嵌小面板
static func card_style(highlight: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.border_color = Color(0.85, 0.66, 0.22, 1.0) if highlight else CARD_BORDER
	style.set_border_width_all(3 if highlight else 2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(12)
	return style


## 深色内嵌区（田地 / 鸡舍场景底板）
static func dark_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(0.28, 0.22, 0.12, 1.0)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(8)
	return style


static func label(text_value: String, font_size: int = 16, color: Color = TEXT_DARK) -> Label:
	var node := Label.new()
	node.text = text_value
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	return node


static func wrapped_label(text_value: String, font_size: int = 15, color: Color = TEXT_SOFT) -> Label:
	var node := label(text_value, font_size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node


static func title_label(text_value: String, font_size: int = 32) -> Label:
	var node := label(text_value, font_size, TEXT_DARK)
	node.add_theme_color_override("font_outline_color", Color(1.0, 0.98, 0.9, 0.6))
	node.add_theme_constant_override("outline_size", 2)
	return node


static func button(text_value: String, font_size: int = 16, min_height: float = 40.0) -> Button:
	var node := Button.new()
	node.text = text_value
	node.focus_mode = Control.FOCUS_NONE
	node.custom_minimum_size = Vector2(0, min_height)
	node.add_theme_font_size_override("font_size", font_size)
	return node


static func progress_bar(fill_color: Color, height: float = 8.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 0.0
	bar.custom_minimum_size = Vector2(0, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.10, 0.07, 0.9)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


## 从一张 16x16 的 TileSet 贴图里切一块出来，给 TextureRect 平铺当底板。
static func tile_texture(texture: Texture2D, index: int = 0) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	if texture == null:
		return atlas
	var cell := TILE_SIZE
	var columns := maxi(1, int(texture.get_width()) / cell)
	var column := index % columns
	var row := floori(float(index) / float(columns))
	atlas.region = Rect2(column * cell, row * cell, cell, cell)
	return atlas


static func tiled_rect(texture: Texture2D, index: int = 0) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = tile_texture(texture, index)
	rect.stretch_mode = TextureRect.STRETCH_TILE
	rect.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect


static func icon_texture(item_id: String) -> Texture2D:
	return ItemDB.icon(item_id)
