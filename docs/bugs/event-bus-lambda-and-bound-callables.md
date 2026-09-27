# Event bus: a lambda or `.bind()`ed subscription fails at its first delivery

*Filed by Claude (agent), overnight 2026-09-27 (Track G1), while updating
[`04-event-bus.md`](../roadmap/design/04-event-bus.md) "Lifetime & cleanup" to the shipped WeakRef
subscriptions.*

**Status:** Open. Severity low (latent): every subscriber in `scripts/` and `scenes/` passes a plain
method of an object, so nothing hits it today.

## Symptom
`subscribe` / `subscribe_cell` accept any `Callable`. Only a plain method of an object works:

| callable subscribed                       | first emit that reaches it                                      |
|-------------------------------------------|-----------------------------------------------------------------|
| `obj.method`                              | delivered                                                       |
| lambda (`func(e): ...`)                   | SCRIPT ERROR "Nonexistent function '<anonymous lambda>'", nothing delivered |
| `obj.method.bind(x)`                      | SCRIPT ERROR "Expected 2 argument(s)", nothing delivered |

`scripts/dev/probe_bus_callable_kinds.gd`, on the session's snapshot engine (Godot 4.6.stable.double
custom build `89cea1439`). A bound method whose extra parameter has a default would, by the same
mechanism, be called without the bound value, silently; not run.

Observed headless: the failing subscription is then pruned. That is incidental, not a failure path
the bus has: the runtime error aborts `Subscription.invoke`, which then returns `false`, and the
dispatch loops read that as a dead subscriber. The same loops carry on, so other subscribers on the
same channel and cell still receive the event (checked with good subscribers placed after bad ones on
both paths, two emits). Under the editor debugger the script error breaks into the debugger instead.

Not tested: a callable whose `get_object()` is null. `weakref(null)` returns null, so
`Subscription.target()` would fail differently (calling `get_ref()` on null).

The bus's header comment said the opposite of the lambda row ("Lambdas have no Object to weakref and
would persist until explicitly removed"); G1 corrected it to what the probe shows.

## Cause
`Subscription` (`scripts/events/voxel_event_bus.gd`) keeps `weakref(callback.get_object())` and
`callback.get_method()`, and delivers with `obj.call(method, event)`. A lambda's `get_object()` is
the object it was created in (or its script), and its `get_method()` is `<anonymous lambda>`, which
that object doesn't have. A bound callable's `get_method()` is the plain method name; the bound
arguments are not kept.

## Options
- Refuse at subscribe: `push_error` and don't subscribe unless the callable is a standard method
  callable (`not is_custom()`) with no bound arguments (`get_bound_arguments_count() == 0`). Keeps
  the WeakRef lifetime rule exact; a test per row above.
- Support them: keep the `Callable` itself for custom/bound callables. That holds a strong reference
  to what the lambda captures, so those subscriptions would need explicit unsubscribe, which is the
  leak the WeakRef design exists to prevent.
