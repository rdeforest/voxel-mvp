// Examine-mode terrain material. cull_disabled renders BOTH sides, so a triangle that
// faces away from you still draws — coloured magenta (its back) and self-lit so it reads
// even in shadow. Front faces stay neutral grey with normal lighting so the surface shape
// is legible. Use it to tell a BACKWARDS triangle (gap fills with magenta) from a MISSING
// one (gap stays see-through). Toggled by the `examine` console command.
shader_type spatial;
render_mode cull_disabled;

void fragment() {
	if (FRONT_FACING) {
		ALBEDO = vec3(0.55, 0.57, 0.60);
	} else {
		ALBEDO = vec3(1.0, 0.0, 1.0);
		EMISSION = vec3(0.8, 0.0, 0.8);
	}
}
