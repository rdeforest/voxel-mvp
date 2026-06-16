#ifndef OCTREE_GEOMETRY_H
#define OCTREE_GEOMETRY_H

// Cube/corner geometry shared by the octree storage and mesher (kept in
// one place so the .cpp files agree on corner order, trilinear sampling, etc.).

#include "core/math/math_funcs.h"
#include "core/math/vector3.h"

namespace voxel_dc {

inline constexpr double OCTREE_EMPTY = 1e30; // sample() of an unwritten region

// Cube corners by xyz bits; 12 edges as corner-index pairs; 4 cells around an edge.
inline constexpr int CB[8][3] = {
	{ 0, 0, 0 }, { 1, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 },
	{ 0, 0, 1 }, { 1, 0, 1 }, { 0, 1, 1 }, { 1, 1, 1 },
};
inline constexpr int EDGES[12][2] = {
	{ 0, 1 }, { 2, 3 }, { 4, 5 }, { 6, 7 },
	{ 0, 2 }, { 1, 3 }, { 4, 6 }, { 5, 7 },
	{ 0, 4 }, { 1, 5 }, { 2, 6 }, { 3, 7 },
};
inline constexpr int RING[4][2] = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } };

inline Vector3 corner(const Vector3 &o, double s, int i) {
	return o + Vector3(CB[i][0], CB[i][1], CB[i][2]) * s;
}

inline double trilerp(const float *c, double fx, double fy, double fz) {
	double c00 = Math::lerp(double(c[0]), double(c[1]), fx);
	double c10 = Math::lerp(double(c[2]), double(c[3]), fx);
	double c01 = Math::lerp(double(c[4]), double(c[5]), fx);
	double c11 = Math::lerp(double(c[6]), double(c[7]), fx);
	return Math::lerp(Math::lerp(c00, c10, fy), Math::lerp(c01, c11, fy), fz);
}

inline Vector3 axis_vec(int i, double a) {
	return i == 0 ? Vector3(a, 0, 0) : (i == 1 ? Vector3(0, a, 0) : Vector3(0, 0, a));
}

inline bool origin_less(const Vector3 &a, const Vector3 &b) {
	if (a.x != b.x) {
		return a.x < b.x;
	}
	if (a.y != b.y) {
		return a.y < b.y;
	}
	return a.z < b.z;
}

} // namespace voxel_dc

#endif // OCTREE_GEOMETRY_H
