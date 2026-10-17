class_name NpcJob
extends Resource
## 岗位：NPC **没有指令时**干什么。每个岗位一个子类 + 一个 .tres，加岗位不用改 npc.gd。
##
## ── 岗位和指令的分工 ────────────────────────────────────────────
##   岗位（本类）  整局不变：「我是农夫 / 厨师 / 巡逻的」，决定闲着的时候干什么
##   指令          临时打断：「过来一下」，做完把岗位还回来
## NPC 每物理帧调 tick()，**有指令时不调**；指令结束会再调一次 start() 让岗位接着干。
##
## ── 怎么加一个岗位 ─────────────────────────────────────────────
##   1. 新建 .gd：class_name FarmerJob / extends NpcJob
##   2. 参数用 @export（会出现在检查器里）。**要碰场景里的东西就导出「组名字符串」**，
##      不要导出 Node —— Resource 会存成 .tres，绑死一个具体节点就再也复用不了了
##   3. FileSystem 面板右键 → 新建资源 → 选 FarmerJob → 存到 data/jobs/farmer.tres
##   4. 把那个 .tres 拖到 NPC 节点的 job 槽里
##
## ── 状态写在岗位上，但有个前提 ─────────────────────────────────
## npc.gd 在 _ready() 里对 job 做了 duplicate(true)，所以每个 NPC 手上都是**自己的一份副本**，
## 可以放心写 var _current_plot 这种状态字段。
## （没有那次复制的话，同一个 .tres 会被所有 NPC 共用 —— 5 个农夫会抢同一块田。）
##
## ── 想移动就调 npc.locomotion ──────────────────────────────────
##     npc.locomotion.move_to(世界坐标)     走过去；走完回到 on_arrived()
##     npc.locomotion.has_target()          手上有没有还没走完的路
## 别自己改 npc.global_position，也别自己碰导航 —— 让移动层统一处理碰撞、卡住、寻路。

## 上岗 / 指令走完回到岗位时调用。重置计时、重新找目标都写在这里
func start(_npc: Npc) -> void:
	pass


## 每物理帧调用（有指令时不调）。**这里只做决策**：挑目标、倒计时、喊 npc.locomotion.move_to()
func tick(_npc: Npc, _delta: float) -> void:
	pass


## 被指令打断时调用（NPC 被释放时不调）。放下手里的活：停计时、放开占用的东西
func stop(_npc: Npc) -> void:
	pass


## 本岗位派出去的移动到位了
func on_arrived(_npc: Npc) -> void:
	pass


## 本岗位派出去的移动走不到（被挡住超过移动层的 stuck_time）
func on_stuck(_npc: Npc) -> void:
	pass
