# -*- coding: utf-8 -*-
"""生成 Milky Frog Stead 数据结构课程实验进度汇报 Word 文档。"""

import datetime
from docx import Document
from docx.shared import Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

OUT = r"D:\MilkyFrogStead\docs\MilkyFrogStead-项目进度汇报.docx"

# ---------------------------------------------------------------- 样式工具

ACCENT = RGBColor(0x1F, 0x3B, 0x57)
BODY_EA = "宋体"
HEAD_EA = "黑体"
MONO = "Consolas"


def style_run(run, ascii_font="Times New Roman", ea_font=BODY_EA, size=None,
              bold=None, color=None, italic=None):
    run.font.name = ascii_font
    rPr = run._element.get_or_add_rPr()
    rFonts = rPr.get_or_add_rFonts()
    rFonts.set(qn("w:eastAsia"), ea_font)
    if size is not None:
        run.font.size = Pt(size)
    if bold is not None:
        run.font.bold = bold
    if italic is not None:
        run.font.italic = italic
    if color is not None:
        run.font.color.rgb = color


def tune_styles(doc):
    normal = doc.styles["Normal"]
    normal.font.name = "Times New Roman"
    normal.font.size = Pt(10.5)
    normal.element.rPr.rFonts.set(qn("w:eastAsia"), BODY_EA)
    normal.paragraph_format.line_spacing = 1.4
    normal.paragraph_format.space_after = Pt(4)

    for name, size in (("Heading 1", 15), ("Heading 2", 12.5), ("Heading 3", 11)):
        st = doc.styles[name]
        st.font.name = "Times New Roman"
        st.font.size = Pt(size)
        st.font.bold = True
        st.font.color.rgb = ACCENT
        st.element.rPr.rFonts.set(qn("w:eastAsia"), HEAD_EA)
        st.paragraph_format.space_before = Pt(12 if name == "Heading 1" else 8)
        st.paragraph_format.space_after = Pt(6)


def shade(cell, fill):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), fill)
    tcPr.append(shd)


def repeat_header(row):
    trPr = row._tr.get_or_add_trPr()
    el = OxmlElement("w:tblHeader")
    el.set(qn("w:val"), "true")
    trPr.append(el)


def add_page_number(doc):
    p = doc.sections[0].footer.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run()
    style_run(run, size=9)
    for kind, text in (("begin", None), (None, "PAGE"), ("end", None)):
        if kind:
            el = OxmlElement("w:fldChar")
            el.set(qn("w:fldCharType"), kind)
        else:
            el = OxmlElement("w:instrText")
            el.set(qn("xml:space"), "preserve")
            el.text = text
        run._r.append(el)


def para(doc, text, size=10.5, bold=False, indent=0.0, ea=BODY_EA,
         ascii_font="Times New Roman", space_after=4, align=None):
    p = doc.add_paragraph()
    if indent:
        p.paragraph_format.left_indent = Cm(indent)
    p.paragraph_format.space_after = Pt(space_after)
    if align is not None:
        p.alignment = align
    style_run(p.add_run(text), ascii_font=ascii_font, ea_font=ea, size=size, bold=bold)
    return p


def bullet(doc, text, level=0):
    p = doc.add_paragraph(style="List Bullet")
    p.paragraph_format.left_indent = Cm(0.75 + 0.6 * level)
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.line_spacing = 1.3
    style_run(p.add_run(text), size=10.5)
    return p


def code_block(doc, lines):
    for line in lines:
        p = doc.add_paragraph()
        p.paragraph_format.left_indent = Cm(0.6)
        p.paragraph_format.space_after = Pt(0)
        p.paragraph_format.line_spacing = 1.05
        style_run(p.add_run(line if line else " "), ascii_font=MONO,
                  ea_font=MONO, size=9)


