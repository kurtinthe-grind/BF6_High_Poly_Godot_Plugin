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
    "F-08": {
        "absent": ["highpoly_fx.gd", "highpoly_fx.gd.uid", "fx_effect_sheets.json", "fx_meshes.json",
                   "fx_motion.json", "fx_params.json", "fx_sheets.json", "fx_sizes.json",
                   "fx_spawn.json", "fx_smoke.gdshader", "fx_smoke.gdshader.uid",
                   "highpoly_lighting.gd", "highpoly_lighting.gd.uid", "highpoly_lighting_zones.gd",
                   "sky_sun.gdshader", "sky_sun.gdshader.uid"],
        "forbid": [r"\bHighpolyFx\b", r"\bHighpolyLighting\b", r"\bHighpolyLightingZones\b",
                   r"\bLightingScript\b", r"\bLightScript\b", r"\bLightingZones\b",
                   r"\bmapctx_fx\b", r"\bmapctx_light\b", r"\bmapctx_gi\b", r"\bmapctx_shadows\b",
                   r"\bmapctx_maplights\b", r"\bmapctx_fill\w*", r"\bprop_light_on\b",
                   r"\b_set_prop_lighting\b", r"\b_lighting_subs_enabled\b",
                   r"\b_lighting_changed\b", r"\b_lighting_guard\b", r"\bLIGHTING_TIP",
                   r"\bFX_JOB\b", r"\bLIGHTS_JOB\b", r"\bwant_fx\b", r"\bwant_lights\b",
                   r"\bshow_fx_cards\b", r"\bset_fx_cards_shown\b", r"\b_fx_cards?_groups?\b",
                   r"\b_fx_animate_materials\b", r"fx_smoke", r"sky_sun", r"FLIP_BASE_SPEED",
                   r"\bprop_emission\b", r"\bset_prop_emission\b", r"\b_emissive_mats\b",
                   r"\blevel_lights\b", r"\bobject_lights\b", r"\b_obj_lights\b",
                   r"\b_light_records?\b", r"\blighting_zones\b", r"\benvironment_lighting\b",
                   r"\b_fx_graph\b", r"\b_fx_class\b", r"func fx\(", r"func lights\(",
                   r"func sky\(", r"\b_sky_from\b", r"hp_light_recs", r"\"_GAME_LIGHTING\"",
                   r"\"_HP_PROP_LIGHTS\"", r"\"prop_lighting\"", r"\"fixture_lights\"",
                   r"\"lighting_options\"", r"\"contact_shading\"", r"\"interior_light\"",
                   r"\"map_lights\"", r"\"fx\"", r"\"lighting\"", r"\"shadows\"",
                   r"\"lights\"\s*:\s*(true|false|want)", r"\"flip\""],
    },
    "HP-006": {
        "absent": [],
        "forbid": [r"set_meta\(\s*(HighpolyLib\.)?VARIANT_META", r"get_meta\(\s*(HighpolyLib\.)?VARIANT_META",
                   r"set_meta\(\s*OPEN_META", r"get_meta\(\s*OPEN_META"],
    },
    # UI-01: the shared "BF6" menu-bar entry and its radial registration are gone;
    # every action they offered lives on the High-Poly dock panel.
    "UI-01": {
        "absent": ["bf6_plugin_menu.gd"],
        "forbid": [r"\bPluginMenu\b", r"bf6_plugin_menu", r"\b_register_bf6_menu\b",
                   r"\b_bf6_menu_items\b", r"\b_bf6_rows_for\b", r"\bregister_plugin\(",
                   r"\bHOME_PANELS_GROUP\b", r"bf6_workspace_panels_v1",
                   r"\bset_visibility_suppressed\b", r"\b_panel_suppressed\b",
                   r"\b_apply_home_suppression\b", r"\b_home_screen_visible_now\b"],
    },
    # UI-02: the panel is a permanent dock tab - no floating window, no toolbar
    # toggle, no float/dock switching.
    "UI-02": {
        "absent": [],
        "forbid": [r"\b_build_tool_window\b", r"\b_float_panel\b", r"\b_dock_panel\b",
                   r"\b_set_tools_visible\b", r"\btools_btn\b", r"\b_close_tools\b",
                   r"\b_win_rect\b", r"\b_win_held_for_home\b", r"\bWIN_SIZE\b",
                   r"\bCONTAINER_SPATIAL_EDITOR_MENU\b", r"\"High-Poly Tools\"",
                   r"\b_first_run_open\b"],
    },
    # C-01: caching is on demand for the open map - no launch-time run, no cover
    # screen or editing lock, no all-maps order, no bf6_geom wipe, and the panel
    # is gated on a detected install only.
    "C-01": {
        "absent": ["highpoly_preparation_screen.gd"],
        "forbid": [r"\b_show_screen\b", r"\bediting_lock_changed\b", r"\bsuspend_viewports\b",
                   r"\b_ordered_levels\b", r"_remove_tree\(\"user://bf6_geom\"\)",
                   r"bool\(_preparation\.cache_ready\)", r"\bshow_deferred_screen\b"],
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
    "HP-006",
    "F-08",
    "UI-01",
    "UI-02",
    "C-01",
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
