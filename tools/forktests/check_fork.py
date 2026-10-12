#!/usr/bin/env python3
"""Static checks for the fork's removals and fixes.

Each rule is keyed by a feature (F-0x) or bug (HP-0xx) id and lists files that
must NOT exist in the addon and regex patterns that must NOT appear in the
addon's .gd / .json / .gdshader / .cfg files or in shared/menu/*.json.
A rule is enforced by default only once its id is in ENABLED, so a task turns
its rule on first, watches it fail, then does the work.

    python tools/forktests/check_fork.py          # every enabled rule
    python tools/forktests/check_fork.py F-03     # one rule, enabled or not
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ADDON = REPO / "addons" / "highpoly_toggle"
SHARED_MENU = REPO / "shared" / "menu"
SCANNED = (".gd", ".json", ".gdshader", ".cfg")

RULES: dict[str, dict] = {
    "F-05a": {
        "absent": ["highpoly_autorun.gd", "highpoly_flightrun.gd", "highpoly_flightpath.gd"],
        "forbid": [r"\bHighpolyAutorun\b", r"\bHighpolyFlightRun\b", r"\bHighpolyFlightPath\b",
                   r"\bFlightPath\.", r"Record flight path", r"BF6_AUTORUN", r"BF6_PERFRUN"],
    },
    "F-03": {
        "absent": ["highpoly_updater.gd", "highpoly_reload.gd"],
        "forbid": [r"\bHighpolyUpdater\b", r"\bHighpolyReload\b", r"\bupdate_btn\b",
                   r"\bcheck_btn\b", r"\b_check_updates_now\b", r"\b_hot_reload\b",
                   r"\b_reopen_panel\b", r"\b_check_plugin_update\b",
                   r"\b_do_plugin_update\b", r"api\.github\.com"],
    },
    "F-04": {
        "absent": ["highpoly_previews.gd"],
        "forbid": [r"\bPreviewsScript\b", r"\bHighpolyPreviews\b",
                   r"\bpreviews\.(tier|textured|rescan_context|clear_cache|shutdown|build_all|missing_count|building|cancel_build)\b",
                   r"_previews_missing_for_cache", r"_run_previews_for_cache",
                   r"_cancel_previews_for_cache", r"\"Object previews\"",
                   r"_keep_service\(\"previews\"", r"_take_service\(\"previews\""],
    },
    "F-01": {
        "absent": ["highpoly_splash.gd", "highpoly_backdrop.gd", "logo.png", "waves.ogv",
                   "waves.json", "ui_font.ttf"],
        "forbid": [r"\bSplashScript\b", r"\bHighpolySplash\b", r"\bVideoStreamPlayer\b",
                   r"\bVideoStreamTheora\b", r"waves\.(ogv|json)", r"logo\.png", r"ui_font",
                   r"\bbuild_ui_theme\b", r"\bpanel_border\b", r"\b_maybe_play_splash\b",
                   r"HighpolyChip", r"\bBackdrop\.(sync|settle)\b", r"\bTINT_DEFAULT\b"],
    },
    "F-07": {
        "absent": ["highpoly_water.gd", "highpoly_native_water.gd", "water.gdshader",
                   "water_native.gdshader"],
        "forbid": [r"\bHighpolyWater\b", r"\bHighpolyNativeWater\b", r"\bmapctx_water\b",
                   r"\bset_water_shown\b", r"\bset_sdk_water_hidden\b", r"\b_sdk_water_planes\b",
                   r"\b_sdk_water_hidden\b", r"\b_add_water_plane\b", r"\blog_water_state\b",
                   r"\b_show_water\b", r"\brefresh_water\b", r"\bwater_texture\b",
                   r"\bwater_sim\b", r"\b_water_look\b", r"\bWATER_STATE_KEY\b",
                   r"func water\(", r"\"water_lab\"", r"\"water\"\s*:", r"base_ripple"],
    },
    "F-06": {
        "absent": ["highpoly_gamemode.gd", "highpoly_gmmine.gd"],
        "forbid": [r"\bHighpolyGamemode\b", r"\bHighpolyGmMine\b", r"\b_gm_key\b",
                   r"\b_gm_heal_off\b", r"\b_mine_gamemodes_async\b",
                   r"\b_gamemodes_then_catalogue\b", r"hp_gamemode", r"gamemode_markers"],
    },
    "F-05b": {
        "absent": ["highpoly_loadout.gd", "highpoly_loadout_inspector.gd", "highpoly_soldier.gd",
                   "highpoly_weapon.gd", "highpoly_vehicle.gd"],
        "forbid": [r"\bHighpolyLoadout\b", r"\bLoadoutScript\b", r"\bLoadoutInspector\b",
                   r"\b_loadout_inspector\b", r"\bHighpolySoldier\b", r"\bHighpolyWeapon\b",
                   r"\bHighpolyVehicle\b", r"soldier://", r"weapon://", r"loadout://",
                   r"vehicle://", r"highpoly\.loadout", r"\bhighpoly_loadout\b",
                   r"_bf6_open_loadout", r"_bf6_loadout_items", r"_selected_spawners"],
    },
}

ENABLED: list[str] = [
    "F-05a",
    "F-03",
    "F-04",
    "F-01",
    "F-07",
    "F-06",
    "F-05b",
]


def _scan_files() -> list[Path]:
    out = [p for p in sorted(ADDON.iterdir()) if p.is_file() and p.suffix in SCANNED]
    out += sorted(SHARED_MENU.glob("*.json"))
    return out


def check(rule_id: str) -> list[str]:
    rule = RULES[rule_id]
    problems: list[str] = []
    for name in rule.get("absent", []):
        if (ADDON / name).exists():
            problems.append(f"{rule_id}: file still present: {name}")
    pats = [re.compile(p) for p in rule.get("forbid", [])]
    for f in _scan_files():
        text = f.read_text(encoding="utf-8", errors="replace")
        for i, line in enumerate(text.splitlines(), 1):
            for p in pats:
                if p.search(line):
                    problems.append(f"{rule_id}: {f.relative_to(REPO)}:{i}: "
                                    f"/{p.pattern}/ -> {line.strip()[:100]}")
    return problems


def main(argv: list[str]) -> int:
    ids = argv[1:] or ENABLED
    unknown = [i for i in ids if i not in RULES]
    if unknown:
        print("unknown rule(s): " + ", ".join(unknown))
        return 2
    problems: list[str] = []
    for i in ids:
        problems += check(i)
    for p in problems:
        print(p)
    print(f"check_fork: {len(ids)} rule(s), {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
