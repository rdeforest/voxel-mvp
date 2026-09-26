#include "edit_store.h"

#include "edit_store_lattice.h"
#include "octree_geometry.h"
#include "sdf_field.h"

using namespace voxel_dc;
using edit_store_lattice::is_write_leaf;
using edit_store_lattice::overlaps;

namespace {

// Whether coordinate `v` descends into the upper child at `mid`; on the mid-plane, `toward` decides.
bool upper_side(double v, double toward, double mid) {
	return v > mid || (v == mid && toward >= mid);
}

} // namespace

int EditStore::_new_node(const Vector3 &o, double s) {
	Node n;
	n.origin = o;
	n.size = s;
	nodes.push_back(n);
	return int(nodes.size()) - 1;
}

void EditStore::setup(Vector3 origin, double size, double base, double amp, double period, int octaves, int seed) {
	nodes.clear();
	_root_origin = origin;
	_root_size = size;
	_base = base;
	_amp = amp;
	_period = period;
	_octaves = octaves;
	_seed = seed;
	_gen = voxel_dc::TerrainField(base, amp, period, octaves, seed);
	_new_node(origin, size);
}

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
		const bool was_edited = n.has_corners;
		bool any_solid = false;
		for (int i = 0; i < 8; ++i) {
			const Vector3 c = corner(o, s, i);
			const double before = was_edited ? double(n.corners[i]) : _gen.sample(c);
			const double b = brush.sample(c);
			const double after = op == 0 ? MIN(before, b) : MAX(before, -b);
			n.corners[i] = float(after);
			any_solid = any_solid || after < 0.0;
		}
		n.has_corners = true;
		if (any_solid && op == 0) {
			n.material = uint8_t(material); // a UNION (add) paints its material; a carve keeps existing
		}
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

void EditStore::write_region(const PackedFloat32Array &sdf, const PackedByteArray &indices, int dim, Vector3 origin, double cell) {
	if (nodes.is_empty() || sdf.size() < int64_t(dim) * dim * dim) {
		return;
	}
	const voxel_dc::ArrayField field(sdf.ptr(), dim, origin, cell);
	const Vector3 rmin = origin;
	const Vector3 rmax = origin + Vector3(1, 1, 1) * (double(dim - 1) * cell);
	_write_region(0, field, indices, dim, origin, cell, rmin, rmax);
}

// Like _stamp_region but it SETS the stored field from the array (the array is the final
// result), rather than combining a brush. Material is the array's nearest index at the
// leaf centre.
void EditStore::_write_region(int idx, const voxel_dc::ArrayField &sdf, const PackedByteArray &indices,
		int adim, const Vector3 &aorigin, double cell, const Vector3 &rmin, const Vector3 &rmax) {
	const Vector3 o = nodes[idx].origin;
	const double s = nodes[idx].size;
	if (!overlaps(o, s, rmin, rmax)) {
		return;
	}
	// Set the corners of every LEAF in the region no coarser than `cell`. Leaves finer than
	// `cell` (refined by an earlier, finer edit) are written too, from the array's trilerp — which
	// reproduces the coarse field exactly — so a coarse write over fine leaves lands instead of
	// setting an internal node's corners that sample() never reads.
	if (is_write_leaf(s, cell) && nodes[idx].is_leaf()) {
		Node &n = nodes[idx];
		for (int i = 0; i < 8; ++i) {
			n.corners[i] = float(sdf.sample(corner(o, s, i)));
		}
		n.has_corners = true;
		if (!indices.is_empty()) {
			// Material is indexed at the leaf ORIGIN cell (floor of the centre), so it lines
			// up with the array cell whose SDF corner sits at this leaf's origin — the
			// convention StoreWrite paints with. (round() would push the .5 to the next cell.)
			const Vector3 c = o + Vector3(1, 1, 1) * (s * 0.5);
			const int ix = CLAMP(int(Math::floor((c.x - aorigin.x) / cell)), 0, adim - 1);
			const int iy = CLAMP(int(Math::floor((c.y - aorigin.y) / cell)), 0, adim - 1);
			const int iz = CLAMP(int(Math::floor((c.z - aorigin.z) / cell)), 0, adim - 1);
			n.material = indices[voxel_dc::flat_index(ix, iy, iz, adim)];
		}
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
		_write_region(ch[i], sdf, indices, adim, aorigin, cell, rmin, rmax);
	}
}

