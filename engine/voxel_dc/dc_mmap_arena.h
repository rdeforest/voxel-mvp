#ifndef DC_MMAP_ARENA_H
#define DC_MMAP_ARENA_H

// M2 (doc 20): a growable array of POD T backed by a memory-mapped temp file (MAP_SHARED). Cold pages page
// out to DISK under memory pressure — they are file-backed and reclaimable, so the OOM-killer never fires —
// while the hot working set stays in RAM. The octree's cell arena uses only operator[] / push_back /
// resize_uninitialized / size, so this is a drop-in for LocalVector<Cell>. A huge sparse mapping is reserved
// up front (virtual only until touched) so growth never remaps. Falls back to anonymous (swap-paged) mmap if
// no temp dir yields a mappable file (read-only or tmpfs-only dirs, or mmap refused) — same interface, just
// not disk-paged.

#include "core/error/error_macros.h"

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <sys/mount.h> // statfs lives here on macOS/BSD
#else
#include <sys/statfs.h>
#endif
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace voxel_dc {
namespace dc_mesh {

// Set true if ANY arena failed to get a disk-backed temp file and fell back to anonymous (RAM) memory — the
// OOM-safety is then GONE. The game surfaces this as an in-game pop-up so it can never be a silent surprise.
inline bool g_arena_anon_fallback = false;
inline char g_arena_dir[256] = { 0 }; // the disk dir an arena actually used (empty if fell back to anon)
inline constexpr long DC_TMPFS_MAGIC = 0x01021994; // tmpfs is RAM-backed — skip it (would defeat disk paging)

// True if `d` is on a RAM-backed filesystem. Linux reports tmpfs by magic number; macOS by type name.
inline bool dc_dir_is_ram_backed(const char *d) {
	struct statfs sfb;
	if (statfs(d, &sfb) != 0) {
		return false;
	}
#if defined(__APPLE__)
	return strcmp(sfb.f_fstypename, "tmpfs") == 0;
#else
	return long(sfb.f_type) == DC_TMPFS_MAGIC;
#endif
}

// DC_ARENA_FAIL_DISK_MMAP refuses the disk mapping in one temp dir (value = that dir, exactly as tried) or in
// every dir ("*"), so a test can drive the mmap-failure paths: no real failure of a valid fd can be induced
// deterministically on demand.
inline void *dc_arena_disk_mmap(const char *dir, int fd, int64_t bytes) {
	const char *fail = getenv("DC_ARENA_FAIL_DISK_MMAP");
	if (fail != nullptr && (strcmp(fail, "*") == 0 || strcmp(fail, dir) == 0)) {
		return MAP_FAILED;
	}
	return mmap(nullptr, bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
}

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
		// Try real-disk temp dirs in order; a dir whose file can't be mapped must not end the search.
		const char *dirs[] = { getenv("DC_ARENA_DIR"), "./tmp", "/var/tmp" };
		for (const char *d : dirs) {
			if (_map_disk(d)) {
				return;
			}
		}
		g_arena_anon_fallback = true; // OOM-safety lost — the game pops a warning about this
		base = (T *)mmap(nullptr, _bytes, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
		CRASH_COND_MSG(base == MAP_FAILED, "MmapArena: mmap failed (out of address space?)");
	}

	// True once `base` maps a fresh temp file in `dir`. The file is unlinked at birth, so closing the fd on
	// any later failure is the whole cleanup — nothing is left on disk.
	bool _map_disk(const char *dir) {
		if (dir == nullptr || dir[0] == '\0' || dc_dir_is_ram_backed(dir)) {
			return false; // RAM-backed would defeat disk paging
		}
		char tmpl[300];
		snprintf(tmpl, sizeof(tmpl), "%s/dc_arena_XXXXXX", dir);
		const int file = mkstemp(tmpl);
		if (file < 0) {
			return false;
		}
		unlink(tmpl); // the open fd keeps the inode for MAP_SHARED; auto-removed on close

		void *mapped = ftruncate(file, _bytes) == 0 ? dc_arena_disk_mmap(dir, file, _bytes) : MAP_FAILED;
		if (mapped == MAP_FAILED) {
			close(file);
			return false;
		}
		fd = file;
		base = (T *)mapped;
		strncpy(g_arena_dir, dir, sizeof(g_arena_dir) - 1);
		return true;
	}

	int64_t size() const { return _size; }
	bool is_empty() const { return _size == 0; }

	// Hard ceiling: slots this arena can hold (int-index-safe, set on first growth). The build/grow must stop
	// below this — exceeding it overflows the int cell indices and trips the resize_uninitialized abort.
	int64_t capacity() const { return _cap; }

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
#if defined(__APPLE__)
		char *vec = (char *)malloc(CHUNK); // macOS mincore takes char *
#else
		unsigned char *vec = (unsigned char *)malloc(CHUNK);
#endif
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
