#ifndef SDF_FIELD_H
#define SDF_FIELD_H

// A signed-distance field source the octree imprints/samples — C++-native so it can be
// evaluated on the mesher's worker thread (a GDScript field-closure can't). Concrete
// fields: analytic shapes now (CSG brushes); a procedural-generator-backed field and a
// combine field (existing op brush) come with the edit + terrain integration.

#include "core/math/math_funcs.h"
#include "core/math/vector3.h"

namespace voxel_dc {

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

} // namespace voxel_dc

#endif // SDF_FIELD_H
