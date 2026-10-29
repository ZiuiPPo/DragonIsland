"""生成崖壁遮罩的「初稿 + 可绘制模板」。

输出 assets/sprites/island/cliff_mask.png：
  · 底图 = 岛图压暗到 50% 不透明度（当描画参考）
  · 红色 = 自动判定的崖壁段（可以在此基础上补画 / 擦掉）

判定思路：**不直接看最外圈的像素**（那里是深色描边，沙滩和岩壁一样暗），
而是往内陆退 10px 再看颜色：
  · 岩壁 = 灰褐、不算亮的
  · 沙滩 = 很亮的米色
  · 草地 = 绿（G 明显高于 R）
判定完再把结果向外扩回去，盖住海岸线那一圈。

运行：python tools/gen_cliff_mask.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SPR = ROOT / "milky-frog-stead" / "assets" / "sprites"
SRC = SPR / "backgrounds" / "island_key_x4_pixel_4032x3624.png"
OUT = SPR / "island" / "cliff_mask.png"

WIDTH = 0             # 0 = 和原图一样大（手画更精细）
INSET = 10            # 往内陆退多少像素再判断
GROW = 12             # 判定完向外扩多少像素（盖住海岸线）


def dilate(mask: np.ndarray, radius: int) -> np.ndarray:
    out = mask.copy()
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            if dx * dx + dy * dy > radius * radius:
                continue
            out |= np.roll(np.roll(mask, dy, axis=0), dx, axis=1)
    return out


def erode(mask: np.ndarray, radius: int) -> np.ndarray:
    return ~dilate(~mask, radius)


img = Image.open(SRC).convert("RGBA")
if WIDTH <= 0:
    WIDTH = img.width
h = int(round(WIDTH * img.height / img.width))
small = img.resize((WIDTH, h), Image.LANCZOS)
arr = np.asarray(small).astype(np.float64) / 255.0
r, g, b, a = arr[..., 0], arr[..., 1], arr[..., 2], arr[..., 3]
luma = 0.299 * r + 0.587 * g + 0.114 * b

land = a > 0.5
inner = erode(land, INSET)             # 离海岸至少 INSET 像素的内陆

# 岩壁：不算亮、且不偏绿（草地 G-R 明显为正）
rock = inner & (luma < 0.80) & ((g - r) < 0.06)
rock &= ~erode(land, INSET + 26)       # 排除更深处（那里已经是草地了）

grown = dilate(rock, GROW)

out = np.zeros((h, WIDTH, 4), dtype=np.uint8)
out[..., 0] = (arr[..., 0] * 255 * 0.5).astype(np.uint8)
out[..., 1] = (arr[..., 1] * 255 * 0.5).astype(np.uint8)
out[..., 2] = (arr[..., 2] * 255 * 0.5).astype(np.uint8)
out[..., 3] = (arr[..., 3] * 255 * 0.55).astype(np.uint8)
out[grown, 0] = 255
out[grown, 1] = 0
out[grown, 2] = 0
out[grown, 3] = 255

Image.fromarray(out, "RGBA").save(OUT)
print("cliff mask ->", OUT, (WIDTH, h), " 红色占比 %.1f%%" % (100.0 * grown.mean()))
