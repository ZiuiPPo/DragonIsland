extends Control
## 多存档界面：固定 SLOT_COUNT 个槽位，支持读取、新建、覆盖新建、删除。

signal back_pressed()
signal new_game_requested(slot: int)
signal load_requested(slot: int)

const MODE_LOAD: int = 0
const MODE_NEW: int = 1
const CARD_SCENE: PackedScene = preload("res://scenes/ui/save_slot_card.tscn")

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _card_box: HBoxContainer = %CardBox
@onready var _hint: Label = %Hint
@onready var _back_button: Button = %BackButton
@onready var _confirm: ConfirmationDialog = %ConfirmDialog

var mode: int = MODE_LOAD
var _pending_action: Callable = Callable()


func _ready() -> void:
	_back_button.pressed.connect(_on_back_pressed)
	_confirm.confirmed.connect(_on_confirm)
	SaveManager.save_changed.connect(_refresh)
	_refresh()


func set_mode(value: int) -> void:
	mode = value
	if mode == MODE_NEW:
		_title.text = "开始新游戏"
		_subtitle.text = "选择一个槽位开始；覆盖已有存档会先确认"
	else:
		_title.text = "读取存档"
		_subtitle.text = "选择一个已保存的农场进度"
	_refresh()


func show_message(text: String) -> void:
	_hint.text = text


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _confirm.visible:
		_on_back_pressed()
		get_viewport().set_input_as_handled()


# ---------------- 列表 ----------------

func _refresh() -> void:
	if not is_node_ready():
		return
	for child in _card_box.get_children():
		_card_box.remove_child(child)
		child.queue_free()

	for summary in SaveManager.get_all_slot_summaries():
		var card := CARD_SCENE.instantiate() as PanelContainer
		_card_box.add_child(card)
		card.call("setup", summary, mode)
		card.connect("primary_pressed", _on_primary_pressed)
		card.connect("delete_requested", _on_delete_requested)

	var used := SaveManager.get_used_slot_count()
	_hint.text = "已用 %d/%d 个存档位" % [used, SaveManager.SLOT_COUNT]


func _format_time(raw: String) -> String:
	if raw.is_empty():
		return "未知时间"
	var text := raw.replace("T", " ")
	if text.length() > 16:
		text = text.substr(0, 16)
	return text


# ---------------- 操作 ----------------

func _on_primary_pressed(slot: int) -> void:
	var summary := SaveManager.get_slot_summary(slot)
	if mode == MODE_NEW:
		if bool(summary.get("exists", false)):
			_ask(
				"覆盖存档",
				"存档位 %d 已有进度，覆盖后会清除原来的农场数据。\n确定要覆盖吗？" % slot,
				"覆盖",
				func() -> void: new_game_requested.emit(slot)
			)
		else:
			new_game_requested.emit(slot)
		return

	if not bool(summary.get("can_load", false)):
		_hint.text = "这个存档位不能读取"
		return
	load_requested.emit(slot)


func _on_delete_requested(slot: int) -> void:
	var summary := SaveManager.get_slot_summary(slot)
	if not bool(summary.get("exists", false)):
		return
	_ask(
		"删除存档",
		"确定删除存档位 %d 的进度吗？\n删除后无法恢复。" % slot,
		"删除",
		func() -> void:
			SaveManager.delete_slot(slot)
			_hint.text = "存档位 %d 已删除" % slot
	)


func _ask(title: String, text: String, confirm_text: String, action: Callable) -> void:
	_pending_action = action
	_confirm.title = title
	_confirm.dialog_text = text
	_confirm.ok_button_text = confirm_text
	_confirm.cancel_button_text = "取消"
	_confirm.popup_centered()


func _on_confirm() -> void:
	if _pending_action.is_valid():
		_pending_action.call()
	_pending_action = Callable()
	_refresh()


func _on_back_pressed() -> void:
	back_pressed.emit()
