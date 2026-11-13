from pathlib import Path
from zipfile import ZipFile
from io import BytesIO
import re, shutil
from lxml import etree
from docx import Document
from docx.shared import Pt
from docx.oxml.ns import qn

root = Path('D:/MilkyFrogStead')
target = root / 'docs/学习笔记.docx'
backup = root / '.dsh-preview/learning_notes_before_data_structures.docx'
title = '当前游戏中的数据结构知识点总结'
with ZipFile(target) as z:
    original = z.read('word/document.xml')
if title.encode() in original:
    raise SystemExit('本节已经存在，停止重复追加')

d = Document()
def para(text, kind='body', page=False):
    p = d.add_paragraph()
    if kind == 'title': p.style = 'Title'
    elif kind == 'head': p.style = 'Heading 2'
    f = p.paragraph_format
    f.space_before = Pt(9 if kind == 'head' else 0)
    f.space_after = Pt(7)
    f.line_spacing = 1.25
    f.page_break_before = page
    f.widow_control = True
    if kind in ('title', 'head'): f.keep_with_next = True
    r = p.add_run(text)
    r.font.name = 'Consolas' if kind == 'code' else 'Microsoft YaHei'
    r._element.get_or_add_rPr().rFonts.set(qn('w:eastAsia'), 'Microsoft YaHei')
    r.font.size = Pt(20 if kind == 'title' else 13 if kind == 'head' else 9 if kind == 'code' else 10.5)
    from docx.shared import RGBColor
    r.font.color.rgb = RGBColor(0, 0, 0)
    r.bold = kind in ('head', 'title')
    return p

para(title, 'title', True)
para('记录日期：2026年11月8日\n问题：当前游戏进度中有哪些涉及数据结构的知识点？它们分别解决什么问题？')
para('当前项目已经使用数组、字典、集合式查重、栈、网格、树形节点和复合数据记录。最值得优先学习的实例是员工名册、NPC 同步、海岸洪水填充和草地分桶。数据结构决定数据怎样组织；遍历、排序、填充等算法则决定怎样处理这些数据。')
para('范围：以下位置均相对 D:/MilkyFrogStead/milky-frog-stead，行号对应本次整理时的代码。仓库菜单仍填充演示数据；不把真实库存、任务队列或寻路系统视为已完成。')
para('一 用记录表示一名员工', 'head')
para('StaffMember 把 id、display_name、portrait_path、look、status 等相关字段放进一个对象。它继承 RefCounted，不是场景节点。这是记录式数据建模：一名员工的数据作为整体传递，避免分别维护姓名数组、外观数组后发生下标错配。')
para('员工 id 表示身份，数组下标表示位置。删除或调整顺序可能改变下标，因此 NPC 映射使用 id。当前读档会处理非正数 id，但没有检查重复的正数 id；“唯一”仍需要业务逻辑维护。')
para('位置：scripts/data/staff_member.gd:1；scripts/core/staff_registry.gd:67。')
para('二 用数组保存有顺序的数据', 'head')
para('StaffRegistry.members 是 Array[StaffMember]，招聘时 append，新员工排在末尾；has_name 从头逐个比较姓名。数组适合“按招聘顺序显示所有人”，但按名字查找需要线性扫描。招聘池 _pool 则是 Array[Dictionary]：外层保存候选顺序，内层保存 path、texture、look。')
para('var members: Array[StaffMember] = []\nmembers.append(member)\n# members[0] 是第一名员工；id 不一定等于下标。', 'code')
para('仓库 _slots 是 40 个格子节点的一维数组，界面用 5 列排成 8 行。第 row 行、第 col 列的下标可理解为 row * 5 + col（均从 0 开始）；这是读取现有布局的公式，不是已经实现了二维库存。set_slot 已有越界检查。')
para('位置：scripts/core/staff_registry.gd:20、41；scripts/ui/menu_recruit.gd:28；scripts/ui/menu_warehouse.gd:18、29、47。')

para('三 用字典建立索引和模拟集合', 'head', True)
para('字典按键查值。staff_spawner.gd 的 _spawned 保存“员工 id → 场景 NPC”。它把逻辑身份与当前节点连接起来，避免每次找某个员工时都扫描场景里的所有 NPC。相比数组按位置访问，字典适合按稳定身份访问。')
para('_spawned[member.id] = npc\nvar existing = _spawned.get(member.id)\nalive[member.id] = true', 'code')
para('_sync 的临时字典 alive 只关心某个 id 是否存在，值统一为 true，因此在这里承担集合的作用。先遍历名册标记仍然存在的员工，并补建缺失 NPC；再遍历已生成 id，把不在 alive 中的 NPC 移除。这相当于比较两组身份的差集。')
para('假设名册 id 为 {1, 3}，场景 id 为 {1, 2}：保留并更新 1，创建 3，移除 2。名册有 n 人、已生成节点有 m 个时，在字典平均查找成本为常数的假设下，索引和比较部分约为 O(n+m)，不包含节点创建、释放和渲染的成本。')
para('易错点：代码遍历 _spawned.keys() 得到的键数组，再 erase 原字典中的条目。不要把这与直接遍历正在修改的容器混淆。字典仍可能保留失效节点的引用，所以查到节点后还要 is_instance_valid。')
para('位置：scripts/staff/staff_spawner.gd:19、28。')
para('四 用字典做缓存', 'head')
para('StaffLooks._cache 保存“look → SpriteFrames”。第一次请求某种外观时加载图片并拼动画，之后直接返回缓存。Sidebar._menus 保存“按钮 → 已创建菜单”，第一次打开才实例化。这都是用额外内存换取重复操作时的较少计算。')
para('if _cache.has(look):\n    return _cache[look]\n# 缓存未命中时构建 frames\n_cache[look] = frames', 'code')
para('缓存是字典的用途，不是另一种容器。共享资源也意味着共享修改：若直接修改缓存里的 SpriteFrames，使用它的多个员工可能一起变化。未来若需要个人独立动画，应考虑复制资源。当前外观缓存没有淘汰逻辑，适合外观种类有限的情况。')
para('位置：scripts/staff/staff_looks.gd:32、41；scripts/ui/sidebar.gd:30、109。')

