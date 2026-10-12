# BF6 High-Poly Preview

Editor-only overlays for the BF6 Portal SDK: real high-poly models over the
low-poly proxies, plus Map Context (full terrain, original object layouts,
water) and viewport performance tools.

- The **low-poly proxy stays the source of truth** — it's what the `.tscn`
  saves and what the Portal exporter ships. This plugin never modifies it.
- Overlays are `owner = null` nodes (`_HIPOLY_PREVIEW`, `_MAP_CONTEXT`):
  never serialized, never exported, dropped automatically on scene reload.

## Install

1. Copy this folder to `addons/highpoly_toggle/` in the SDK Godot project.
2. Enable it under Project → Project Settings → Plugins.
3. Press **High-Poly Tools** in the 3D viewport toolbar — beside the SDK's own
   **Apply Texture** button. It opens a floating panel you can move anywhere,
   including onto a second monitor. Models and map data sync automatically in
   the background (scene props first) — no other setup.

The panel is a window rather than a dock because level building wants the
viewport wide, and a permanent right-hand dock costs ~400px of it. Closing the
panel only hides it: the background sync, map-context builds and downloads all
keep running. Its position and open/closed state are remembered per project.

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