def table(doc, headers, rows, widths=None, font_size=9.5, caption=None):
    if caption:
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_after = Pt(2)
        p.paragraph_format.space_before = Pt(6)
        style_run(p.add_run(caption), size=9, bold=True, ea_font=HEAD_EA)

    t = doc.add_table(rows=1, cols=len(headers))
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False

    hdr = t.rows[0]
    for i, h in enumerate(headers):
        cell = hdr.cells[i]
        cell.text = ""
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_after = Pt(1)
        p.paragraph_format.line_spacing = 1.15
        style_run(p.add_run(h), size=font_size, bold=True, ea_font=HEAD_EA)
        shade(cell, "DCE6F1")
    repeat_header(hdr)

    for row_data in rows:
        cells = t.add_row().cells
        for i, val in enumerate(row_data):
            cells[i].text = ""
            p = cells[i].paragraphs[0]
            p.paragraph_format.space_after = Pt(1)
            p.paragraph_format.line_spacing = 1.15
            style_run(p.add_run(str(val)), size=font_size)

    if widths:
        for r in t.rows:
            for i, w in enumerate(widths):
                r.cells[i].width = Cm(w)

    doc.add_paragraph().paragraph_format.space_after = Pt(2)
    return t


# ---------------------------------------------------------------- 文档

doc = Document()
tune_styles(doc)
sec = doc.sections[0]
sec.page_width = Cm(21.0)      # A4
sec.page_height = Cm(29.7)
sec.top_margin = Cm(2.4)
sec.bottom_margin = Cm(2.2)
sec.left_margin = Cm(2.6)
sec.right_margin = Cm(2.4)
add_page_number(doc)

# ---- 封面标题
title = doc.add_paragraph()
title.alignment = WD_ALIGN_PARAGRAPH.CENTER
title.paragraph_format.space_after = Pt(2)
style_run(title.add_run("Milky Frog Stead 项目进度汇报"),
          ea_font="微软雅黑", size=20, bold=True, color=ACCENT)

sub = doc.add_paragraph()
sub.alignment = WD_ALIGN_PARAGRAPH.CENTER
sub.paragraph_format.space_after = Pt(10)
style_run(sub.add_run("数据结构课程实验 · 小组阶段汇报"),
          ea_font="微软雅黑", size=11.5, color=RGBColor(0x55, 0x55, 0x55))

table(doc, ["项目", "内容"], [
    ["项目名称", "Milky Frog Stead（放置经营类农场 + 餐厅模拟游戏）"],
    ["课程名称", "数据结构课程实验"],
    ["开发引擎", "Godot 4.7（Forward+ / D3D12）"],
    ["开发语言", "GDScript"],
    ["版本控制", "Git / Gitee，主分支 master，采用分支 + Pull Request 协作"],
    ["小组人数", "4 人"],
    ["汇报日期", datetime.date.today().strftime("%Y 年 %m 月 %d 日")],
], widths=[3.2, 12.6], font_size=10)

# ---- 一
doc.add_heading("一、项目概况", level=1)
para(doc, "本项目是一款以“放置经营”为核心的农场 + 餐厅模拟游戏。玩家扮演农庄与餐厅的经营者，"
          "通过安排员工岗位、配置每日餐厅菜单、决定资金投向来完成经营；"
          "角色的一切行为（耕种、投喂、钓鱼、做菜、上菜、结账）全部由程序自动调度完成。")
para(doc, "选择这一题材作为数据结构课程实验的载体，主要原因是它天然覆盖了课程中的多类经典结构："
          "库存需要哈希表、顾客订单需要队列、地图寻路需要图与最短路径算法、"
          "员工行为需要状态机、存档需要树形结构的序列化。"
          "相比增删改查类的练习题目，本项目的各类结构都有真实的性能动机与业务约束，"
          "便于我们观察“结构选错会带来什么后果”。")

doc.add_heading("二、玩法设计与系统划分", level=2)
para(doc, "游戏的信息结构围绕三条循环展开：", space_after=2)
bullet(doc, "决策层：玩家仅执行四类操作——分配员工岗位、配置餐厅菜单、消费资金（买种子 / 招员工 / 扩地扩座）、点击“开始营业”。")
bullet(doc, "单日循环：早晨结算农场产出 → 员工自动上工 → 配置菜单 → 营业时段 → 打烊结算当日净利润。")
bullet(doc, "成长循环：净利润用于招募员工与扩展农场 / 餐厅，提升产能上限，形成正反馈。")
para(doc, "资源链路的设计要点在于“闭环”：农作物既是餐厅食材，也是饲料；"
          "饲料驱动畜牧产出；钓鱼区提供高价值食材。三条产线互相咬合，而非各自独立产钱。", space_after=6)

