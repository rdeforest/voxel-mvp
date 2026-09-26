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
		b->put_u8(n.has_corners ? 1 : 0);
		b->put_u8(n.material);
	}
	return b->get_data_array();
}

void EditStore::deserialize(const PackedByteArray &bytes) {
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
	_root_origin = Vector3(rox, roy, roz);
	_root_size = b->get_double();
	_base = b->get_double();
	_amp = b->get_double();
	_period = b->get_double();
	_octaves = b->get_32();
	_seed = b->get_32();
	_gen = voxel_dc::TerrainField(_base, _amp, _period, _octaves, _seed);
	const int count = b->get_32();
	nodes.clear();
	nodes.reserve(count);
	for (int i = 0; i < count; ++i) {
		Node n;
		const double nox = b->get_double();   // sequential reads — see _root_origin above
		const double noy = b->get_double();
		const double noz = b->get_double();
		n.origin = Vector3(nox, noy, noz);
		n.size = b->get_double();
		for (int j = 0; j < 8; ++j) {
			n.children[j] = b->get_32();
		}
		for (int j = 0; j < 8; ++j) {
			n.corners[j] = b->get_float();
		}
		n.has_corners = b->get_u8() != 0;
		n.material = b->get_u8();
		nodes.push_back(n);
	}
}
