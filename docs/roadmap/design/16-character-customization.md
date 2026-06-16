# Character Customization

What avatar creation is, independent of when it ships. The manifesto
supersedes this chapter; if they disagree, the manifesto wins.

Customization is gated behind the in-world discovery of a reflective
surface (see [`../vision/04-volcano-story.md`](../vision/04-volcano-story.md)'s
mirror arc: still water → polished obsidian → polished metal → poured-glass
mirror). This chapter covers *what the player can author about their body*,
not *when they unlock the ability to*.

## Two commitments, held at once

**1. Avatars should look really good.** The default and the achievable
should be genuinely attractive, well-crafted characters. Fidelity is not
sacrificed to support the second commitment.

**2. Avatars should be able to look "ugly" — and that is a feature, not a
failure mode.** The customization system is explicitly an *ally to people
who want an avatar that does not fit "normal" ranges of human shape.* The
full range is offered without the game flinching, editorializing, or
treating departures from a beauty ideal as a penalty.

These are not in tension. A good customization system makes *both* the
striking and the atypical avatar feel deliberately made, not glitched.

## What "the full range" means

The system exposes the underlying body parameters honestly rather than
clamping them to a flattering window:

- **Asymmetry** — left/right need not match. Faces and bodies can be
  unbalanced on purpose.
- **Adipose tissue** — body fat is a first-class, freely-set option across
  the whole range, not a hidden or shamed slider.
- **Skeletal proportion** — "abnormal" lengths and widths of bones. Limbs,
  torso, skull, and so on can sit well outside statistical-average human
  proportion.
- **Missing limbs** — a missing arm is a supported option, represented
  honestly in the rig and animations.

The design intent is affirmative: someone whose body, or whose imagined
body, sits outside the usual range should find themselves *representable
here* without the tool resisting them.

## The one deliberate exclusion

**Missing legs are not an option** — not as a values statement but as a
playability one: locomotion is so central that a legless avatar would make
the game nearly impossible to play, and building the alternative
traversal/animation systems to support it well is out of scope.

This exclusion should be **surfaced honestly in the customization UI** with
a brief in-line note explaining *why* (it's a gameplay limitation, not a
judgment), so its absence doesn't read as the one place the system quietly
decided some bodies don't belong. Naming the reason is consistent with the
"no manipulation the player would resent if they noticed it" pillar — the
player who looks for the seam should find an honest explanation, not a
silent clamp.

(Missing *arms* do not have this problem — they cost some interactions but
don't break traversal — which is why arms are in and legs are out. The line
is mechanical, and the UI should say so.)

## Consistency checks

- **The unremovable wounds** (volcano-story): customization is where the
  player meets the marks they *cannot* edit away — the wounds that put them
  under. The free-customization system and the locked-wound exception must
  coexist: nearly everything is yours to author; a specific few things are
  not, and that contrast is the narrative point. Implementation-wise the
  wounds are a non-editable overlay on an otherwise fully-editable model.
- **All progression is external or epistemic**: body shape is pure
  self-representation. A larger or smaller or asymmetric body grants and
  costs *nothing* mechanically — no hidden strength-from-size, no
  speed-from-leanness. Bodies are identity, not stats. (This is also what
  keeps "make an atypical avatar" from becoming "accept a handicap.")
- **Minimal text / diegetic UI**: the customization screen is one of the few
  places explanatory text is justified (the missing-legs note, the
  reflective-surface framing). Keep it minimal but do not omit the honest
  explanations — this is exactly where silence would be misread.

## Open questions

- **Rig + animation cost of supported atypical bodies.** A missing arm and
  wide proportion ranges multiply the animation-retargeting burden. What's
  the budget, and which ranges are guaranteed to animate cleanly vs.
  best-effort?
- **Third-person and self-view fidelity.** The mirror arc unlocks
  third-person and looking-down-at-one's-own-body; atypical bodies must read
  correctly from those camera positions too, not just in the customization
  pose.
- **How the locked wounds are authored** per-playthrough — fixed set, or
  varied — is a narrative-layer decision that this system must accommodate
  but does not own.
