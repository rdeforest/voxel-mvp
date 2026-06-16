# Pets & Companions

What animal companionship is, independent of when it ships. The manifesto
supersedes this chapter; if they disagree, the manifesto wins.

## The thesis

> "If you want a friend, feed any animal." — Jane's Addiction

Companionship is **earned by feeding, not by a tame button.** There is no
capture mechanic, no taming minigame, no loyalty stat. You offer food; an
animal that accepts begins to associate the player with food and safety and
stays nearby of its own apparent accord. The relationship is diegetic and
behavioral, never a UI state the player toggles.

This is the same root value as the rest of the project: the player owns the
world, and the world responds to what the player *does* in it, not to menu
selections (see [`../vision/05-design-pillars.md`](../vision/05-design-pillars.md),
"The player owns the world"). A companion is a creature whose behavior
changed because of how the player treated it.

## The hard target

Get a "yes" on [@CanYouPetTheDog](https://twitter.com/CanYouPetTheDog).
This is a real, falsifiable acceptance criterion, not a joke: petting must
be a first-class interaction with a visible animal response. If you can see
the animal, you can reach out to it — the "if I can see it, I can interact
with it" pillar applies to living things too.

## What pets do

Standard, unglamorous, real-animal jobs — nothing fantastical:

- **Pest control.** A cat-equivalent reduces the small-vermin pressure that
  would otherwise reach the player's stores.
- **Alarm.** A dog-equivalent reacts to approaching fauna or disturbances
  before the player would notice, giving warning through behavior (posture,
  sound, attention direction) rather than a HUD alert. This is a diegetic
  early-warning system, consistent with the minimal-text pillar.
- **Company.** The dream is a lonely place by design (see
  [`../vision/04-volcano-story.md`](../vision/04-volcano-story.md)). A
  companion is emotional furniture as much as a mechanic. This matters more
  than its utility.

## The flip side: unfed animals are not safe to ignore

If the player does **not** offer food, animals are not passive scenery —
they may attempt to **steal** it. This keeps the feeding relationship
honest: the choice is "feed and befriend" vs. "hoard and be raided," not
"feed for bonus" vs. "ignore for free." An animal is an agent pursuing food
either way; the player only decides whether that pursuit is cooperative.

This dovetails with the inventory/containers arc — theft pressure is part of
why a player wants secure storage, and a befriended pest-controller is one
answer to it.

## Consistency checks

- **All progression is external or epistemic** (design pillar): a pet does
  not "level up" and the player gains no companion skill. The relationship
  deepens in *world state* (the animal is present, fed, nearby), not in
  numbers.
- **Comprehension over conquest**: companions are not war assets. They do
  pest control and alarm; they are not directed to attack humanoids, because
  there is no humanoid combat to direct them into.
- **Threat-gating** (reward precedes threat): vermin only become a pressure
  once the player has stores worth raiding; the pest-control value of a pet
  therefore unlocks in step with the player having something to protect.

## Open questions

- **Species roster.** Which tropical-island-plausible animals fill the
  cat-role and dog-role without importing non-native fauna? (The setting's
  realism grammar — everything follows from the island's volcanic history —
  applies.)
- **Death and the dream.** Death is impermanent for the player; is it for a
  companion? A pet that can be permanently lost is a powerful (and possibly
  cruel) emotional lever; a pet that cannot be lost undercuts stakes. This
  is a story decision, not a systems one — defer to the narrative layer.
- **Petting fidelity.** What animation/response budget clears the
  @CanYouPetTheDog bar convincingly rather than minimally.
