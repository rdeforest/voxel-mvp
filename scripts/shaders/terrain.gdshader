shader_type spatial;
render_mode cull_back;

// Slope-aware ground material: grass on shallow slopes (≤30°), dirt on
// steeper ones. Grass colour is modulated by two-octave value noise
// sampled at world XZ + TIME so the surface looks like wind is blowing
// across it without actually deforming the Transvoxel mesh.

uniform vec3  grass_color    : source_color = vec3(0.35, 0.55, 0.22);
uniform vec3  dirt_color     : source_color = vec3(0.42, 0.32, 0.20);
uniform vec3  rock_color     : source_color = vec3(0.46, 0.46, 0.48);

// Slope mask in cos(angle) space. cos(30°) ≈ 0.866; the transition band
// from full-dirt to full-grass spans roughly 25°–35°.
uniform float slope_dirt_max : hint_range(0.0, 1.0) = 0.82;   // ≥35°  → full dirt
uniform float slope_grass_min: hint_range(0.0, 1.0) = 0.91;   // ≤25°  → full grass

// Rock on the heights and the cliffs. Above rock_line (in a band) the surface turns to
// rock; very steep faces turn to rock at any altitude (rock_slope_cos in cos space — a
// smaller cos = steeper). Tunable live: `set rock_line 50`, `set rock_band 12`, etc.
uniform float rock_line      = 60.0;                          // altitude (m) where rock takes over
uniform float rock_band      : hint_range(0.5, 60.0) = 14.0;  // blend thickness around rock_line
uniform float rock_slope_cos : hint_range(0.0, 1.0)  = 0.55;  // faces steeper than this → rock
uniform float rock_slope_soft: hint_range(0.0, 1.0)  = 0.20;  // steepness blend width

// Sarsen-stone detail for natural rock (Stonehenge look): triplanar value mottle + a warm buff
// undertone + Worley-cell lichen blotches + crevice darkening. Computed only on rock pixels.
// All world-space (sticks to surfaces, survives the wash as mid-frequency mottle).
uniform float rock_mottle_scale : hint_range(0.05, 3.0) = 0.7;   // 1/scale ≈ blotch size in metres
uniform float rock_warmth       : hint_range(0.0, 1.0) = 0.40;   // buff/tan undertone strength
uniform float rock_lichen       : hint_range(0.0, 1.0) = 0.35;   // fraction of cells bearing lichen
uniform float rock_crevice      : hint_range(0.0, 1.0) = 0.35;   // darkening in the pits (fake AO)
uniform vec3  rock_lichen_green : source_color = vec3(0.52, 0.56, 0.42);  // pale grey-green lichen
uniform vec3  rock_lichen_ochre : source_color = vec3(0.62, 0.55, 0.36);  // ochre / rust lichen

uniform float wave_scale     : hint_range(0.01, 5.0) = 1.4;   // base frequency; larger = denser pattern
uniform float wave_speed     : hint_range(0.0, 10.0) = 0.9;
uniform float wave_amount    : hint_range(0.0, 1.0) = 0.40;   // brightness modulation depth
uniform float hue_amount     : hint_range(0.0, 1.0) = 0.18;   // green-tint variation
uniform vec2  wave_dir                              = vec2(0.7, 0.3);

uniform float roughness      : hint_range(0.0, 1.0) = 0.9;

// Grain on PLACED-material surfaces (wood, etc.) so a log reads as wood, not a flat colour.
// World-space + static; anisotropic (fine across, coarse along) so it forms grain LINES. Subtle
// defaults — tune live with `set grain_amount` / `set grain_scale`. (First pass; orientation is
// world-space since the shader doesn't know the log's axis — grain runs along world Z.)
uniform float grain_amount   : hint_range(0.0, 1.0) = 0.18;  // brightness striation depth
uniform float grain_scale    : hint_range(0.1, 12.0) = 4.0;  // grain frequency