para('五 二维网格怎样放进一维数组', 'head', True)
para('海岸遮罩使用 PackedByteArray，分别记录墙 wall、外部区域 outside、陆地 land 和崖壁 cliff。宽 w、高 h 的网格分配 w*h 个元素，按行连续存储。每格用 0 或 1 表示一种状态；它是字节数组，并不是每格只占一个 bit 的位图。')
para('i = y * w + x\nx = i % w\ny = floor(i / w)\n左 i-1    右 i+1    上 i-w    下 i+w', 'code')
para('例如宽度为 5，坐标 (2, 3) 对应下标 17。下标加减之前必须检查坐标边界：右边界的 i+1 虽可能仍在数组范围内，却已经是下一行的第一格，不是右邻居。高度和距离使用 PackedFloat32Array；连续数值适合这种专用数组。')
para('位置：scripts/world/island_terrain.gd:145；scripts/world/terrain_field.gd:128、293。')
para('六 栈与洪水填充识别海岸内外', 'head')
para('_load_shore_mask 用 Array[int] 实现栈。append 放到尾部，pop_back 从尾部取出，体现后进先出。把图像四条边的格子压栈，不断取一个格子：越界、已经访问或是墙就跳过；否则标记 outside，并把上下左右邻居压栈。这是使用显式栈的深度优先洪水填充。')
para('边缘种子 → 弹出格子 → 检查墙和访问标记 → 标记外部 → 压入邻格 → 重复直到栈空', 'code')
para('可把每个格子看作图的顶点、相邻关系看作边；代码通过坐标计算邻居，所以无需单独建立邻接表。outside 同时承担访问标记，防止相邻格子彼此反复扩展。显式栈还避免了递归函数调用层数过深。')
para('设 N=w*h，固定四邻域下，填充的时间和额外空间上界均为 O(N)。当前在弹出后标记，一个格子可能重复入栈，但已访问检查会跳过重复扩展。')
para('关键细节：最终代码是 outside[i]==0 就设为 land，因此墙线本身也包含在陆地掩码中；源码注释“既不是墙、也没被灌到”比实际条件更严格。岸线出现缺口时，外部填充可能进入岛内，导致陆地识别异常。')
para('位置：scripts/world/island_terrain.gd:130、159、186。当前这里不是广度优先搜索，也没有用队列求最短路径。')

para('七 空间分桶与区块缓存', 'head', True)
para('草地把每株草的位置换算成区块坐标，以 Vector2i 为字典键，每个键对应该区块的草数组。数组里的一条记录是 [pos, col, size]。随后按桶创建 MultiMesh，集中提交同块内的草，而不是每株草都建独立节点。')
para('桶坐标 = floor((位置 - 区域起点) / 区块边长)\nbuckets[桶坐标].append([pos, col, size])', 'code')
para('这是均匀网格分桶，不是四叉树。负坐标要向下取整，否则靠近零点的负坐标可能被划到错误区块。数组记录紧凑，但 [0]、[1]、[2] 的含义依赖约定；若字段继续增加，可考虑命名记录，降低读错下标的风险。')
para('地形 _chunks 保存“区块坐标 → PackedFloat32Array 高度数据”。首次采样一个区块时计算高度，之后复用；_evict_chunks 在缓存规模达到阈值后按当前区域清理远处区块。这是按空间范围清理，并不是按最近使用顺序淘汰的 LRU。')
para('IslandTerrain 继承 TerrainField，当前农场的 level.tscn 使用 IslandTerrain。因此基类的区块数据和距离场机制也与农场有关，不能仅因 water_proto.tscn 直接引用 TerrainField 就把整个基类当成未使用的原型。')
para('位置：scripts/world/grass_field_2d.gd:221、239、437；scripts/world/terrain_field.gd:128、360；scripts/world/island_terrain.gd:3。')
para('八 在数组上做排序与邻域计算', 'head')
para('草地 _resolve_pushers 收集踩草对象，去重后在对象超过 4 个且存在相机时，按到镜头中心的距离平方排序。_push_update 用 PackedVector4Array 传入最多 4 个槽位，每项的四个分量表示 x、y、半径、强度；鼠标互动启用时也会占一个槽位。')
para('只用距离比较时，距离平方保持非负距离的大小关系，可以省去开平方。注意这里只是按距离选取优先对象，并没有进行寻路；out.has(n) 的数组查重还需要扫描，不能只计算最后的排序成本。')
para('地形 _chamfer 用浮点数组存每格到目标类别的近似距离，正反扫描时读取邻格已有结果，再取更小值。它属于距离变换算法，底层仍是网格数组；当前权重是直线 1、对角约 √2，并非严格的 3 与 4，也不是任意方向上的精确欧氏距离。此处补充数据组织，水面视觉用途见已有水体笔记。')
para('位置：scripts/world/grass_field_2d.gd:317、356；scripts/world/terrain_field.gd:293。')

