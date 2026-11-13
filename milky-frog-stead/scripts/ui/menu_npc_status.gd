extends VBoxContainer
## 员工状态界面（名册数据的视图层）。
##
## 列表 / 详情 / 筛选 / 操作都只读写 StaffRegistry。
## 名册变化发 staff_changed，界面自动刷新；界面上的岗位、任务、休息、解雇操作
## 也全部调用 StaffRegistry 的方法，由它再发信号。
##
## 物品栏：
##   上方 5 格背包，下方员工携带槽；两个 ItemSlot 都绑定 Inventory，拖拽直接走库存接口。

const PORTRAIT_SIZE: float = 44.0
const BACKPACK_SLOTS: int = 5

const SLOT_SCENE: PackedScene = preload("res://scenes/ui/item_slot.tscn")

const STATE_FILTERS: Array = [
	{"text": "全部", "status": ""},
	{"text": "在岗", "status": "工作中"},
	{"text": "空闲", "status": "空闲"},
	{"text": "休息", "status": "休息"},
]

const TASK_OPTIONS: Array = [
	{"name": "浇水", "hours": 2.0},
	{"name": "收获", "hours": 2.0},
	{"name": "喂鸡", "hours": 1.5},
	{"name": "打扫", "hours": 1.0},
]

@onready var _list_view: VBoxContainer = %ListView
@onready var _detail_view: VBoxContainer = %DetailView

@onready var _state_filter: OptionButton = %StateFilter
@onready var _job_filter: OptionButton = %JobFilter
@onready var _empty_label: Label = %EmptyLabel
@onready var _scroll: ScrollContainer = %Scroll
@onready var _list: VBoxContainer = %List
@onready var _list_hint: Label = %ListHint

@onready var _back_button: Button = %BackButton
@onready var _detail_scroll: ScrollContainer = %DetailScroll
@onready var _detail_portrait: TextureRect = %DetailPortrait
@onready var _detail_name: Label = %DetailName
@onready var _detail_id: Label = %DetailId
@onready var _detail_job: Label = %DetailJob
@onready var _basic_grid: GridContainer = %BasicGrid
@onready var _status_grid: GridContainer = %StatusGrid
@onready var _backpack_row: HBoxContainer = %BackpackRow
@onready var _equip_holder: HBoxContainer = %EquipHolder
@onready var _job_button: Button = %JobButton
@onready var _task_button: Button = %TaskButton
@onready var _rest_button: Button = %RestButton
@onready var _fire_button: Button = %FireButton
@onready var _detail_hint: Label = %DetailHint

@onready var _job_popup: PopupMenu = %JobPopup
@onready var _task_popup: PopupMenu = %TaskPopup
@onready var _fire_dialog: ConfirmationDialog = %FireDialog

var _selected_id: int = 0
var _state_filter_value: String = ""
var _job_filter_value: String = ""
var _equip_slot: PanelContainer


func _ready() -> void:
	_build_backpack_slots()
	_build_equip_slot()
	_setup_state_filter()
	_setup_job_filter()
	_setup_task_popup()

	_job_popup.id_pressed.connect(_on_job_selected)
	_task_popup.id_pressed.connect(_on_task_selected)
	_fire_dialog.confirmed.connect(_on_fire_confirmed)
	_back_button.pressed.connect(_close_detail)
	_job_button.pressed.connect(_on_job_pressed)
	_task_button.pressed.connect(_on_task_pressed)
	_rest_button.pressed.connect(_on_rest_pressed)
	_fire_button.pressed.connect(_on_fire_pressed)

	StaffRegistry.staff_changed.connect(_on_staff_changed)
	StaffRegistry.staff_removed.connect(_on_staff_removed)
	SaveManager.game_loaded.connect(_on_game_loaded)
	_refresh_list()


func open_member(member_id: int) -> void:
	var member := StaffRegistry.get_member(member_id)
	if member == null:
		return
	_selected_id = member_id
	_list_view.visible = false
	_detail_view.visible = true
	_detail_scroll.scroll_vertical = 0
	_refresh_detail()


# ---------------- 筛选 / 列表 ----------------

func _setup_state_filter() -> void:
	_state_filter.clear()
	for entry in STATE_FILTERS:
		_state_filter.add_item(String(entry["text"]))
	_state_filter.select(0)
	_state_filter.item_selected.connect(_on_state_filter_selected)


func _setup_job_filter() -> void:
	_refresh_job_filter()
	_job_filter.item_selected.connect(_on_job_filter_selected)


func _setup_task_popup() -> void:
	_task_popup.clear()
	for task in TASK_OPTIONS:
		_task_popup.add_item(String(task["name"]))


