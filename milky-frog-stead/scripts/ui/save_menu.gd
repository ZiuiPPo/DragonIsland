extends Control
## 多槽位存档界面。
##
## 两种进入方式：
##   MODE_LOAD     —— 主菜单「读取存档」：读取 / 新建 / 覆盖 / 删除
##   MODE_NEW_GAME —— 主菜单「开始新游戏」：新建 / 覆盖 / 删除
##
## 卡片本身只发信号；真正的新游戏初始化、读档和场景跳转由 scene_handler 统一处理。

signal back_pressed()
signal load_requested(slot: int)
signal new_game_requested(slot: int)

const CARD_SCENE: PackedScene = preload("res://scenes/ui/save_slot_card.tscn")

const MODE_LOAD: int = 0
const MODE_NEW_GAME: int = 1

@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _card_box: VBoxContainer = %CardBox
@onready var _hint: Label = %Hint
@onready var _back_button: Button = %BackButton
@onready var _confirm: ConfirmationDialog = %ConfirmDialog

var _mode: int = MODE_LOAD
var _cards: Array[Node] = []
var _pending_action: Callable = Callable()


func _ready() -> void:
	_back_button.pressed.connect(_on_back_pressed)
	_confirm.confirmed.connect(_on_confirm_confirmed)
	SaveManager.save_changed.connect(_refresh)
	_build_cards()
	_refresh()


func set_mode(mode: int) -> void:
	_mode = mode if mode == MODE_NEW_GAME else MODE_LOAD
	if is_node_ready():
		_refresh()


func show_message(text: String) -> void:
	_hint.text = text


func refresh_saves() -> void:
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _confirm.visible:
		_on_back_pressed()
		get_viewport().set_input_as_handled()


# ---------------- 构建 / 刷新 ----------------

func _build_cards() -> void:
	for child in _card_box.get_children():
		_card_box.remove_child(child)
		child.queue_free()
	_cards.clear()

	for slot in range(1, SaveManager.SLOT_COUNT + 1):
		var card: Node = CARD_SCENE.instantiate()
		_card_box.add_child(card)
		# 按信号名连接，卡片脚本类型不在这里写死
		card.connect("new_game_requested", _on_new_game_requested)
		card.connect("load_requested", _on_load_requested)
		card.connect("overwrite_requested", _on_overwrite_requested)
		card.connect("delete_requested", _on_delete_requested)
		_cards.append(card)


func _refresh() -> void:
	_title.text = "开始新游戏" if _mode == MODE_NEW_GAME else "读取存档"
	_subtitle.text = (
		"选择空槽位新建存档，或覆盖已有存档"
		if _mode == MODE_NEW_GAME
		else "选择一份存档读取，也可以新建、覆盖或删除"
	)

	var summaries := SaveManager.get_all_slot_summaries()
	for i in range(_cards.size()):
		var summary: Dictionary = {}
		if i < summaries.size():
			summary = summaries[i]
		_cards[i].call("setup", i + 1, summary, _mode)

	var used := SaveManager.get_used_slot_count()
	if _mode == MODE_NEW_GAME and used >= SaveManager.SLOT_COUNT:
		_hint.text = "存档位已满，请选择一个槽位覆盖"
	else:
		_hint.text = "共 %d 个存档位，已用 %d 个" % [SaveManager.SLOT_COUNT, used]


# ---------------- 卡片操作 ----------------

## 空槽位直接新建；已有存档先确认覆盖。
func _on_new_game_requested(slot: int) -> void:
	var summary := SaveManager.get_slot_summary(slot)
	if not bool(summary.get("exists", false)):
		new_game_requested.emit(slot)
		return
	_confirm_overwrite(slot, summary)


func _on_overwrite_requested(slot: int) -> void:
	_confirm_overwrite(slot, SaveManager.get_slot_summary(slot))


func _confirm_overwrite(slot: int, summary: Dictionary) -> void:
	var detail := "存档 %d" % slot
	if bool(summary.get("valid", false)):
		detail = "%s · 第 %d 天" % [
			String(summary.get("farm_name", SaveManager.DEFAULT_FARM_NAME)),
			int(summary.get("day", 1)),
		]
	var start_new := func() -> void:
		new_game_requested.emit(slot)
	_ask(
		"覆盖 %s 的存档？\n原进度会丢失，并从第 1 天重新开始。" % detail,
		start_new
	)


func _on_load_requested(slot: int) -> void:
	var summary := SaveManager.get_slot_summary(slot)
	if not bool(summary.get("can_load", false)):
		_hint.text = "该存档无法读取，请选择其它槽位"
		return

	if bool(summary.get("old_version", false)):
		var do_load := func() -> void:
			load_requested.emit(slot)
		_ask(
			"这是旧版本（v%d）存档。\n读取会尽量兼容，并自动升级为当前版本。" % int(summary.get("version", 1)),
			do_load
		)
		return

	load_requested.emit(slot)


func _on_delete_requested(slot: int) -> void:
	var summary := SaveManager.get_slot_summary(slot)
	var detail := "存档 %d" % slot
	if bool(summary.get("valid", false)):
		detail = "%s · 第 %d 天" % [
			String(summary.get("farm_name", SaveManager.DEFAULT_FARM_NAME)),
			int(summary.get("day", 1)),
		]
	var do_delete := func() -> void:
		if SaveManager.delete_slot(slot):
			_hint.text = "存档 %d 已删除" % slot
		else:
			_hint.text = "删除存档失败"
	_ask("确定删除 %s 吗？\n删除后无法恢复。" % detail, do_delete)


func _on_back_pressed() -> void:
	back_pressed.emit()


# ---------------- 确认框 ----------------

func _ask(text: String, action: Callable) -> void:
	_pending_action = action
	_confirm.dialog_text = text
	_confirm.popup_centered()


func _on_confirm_confirmed() -> void:
	var action := _pending_action
	_pending_action = Callable()
	if action.is_valid():
		action.call()
