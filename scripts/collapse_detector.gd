class_name CollapseDetector
extends RefCounted

# Detects connected components of unsupported voxels and converts them
# into falling rigid bodies. Designed to be invoked by StructuralIntegrity
# after its dirty queue settles.
#
# A voxel is a "fall candidate" when its support has decayed to (effectively)
# zero. We flood-fill across candidate voxels to find connected components.
#
# A detected component does NOT collapse immediately. It becomes a *pending
# collapse* with a strain countdown (see VoxelConstants.STRAIN_DURATION_SEC).
# During the window:
#   - if the player adds support (the voxel_support_increased signal fires
#     for one of its voxels), the timer is reset toward full;
#   - if enough support is added that the component is no longer a fall
#     candidate at all, the pending collapse is cancelled and its voxels
#     return to ordinary tracked status;
#   - if the timer expires while still a fall candidate, the component is
#     materialized into a falling rigid body.
#
# This is the cave-reinforcement loop: the structure creaks, the player
# scrambles, the structure is either saved or lost.

# A single component-in-progress carried across frames if the flood
# exceeds the budget.
var _pending_floods: Array = []  # of { voxels: Array[Vector3i], frontier: Array[Vector3i], visited: Dictionary }

# Coordinates already claimed this detection pass, OR claimed by a still-live
# pending collapse. Used so a second scan doesn't re-flood the same mass and
# so a pending component's neighbours can't start an overlapping flood.
# Per-pass claims are cleared at the end of step(); pending-collapse claims
# persist until the pending collapse resolves (materialize or cancel).
var _claimed: Dictionary = {}

# Active pending collapses, each a dict:
#   {
#     voxels:        Array[Vector3i],  # the connected component
#     voxel_set:     Dictionary,       # Vector3i -> true, for O(1) membership
#     strained:      float,            # seconds of strain accumulated so far
#   }
#
# `strained` counts UP from 0 toward STRAIN_DURATION_SEC, accumulated against
# the physics `delta`. It deliberately does NOT use Time.get_ticks_msec():
# wall-clock time keeps running while the game is paused, which would expire
# strain windows during a pause. Accumulating `delta` inside _physics_process
# is automatically pause-correct (physics processing stops when the tree is
# paused) and frame-hitch-correct (delta is the true step length).
var _pending_collapses: Array = []

# Flat index: Vector3i -> the pending-collapse dict that contains it.
# Lets the support-increased signal handler find a voxel's pending collapse
# in O(1) without scanning _pending_collapses.
var _voxel_to_pending: Dictionary = {}

# Back-reference to the integrity manager (provides voxel_data, terrain,
# and voxel removal helpers).
var _integrity: Node


func _init(integrity: Node) -> void:
    _integrity = integrity
    # React to support being added back to voxels. Synchronous: this handler
    # runs inside StructuralIntegrity's propagation loop at emit time.
    _integrity.voxel_support_increased.connect(_on_voxel_support_increased)


# Called by StructuralIntegrity once the propagation dirty_queue is empty.
# Detects new unsupported components and files them as pending collapses.
#
# The work is three ordered phases. The first two can run out of detection
# budget mid-phase; when that happens they return false and step() bails,
# resuming next frame. Only if both phases complete do we recycle the
# per-pass claim set.
#
# (No return value: nothing currently consumes a "did anything happen?"
# signal. If a caller ever needs that, give the phases progress tracking
# then — don't thread an unused value through speculatively.)
func step() -> void:
    if not _resume_unfinished_floods():
        return  # budget exhausted; a flood resumes next frame
    if not _scan_for_new_collapses():
        return  # budget exhausted mid-scan; resumes next frame
    _reset_claims_to_pending()


