# Godot's float parser isn't correctly rounded, and reads tiny values as 0

*Filed by Claude (agent), overnight 2026-09-27, from Track G4.0/G4.1's measurements and a follow-up
research pass ([reference note 10](../roadmap/reference/10-godot-float-parsing.md)).*

**Status:** Open. Severity low-med. Upstream bug; we work around it. Needs Robert's call on whether
to post our findings upstream (an outward-facing action).

## Symptom
Every text → double path in the engine (GDScript float literals, `JSON.parse`, `str_to_var`,
`Expression`) goes through Godot's `built_in_strtod`. About 24 % of 17-significant-digit doubles
come back one unit in the last place off. Separately, any value whose net exponent reaches -309 or
below parses as 0: `2.2250738585072014e-308`, every subnormal, and 17-digit values below ~1e-292.
The writer (`JSON.stringify(full_precision)`, grisu2) round-trips correctly; only the reader is
wrong.

## Where it bit us, and the workarounds in place
- Scenario steps: `StepJson` / `ExactDecimal` (G4.1) re-read numbers from their text with correct
  rounding.
- The world snapshot: tracked support and the player are stored as bytes (snapshot v10, G4.2); the
  PartIndex section was already bytes (G4.0).
- Still exposed: any GDScript float literal with 17 significant digits, and any other `JSON.parse`
  or `str_to_var` of doubles.

## Upstream
Open issue [godotengine/godot#123700](https://github.com/godotengine/godot/issues/123700) (2026-09-22)
covers the rounding and proposes fast_float; open PR #123839 fixes only a leading-zeros case. The
underflow-to-0 case is not in the issue. Master is unchanged.

## Options
- Comment on #123700 with the underflow case and the measurement harness (recommended).
- Patch our pinned engine build with fast_float: needs `tools/build` changes, since it refuses a
  modified Godot tree, and breaks the "plain upstream clones" stance in `versions.env`.
- Keep the workarounds and wait for upstream.
