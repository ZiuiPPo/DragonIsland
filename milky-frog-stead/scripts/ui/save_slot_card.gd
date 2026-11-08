extends PanelContainer
## 单个存档槽卡片：缩略图、农场名、天数、保存时间、状态提示和操作按钮。
##
## 由 SaveMenu 按 SLOT_COUNT 动态生成。
## 卡片只显示和发信号，真正的新游戏/读档/删除由 SaveMenu + scene_handler 处理。

signal new_game_requested(slot: int)
signal load_requested(slot: int)
signal overwrite_requested(slot: int)
signal delete_requested(slot: int)

const MODE_LOAD: int = 0
const MODE_NEW_GAME: int = 1

@onready var _thumbnail: TextureRect = %Thumbnail
@onready var _thumbnail_empty: Label = %ThumbnailEmpty
@onready var _farm_name: Label = %FarmName
@onready var _meta: Label = %Meta
@onready var _saved_at: Label = %SavedAt
@onready var _status: Label = %Status
@onready var _new_button: Button = %NewButton
@onready var _load_button: Button = %LoadButton
@onready var _overwrite_button: Button = %OverwriteButton
@onready var _delete_button: Button = %DeleteButton

var _slot: int = 0
var _mode: int = MODE_LOAD


func _ready() -> void:
	_new_button.pressed.connect(_on_new_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	_overwrite_button.pressed.connect(_on_overwrite_pressed)
	_delete_button.pressed.connect(_on_delete_pressed)


func setup(slot: int, summary: Dictionary, mode: int) -> void:
	_slot = slot
	_mode = mode
	var exists := bool(summary.get("exists", false))
	var can_load := bool(summary.get("can_load", false))
	var status := String(summary.get("status", "empty"))
	var version := int(summary.get("version", 0))

	var texture := SaveManager.get_slot_thumbnail(slot)
	_thumbnail.texture = texture
	_thumbnail_empty.visible = texture == null

	if not exists:
		_farm_name.text = "空存档位"
		_meta.text = "新建后开始一段新的农场生活"
		_saved_at.visible = false
		_status.visible = false
		_new_button.visible = true
		_load_button.visible = false
		_overwrite_button.visible = false
		_delete_button.visible = false
		modulate = Color(1, 1, 1, 1)
		return

	modulate = Color(1, 1, 1, 1)
	var metadata_ok := status == "ok" or status == "old"
	if not metadata_ok:
		_farm_name.text = "存档 %d" % slot
		_meta.text = "该槽位的数据无法正常读取"
		_saved_at.visible = false
	else:
		var farm_name := String(summary.get("farm_name", SaveManager.DEFAULT_FARM_NAME))
		if farm_name.is_empty():
			farm_name = "存档 %d" % slot
		_farm_name.text = farm_name
		_meta.text = "第 %d 天 · 金币 %d · 员工 %d 名" % [
			int(summary.get("day", 1)),
			int(summary.get("gold", 0)),
			int(summary.get("staff_count", 0)),
		]
		var saved_at_text := _format_time(String(summary.get("saved_at", "")))
		_saved_at.text = "保存于 %s" % saved_at_text
		_saved_at.visible = not saved_at_text.is_empty()

	_status.visible = status != "ok"
	_status.modulate = Color(1, 1, 1, 1)
	_status.add_theme_color_override("font_color", Color(0.95, 0.84, 0.62, 1))
	match status:
		"old":
			_status.text = "旧版本 v%d（读取后自动升级）" % version
			_status.add_theme_color_override("font_color", Color(1, 0.82, 0.45, 1))
		"corrupt":
			_status.text = "存档损坏，无法读取"
			_status.add_theme_color_override("font_color", Color(1, 0.42, 0.36, 1))
		"future":
			_status.text = "存档版本 v%d 高于当前游戏，暂不支持" % version
			_status.add_theme_color_override("font_color", Color(1, 0.42, 0.36, 1))
		"unsupported":
			_status.text = "存档版本 v%d 过旧，暂不支持" % version
			_status.add_theme_color_override("font_color", Color(1, 0.42, 0.36, 1))
		_:
			_status.text = ""
	_status.tooltip_text = _status.text

	# 读取模式：有可读存档才显示读取；新游戏模式不显示读取
	_load_button.visible = _mode == MODE_LOAD and can_load
	_overwrite_button.visible = true
	_delete_button.visible = true
	_new_button.visible = false


func _format_time(raw: String) -> String:
	if raw.is_empty():
		return ""
	var text := raw.replace("T", " ")
	if text.length() > 16:
		text = text.substr(0, 16)
	return text


func _on_new_pressed() -> void:
	new_game_requested.emit(_slot)


func _on_load_pressed() -> void:
	load_requested.emit(_slot)


func _on_overwrite_pressed() -> void:
	overwrite_requested.emit(_slot)


func _on_delete_pressed() -> void:
	delete_requested.emit(_slot)
