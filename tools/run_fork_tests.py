#!/usr/bin/env python3
"""Run the fork's tests against the REPO addon, never the user's project.

1. tools/forktests/check_fork.py - static removal/fix rules
2. every tools/forktests/test_*.gd, each in its own headless `--script` run
   inside a throwaway project holding a copy of the addon (as gate_sandbox.py)
3. tools/gate_sandbox.py - every script and shader loads as a set

A GDScript test prints "FORKTEST PASS <what>" / "FORKTEST FAIL <what>" and
quits non-zero on failure.

    python tools/run_fork_tests.py               # everything
    python tools/run_fork_tests.py sleeppark     # GD tests whose name contains this
    python tools/run_fork_tests.py --no-gate     # skip step 3

Environment: GODOT_BIN (see gate_sandbox.py).
"""
from __future__ import annotations

import argparse
import io
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
ADDON = REPO / "addons" / "highpoly_toggle"
TESTS = HERE / "forktests"
sys.path.insert(0, str(HERE))
import gate_sandbox  # noqa: E402  - find_godot, PROJECT_GODOT


def run_gd_tests(godot: str, only: str, timeout: float) -> int:
    tests = sorted(p for p in TESTS.glob("test_*.gd") if only in p.name)
    if not tests:
        print("no GDScript tests matched")
        return 0
    work = Path(tempfile.mkdtemp(prefix="bf6-forktests-"))
    proj = work / "proj"
    dst = proj / "addons" / "highpoly_toggle"
    dst.mkdir(parents=True)
    io.open(proj / "project.godot", "w", encoding="utf-8",
            newline="\n").write(gate_sandbox.PROJECT_GODOT)
    for src in sorted(ADDON.iterdir()):
        if src.is_file():
            shutil.copy2(src, dst / src.name)
    (proj / "forktests").mkdir()
    for t in tests:
        shutil.copy2(t, proj / "forktests" / t.name)
    failed = 0
    try:
        # Registers every class_name, exactly as the gate does before it loads.
        subprocess.run([godot, "--headless", "--path", str(proj), "--import"],
                       capture_output=True, text=True, timeout=timeout)
        for t in tests:
            # --quit-after: a script error inside _init skips its quit(), and a
            # SceneTree with nothing to do would otherwise idle until timeout.
            r = subprocess.run([godot, "--headless", "--path", str(proj),
                                "--quit-after", "600",
                                "--script", f"res://forktests/{t.name}"],
                               capture_output=True, text=True, timeout=timeout)
            out = (r.stdout or "") + (r.stderr or "")
            ok = (r.returncode == 0 and "FORKTEST PASS" in out
                  and "FORKTEST FAIL" not in out and "SCRIPT ERROR" not in out)
            print(("PASS " if ok else "FAIL ") + t.name)
            for line in out.splitlines():
                if "FORKTEST" in line or "SCRIPT ERROR" in line or "Parse Error" in line:
                    print("    " + line.strip())
            failed += 0 if ok else 1
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return failed


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("only", nargs="?", default="")
    ap.add_argument("--godot", default="")
    ap.add_argument("--no-gate", action="store_true")
    ap.add_argument("--timeout", type=float, default=900.0)
    a = ap.parse_args()
    godot = a.godot or gate_sandbox.find_godot()
    bad = 0
    if subprocess.run([sys.executable, str(TESTS / "check_fork.py")]).returncode:
        bad += 1
    bad += run_gd_tests(godot, a.only, a.timeout)
    if not a.no_gate:
        if subprocess.run([sys.executable, str(HERE / "gate_sandbox.py"),
                           "--godot", godot]).returncode:
            bad += 1
    print("\nFORK TESTS " + ("PASSED" if bad == 0 else f"FAILED ({bad})"))
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
