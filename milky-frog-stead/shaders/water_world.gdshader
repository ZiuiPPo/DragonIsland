shader_type canvas_item;
render_mode unshaded, blend_mix;

// Driven by DayNightCycle; defaults preserve standalone daytime previews.
uniform vec4 environment_tint : source_color = vec4(1.0);
uniform float night_amount : hint_range(0.0, 1.0) = 0.0;
// Keep the sunset amber hue at night, with darker water and subdued warm highlights.
uniform vec4 night_shallow : source_color = vec4(0.25, 0.15, 0.07, 1.0);
uniform vec4 night_deep : source_color = vec4(0.14, 0.065, 0.02, 1.0);
uniform float night_caustics : hint_range(0.0, 1.0) = 0.12;
uniform float night_highlight : hint_range(0.0, 1.0) = 0.22;

// ═══════════════════════════════════════════════════════════════════════
//  世界水体着色器
//
//  数据来源是 CPU 烘出来的一张低分辨率小图（1 texel = 1 格瓦片）：
//      R = 水深 0..1（0 = 水线，1 = 深水）
//      G = 到水线的有符号距离（0.5 = 水线，>0.5 在水里）
//      B = 陆地高度 0..1（备用）
//      A = 水体蒙版（0/1，靠双线性插值出一格宽的过渡）
//
//  贴图是**世界锚定**的：rect_origin/rect_size 只在跨区块时变一次，
//  所以水纹钉在世界坐标上，镜头移动时不会整体跟着滑。
//
//  分五段：水体配色 → 焦散 → 高光 → 浪花 → 合成
// ═══════════════════════════════════════════════════════════════════════

// ── 高度图定位（对应你说的 position / scale）─────────────────────
uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform vec2  rect_origin = vec2(0.0);   // 贴图左下角的世界坐标
uniform vec2  rect_size = vec2(1024.0);  // 贴图覆盖的世界范围
uniform float sdf_range = 8.0;           // 距离场在多少格处截止
uniform float tile_size = 16.0;          // 一格瓦片多少世界像素

// ── 水体配色 ─────────────────────────────────────────────────────
uniform float shallow_width = 6.0;       // 浅水带宽度（格）：从水线往里多少格算深水
// 渐变方向：近岸浅水 = 浅黄（亮），越往外越深 = 橙黄。
// 想反过来就交换这两个颜色。
uniform vec4  col_water_shallow : source_color = vec4(1.0, 0.93, 0.66, 1.0);   // 浅黄（近岸）
uniform vec4  col_water_deep : source_color = vec4(0.86, 0.50, 0.16, 1.0);      // 橙黄（深水）

// ── 像素化 ───────────────────────────────────────────────────────
uniform float pixel_size = 2.0;          // 世界坐标先量化到这个网格再喂噪声
uniform float grain = 0.10;              // 水体颗粒感

// ── 焦散层 ───────────────────────────────────────────────────────
uniform sampler2D caustics_tex : repeat_enable, filter_nearest;
uniform sampler2D foam_mask_tex : repeat_enable, filter_nearest;   // 浪花图案（更密的硬边像素图）
uniform float caustics_size = 220.0;     // 一张焦散贴图铺多少世界像素
uniform float caustics_y_squash = 1.30;  // y 方向压扁，营造俯视感
uniform float caustics_strength = 0.85;
uniform vec4  col_caustics : source_color = vec4(1.0, 0.97, 0.80, 1.0);
uniform float flow_freq = 0.016;         // 流动噪声频率
uniform float flow_speed = 0.35;         // 流动速度（UV/秒）
uniform float flow_strength = 10.0;      // 扰动强度（世界像素）

// ── 高光层 ───────────────────────────────────────────────────────
uniform float hl_freq = 0.038;
uniform float hl_speed = 0.55;
uniform float hl_threshold = 0.28;
uniform float hl_softness = 0.08;
uniform float hl_strength = 0.75;
uniform float hl_crest_mode : hint_range(0.0, 1.0) = 0.85;  // 0 = 按贴图上半部, 1 = 按焦散亮度
uniform vec4  col_highlight : source_color = vec4(1.0, 0.97, 0.82, 1.0);
uniform float hl_breakup = 0.85;         // 细噪声把大色块切碎

