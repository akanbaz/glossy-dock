# Glossy Dock: root-cause analysis of design issues

This looks back at the problems found while building Glossy Dock 1.0 and the work after it,
grouped by the design decision that caused them rather than by symptom. For each one: what
you saw, why the design allowed it, the fix, and the guardrail that now catches that whole
class of problem.

Commits are in this repository; issues fixed before the first commit (`02b6e68`) were found
while the dock was still a local widget.

## Summary

| # | Root cause in the design | Issues it caused |
|---|---|---|
| 1 | Things were identified by their **position in a list** that changes | Menu acting on the wrong app or window; previews of the wrong app; last pin missing; hover zoom on the wrong icon |
| 2 | Checks trusted **reported values** instead of what is on screen | Laptop dock with half its glass empty; one-icon dock 4px lopsided; a "reproducible" claim that held on one machine only |
| 3 | **Undocumented Plasma/Qt behaviour** was assumed instead of measured | Icons drawn at 22px instead of 29; blurry zoom; menu far above the dock and then vanishing; ghost slots for uninstalled apps |
| 4 | Changes to **shared resources** weren't checked against everything that uses them | Top bars changed size; ends growing on taller panels; dark-on-dark text with a light colour scheme; wallpaper reset by the theme |
| 5 | **Per-dock settings** with no coordination | Two screens' docks drifting to different sizes |
| 6 | **Tests only checked the first state**, in an environment that wasn't what they assumed | Every item above reaching the user before a test; a test run leaking into the real session; CI red unnoticed |

The common thread: each piece was verified against what it was *supposed* to do, using the
values it *reported*, in the state it *started* in. The fixes move every check to what is
really on screen, after changes, in an environment that is known to be isolated.

---

## 1. Identity by position

The dock builds a list of slots (pinned apps, then open apps) and, from a separate model, a
list of windows. Both lists are rebuilt whenever anything changes. Early code remembered
"slot 12" or "window row 5" and used that number later.

| Symptom | Root cause | Fix | Guardrail |
|---|---|---|---|
| A pin (often the last) missing until something else happened | Each pin's model refreshed while it was still being created, when `Instantiator.objectAt(i)` returns nothing; the rebuilt list skipped it and nothing rebuilt it again | Rebuild when the Instantiator finishes adding or removing an object (`02b6e68`) | Smoke test asserts each dock's exact app list; fails with the fix removed |
| Right-click *Unpin / Minimize / Close* could act on another app or window if anything opened or closed while the menu was up | Menu items captured slot and window-row positions when the menu opened | Items keep the app key and window id and look the position up when clicked (`7873bc9`) | Code review rule below; not testable without input injection |
| Preview popup could show another app's windows | Preview tracked the slot index | Track the app key (`7873bc9`) | As above |
| Hover zoom stayed on the wrong icon after an app appeared or disappeared | Hover index not reset when slots change | Reset on slot-count change (`7873bc9`) | — |

**Design rule now:** anything that acts later (menus, popups, timers, async callbacks)
stores a stable identity (app id, window id) and resolves it at the moment it acts.

## 2. Trusting reported values

| Symptom | Root cause | Fix | Guardrail |
|---|---|---|---|
| Laptop dock with ~264px of empty glass | Swapping the old widget for the new one left the panel sized for both; Plasma still *reported* 284px, which is what the check read. The screenshot check was cropped to the expected size, so the extra glass was outside it | Restarting Plasma re-laid it out (one-off) | Smoke test measures dock windows through KWin, and compares reported and real sizes (`63ffb04`) |
| One-icon dock: 14px of glass at one end, 10px at the other | A minimum-size clamp skipped the end-gap compensation for a single icon | Clamp to 1px (`63ffb04`) | Smoke test unpins down to one icon and checks the real window shrinks by exactly one icon and gap; failed before the fix |
| Expected dock lengths wrong on GitHub (92px vs 96px) | Test hardcoded pixel sizes from one machine; the ends depend on Plasma style and fonts | Compare docks with each other and with their own earlier size (`7873bc9`) | Relative assertions only |
| Release archives differed from a local build | The build's gzip header held the build time; "reproducible" had only been checked on one machine | Pin the timestamp (`f35e7ec`); docs now say bytes match only with the same zlib | Release files downloaded and their contents compared with a local build |

**Design rule now:** verify geometry by measuring the real window or real pixels; crop
screenshots wider than expected and measure edges; never assert machine-specific absolutes.

## 3. Assumed platform behaviour

These were all reasonable assumptions about Plasma, Kirigami or Qt that turned out to be
wrong, and nothing measured them.

