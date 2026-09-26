#include "edit_store.h"

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
	const Vector3 root_origin(rox, roy, roz);
	const double root_size = b->get_double();
	const double base = b->get_double();
	const double amp = b->get_double();
	const double period = b->get_double();
	const int octaves = b->get_32();
	const int seed = b->get_32();
	const int count = b->get_32();
	ERR_FAIL_COND_V_MSG(count < 1, false, "EditStore blob has no root node.");
	LocalVector<Node> read;
	read.reserve(count);
	for (int i = 0; i < count; ++i) {
		Node n;
		if (!_read_node(**b, i, n)) {
			return false;
		}
		read.push_back(n);
	}
	LocalVector<Node> kept = nodes;
	nodes = read;
	if (!_link_sources(0, -1)) {
		nodes = kept;
		ERR_FAIL_V_MSG(false, "EditStore blob: an inherited leaf has no field source above it.");
	}
	_root_origin = root_origin;
	_root_size = root_size;
	_base = base;
	_amp = amp;
	_period = period;
	_octaves = octaves;
	_seed = seed;
	_gen = voxel_dc::TerrainField(_base, _amp, _period, _octaves, _seed);
	return true;
}

bool EditStore::_read_node(StreamPeerBuffer &b, int index, Node &n) {
	const double ox = b.get_double();   // sequential reads — see deserialize's root_origin
	const double oy = b.get_double();
	const double oz = b.get_double();
	n.origin = Vector3(ox, oy, oz);
	n.size = b.get_double();
	for (int j = 0; j < 8; ++j) {
		n.children[j] = b.get_32();
	}
	for (int j = 0; j < 8; ++j) {
		n.corners[j] = b.get_float();
	}
	const uint8_t state = b.get_u8();
	ERR_FAIL_COND_V_MSG(state > FIELD_SOURCE, false, vformat("EditStore blob: node %d has unknown field state %d.", index, state));
	n.field = FieldState(state);
	n.material = b.get_u8();
	return true;
}

// Sets every edited leaf's `source` under `idx`, `source` being the nearest FIELD_SOURCE above it.
// False if an inherited leaf has none.
bool EditStore::_link_sources(int idx, int source) {
	Node &n = nodes[idx];
	if (n.is_leaf()) {
		const int by_state[] = { -1, idx, source, -1 };
		n.source = by_state[n.field];
		return n.field != INHERITED_FIELD || source >= 0;
	}
	const int below = n.field == FIELD_SOURCE ? idx : source;
	bool linked = true;
	for (int i = 0; i < 8; ++i) {
		linked = _link_sources(nodes[idx].children[i], below) && linked;
	}
	return linked;
}