# Phase 1: continue any flood that didn't finish in a previous frame.
# Returns false if budget ran out with a flood still in progress (step()
# should bail and resume next frame); true if all carried-over floods are
# now complete.
#
# KNOWN LIMIT (v0.1 perf-tuning): this advances each pending flood by exactly
# one DETECTION_BUDGET slice per step(), and step() only runs on frames where
# the propagation dirty_queue is empty. A single connected component larger
# than DETECTION_BUDGET therefore takes multiple settled frames to fully
# detect, and a continuous stream of edits that keeps the dirty_queue busy
# can starve phase 1 entirely. Not a correctness bug — detection just lags.
# The fix is budget profiling (how big is a realistic worst-case component?)
# and possibly advancing multiple floods per step; deferred until there are
# real numbers to tune against.
func _resume_unfinished_floods() -> bool:
    while not _pending_floods.is_empty():
        var flood: Dictionary = _pending_floods[0]
        var finished := _advance_flood(flood, VoxelConstants.DETECTION_BUDGET)
        if not finished:
            return false  # budget exhausted; resume this same flood next frame
        _pending_floods.pop_front()
        if not flood.voxels.is_empty():
            _begin_pending_collapse(flood.voxels)

    return true


# Phase 2: scan tracked voxels for new fall candidates and flood each into a
# connected component. Returns false if a fresh flood ran out of budget (it
# has been parked in _pending_floods and step() should bail); true if the
# whole scan completed.
func _scan_for_new_collapses() -> bool:
    for pos in _integrity.voxel_data.keys():
        if _claimed.has(pos):
            continue
        # Seeding is conservative: only start a flood from a voxel whose
        # support has settled (see _can_seed_collapse). Flood *expansion*,
        # by contrast, is permissive — see _advance_flood.
        if not _can_seed_collapse(pos):
            continue

        var flood := {
            "voxels":   [] as Array,
            "frontier": [pos] as Array,
            "visited":  { pos: true },
        }
        _claimed[pos] = true

        var finished := _advance_flood(flood, VoxelConstants.DETECTION_BUDGET)
        if not finished:
            _pending_floods.append(flood)
            return false  # ran out of budget; pick up next frame

        if not flood.voxels.is_empty():
            _begin_pending_collapse(flood.voxels)

    return true


# Accumulates strain on every pending collapse by `delta`. Called every frame
# by StructuralIntegrity, unconditionally — strain must accumulate even while
# the dirty queue is busy.
#
# Per pending collapse, each tick:
#   - if it is no longer a fall candidate at all -> cancel (voxels recovered);
#   - else accumulate `delta` of strain, and if it has reached the full
#     duration -> materialize the collapse;
#   - else -> keep straining.
func tick_pending(delta: float) -> void:
    if _pending_collapses.is_empty():
        return

    # Iterate a copy of indices back-to-front so we can remove in place.
    for i in range(_pending_collapses.size() - 1, -1, -1):
        var pc: Dictionary = _pending_collapses[i]

        if not _component_still_falling(pc):
            # Enough support came back: the component is saved.
            _cancel_pending_collapse(i)
            continue

        pc.strained += delta
        if pc.strained >= VoxelConstants.STRAIN_DURATION_SEC:
            # Strain window elapsed with the mass still unsupported. It falls.
            _materialize_pending_collapse(i)


# Returns the set (Vector3i -> true) of every voxel currently in a pending
# collapse. StructuralIntegrity uses this to pulse their debug markers.
func get_straining_voxels() -> Dictionary:
    return _voxel_to_pending


# --- Signal handler -------------------------------------------------------