// ── 浪花层 ───────────────────────────────────────────────────────
uniform float foam_scale = 120.0;        // 复用焦散贴图，缩小来当浪花纹理
uniform float foam_pixel = 4.0;          // 浪花的像素网格（世界像素）：调大=块更粗
uniform float foam_cell = 64.0;          // 每多少世界像素换一个浪花变体
uniform float foam_speed = 0.06;         // 浪花纹理漂移
uniform float splash_scale = 55.0;       // 崖壁溅沫的纹理尺度（越小越碎）
uniform float foam_opacity = 0.9;
uniform float anim_speed = 1.0;          // 0 = 冻住水面（截图 / 对比测试用）
uniform float rim_width = 0.35;          // 岸边浅色环的宽度（格）
uniform float rim_strength = 0.9;        // 浅色环强度
uniform vec4  col_rim : source_color = vec4(1.0, 1.0, 1.0, 1.0);   // 岸边白描边

// ── 边缘起伏（水线随噪声来回走）─────────────────────────────────
uniform float edge_wobble = 0.85;        // 起伏幅度，单位「格」
uniform float edge_freq = 0.020;         // 起伏的空间频率
uniform float edge_speed = 0.22;         // 起伏的流动速度
uniform float edge_breathe = 0.18;       // 整条海岸线的整体呼吸幅度（格）
uniform float edge_inland_clamp = 1.0;   // 1 = 水线只往海里退，绝不上岸越过遮罩红线
uniform float edge_pixel = 2.0;          // 海岸线的像素网格：水线按这个格子量化成硬边
uniform float edge_fps = 8.0;            // 海岸线动画帧率（序列帧感，别设太高）
uniform float tide_amp = 0.9;            // 潮汐幅度（格）：水线上下各走多少
uniform float tide_speed = 0.7;          // 潮汐速度（弧度/秒）
uniform float debug_cliff = 0.0;        // 1 = 把判定成崖壁的岸段染红（调参用）
uniform float shore_offset = 0.0;        // 把水线往岸上推几格（用来盖住瓦片海岸的台阶）
uniform vec4  col_foam : source_color = vec4(1.0, 1.0, 1.0, 1.0);
varying vec2 world_pos;

