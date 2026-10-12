#!/usr/bin/env python3
"""Enable the plugin in a throwaway project and run the real editor headless.

The gate only proves every script COMPILES; EditorPlugin cannot be instantiated
outside the editor, so _enter_tree and the panel build are never executed by
the GDScript tests. This runs them, in a sandbox project with its own user://
folder (app_userdata/hpsmoke-<pid>), and checks:

  * no script or parse error from the add-on while the editor starts and quits;
  * the panel came up ("Panel opened" in highpoly-session.log);
  * enabling the plugin started NO cache run: no user://highpoly/preparation.json,
    no preparation_jobs folder (a job file is always written before a worker
    process is spawned), and the shared game cache folder
    %LOCALAPPDATA%/BF6HighPoly was not touched.

The sandbox user:// folder is deleted afterwards. Nothing under the live SDK
project or its user:// folder is read or written.

    python tools/editor_smoke.py [--godot PATH] [--addon DIR] [--frames N] [--keep]
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import gate_sandbox  # noqa: E402  - find_godot

ADDON = HERE.parent / "addons" / "highpoly_toggle"


def _stamp(p: Path) -> tuple:
    """Newest modification time and entry count anywhere under p."""
    if not p.exists():
        return ("missing",)
    newest, n = p.stat().st_mtime_ns, 0
    for x in p.rglob("*"):
        n += 1
        newest = max(newest, x.stat().st_mtime_ns)
    return (newest, n)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--godot", default="")
    ap.add_argument("--addon", default=str(ADDON))
    ap.add_argument("--frames", type=int, default=400)
    ap.add_argument("--keep", action="store_true", help="keep the sandbox user:// folder")
    a = ap.parse_args()
    godot = a.godot or gate_sandbox.find_godot()
    name = "hpsmoke-%d" % os.getpid()
    userdir = Path(os.environ.get("APPDATA", "")) / "Godot" / "app_userdata" / name
    shared = Path(os.environ.get("LOCALAPPDATA", "")) / "BF6HighPoly"
    before = _stamp(shared)
    work = Path(tempfile.mkdtemp(prefix="bf6-editor-smoke-"))
    proj = work / "proj"
    shutil.copytree(a.addon, proj / "addons" / "highpoly_toggle")
    (proj / "project.godot").write_text(
        'config_version=5\n\n[application]\nconfig/name="%s"\n\n' % name
        + '[editor_plugins]\nenabled=PackedStringArray("res://addons/highpoly_toggle/plugin.cfg")\n\n'
        + '[rendering]\nrenderer/rendering_method="mobile"\n', encoding="utf-8")
    problems: list[str] = []
    try:
        subprocess.run([godot, "--headless", "--path", str(proj), "--import"],
                       capture_output=True, text=True, timeout=600)
        r = subprocess.run([godot, "--headless", "--editor", "--path", str(proj),
                            "--quit-after", str(a.frames)],
                           capture_output=True, text=True, timeout=600)
        out = (r.stdout or "") + (r.stderr or "")
        lines = out.splitlines()
        for i, line in enumerate(lines):
            if "SCRIPT ERROR" in line or "Parse Error" in line:
                ctx = " | ".join(lines[i:i + 2]).strip()
                problems.append("script error: " + ctx[:220])
        log = userdir / "highpoly-session.log"
        text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
        if "Panel opened" not in text:
            problems.append("the panel did not report 'Panel opened' (plugin did not start?)")
        if (userdir / "highpoly" / "preparation.json").exists():
            problems.append("enable wrote user://highpoly/preparation.json (a cache run started)")
        if (userdir / "highpoly" / "preparation_jobs").exists():
            problems.append("enable created preparation_jobs (a worker process was started)")
        if _stamp(shared) != before:
            problems.append("enable touched %s (the shared game cache)" % shared)
        print("editor smoke: exit %d, %d frames" % (r.returncode, a.frames))
        for line in text.splitlines():
            if " info " in line or " warn " in line:
                print("  log: " + line.strip())
    finally:
        shutil.rmtree(work, ignore_errors=True)
        if not a.keep and userdir.name.startswith("hpsmoke-"):
            shutil.rmtree(userdir, ignore_errors=True)
    for p in problems:
        print("EDITOR SMOKE PROBLEM: " + p)
    print("EDITOR SMOKE " + ("PASSED" if not problems else "FAILED"))
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