table(doc, ["区域 / 系统", "主要职责", "产出物"], [
    ["种地区域", "地块播种、按天生长、每日收获一次", "萝卜、生菜、小麦、番茄"],
    ["畜牧区域", "投喂饲料、每日产出、无人照料则减产", "鸡蛋、牛奶"],
    ["钓鱼区域", "渔获自动积累，员工收取", "鱼"],
    ["餐厅系统", "菜单配置、顾客生成、做菜、上菜、结账", "蛙币（营收）"],
    ["员工系统", "岗位分配、自主寻路、循环工作、体力恢复", "劳动力（驱动以上所有系统）"],
], widths=[3.4, 7.6, 4.8], caption="表 1  系统划分与职责")

# ---- 三
doc.add_heading("三、数据结构与算法设计（课程重点）", level=1)
para(doc, "本章是本次实验的核心设计内容。我们按“业务场景 → 结构选型 → 复杂度 → 取舍理由”"
          "四个维度逐项论证，并在最后给出与课程知识点的对应关系。")

doc.add_heading("3.1 结构选型总览", level=2)
table(doc, ["业务场景", "采用的数据结构", "关键操作", "时间复杂度"], [
    ["物品库存", "哈希表 Dictionary（键为物品 ID 字符串）", "增、删、查、改", "平均 O(1)"],
    ["顾客订单", "队列（FIFO），数组实现", "入队 / 出队", "入队 O(1)，数组首删 O(n)"],
    ["员工行为", "有限状态机（枚举 + 分支匹配）", "状态转移", "O(1)"],
    ["岗位分配", "一对一映射（对象引用 + 空闲判定）", "分配 / 释放", "O(1)"],
    ["员工与岗位集合", "动态数组", "遍历、按条件筛选", "O(n)"],
    ["自主寻路", "图（导航网格）+ A* 最短路", "路径求解", "O(E log V)"],
    ["日循环流程", "阶段状态机", "阶段切换", "O(1)"],
    ["当日收支结算", "分类累加器（枚举为键的哈希表）", "累加 / 汇总", "O(1) 累加，O(k) 汇总"],
    ["系统间通信", "观察者模式（信号总线）", "发布 / 订阅", "广播 O(m)，m 为监听者数"],
    ["菜单可行性判定", "多重集合包含关系", "配方校验", "O(k·m)"],
    ["作物生长", "按天推进的计数状态机", "每日推进", "O(1)"],
    ["存档", "树形结构序列化（嵌套字典 / 数组）", "序列化 / 反序列化", "O(n)"],
], widths=[3.0, 5.4, 3.4, 4.0], caption="表 2  各子系统数据结构选型与复杂度")

doc.add_heading("3.2 库存系统：哈希表", level=2)
para(doc, "库存以“物品 ID → 数量”的哈希表存储。选择哈希表而非线性表，"
          "原因在于库存的访问模式是高频的按键查询：做菜时要校验配方中每种食材是否充足，"
          "营业时段内每道菜都会触发一次多键查询。若用数组线性查找，单次查询为 O(n)，"
          "订单量增大后耗时随物品种类线性增长；哈希表将此降为平均 O(1)。", space_after=4)
para(doc, "此外我们实现了“先全部校验、再统一扣除”的两趟处理，避免出现“料扣了一半却做不出菜”的中间状态，"
          "这是数据结构操作原子性的一次实践。", space_after=4)
para(doc, "需要说明的是，哈希表平均 O(1) 建立在散列均匀的假设上；"
          "最坏情况下所有键冲突会退化为 O(n)。本项目的物品 ID 为语义化字符串，"
          "数量在数十量级，冲突概率极低，因此不额外设计自定义散列函数。")

doc.add_heading("3.3 订单系统：队列与 FIFO 语义", level=2)
para(doc, "顾客下单后产生的订单必须按“先到先服务”处理，这正是队列的典型语义："
          "厨房从队首取单，新订单从队尾入队。整个订单生命周期被划分为"
          "“待处理 → 制作中 → 已出菜 → 已上菜”四个阶段，用两个队列衔接："
          "待处理队列供厨房消费，已出菜队列供服务员消费。", space_after=4)
