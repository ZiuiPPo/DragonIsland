extends PanelContainer
## 一个存档位卡片。只接收摘要和模式，不直接读写文件。

signal primary_pressed(slot: int)
signal delete_requested(slot: int)

const MODE_LOAD: int = 0
const MODE_NEW: int = 1

@onready var _slot_title: Label = %SlotTitle
@onready var _status: Label = %Status
@onready var _meta: Label = %Meta
@onready var _time: Label = %Time
@onready var _primary: Button = %PrimaryButton
@onready var _delete: Button = %DeleteButton

var slot_index: int = 0
var mode: int = MODE_LOAD


func _ready() -> void:
	_primary.pressed.connect(_on_primary_pressed)
	_delete.pressed.connect(_on_delete_pressed)


func setup(summary: Dictionary, card_mode: int) -> void:
	slot_index = int(summary.get("slot", 0))
	mode = card_mode

	var exists := bool(summary.get("exists", false))
	var can_load := bool(summary.get("can_load", false))
	var status := String(summary.get("status", "empty"))
	_slot_title.text = "存档位 %d" % slot_index

	if not exists:
		_status.text = "空槽位"
		_status.add_theme_color_override("font_color", Color(0.8, 0.74, 0.58, 0.7))
		_meta.text = "还没有保存进度"
		_time.text = "新建后可保存农场数据"
		_primary.visible = mode == MODE_NEW
		_primary.text = "新建存档"
		_primary.disabled = false
		_delete.visible = false
		return

	if can_load:
		_status.text = "可读取"
		_status.add_theme_color_override("font_color", Color(0.55, 0.82, 0.48, 1))
		_meta.text = "金币 %d · 员工 %d 名 · 第 %d 天" % [
			int(summary.get("gold", 0)),
			int(summary.get("staff_count", 0)),
			int(summary.get("day", 0)),
		]
		_time.text = "保存于 %s" % _format_time(String(summary.get("saved_at", "")))
	else:
		_status.text = String(summary.get("status_text", "存档不可用"))
		_status.add_theme_color_override("font_color", Color(0.95, 0.55, 0.35, 1))
		_meta.text = "此槽位不能直接读取"
		_time.text = "可以删除或覆盖"

	if mode == MODE_NEW:
		_primary.visible = true
		_primary.text = "覆盖新建"
		_primary.disabled = false
	else:
		_primary.visible = can_load
		_primary.text = "读取存档"
		_primary.disabled = not can_load
	_delete.visible = true


func _format_time(raw: String) -> String:
	if raw.is_empty():
		return "未知时间"
	var text := raw.replace("T", " ")
	if text.length() > 16:
		text = text.substr(0, 16)
	return text


func _on_primary_pressed() -> void:
	primary_pressed.emit(slot_index)


func _on_delete_pressed() -> void:
	delete_requested.emit(slot_index)
