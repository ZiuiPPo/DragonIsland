shader_type canvas_item;
render_mode blend_mix;

// ═══════════════════════════════════════════════════════════════════════
//  2D 像素草地 · 草丛层
//
//  对应的 3D 版本是「竖直四边形 + 卡通着色器 + billboard + 世界噪声风场」。
//  搬到 2D 之后有几件事**必须**换做法，代码里都用 ★ 标出来了：
//
//  ★1 没有 billboard：俯视视角下精灵本来就正对镜头。3D 里 billboard 的真正职责
//     是「别让面片从它扎根的位置滑走」，2D 里这件事由「锚点 + 只动上半身」来保证。
//  ★2 没有法线/没有光照：像素画的明暗是画进图里的，所以这里不做 NdotL，
//     而是把精灵的三档色阶**重映射到地面调色板**上（见 ★6）。
//  ★3 canvas_item 没有 INSTANCE_CUSTOM：逐实例数据走 MultiMesh 的实例颜色
//     COLOR（由 grass_field_2d.gd 写入，见下面的数据约定）。
//  ★4 逐实例的姿态不能每帧从 CPU 灌（几千个实例），一律在世界坐标上现算。
//  ★5 色块在**顶点**里算：锚点对整棵草是常量，逐像素再采一次噪声没有意义。
//  ★6 色块 ≠ 给草染色，而是**换一组调色板**。精灵只有三档色阶，乘法染色
//     会把颜色推出调色板（变成脏橄榄色）；按亮度把三档色阶映射到调色板上的
//     三个绿，才是像素画该有的做法。
//
//  数据约定（MultiMesh.use_colors）：
//      COLOR.r = 0..1 随机数   —— 亮度微差
//      COLOR.g = 0..1 时间相位 —— 每簇错开节拍
//      COLOR.b = 0..1 变体     —— 帧号 + 镜像
//      COLOR.a = 0..1 风力增益 —— 有的草反应大，有的几乎不动
// ═══════════════════════════════════════════════════════════════════════

// ── 精灵 ─────────────────────────────────────────────────────────
uniform sampler2D albedo_tex : filter_nearest, repeat_disable;
uniform float frame_count = 1.0;          // 精灵横向有几帧

// ── 调色板（★6）──────────────────────────────────────────────────
// 三档色阶 × 三种色块。下面这组的颜色就是精灵原色，所以 palette_strength=1
// 时"中性"色块和原图完全一致，另两组只是往亮/暗各挪一点。
uniform vec3  pal_0_lo : source_color = vec3(0.639, 0.808, 0.098);  // 日照-暗
uniform vec3  pal_0_mid : source_color = vec3(0.769, 0.902, 0.278); // 日照-中
uniform vec3  pal_0_hi : source_color = vec3(0.831, 0.949, 0.376);  // 日照-亮
uniform vec3  pal_1_lo : source_color = vec3(0.584, 0.773, 0.059);  // 中性-暗（精灵原色）
uniform vec3  pal_1_mid : source_color = vec3(0.725, 0.875, 0.227); // 中性-中
uniform vec3  pal_1_hi : source_color = vec3(0.780, 0.918, 0.310);  // 中性-亮
uniform vec3  pal_2_lo : source_color = vec3(0.522, 0.714, 0.039);  // 背阴-暗
uniform vec3  pal_2_mid : source_color = vec3(0.663, 0.827, 0.176); // 背阴-中
uniform vec3  pal_2_hi : source_color = vec3(0.729, 0.882, 0.259);  // 背阴-亮
uniform float palette_strength = 1.0;     // 0 = 保留精灵原色，1 = 完全换成调色板
// 色阶分档只按"离哪一档的亮度最近"来判，不写死阈值：
// canvas_item 里纹理采样是**线性空间**，写死的 sRGB 阈值一个都对不上。