| Symptom | What was assumed vs. what happens | Fix |
|---|---|---|
| All icons smaller than intended and of uneven size | `Kirigami.Icon` draws at the requested size. It **rounds down to standard sizes** (16, 22, 32…), so 29px icons were drawn at 22 | `roundToIconSize: false` (`15de599`) |
| Some icons (Claude, Cursor, WhatsApp) looked smaller than others | Icon artwork fills its image. Many ship with **transparent padding** (23 of 29px) | Measure each icon's artwork once and draw padded ones larger, up to 1.3x (`15de599`) |
| Hover zoom blurry | A scale transform re-renders. It **stretches the already-drawn bitmap** | Render at the zoomed size, scale down at rest (`2877a68`) |
| Right-click menu ~100px above the dock, then disappearing | `QMenu` positioning from QML works on a panel. It used a **stale menu height**, and on a dodge-windows panel the panel hid when the pointer left it, taking the menu along | Plasma popup window anchored to the slot; panel kept visible while it's open (before `02b6e68`) |
| Menu popup a 500px box with the items at the top | A Plasma popup window **sizes itself from its content**. It doesn't | Set its width and height explicitly (before `02b6e68`) |
| Blank slots for uninstalled apps | A pin for a missing `.desktop` file has no row. Plasma creates a **placeholder row with no app id** | Treat "has an app id" as installed (`02b6e68`) |
| Launcher icons vanished while their app was open | Launcher rows stay. Plasma **hides a launcher while its app has a window** | One launcher model per pin with windows filtered out (before `02b6e68`) |
| Ends 4px uneven; menu unreachable | The dock is alone in its panel and the panel's own menu stays available. The panel adds a 4px gap before a hidden spacer, and the dock's menu replaced Plasma's | Compensate only when alone (`7873bc9`); add *Configure* / *Edit Panel* to the menu (`620e012`) |
| Widget failing to load | Property names are free. `states`, `left`, `right` are **built-in Item properties** | Renamed (before `02b6e68`) |

**Design rule now:** when relying on platform behaviour that isn't documented, prove it with a
measurement or a test fixture before building on it (the icon-size and padding findings came
from rendering the real icons and measuring their pixels).

## 4. Shared resources

The Plasma style and the global theme are used by more than the dock.

| Symptom | Root cause | Fix | Guardrail |
|---|---|---|---|
| Clock and icons on the top bars got bigger | A style change meant for docks also changed the margins *across* every panel on that edge | Shrink only the margin *along* the panel (`a947bd9`) | Before/after screenshots of the top bars, compared by element position |
| Ends grew on taller top, left and right panels | Only the bottom edge had the tight frame; others fell back to the 16px default, capped by the panel height | Tight frame on every edge (`5c24c97`) | Smoke test changes a dock's height and asserts its length doesn't change; failed before the fix |
| Names and indicators dark on dark glass with a light colour scheme | The glass is always dark but the text followed the user's colour scheme | Glossy Glass ships its own dark colours (`5c24c97`) | Screenshot check of names on the glass |
| Applying the global theme reset the wallpaper | Plasma wipes the desktop configuration before running a theme's layout script | Theme restores the wallpaper from a snapshot (local setup, not in the package) | — |

**Design rule now:** a change to a shared resource is checked against everything that uses it,
on the real desktop, before and after.

## 5. Uncoordinated per-dock settings

Plasma stores settings per widget instance. Each screen's dock had its own icon size, gap and
zoom, so changing one left the other behind, and it looked like the setting didn't work.

**Fix:** "Use these settings on all docks" (on by default) copies any change of a look or
size setting to every other dock; pins and "show open apps" stay per dock. Copies skip docks
that already have the value, so they can't bounce (`ade4033`).

**Guardrail:** the smoke test gives docks different settings, turns sharing on, and asserts
the values spread and the pins don't; it failed with sharing disabled. Runs in CI too.

## 6. Tests that only saw the first state, in the wrong environment

Most of the issues above reached the user before a test because of how the tests were
designed, not because they were missing.

| Gap | Effect | Fix |
|---|---|---|
| Docks built once and checked once | Nothing exercised apps opening and closing, unpinning, resizing or changing settings | Smoke test now runs those transitions (`7873bc9`, `5c24c97`, `ade4033`) |
| No proof a check could fail | A check that can't fail looks the same as one that passes | Each new check was run once with a deliberately planted bug |
| Test session not fully isolated | Services that D-Bus started inside the test used the real home folder, because isolation was set up after the private D-Bus daemon started | Isolate the environment before starting D-Bus; stop every process on the test bus afterwards |
| Logs went to the journal, then were deleted on abort | Failures were invisible ("passed" while blind; CI failures with no clues) | Force logs to the test's files; keep and upload them on any failure (`0415ccb`) |
| CI has no GPU | KWin can't draw, so later changes never reach the screen and app windows crash it | Skip exactly those steps there, with the reason, and run the full test locally before releases (`2ad9ac7`, `45270ab`) |
| CI not checked after each push | Two red commits went unnoticed | Check each commit's CI before moving on |

---

## Principles going forward

1. **Stable identity:** anything that acts later stores ids, not positions.
2. **Measure reality:** real window geometry and real pixels, not reported values; wide crops.
3. **Test transitions:** every change a user can make after start-up has a test that makes it.
4. **Prove checks can fail:** plant the bug once before trusting a new check.
5. **Measure undocumented platform behaviour** before designing around it.
6. **Shared resources:** check before/after on everything that uses them.
7. **Isolated, observable tests:** isolate before starting services; keep logs on failure.
8. **Check CI on every push.**

## Not yet covered

- Hover, clicks and the right-click menu can't be driven automatically (the isolated session
  has no input injection), so the menu and preview fixes in section 1 rely on code review
  and manual testing.
- GitHub's runners have no GPU, so steps after start-up only run in local smoke tests.
- Plasma versions before 6.8 and X11 sessions haven't been tested.
