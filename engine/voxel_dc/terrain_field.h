#ifndef TERRAIN_FIELD_H
#define TERRAIN_FIELD_H

// The procedural terrain as a fine analytic SDF field, evaluable per-point on a worker
// thread — the "fine everywhere" the octree substrate needs (no godot_voxel mips, so a
// coarse octree cell accumulates from genuinely fine data; that's where the geomorph
// blend dies). Mirrors tools/build_terrain_graph.gd exactly:
//
//   surface = base + amp * ridgedNoise(x, z)      (OpenSimplex2, freq = 1/period)
//   SDF     = y - surface                          (negative below ground = solid)
//
// Uses the SAME FastNoiseLite godot_voxel's graph node does (period -> 1/frequency,
// FRACTAL_RIDGED), so octree-meshed terrain matches godot_voxel-streamed terrain while
// the two coexist. Parameterised so it stays the single tunable generator once the
// .tres graph retires.

#include "sdf_field.h"
#include "modules/voxel/thirdparty/fast_noise/FastNoiseLite.h"

namespace voxel_dc {

struct TerrainField : public Field {
	fast_noise_lite::FastNoiseLite noise;
	double base;
	double amp;

	TerrainField(double p_base, double p_amp, double period, int octaves, int seed) :
			base(p_base), amp(p_amp) {
		noise.SetSeed(seed);
		noise.SetNoiseType(fast_noise_lite::FastNoiseLite::NoiseType_OpenSimplex2);
		noise.SetFrequency(float(1.0 / period));
		noise.SetFractalType(fast_noise_lite::FastNoiseLite::FractalType_Ridged);
		noise.SetFractalOctaves(octaves);
	}

	double surface(double x, double z) const {
		return base + amp * double(noise.GetNoise(float(x), float(z)));
	}

	double sample(const Vector3 &p) const override {
		return p.y - surface(p.x, p.z);
	}
};

} // namespace voxel_dc

#endif // TERRAIN_FIELD_H