para(doc, "这里有一个我们主动记录的性能问题：数组实现的队列在队首删除元素时需要整体前移，"
          "pop_front 的复杂度为 O(n)。在当前 Demo 的订单规模（同时不超过 20 单）下可以接受，"
          "但若订单规模继续增大，应改用环形缓冲区，或用“头指针 + 不清空元素”的方式把首删降为 O(1)。"
          "这是我们为后续优化预留的改进点。", space_after=4)

doc.add_heading("3.4 员工行为：有限状态机", level=2)
para(doc, "每名员工的行为被抽象为四个状态：待命、前往岗位、工作中、休息。"
          "状态转移由明确的条件触发（是否有岗位、是否到达目标、体力是否耗尽），"
          "构成一个确定性的有限状态机。选择状态机而非行为树的原因是其状态数有限、"
          "转移条件单一，单次转移为 O(1)，且便于调试时定位“员工卡在哪个状态”。", space_after=4)
code_block(doc, [
    "  待命 IDLE ──分配到岗位──> 前往岗位 SEEK_WORK",
    "     ▲                            │ 到达岗位",
    "     │                            ▼",
    "     └──体力恢复完成──── 休息 REST <──体力耗尽── 工作中 WORK",
    "                                   │",
    "                                   └── 循环执行岗位工作",
])

doc.add_heading("3.5 寻路：图与 A* 最短路", level=2)
para(doc, "农场与餐厅地图被离散为导航网格，每个可行走区域视为图的顶点，"
          "相邻区域之间构成边。员工从当前位置前往岗位目标点时，"
          "由 A* 算法在导航网格上求解最短路径。选择 A* 而非广度优先搜索，"
          "是因为地图中障碍物密集、起点与终点距离较远，"
          "A* 借助启发式函数（到目标的欧氏距离）能显著减少扩展的节点数，"
          "在保证最优解的前提下降低实际运行开销。", space_after=4)
para(doc, "由于导航网格的构建与烘焙需要与背景底图精确对齐，"
          "我们为该模块准备了降级方案：若网格烘焙调参耗时超出预期，"
          "则暂时改用网格化的 A* 寻路加路点直连，保证功能先跑通再优化手感。")

doc.add_heading("3.6 日循环与事件通信", level=2)
para(doc, "游戏以“天”为最小决策单位，日循环用阶段状态机驱动，"
          "依次为早晨、营业、打烊三个阶段。农作物生长、动物产出等结算逻辑"
          "统一挂在“新的一天开始”事件上，避免各处分散判断日期。", space_after=4)
para(doc, "系统间通信采用观察者模式：设置一个全局信号总线作为发布者，"
          "各子系统按需订阅。这样农场系统与餐厅系统之间不存在直接依赖，"
          "两组人可以并行开发，只需遵守事先约定的信号契约。"
          "广播一次的代价为 O(m)，m 为监听者数量，在本项目的规模下可忽略。", space_after=4)

doc.add_heading("3.7 存档：树形结构的序列化", level=2)
para(doc, "存档采用“只存数据、不存场景对象”的策略：将运行状态扁平化为嵌套的字典与数组，"
          "再序列化为 JSON 文本。这样避免了在存档中写入对象引用或节点路径"
          "（一旦场景结构调整，旧存档即失效），"
          "同时 JSON 的嵌套结构本身对应一棵树，便于人工检查与版本兼容判断。"
          "序列化与反序列化的复杂度均为 O(n)，n 为需要保存的数据项数量。")

doc.add_heading("3.8 与课程知识点的对应关系", level=2)
table(doc, ["课程知识点", "在本项目中的落地位置"], [
    ["线性表", "员工列表、岗位列表、库存清单"],
    ["栈与队列", "顾客订单的 FIFO 队列、已出菜队列"],
    ["哈希表", "物品库存、当日收支的分类累加器"],
    ["树", "Godot 场景树、JSON 存档的嵌套结构"],
    ["图", "地图导航网格、员工寻路"],
    ["图的遍历与最短路", "A* 寻路算法"],
    ["查找与排序", "菜单候选按毛利排序、空闲岗位查找"],
    ["算法设计（状态机 / 贪心）", "日循环阶段机、员工行为状态机"],
], widths=[4.6, 11.2], caption="表 3  课程知识点与项目落点对应表")

