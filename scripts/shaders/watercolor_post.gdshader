shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, ambient_light_disabled;

// Line-and-wash post-process (the "line" half + the vignette): a fullscreen quad that reads the
// rendered frame, draws INK at depth/normal discontinuities (silhouettes + creases) with a hand-
// tremor wobble, and fades the whole composite to bare PAPER at the screen periphery (vignette).
// Runs after the watercolour wash in the terrain material, so together they read as line-and-wash.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex  : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;

uniform float ink_enable     : hint_range(0.0, 1.0) = 1.0;
uniform vec3  ink_color      : source_color = vec3(0.13, 0.11, 0.15);
uniform float ink_depth_sens : hint_range(0.0, 60.0) = 14.0;  // depth-discontinuity weight (relative)
uniform float ink_normal_sens: hint_range(0.0, 6.0)  = 1.4;   // crease (normal-discontinuity) weight
uniform float ink_thresh     : hint_range(0.0, 2.0)  = 0.40;  // edge cutoff
uniform float ink_gain       : hint_range(0.5, 12.0) = 4.0;   // line hardness
uniform float ink_tremor     : hint_range(0.0, 6.0)  = 1.6;   // hand-tremor wobble (px)
uniform float ink_width      : hint_range(0.5, 4.0)  = 1.2;   // sample step (px) — line thickness

uniform float vig_enable     : hint_range(0.0, 1.0) = 1.0;
uniform vec3  vig_paper      : source_color = vec3(0.97, 0.96, 0.93);
uniform float vig_inner      : hint_range(0.0, 1.5) = 0.62;   // where the fade begins
uniform float vig_outer      : hint_range(0.0, 1.5) = 1.05;   // where it reaches full paper
uniform float vig_round      : hint_range(0.0, 1.0) = 0.5;    // 0 = hard rectangle, 1 = circle;
                                                             // rounds the corners so diagonals fade
                                                             // at the same rate as the edges

float h21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void vertex() {
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);   // fullscreen clip-space quad (ignores transform)
}

float lin_depth(vec2 uv, mat4 inv_proj) {
    float d = texture(depth_tex, uv).r;
    vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
    return -(v.z / v.w);
}

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 ts = (1.0 / VIEWPORT_SIZE) * ink_width;

    // Hand tremor: wobble the sampling cross by a little noise so lines aren't ruler-straight.
    vec2 wob = (vec2(h21(uv * VIEWPORT_SIZE), h21(uv * VIEWPORT_SIZE + 7.3)) - 0.5) * ink_tremor * ts;
    vec2 c = uv + wob;

    // Depth edges (relative Roberts cross — normalise by depth so far geometry isn't all edge).
    float dc = lin_depth(c, INV_PROJECTION_MATRIX);
    float dr = lin_depth(c + vec2(ts.x, 0.0), INV_PROJECTION_MATRIX);
    float dd = lin_depth(c + vec2(0.0, ts.y), INV_PROJECTION_MATRIX);
    float ddg = lin_depth(c + ts, INV_PROJECTION_MATRIX);
    float depth_edge = (abs(dc - ddg) + abs(dr - dd)) / max(dc, 1.0);

    // Normal edges (creases). normal_rough is encoded [0,1]; decode to [-1,1].
    vec3 nc = texture(normal_tex, c).xyz * 2.0 - 1.0;
    vec3 nr = texture(normal_tex, c + vec2(ts.x, 0.0)).xyz * 2.0 - 1.0;
    vec3 nd = texture(normal_tex, c + vec2(0.0, ts.y)).xyz * 2.0 - 1.0;
    float normal_edge = (1.0 - dot(nc, nr)) + (1.0 - dot(nc, nd));

    float e = depth_edge * ink_depth_sens + normal_edge * ink_normal_sens;
    float ink = clamp((e - ink_thresh) * ink_gain, 0.0, 1.0) * ink_enable;

    vec3 base = texture(screen_tex, uv).rgb;

    // Vignette fades only the WASH to paper, as a RECTANGLE (the paper edge), not a circle.
    if (vig_enable > 0.5) {
        vec2 d = abs(uv - vec2(0.5)) * 2.0;    // 0 at centre .. 1 at the nearest screen edge
        float vr = mix(max(d.x, d.y), length(d), vig_round);   // rectangle .. circle; rounds corners
        base = mix(base, vig_paper, smoothstep(vig_inner, vig_outer, vr));
    }

    // Ink is drawn ON TOP of the faded wash, so an object's OUTLINE keeps drawing past the fade
    // into the paper margin (line-and-wash: the line extends where the colour has washed out).
    vec3 col = mix(base, ink_color, ink);

    ALBEDO = col;   // unshaded → ALBEDO is the final colour (EMISSION does NOT apply when unshaded)
}
