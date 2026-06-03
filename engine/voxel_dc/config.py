# Godot module config for voxel_dc (our Dual Contouring mesher). Depends on the
# `voxel` module (godot_voxel) being present; subclasses its VoxelMesher.


def can_build(env, platform):
    return True


def configure(env):
    pass


def get_doc_classes():
    return [
        "VoxelMesherDC",
    ]


def get_doc_path():
    return "doc_classes"