func _refresh_job_filter() -> void:
	var wanted := _job_filter_value
	_job_filter.clear()
	_job_filter.add_item("全部岗位")
	var selected := 0
	var jobs := StaffRegistry.get_jobs()
	for job in jobs:
		_job_filter.add_item(job)
		if job == wanted:
			selected = _job_filter.item_count - 1
	_job_filter.select(selected)
	_job_filter_value = "" if selected == 0 else _job_filter.get_item_text(selected)


func _on_state_filter_selected(index: int) -> void:
	if index < 0 or index >= STATE_FILTERS.size():
		return
	_state_filter_value = String(STATE_FILTERS[index]["status"])
	_refresh_list()


func _on_job_filter_selected(index: int) -> void:
	_job_filter_value = "" if index == 0 else _job_filter.get_item_text(index)
	_refresh_list()


func _refresh_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	var total := StaffRegistry.count()
	var filtered := StaffRegistry.get_filtered_members(_state_filter_value, _job_filter_value)

	if total == 0:
		_empty_label.text = "还没有员工，去「招聘」抽一个吧"
		_empty_label.visible = true
	elif filtered.is_empty():
		_empty_label.text = "没有符合筛选条件的员工"
		_empty_label.visible = true
	else:
		_empty_label.visible = false

	_scroll.visible = not filtered.is_empty()
	for member in filtered:
		_list.add_child(_make_row(member))

	_list_hint.text = "共 %d 人 · 在岗 %d · 空闲 %d · 休息 %d" % [
		total,
		StaffRegistry.count_status(StaffMember.STATUS_WORKING),
		StaffRegistry.count_status(StaffMember.STATUS_IDLE),
		StaffRegistry.count_status(StaffMember.STATUS_RESTING),
	]


func _make_row(member: StaffMember) -> Control:
	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size = Vector2(0, 58)
	row_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	row_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row_panel.gui_input.connect(_on_row_gui_input.bind(member.id))

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.91, 0.83, 0.55)
	style.border_width_left = 3
	style.border_color = _status_color(member.status)
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	style.content_margin_left = 7
	style.content_margin_top = 7
	style.content_margin_right = 7
	style.content_margin_bottom = 7
	row_panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	row_panel.add_child(row)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = member.portrait
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	info.add_theme_constant_override("separation", 1)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info)

	var name_label := Label.new()
	name_label.text = member.display_name
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_label)

	var meta := Label.new()
	meta.text = "#%d · %s" % [member.id, member.job if not member.job.is_empty() else "未分配"]
	meta.add_theme_font_size_override("font_size", 11)
	meta.add_theme_color_override("font_color", Color(0.18, 0.14, 0.08, 0.85))
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(meta)

	var status_label := Label.new()
	status_label.text = member.status
	status_label.add_theme_font_size_override("font_size", 12)
	status_label.add_theme_color_override("font_color", _status_color(member.status))
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(status_label)

	var arrow := Label.new()
	arrow.text = "›"
	arrow.add_theme_font_size_override("font_size", 20)
	arrow.add_theme_color_override("font_color", Color(0.25, 0.2, 0.12, 0.5))
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow)

	return row_panel


func _on_row_gui_input(event: InputEvent, member_id: int) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			open_member(member_id)
			accept_event()


func _status_color(status: String) -> Color:
	if status == StaffMember.STATUS_WORKING:
		return Color(0.22, 0.52, 0.27, 1)
	if status == StaffMember.STATUS_RESTING:
		return Color(0.6, 0.48, 0.18, 1)
	return Color(0.72, 0.33, 0.2, 1)


# ---------------- 详情 ----------------

func _refresh_detail() -> void:
	var member := StaffRegistry.get_member(_selected_id)
	if member == null:
		_close_detail()
		return

	_detail_portrait.texture = member.portrait
	_detail_name.text = member.display_name
	_detail_id.text = "ID：%d" % member.id
	_detail_job.text = "岗位：%s" % (member.job if not member.job.is_empty() else "未分配")

	_fill_grid(_basic_grid, [
		["岗位", member.job if not member.job.is_empty() else "未分配"],
		["熟练度", "Lv.%d / 5" % member.proficiency],
		["薪资", "%d 金币/天" % member.salary],
		["出勤", member.attendance],
	])
	_fill_grid(_status_grid, [
		["当前状态", member.status],
		["当前工作目标", member.current_task if not member.current_task.is_empty() else "无"],
		["剩余工时", "%.1f 小时" % member.remaining_hours],
		["体力", "%d / 100" % int(round(member.stamina))],
		["心情", "%d / 100" % int(round(member.mood))],
	])

	Inventory.ensure_staff_container(member.id)
	_equip_slot.call("bind", "%s%d" % [Inventory.STAFF_PREFIX, member.id], 0)
	_equip_slot.call("set_default_tooltip", "%s 的装备（只能放种子）" % member.display_name)

	_rest_button.disabled = member.is_resting()
	_detail_hint.text = "状态修改会立即写回名册并自动存档"


