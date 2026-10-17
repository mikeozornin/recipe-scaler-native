#!/usr/bin/env python3
"""Summarise an xctrace Time Profiler recording of RecipeScalerNative.

Usage: python3 -I scripts/perf/analyze-trace.py <file.trace> [--top N] [--json out.json]

Prints main-thread CPU time, hangs (Instruments "potential hangs"), the app frames that
hold the main thread longest (inclusive), and the hottest leaf symbols. Used by
scripts/measure-perf.sh; standalone for ad-hoc traces.
"""
import argparse
import collections
import json
import subprocess
import sys
import xml.etree.ElementTree as ET

APP_BINARY = "RecipeScalerNative"


def export(trace, schema):
    xpath = f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'
    out = subprocess.run(
        ["xcrun", "xctrace", "export", "--input", trace, "--xpath", xpath],
        check=True, capture_output=True,
    ).stdout
    return ET.fromstring(out)


class Refs:
    """xctrace writes each value once with id=, later rows point at it with ref=."""

    def __init__(self):
        self.by_id = {}

    def resolve(self, el):
        ref = el.get("ref")
        if ref is not None:
            return self.by_id[ref]
        if el.get("id") is not None:
            self.by_id[el.get("id")] = el
        for child in el:
            self.resolve(child)
        return el


def hangs(trace):
    root = export(trace, "potential-hangs")
    refs = Refs()
    result = []
    for row in root.iter("row"):
        row = refs.resolve(row)
        cells = {c.tag: refs.resolve(c) for c in row}
        result.append({
            "start_ms": int(cells["start-time"].text) / 1e6,
            "duration_ms": int(cells["duration"].text) / 1e6,
            "type": cells["hang-type"].text,
        })
    return result


def profile(trace, window=None, callers=None):
    root = export(trace, "time-profile")
    caller_chains = collections.Counter()
    refs = Refs()
    main_ms = 0.0
    inclusive = collections.Counter()
    leaf = collections.Counter()
    first_sample_ms = None
    for row in root.iter("row"):
        cells = {}
        for c in row:
            cells[c.tag] = refs.resolve(c)
        thread = cells.get("thread")
        if thread is None or not thread.get("fmt", "").startswith("Main Thread"):
            continue
        weight = int(cells["weight"].text) / 1e6
        t = int(cells["sample-time"].text) / 1e6
        if window and not (window[0] <= t <= window[1]):
            continue
        first_sample_ms = t if first_sample_ms is None else min(first_sample_ms, t)
        main_ms += weight
        stack = cells.get("backtrace")
        if stack is None:
            continue
        frames = []
        for f in stack.iter("frame"):
            f = refs.resolve(f)
            binary = f.find("binary")
            binary = refs.resolve(binary) if binary is not None else None
            frames.append((f.get("name") or "?", binary.get("name") if binary is not None else "?"))
        if callers and any(callers in name for name, _ in frames):
            idx = next(i for i, (name, _) in enumerate(frames) if callers in name)
            chain = [n for n, b in frames[idx:] if b == APP_BINARY or "SwiftUI" in b][:6]
            caller_chains[" <- ".join(c[:70] for c in chain)] += weight
        if frames:
            leaf[f"{frames[0][0]}  [{frames[0][1]}]"] += weight
        seen = set()
        for name, binary in frames:
            if binary == APP_BINARY and name not in seen:
                seen.add(name)
                inclusive[name] += weight
    return main_ms, inclusive, leaf, caller_chains


def main():
    p = argparse.ArgumentParser()
    p.add_argument("trace")
    p.add_argument("--top", type=int, default=25)
    p.add_argument("--json")
    p.add_argument("--window", help="start-end in ms since trace start, e.g. 2000-2500")
    p.add_argument("--callers", help="print app/SwiftUI caller chains of frames containing this text")
    a = p.parse_args()

    hs = hangs(a.trace)
    window = tuple(float(x) for x in a.window.split("-")) if a.window else None
    main_ms, inclusive, leaf, chains = profile(a.trace, window, a.callers)

    print(f"main thread CPU: {main_ms:.0f} ms")
    print(f"hangs: {len(hs)}, total {sum(h['duration_ms'] for h in hs):.0f} ms")
    for h in hs:
        print(f"  {h['start_ms']:8.0f} ms  {h['duration_ms']:6.0f} ms  {h['type']}")
    print(f"\napp frames on main thread (inclusive ms, top {a.top}):")
    for name, ms in inclusive.most_common(a.top):
        print(f"  {ms:7.0f}  {name[:150]}")
    print(f"\nleaf symbols on main thread (self ms, top {a.top}):")
    for name, ms in leaf.most_common(a.top):
        print(f"  {ms:7.0f}  {name[:150]}")

    if a.callers:
        print(f"\ncaller chains of '{a.callers}' (ms):")
        for chain, ms in chains.most_common(a.top):
            print(f"  {ms:7.0f}  {chain}")

    if a.json:
        with open(a.json, "w") as f:
            json.dump({
                "main_thread_ms": main_ms,
                "hangs": hs,
                "app_inclusive": inclusive.most_common(80),
                "leaf": leaf.most_common(80),
            }, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    sys.exit(main())
