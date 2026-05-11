class_name EditMode
extends RefCounted

var mode_name:            String
var execute:              Callable
var get_preview_mesh:     Callable
var get_preview_material: Callable
var get_preview_position: Callable

func named(                p_name: String)   -> EditMode:
    mode_name            = p_name
    return self

func on_execute(           fn:     Callable) -> EditMode:
    execute              = fn
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