# Fired (synchronously) by StructuralIntegrity when a voxel's support is
# recalculated meaningfully higher than before. If that voxel belongs to a
# pending collapse, the player has propped it up — rewind its strain.
func _on_voxel_support_increased(
        pos: Vector3i, _old_support: float, _new_support: float) -> void:
    # No-op if the voxel isn't part of any pending collapse. This is the
    # common case during a cascade: support-increased signals fire long
    # before (or entirely without) a voxel ever becoming a pending collapse.
    if not _voxel_to_pending.has(pos):
        return

    var pc: Dictionary = _voxel_to_pending[pos]
    # Rewind accumulated strain so that at least STRAIN_RESET_SEC of the
    # window remains. min() means adding support can only ever *help* — it
    # never advances strain on a component that was already fresher than the
    # reset point.
    #
    # Concretely with a 3.0s window and 2.7s reset: a component that has
    # strained 2.5s gets rewound to 0.3s (2.7s left). One that has only
    # strained 0.1s is left alone (it already has 2.9s left).
    var reset_floor := VoxelConstants.STRAIN_DURATION_SEC \
        - VoxelConstants.STRAIN_RESET_SEC
    pc.strained = minf(pc.strained, reset_floor)


# --- Pending-collapse lifecycle -------------------------------------------

# Turn a freshly detected connected component into a pending collapse:
# start its strain timer and index every voxel so the signal handler and
# the claim system can find it.
func _begin_pending_collapse(voxels: Array) -> void:
    var voxel_set: Dictionary = {}
    for v in voxels:
        voxel_set[v] = true

    var pc := {
        "voxels":    voxels,
        "voxel_set": voxel_set,
        "strained":  0.0,
    }
    _pending_collapses.append(pc)

    # Index voxels -> this pending collapse, and keep them claimed so the
    # detector won't re-flood them while they're straining.
    for v in voxels:
        _voxel_to_pending[v] = pc
        _claimed[v] = true


# A pending collapse was saved: the player added enough support that the
# component is no longer falling. Drop it from tracking and re-dirty its
# voxels' neighbours so support can re-propagate through what is now, again,
# ordinary standing structure.
func _cancel_pending_collapse(index: int) -> void:
    var pc: Dictionary = _pending_collapses[index]

    for v in pc.voxels:
        _voxel_to_pending.erase(v)
        _claimed.erase(v)
        # The voxel went from "doomed" back to "fine" — that's a meaningful
        # change for anything resting on it. Re-dirty neighbours so the
        # propagation system re-evaluates them.
        _redirty_neighbors(v)

    _pending_collapses.remove_at(index)


# A pending collapse's strain window elapsed. Hand the component off to the
# (unchanged) materialization path, then drop it from tracking.
func _materialize_pending_collapse(index: int) -> void:
    var pc: Dictionary = _pending_collapses[index]

    for v in pc.voxels:
        _voxel_to_pending.erase(v)
        _claimed.erase(v)

    _pending_collapses.remove_at(index)
    _materialize_collapse(pc.voxels)


# True while at least one voxel of the component is still a fall candidate.
# A pending collapse stays pending as long as *any* part of it is unsupported;
# it is only cancelled once the whole component has recovered.
func _component_still_falling(pc: Dictionary) -> bool:
    for v in pc.voxels:
        # A voxel that was removed from the world entirely (e.g. the player
        # dug it out) is no longer this component's problem, but the rest of
        # the component might still be falling — so skip, don't bail.
        if not _integrity.voxel_data.has(v):
            continue
        if _is_fall_candidate(v):
            return true
    return false


# Re-dirty a voxel's tracked neighbours so propagation re-evaluates them.
func _redirty_neighbors(pos: Vector3i) -> void:
    for neighbor in _neighbors(pos):
        if _integrity.voxel_data.has(neighbor) \
                and not _integrity.voxel_data[neighbor].dirty:
            _integrity.voxel_data[neighbor].dirty = true
            _integrity.dirty_queue.append(neighbor)


# Clear per-pass claims while preserving claims held by live pending
# collapses. Called at the end of each step().
func _reset_claims_to_pending() -> void:
    _claimed.clear()
    for pc: Dictionary in _pending_collapses:
        for v in pc.voxels:
            _claimed[v] = true


# --- Flood fill (unchanged) -----------------------------------------------

