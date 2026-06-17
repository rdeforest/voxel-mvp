class_name CsgShape
extends RefCounted

# Strategy for one CSG editing primitive: it owns its own dimensions and ALL per-shape
# behaviour — preview mesh, bounds, resizable axes, and signed distance (wrapping the
# CsgSdf math). CsgState delegates to the active shape, so adding a primitive is a new
# subclass, not a new branch in nine methods. `axis` is the resize axis CsgState is
# currently driving; shapes are stateless about it (it lives in CsgState).
#
# Subclasses override everything; the base returns harmless defaults.

const MIN_DIM := 1.0   # smallest extent the resize wheel will leave

func mesh() -> Mesh:                      return null         # preview ghost mesh
func bounding_extent() -> float:          return 1.0          # largest world dimension
func sdf(_local_point: Vector3) -> float: return 1.0          # signed distance, local frame
func local_aabb() -> AABB:                return AABB()       # local bounds, centred at origin
func axis_count() -> int:                 return 1            # resizable axes (the wheel cycles these)
func axis_label(_axis: int) -> String:    return ""
func axis_dir(_axis: int) -> Vector3:     return Vector3.ZERO # local arrow direction; ZERO hides it
func resize_label() -> String:            return ""
func grow(_axis: int, _amount: float) -> void: pass           # resize the given axis
