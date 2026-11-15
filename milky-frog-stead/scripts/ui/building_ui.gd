extends RefCounted
## 建筑界面的共用配色与控件样式。
##
## 目标：像游戏里的一套木框纸面板 UI —— 暖色纸底、深木色描边、圆角、
## 图标放在深色小格子里、按钮有正常的悬停/按下反馈，而不是裸的灰色控件。
## 建筑中心页、农田页、鸡舍页都从这里取样式，避免三个界面各有一套颜色。

# ---------------- 配色 ----------------
const INK := Color("3a2e1d")
const INK_SOFT := Color("6a583c")
const TEXT_DARK := Color("3a2e1d")
const TEXT_SOFT := Color("6a583c")
const TEXT_LIGHT := Color("f6efd9")
const PAPER := Color("efe5c6")
const PAPER_DEEP := Color("e4d6b0")
const CARD_BG := Color("f7efd6")
const CARD_BORDER := Color("c8b083")
const GOLD := Color("d9a63c")
const GOLD_DARK := Color("a97c23")
const GREEN := Color("5f8f3c")
const GREEN_DARK := Color("466a2b")
const RED := Color("b8503a")
const WOOD := Color("7d5a31")
const WOOD_DARK := Color("4a3419")
const WOOD_LIGHT := Color("a67b46")
const SHADOW := Color(0.08, 0.06, 0.03, 0.35)

const TILE_SIZE := 16

# 兼容旧的颜色常量名
const PANEL_BG := PAPER
const PANEL_BORDER := WOOD_DARK
const DIM_COLOR := Color(0.05, 0.04, 0.02, 0.72)

const GROWTH_BAR := preload("res://scripts/ui/growth_bar.gd")


# ---------------- 面板 ----------------

## 整页底板：暖纸色 + 深木色粗描边 + 投影 + 内层一圈浅金线
static func page_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = WOOD_DARK
	style.set_border_width_all(4)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(26)
	style.shadow_color = SHADOW
	style.shadow_size = 14
	style.shadow_offset = Vector2(0, 6)
	return style