func _fill_grid(grid: GridContainer, rows: Array) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for row in rows:
		var key := Label.new()
		key.text = String(row[0])
		key.add_theme_font_size_override("font_size", 12)
		key.add_theme_color_override("font_color", Color(0.18, 0.14, 0.08, 0.9))
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(key)

		var value := Label.new()
		value.text = String(row[1])
		value.add_theme_font_size_override("font_size", 12)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(value)


func _close_detail() -> void:
	_selected_id = 0
	_detail_view.visible = false
	_list_view.visible = true
	_refresh_list()


func _on_staff_changed() -> void:
	if SaveManager.is_restoring():
		return
	_refresh_job_filter()
	_refresh_list()
	if _selected_id != 0:
		if StaffRegistry.get_member(_selected_id) == null:
			_close_detail()
		else:
			_refresh_detail()


func _on_staff_removed(member_id: int) -> void:
	if member_id == _selected_id:
		_close_detail()


func _on_game_loaded(_slot: int) -> void:
	_refresh_job_filter()
	_refresh_list()
	if _selected_id != 0:
		if StaffRegistry.get_member(_selected_id) == null:
			_close_detail()
		else:
			_refresh_detail()


# ---------------- 操作 ----------------

func _on_job_pressed() -> void:
	if _selected_id == 0:
		return
	_job_popup.clear()
	for job in StaffMember.JOB_OPTIONS:
		_job_popup.add_item(job)
	_job_popup.add_separator()
	_job_popup.add_item("清除岗位")
	_popup_below(_job_popup, _job_button)


func _on_job_selected(index: int) -> void:
	if _selected_id == 0:
		return
	var job := ""
	if index >= 0 and index < StaffMember.JOB_OPTIONS.size():
		job = StaffMember.JOB_OPTIONS[index]
	else:
		job = ""
	if StaffRegistry.set_job(_selected_id, job):
		_detail_hint.text = "岗位已更新为「%s」" % (job if not job.is_empty() else "未分配")


func _on_task_pressed() -> void:
	if _selected_id == 0:
		return
	_task_popup.clear()
	for task in TASK_OPTIONS:
		_task_popup.add_item(String(task["name"]))
	_popup_below(_task_popup, _task_button)


func _on_task_selected(index: int) -> void:
	if _selected_id == 0:
		return
	if index < 0 or index >= TASK_OPTIONS.size():
		return
	var task: Dictionary = TASK_OPTIONS[index]
	if StaffRegistry.assign_task(_selected_id, String(task["name"]), float(task["hours"])):
		_detail_hint.text = "已指派「%s」，预计 %.1f 小时" % [String(task["name"]), float(task["hours"])]


func _on_rest_pressed() -> void:
	if _selected_id == 0:
		return
	if StaffRegistry.force_rest(_selected_id):
		_detail_hint.text = "已强制休息，体力和心情有所恢复"


func _on_fire_pressed() -> void:
	if _selected_id == 0:
		return
	var member := StaffRegistry.get_member(_selected_id)
	if member == null:
		return
	_fire_dialog.dialog_text = "确定解雇「%s」吗？\n携带物品会尝试放回仓库。" % member.display_name
	_fire_dialog.popup_centered()


func _on_fire_confirmed() -> void:
	if _selected_id == 0:
		return
	var fired_id := _selected_id
	Inventory.return_container_to_warehouse("%s%d" % [Inventory.STAFF_PREFIX, fired_id])
	if StaffRegistry.dismiss_member(fired_id):
		_close_detail()


func _popup_below(popup: PopupMenu, button: Button) -> void:
	popup.position = Vector2i(button.get_screen_position() + Vector2(0, button.size.y + 2))
	popup.popup()


# ---------------- 物品栏 ----------------

func _build_backpack_slots() -> void:
	Inventory.ensure_container(Inventory.BACKPACK_ID, BACKPACK_SLOTS, "背包")
	for i in range(BACKPACK_SLOTS):
		var slot := SLOT_SCENE.instantiate() as PanelContainer
		_backpack_row.add_child(slot)
		slot.call("bind", Inventory.BACKPACK_ID, i)


func _build_equip_slot() -> void:
	_equip_slot = SLOT_SCENE.instantiate() as PanelContainer
	_equip_holder.add_child(_equip_slot)
