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

// Canonical terrain params (mirror tools/build_terrain_graph.gd). The C++ field is the
// home now; the .tres graph is the legacy mirror until godot_voxel retires.
namespace terrain_defaults {
constexpr double BASE = 30.0;
constexpr double AMP = 140.0;
constexpr double PERIOD = 1000.0;
constexpr int OCTAVES = 2;
constexpr int SEED = 1337;
// Bedrock band: solid deeper than this many metres BELOW THE LOCAL SURFACE (not an absolute Z —
// it follows the terrain, so there's no world-space floor plane) is Bedrock, perturbed by ±VARY
// so the boundary isn't a flat shell. A material property of the world, tunable like any other.
constexpr double BEDROCK_DEPTH = 50.0;
constexpr double BEDROCK_VARY = 14.0;
} // namespace terrain_defaults

// Generator material ids. MUST match MaterialPalette (scripts/material_palette.gd): 0 = Natural
// (slope-shaded), 6 = Bedrock.
constexpr int MATERIAL_NATURAL = 0;
constexpr int MATERIAL_BEDROCK = 6;

struct TerrainField : public Field {
	fast_noise_lite::FastNoiseLite noise;
	double base;
	double amp;
	double bedrock_depth = terrain_defaults::BEDROCK_DEPTH;
	double bedrock_vary = terrain_defaults::BEDROCK_VARY;

	TerrainField() :
			TerrainField(terrain_defaults::BASE, terrain_defaults::AMP, terrain_defaults::PERIOD,
					terrain_defaults::OCTAVES, terrain_defaults::SEED) {}

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

	// Generator material at a point: Bedrock once it's deeper than the (noise-perturbed) bedrock
	// depth below the local surface, else Natural. Air returns Natural (unused — air has no
	// surface). The flood-to-ground trigger treats Bedrock as ground.
	int material(const Vector3 &p) const {
		const double depth = surface(p.x, p.z) - p.y; // >0 inside solid
		if (depth <= 0.0) {
			return MATERIAL_NATURAL;
		}
		const double vary = bedrock_vary * double(noise.GetNoise(float(p.x) * 0.3f + 1000.0f, float(p.z) * 0.3f + 1000.0f));
		return depth >= bedrock_depth + vary ? MATERIAL_BEDROCK : MATERIAL_NATURAL;
	}
};

} // namespace voxel_dc

#endif // TERRAIN_FIELD_H
