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


# ============================================================================
# Support scalar
# ============================================================================
# The structural-support scalar runs [0, 1]: 0 = unsupported, 1 = fully supported
# (direct bedrock/terrain contact). Shared by TerrainSupport and PartSupport.
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
# Also used as the threshold for "support meaningfully increased" when
# deciding whether to reset a pending collapse's strain timer.
const SUPPORT_EPSILON := 0.01


# ============================================================================
# Strain window (pending-collapse delay)
# ============================================================================
# When a connected component loses support, it does not collapse immediately.
# It enters a "straining" state with a countdown. During the window the player
# can add support (a pillar, a beam) to reset the timer and, if they add
# enough, cancel the collapse entirely. This is the cave-reinforcement loop
# in miniature: the structure creaks, you scramble, you either save it or you
# don't.
#
# Full duration of the strain countdown, in seconds. A freshly detected
# unsupported component gets this long before it falls.
#
# NOTE: flat constant for v0.0. The intended v0.1 design reads this from the
# material (a stone fracture should groan longer than a dirt crumble) and
# scales the reset amount by the *nature* of the support change. Both are
# deferred to the in-game building feature work — see roadmap.
const STRAIN_DURATION_SEC := 3.0

# When support is added to a straining component, its accumulated strain is
# rewound so that at least this much of the window remains. For v0.0 this is
# a flat "90% restored" floor: any meaningful support addition buys back most
# of the window, but can never make a fresher component worse.
#
# Concretely: a 3.0s window with this at 2.7s means a component that has
# strained 2.5s is rewound to 0.3s strained (2.7s remaining); a component
# that has only strained 0.1s is left untouched.
#
# The v0.1 upgrade replaces this flat floor with a rewind proportional to how
# much support the player's change actually contributed — a critical pillar
# buys back lots of window, a token prop buys back little.
const STRAIN_RESET_SEC := 2.7

# Debug-visual pulse rate for straining voxels, in full pulses per second.
# Straining voxels oscillate their debug-marker alpha so the strain window is
# readable at a glance — distinct from a voxel that is merely unsupported.
const STRAIN_PULSE_HZ := 2.5
