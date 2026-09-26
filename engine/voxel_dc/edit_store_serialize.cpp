#include "edit_store.h"

#include "octree_geometry.h"

using voxel_dc::CB;

namespace {

// The layout serialize writes: a header of the root origin, root size and generator params (doubles),
// then octaves, seed and node count (32-bit); per node its origin and size (doubles), 8 child indices
// (32-bit), 8 corners (floats), then field state and material (bytes).
constexpr int64_t HEADER_BYTES = 7 * 8 + 3 * 4;
constexpr int64_t NODE_BYTES = 4 * 8 + 8 * 4 + 8 * 4 + 2;

// FastNoiseLite loops over every octave per sample, unguarded, so a corrupt count freezes the first
// sample; past ~30 the doubling frequency leaves float range anyway.
constexpr int MAX_OCTAVES = 32;

} // namespace

// A blob as _parse reads it, vetted whole before deserialize lets it replace the store.
struct EditStore::Blob {
	Vector3 root_origin;
	double root_size = 0.0;
	double base = 0.0;
	double amp = 0.0;
	double period = 1.0;
	int octaves = 0;
	int seed = 0;
	LocalVector<Node> nodes;
	LocalVector<int> parent; // each node's parent; -1 for the root
};

PackedByteArray EditStore::serialize() const {
	Ref<StreamPeerBuffer> b;
	b.instantiate();
	b->put_double(_root_origin.x);
	b->put_double(_root_origin.y);
	b->put_double(_root_origin.z);
	b->put_double(_root_size);
	b->put_double(_base);
	b->put_double(_amp);
	b->put_double(_period);
	b->put_32(_octaves);
	b->put_32(_seed);
	b->put_32(int(nodes.size()));
	for (uint32_t i = 0; i < nodes.size(); ++i) {
		const Node &n = nodes[i];
		b->put_double(n.origin.x);
		b->put_double(n.origin.y);
		b->put_double(n.origin.z);
		b->put_double(n.size);
		for (int j = 0; j < 8; ++j) {
			b->put_32(n.children[j]);
		}
		for (int j = 0; j < 8; ++j) {
			b->put_float(n.corners[j]);
		}
		b->put_u8(n.field);
		b->put_u8(n.material);
	}
	return b->get_data_array();
}

// Returns false, leaving the store as it was, on a blob this build can't read.
bool EditStore::deserialize(const PackedByteArray &bytes) {
	Blob blob;
	const String problem = _parse(bytes, blob);
	ERR_FAIL_COND_V_MSG(!problem.is_empty(), false, problem);
	nodes = std::move(blob.nodes);
	_root_origin = blob.root_origin;
	_root_size = blob.root_size;
	_base = blob.base;
	_amp = blob.amp;
	_period = blob.period;
	_octaves = blob.octaves;
	_seed = blob.seed;
	_gen = voxel_dc::TerrainField(_base, _amp, _period, _octaves, _seed);
	return true;
}

String EditStore::blob_problem(const PackedByteArray &bytes) {
	Blob blob;
	return _parse(bytes, blob);
}

// Reads `bytes` into `blob`: "" when they are a tree serialize could have written, else what is wrong
// with them. The length is checked before anything is read, and the tree before anything walks it.
String EditStore::_parse(const PackedByteArray &bytes, Blob &blob) {
	if (bytes.size() < HEADER_BYTES) {
		return vformat("EditStore blob is %d bytes, shorter than its %d-byte header.", bytes.size(), HEADER_BYTES);
	}
	Ref<StreamPeerBuffer> b;
	b.instantiate();
	b->set_data_array(bytes);
	b->seek(0);
	// Read each component into a local before constructing the Vector3: C++ leaves the
	// order of evaluation of function arguments unspecified, and GCC evaluates right-to-
	// left, which would transpose X<->Z relative to serialize's sequential writes.
	const double rox = b->get_double();
	const double roy = b->get_double();
	const double roz = b->get_double();
	blob.root_origin = Vector3(rox, roy, roz);
	blob.root_size = b->get_double();
	blob.base = b->get_double();
	blob.amp = b->get_double();
	blob.period = b->get_double();
	blob.octaves = b->get_32();
	blob.seed = b->get_32();
	const int count = b->get_32();
	const String generator = _check_generator(blob);
	if (!generator.is_empty()) {
		return generator;
	}
	if (count < 1) {
		return "EditStore blob has no root node.";
	}
	const int64_t size = HEADER_BYTES + int64_t(count) * NODE_BYTES;
	if (bytes.size() != size) {
		return vformat("EditStore blob is %d bytes; its %d nodes take %d (truncated or corrupt).", bytes.size(), count, size);
	}
	blob.nodes.resize(count);
	for (int i = 0; i < count; ++i) {
		const String problem = _read_node(**b, i, blob.nodes[i]);
		if (!problem.is_empty()) {
			return problem;
		}
	}
	const String problem = _check_tree(blob);
	return problem.is_empty() ? _link_sources(blob) : problem;
}