# ---- 四
doc.add_heading("四、已完成工作", level=1)

doc.add_heading("4.1 文件与目录管理", level=2)
para(doc, "工程已完成目录骨架搭建，按“资源类型 + 功能模块”两个维度组织，"
          "使美术、场景、脚本、数据四类内容互不混杂，便于多人并行开发时减少冲突。"
          "工程位于仓库的 milky-frog-stead/ 子目录，与文档分离。", space_after=4)
code_block(doc, [
    "milky_frog_stead/                 ← 仓库根目录（Git 操作在此进行）",
    "├── README.md                     # 项目说明与快速开始",
    "├── .gitignore                    # 忽略引擎缓存等",
    "├── docs/",
    "│   ├── 协作指南.md                # 环境配置、Git 流程、常见问题排查",
    "│   └── 游戏企划.md                # 立项文档（11 章，含代码骨架）",
    "└── milky-frog-stead/             ← Godot 工程根目录",
    "    ├── project.godot             # 工程配置（引擎版本、渲染、自动加载）",
    "    ├── icon.svg",
    "    ├── assets/                   # 美术资源",
    "    │   ├── sprites/",
    "    │   │   ├── backgrounds/      # farm.png, restaurant.png",
    "    │   │   └── 3像素.png          # 角色动画图集（12 帧）",
    "    │   ├── audio/                # 预留：音效与音乐",
    "    │   ├── fonts/                # 预留：字体",
    "    │   ├── textures/             # 预留：UI 贴图",
    "    │   └── tilesets/             # 预留：瓦片集",
    "    ├── scenes/                   # 场景",
    "    │   ├── farm/                 # game.tscn, character_body_2d.tscn",
    "    │   ├── restaurant/           # 预留：餐厅场景",
    "    │   ├── ui/                   # 预留：界面",
    "    │   └── main/                 # 预留：主菜单 / 入口",
    "    ├── scripts/                  # GDScript 脚本（待填充）",
    "    └── data/                     # 数值配置资源（待填充）",
])
para(doc, "需要说明的是，scripts/ 与 data/ 均已建目录但尚未提交脚本文件，"
          "assets/ 下的 audio、fonts、textures、tilesets 为后续预留目录。", space_after=6)

doc.add_heading("4.2 美术素材收集（已完成）", level=2)
para(doc, "本阶段美术素材收集工作已经完成，核心资源已导入工程并通过引擎的导入管线，"
          "可以直接在场景中引用：", space_after=3)
table(doc, ["资源", "文件", "规格与用途"], [
    ["农场底图", "assets/sprites/backgrounds/farm.png", "俯视视角农场场景底图，作为主场景背景"],
    ["餐厅底图", "assets/sprites/backgrounds/restaurant.png", "餐厅场景底图，用于营业时段"],
    ["角色动画图集", "assets/sprites/3像素.png", "横向图集，单帧 256×256，共 12 帧，"
     "已切分为行走与待机两组动画"],
], widths=[2.8, 5.6, 7.4], caption="表 4  已到位的美术素材")
para(doc, "素材统一采用像素美术风格，贴图过滤设置为 Nearest（最近邻采样）以避免缩放模糊。"
          "音频与字体资源尚未收集，当前阶段不影响功能开发。", space_after=6)

doc.add_heading("4.3 文档与协作规范（已完成）", level=2)
bullet(doc, "《游戏企划》：共 11 章，涵盖定位、核心循环、系统设计、Demo 范围与砍掉清单、"
            "数值草案、技术方案、里程碑、风险对策，并附 GDScript 代码骨架与信号契约表。")
bullet(doc, "《协作指南》：涵盖仓库权限、环境安装、Git 身份与推送凭据配置、"
            "提交与 Pull Request 流程、工程注意事项、常见报错排查表。")
bullet(doc, "信号契约表：预先约定 17 个跨系统信号的名称、参数与收发双方，"
            "作为并行开发的接口基准，避免两组人互相等待。")

doc.add_heading("4.4 工程配置（已完成）", level=2)
bullet(doc, "统一引擎版本为 Godot 4.7，避免 project.godot 中的特性标记被自动改写而产生无意义冲突。")
bullet(doc, ".gitignore 已忽略引擎缓存目录与构建产物，保证仓库整洁。")
bullet(doc, "窗口缩放模式设为 canvas_items 并采用 expand 宽高比，适配不同分辨率。")

