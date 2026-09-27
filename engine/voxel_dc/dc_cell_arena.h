#ifndef DC_CELL_ARENA_H
#define DC_CELL_ARENA_H

// A growable array of POD T in fixed-size RAM blocks with a hard capacity, for the octree's cell storage
// (doc 20, M2). Growth allocates whole new blocks and never moves or copies existing elements, so a
// multi-gigabyte arena grows without a transient 2x copy or stall, and an element's address is stable
// for the arena's lifetime. The block table is sized for the full capacity at construction, so it never
// reallocates either: parallel readers stay valid while a serial caller grows the arena.
//
// Capacity is a contract, not a soft limit: callers check room() before growing (the octree turns a full
// arena into a graceful stop in refinement). Exceeding it is a caller bug and aborts.

#include "core/error/error_macros.h"
#include "core/os/memory.h"

#include <cstdint>

namespace voxel_dc {
namespace dc_mesh {

template <typename T>
struct CellArena {
	static constexpr int BLOCK_SHIFT = 16;
	static constexpr int64_t BLOCK   = int64_t(1) << BLOCK_SHIFT;
	static constexpr int64_t MASK    = BLOCK - 1;

	T **blocks        = nullptr;
	int64_t _size     = 0;
	int64_t _cap      = 0;
	int64_t _n_blocks = 0;

	explicit CellArena(int64_t capacity) :
			_cap(capacity) {
		const int64_t slots = (capacity + MASK) >> BLOCK_SHIFT;
		blocks = (T **)memalloc_zeroed(size_t(slots) * sizeof(T *));
	}

	CellArena(const CellArena &) = delete;
	CellArena &operator=(const CellArena &) = delete;

	~CellArena() {
		for (int64_t b = 0; b < _n_blocks; ++b) {
			memfree(blocks[b]);
		}
		memfree(blocks);
	}

	int64_t size() const { return _size; }
	int64_t capacity() const { return _cap; }
	int64_t room() const { return _cap - _size; }

	// RAM actually held: whole blocks, including the unused tail of the last one.
	int64_t allocated_bytes() const { return _n_blocks * BLOCK * int64_t(sizeof(T)); }

	T &operator[](int64_t i) { return blocks[i >> BLOCK_SHIFT][i & MASK]; }
	const T &operator[](int64_t i) const { return blocks[i >> BLOCK_SHIFT][i & MASK]; }

	void push_back(const T &v) {
		_grow_to(_size + 1);
		(*this)[_size - 1] = v;
	}

	// New slots are uninitialized; the caller fills every one (the level-sync build does it in parallel).
	void resize_uninitialized(int64_t n) {
		_grow_to(n);
	}

	void _grow_to(int64_t n) {
		CRASH_COND_MSG(n > _cap, "CellArena: grown past capacity (the caller must check room())");
		const int64_t need = (n + MASK) >> BLOCK_SHIFT;
		for (; _n_blocks < need; ++_n_blocks) {
			blocks[_n_blocks] = (T *)memalloc(size_t(BLOCK) * sizeof(T));
			CRASH_COND_MSG(blocks[_n_blocks] == nullptr, "CellArena: out of memory below the cell budget");
		}
		_size = n;
	}
};

} // namespace dc_mesh
} // namespace voxel_dc

#endif // DC_CELL_ARENA_H