para('九 场景树与存档的层次结构', 'head', True)
para('场景树是真正的父子层级。例如员工状态列表下有多行，每行包含立绘和姓名状态区域。add_child 建立父子关系，get_children 得到直接子节点。_refresh 先 remove_child 把旧行立即移出，再 queue_free 延迟释放，随后添加新行；逻辑移除与内存释放不是同一时刻。')
para('位置：scripts/ui/menu_npc_status.gd:20、35。节点分组可用于跨层级收集对象，但分组关系不是父子关系。小鸡 _find_food_spot 遍历食物组并记录当前最近点，是线性最小值搜索；没有使用堆或空间树。')
para('位置：scripts/chicken.gd:318。State 枚举与分支构成状态机逻辑；状态机可以画成转移图，但这不代表代码已经使用邻接表存图。food_queue_spread 表示食物点附近的分散范围，不是 FIFO 队列。')
para('存档是复合数据结构：顶层 Dictionary 下有金币、版本、时间，staff 字段是数组，每个员工是字典，clock 也是字典。JSON 是这些数据的文本表示形式，不是把场景树原样写入磁盘。')
para('{"gold": 500,\n "staff": [{"id": 1, "display_name": "青蛙一号"}],\n "clock": {"day": 1, "hour": 9.0}}', 'code')
para('上面只是结构示意，省略了 version 等必需或实际使用字段，不能直接当完整存档。资源保存路径，读档再加载；员工记录重建后，NPC 再由出现器生成。这里只补充数组与字典的嵌套关系，时间跨场景恢复详见已有存档章节。')
para('位置：scripts/core/save_manager.gd:165；scripts/core/staff_registry.gd:53、67。')
para('十 用复杂度判断何时需要优化', 'head')
para('令 n 为记录数：数组按下标访问通常为 O(1)，尾部追加均摊 O(1)，逐个查找为 O(n)，中间删除通常需要移动后续元素。哈希字典查找通常平均 O(1)，最坏情况不保证常数。大 O 描述随规模增长的趋势，不等于实测耗时。')
para('当前员工规模较小时，姓名查重直接扫描容易理解。若以后大量招聘且频繁查重，可以在保留 members 顺序的同时增加姓名索引；但新增、改名、删除、读档都必须同步维护。数组与字典可以配合使用，不必二选一。')
para('学习练习与参考答案', 'head')
para('① 名册删掉第一人后，第二人的 id 应不应该减一？不应该，身份与位置应分开。② 为什么填充必须有 outside？它记录已访问格子，阻止重复扩展。③ 把栈改成 FIFO 队列后是什么遍历？广度优先遍历；若求最短步数还需记录距离。④ 缓存和存档有什么区别？缓存减少重复计算，存档负责跨进程恢复；两者都可以使用字典。')
para('推荐阅读顺序：StaffMember → StaffRegistry → StaffSpawner → IslandTerrain 的填充 → GrassField2D 的分桶。先手动跟踪 3 个员工和一个 5×5 网格，再理解大地图上的同类操作。')

# Only insert new body XML. Preserve every original package entry and original body byte.
fragment = b''.join(etree.tostring(e, encoding='utf-8') for e in d.element.body if e.tag != qn('w:sectPr'))
position = original.rfind(b'<w:sectPr')
if position < 0: position = original.rfind(b'</w:body>')
assert position > 0
updated = original[:position] + fragment + original[position:]
etree.fromstring(updated)
shutil.copy2(target, backup)
temp = target.with_suffix('.tmp.docx')
with ZipFile(target) as src, ZipFile(temp, 'w') as dest:
    for info in src.infolist():
        dest.writestr(info, updated if info.filename == 'word/document.xml' else src.read(info.filename))
with ZipFile(backup) as old, ZipFile(temp) as new:
    assert old.namelist() == new.namelist()
    for name in old.namelist():
        if name != 'word/document.xml': assert old.read(name) == new.read(name)
    assert new.read('word/document.xml').replace(fragment, b'', 1) == original
temp.replace(target)
Document(target)
print('追加完成；原有正文和所有其他压缩包条目保持不变；DOCX 可读取。新增段落：', len(d.paragraphs))
print(target)
