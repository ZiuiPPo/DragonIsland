shader_type canvas_item;
render_mode unshaded;

// ═══════════════════════════════════════════════════════════════════════
//  2D 像素草地 · 地面色块层
//
//  这就是 3D 流程里「采样世界空间噪声 → 和阈值比较 → 选一种草地颜色」那一步，
//  只不过变色的对象是**地面瓦片本身**，不是草丛：
//
//    1. 用世界坐标采一张可平铺噪声（和草丛层同一张、同一个尺度，两层才对得上）；
//    2. 噪声拉伸后和 0.34 / 0.68 两个阈值比较 → 选中三组调色板之一；
//    3. 再把瓦片像素按**亮度**归到最近的一档（暗边 / 主色 / 亮边），换成选中调色板
//       里对应的那一档。
//
//  第 3 步是 2D 特有的：像素瓦片自带两三档明暗（描边、斜面），直接乘一个颜色会把
//  明暗关系糊掉、还会把颜色推出调色板。按色阶分别替换，瓦片的立体感原样保留。
//
//  ★ 两个实测坑（改这个文件前先看）：
//    · **不要写 `texture(TEXTURE, UV) * COLOR`**。TileMapLayer 的 COLOR 不是白色，
//      实测它等于瓦片自己的颜色 —— 乘上去会把颜色平方（169,211,33 → 112,175,4），
//      于是所有像素都被判成最暗一档，地面塌成一片死色。
//    · 色阶分档别写死 sRGB 阈值：按"离参考调色板哪一档的亮度最近"来判，
//      这样不受颜色空间/调色板改动影响。
//
//  用法：把本材质挂到 TileMapLayer 的 material 上（只挂草地层，沙滩/农田不要挂）。
// ═══════════════════════════════════════════════════════════════════════

uniform sampler2D noise_tex : filter_linear, repeat_enable;

// ── 色块 ─────────────────────────────────────────────────────────
uniform float patch_scale = 1400.0;       // 一张噪声铺多少世界像素（和草丛层保持一致）
uniform float patch_contrast = 1.15;      // 和草丛层一致：>1.6 会大面积饱和成 0/1
uniform float patch_bias = 0.0;

uniform vec3  pal_0_lo : source_color = vec3(0.561, 0.749, 0.137);  // 日照-暗边
uniform vec3  pal_0_mid : source_color = vec3(0.682, 0.843, 0.149); // 日照-主色
uniform vec3  pal_0_hi : source_color = vec3(0.797, 0.925, 0.310);  // 日照-亮边
uniform vec3  pal_1_lo : source_color = vec3(0.498, 0.694, 0.110);  // 中性-暗边
uniform vec3  pal_1_mid : source_color = vec3(0.663, 0.827, 0.129); // 中性-主色（= 瓦集原色）
uniform vec3  pal_1_hi : source_color = vec3(0.725, 0.875, 0.227);  // 中性-亮边
uniform vec3  pal_2_lo : source_color = vec3(0.443, 0.639, 0.098);  // 背阴-暗边
uniform vec3  pal_2_mid : source_color = vec3(0.620, 0.788, 0.102); // 背阴-主色
uniform vec3  pal_2_hi : source_color = vec3(0.686, 0.855, 0.184);  // 背阴-亮边

// 色块边界抖动：拿高频噪声把 patch 推一下，边界就不会是"喷枪画的一条曲线"，
// 而是一段一段散开的像素点 —— 像素画里这种 dither 边才不显脏。
uniform float patch_dither = 0.10;
// 色块强度：0 = 地面一整片纯色（只用瓦片原色），1 = 完全按噪声分三种色块
uniform float patch_strength = 1.0;

// ── 草线细化：把草地和沙滩的交界从 16px 瓦片台阶细化到 4 像素 ──────────
// 数据来自 TerrainField 烘的那张距离场（和水体共用同一张）。use_edge_mask 由
// IslandTerrain 在第一次烘完距离场后置 1，所以刚启动的那一两帧不会误切。
uniform float use_edge_mask = 0.0;
uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform vec2  rect_origin = vec2(0.0);
uniform vec2  rect_size = vec2(1024.0);
uniform float sdf_range = 24.0;
uniform float edge_pixel = 2.0;     // 草线量化到 2 像素
uniform float grass_edge = 4.0;     // 到水线几格以内算沙滩（= IslandTerrain.beach_tiles）
uniform float edge_inset = 0.0;     // 正数 = 把草线往岸上推（格）

varying vec2 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// ── 草线细化：按 4 像素网格取距离场，落在沙滩侧的直接丢掉，露出下面的沙滩瓦片 ──
	if (use_edge_mask > 0.5) {
		vec2 eq = floor(v_world / edge_pixel) * edge_pixel;
		float sd = (texture(mask_tex, (eq - rect_origin) / rect_size).g - 0.5) * 2.0 * sdf_range;
		if (-sd <= grass_edge + edge_inset) {
			discard;
		}
	}

	vec4 c = texture(TEXTURE, UV);            // ★ 别乘 COLOR，见文件头
	if (c.a < 0.5) {
		discard;                              // 图集里的透明块（自动拼接用）
	}

	// 1) 世界噪声 → 拉伸 → 选调色板
	float n = texture(noise_tex, v_world / patch_scale).r;
	float patch = clamp((n - 0.5) * patch_contrast + 0.5 + patch_bias, 0.0, 1.0);
	float dither = (texture(noise_tex, v_world / 42.0 + vec2(0.37, 0.11)).b - 0.5) * patch_dither;
	patch = mix(0.5, clamp(patch + dither, 0.0, 1.0), patch_strength);

	vec3 lo = patch < 0.34 ? pal_0_lo : (patch < 0.68 ? pal_1_lo : pal_2_lo);
	vec3 mid = patch < 0.34 ? pal_0_mid : (patch < 0.68 ? pal_1_mid : pal_2_mid);
	vec3 hi = patch < 0.34 ? pal_0_hi : (patch < 0.68 ? pal_1_hi : pal_2_hi);

	// 2) 瓦片像素归到最近的一档：描边还在，颜色变了
	const vec3 LUMA = vec3(0.299, 0.587, 0.114);
	float luma = dot(c.rgb, LUMA);
	float d_lo = abs(luma - dot(pal_1_lo, LUMA));
	float d_mid = abs(luma - dot(pal_1_mid, LUMA));
	float d_hi = abs(luma - dot(pal_1_hi, LUMA));

	vec3 out_col = hi;
	if (d_lo < d_mid && d_lo < d_hi) {
		out_col = lo;
	} else if (d_mid < d_hi) {
		out_col = mid;
	}

	COLOR = vec4(out_col, 1.0);
}
