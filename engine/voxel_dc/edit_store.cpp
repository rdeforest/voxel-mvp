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
		n.field = OWN_FIELD;
		n.source = idx;
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

// An edited leaf subdivides into children that read its field unchanged (see FieldState), so
// refining moves no sample, the stored surface included. An unedited leaf subdivides into fresh
// unedited children (they still defer to the generator until a brush materialises them).
void EditStore::_subdivide(int idx) {
	const Vector3 o = nodes[idx].origin;
	const double half = nodes[idx].size * 0.5;
	const int field = _leaf_field(idx);
	const uint8_t mat = nodes[idx].material;
	int ch[8];
	for (int i = 0; i < 8; ++i) {
		const Vector3 child_origin = o + Vector3(CB[i][0], CB[i][1], CB[i][2]) * half;
		const int ci = _new_node(child_origin, half);
		if (field >= 0) {
			Node &c = nodes[ci];
			c.field = INHERITED_FIELD;
			c.source = field;
			c.material = mat;
			for (int j = 0; j < 8; ++j) {
				c.corners[j] = _held_corner(field, child_origin, half, j);
			}
		}
		ch[i] = ci;
	}
	Node &n = nodes[idx];
	for (int i = 0; i < 8; ++i) {
		n.children[i] = ch[i];
	}
	n.field = n.field == OWN_FIELD ? FIELD_SOURCE : NO_FIELD;
}

// The field node `field` holds (see FieldState) at `p`.
double EditStore::_field_value(int field, const Vector3 &p) const {
	const Node &f = nodes[field];
	const Vector3 at = (p - f.origin) / f.size;
	return trilerp(f.corners, at.x, at.y, at.z);
}

// What the edited leaf (o, s), whose field node `field` holds, stores at its corner `i`: that corner
// as it is for a leaf holding its own field, else the field there rounded as a stored corner is. Read
// from the corner itself rather than trilerped at it, which need not reproduce it to the bit.
float EditStore::_held_corner(int field, const Vector3 &o, double s, int i) const {
	const Node &f = nodes[field];
	if (f.origin == o && f.size == s) {
		return f.corners[i];
	}
	return float(_field_value(field, corner(o, s, i)));
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

// The node holding leaf `leaf`'s field (see FieldState), -1 for an unedited leaf (the generator).
int EditStore::_leaf_field(int leaf) const {
	return nodes[leaf].is_edited() ? nodes[leaf].source : -1;
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
	const int field = _leaf_field(_leaf_toward(p, toward));
	return field < 0 ? _gen.sample(p) : _field_value(field, p);
}

bool EditStore::has_edit(Vector3 p) const {
	if (nodes.is_empty() || !_inside_root(p)) {
		return false;
	}
	return nodes[_leaf_at(p)].is_edited();
}

int EditStore::material_at(Vector3 p) const {
	if (nodes.is_empty() || !_inside_root(p)) {
		return 0;
	}
	const int idx = _leaf_at(p);
	// Unedited leaf -> the generator's material (so deep terrain reads Bedrock); edited -> stored.
	return nodes[idx].is_edited() ? int(nodes[idx].material) : _gen.material(p);
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
		if (nodes[i].is_leaf() && nodes[i].is_edited()) {
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
	ClassDB::bind_method(D_METHOD("write_region_flips", "sdf", "indices", "dim", "origin", "cell"), &EditStore::write_region_flips);
	ClassDB::bind_method(D_METHOD("predict_sphere_stamp", "center", "radius", "op", "min_leaf"), &EditStore::predict_sphere_stamp);
	ClassDB::bind_method(D_METHOD("predict_imprint", "shape", "dims", "xform", "op", "cell"), &EditStore::predict_imprint);
	ClassDB::bind_method(D_METHOD("predict_work", "points", "sdfs"), &EditStore::predict_work);
	ClassDB::bind_method(D_METHOD("predict_bell", "center", "radius", "peak"), &EditStore::predict_bell);
	ClassDB::bind_method(D_METHOD("predict_flatten", "plane_point", "normal", "radius"), &EditStore::predict_flatten);
	ClassDB::bind_method(D_METHOD("imprint_near_solid", "shape", "dims", "xform", "cell", "reach", "below"), &EditStore::imprint_near_solid);
	ClassDB::bind_method(D_METHOD("lattice_flips", "sdf", "dim", "origin", "cell"), &EditStore::lattice_flips);
	ClassDB::bind_method(D_METHOD("lattice_turns_in", "sdf", "dim", "origin", "cell", "box", "to_solid"), &EditStore::lattice_turns_in);
	ClassDB::bind_method(D_METHOD("lattice_materials", "sdf", "made", "dim", "origin", "cell", "material", "air_keeps"), &EditStore::lattice_materials);
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
