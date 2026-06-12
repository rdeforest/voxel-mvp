class_name VoxelConstants

# ============================================================================
# Voxel grid geometry
# ============================================================================
# The world coordinate length of one voxel cell along each axis.
# Voxel positions in Vector3i are multiplied by this to get world positions.
# Changing this scales the entire world; not a per-session tunable.
const VOXEL_SIZE := 1.0

# Half-cell offset, used to convert voxel-grid coordinates (cell corners) to
# cell centers for physics, rendering, and centroid calculations.
const VOXEL_HALF := VOXEL_SIZE * 0.5

# Vector3 form of (VOXEL_HALF, VOXEL_HALF, VOXEL_HALF), useful for centering.
# Computed at class load so callsites don't allocate per use.
const VOXEL_CENTER_OFFSET := Vector3(VOXEL_HALF, VOXEL_HALF, VOXEL_HALF)

# Identifies which voxel grid an event/edit targets. Single grid today (0); in
# every event payload from day one so multi-grid (deferred) lands without churn.
const GRID_ID := 0

# Sub-metre RENDER/EDIT resolution — the finest world cell the DC render, edit imprints,
# collision, and the MPM carve/freeze operate at. SEPARATE from VOXEL_SIZE: the gameplay /
# structural / event grid stays at VOXEL_SIZE (1m), but the surface is sampled and meshed this
# fine. MUST be 1/2^n so the clipmap's `1<<k` level math stays an exact power-of-two relationship
# to world (RENDER_SUBDIV = 1/RENDER_BASE_CELL, a power of two). Stage 0 keeps this at 1.0 (no
# behaviour change); the sub-metre flip sets it to 0.25.
const RENDER_BASE_CELL := 0.25
const RENDER_SUBDIV    := 4     # int(round(1.0 / RENDER_BASE_CELL)); power of two
# log2(RENDER_SUBDIV) — extra LOD levels the render adds so the clipmap reaches the same WORLD
# distance as at 1m (the finer base cell shrinks the octree's world extent by RENDER_SUBDIV, so we
# add one octave of coverage per halving). MUST equal log2(RENDER_SUBDIV): 1.0→0, 0.5→1, 0.25→2.
const RENDER_SUBDIV_LOG2 := 2


# ============================================================================
# Support scalar
# ============================================================================
# The structural-support scalar runs [0, 1]: 0 = unsupported, 1 = fully supported
# (direct bedrock/terrain contact). Drives TerrainSupport's suspended-mass discovery.
const NO_SUPPORT   := 0.0
const FULL_SUPPORT := 1.0


# ============================================================================
# SDF (signed distance field) semantics
# ============================================================================
# In Transvoxel SDF terrain, negative values are "inside solid" and positive
# values are "outside / in air". Magnitude carries distance-to-surface info
# used for interpolation. The mesher draws the surface at the zero-crossing.

# Strongly positive value used when clearing voxels (e.g. after collapse
# extraction). Empirically, +1.0 leaves "ghost geometry" because Transvoxel
# interpolation pulls the surface back toward solid neighbors. +5.0 overrides
# that interpolation reliably.
const SDF_AIR := 5.0

# Strongly negative value used when forcing voxels solid. Symmetric to SDF_AIR.
const SDF_SOLID := -5.0

# Threshold used to distinguish solid from air when querying terrain.
# Strictly less-than-zero is solid; anything else is air.
const SDF_SOLID_THRESHOLD := 0.0

# EditStore brush ops (match EditStore::stamp_* `op`): UNION adds solid, SUBTRACT carves.
const STORE_OP_UNION    := 0
const STORE_OP_SUBTRACT := 1


# ============================================================================
# Structural integrity tuning
# ============================================================================
# Per-frame budget on how many voxels the propagation system processes from
# its dirty queue. Higher = faster settling, more frame-time cost per change.
# Tuned for cascading collapses to feel deliberate without stalling.
const PROPAGATION_BUDGET := 200

# Support value at or below which a voxel is considered a fall candidate.
# Just above zero to avoid floating-point dust. Anything in [0, this] is
# eligible for collapse.
const FALL_THRESHOLD := 0.01

# Minimum support change between propagation passes that re-dirties neighbors.
# Below this, the change is treated as noise and propagation halts.
const SUPPORT_EPSILON := 0.01
