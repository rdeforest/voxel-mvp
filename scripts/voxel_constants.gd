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


# ============================================================================
# Structural integrity tuning
# ============================================================================
# Per-frame budget on how many voxels the propagation system processes from
# its dirty queue. Higher = faster settling, more frame-time cost per change.
# Tuned for cascading collapses to feel deliberate without stalling.
const PROPAGATION_BUDGET := 200

# Per-frame budget on how many voxels the collapse detector can flood across.
# Independent from propagation budget because detection runs only after
# propagation settles.
const DETECTION_BUDGET := 500

# Support value at or below which a voxel is considered a fall candidate.
# Just above zero to avoid floating-point dust. Anything in [0, this] is
# eligible for collapse.
const FALL_THRESHOLD := 0.01

# Minimum support change between propagation passes that re-dirties neighbors.
# Below this, the change is treated as noise and propagation halts.
const SUPPORT_EPSILON := 0.01
