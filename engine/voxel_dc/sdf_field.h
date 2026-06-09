#ifndef SDF_FIELD_H
#define SDF_FIELD_H

// A signed-distance field source the octree imprints/samples — C++-native so it can be
// evaluated on the mesher's worker thread (a GDScript field-closure can't). Concrete
// fields: analytic shapes now (CSG brushes); a procedural-generator-backed field and a
// combine field (existing op brush) come with the edit + terrain integration.

#include "core/math/math_funcs.h"
#include "core/math/vector3.h"

namespace voxel_dc {

// Trilinear sampling of a dense SDF grid (x-fastest, dim^3, world = origin + lattice
// * cell), clamped at the edge. Shared by ArrayField and the mesher's clipmap Level —
// the one definition of "read this grid" so the two can't drift apart.
inline double grid_clamped(const float *data, int dim, int x, int y, int z) {
	x = CLAMP(x, 0, dim - 1);
	y = CLAMP(y, 0, dim - 1);
	z = CLAMP(z, 0, dim - 1);
	return double(data[x + dim * (y + dim * z)]);
}

inline double sample_trilinear(const float *data, int dim, const Vector3 &origin, double cell, const Vector3 &world) {
	double lx = (world.x - origin.x) / cell, ly = (world.y - origin.y) / cell, lz = (world.z - origin.z) / cell;
	int x0 = int(Math::floor(lx)), y0 = int(Math::floor(ly)), z0 = int(Math::floor(lz));
	double fx = lx - x0, fy = ly - y0, fz = lz - z0;
	double c00 = Math::lerp(grid_clamped(data, dim, x0, y0, z0), grid_clamped(data, dim, x0 + 1, y0, z0), fx);
	double c10 = Math::lerp(grid_clamped(data, dim, x0, y0 + 1, z0), grid_clamped(data, dim, x0 + 1, y0 + 1, z0), fx);
	double c01 = Math::lerp(grid_clamped(data, dim, x0, y0, z0 + 1), grid_clamped(data, dim, x0 + 1, y0, z0 + 1), fx);
	double c11 = Math::lerp(grid_clamped(data, dim, x0, y0 + 1, z0 + 1), grid_clamped(data, dim, x0 + 1, y0 + 1, z0 + 1), fx);
	return Math::lerp(Math::lerp(c00, c10, fy), Math::lerp(c01, c11, fy), fz);
}

struct Field {
	virtual ~Field() {}
	virtual double sample(const Vector3 &p) const = 0; // negative inside solid
};

struct SphereField : public Field {
	Vector3 center;
	double radius;
	SphereField(const Vector3 &c, double r) :
			center(c), radius(r) {}
	double sample(const Vector3 &p) const override {
		return (p - center).length() - radius;
	}
};

struct BoxField : public Field {
	Vector3 center;
	Vector3 half;
	BoxField(const Vector3 &c, const Vector3 &size) :
			center(c), half(size * 0.5) {}
	double sample(const Vector3 &p) const override {
		Vector3 q = (p - center).abs() - half;
		double outside = Vector3(MAX(q.x, 0.0), MAX(q.y, 0.0), MAX(q.z, 0.0)).length();
		double inside = MIN(MAX(q.x, MAX(q.y, q.z)), 0.0);
		return outside + inside;
	}
};

// A dense SDF grid (what DCRegionReader gives us for procedural terrain), sampled
// trilinearly — the bridge that lets the octree be built from real terrain. The data
// pointer must outlive the imprint call. Layout: x-fastest, dim^3; world = origin +
// lattice * cell. Clamped at the grid edge.
struct ArrayField : public Field {
	const float *data;
	int dim;
	Vector3 origin;
	double cell;
	ArrayField(const float *d, int dm, const Vector3 &o, double c) :
			data(d), dim(dm), origin(o), cell(c) {}
	double sample(const Vector3 &p) const override {
		return sample_trilinear(data, dim, origin, cell, p);
	}
};

} // namespace voxel_dc

#endif // SDF_FIELD_H
