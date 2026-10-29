extends VBoxContainer
## 招聘菜单（抽卡）。
##
## 流程：点「招聘一次」→ 扣钱 → 从 pool 里等概率抽一名 → 显示立绘 + 起名框
##      → 点「确定录用」（或回车）→ 写进 StaffRegistry → 员工状态菜单自动刷新。
##
## 招聘池不是写死的：运行时扫描 POOL_DIR 下的所有 png，往目录里丢一张新图就多一个可抽角色。
## 每张立绘必须有同名的序列帧（见 scripts/staff/staff_looks.gd），否则会被跳过。
## 概率目前完全平均（randi_range 均匀取一个），以后要加权就改 _pick()。

const POOL_DIR: String = "res://assets/icons/recruit"
## 用 preload 而不是全局类名：新脚本的 class_name 要等编辑器扫过才注册
const Looks := preload("res://scripts/staff/staff_looks.gd")
const POOL_COLUMNS: int = 3
const POOL_CELL: float = 64.0
## 抽一次多少钱
const DRAW_COST: int = 100

@onready var _pool_grid: GridContainer = %PoolGrid
@onready var _result_panel: Control = %ResultPanel
@onready var _result_portrait: TextureRect = %ResultPortrait
@onready var _name_edit: LineEdit = %NameEdit
@onready var _confirm_button: Button = %ConfirmButton
@onready var _draw_button: Button = %DrawButton
@onready var _hint: Label = %Hint

## [{ "path": String, "texture": Texture2D }, ...]
var _pool: Array[Dictionary] = []
## 抽到但还没起名的那个角色；空字典 = 没有待处理
var _pending: Dictionary = {}

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_result_panel.visible = false
	_draw_button.pressed.connect(_on_draw)
	_confirm_button.pressed.connect(_on_confirm)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_load_pool()
	_build_pool_cells()
	_update_draw_button()
	_set_hint("抽一次 %d 金币" % DRAW_COST)


# ---------------- 招聘池 ----------------

## 扫描目录，把每个 png 变成一个候选角色
func _load_pool() -> void:
	_pool.clear()
	var dir := DirAccess.open(POOL_DIR)
	if dir == null:
		push_error("招聘目录打不开：%s" % POOL_DIR)
		return

	var files := dir.get_files()
	files.sort()
	for file in files:
		# 编辑器里目录同时有 npc1.png 和 npc1.png.import，只认前者
		if file.ends_with(".import"):
			continue
		if not file.to_lower().ends_with(".png"):
			continue
		var path := "%s/%s" % [POOL_DIR, file]
		# look = 立绘文件名，进场景后按它加载同名的序列帧（见 StaffLooks）
		var look := file.get_basename()
		if not Looks.has_look(look):
			push_warning("招聘池里的 %s 没有对应的序列帧，先跳过（看 scripts/staff/staff_looks.gd 的命名约定）" % file)
			continue
		var texture := load(path) as Texture2D
		if texture == null:
			push_warning("招聘池里的图加载失败：%s" % path)
			continue
		_pool.append({"path": path, "texture": texture, "look": look})


## 把招聘池画成格子，给玩家看"能抽到谁"
func _build_pool_cells() -> void:
	for child in _pool_grid.get_children():
		_pool_grid.remove_child(child)
		child.queue_free()

	for entry in _pool:
		var cell := TextureRect.new()
		cell.custom_minimum_size = Vector2(POOL_CELL, POOL_CELL)
		cell.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cell.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.texture = entry["texture"]
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.tooltip_text = (entry["path"] as String).get_file()
		_pool_grid.add_child(cell)


# ---------------- 抽一次 ----------------

func _on_draw() -> void:
	if not _pending.is_empty():
		_set_hint("先给刚抽到的角色起个名字")
		return
	if _pool.is_empty():
		_set_hint("招聘池是空的：往 %s 里放角色图" % POOL_DIR)
		return

	var wallet := _get_wallet()
	if wallet == null:
		_set_hint("场景里找不到金币计数器（CoinCounter）")
		return
	# spend_gold 余额不够会返回 false 且什么都不改
	if not wallet.spend_gold(DRAW_COST):
		_set_hint("金币不够，抽一次要 %d" % DRAW_COST)
		return

	_pending = _pick()
	_show_result(_pending)


## 等概率抽一名。以后要做稀有度/加权就改这里。
func _pick() -> Dictionary:
	return _pool[_rng.randi_range(0, _pool.size() - 1)]


func _show_result(entry: Dictionary) -> void:
	_result_portrait.texture = entry["texture"]
	_name_edit.text = _suggest_name()
	_result_panel.visible = true
	_update_draw_button()
	_set_hint("抽到了！给他起个名字吧")
	_name_edit.grab_focus()
	_name_edit.select_all()


# ---------------- 起名与入职 ----------------

func _on_confirm() -> void:
	if _pending.is_empty():
		return

	var display_name := _name_edit.text.strip_edges()
	if display_name.is_empty():
		_set_hint("名字不能是空的")
		_name_edit.grab_focus()
		return
	if StaffRegistry.has_name(display_name):
		_set_hint("已经有叫「%s」的员工了，换个名字" % display_name)
		_name_edit.grab_focus()
		return

	StaffRegistry.add_member(display_name, _pending["texture"], _pending["path"], _pending["look"])
	_pending = {}
	_result_panel.visible = false
	_update_draw_button()
	_set_hint("「%s」已入职，正在农场里出现" % display_name)


## 在起名框里按回车等同于点「确定录用」
func _on_name_submitted(_text: String) -> void:
	_on_confirm()


# ---------------- 小工具 ----------------

func _suggest_name() -> String:
	return "员工%d" % (StaffRegistry.count() + 1)


func _set_hint(text: String) -> void:
	_hint.text = text


func _update_draw_button() -> void:
	var waiting := not _pending.is_empty()
	_draw_button.disabled = waiting
	_draw_button.text = "先给抽到的角色起名" if waiting else "招聘一次 · %d 金币" % DRAW_COST


## 金币在 HUD 的 CoinCounter 节点上（coin_counter.tscn 里挂了 coin_counter 分组）
func _get_wallet() -> Node:
	var node := get_tree().get_first_node_in_group("coin_counter")
	if node == null or not node.has_method("spend_gold"):
		return null
	return node
