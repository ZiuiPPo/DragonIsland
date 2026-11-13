extends Control
## 存档界面：显示唯一的存档，提供读取 / 删除 / 返回。
##
## 场景切换不在这里做：读取成功后发 load_requested，由 scene_handler 跳到农场；
## 返回时发 back_pressed，由 scene_handler 切回主菜单。

signal back_pressed()
signal load_requested()

@onready var _slot_panel: PanelContainer = %SlotPanel
@onready var _empty_panel: Control = %EmptyPanel
@onready var _slot_meta: Label = %SlotMeta
@onready var _slot_time: Label = %SlotTime
@onready var _load_button: Button = %LoadButton
@onready var _delete_button: Button = %DeleteButton
@onready var _back_button: Button = %BackButton
@onready var _hint: Label = %Hint
@onready var _confirm_delete: ConfirmationDialog = %ConfirmDelete


func _ready() -> void:
	_load_button.pressed.connect(_on_load_pressed)
	_delete_button.pressed.connect(_on_delete_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_confirm_delete.confirmed.connect(_on_delete_confirmed)
	SaveManager.save_changed.connect(_refresh)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _confirm_delete.visible:
		_on_back_pressed()
		get_viewport().set_input_as_handled()


## 给 scene_handler 在跳转失败时显示提示用
func show_message(text: String) -> void:
	_hint.text = text


# ---------------- 刷新显示 ----------------

func _refresh() -> void:
	var summary := SaveManager.get_save_summary()
	var exists := bool(summary.get("exists", false))

	_slot_panel.visible = exists
	_empty_panel.visible = not exists
	_load_button.disabled = not exists
	_delete_button.disabled = not exists

	if not exists:
		_hint.text = "开始一段农场生活后，回到这里就能读取进度"
		return

	_slot_meta.text = "金币 %d · 员工 %d 名" % [
		int(summary.get("gold", 0)),
		int(summary.get("staff_count", 0)),
	]
	_slot_time.text = "保存于 %s" % _format_time(String(summary.get("saved_at", "")))
	_hint.text = "单存档模式 · 共 1 个槽位"


func _format_time(raw: String) -> String:
	if raw.is_empty():
		return "未知时间"
	var text := raw.replace("T", " ")
	if text.length() > 16:
		text = text.substr(0, 16)
	return text


# ---------------- 按钮 ----------------

func _on_load_pressed() -> void:
	if not SaveManager.load_save():
		_refresh()
		_hint.text = "存档读取失败，文件可能损坏"
		return
	load_requested.emit()


func _on_delete_pressed() -> void:
	if SaveManager.has_save():
		_confirm_delete.popup_centered()


func _on_delete_confirmed() -> void:
	SaveManager.delete_save()
	_hint.text = "存档已删除"


func _on_back_pressed() -> void:
	back_pressed.emit()
