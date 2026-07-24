#!/usr/bin/env python3
"""Seed a timer snapshot into the simulator's App Group UserDefaults.

Usage: python3 scripts/seed-timer-snapshot.py <sim_udid> [--empty | --one | --two | --four]
"""
import json
import plistlib
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dTH:%M:%SZ")


def make_timer(
    timer_id: str,
    name: str,
    recipe_name: str | None,
    duration_seconds: int,
    remaining_seconds: int,
    phase: str = "running",
) -> dict:
    now = datetime.now()
    end = now + timedelta(seconds=remaining_seconds)
    return {
        "id": timer_id,
        "name": name,
        "recipeId": None,
        "recipeName": recipe_name,
        "endDate": iso(end) if phase in ("running", "exceeded") else None,
        "pausedRemainingSeconds": int(remaining_seconds) if phase == "paused" else None,
        "phase": phase,
        "totalDurationSeconds": float(duration_seconds),
    }


def build_document(scenario: str) -> dict:
    now = datetime.now()
    if scenario == "empty":
        timers = []
    elif scenario == "one":
        timers = [
            make_timer("t1", "Pasta", "Spaghetti Carbonara", 600, 240),
        ]
    elif scenario == "two":
        timers = [
            make_timer("t1", "Bake", "10 минут длинное название", 3600, -16 * 60, "exceeded"),
            make_timer("t2", "Oven", "10 часов длинное название", 36000, 9 * 3600 + 45 * 60),
        ]
    elif scenario == "four":
        timers = [
            make_timer("t1", "Step 1", "Pasta", 600, 240),                # normal
            make_timer("t2", "Step 2", "Sauce", 300, 20),                 # soon (<10%)
            make_timer("t3", "Proof", "Bread", 1800, -60, "exceeded"),    # exceeded
            make_timer("t4", "Rest", "Steak", 900, 480, "paused"),        # paused
        ]
    else:
        raise SystemExit(f"Unknown scenario: {scenario}")
    return {
        "timers": timers,
        "generatedAt": iso(now),
    }


def app_data_container(sim_udid: str, bundle_id: str) -> Path:
    out = subprocess.check_output(
        ["xcrun", "simctl", "get_app_container", sim_udid, bundle_id, "data"],
        text=True,
    ).strip()
    return Path(out)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    sim_udid = sys.argv[1]
    scenario = sys.argv[2] if len(sys.argv) > 2 else "one"
    if scenario.startswith("--"):
        scenario = scenario[2:]

    bundle_id = "ru.recipescaler.RecipeScaler"
    container = app_data_container(sim_udid, bundle_id)
    prefs_dir = container / "Library" / "Preferences"
    prefs_dir.mkdir(parents=True, exist_ok=True)
    plist_path = prefs_dir / "group.ru.recipescaler.RecipeScaler.plist"

    doc = build_document(scenario)
    encoded = json.dumps(doc, separators=(",", ":"))

    # Read existing plist if present, then set our key.
    data: dict = {}
    if plist_path.exists():
        with plist_path.open("rb") as f:
            try:
                data = plistlib.load(f)
            except Exception:
                data = {}
    data["widgets.timerSnapshot"] = encoded.encode("utf-8")
    with plist_path.open("wb") as f:
        plistlib.dump(data, f)

    print(f"Seeded scenario='{scenario}' ({len(doc['timers'])} timers)")
    print(f"  plist: {plist_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
