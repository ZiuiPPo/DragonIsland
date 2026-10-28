"""生成草地系统用的无缝噪声图（tileable fbm）。

python tools/gen_grass_noise.py

输出 assets/textures/noise/grass_noise.png，256x256 RGBA：
  R = 低频（~40 世界像素一格）→ 色块 / 密度大块
  G = 中频（~110 世界像素一格）→ 风的阵风
  B = 高频（~7 世界像素一格）→ 逐点微抖动
  A = 255

无缝的做法很简单：晶格坐标按格数取模，插值用 smoothstep，八度叠加时每层格数都是 2 的幂，
所以左右/上下边界天然接得上，不需要额外缝合。
"""
from pathlib import Path

import numpy as np
from PIL import Image

N = 256
OUT = Path(__file__).resolve().parent.parent / "milky-frog-stead" / "assets" / "textures" / "noise" / "grass_noise.png"


def value_noise(cells: int, seed: int, size: int = N) -> np.ndarray:
    """周期性 value noise：cells x cells 的随机晶格，双线性 + smoothstep 插值。"""
    rng = np.random.default_rng(seed)
    lat = rng.random((cells, cells)).astype(np.float64)
    t = np.arange(size) / size * cells
    i0 = np.floor(t).astype(int) % cells
    i1 = (i0 + 1) % cells
    f = t - np.floor(t)
    f = f * f * (3.0 - 2.0 * f)          # smoothstep
    fx = f[None, :]
    fy = f[:, None]

    # 四个角的晶格值：行取 y 的两个索引，列取 x 的两个索引
    ax = lat[i0[:, None], i0[None, :]] * (1.0 - fx) + lat[i0[:, None], i1[None, :]] * fx
    bx = lat[i1[:, None], i0[None, :]] * (1.0 - fx) + lat[i1[:, None], i1[None, :]] * fx
    return ax * (1.0 - fy) + bx * fy


def fbm(layers: list[tuple[int, float]], seed: int) -> np.ndarray:
    out = np.zeros((N, N), dtype=np.float64)
    total = 0.0
    for k, (cells, weight) in enumerate(layers):
        out += value_noise(cells, seed + k * 101, N) * weight
        total += weight
    out /= total
    out -= out.min()
    mx = out.max()
    return out / mx if mx > 0 else out


def main() -> None:
    # 频率按「一张 256 贴图铺多少世界像素」换算：patch_scale=900 时，
    # cells=8 → 一格约 112 世界像素；cells=32 → 28 世界像素。
    r = fbm([(4, 0.55), (8, 0.30), (16, 0.15)], 1)        # 大色块
    g = fbm([(8, 0.45), (16, 0.35), (32, 0.20)], 2)       # 阵风
    b = fbm([(32, 0.50), (64, 0.35), (128, 0.15)], 3)     # 微抖动

    # 每通道拉开对比度，采样时才不会都挤在 0.5 附近
    def stretch(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
        return np.clip((x - lo) / (hi - lo), 0.0, 1.0)

    r = stretch(r, 0.18, 0.82)
    g = stretch(g, 0.22, 0.78)
    b = stretch(b, 0.10, 0.90)

    rgba = np.zeros((N, N, 4), dtype=np.uint8)
    rgba[..., 0] = (r * 255.0 + 0.5).astype(np.uint8)
    rgba[..., 1] = (g * 255.0 + 0.5).astype(np.uint8)
    rgba[..., 2] = (b * 255.0 + 0.5).astype(np.uint8)
    rgba[..., 3] = 255

    OUT.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(rgba, "RGBA").save(OUT, optimize=True)
    print("noise ->", OUT)


if __name__ == "__main__":
    main()
