#include "edit_store.h"

#include "edit_store_lattice.h"
#include "octree_geometry.h"
#include "sdf_field.h"

// EditStore's brush stamps (stamp_sphere / stamp_box), split from edit_store.cpp.

using namespace voxel_dc;
using edit_store_lattice::brush_leaf_material;
using edit_store_lattice::brush_made_solid;
using edit_store_lattice::is_write_leaf;
using edit_store_lattice::OP_UNION;
using edit_store_lattice::overlaps;
using edit_store_lattice::SOLID_THRESHOLD;

void EditStore::stamp_sphere(Vector3 center, double radius, int op, int material, double min_leaf) {
	const voxel_dc::SphereField brush(center, radius);
	const Vector3 r = Vector3(1, 1, 1) * (radius + min_leaf);
	_stamp(brush, center - r, center + r, op, material, min_leaf);
}

void EditStore::stamp_box(Vector3 center, Vector3 size, int op, int material, double min_leaf) {
	const voxel_dc::BoxField brush(center, size);
	const Vector3 r = size * 0.5 + Vector3(1, 1, 1) * min_leaf;
	_stamp(brush, center - r, center + r, op, material, min_leaf);
}

void EditStore::_stamp(const voxel_dc::Field &brush, const Vector3 &rmin, const Vector3 &rmax, int op, int material, double min_leaf) {
	if (nodes.is_empty()) {
		return;
	}
	_stamp_region(0, brush, rmin, rmax, op, material, min_leaf);
}

// Copy-on-write: descend only into nodes overlapping the brush region, subdividing toward
// it (so the rest stays sparse -> generator). At a min_leaf leaf, combine the brush with
// the cell's CURRENT value — the stored corner if already edited, else the generator — so
// re-edits stack and first edits materialise from the generator.
void EditStore::_stamp_region(int idx, const voxel_dc::Field &brush, const Vector3 &rmin, const Vector3 &rmax, int op, int material, double min_leaf) {
	const Vector3 o = nodes[idx].origin;
	const double s = nodes[idx].size;
	if (!overlaps(o, s, rmin, rmax)) {
		return; // leave it sparse (generator)
	}
	// Write at a leaf no coarser than min_leaf. A node that small which already has children
	// (refined by an earlier, finer edit) is NOT a leaf — sample() reads its children, so the
	// brush must land on them too, or the stamp would be a silent no-op there.
	if (is_write_leaf(s, min_leaf) && nodes[idx].is_leaf()) {
		Node &n = nodes[idx];
		const bool was_edited = n.is_edited();
		const Vector3 centre = o + Vector3(1, 1, 1) * (s * 0.5);
		bool made = false;
		bool solid = false;
		for (int i = 0; i < 8; ++i) {
			const Vector3 c = corner(o, s, i);
			const double before = was_edited ? double(n.corners[i]) : _gen.sample(c);
			const double b = brush.sample(c);
			const float after = float(op == OP_UNION ? MIN(before, b) : MAX(before, -b));
			n.corners[i] = after;
			made = made || brush_made_solid(after, b);
			solid = solid || after < SOLID_THRESHOLD;
		}
		n.field = OWN_FIELD;
		n.source = idx;
		n.material = uint8_t(brush_leaf_material(made, solid, material, true,
				[&] { return was_edited ? int(n.material) : _gen.material(centre); }));
		return;
	}
	if (nodes[idx].is_leaf()) {
		_subdivide(idx);
	}
	int ch[8];
	for (int i = 0; i < 8; ++i) {
		ch[i] = nodes[idx].children[i];
	}
	for (int i = 0; i < 8; ++i) {
		_stamp_region(ch[i], brush, rmin, rmax, op, material, min_leaf);
	}
}