// --- Watercolour spike (line-and-wash). Toggle: `set wc_enable 1`. All tunable live. ---
// The wash half: flatten to bands, lift toward paper white (dilution), WORLD-ANCHORED paper-tooth
// granulation + pigment turbulence (so the paint sticks to the world, not the screen — the
// temporal-coherence test), and edge-darkening (pigment pools at silhouettes). Rendered unshaded
// (EMISSION) so the white paper is the light. The ink lines + vignette are a separate post-process.
uniform float wc_enable      : hint_range(0.0, 1.0) = 0.0;
uniform vec3  wc_paper_color : source_color = vec3(0.96, 0.95, 0.91);
uniform float wc_dilute      : hint_range(0.0, 1.0) = 0.28;   // lift toward paper white
uniform float wc_desat       : hint_range(0.0, 1.0) = 0.20;   // pull toward grey (washy)
uniform float wc_bands       : hint_range(1.0, 8.0) = 4.0;    // value quantisation (flat washes)
uniform float wc_paper_scale : hint_range(0.1, 16.0) = 6.0;   // paper-tooth frequency (world units)
uniform float wc_granulate   : hint_range(0.0, 1.0) = 0.18;   // pigment-on-tooth density variation
uniform float wc_turb_scale  : hint_range(0.05, 4.0) = 0.5;   // low-freq pigment turbulence frequency
uniform float wc_turb        : hint_range(0.0, 1.0) = 0.14;   // turbulence depth
uniform float wc_edge        : hint_range(0.0, 1.0) = 0.45;   // edge-darkening (silhouette pooling)
uniform float wc_edge_start  : hint_range(0.0, 1.0) = 0.45;   // fresnel threshold for the pooling
// Grass sprigs (loose drawn green marks on grass; denser where the ground tilts up).
uniform float wc_sprig_amount: hint_range(0.0, 1.0) = 0.5;    // mark strength (0 = off)
uniform float wc_sprig_freq  : hint_range(0.2, 10.0) = 2.5;   // mark frequency (size)
uniform float wc_sprig_patch : hint_range(0.05, 2.0) = 0.4;   // patch sparseness (lower = sparser)
uniform float wc_sprig_flat  : hint_range(0.0, 1.0) = 0.3;    // fraction of marks on FLAT ground vs rises
uniform vec3  wc_sprig_color : source_color = vec3(0.16, 0.30, 0.12);
// Watercolour reflectance (paper §3.2): cangiante = highlights shift to a brighter HUE (not just
// white); light-driven dilution = more bare paper shows where the surface faces the light.
uniform float wc_paper_mode  : hint_range(0.0, 3.0) = 1.0;    // 0 none, 1 screen noise, 2 world noise, 3 texture
uniform sampler2D wc_paper_tex : repeat_enable, filter_linear_mipmap;  // substrate texture (mode 3)
uniform vec3  wc_light_dir                          = vec3(0.4, -0.85, 0.35);  // light direction
uniform vec3  wc_cangiante   : source_color = vec3(1.0, 0.96, 0.72);  // highlight hue-shift target
uniform float wc_cangiante_amt : hint_range(0.0, 1.0) = 0.0;  // hue-shift strength in highlights (0=off)
uniform float wc_dilute_light  : hint_range(0.0, 1.0) = 0.0;  // extra paper-lift where lit (0=off)

// Debug: blend each triangle's per-LOD colour (vertex COLOR from the DC mesher)
// over the grass/dirt material. 0 = off, 1 = full. Console: set debug_lod 0.3
uniform float debug_lod      : hint_range(0.0, 1.0) = 0.0;

// Debug: when on, show the surface NORMAL as an unlit colour (xyz -> rgb,
// [-1,1] mapped to [0,1]). A correct terrain normal is mostly green (+Y up);
// black/very-dark patches are degenerate normals. Console: set debug_normal 1
uniform float debug_normal   : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;


// Non-periodic hash (Dave Hoskins, hash22). The old sin(p)*43758 hash visibly TILES (a repeating
// ~50px pattern showed in the screen-space paper at distance); this one has no sine period.
vec2 hash2(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return -1.0 + 2.0 * fract((p3.xx + p3.yz) * p3.zy);
}