# ---- 五
doc.add_heading("五、分工安排", level=1)
para(doc, "小组共 4 人，按“一人一条主线 + 接口先行”的方式划分。"
          "架构与接口由组长先行确定并冻结，其余成员在契约之上并行开发，"
          "尽量减少相互阻塞。", space_after=4)
table(doc, ["成员", "角色", "负责模块", "主要交付物"], [
    ["洪启智", "组长 / 架构与集成", "工程搭建、全局单例、日循环状态机、"
     "事件总线、Git 仓库与协作规范、集成联调",
     "project.godot、event_bus.gd、game_clock.gd、协作指南"],
    ["成员 B", "农场系统", "种地 / 畜牧 / 钓鱼三区域、作物按天生长与每日收获、库存系统",
     "field_plot.gd、animal_pen.gd、fishing_spot.gd、inventory.gd"],
    ["成员 C", "餐厅系统", "菜单配置、营业流程、顾客生成、订单队列、做菜上菜结账、经济结算",
     "order_queue.gd、customer.gd、restaurant_service.gd、economy.gd"],
    ["成员 D", "员工 AI 与界面", "员工状态机与寻路、岗位分配、各界面面板、美术素材收集与整理",
     "worker.gd、job_slot.gd、ui/*.tscn、assets/*"],
], widths=[2.0, 2.6, 6.0, 5.2], caption="表 5  小组成员分工")
para(doc, "说明：成员 B、C、D 的姓名待补充为组员真实姓名；"
          "除表中主责外，美术素材收集由成员 D 牵头完成，测试与文档由全组共同参与。", space_after=6)

table(doc, ["成员", "工作量占比", "当前主要工作"], [
    ["洪启智", "30%", "企划定稿、代码骨架与接口设计、仓库规范、下一步编码集成"],
    ["成员 B", "25%", "数据结构方案论证、农场系统模块设计、准备进入编码"],
    ["成员 C", "25%", "订单与营业流程设计、餐厅数据结构选型、准备进入编码"],
    ["成员 D", "20%", "美术素材收集（已完成）、员工 AI 方案设计、界面原型"],
], widths=[2.6, 2.6, 10.6], caption="表 6  工作量分配")

# ---- 六
doc.add_heading("六、进度与里程碑", level=1)
table(doc, ["阶段", "目标", "状态", "完成度"], [
    ["M0  骨架", "自动加载单例、数据资源定义、日循环状态机、主场景接线", "进行中", "60%"],
    ["M1  农场", "种地、畜牧、钓鱼三区域与库存打通", "未开始", "0%"],
    ["M2  员工", "员工状态机、寻路、岗位分配", "未开始", "0%"],
    ["M3  餐厅", "菜单配置、营业流程、顾客与订单队列、日结算", "未开始", "0%"],
    ["M4  闭环", "商店与扩张、数值接入、瓶颈可视化", "未开始", "0%"],
    ["M5  打磨", "引导提示、界面美化、缺陷清理、体验验收", "未开始", "0%"],
], widths=[2.4, 8.0, 2.6, 2.8], caption="表 7  里程碑进度")

table(doc, ["工作项", "完成度", "说明"], [
    ["需求分析与玩法设计", "100%", "企划文档定稿，范围与砍掉清单已明确"],
    ["美术素材收集", "100%", "两张场景底图与一套角色动画图集已导入工程"],
    ["工程与目录骨架", "90%", "目录、配置、场景已建立；脚本与数据目录待填充"],
    ["数据结构与算法设计", "80%", "选型与复杂度分析已完成，等待编码验证"],
    ["代码实现", "5%", "代码骨架已在企划中定型，尚未落地为脚本文件"],
    ["测试与验收", "0%", "待功能跑通后开展"],
], widths=[4.4, 2.4, 9.0], caption="表 8  各工作项完成度")
para(doc, "综合评估，项目整体进度约为 30%，处于“设计完成、即将进入编码”的节点。"
          "当前交付物以文档、工程骨架与美术资源为主，代码实现将在下一阶段集中展开。")