// ── 色块（异质性 A）──────────────────────────────────────────────
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float patch_scale = 900.0;        // 一张噪声铺多少世界像素（要和地面色块层一致）
uniform float patch_contrast = 1.15;      // 色块硬边程度（>1.6 会大面积饱和成 0/1）
uniform float patch_bias = 0.0;
// 边界抖动：必须和地面色块层用同一套参数，否则草丛换色和地面换色的边界会错开
uniform float patch_dither = 0.10;
// 色块强度：0 = 所有草丛都用中性调色板（原图色），1 = 完全按噪声分三种色块
uniform float patch_strength = 1.0;
uniform float brightness_jitter = 0.05;   // 逐簇亮度微差

// ── 风 ───────────────────────────────────────────────────────────
uniform vec2  wind_dir = vec2(1.0, 0.35);
uniform float wind_speed = 26.0;          // 阵风移动速度（世界像素/秒）
uniform float wind_scale = 760.0;         // 阵风噪声的世界尺度
uniform float gust_spread = 42.0;         // 发散角（度）
uniform float gust_gain = 2.8;            // 两路噪声相乘后放大
uniform float gust_bias = -0.22;          // 偏移：控制"静止的草"占多少
uniform float gust_stretch = 0.42;        // 沿垂直风向压扁 → 阵风成带状
uniform float wind_slide = 0.0;           // 整块平移上限（局部像素）。草丛不要整体晃，给 0
uniform float wind_shear = 1.2;           // 顶端剪切上限（局部像素）：1~2 = 只有顶上几行位移 1 像素
uniform float shear_pow = 1.7;
uniform float flutter = 0.5;              // 高频微抖（像素）
uniform float anim_fps = 9.0;             // 整片草地的时间步进；0 = 每帧连续
uniform float pixel_snap = 1.0;           // 1 = 位移取整到像素

// ── 交互 ─────────────────────────────────────────────────────────
// xy = 世界坐标，z = 半径，w = 强度（0 = 槽位空着）
uniform vec4 pushers[4];

varying vec2  v_uv;
varying float v_var;
varying float v_bright;
varying float v_patch;

mat2 rot2(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}


void vertex() {
	v_uv = UV;
	v_var = COLOR.b;
	v_bright = COLOR.r;

	// 实例锚点（世界坐标）。不能用 VERTEX 现算：那是逐顶点的，噪声会被拉成斜面。
	vec2 anchor = MODEL_MATRIX[3].xy;

	// ★4 时间量化：整片草按 anim_fps 步进。COLOR.g 让每簇在自己的节拍上跳，
	//   否则整片草地会在同一帧一起动，看起来是"卡住"而不是"手绘"。
	float t = TIME;
	if (anim_fps > 0.001) {
		t = floor(TIME * anim_fps + COLOR.g * 1.7) / anim_fps;
	}

	// ── 阵风：两个「偏开 ±发散角」的风向各采一次噪声，相乘 ──────────
	vec2 d = normalize(wind_dir);
	vec2 perp = vec2(-d.y, d.x);
	mat2 basis = mat2(d, perp * gust_stretch);      // 沿垂直风向压扁 → 带状
	vec2 q = basis * anchor / wind_scale;

	vec2 d1 = rot2(radians(gust_spread)) * d;
	vec2 d2 = rot2(-radians(gust_spread)) * d;

	// 无理数比例（√2、φ）保证两路噪声永远不会重新对齐成同一个图案
	float s1 = t * wind_speed / wind_scale;
	float s2 = t * wind_speed * 1.6180339 / (wind_scale * 1.4142136);

	float n1 = texture(noise_tex, q - d1 * s1).g;
	float n2 = texture(noise_tex, q * 1.4142136 - d2 * s2).g;

	// 相乘 → 到处都是 0 居多，补一个偏移把"动起来"的比例调回来
	float gust = clamp(n1 * n2 * gust_gain + gust_bias, 0.0, 1.0) * COLOR.a;

	// ── 姿态：只动顶端，而且只动整数像素 ──────────────────────────
	// 逐实例的基础抖动：三角波 + 各自相位，周期约 0.8 秒，幅度 1 像素。
	// 这是"草丛在呼吸"，阵风再叠在它上面。别用纯随机——那会变成雪花噪点。
	float base = abs(fract(t * 2.5 + COLOR.g * 3.1) * 2.0 - 1.0);
	float amp = clamp(max(gust * 1.2, base * 0.8), 0.0, 1.6);
	float h = clamp(1.0 - UV.y, 0.0, 1.0);          // 0 = 根部, 1 = 顶部
	vec2 offset = d * (gust * wind_slide + amp * wind_shear * pow(h, shear_pow));

	// 高频微抖：不是风，是"像素在呼吸"
	float micro = texture(noise_tex, anchor / 83.0 + vec2(t * 2.7, -t * 1.9)).b;
	offset += (vec2(micro, 1.0 - micro) - 0.5) * flutter * h;

	// ── 被踩开的草 ──────────────────────────────────────────────
	// 2D 俯视里"弯腰"= 朝远离推挤点的方向倒；离得越近倒得越狠，根不动。
	for (int i = 0; i < 4; i++) {
		vec4 p = pushers[i];
		if (p.w > 0.001) {
			vec2 dp = anchor - p.xy;
			float dist = length(dp);
			if (dist < p.z && dist > 0.001) {
				float f = 1.0 - dist / p.z;
				offset += normalize(dp) * p.w * f * f * h;
			}
		}
	}

	// ★ 位移取整到像素：像素画里"半个像素"的位移会抖成锯齿
	if (pixel_snap > 0.5) {
		offset = floor(offset + 0.5);
	}
	VERTEX += offset;

	// ── 色块（异质性 A）──────────────────────────────────────────
	// ★5 锚点对整棵草是常量，在这里算一次就够。
	float patch = texture(noise_tex, anchor / patch_scale).r;
	patch = clamp((patch - 0.5) * patch_contrast + 0.5 + patch_bias, 0.0, 1.0);
	float dither = (texture(noise_tex, anchor / 42.0 + vec2(0.37, 0.11)).b - 0.5) * patch_dither;
	v_patch = mix(0.5, clamp(patch + dither, 0.0, 1.0), patch_strength);
}


