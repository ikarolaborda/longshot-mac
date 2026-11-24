"""Measure controls in adult Kakariko Village, on a copy of a playable save.

Launch Longshot with HOS_CONTROL, HOS_METAL_TIMING=2 and HOS_FPS_LOG=1.
Select the graphics mode, enter the village, and run this script with the
control socket and game log paths. The JSON result can be compared between runs.
"""
import argparse
from bisect import bisect_left
import json
import math
from pathlib import Path
import re
import statistics
import struct
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from longshot_bridge import Bridge, check


def state(bridge):
    status = check(bridge.request("status"))
    game = status["game"]
    if game.get("map") != "KakarikoVillage_Adult" or game.get("event") or game.get("loading"):
        raise RuntimeError("Start with adult Link standing on the road in Kakariko Village.")
    return {k: game.get(k) for k in ("pos", "camera", "facing", "prompt")} | {"frame": status["frame"]}


def action(bridge, kind, duration, **controls):
    before = state(bridge)
    press = time.monotonic()
    try:
        if controls:
            command = "press" if "buttons" in controls else "stick"
            check(bridge.request(command, frames=300, exclusive=True, wait=False, **controls))
        time.sleep(max(0, press + duration - time.monotonic()))
    finally:
        release = time.monotonic()
        if controls:
            check(bridge.request("release"))
    time.sleep(.65 if kind.startswith("run") else 1.45)
    return dict(kind=kind, press=press, release=release, pre=before, post=state(bridge))


def village(bridge):
    action(bridge, "warm right", .75, x=.85, y=0)
    action(bridge, "warm left", .75, x=-.85, y=0)
    action(bridge, "draw sword", .10, buttons=["Y"])
    time.sleep(1)
    action(bridge, "idle control", .4)
    actions = []
    start = time.monotonic()
    for repeat in range(5):
        for sign, side in ((1, "right"), (-1, "left")):
            move = action(bridge, "run " + side, .82 if repeat % 2 else .64, x=sign*.9, y=0)
            if math.dist(move["pre"]["pos"], move["post"]["pos"]) < .1:
                raise RuntimeError("The movement input did not move Link.")
            actions.append(move)
            actions.append(action(bridge, "sword", .11, buttons=["Y"]))
        if repeat in (0, 2, 4):
            actions.append(action(bridge, "idle control", .25))
    actions.extend([
        action(bridge, "forward", 1.75, x=0, y=.88),
        action(bridge, "turn camera", .66, stick="R", x=.75, y=0),
        action(bridge, "advancing attack", .19, buttons=["Y"], x=0, y=.75),
        action(bridge, "return", 1.35, x=0, y=-.88),
    ])
    return dict(start=start, end=time.monotonic(), actions=actions)


def score(route, log):
    events = sorted((float(guest), float(shown)) for guest, shown in re.findall(
        r"Metal response sample: guest=([\d.]+) shown=([\d.]+)", log))
    displays = sorted(float(shown) for shown in re.findall(
        r"Metal timing display: shown=([\d.]+)", log)
        if route["start"] <= float(shown) <= route["end"])
    latencies = []
    for action in route["actions"]:
        hits = [shown for guest, shown in events if action["press"] <= guest < action["release"]]
        if action["kind"] == "idle control":
            if hits:
                raise RuntimeError("The game received another control during an idle trial.")
        elif hits:
            latencies.append((min(hits) - action["press"]) * 1000)
        else:
            raise RuntimeError(f"No game frame matched {action['kind']}.")
    if len(displays) < 2 or not latencies:
        raise RuntimeError("The log needs HOS_METAL_TIMING=2 and the corresponding route.")
    def p95(seq):
        return sorted(seq)[math.ceil(len(seq)*.95)-1]
    gaps = [(b-a)*1000 for a, b in zip(displays, displays[1:])]
    return dict(actions=len(latencies), median_ms=statistics.median(latencies),
                p95_ms=p95(latencies), displayed_fps=1000/statistics.mean(gaps),
                p95_frame_gap_ms=p95(gaps))


def visible_actions(route, log, pixel_file, floor=.20):
    """Find character motion in displayed game frames that carry the sampled control."""
    record = struct.Struct("<QQ1024s")
    tiles = {}
    with pixel_file.open("rb") as frames:
        while len(data := frames.read(record.size)) == record.size:
            frame, generated, tile = record.unpack(data)
            tiles[frame, generated] = tile
    shown = sorted((float(t), int(f), int(g)) for t, f, g in re.findall(
        r"Metal timing display: shown=([\d.]+) frame=(\d+) generated=(\d+)", log)
        if route["start"] - .3 < float(t) < route["end"] + .5)
    real = [(t, f) for t, f, generated in shown if not generated]
    samples = [(t, tiles[f, 0]) for t, f in real if (f, 0) in tiles]
    inputs = [(float(guest), float(shown)) for guest, shown in re.findall(
        r"Metal response sample: guest=([\d.]+) shown=([\d.]+)", log)]
    if not real or len(samples) < .95 * len(real):
        raise RuntimeError("The trace does not cover the displayed SDR game frames.")
    times = [t for t, _ in samples]
    latencies = {"run": [], "sword": [], "idle control": []}
    counts = dict.fromkeys(latencies, 0)
    for act in route["actions"]:
        kind = "run" if act["kind"].startswith("run ") else act["kind"]
        if kind not in counts:
            continue
        counts[kind] += 1
        press = act["press"]
        eligible = press
        if kind != "idle control":
            hits = [shown for guest, shown in inputs if press <= guest < act["release"]]
            if not hits:
                continue
            eligible = min(hits)
        before = samples[bisect_left(times, press-.105):bisect_left(times, press-.018)]
        if len(before) < 3:
            continue
        reference = bytes(int(statistics.median(values)) for values in zip(*(tile for _, tile in before)))
        observations = samples[bisect_left(times, press-.16):bisect_left(times, press+.50)]
        changes = [(t, sum(abs(a-b) > 19 for a, b in zip(tile, reference))/len(reference))
                   for t, tile in observations]
        noise = sorted(change for t, change in changes if t < press-.015)
        if not noise:
            continue
        threshold = max(floor, noise[math.ceil(len(noise)*.9)-1] + .017)
        first = None
        for t, change in changes:
            if t < eligible or change <= threshold:
                first = None
            elif first is None:
                first = t
            elif t-first >= .012:
                latencies[kind].append((first-press)*1000)
                break
    result = {"coverage": len(samples)/len(real)}
    for kind, values in latencies.items():
        result[kind] = dict(trials=counts[kind], detected=len(values),
                            median_ms=statistics.median(values) if values else None)
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("socket")
    parser.add_argument("log", type=Path)
    parser.add_argument("--pixels", type=Path, help="File created by HOS_METAL_PIXEL_TRACE for visible movement and swings")
    args = parser.parse_args()
    connection = Bridge(args.socket)
    try:
        route = village(connection)
    finally:
        connection.close()
    log = args.log.read_text(errors="replace")
    results = {"route": route, "results": score(route, log)}
    if args.pixels:
        results["visible"] = visible_actions(route, log, args.pixels)
    print(json.dumps(results))
