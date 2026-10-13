# BF6 High-Poly Preview

Editor-only overlays for the BF6 Portal SDK: real high-poly models over the
low-poly proxies, plus Map Context (full terrain and original object
layouts) and viewport performance tools.

- The **low-poly proxy stays the source of truth** — it's what the `.tscn`
  saves and what the Portal exporter ships. This plugin never modifies it.
- Overlays are `owner = null` nodes (`_HIPOLY_PREVIEW`, `_MAP_CONTEXT`):
  never serialized, never exported, dropped automatically on scene reload.

## Install

1. Copy this folder to `addons/highpoly_toggle/` in the SDK Godot project.
2. Enable it under Project → Project Settings → Plugins.
3. The **High-Poly** tab appears in the editor's right-hand dock column (the
   lower slot, below the Inspector) as soon as the plugin is enabled. Drag it
   to any other dock slot like any editor panel; the editor remembers where.

Nothing is cached when Godot starts. Open a map and press **Cache this map** in
the panel to prepare that map only; High-Poly also works on an uncached map
(the first build reads everything from the install, and later builds reuse the
geometry and texture packs it writes).

## Look

The panel uses the Godot editor theme.

## Viewport double-click

- **Doors** swing open/closed like in game.
- **Variant props** (police liveries, barn colour schemes, destroyed shells, …)
  cycle base → variant → … → base. The choice is per instance — two buses can
  wear different liveries — and survives Low/High-Poly toggles. Variants seen
  on the current map come first in the cycle. Doors win when a prop is both.

Full guide: the repository README. Contributor guide: `docs/ARCHITECTURE.md`.
Overlay/fitter internals: `docs/HIGHPOLY-PREVIEW.md`.
