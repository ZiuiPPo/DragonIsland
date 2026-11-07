shader_type canvas_item;
render_mode unshaded, blend_mul;

// Original photos are keyed directly: no AI-redrawn silhouettes.
uniform sampler2D reference_0 : repeat_disable, filter_linear;
uniform sampler2D reference_1 : repeat_disable, filter_linear;
uniform sampler2D reference_2 : repeat_disable, filter_linear;
uniform sampler2D reference_3 : repeat_disable, filter_linear;
uniform sampler2D reference_4 : repeat_disable, filter_linear;
uniform sampler2D reference_5 : repeat_disable, filter_linear;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec4 cloud_color : source_color = vec4(0.46, 0.46, 0.46, 0.24);
uniform float coverage : hint_range(0.0, 1.0) = 0.55;
uniform float spacing : hint_range(400.0, 1200.0) = 580.0;
// Stable random scale per cloud: 1x to 3x the 180-unit world-space base size.
uniform vec2 size_range = vec2(180.0, 540.0);
uniform float edge_blur : hint_range(0.0, 0.08) = 0.04;
// World-space pixel grid; 0 disables pixelation.
uniform float pixel_size : hint_range(0.0, 8.0, 0.5) = 4.0;
uniform vec2 wind = vec2(12.0, 4.0);
uniform float edge_noise : hint_range(0.0, 0.06) = 0.018;
uniform float rotation_range : hint_range(0.0, 180.0) = 65.0;
uniform vec2 camera_origin = vec2(0.0);
uniform vec2 camera_axis_x = vec2(1.0, 0.0);
uniform vec2 camera_axis_y = vec2(0.0, 1.0);
uniform vec2 noise_offset = vec2(0.0);
uniform float elapsed = 0.0;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 reference_color(int frame, vec2 uv) {
    if (frame == 0) { return texture(reference_0, uv).rgb; }
    if (frame == 1) { return texture(reference_1, uv).rgb; }
    if (frame == 2) { return texture(reference_2, uv).rgb; }
    if (frame == 3) { return texture(reference_3, vec2(uv.x, mix(0.022, 0.98, uv.y))).rgb; }
    if (frame == 4) { return texture(reference_4, uv).rgb; }
    return texture(reference_5, uv).rgb;
}

float keyed_mask(int frame, vec2 uv) {
    vec3 c = reference_color(frame, clamp(uv, vec2(0.0), vec2(1.0)));
    // Yellow/brown body, green eyes and dark mouth are foreground.
    // Neutral white/gray backgrounds and ground shadows disappear.
    float chroma = max(c.r, c.g) - c.b;
    // The second reference has a warm gray backdrop, requiring a stronger key.
    float body = frame == 1 ? smoothstep(0.15, 0.23, chroma) : smoothstep(0.035, 0.085, chroma);
    float dark = 1.0 - smoothstep(0.18, 0.28, max(c.r, max(c.g, c.b)));
    float bounds = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
    // Soften cropped photo borders before blur, so no hard rectangle is reintroduced.
    vec2 border = smoothstep(vec2(0.0), vec2(0.045), uv) * (vec2(1.0) - smoothstep(vec2(0.955), vec2(1.0), uv));
    return max(body, dark) * bounds * border.x * border.y;
}

float blur_weight(int offset) {
    int distance = abs(offset);
    if (distance == 0) { return 6.0; }
    if (distance == 1) { return 4.0; }
    return 1.0;
}

float blurred_mask(int frame, vec2 uv, vec2 pixel_step) {
    // Normalized 5x5 Gaussian approximation, applied to the grayscale mask.
    float result = 0.0;
    for (int by = -2; by <= 2; by++) {
        for (int bx = -2; bx <= 2; bx++) {
            result += keyed_mask(frame, uv + vec2(float(bx), float(by)) * pixel_step)
                * blur_weight(bx) * blur_weight(by);
        }
    }
    return result / 256.0;
}

float aspect(int frame) {
    if (frame == 0) { return 1080.0 / 1110.0; }
    if (frame == 1) { return 1086.0 / 960.0; }
    if (frame == 2) { return 607.0 / 750.0; }
    if (frame == 3) { return 627.0 / 645.0; }
    if (frame == 4) { return 1080.0 / 1062.0; }
    return 1080.0 / 1058.0;
}

void fragment() {
    vec2 world = camera_origin + FRAGCOORD.x * camera_axis_x + FRAGCOORD.y * camera_axis_y;
    // Sample mask and density on the same world-anchored pixel grid.
    if (pixel_size > 0.0) {
        world = (floor(world / pixel_size) + vec2(0.5)) * pixel_size;
    }
    // Integrated gust displacement varies speed without abrupt time-dependent jumps.
    vec2 gust = vec2(sin(elapsed * 0.065), sin(elapsed * 0.043 + 1.2)) * vec2(45.0, 32.0);
    vec2 p = (world - wind * elapsed - gust) / spacing + noise_offset * 100.0;
    vec2 cell = floor(p);
    float mask = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 id = cell + vec2(float(x), float(y));
            if (hash(id + 19.7) < coverage) {
                float phase = hash(id + 41.0) * 6.283185;
                float rate = mix(0.04, 0.085, hash(id + 22.0));
                vec2 sway = vec2(sin(elapsed * rate + phase), cos(elapsed * rate * 0.71 + phase)) * 0.085;
                vec2 center = id + vec2(0.25) + vec2(hash(id), hash(id + 4.3)) * 0.5 + sway;
                float size = mix(size_range.x, size_range.y, hash(id + 8.1));
                vec2 local = (p - center) * spacing / size;
                // Cull before sampling noise or reference images.
                if (length(local) < 0.9) {
                    int frame = int(floor(hash(id + 12.5) * 6.0));
                    float angle = (hash(id + 31.0) * 2.0 - 1.0) * radians(rotation_range);
                    angle += sin(elapsed * rate * 0.55 + phase) * radians(7.0);
                    float c = cos(angle);
                    float s = sin(angle);
                    vec2 uv = vec2(c * local.x + s * local.y, -s * local.x + c * local.y);
                    float ratio = aspect(frame);
                    vec2 proportions = vec2(min(ratio, 1.0), min(1.0 / ratio, 1.0));
                    uv /= proportions;
                    uv += 0.5;
                    // Cloud-local noise stays fixed while the whole cloud moves and rotates.
                    vec2 flow = uv * 1.9 + id * 0.37;
                    float n = texture(noise_tex, flow).r;
                    float fine = texture(noise_tex, flow * 3.1).r;
                    vec2 warp = vec2(n - 0.5, texture(noise_tex, flow + 0.43).r - 0.5) * edge_noise * 2.0;
                    uv += warp;
                    float radius = edge_blur * mix(0.85, 1.15, fine);
                    float shape = blurred_mask(frame, uv, vec2(radius * 0.5) / proportions);
                    float density = mix(0.42, 1.0, smoothstep(0.25, 0.75, n * 0.65 + fine * 0.35));
                    mask = max(mask, shape * density);
                }
            }
        }
    }
    COLOR = vec4(mix(vec3(1.0), cloud_color.rgb, mask * cloud_color.a), 1.0);
}
