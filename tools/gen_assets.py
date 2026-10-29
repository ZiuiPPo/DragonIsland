"""生成水体要用的贴图。

  1. 焦散贴图 64x64 —— 硬边像素图（不是平滑灰度），放大后是块状的光斑/浪花。
  2. 浪花贴图 64x64 —— 更密的白网，专门给近岸浪花用。
  3. 16px 地形调试图集 + 沙滩图集。

两张水体贴图都要求：
  · 无缝平铺（所有波项都是整数波矢）
  · 硬阈值 + 有序抖动，没有抗锯齿 —— 放大才是像素风，不会糊
运行：python tools/gen_assets.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "milky-frog-stead" / "assets"

N = 64  # 像素图的尺寸，越小越"块"
ys, xs = np.mgrid[0:N, 0:N].astype(np.float64)
u = xs / N * np.pi * 2.0
v = ys / N * np.pi * 2.0

# 4x4 有序抖动矩阵（Bayer），用来在阈值边缘做像素风的抖动过渡
BAYER4 = np.array([
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
], dtype=np.float64) / 16.0
DITHER = np.tile(BAYER4, (N // 4, N // 4))


def hard(level: np.ndarray, density: float) -> np.ndarray:
    """按目标白色占比取阈值，并叠一层有序抖动让边缘有颗粒感。"""
    level = (level - level.min()) / (level.max() - level.min() + 1e-9)
    t = np.quantile(level, 1.0 - density)
    return (level > t - (DITHER - 0.5) * 0.18).astype(np.float64)


def field_coarse() -> np.ndarray:
    """大格光斑：低波矢的干涉条纹，做海面的焦散。"""
    a = np.sin(u * 1.0 + 1.9 * np.sin(v * 2.0)) + np.sin(v * 3.0 + 1.4 * np.sin(u * 2.0))
    sig = a + 0.8 * np.sin((u + v) * 1.5 + 0.7 * np.sin(u - v))
    return 1.0 - np.tanh(np.abs(sig) * 1.1)


def field_foam() -> np.ndarray:
    """密网：多叠两三层，得到一簇一簇的浪花白。"""
    base = field_coarse()
    b = np.sin(u * 4.0 + 2.1 * np.sin(v * 3.0 + 0.4)) + np.sin(v * 5.0 + 1.3 * np.sin(u * 4.0))
    fine = 1.0 - np.tanh(np.abs(b) * 1.6)
    c = np.sin((u * 3.0 - v * 2.0) + 1.5 * np.sin(u * 2.0 + v))
    return base * 0.55 + fine * 0.35 + (1.0 - np.tanh(np.abs(c) * 2.0)) * 0.25


def save_water_textures() -> None:
    out = ASSETS / "textures" / "water"
    out.mkdir(parents=True, exist_ok=True)

    caus = hard(field_coarse(), 0.32)
    # 三通道放同一份亮度（shader 只用 alpha），alpha = 亮度
    caus_img = np.concatenate([caus[..., None] * 255.0] * 3 + [caus[..., None] * 255.0], axis=-1)
    Image.fromarray(caus_img.astype(np.uint8), "RGBA").save(out / "caustics.png")

    foam = hard(field_foam(), 0.55)
    foam_img = np.concatenate([foam[..., None] * 255.0] * 4, axis=-1)
    Image.fromarray(foam_img.astype(np.uint8), "RGBA").save(out / "foam.png")

    # 预览：4x4 拼贴看接缝，放大 4 倍看像素
    def preview(mask: np.ndarray) -> Image.Image:
        tiled = np.tile(mask, (2, 2)) * 255.0
        return Image.fromarray(tiled.astype(np.uint8), "L").resize(
            (N * 2 * 4, N * 2 * 4), Image.NEAREST)

    preview(caus).save(ROOT / "tools" / "preview_caustics.png")
    preview(foam).save(ROOT / "tools" / "preview_foam.png")
    print("caustics / foam ->", out, caus.mean().round(2), foam.mean().round(2))


# ---------------------------------------------------------------- 地形
GRASS = [(0x8F, 0xC0, 0x45), (0x83, 0xB3, 0x3D), (0x9B, 0xCB, 0x50), (0x77, 0xA6, 0x36)]
SAND = [(0xE8, 0xC8, 0x7A), (0xDE, 0xBA, 0x68), (0xF2, 0xD6, 0x8E), (0xD2, 0xAC, 0x5C)]
WATER = [(0x3E, 0x8F, 0xB8), (0x36, 0x82, 0xAA), (0x4A, 0x9E, 0xC6), (0x2F, 0x77, 0x9E)]


def build_tile(color, cell: int, rng: np.random.Generator) -> np.ndarray:
    base = np.array(color, dtype=np.float64)
    tile = np.tile(base, (cell, cell, 1))
    noise = rng.normal(0.0, 9.0, (cell, cell, 1))
    speck = rng.random((cell, cell, 1)) < 0.06
    noise += speck * 14.0
    return (tile + noise).clip(0, 255).astype(np.uint8)


def save_tileset() -> None:
    cell = 16
    rng = np.random.default_rng(7)
    atlas = np.zeros((cell * 3, cell * 4, 3), dtype=np.uint8)
    for row, palette in enumerate((GRASS, SAND, WATER)):
        for col in range(4):
            tile = build_tile(palette[col], cell, rng)
            atlas[row * cell:(row + 1) * cell, col * cell:(col + 1) * cell] = tile
    Image.fromarray(atlas, "RGB").save(ASSETS / "tilesets" / "terrain_placeholder.png")


def save_sand_atlas() -> None:
    cell = 16
    rng = np.random.default_rng(11)
    atlas = np.zeros((cell, cell * 4, 3), dtype=np.uint8)
    for col in range(4):
        base = np.array([0xD3, 0xAD, 0x76], dtype=np.float64)
        tile = np.tile(base, (cell, cell, 1))
        dark = rng.random((cell, cell, 1)) < 0.05
        light = rng.random((cell, cell, 1)) < 0.05
        tile += dark * np.array([-26.0, -30.0, -34.0])
        tile += light * np.array([16.0, 14.0, 10.0])
        tile += rng.normal(0.0, 3.0, (cell, cell, 1))
        atlas[:, col * cell:(col + 1) * cell] = tile.clip(0, 255).astype(np.uint8)
    Image.fromarray(atlas, "RGB").save(ASSETS / "tilesets" / "sand_island.png")


if __name__ == "__main__":
    save_water_textures()
    save_tileset()
    save_sand_atlas()