# Advance one flood by up to `budget` voxels. Returns true when the
# flood is complete (frontier is empty).
func _advance_flood(flood: Dictionary, budget: int) -> bool:
    var voxels:   Array      = flood.voxels
    var frontier: Array      = flood.frontier
    var visited:  Dictionary = flood.visited

    var processed := 0
    while not frontier.is_empty() and processed < budget:
        var pos: Vector3i = frontier.pop_back()
        voxels.append(pos)
        _claimed[pos] = true
        processed += 1

        for neighbor in _neighbors(pos):
            if visited.has(neighbor):
                continue
            # We only flood across other fall candidates. Boundaries
            # (supported tracked voxels, solid terrain, air) terminate
            # the expansion at this neighbor.
            if not _integrity.voxel_data.has(neighbor):
                continue
            if not _is_fall_candidate(neighbor):
                continue
            visited[neighbor] = true
            frontier.append(neighbor)

    return frontier.is_empty()


# Should a flood be SEEDED from this voxel? Conservative: requires that the
# voxel's support has finished propagating. We won't *start* a collapse from
# a support value that is still settling — it might be on its way back up.
#
# This is the strict half of what used to be a single _is_fall_candidate.
# Used only by the phase-2 seed scan.
func _can_seed_collapse(pos: Vector3i) -> bool:
    if not _integrity.voxel_data.has(pos):
        return false
    var data: Dictionary = _integrity.voxel_data[pos]
    if data.dirty:
        return false  # support not finalized; don't seed a flood from it
    return data.support <= VoxelConstants.FALL_THRESHOLD


# Should a flood EXPAND into this voxel — and, separately, is this voxel still
# falling when re-checked during the strain window?
#
# Permissive: a voxel whose support is at/below the threshold is part of the
# unsupported component whether or not propagation has fully settled its
# value. `dirty` here means only "this number will be refined," NOT "this
# voxel might not belong." The earlier version excluded dirty voxels and that
# artificially split components that were still cascading — a large structure
# would flood only its already-settled part, strand its still-settling
# (often most-unsupported) voxels, and those would never pulse or fall.
#
# Optimistically flooding a dirty voxel that later recovers is safe: the
# strain window is the grace period. _component_still_falling re-checks every
# voxel every tick through this same predicate, and tick_pending cancels the
# whole pending collapse the moment the component is no longer falling. The
# architecture already absorbs the "flooded in, then recovered" case.
func _is_fall_candidate(pos: Vector3i) -> bool:
    if not _integrity.voxel_data.has(pos):
        return false
    return _integrity.voxel_data[pos].support <= VoxelConstants.FALL_THRESHOLD


func _neighbors(pos: Vector3i) -> Array:
    return [
        pos + Vector3i( 1,  0,  0),
        pos + Vector3i(-1,  0,  0),
        pos + Vector3i( 0,  1,  0),
        pos + Vector3i( 0, -1,  0),
        pos + Vector3i( 0,  0,  1),
        pos + Vector3i( 0,  0, -1),
    ]


# --- Materialization (unchanged) ------------------------------------------

