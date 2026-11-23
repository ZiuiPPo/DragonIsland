extends VBoxContainer
## 员工状态菜单。
##
## 不写死名单：内容全部来自 StaffRegistry.members，招聘菜单加了人这里会立刻刷新。
## 每行 = 立绘 + 名字 + 工作状态（招聘进来默认「待定」，以后分配岗位再改）。

## 一行里立绘的边长
const PORTRAIT_SIZE: float = 44.0

@onready var _list: VBoxContainer = %List
@onready var _scroll: ScrollContainer = %Scroll
@onready var _empty_label: Label = %EmptyLabel


var _readouts: Dictionary = {}

func _ready() -> void:
	StaffRegistry.staff_changed.connect(_refresh)
	StaffCare.changed.connect(_update_readouts)
	_refresh()


func _refresh() -> void:
	_readouts.clear()
	# 先把旧行摘掉再建新的（remove_child 立即生效，queue_free 只是延迟释放）
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	var count := StaffRegistry.count()
	_empty_label.visible = count == 0
	_scroll.visible = count > 0

	for member in StaffRegistry.members:
		_list.add_child(_make_row(member))


## 一行的节点在代码里拼：HBox[ 立绘 | VBox(名字 / 状态) ]
func _make_row(member: StaffMember) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = member.portrait
	row.add_child(portrait)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	info.add_theme_constant_override("separation", 2)

	var name_label := Label.new()
	name_label.text = member.display_name
	name_label.add_theme_font_size_override("font_size", 17)
	info.add_child(name_label)

	var status_label := Label.new()
	status_label.text = ("悲伤 · 体力耗尽" if member.satiety <= 0 else ("工作中" if member.is_working else ("闲置 · 大笑" if member.is_laughing else "闲置 · 漫游"))) + "\n饱腹值 %d/100" % roundi(member.satiety)
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color(0.72, 0.33, 0.2, 1))
	info.add_child(status_label)

	var feed := Button.new()
	feed.text = "喂食"
	feed.custom_minimum_size = Vector2(58.0, 34.0)
	feed.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	feed.disabled = member.satiety >= StaffMember.MAX_SATIETY or StaffCare.best_food().is_empty()
	feed.pressed.connect(func(): StaffCare.feed_with_available(member.id))
	row.add_child(info)
	row.add_child(feed)
	_readouts[member.id] = {"member": member, "status": status_label, "feed": feed}
	return row

func _update_readouts() -> void:
	for row in _readouts.values():
		var member: StaffMember = row.member
		row.status.text = ("悲伤 · 体力耗尽" if member.satiety <= 0 else ("工作中" if member.is_working else ("闲置 · 大笑" if member.is_laughing else "闲置 · 漫游"))) + "\n饱腹值 %d/100" % roundi(member.satiety)
		row.feed.disabled = member.satiety >= StaffMember.MAX_SATIETY or StaffCare.best_food().is_empty()