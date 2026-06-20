#ifndef DC_MMAP_ARENA_H
#define DC_MMAP_ARENA_H

// M2 (doc 20): a growable array of POD T backed by a memory-mapped temp file (MAP_SHARED). Cold pages page
// out to DISK under memory pressure — they are file-backed and reclaimable, so the OOM-killer never fires —
// while the hot working set stays in RAM. The octree's cell arena uses only operator[] / push_back /
// resize_uninitialized / size, so this is a drop-in for LocalVector<Cell>. A huge sparse mapping is reserved
// up front (virtual only until touched) so growth never remaps. Falls back to anonymous (swap-paged) mmap if
// the temp file can't be created (e.g. tests on a read-only dir) — same interface, just not disk-paged.

#include "core/error/error_macros.h"

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <cstdint>
#include <cstdlib>

namespace voxel_dc {
namespace dc_mesh {

template <typename T>
struct MmapArena {
	T *base = nullptr;
	int64_t _size = 0;
	int64_t _cap = 0;
	int fd = -1;
	int64_t _bytes = 0;

	MmapArena() {}
	MmapArena(const MmapArena &) = delete;
	MmapArena &operator=(const MmapArena &) = delete;

	~MmapArena() {
		if (base != nullptr && base != MAP_FAILED) {
			munmap(base, _bytes);
		}
		if (fd >= 0) {
			close(fd);
		}
	}

	void _ensure() {
		if (base != nullptr) {
			return;
		}
		// Reserve a large sparse region (capped well under INT_MAX cells, since indices are int).
		const int64_t reserve_bytes = int64_t(384) << 30; // 384 GiB
		_cap = reserve_bytes / int64_t(sizeof(T));
		const int64_t cap_limit = int64_t(1) << 30; // 1.07B cells — keep int indices safe
		if (_cap > cap_limit) {
			_cap = cap_limit;
		}
		_bytes = _cap * int64_t(sizeof(T));
		char tmpl[] = "./tmp/dc_arena_XXXXXX";
		fd = mkstemp(tmpl);
		if (fd >= 0) {
			unlink(tmpl); // the open fd keeps the inode for MAP_SHARED; auto-removed on close
			if (ftruncate(fd, _bytes) != 0) {
				close(fd);
				fd = -1;
			}
		}
		if (fd >= 0) {
			base = (T *)mmap(nullptr, _bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
		} else {
			base = (T *)mmap(nullptr, _bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
		}
		CRASH_COND_MSG(base == MAP_FAILED, "MmapArena: mmap failed (out of address space?)");
	}

	int64_t size() const { return _size; }
	bool is_empty() const { return _size == 0; }

	T &operator[](int64_t i) { return base[i]; }
	const T &operator[](int64_t i) const { return base[i]; }

	void push_back(const T &v) {
		_ensure();
		CRASH_COND_MSG(_size >= _cap, "MmapArena: arena full (raise the reserve)");
		base[_size++] = v;
	}

	void resize_uninitialized(int64_t n) {
		_ensure();
		CRASH_COND_MSG(n > _cap, "MmapArena: arena full (raise the reserve)");
		_size = n; // pages commit on first touch; the caller fills every new slot
	}

	// M2 metric: resident (in-RAM) bytes of the LIVE region, via mincore — one byte/page residency bitmap,
	// queried in fixed chunks so the scratch buffer stays small. The rest of `size()*sizeof(T)` is on disk.
	int64_t resident_bytes() const {
		if (base == nullptr || _size == 0) {
			return 0;
		}
		const int64_t pg = sysconf(_SC_PAGESIZE);
		const int64_t used = _size * int64_t(sizeof(T));
		const int64_t total_pages = (used + pg - 1) / pg;
		static const int64_t CHUNK = 1 << 20; // up to 1M pages (1 MiB vec) per mincore call
		unsigned char *vec = (unsigned char *)malloc(CHUNK);
		if (vec == nullptr) {
			return 0;
		}
		int64_t resident = 0;
		for (int64_t p0 = 0; p0 < total_pages; p0 += CHUNK) {
			int64_t n = total_pages - p0;
			if (n > CHUNK) {
				n = CHUNK;
			}
			if (mincore((char *)base + p0 * pg, n * pg, vec) == 0) {
				for (int64_t k = 0; k < n; ++k) {
					resident += (vec[k] & 1);
				}
			}
		}
		free(vec);
		return resident * pg;
	}
};

} // namespace dc_mesh
} // namespace voxel_dc

#endif // DC_MMAP_ARENA_H