// An edited leaf subdivides into children that reproduce its field (trilerp'd corners), so
// refining doesn't move the stored surface. An unedited leaf subdivides into fresh unedited
// children (they still defer to the generator until a brush materialises them).
void EditStore::_subdivide(int idx) {
	const Vector3 o = nodes[idx].origin;
	const double s = nodes[idx].size;
	const double half = s * 0.5;
	const bool inherit = nodes[idx].has_corners;
	float src[8];
	const uint8_t mat = nodes[idx].material;
	for (int i = 0; i < 8; ++i) {
		src[i] = nodes[idx].corners[i];
	}
	int ch[8];
	for (int i = 0; i < 8; ++i) {
		const int ci = _new_node(o + Vector3(CB[i][0], CB[i][1], CB[i][2]) * half, half);
		if (inherit) {
			Node &c = nodes[ci];
			c.has_corners = true;
			c.material = mat;
			edit_store_lattice::child_corners(src, i, c.corners);
		}
		ch[i] = ci;
	}
	Node &n = nodes[idx];
	for (int i = 0; i < 8; ++i) {
		n.children[i] = ch[i];
	}
	n.has_corners = false;
}

bool EditStore::_inside_root(const Vector3 &p) const {
	return p.x >= _root_origin.x && p.y >= _root_origin.y && p.z >= _root_origin.z &&
			p.x < _root_origin.x + _root_size && p.y < _root_origin.y + _root_size && p.z < _root_origin.z + _root_size;
}

// The leaf holding `p`, taking the child on `toward`'s side where `p` lies on a node's mid-plane.
int EditStore::_leaf_toward(const Vector3 &p, const Vector3 &toward) const {
	int idx = 0;
	while (!nodes[idx].is_leaf()) {
		const Node &n = nodes[idx];
		const Vector3 mid = n.origin + Vector3(1, 1, 1) * (n.size * 0.5);
		const int child = (upper_side(p.x, toward.x, mid.x) ? 1 : 0) | (upper_side(p.y, toward.y, mid.y) ? 2 : 0) |
				(upper_side(p.z, toward.z, mid.z) ? 4 : 0);
		idx = n.children[child];
	}
	return idx;
}

int EditStore::_leaf_at(const Vector3 &p) const {
	return _leaf_toward(p, p);
}

double EditStore::sample(Vector3 p) const {
	return sample_toward(p, p);
}

double EditStore::sample_toward(Vector3 p, Vector3 toward) const {
	if (nodes.is_empty() || !_inside_root(p)) {
		return _gen.sample(p);
	}
	const int idx = _leaf_toward(p, toward);
	if (!nodes[idx].has_corners) {
		return _gen.sample(p); // unedited -> defer to the generator
	}
	const Node &n = nodes[idx];
	const Vector3 f = (p - n.origin) / n.size;
	return trilerp(n.corners, f.x, f.y, f.z);
}

bool EditStore::has_edit(Vector3 p) const {
	if (nodes.is_empty() || !_inside_root(p)) {
		return false;
	}
	return nodes[_leaf_at(p)].has_corners;
}

int EditStore::material_at(Vector3 p) const {
	if (nodes.is_empty() || !_inside_root(p)) {
		return 0;
	}
	const int idx = _leaf_at(p);
	// Unedited leaf -> the generator's material (so deep terrain reads Bedrock); edited -> stored.
	return nodes[idx].has_corners ? int(nodes[idx].material) : _gen.material(p);
}

PackedFloat32Array EditStore::fill_region(Vector3i origin, int dim, double cell,
		const PackedFloat32Array &prev, Vector3i prev_origin, Vector3i dirty_origin, Vector3i dirty_size) const {
	PackedFloat32Array out;
	out.resize(int64_t(dim) * dim * dim);
	float *w = out.ptrw();
	const bool has_prev = prev.size() == int64_t(dim) * dim * dim;
	const float *pr = has_prev ? prev.ptr() : nullptr;
	const Vector3i shift = origin - prev_origin; // prev index of new cell i is i + shift
	const bool has_dirty = dirty_size.x > 0 && dirty_size.y > 0 && dirty_size.z > 0;
	for (int z = 0; z < dim; ++z) {
		for (int y = 0; y < dim; ++y) {
			for (int x = 0; x < dim; ++x) {
				const int wx = origin.x + x; // world cell (cell == 1 for the collision buffer)
				const int wy = origin.y + y;
				const int wz = origin.z + z;
				const int px = x + shift.x;
				const int py = y + shift.y;
				const int pz = z + shift.z;
				const bool in_dirty = has_dirty &&
						wx >= dirty_origin.x && wx < dirty_origin.x + dirty_size.x &&
						wy >= dirty_origin.y && wy < dirty_origin.y + dirty_size.y &&
						wz >= dirty_origin.z && wz < dirty_origin.z + dirty_size.z;
				const int oi = voxel_dc::flat_index(x, y, z, dim);
				if (has_prev && !in_dirty && px >= 0 && px < dim && py >= 0 && py < dim && pz >= 0 && pz < dim) {
					w[oi] = pr[voxel_dc::flat_index(px, py, pz, dim)];
				} else {
					w[oi] = float(sample(Vector3(wx, wy, wz) * cell));
				}
			}
		}
	}
	return out;
}

