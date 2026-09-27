# Godot String::to_float — why it's inexact, upstream state, options

_Research notes drafted by Claude (agent), 2026-09-26. Tags: [V] = verified (read the code or ran it), [I] = inference, or taken from a web summary I did not check line by line._

## 1. Local implementation (Godot 89cea1439 = 4.6-stable)

- [V] Every path goes to one function, `built_in_strtod<C>()`, at `core/string/ustring.cpp:2352-2566`.
  - `String::to_float()` is at :2668. The `const char*`, `char32_t*` and `wchar_t*` overloads are at :2575-2585.
  - Callers:
    - GDScript float literals: `modules/gdscript/gdscript_tokenizer.cpp:844`
    - JSON: `core/io/json.cpp:388` and :1079
    - `str_to_var` / VariantParser: `core/variant/variant_parser.cpp:488` → `StringBuffer::as_double()` (`core/string/string_buffer.h:154`) → `String::to_float`
    - Expression: `core/math/expression.cpp:423`
- [V] The algorithm is the classic Tcl/John Ousterhout `strtod` that has been in Godot since the 2014 open-source import (per `git log -L`). It works like this:
  1. It reads at most 18 digits. Extra digits are **truncated**, not rounded. Leading zeros count toward the 18.
  2. `fraction = 1.0e9*frac1 + frac2`. That is two double roundings once the mantissa is more than 2^53.
  3. It builds `dblExp` as a product of `10^(2^i)` from a table. Every entry from 1e32 up is inexact, so each multiply rounds again.
  4. It returns `fraction * dblExp` or `fraction / dblExp`, which is one more rounding.

  With three or more roundings and no correction step, the result is not correctly rounded.
- [V] **Underflow to 0.** The exponent it applies is the written exponent minus the number of fractional digits. When that exponent is -309 or lower, `dblExp` overflows to +inf and `fraction/inf == 0`. So `2.2250738585072014e-308` (net exponent -324), any 17-digit value below about 1e-292, and every subnormal (`4.9e-324`, `1e-309`) parse as 0. The code also clamps the exponent at 511 with a `WARN_PRINT`.
- [V] I compiled the function verbatim in `scratchpad/research/strtod_probe.cpp` and compared it with glibc `strtod`:
  - `%.17g` random doubles with |v| from 1e-280 to 1e300: **48.2%** are off.
  - `%.17g` uniform over (-1e6, 1e6): **15.6%** are off.
  - Examples: `1.8143934130161599` → `…601`; `1.5e-300` → `1.4999999999999998e-300`; `00000000000000000001.5` → 0.

  The 24% you measured falls inside this range and depends on the value distribution.
- [V] The writer (`num_scientific`) uses `thirdparty/grisu2` (`ustring.cpp:1611`). [I] Grisu2 always round-trips but is not guaranteed to give the *shortest* output. Don't assert "shortest" in docs.
- [V] Master is unchanged. The local `origin/master` was fetched 2026-09-26 and is 5965 commits past 4.6. Its `built_in_strtod` is identical except for parameter renames. There is no `fast_float`, `from_chars` or new `thirdparty/` entry, and no master commit mentions strtod, fast_float or from_chars.

## 2. Upstream

- **#123700** (open, 2026-09-22, by luqtas, labels bug, needs testing, topic:core): https://github.com/godotengine/godot/issues/123700
  - It reports the leading-zeros-count-toward-18 bug.
  - It also says about 1 in 6 `num_scientific` outputs read back 1 ulp off.
  - It proposes fast_float as the long-term fix. [I, via web summary] It has no maintainer comments yet.
- **PR #123839** (open, 2026-09-25, by gjain-27): https://github.com/godotengine/godot/pull/123839
  - It only skips leading zeros. It does **not** fix rounding or the underflow-to-0.
- Related and closed, both writer side: #78204 (var_to_str rounding, fixed by #98750, https://github.com/godotengine/godot/issues/78204) and #34541 (to_json precision, https://github.com/godotengine/godot/issues/34541).
- #27706 was float32 noise and was archived.
- [I] I found no godot-proposals entry and no PR that adopts fast_float or `std::from_chars`. The `gh` CLI search timed out, so this relies on web search only and could miss something.

## 3. Options

**(a) Upstream.** #123700 is the right thread to add to. [V] Two things are new relative to that issue:
- The net-exponent ≤ -309 → 0 collapse. It is a separate mechanism: `dblExp` overflows. It is not caused by the digit cap.
- A reproducible measurement harness.

Suggested fix: vendor fast_float, which is header-only and licensed MIT / Apache-2.0 / BSL-1.0.
- [I] It supports char/char16_t/char32_t input through its `UC` template in recent versions. Check this before relying on it.
- The PR must keep Godot's grammar:
  - leading whitespace and `+`
  - `"1."`, `".5"`
  - `"1e"` backs off to before the `e`
  - no `inf`/`nan` text. fast_float accepts these by default, which would change JSON and `str_to_var` behavior.
  - out-of-range results: decide between inf and a clamp
- Cost: a PR plus review. Adding a thirdparty library needs maintainer buy-in. It would realistically land in 4.7/4.8 at the earliest, so it does not help our 4.6 pin.

**(b) Patch our pinned build.** [V] `tools/build` does `git checkout --detach` to `GODOT_REF` from `tools/versions.env`. It also **dies if the Godot tree has uncommitted changes** (`checkout_ref`). The core stamp hashes engine refs, SCons args and platform. A patch applied to the working tree would therefore trip the next run. It needs build-script changes:
1. Add `tools/godot-patches/*.patch`.
2. Reverse-apply the patches before the dirty check, or compare `git diff` with the patch set.
3. Run `git apply` after checkout.
4. Add the patch hashes to the core stamp so a changed patch forces a clean rebuild.

This is moderate work, and it breaks the "plain upstream clones, no forks" stance in versions.env. Pick one of two patch bodies:
- **Vendor fast_float**, about 4k lines of header. Put it in `engine/` to keep the patch small, and include it by path.
- **Keep Godot's grammar scanner** and hand the ASCII span to `strtod_l`/`_strtod_l` with a C locale. That is a few dozen lines, but the API differs per platform.

**(c) Keep ExactDecimal in GDScript.** Zero engine cost. But it only covers code paths that call it. GDScript float **literals**, `JSON.parse` and `str_to_var` remain wrong everywhere else, including the 0-collapse below 1e-292.

**`std::from_chars(double)` portability:**
- [I] libstdc++ has it from GCC 11. GCC 12+ uses fast_float internally. This covers Linux GCC and MinGW.
- [I] MSVC STL has it from VS 2019 16.4.
- [I] libc++ has it only from **LLVM 20** (per the libc++ 20 release notes). Apple's Xcode libc++ also uses deployment-target availability markup. I found reports that Apple's libc++ lacks it in practice. Treat macOS as **unsupported**, so `from_chars` alone is not a cross-platform answer.
- [V] Godot compiles `-std=gnu++17` / `/std:c++17` (SConstruct:890-895), so from_chars is allowed but can't be relied on. fast_float is the portable choice.

**Recommendation:**
- Now: comment on #123700 with the underflow case and the harness. Keep ExactDecimal.
- If engine-wide correctness matters before upstream moves (GDScript literals, `str_to_var`): do (b) with fast_float, and pair it with the patch-aware `tools/build` change as one deliberate step.
