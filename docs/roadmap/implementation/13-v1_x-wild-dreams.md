# v1.x: Wild Dreams

Larger boundaries to be carved out when we get closer.

- **FEAT083**: Planet-scale world — cube-sphere projection, tectonic
  generation, real oceans. See
  [planet-scale notes in known hard problems](../design/07-known-hard-problems.md).
- **FEAT084**: Sailing as a gameplay loop — across-ocean journeys,
  vessel-vs-vessel combat, navigation.

## Embodied character

The player is a disembodied first-person camera today. These turn that into an
actual character you can see, move expressively, and dress. Roughly in order —
each later one leans on the earlier.

- **FEAT085**: Customizable in-world avatar — a visible player body with
  author-controlled appearance (proportions, face, skin/colour). Foundation for
  everything else here.
- **FEAT086**: Third-person perspective — selectable camera modes (over-shoulder
  / orbit) once there's an avatar worth looking at. Depends on FEAT085.
- **FEAT087**: Full locomotion set — walking, running, jumping, crawling,
  climbing, mantling. Today's movement is walk + jump + fly (`movement.gd`);
  this is the expressive traversal layer, with the animation/state machine to
  match. Depends on FEAT085.
- **FEAT088**: Craftable & customizable clothing — player-authored garments
  (cut, fit, fabric, colour). *"Tailor Simulator 2028."* Implies **cloth
  physics**, which is a meaningful new simulation (and perf) commitment in its
  own right. Depends on FEAT085; cloth sim is the long pole.

## v1.1: Can I Make It Run On Windows?

- **FEAT081**: Cross-compilation to Windows via GitHub Actions
  Windows runners.
- **FEAT082**: Windows-specific testing — driver quirks, filesystem
  paths.

Only worthwhile if Linux/macOS sales demonstrate demand.
