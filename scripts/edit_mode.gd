class_name EditMode
extends RefCounted

var mode_name:            String
var make_action:          Callable  # (hit_pos, hit_normal) -> Action
var get_preview_mesh:     Callable
var get_preview_material: Callable
var get_preview_position: Callable
var get_preview_basis:    Callable  # optional; (hit_pos, hit_normal) -> Basis
var get_axis_arrow:       Callable  # optional; () -> Vector3 local-axis dir (ZERO = no arrow)
var allows_air_placement: bool = false  # show a ghost at a fixed distance when aiming at nothing
var acts_on_air:          bool = true   # a click on an air target actually acts (false = inert preview only)
var get_air_distance:     Callable      # optional; () -> float air-preview distance (else AIR_PLACE_DISTANCE)
var uses_placement_offset: bool = false # Shift+W/A/E + wheel nudges the target
var keep_offset_on_action: bool = false # don't reset the offset after acting (e.g. Probe)
var csg_shape:            int  = -1     # CsgSdf.Shape for CSG activities; -1 = not a CSG mode

func named(                p_name: String)   -> EditMode:
    mode_name            = p_name
    return self

func on_make_action(       fn:     Callable) -> EditMode:
    make_action          = fn
    return self

func preview_mesh(         fn:     Callable) -> EditMode:
    get_preview_mesh     = fn
    return self

func preview_material(     fn:     Callable) -> EditMode:
    get_preview_material = fn
    return self

func preview_position(     fn:     Callable) -> EditMode:
    get_preview_position = fn
    return self

func preview_basis(        fn:     Callable) -> EditMode:
    get_preview_basis    = fn
    return self

func axis_arrow(           fn:     Callable) -> EditMode:
    get_axis_arrow       = fn
    return self

func shape(                p_shape: int)     -> EditMode:
    csg_shape            = p_shape
    return self

func air_placement(        enabled: bool)    -> EditMode:
    allows_air_placement = enabled
    return self

func act_on_air(           enabled: bool)    -> EditMode:
    acts_on_air          = enabled
    return self

func air_distance(         fn:     Callable) -> EditMode:
    get_air_distance     = fn
    return self

func placement_offset(     enabled: bool)    -> EditMode:
    uses_placement_offset = enabled
    return self

func keep_offset(          enabled: bool)    -> EditMode:
    keep_offset_on_action = enabled
    return self