# Take a connected component of unsupported voxels and turn it into a falling
# rigid body. For v0.0 we use greedy axis-aligned box merge for collision and
# a simple BoxMesh-per-merged-box for visuals. (We can switch to slicing the
# existing voxel mesh later; that's a polish pass.)
func _materialize_collapse(voxels: Array) -> void:
    # Compute centroid (used to position the rigid body's origin).
    var centroid := Vector3.ZERO
    for v in voxels:
        centroid += Vector3(v)
    centroid /= float(voxels.size())
    # Voxel-grid cells are VOXEL_SIZE meters; offset to cell center.
    centroid += VoxelConstants.VOXEL_CENTER_OFFSET

    # Greedy merge into the minimum set of axis-aligned boxes.
    var voxel_set: Dictionary = {}
    for v in voxels:
        voxel_set[v] = true
    var boxes := _greedy_merge_boxes(voxel_set)

    # Build the rigid body.
    var body := RigidBody3D.new()
    body.global_position = centroid

    # Mass scales with voxel count (1kg per voxel for now; revisit per-material).
    body.mass = float(voxels.size())

    body.can_sleep = false

    for box in boxes:
        # box is { min: Vector3i, size: Vector3i }
        var box_center_local := Vector3(box.min) + Vector3(box.size) * 0.5 - centroid

        var shape := BoxShape3D.new()
        shape.size = Vector3(box.size)
        var collider := CollisionShape3D.new()
        collider.shape = shape
        collider.position = box_center_local
        body.add_child(collider)

        var mesh := BoxMesh.new()
        mesh.size = Vector3(box.size)
        var mi := MeshInstance3D.new()
        mi.mesh = mesh
        mi.position = box_center_local
        # Visual: brown-ish so we can see it falling. Real material color TBD.
        var mat := StandardMaterial3D.new()
        mat.albedo_color = Color(0.45, 0.30, 0.18)
        mi.material_override = mat
        body.add_child(mi)

    # Parent into the world (sibling of the terrain).
    _integrity.get_parent().add_child(body)

    # Clear the source voxels from the SDF terrain and the integrity tracker.
    # This will dirty neighbors and may trigger cascading collapses next pass.
    var voxel_tool: VoxelTool = _integrity.terrain.get_voxel_tool()
    voxel_tool.channel = VoxelBuffer.CHANNEL_SDF
    voxel_tool.mode = VoxelTool.MODE_REMOVE
    for v in voxels:
        # Set SDF positive (air) at each cell. do_sphere with radius < 1
        # would be approximate; set_voxel_f is exact.
        # We set the value to 5 to account for the interpolation of the SDF value.
        voxel_tool.set_voxel_f(v, VoxelConstants.SDF_AIR)
        _integrity.remove_voxel(v)


# Greedy axis-aligned box merge. Walks voxels in scan order, grows each
# starting voxel as far as it can in +X, then +Y, then +Z while all cells
# in the candidate box are members of the set and not yet consumed.
# Not optimal, but produces a small number of boxes for slab-shaped masses.
func _greedy_merge_boxes(voxel_set: Dictionary) -> Array:
    var consumed: Dictionary = {}
    var boxes: Array = []

    # Stable iteration order so the merger is deterministic.
    var keys: Array = voxel_set.keys()
    keys.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
        if a.y != b.y: return a.y < b.y
        if a.z != b.z: return a.z < b.z
        return a.x < b.x)

    for start: Vector3i in keys:
        if consumed.has(start):
            continue

        # Grow in +X.
        var sx := 1
        while voxel_set.has(start + Vector3i(sx, 0, 0)) \
                and not consumed.has(start + Vector3i(sx, 0, 0)):
            sx += 1

        # Grow in +Z, requiring the full X-strip to be available at each step.
        var sz := 1
        while true:
            var z_ok := true
            for dx in range(sx):
                var p := start + Vector3i(dx, 0, sz)
                if not voxel_set.has(p) or consumed.has(p):
                    z_ok = false
                    break
            if not z_ok:
                break
            sz += 1

        # Grow in +Y, requiring the full X*Z slab to be available at each step.
        var sy := 1
        while true:
            var y_ok := true
            for dx in range(sx):
                for dz in range(sz):
                    var p := start + Vector3i(dx, sy, dz)
                    if not voxel_set.has(p) or consumed.has(p):
                        y_ok = false
                        break
                if not y_ok:
                    break
            if not y_ok:
                break
            sy += 1

        # Mark every voxel in this box as consumed.
        for dx in range(sx):
            for dy in range(sy):
                for dz in range(sz):
                    consumed[start + Vector3i(dx, dy, dz)] = true

        boxes.append({
            "min":  start,
            "size": Vector3i(sx, sy, sz),
        })

    return boxes
