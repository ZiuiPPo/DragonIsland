extends Node2D
## 员工出现器：名册里有人就生成对应的员工 NPC，名册清空就把人收走。
##
## 挂在农场的场景里，位置就是员工的「出生中心」。招聘菜单只负责往
## StaffRegistry 里加人，这里监听 staff_changed 自动生成——两边不用互相认识。
##
## 名册是 Autoload，切场景不会丢；所以农场重载时这里会把已有员工重新放一遍。
## 每名员工的漫游中心按 id 散在一个小圆环上；具体出生点仍由 Npc.random_spawn
## 在中心附近随机，所以不会五个人挤在同一点。

const STAFF_SCENE: PackedScene = preload("res://scenes/npc/staff_npc.tscn")

## 第一个员工的出生半径
@export var spawn_radius: float = 30.0
## 每多一个人，半径往外挪多少（按 id % 3 分三圈）
@export var ring_gap: float = 22.0

## member.id -> StaffNpc
var _spawned: Dictionary = {}


func _ready() -> void:
	StaffRegistry.staff_changed.connect(_sync)
	_sync.call_deferred()


## 名册和场景对齐：缺的人生出来，多出来的人收走，改名的人更新头顶文字
func _sync() -> void:
	print("[spawner] _sync 名册 %d 人，已生成 %d 个，父节点 visible=%s" % [
		StaffRegistry.members.size(), _spawned.size(), visible])
	var alive := {}
	for member in StaffRegistry.members:
		alive[member.id] = true
		var existing: Variant = _spawned.get(member.id)
		if existing != null and is_instance_valid(existing):
			existing.call("update_member", member)
			continue
		_spawn(member)

	for id in _spawned.keys():
		if alive.has(id):
			continue
		var npc: Variant = _spawned[id]
		if is_instance_valid(npc):
			npc.queue_free()
		_spawned.erase(id)


func _spawn(member: StaffMember) -> void:
	var npc: Node = STAFF_SCENE.instantiate()
	if npc == null:
		push_error("[员工出现器] staff_npc.tscn 实例化失败")
		return

	# 黄金角散点：连续生成的人会绕圈排开，不会全挤在朝右的方向
	var angle := float(member.id) * 2.39996323
	var radius := spawn_radius + ring_gap * float(member.id % 3)
	npc.call("configure", member, Vector2(cos(angle), sin(angle)) * radius)
	add_child(npc)
	_spawned[member.id] = npc
	print("[spawner] 生成 %s id=%d 位置=%s 可见=%s" % [
		member.display_name, member.id,
		(npc as Node2D).global_position, (npc as CanvasItem).visible])
