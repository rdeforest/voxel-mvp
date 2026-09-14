#ifndef DC_MESH_COMMON_H
#define DC_MESH_COMMON_H

// Shared primitives for the DC octree mesher's internal structs (Clipmap / EditStoreSource /
// Octree): the parallel worker count, the dynamic-load-balanced parallel_for, and small helpers.
// In a NAMED internal namespace (voxel_dc::dc_mesh) so these headers are header-correct even though
// only dc_octree_mesher.cpp includes them.

#include "core/math/vector3.h"
#include "core/math/vector3i.h"
#include "core/templates/local_vector.h"
#include "core/typedefs.h"

#include <atomic>
#include <thread>

namespace voxel_dc {
namespace dc_mesh {

inline int g_mesh_threads = 1; // parallel worker count for the build's parallel phases; 1 = serial

const double QUERY_EPS = 0.25; // perpendicular offset to land just across an edge

inline Vector3 to_v3(const Vector3i &v) {
	return Vector3(real_t(v.x), real_t(v.y), real_t(v.z));
}

// Run fn(i) for i in [0, n) across `nthreads` workers with DYNAMIC load balancing: each worker
// grabs a chunk of indices off a shared atomic cursor and keeps grabbing until the range is drained,
// so uneven per-index cost (clustered surface leaves, varying crossing counts) can't strand a thread
// on one heavy range. nthreads <= 1 runs inline on the calling thread. Joins before returning, so a
// fn capturing caller locals by reference is safe. Raw std::thread (not WorkerThreadPool) on purpose:
// this already runs inside a pool task, and waiting on nested pool tasks from a pool thread can deadlock.
template <typename Fn>
void parallel_for(int n, int nthreads, Fn fn) {
	if (nthreads <= 1 || n <= 0) {
		for (int i = 0; i < n; ++i) {
			fn(i);
		}
		return;
	}
	const int chunk = MAX(1, n / (nthreads * 16)); // ~16 grabs/worker: balance vs atomic contention
	std::atomic<int> cursor(0);
	LocalVector<std::thread> workers;
	workers.resize(nthreads);
	for (int t = 0; t < nthreads; ++t) {
		workers[t] = std::thread([&fn, &cursor, n, chunk]() {
			for (;;) {
				int start = cursor.fetch_add(chunk, std::memory_order_relaxed);
				if (start >= n) {
					break;
				}
				int end = MIN(start + chunk, n);
				for (int i = start; i < end; ++i) {
					fn(i);
				}
			}
		});
	}
	for (int t = 0; t < nthreads; ++t) {
		workers[t].join();
	}
}

} // namespace dc_mesh
} // namespace voxel_dc

#endif // DC_MESH_COMMON_H
