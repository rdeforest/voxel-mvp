class_name EditSource
extends RefCounted

# Who made an edit to matter. Every matter-changed event carries one, so a subscriber decides what
# to react to from a fact rather than inferring it from world state (DetachmentScout used to guess
# "MPM made it" from MPM having particles in flight). docs/roadmap/design/04-event-bus.md.

enum Kind {
    PLAYER,       # a gameplay verb the player used (ActionFactories)
    INSTRUMENT,   # a console / debug tool write (mpmthaw, the planned exact writes)
    MPM,          # the structural sim returning settled material to the store (freeze)
    SCOUT,        # DetachmentScout thawing a component it proved detached
    REPLAY,       # a recorded scenario step being re-executed
}