PackedByteArray EditStore::fill_indices_region(Vector3i origin, int dim, double cell) const {
	PackedByteArray out;
	out.resize(int64_t(dim) * dim * dim);
	uint8_t *w = out.ptrw();
	for (int z = 0; z < dim; ++z) {
		for (int y = 0; y < dim; ++y) {
			for (int x = 0; x < dim; ++x) {
				const Vector3 p = Vector3(origin.x + x, origin.y + y, origin.z + z) * cell;
				w[voxel_dc::flat_index(x, y, z, dim)] = uint8_t(material_at(p));
			}
		}
	}
	return out;
}

Ref<EditStore> EditStore::duplicate() const {
	Ref<EditStore> c;
	c.instantiate();
	c->nodes = nodes;
	c->_root_origin = _root_origin;
	c->_root_size = _root_size;
	c->_base = _base;
	c->_amp = _amp;
	c->_period = _period;
	c->_octaves = _octaves;
	c->_seed = _seed;
	c->_gen = _gen;
	return c;
}

int EditStore::leaf_count() const {
	int n = 0;
	for (uint32_t i = 0; i < nodes.size(); ++i) {
		if (nodes[i].is_leaf() && nodes[i].has_corners) {
			++n;
		}
	}
	return n;
}

double EditStore::terrain_surface(double x, double z, double base, double amp, double period, int octaves, int seed) {
	return voxel_dc::TerrainField(base, amp, period, octaves, seed).surface(x, z);
}

void EditStore::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "origin", "size", "base", "amp", "period", "octaves", "seed"), &EditStore::setup);
	ClassDB::bind_method(D_METHOD("stamp_sphere", "center", "radius", "op", "material", "min_leaf"), &EditStore::stamp_sphere);
	ClassDB::bind_method(D_METHOD("stamp_box", "center", "size", "op", "material", "min_leaf"), &EditStore::stamp_box);
	ClassDB::bind_method(D_METHOD("write_region", "sdf", "indices", "dim", "origin", "cell"), &EditStore::write_region);
	ClassDB::bind_method(D_METHOD("predict_sphere_stamp", "center", "radius", "op", "min_leaf"), &EditStore::predict_sphere_stamp);
	ClassDB::bind_method(D_METHOD("predict_imprint", "shape", "dims", "xform", "op", "cell"), &EditStore::predict_imprint);
	ClassDB::bind_method(D_METHOD("predict_work", "points", "sdfs"), &EditStore::predict_work);
	ClassDB::bind_method(D_METHOD("predict_bell", "center", "radius", "peak"), &EditStore::predict_bell);
	ClassDB::bind_method(D_METHOD("predict_flatten", "plane_point", "normal", "radius"), &EditStore::predict_flatten);
	ClassDB::bind_method(D_METHOD("lattice_flips", "sdf", "dim", "origin", "cell"), &EditStore::lattice_flips);
	ClassDB::bind_method(D_METHOD("lattice_turns_in", "sdf", "dim", "origin", "cell", "box", "to_solid"), &EditStore::lattice_turns_in);
	ClassDB::bind_method(D_METHOD("lattice_writes", "sdf", "dim", "origin", "cell"), &EditStore::lattice_writes);
	ClassDB::bind_method(D_METHOD("sample", "p"), &EditStore::sample);
	ClassDB::bind_method(D_METHOD("sample_toward", "p", "toward"), &EditStore::sample_toward);
	ClassDB::bind_method(D_METHOD("has_edit", "p"), &EditStore::has_edit);
	ClassDB::bind_method(D_METHOD("material_at", "p"), &EditStore::material_at);
	ClassDB::bind_method(D_METHOD("leaf_count"), &EditStore::leaf_count);
	ClassDB::bind_method(D_METHOD("duplicate"), &EditStore::duplicate);
	ClassDB::bind_method(D_METHOD("fill_region", "origin", "dim", "cell", "prev", "prev_origin", "dirty_origin", "dirty_size"), &EditStore::fill_region);
	ClassDB::bind_method(D_METHOD("fill_indices_region", "origin", "dim", "cell"), &EditStore::fill_indices_region);
	ClassDB::bind_method(D_METHOD("serialize"), &EditStore::serialize);
	ClassDB::bind_method(D_METHOD("deserialize", "bytes"), &EditStore::deserialize);
	ClassDB::bind_static_method("EditStore", D_METHOD("terrain_surface", "x", "z", "base", "amp", "period", "octaves", "seed"), &EditStore::terrain_surface);
}