// "" when the header's generator params make a field TerrainField can sample: it checks none of them,
// and a zero or non-finite period or non-finite base / amp makes every sample NaN.
String EditStore::_check_generator(const Blob &blob) {
	const bool finite = Math::is_finite(blob.base) && Math::is_finite(blob.amp) && Math::is_finite(blob.period);
	if (!finite || !(blob.period > 0.0)) {
		return vformat("EditStore blob: generator base %f, amp %f, period %f are not finite with a positive period.",
				blob.base, blob.amp, blob.period);
	}
	if (blob.octaves < 0 || blob.octaves > MAX_OCTAVES) {
		return vformat("EditStore blob: generator octaves %d is outside 0..%d.", blob.octaves, MAX_OCTAVES);
	}
	return String();
}

String EditStore::_read_node(StreamPeerBuffer &b, int index, Node &n) {
	const double ox = b.get_double();   // sequential reads — see _parse's root_origin
	const double oy = b.get_double();
	const double oz = b.get_double();
	n.origin = Vector3(ox, oy, oz);
	n.size = b.get_double();
	for (int j = 0; j < 8; ++j) {
		n.children[j] = b.get_32();
	}
	for (int j = 0; j < 8; ++j) {
		n.corners[j] = b.get_float();
		if (!Math::is_finite(n.corners[j])) {
			return vformat("EditStore blob: node %d has a non-finite corner %d.", index, j);
		}
	}
	const uint8_t state = b.get_u8();
	if (state > FIELD_SOURCE) {
		return vformat("EditStore blob: node %d has unknown field state %d.", index, state);
	}
	n.field = FieldState(state);
	n.material = b.get_u8();
	return String();
}

// "" when the blob's nodes are the tree serialize writes: node 0 is the header's root cube, and every
// other node is an octant of exactly one node listed before it (_subdivide appends a leaf's children
// after it, and nothing removes a node). Parents before children makes the tree acyclic without walking
// it, and octants of a finite root halve in size, bounding its depth. Fills `blob.parent`.
String EditStore::_check_tree(Blob &blob) {
	const Node &root = blob.nodes[0];
	const bool root_cube = root.origin == blob.root_origin && root.size == blob.root_size;
	if (!root_cube || !(blob.root_size > 0.0) || !Math::is_finite(blob.root_size) || !blob.root_origin.is_finite()) {
		return "EditStore blob: the root node isn't the header's (finite, non-empty) root cube.";
	}
	const int count = int(blob.nodes.size());
	blob.parent.resize(count);
	for (int i = 0; i < count; ++i) {
		blob.parent[i] = -1;
	}
	for (int i = 0; i < count; ++i) {
		const String problem = _check_children(blob, i);
		if (!problem.is_empty()) {
			return problem;
		}
	}
	for (int i = 1; i < count; ++i) {
		if (blob.parent[i] < 0) {
			return vformat("EditStore blob: node %d is no node's child.", i);
		}
	}
	return String();
}

// Node `i`'s children and field state, by _check_tree's rules. An internal node may hold OWN_FIELD,
// which nothing reads: write_region before f11d284 stored corners on internal nodes, and v1 blobs
// written then carry it.
String EditStore::_check_children(Blob &blob, int i) {
	const Node &n = blob.nodes[i];
	if (n.is_leaf()) {
		for (int j = 0; j < 8; ++j) {
			if (n.children[j] != -1) {
				return vformat("EditStore blob: leaf %d has child index %d in slot %d.", i, n.children[j], j);
			}
		}
		return n.field == FIELD_SOURCE ? vformat("EditStore blob: leaf %d is marked a field source.", i) : String();
	}
	if (n.field == INHERITED_FIELD) {
		return vformat("EditStore blob: internal node %d is marked an inherited field.", i);
	}
	const double half = n.size * 0.5;
	for (int j = 0; j < 8; ++j) {
		const int c = n.children[j];
		if (c <= i || c >= int(blob.nodes.size())) {
			return vformat("EditStore blob: node %d's child index %d in slot %d is not a node after it.", i, c, j);
		}
		if (blob.parent[c] >= 0) {
			return vformat("EditStore blob: node %d is a child of both node %d and node %d.", c, blob.parent[c], i);
		}
		blob.parent[c] = i;
		const Node &child = blob.nodes[c];
		const Vector3 origin = n.origin + Vector3(CB[j][0], CB[j][1], CB[j][2]) * half;
		if (!(half > 0.0) || child.origin != origin || child.size != half) {
			return vformat("EditStore blob: node %d is not octant %d of its parent, node %d.", c, j, i);
		}
	}
	return String();
}

// Sets every edited leaf's `source`: itself for OWN_FIELD, the nearest FIELD_SOURCE above it for
// INHERITED_FIELD. One forward pass reaches every ancestor first (_check_tree: parents come before
// their children). "" unless an inherited leaf has no field source above it.
String EditStore::_link_sources(Blob &blob) {
	LocalVector<Node> &read = blob.nodes;
	LocalVector<int> above; // each node's nearest FIELD_SOURCE ancestor, -1 for none
	above.resize(read.size());
	above[0] = -1;
	for (uint32_t i = 1; i < read.size(); ++i) {
		const int p = blob.parent[i];
		above[i] = read[p].field == FIELD_SOURCE ? p : above[p];
	}
	for (uint32_t i = 0; i < read.size(); ++i) {
		Node &n = read[i];
		if (!n.is_leaf()) {
			continue;
		}
		if (n.field == INHERITED_FIELD && above[i] < 0) {
			return "EditStore blob: an inherited leaf has no field source above it.";
		}
		const int by_state[] = { -1, int(i), above[i], -1 };
		n.source = by_state[n.field];
	}
	return String();
}