## 卡片：比底板再浅一点，细描边 + 轻微投影
static func card_style(highlight: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.border_color = GOLD if highlight else CARD_BORDER
	style.set_border_width_all(3 if highlight else 2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(10)
	style.shadow_color = Color(0.1, 0.07, 0.03, 0.18)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
	return style


## 深色内嵌区（田地 / 鸡舍内部）
static func dark_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color("3c2a17")
	style.set_border_width_all(4)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(6)
	return style


static func inner_style(bg: Color, border: Color = CARD_BORDER) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(8)
	return style


## 图标底格：深木色小方块，图标放中间，像物品栏格子
static func icon_slot_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("3b2a18")
	style.border_color = Color("261a0d")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(4)
	return style


# ---------------- 文字 ----------------

static func label(text_value: String, font_size: int = 16, color: Color = INK) -> Label:
	var node := Label.new()
	node.text = text_value
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	return node


static func wrapped_label(text_value: String, font_size: int = 15, color: Color = INK_SOFT) -> Label:
	var node := label(text_value, font_size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node


static func title_label(text_value: String, font_size: int = 32) -> Label:
	var node := label(text_value, font_size, INK)
	node.add_theme_color_override("font_outline_color", Color(1.0, 0.97, 0.86, 0.85))
	node.add_theme_constant_override("outline_size", 3)
	node.add_theme_color_override("font_shadow_color", Color(0.18, 0.12, 0.05, 0.35))
	node.add_theme_constant_override("shadow_offset_x", 2)
	node.add_theme_constant_override("shadow_offset_y", 2)
	return node


# ---------------- 按钮 ----------------

static func button(text_value: String, font_size: int = 16, min_height: float = 40.0) -> Button:
	return _styled_button(text_value, font_size, min_height, WOOD, WOOD_LIGHT, WOOD_DARK, TEXT_LIGHT)


## 绿色主操作按钮（投喂、一键收蛋、买种子等）
static func primary_button(text_value: String, font_size: int = 16, min_height: float = 40.0) -> Button:
	return _styled_button(text_value, font_size, min_height, GREEN, Color("6fa347"), GREEN_DARK, TEXT_LIGHT)


## 自定义颜色按钮：用于建筑中心卡片这类需要强调色的地方
static func colored_button(text_value: String, base_color: Color, font_size: int = 16,
		min_height: float = 40.0) -> Button:
	return _styled_button(text_value, font_size, min_height, base_color,
		base_color.lightened(0.12), base_color.darkened(0.18), TEXT_LIGHT)


## 半透明"幽灵"按钮：用在卡片内部当选中行
static func ghost_button(text_value: String, font_size: int = 16, min_height: float = 40.0) -> Button:
	var node := Button.new()
	node.text = text_value
	node.focus_mode = Control.FOCUS_NONE
	node.custom_minimum_size = Vector2(0, min_height)
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", INK)
	node.add_theme_color_override("font_hover_color", INK)
	node.add_theme_color_override("font_pressed_color", INK)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0, 0, 0, 0)
	normal.set_corner_radius_all(8)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(1.0, 0.95, 0.78, 0.55)
	hover.set_corner_radius_all(8)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.85, 0.76, 0.53, 0.7)
	pressed.set_corner_radius_all(8)
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("hover", hover)
	node.add_theme_stylebox_override("pressed", pressed)
	node.add_theme_stylebox_override("focus", normal)
	return node


static func _styled_button(text_value: String, font_size: int, min_height: float,
		bg: Color, bg_hover: Color, bg_pressed: Color, text_color: Color) -> Button:
	var node := Button.new()
	node.text = text_value
	node.focus_mode = Control.FOCUS_NONE
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.custom_minimum_size = Vector2(0, min_height)
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", text_color)
	node.add_theme_color_override("font_hover_color", text_color)
	node.add_theme_color_override("font_pressed_color", text_color)
	node.add_theme_color_override("font_disabled_color", Color(0.45, 0.42, 0.35, 0.8))

	node.add_theme_stylebox_override("normal", _button_style(bg, false))
	node.add_theme_stylebox_override("hover", _button_style(bg_hover, false))
	node.add_theme_stylebox_override("pressed", _button_style(bg_pressed, true))
	node.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	node.add_theme_stylebox_override("disabled", _button_style(Color("9b8f78"), true))
	return node


static func _button_style(bg: Color, pressed: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = WOOD_DARK
	style.set_border_width_all(2)
	style.set_corner_radius_all(9)
	style.set_content_margin_all(6)
	style.content_margin_top = 6 if not pressed else 9
	style.content_margin_bottom = 9 if pressed else 6
	style.shadow_color = Color(0.1, 0.07, 0.03, 0.28)
	style.shadow_size = 0 if pressed else 3
	style.shadow_offset = Vector2(0, 3) if not pressed else Vector2(0, 0)
	return style


# ---------------- 小部件 ----------------

## 图标格：深色底 + 居中图标
static func icon_slot(texture: Texture2D, slot_size: float = 48.0) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(slot_size, slot_size)
	panel.add_theme_stylebox_override("panel", icon_slot_style())
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rect)
	return panel


static func divider(color: Color = Color(0.78, 0.64, 0.35, 0.65), thickness: int = 2) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.custom_minimum_size = Vector2(0, thickness)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## 状态小药丸：带浅色底的圆角小标签
static func chip(text_value: String, color: Color = GREEN, font_size: int = 13) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.16)
	style.border_color = Color(color.r, color.g, color.b, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	style.set_content_margin_all(6)
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	var node := label(text_value, font_size, color)
	panel.add_child(node)
	return panel


## 细进度条（自绘）
static func growth_bar(fill_color: Color = GREEN, bar_width: float = 64.0, bar_height: float = 6.0) -> Control:
	var bar: Control = GROWTH_BAR.new()
	bar.custom_minimum_size = Vector2(bar_width, bar_height)
	bar.size = Vector2(bar_width, bar_height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.call("setup", fill_color)
	return bar


## 暗角：中间透明、四周略暗，放在场景区上增加一点纵深
static func vignette(strength: float = 0.32) -> TextureRect:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, strength)])
	gradient.offsets = PackedFloat32Array([0.45, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect


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


# ---------------- 兼容旧接口 ----------------

## 旧版灰底进度条（鸡舍旧代码使用；新界面请用 growth_bar）
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