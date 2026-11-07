extends Node2D
## 农场场景入口。
##
## 主菜单只负责准备数据（SaveManager.pending_gold / StaffRegistry），
## 这里负责把数据落到场景节点上，并启动这一局的自动存档。
##
## 场景里 CoinCounter 已经在 coin_counter.tscn 中挂了 "coin_counter" 组，
## 所以不写死节点路径，换 HUD 布局也不会影响读档。

func _ready() -> void:
	_apply_pending_gold()
	_bind_autosave()
	SaveManager.begin_session()


## 新游戏 / 读档时，主菜单会把金币放在 SaveManager 里带过来。
func _apply_pending_gold() -> void:
	var gold := SaveManager.consume_pending_gold()
	if gold < 0:
		return

	var counter := get_tree().get_first_node_in_group("coin_counter")
	if counter == null or not counter.has_method("set_gold"):
		push_warning("农场里找不到 CoinCounter，读档金币没有应用")
		return
	counter.call("set_gold", gold, false)


## 金币变化时通知 SaveManager 延迟自动存档。
func _bind_autosave() -> void:
	var counter := get_tree().get_first_node_in_group("coin_counter")
	if counter == null:
		return
	if not counter.has_signal("gold_changed"):
		return
	if not counter.gold_changed.is_connected(SaveManager.note_gold):
		counter.gold_changed.connect(SaveManager.note_gold)
