# The Hytale Case Study — How to Burn $100M and Ship Nothing

A cautionary tale, with specific lessons mapped to this project. The
one-line version lives in the manifesto: **ship the working thing.**

## Timeline

- **2015–2018:** Small team of Minecraft modders builds a working voxel
  game engine in C#/Java. By 2018, the game is nearly ready for launch.
  Announcement trailer gets 60 million views.
- **2020:** Riot Games acquires Hypixel Studios. Funding secured, scope
  begins expanding.
- **2022:** Decision to rewrite the entire engine in C++ for simultaneous
  cross-platform launch (PC, mobile, console). Seven years of working
  code is effectively thrown away.
- **2022–2025:** Engine rewrite consumes all development momentum.
  Working features are scrapped and rebuilt from scratch, often with
  worse results. Veteran developers watch their code get replaced. Key
  people leave under stress.
- **June 2025:** Riot cancels Hytale after $100M+ spent. Studio closure
  announced.
- **November 2025:** Original founder Simon Collins-Laflamme buys back
  the IP with personal funds. Rehires 30 developers. Reverts to the
  four-year-old legacy build.
- **January 2026:** Ships early access in eight weeks. It's rough but
  playable. Critics note that Riot probably could have shipped this
  years ago.

## What actually went wrong

It was not a technology problem. It was not a talent problem. It was an
organizational and decision-making problem.

**1. The engine rewrite was unjustified.**
The original C#/Java engine worked. It produced the trailer that got 60
million views. The rewrite was driven by Riot's desire for simultaneous
cross-platform launch — a business requirement, not a technical
necessity. The right answer was: ship on PC first, port later. The
founders eventually proved this by shipping the legacy build in eight
weeks.

**2. New leadership disrespected existing expertise.**
The former IT lead's assessment: "What could possibly go wrong when you
hire new leadership that thinks the original team is incompetent? The
whole project ends up going in circles until it dies." Producers with
"real game industry experience" were brought in and proceeded to rewrite
systems that already worked, not because they were broken but because
the new people hadn't built them.

**3. Scope creep was driven by corporate metrics, not player needs.**
Riot wanted a "forever platform" on every device simultaneously. The
original team wanted to ship a moddable PC sandbox game. The original
team was right. The market they were targeting (Minecraft's audience)
lives on PC. Mobile and console could have followed.

**4. Perfectionism replaced shipping.**
The rewritten engine was perpetually "almost ready" but never playable.
Meanwhile, the legacy build sat in a Git repository, functional but
abandoned. The team optimized for the long game instead of the fastest
path to a playable release. Three years of infrastructure work produced
nothing players could touch.

**5. Money made things worse, not better.**
$100M funded a 150-person team that produced less than the original
30-person team had in 2018. More people meant more coordination
overhead, more competing visions, more process, and less velocity. The
founder's eventual solution — buy it back, rehire 30 people, ship in
eight weeks — proves that a focused small team outperforms a bloated one.

## Lessons for this project

These are not abstract principles. They are specific engineering
decisions:

**Ship the working thing.** The v0.0 checkpoint existed to prevent
Hytale syndrome. The thesis is now defended; v0.1 is the next "ship the
working thing" milestone. Resist the urge to retreat into infrastructure
work.

**Never rewrite to satisfy a hypothetical future requirement.** Godot
4.6 + godot_voxel is good enough for the current phase. The eventual
DC-QEF transition is *not* "rewriting to satisfy a hypothetical" — it's
replacing one specific layer (meshing) with the architecture the thesis
requires, while keeping storage, streaming, and LOD borrowed. That
distinction matters.

**PC first. Everything else later.** Linux first, macOS second, Windows
when there's demand. Cross-platform is a distribution problem, not an
architecture problem. Godot handles the engine layer; the game code
stays portable.

**Stay solo (or very small) as long as possible.** Every person added to
a project introduces communication overhead and competing vision. Claude
Code is a force multiplier that doesn't argue about architecture *the
way humans do* — though see the manifesto on the Enterprise trap for the
ways it argues that are still wrong. A solo developer with AI assistance
and clear vision will outpace a confused team of 150 every time.

**Data-driven design enables future flexibility without premature
engineering.** Items, recipes, biomes, and materials defined in `.tres`
files or JSON. Mod support is a side effect of good architecture, not a
feature you build. This is the right kind of future-proofing — it costs
nothing now and pays off later.

**The engineer was right: "It's simple, just X."** Collins-Laflamme
proved this. The game was there in 2018. It was there in the legacy
build in 2025. It took eight weeks to dust it off and ship it. Sometimes
when an engineer says "it's simple, just ship the thing we already
have," they are correct, and the people adding complexity are the ones
who need to justify their position — not the other way around.