void fragment() {
	// ── 变体：帧号 + 水平镜像（镜像不破坏左上光源的斜面）────────────
	float vv = clamp(v_var, 0.0, 0.9999) * frame_count;
	float col = floor(vv);
	float flip = mod(floor(fract(vv) * 2.0), 2.0);

	float u = mix(v_uv.x, 1.0 - v_uv.x, flip);
	vec2 uv = vec2((u + col) / frame_count, v_uv.y);
	vec4 c = texture(albedo_tex, uv);

	// ★ 硬边：像素精灵不该有半透明过渡；alpha 阈值 1 = 只有全不透明的留下
	if (c.a < 0.999) {
		discard;
	}

	// ── ★6 三档色阶 → 调色板 ──────────────────────────────────────
	// 先按色块选一组调色板，再把精灵像素分到"离它最近的那一档亮度"上。
	// 参照档位用 pal_1（中性组 = 精灵原色），所以换了别的色块也能判准。
	vec3 lo = v_patch < 0.34 ? pal_0_lo : (v_patch < 0.68 ? pal_1_lo : pal_2_lo);
	vec3 mid = v_patch < 0.34 ? pal_0_mid : (v_patch < 0.68 ? pal_1_mid : pal_2_mid);
	vec3 hi = v_patch < 0.34 ? pal_0_hi : (v_patch < 0.68 ? pal_1_hi : pal_2_hi);

	const vec3 LUMA = vec3(0.299, 0.587, 0.114);
	float luma = dot(c.rgb, LUMA);
	float d_lo = abs(luma - dot(pal_1_lo, LUMA));
	float d_mid = abs(luma - dot(pal_1_mid, LUMA));
	float d_hi = abs(luma - dot(pal_1_hi, LUMA));

	vec3 remapped = hi;
	if (d_lo < d_mid && d_lo < d_hi) {
		remapped = lo;
	} else if (d_mid < d_hi) {
		remapped = mid;
	}

	// 逐簇亮度微差：用实例随机数（用世界噪声会和色块叠成条纹）
	float jitter = 1.0 + (v_bright - 0.5) * 2.0 * brightness_jitter;

	vec3 rgb = mix(c.rgb, remapped, palette_strength) * jitter;
	COLOR = vec4(rgb, 1.0);
}
