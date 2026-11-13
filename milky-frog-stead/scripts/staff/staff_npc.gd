class_name StaffNpc
extends Npc
## 一名已招聘的员工：在 Npc 的「漫游」行为上，加了外观和头顶名字。
##
## 外观不单独做场景：look 只决定加载哪一对序列帧（见 StaffLooks），
## 所以 5 种颜色共用这一份 staff_npc.tscn。
##
## 用法（StaffSpawner 里）：
##   var npc := STAFF_SCENE.instantiate()
##   npc.configure(member, spawn_position)   # 必须在 add_child 之前
##   add_child(npc)
##
## configure 要在 add_child 之前调：Npc._ready() 会把当时的位置记成漫游中心，
## 晚了的话员工会从场景原点开始算活动范围。

## 用 preload 而不是全局类名：新脚本的 class_name 要等编辑器扫过才注册，
## 先 preload 能保证命令行 / 首次运行也立刻可用。
const Looks := preload("res://scripts/staff/staff_looks.gd")

## 外观编号，对应 assets/sprites/npcs/staff/<look>_idle_move_*.png
@export var look: String = "npc1"

@onready var _name_label: Label = $NameLabel

var _display_name: String = ""
var _member: StaffMember
var _care_view: Control


## 填入名册里的员工资料并摆好出生位置。在 add_child 之前调用。
func configure(member: StaffMember, spawn_position: Vector2) -> void:
	_member = member
	look = member.look if not member.look.is_empty() else _look_from_portrait(member.portrait_path)
	_display_name = member.display_name
	position = spawn_position


func _ready() -> void:
	var frames := Looks.frames_for(look)
	if frames == null and look != "npc1":
		push_warning("[员工] 外观「%s」没有序列帧，先用 npc1 顶上" % look)
		frames = Looks.frames_for("npc1")
	if frames != null:
		($AnimatedSprite2D as AnimatedSprite2D).sprite_frames = frames

	_apply_name()

	# 帧要先装好，Npc._ready() 里的 _check_animations() 才能通过
	super._ready()
	_care_view = preload("res://scripts/staff/staff_care_view.gd").new()
	add_child(_care_view)
	_care_view.bind_member(_member)


## 改名字（名册改名后由 Spawner 调）
func set_display_name(value: String) -> void:
	_display_name = value
	_apply_name()


func _apply_name() -> void:
	if _name_label == null:
		return
	_name_label.text = _display_name
	_name_label.visible = not _display_name.is_empty()


## 兼容旧数据：没存 look 时，从立绘路径推（res://assets/icons/recruit/npc3.png → npc3）
func _look_from_portrait(portrait_path: String) -> String:
	return portrait_path.get_file().get_basename() if not portrait_path.is_empty() else "npc1"

func _physics_process(delta: float) -> void:
	if _care_view != null and _care_view.blocks_movement(delta, _facing_right):
		velocity = Vector2.ZERO
		locomotion.stop()
		return
	super._physics_process(delta)

## 名册读档后可能创建新的 StaffMember 实例，更新绑定而非保留旧引用。
func update_member(member: StaffMember) -> void:
	_member = member
	set_display_name(member.display_name)
	var next_look := member.look if not member.look.is_empty() else _look_from_portrait(member.portrait_path)
	if next_look != look:
		look = next_look
		var frames := Looks.frames_for(look)
		if frames != null:
			animated_sprite_2d.sprite_frames = frames
	if _care_view != null:
		_care_view.bind_member(member)