// ── Perlin 噪声（够用就行，不追和 CPU 侧一致）────────────────────
vec2 hash22(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float perlin(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(hash22(i), f);
	float b = dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	return perlin(p) * 0.62 + perlin(p * 2.07 + 19.3) * 0.38;
}

// 0..1 的哈希，用作像素颗粒
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	// 世界坐标在顶点里算：MODEL_MATRIX 是「模型 → 世界」，不含相机变换，
	// 所以相机移动不会让水纹跟着滑。
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 wp = world_pos;

	// ── 0. 高度图采样 ──────────────────────────────────────────────
	vec2 uv = (wp - rect_origin) / rect_size;
	vec4 mask = texture(mask_tex, uv);
	float depth = mask.r;                                  // 0 = 水线, 1 = 深水
	// 岸型：烘焙在 B 通道里，0 = 沙滩，1 = 崖壁（由岛图颜色判断出来的）
	float cliff = clamp(mask.b, 0.0, 1.0);

	// 先用像素化网格把世界坐标量化，再拿去做噪声 / 采样焦散。
	// 不量化的话，流动噪声把 UV 一拉，贴图里的像素会被拉伸得很明显。
	vec2 pwp = floor(wp / pixel_size) * pixel_size;
	float T = TIME * anim_speed;

	// ── 0.5 海岸线：像素化 + 序列帧 + 潮汐 ────────────────────────
	vec2 ep = floor(wp / edge_pixel) * edge_pixel;
	vec2 euv = (ep - rect_origin) / rect_size;
	float d_e = (texture(mask_tex, euv).g - 0.5) * 2.0 * sdf_range;

	// 序列帧：时间量化到 edge_fps，海岸线是一帧一帧跳的，不是连续滑的
	float Tq = floor(T * edge_fps) / max(edge_fps, 1.0);

	// 每段海岸线自己的相位（潮汐和浪花共用，所以各处不同步）
	float phase = fbm(ep * 0.0032 + 13.0) * 11.0;   // 低频、大范围：整条海岸线分几段各走各的

	// 低频噪声：把水线揉出起伏
	vec2 ewob_uv = ep * edge_freq + vec2(Tq * edge_speed, Tq * edge_speed * 0.6);
	float wob = (fbm(ewob_uv) + 0.55 * fbm(ewob_uv * 2.3 + 11.0)) * edge_wobble;

	// 潮汐：本段海岸线的水位在 ±tide_amp 格之间涨落
	float tide = sin(Tq * tide_speed + phase) * tide_amp;

	float off = wob + shore_offset + tide + sin(Tq * 0.45) * edge_breathe;
	// 岸线由遮罩决定：
	//   沙滩 — 只许往海里退，不上岸
	//   崖壁 — 完全不动，白描边固定死（浪拍上去，但水线不挪）
	off = mix(off, min(off, 0.0), edge_inland_clamp);
	off = mix(off, 0.0, cliff);
	float d = d_e + off;
	// 近岸不做硬切：用 alpha 渐变让水色淡进沙子里（这就是"透明选色"）。
	// d 已经在 edge_pixel 的网格上量化过，所以这条渐变是块状的，不是抗锯齿的糊边。
	float water = smoothstep(-0.5, 0.5, d);
	float shore = -d;

	// ── 1. 水体配色 ─────────────────────────────────────────────
	// 水深渐变：浅水发青，深水压暗。
	// 用「到水线的距离」当主控（浅水带宽度就是直观的几格），
	// 再和贴图里的真实水深取 max，避免地形陡的地方浅水带被吃掉。
	// 崖壁下面没有沙滩，所以不吃浅水带：水直接是深的、能压出暗边，
	// 白色溅沫这才有对比（不然全是浅色的白，什么都看不出来）
	float shallow_t = smoothstep(0.0, shallow_width, -shore) * (1.0 - cliff * 0.9);
	float depth_t = clamp(max(pow(clamp(depth, 0.0, 1.0), 1.4), shallow_t), 0.0, 1.0);
	vec3 water_col = mix(col_water_shallow.rgb, col_water_deep.rgb, depth_t);

	// ── 2. 水体边缘：渐变色的 alpha × 主贴图 alpha ────────────────
	// 这里的 water 就是"主贴图 alpha"那一项：双线性插出来的 0..1 水体蒙版。
	// 乘上它，水体渐变才只在水里出现，不会糊到沙滩上。
	vec3 base = water_col;

	// 像素颗粒
	base *= 1.0 + (hash21(pwp) - 0.5) * grain;

	// ── 3. 焦散层：流动噪声扰动 + 平铺贴图 ────────────────────────
	// 噪声的输入端加 TIME，它就"流"起来了；再把它混进世界坐标，
	// 采样贴图前坐标已经被揉过，看起来就是水在动。
	vec2 flow_uv = pwp * flow_freq + vec2(T * flow_speed * 0.35, T * flow_speed);
	vec2 warp = vec2(fbm(flow_uv), fbm(flow_uv + 41.7)) * flow_strength;

	vec2 cuv = (pwp + warp) / caustics_size;
	cuv.y *= caustics_y_squash;                    // y 轴压扁 = 俯视
	vec4 c1 = texture(caustics_tex, cuv);
	// 第二层不同尺度反向漂移，盖掉单张平铺的重复感
	vec4 c2 = texture(caustics_tex, cuv * 1.63 + vec2(T * 0.009, -T * 0.013));
	float caus = c1.a * 0.80 + c2.a * 0.22;
	caus = pow(clamp(caus, 0.0, 1.0), 3.4);          // 压成细亮线，别糊成一片塑料布
	// 深水看不见底，焦散弱一些
	caus *= mix(1.0, 0.55, depth_t);

	// ── 4. 高光层：两组反向流动的噪声相减 ─────────────────────────
	vec2 hl_uv = pwp * hl_freq;
	float n1 = fbm(hl_uv + vec2(T * hl_speed, T * hl_speed * 0.4));
	float n2 = fbm(hl_uv * 0.92 - vec2(T * hl_speed * 0.8, -T * hl_speed * 0.25) + 57.0);
	float sparkle = n1 - n2;                       // 两组冲撞出来的波光
	// step 出硬边：低于阈值的全砍掉（用 smoothstep 留一点点柔度，防锯齿）
	sparkle = smoothstep(hl_threshold, hl_threshold + hl_softness, sparkle);

	// 细小尺度的噪声，把大色块切碎
	float breakup = fbm(pwp * hl_freq * 4.3 - vec2(T * 0.05, 0.0));
	sparkle *= mix(1.0, smoothstep(-0.15, 0.35, breakup), hl_breakup);

	// 只在焦散的上部显示：把「贴图上半部」和「焦散自己的亮部」混着用，
	// 纯按贴图上半部会看到一排排重复的横条。
	float crest_v = smoothstep(0.30, 0.78, fract(cuv.y));
	float crest_luma = smoothstep(0.30, 0.85, c1.a);
	float crest = mix(crest_v, crest_luma, hl_crest_mode);

	// ── 5. 浪花层 ─────────────────────────────────────────────────
	// ① 主贴图（水体蒙版）模糊。关键：**在更粗的像素网格上采**，
	//    这样模糊出来的岸线带也是块状的；按屏幕逐像素采会得到一条糊掉的渐变。
	vec2 fwp = floor(wp / foam_pixel) * foam_pixel;
	vec2 fuv = (fwp - rect_origin) / rect_size;
	vec2 texel = 1.0 / vec2(textureSize(mask_tex, 0));
	float blurred = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			blurred += texture(mask_tex, fuv + vec2(float(i), float(j)) * texel).a;
		}
	}
	blurred /= 9.0;

	// ② 白色区域里铺缩小版焦散 —— 缩得足够小，看起来就是浪花。
	//    每个 foam_cell 随机换偏移/镜像，避免一眼看出是同一张贴图在平铺。
	float vh = hash21(floor(fwp / foam_cell) + 3.0);
	vec2 foam_uv = fwp / foam_scale + vec2(T * 0.015, -T * foam_speed);
	foam_uv += vec2(floor(vh * 7.0), floor(fract(vh * 13.0) * 5.0));
	if (vh > 0.5) {
		foam_uv.x = -foam_uv.x;          // 一半格子镜像，变体感更强
	}
	float foam_pat = texture(foam_mask_tex, foam_uv).a;   // 已经是 0/1 的硬边像素
	float foam_zone = smoothstep(0.42, 0.70, blurred)
			* (1.0 - smoothstep(0.0, 2.8, d));
	// 一圈圈往岸上推：整条带的强度跟着时间脉动。
	// 相位按位置错开——否则整圈海岸线会同时冒出来、同时消失，假得离谱。
	// 一圈圈往岸上推：相位在 0.5 步就按位置错开过了，各段自己走
	float wave = 0.5 + 0.5 * sin(Tq * 0.9 - d * 0.85 + phase);
	// 硬边：像素风的浪花是实心的白块，不是半透明的一层雾
	float foam = step(0.16, foam_zone * wave) * foam_pat;

	// ③ 崖壁：浪是「撞」上去的，和沙滩那套完全不一样
	//    · 贴得更近、带子更窄（撞在岩壁上，不会铺开）
	//    · 节奏更快、更爆（burst 用高频正弦）
	//    · 纹理纵向拉长（溅起来的水柱/白沫）
	//    mask.b 是烘焙出来的岸型：0 = 沙滩，1 = 崖壁
	vec2 splash_uv = vec2(fwp.x / splash_scale, fwp.y / (splash_scale * 0.42));
	splash_uv += vec2(floor(vh * 5.0), -Tq * 0.55);
	float splash = texture(foam_mask_tex, splash_uv).a;
	float burst = 0.5 + 0.5 * sin(Tq * 3.2 + phase * 2.0);
	// 撞在水线上的白沫
	float cliff_band = 1.0 - smoothstep(0.0, 1.7, abs(d - 0.25));
	float foam_cliff = step(0.28, cliff_band * burst) * splash;
	foam = mix(foam, foam_cliff, cliff);

	// ③ 白色描边：贴着水线的白线，不是"岸边浅色环"。
	//    和浅↔深的过渡是两件事：过渡在水体内部（靠 water_col 的 mix），描边只在水线上。
	float rim = (1.0 - smoothstep(0.0, max(rim_width, 0.001), d)) * step(0.0, d);

	// ── 6. 合成 ──────────────────────────────────────────────────
	vec3 night_base = mix(night_shallow.rgb, night_deep.rgb, depth_t);
	vec3 col = mix(base * environment_tint.rgb, night_base, night_amount);
	vec3 light_tint = mix(environment_tint.rgb, vec3(0.36, 0.27, 0.18), night_amount);
	col += col_caustics.rgb * light_tint * caus * caustics_strength * water * mix(1.0, night_caustics, night_amount);
	col += col_highlight.rgb * light_tint * sparkle * crest * hl_strength * water * mix(1.0, night_highlight, night_amount);
	col = mix(col, col_foam.rgb * light_tint, clamp(foam * foam_opacity * water, 0.0, 1.0));
	col = mix(col, col_rim.rgb * light_tint, rim * rim_strength);
	col = mix(col, vec3(1.0, 0.0, 0.0), cliff * debug_cliff * 0.7);

	// 只输出水体；原始岸线之外完全透明，陆地由背景图负责。
	float water_mask = step(0.0, d_e) * mask.a;
	float alpha = max(water, rim * rim_strength) * water_mask;
	COLOR = vec4(col, alpha);
}