// Gradient (Perlin-ish) noise. No axis-aligned grid artefacts the way
// value_noise has — the per-cell gradients break the squareness.
float gnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
            dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
        mix(dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
            dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x),
        u.y);
}

// Plain 4-octave fbm of gnoise, remapped to [0,1]. (gnoise sums to ±0.9375 over 4 octaves.)
float fbm2(vec2 p) {
    float total = 0.0;
    float amp   = 0.5;
    for (int i = 0; i < 4; i++) {
        total += amp * gnoise(p);
        p     *= 2.03;
        amp   *= 0.5;
    }
    return 0.5 + 0.5 * total / 0.9375;
}

// Triplanar fbm: blend three planar fbms by the world normal, so it doesn't stretch on cliffs.
float triplanar_fbm(vec3 p, vec3 n) {
    vec3 an = abs(n); an /= (an.x + an.y + an.z + 1e-4);
    return an.x * fbm2(p.yz) + an.y * fbm2(p.xz) + an.z * fbm2(p.xy);
}

// 3D hash for the Worley cells.
vec3 hash33(vec3 p) {
    p = fract(p * vec3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

// Worley (cellular) noise: nearest feature-point distance + a per-cell id. Used for lichen blotches
// — the id picks a tint per cell, the distance gives a soft blotch core. 3D so it wraps cliffs.
vec2 worley3(vec3 p) {
    vec3 ip = floor(p);
    vec3 fp = fract(p);
    float f1 = 1e9;
    vec3 wcell = vec3(0.0);
    for (int x = -1; x <= 1; x++)
    for (int y = -1; y <= 1; y++)
    for (int z = -1; z <= 1; z++) {
        vec3 g = vec3(float(x), float(y), float(z));
        vec3 d = g + hash33(ip + g) - fp;
        float dist = dot(d, d);
        if (dist < f1) { f1 = dist; wcell = ip + g; }
    }
    float id = fract(sin(dot(wcell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
    return vec2(sqrt(f1), id);
}

// Sarsen-stone albedo: warm-grey value mottle + lichen blotches + crevice darkening.
vec3 sarsen_rock(vec3 wp, vec3 wn) {
    // Broad value variation around the base grey (large blotches).
    float v = triplanar_fbm(wp * rock_mottle_scale * 0.5, wn);
    vec3 base = rock_color * (0.78 + 0.44 * v);
    base = mix(base, base * vec3(1.12, 1.04, 0.86), rock_warmth * v);   // warm buff in the mids

    // Lichen: per-cell tint, soft-cored, on a fraction of cells.
    vec2 w = worley3(wp * rock_mottle_scale);
    float covered = step(1.0 - rock_lichen, w.y);          // this cell bears lichen?
    float blotch  = covered * (1.0 - smoothstep(0.0, 0.35, w.x));
    vec3 lichen   = mix(rock_lichen_green, rock_lichen_ochre, step(0.5, fract(w.y * 7.0)));
    base = mix(base, lichen, blotch * 0.8);

    // Crevice darkening (fake AO from a finer fbm pooling in the low spots).
    float crev = triplanar_fbm(wp * rock_mottle_scale * 2.0, wn);
    base *= 1.0 - rock_crevice * smoothstep(0.6, 0.0, crev);
    return base;
}

// 4-octave fbm with per-octave rotation and direction variation, so the
// pattern doesn't read as a single sliding texture.
float wind_fbm(vec2 p, vec2 dir, float t) {
    const mat2 R = mat2(vec2( 0.80, -0.60), vec2(0.60, 0.80));   // ~37° rotation
    float total = 0.0;
    float amp   = 0.55;
    float norm  = 0.0;
    // Each octave: rotate coords, shift by direction-perturbed motion.
    for (int i = 0; i < 4; i++) {
        float fi   = float(i);
        vec2  flow = dir + 0.25 * vec2(sin(fi * 1.7), cos(fi * 2.3));
        total += gnoise(p + flow * t) * amp;
        norm  += amp;
        p      = R * p * 2.07;     // 2x freq with rotation — kills axis alignment
        amp   *= 0.55;
    }
    return 0.5 + 0.5 * (total / norm);   // remap [-1,1] → [0,1]
}


void vertex() {
    v_world_pos    = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    v_world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}


void fragment() {
    float slope_cos  = clamp(v_world_normal.y, 0.0, 1.0);
    float grass_mask = smoothstep(slope_dirt_max, slope_grass_min, slope_cos);

    vec2 wp    = v_world_pos.xz * wave_scale;
    // Watercolour mode freezes the animation (TIME -> 0): the moving wave reads as rippling water,
    // not grass. Static, it's just mottled pigment variation. (Sprigs of grass are a separate pass.)
    float wave = wind_fbm(wp, wave_dir, TIME * wave_speed * (1.0 - wc_enable));

    // Brightness modulation + small hue shift in the green channel so the
    // grass varies between slightly warmer and cooler greens, not just
    // light/dark of one colour.
    float bright = 1.0 - wave_amount + wave * wave_amount * 2.0;
    vec3 grass   = grass_color * bright;
    grass.g     += hue_amount * (wave - 0.5);

    vec3 albedo = mix(dirt_color, grass, grass_mask);

    // Rock on the heights and steep cliffs (procedural terrain material — altitude+slope,
    // so it works at every LOD). Mountains are high AND steep, so either pushes toward rock.
    float rock_alt   = smoothstep(rock_line - rock_band, rock_line + rock_band, v_world_pos.y);
    float rock_steep = smoothstep(rock_slope_cos + rock_slope_soft, rock_slope_cos - rock_slope_soft, slope_cos);
    float rock_mask  = max(rock_alt, rock_steep);
    vec3 rock = rock_color;
    if (rock_mask > 0.001) rock = sarsen_rock(v_world_pos, v_world_normal);  // sarsen only on rock pixels
    albedo = mix(albedo, rock, rock_mask);

    // Per-voxel material (from the DC mesher's CHANNEL_INDICES sampling): COLOR.a
    // near 0 marks a vertex carrying an explicit material colour (a CSG stamp), so
    // use COLOR.rgb instead of slope shading. a near 1 (natural terrain, and the
    // default for meshes that emit no vertex colour) keeps the grass/dirt look.
    float material_mask = 1.0 - step(0.5, COLOR.a);
    albedo = mix(albedo, COLOR.rgb, material_mask);

    // Wood/material grain: anisotropic static noise → grain lines; modulate brightness on placed-
    // material surfaces only (natural terrain unaffected) so wood reads as wood, not flat colour.
    vec2 guv = v_world_pos.xz * vec2(grain_scale, grain_scale * 0.12) + vec2(v_world_pos.y * grain_scale * 0.5, 0.0);
    float grain = 0.5 + 0.5 * gnoise(guv);
    float grain_b = 1.0 - grain_amount + grain * grain_amount * 2.0;
    albedo *= mix(1.0, grain_b, material_mask);

    ROUGHNESS = roughness;

    if (wc_enable > 0.5) {
        // --- Watercolour wash (unshaded; the white paper is the light) ---
        vec3 wc = albedo;
        float ndl = clamp(dot(normalize(v_world_normal), normalize(-wc_light_dir)), 0.0, 1.0);
        float lum = dot(wc, vec3(0.299, 0.587, 0.114));
        wc = mix(wc, vec3(lum), wc_desat);                 // desaturate toward washy grey
        wc = mix(wc, wc_cangiante, ndl * wc_cangiante_amt); // cangiante: highlights shift to a brighter hue
        wc = mix(wc, wc_paper_color, clamp(wc_dilute + ndl * wc_dilute_light, 0.0, 1.0)); // dilution (more where lit)
        // Flatten into a few wash bands (quantise value, keep hue).
        float lw = max(dot(wc, vec3(0.299, 0.587, 0.114)), 1e-3);
        wc *= (floor(lw * wc_bands + 0.5) / wc_bands) / lw;
        // Paper tooth: NONE / SCREEN noise / WORLD noise / TEXTURE (wc_paper_mode 0/1/2/3).
        // Screen = a fixed sheet you draw ON (paint stays put as you move — the "dream" look);
        // World = the tooth sticks to surfaces (shower-door gone but it reads as papercraft);
        // Texture = a real scanned paper sheet sampled in screen-space (mode 1's look, real grain);
        // None = off. Larger wc_paper_scale = coarser tooth in all modes.
        if (wc_paper_mode > 0.5) {
            float paper;
            if (wc_paper_mode < 1.5) {
                paper = gnoise(SCREEN_UV * VIEWPORT_SIZE / max(wc_paper_scale, 0.1));   // screen sheet
            } else if (wc_paper_mode < 2.5) {
                float wf = 4.0 / max(wc_paper_scale, 0.1);                              // world freq
                vec3 an = abs(v_world_normal); an /= (an.x + an.y + an.z + 1e-4);
                paper = an.x * gnoise(v_world_pos.yz * wf)
                      + an.y * gnoise(v_world_pos.xz * wf)
                      + an.z * gnoise(v_world_pos.xy * wf);                             // world triplanar
                paper = 0.5 + 0.5 * paper;
            } else {
                // Real scanned-paper sheet, screen-space. Tile so wc_paper_scale reads like the
                // noise modes: larger = coarser grain. Centre on 0 so granulate darkens/lightens.
                vec2 pt_uv = SCREEN_UV * VIEWPORT_SIZE / max(wc_paper_scale * 16.0, 0.1);
                paper = texture(wc_paper_tex, pt_uv).r;                                 // luminance tooth
            }
            if (wc_paper_mode < 1.5) paper = 0.5 + 0.5 * paper;                         // screen noise → [0,1]
            wc *= 1.0 - wc_granulate + paper * wc_granulate * 2.0;
        }
        // Pigment COLOUR turbulence stays WORLD-space — the splotches stick to surfaces and
        // emphasise depth (this is the half that should follow the world, not the screen).
        float turb = 0.5 + 0.5 * gnoise(v_world_pos.xz * wc_turb_scale);
        wc *= 1.0 - wc_turb + turb * wc_turb * 2.0;
        // Grass sprigs: loose drawn green marks on grass. World-anchored XZ-anisotropic streaks
        // (clumpy strokes), thinned to a threshold so they read as separate marks, gated by the
        // grass mask + a sparse patch noise (so they're sprigs, not a lawn), and denser where the
        // ground tilts up (slope_cos drops) — roughly the base of things rising out of the grass.
        // (Not standing blades — that needs geometry; these are the gestural marks of line-and-wash.)
        if (wc_sprig_amount > 0.001 && grass_mask > 0.01) {
            float streak = gnoise(v_world_pos.xz * vec2(wc_sprig_freq, wc_sprig_freq * 0.35));
            streak = smoothstep(0.15, 0.45, 0.5 + 0.5 * streak);
            float patch = smoothstep(0.45, 0.85, 0.5 + 0.5 * gnoise(v_world_pos.xz * wc_sprig_patch));
            float rise  = mix(wc_sprig_flat, 1.0, smoothstep(0.98, 0.72, slope_cos));
            float spr   = clamp(streak * patch * grass_mask * rise * wc_sprig_amount, 0.0, 1.0);
            wc = mix(wc, wc_sprig_color, spr);
        }
        // Edge darkening: pigment pools at silhouettes (grazing angle = fresnel).
        float fres = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
        wc *= 1.0 - wc_edge * smoothstep(wc_edge_start, 1.0, fres);
        ALBEDO   = vec3(0.0);
        EMISSION = wc;
    } else {
        // debug_lod blends the per-LOD colour over the material (console: set debug_lod 0.3).
        ALBEDO   = mix(albedo, COLOR.rgb, debug_lod);
        // Normal visualiser: unlit, so a bad normal can't hide behind lighting.
        ALBEDO   = mix(ALBEDO, vec3(0.0), debug_normal);
        EMISSION = (v_world_normal * 0.5 + 0.5) * debug_normal;
    }
}
