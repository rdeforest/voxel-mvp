# Target Folder Structure

Aspirational. Current state differs; this is where we're going.

```
project/
├── addons/
│   └── zylann.voxel/          # godot_voxel module
├── assets/
│   ├── models/                # CC0 models (Kenney, Quaternius)
│   ├── textures/              # terrain materials, UI
│   ├── sounds/                # CC0 audio
│   └── fonts/
├── scenes/
│   ├── world/
│   │   ├── terrain_generator.gd
│   │   ├── biome_manager.gd
│   │   ├── structural_integrity.gd
│   │   └── world.tscn
│   ├── player/
│   │   ├── player.tscn
│   │   ├── player_controller.gd
│   │   ├── work_action_manager.gd  # continuous mining/logging
│   │   ├── inventory.gd
│   │   └── stats.gd
│   ├── building/
│   │   ├── build_system.gd
│   │   ├── snap_manager.gd
│   │   └── pieces/
│   ├── enemies/
│   │   ├── enemy_base.gd
│   │   ├── pathfinding/
│   │   │   ├── raycast_steering.gd
│   │   │   └── nav_grid_3d.gd
│   │   └── types/
│   └── ui/
│       ├── hud.tscn
│       ├── inventory_ui.tscn
│       ├── crafting_ui.tscn
│       └── work_progress_ui.tscn
├── data/
│   ├── items.json
│   ├── recipes.json
│   ├── materials.json         # structural properties per material
│   └── biomes.json
└── scripts/
    ├── voxel_editor.gd
    ├── resource_node.gd
    └── save_manager.gd
```

Current actual structure is similar but smaller. The aspirational
version assumes Phase 1, 3, and 4 have all landed.
