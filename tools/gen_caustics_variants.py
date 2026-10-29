"""焦散贴图的几个变体，拼成一张对比图挑一个。

python tools/gen_caustics_variants.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tools" / "caustics_variants.png"

N = 256
ys, xs = np.mgrid[0:N, 0:N].astype(np.float64)
u = xs / N * np.pi * 2.0
v = ys / N * np.pi * 2.0


def ridge(x, k):
    r = 1.0 - np.tanh(np.abs(x) * k)
    return r / r.max()


def v1():
    """大格 + 粗线：波矢降到 1~3"""
    a = np.sin(u * 1.0 + 1.9 * np.sin(v * 2.0)) + np.sin(v * 3.0 + 1.4 * np.sin(u * 2.0))
    sig = a + 0.8 * np.sin((u + v) * 1.5 + 0.7 * np.sin(u - v))
    return ridge(sig, 1.1) ** 2.0


def v2():
    """经典 caustic 味：两层脊线相乘，一层大一层小"""
    big = ridge(np.sin(u * 2.0 + 1.6 * np.sin(v * 3.0)) + np.sin(v * 2.0 + 1.3 * np.sin(u * 3.0)), 1.3)
    small = ridge(np.sin(u * 5.0 - 0.8 * np.sin(v * 4.0)) + np.sin(v * 5.0), 2.4)
    return np.clip(big ** 1.6 + small * 0.35, 0, None)


def v3():
    """用"到格子边界的距离"做线，更像水底光斑拼接"""
    gx = np.sin(u * 2.0) * np.cos(v * 1.0)
    gy = np.sin(v * 3.0) * np.cos(u * 1.0)
    d = np.abs(gx * 0.6 + gy * 0.4)
    return (1.0 - np.tanh(d * 2.2)) ** 2.5


def v4():
    v1_ = v1()
    v2_ = v2()
    return np.clip(v1_ * 0.6 + v2_ * 0.7, 0, None)


variants = [v1(), v2(), v3(), v4()]
tiles = []
for c in variants:
    c = (c - c.min()) / (c.max() - c.min())
    tiles.append((c * 255).astype(np.uint8))

montage = np.zeros((N * 2, N * 2), dtype=np.uint8)
for i, t in enumerate(tiles):
    y = (i // 2) * N
    x = (i % 2) * N
    montage[y:y + N, x:x + N] = t

Image.fromarray(montage, "L").save(OUT)
print("variants ->", OUT, "  (左上 v1 右上 v2 / 左下 v3 右下 v4)")