# ---- 七
doc.add_heading("七、技术难点与解决方案", level=1)
table(doc, ["难点", "问题描述", "解决方案"], [
    ["全局单例与类名冲突",
     "自动加载脚本若同时声明全局类名，会与单例名冲突导致工程报错",
     "约定自动加载脚本不声明全局类名，直接以单例名作为全局标识符使用"],
    ["脚本循环引用",
     "状态类既被事件总线引用、又反过来引用事件总线，构成循环依赖，"
     "可能触发解析错误",
     "约定事件总线的信号参数一律不写类型标注，仅以注释说明类型，"
     "从根上切断解析期的循环引用"],
    ["队列首删的性能代价",
     "数组实现的队列在队首删除时需整体前移，复杂度 O(n)",
     "当前订单规模下可接受，已记录为改进点：后续改用环形缓冲区降为 O(1)"],
    ["寻路网格与底图对齐",
     "导航网格需与 1014×1014 的场景底图精确对齐，烘焙调参耗时不可控",
     "准备降级方案：先以网格化 A* 加路点直连跑通功能，再回头优化"],
    ["动画资源命名不规范",
     "现有角色动画名存在拼写错误，且仅有两个方向的动画",
     "规范为待机 / 行走两个动画，方向统一由水平翻转实现，避免为每个方向单独制作"],
    ["二进制资源协作冲突",
     "Git 无法合并图片、音频等二进制文件，两人同改只能重做",
     "同一资源指定唯一负责人，美术资源由成员 D 统一收集后一次性导入"],
], widths=[3.0, 6.4, 6.4], caption="表 9  已识别的技术难点与对策")

# ---- 八
doc.add_heading("八、下一步计划", level=1)
table(doc, ["时间", "工作内容", "负责人"], [
    ["第 1 步", "落地代码骨架：自动加载单例与数据资源定义，接通日循环，保证空跑不崩",
     "洪启智"],
    ["第 2 步", "实现库存哈希表与农场三区域，打通“种植→收获→入库”链路", "成员 B"],
    ["第 3 步", "实现员工状态机与寻路，完成岗位分配与自动工作", "成员 D"],
    ["第 4 步", "实现订单队列与营业流程，打通“顾客→做菜→上菜→结账”链路", "成员 C"],
    ["第 5 步", "接入数值配置，实现商店与扩张，完成经济闭环", "成员 B、C"],
    ["第 6 步", "联调、缺陷修复与体验验收，准备课程演示", "全组"],
], widths=[2.0, 11.2, 2.6], caption="表 10  下一步工作计划")
para(doc, "验收标准：连续游玩三个游戏日不出现崩溃与数值错乱；"
          "员工被分配到不同岗位后能自行寻路并循环工作；"
          "玩家能在 15 分钟内自行发现“配菜单 → 开始营业 → 赚钱 → 招人”的主线。")

# ---- 九
doc.add_heading("九、风险与应对", level=1)
bullet(doc, "范围失控（最高风险）：放置类游戏系统易无限扩张。已建立明确的“砍掉清单”，"
            "本阶段不做天气季节、剧情对话、员工养成与钓鱼小游戏，新想法一律记入后续规划。")
bullet(doc, "进度风险：代码实现尚未开始，是当前进度的主要缺口。"
            "对策是接口先行——信号契约与代码骨架已冻结，四人可同时开工而不互相阻塞。")
bullet(doc, "数值平衡风险：首次调参可能出现经济滚不起来或过快膨胀。"
            "对策是所有数值以数据资源配置文件管理，调整不改代码。")
bullet(doc, "协作风险：多人修改同一文件易冲突。已按目录划分职责，"
            "数值配置一人一文件，二进制资源指定唯一负责人。")

# ---- 十
doc.add_heading("十、参考资料", level=1)
for ref in [
    "Godot Engine 4.x 官方文档（场景树、导航与寻路、资源系统）：https://docs.godotengine.org",
    "严蔚敏, 吴伟民. 数据结构（C 语言版）. 清华大学出版社.",
    "Thomas H. Cormen 等. 算法导论（第 3 版）. 机械工业出版社.",
    "项目仓库：https://gitee.com/hong-qizhi/milky_frog_stead",
]:
    bullet(doc, ref)

doc.save(OUT)
print("saved:", OUT)
