"""Summarize a gate_crossings and field_traversal run from its Metal display log."""
import argparse
import json
from pathlib import Path
import re
from statistics import median

from displayed_fps import measure, read_displays

# The renderer reports upload and pipeline totals for long frames only.
LONG_FRAME = re.compile(r"\[长帧\] 帧 (\d+)（[^）]+）整帧 [\d.]+ ms，[^\n]*?新建管线 (\d+) 条 \+ 着色器库 (\d+) 个共 ([\d.]+) ms；上传贴图 首传 (\d+) 张 \+ 重传 (\d+) 次 ([\d.]+) MB / ([\d.]+) ms")
INPUT = re.compile(r"Metal response sample: guest=([\d.]+) shown=([\d.]+)")
REASONS = re.compile(r"Scene textures: at=([\d.]+).*?first=(\d+) evicted=(\d+) format=(\d+) dirty=(\d+) untracked=(\d+) identical=(\d+)(?: first_bytes=(\d+) repeat_bytes=(\d+))?")
PHASE = re.compile(r"Scene phase: at=([\d.]+) map=(\S+) event=(\d) loading=(\d) read_bytes=(\d+) read_ms=([\d.]+) last_read=([\d.]+) decode_bytes=(\d+) decode_ms=([\d.]+) last_decode=([\d.]+)")
PRESENT = re.compile(r"Scene presentation: ready=([\d.]+) shown=([\d.]+)")


def report(log, gates, field):
    contents = log.read_text(errors="replace")
    frames = read_displays(log)
    times = sorted(frames)
    route = json.loads(gates.read_text())
    run = json.loads(field.read_text())
    inputs = [(float(a), float(b)) for a, b in INPUT.findall(contents)]
    rows = [list(map(float, row)) for row in LONG_FRAME.findall(contents)]
    reasons = [[float(value) if value else None for value in row] for row in REASONS.findall(contents)]
    phases = PHASE.findall(contents)
    presents = dict(PRESENT.findall(contents))

    def display(start, end):
        stats = measure(times, frames, start, end, 120)
        ages = [1000*(b-a) for a, b in inputs if start <= a <= end]
        stats["displayed_generated_fps"] = round(stats["displayed_fps"] - stats["displayed_game_fps"], 2)
        stats["input_samples"] = len(ages)
        stats["median_guest_to_display_ms"] = round(median(ages), 2) if ages else None
        return stats

    result = {}
    if len(route["trips"]) != 3:
        raise ValueError("Expected three completed gate crossings.")
    for name, trip in zip(("first", "return", "repeat"), route["trips"]):
        start, end = route["spans"][name + "_arrival"]
        selected = [row for row in rows if trip["trigger_frame"] <= row[0] <= trip["playable_frame"]]
        item = dict(arrival=display(start, end), crossing=display(trip["trigger"], start),
                    seconds_to_control=round(trip["moved"]-trip["trigger"], 3))
        item["long_frames_during_crossing"] = dict(zip(
            ("pipelines", "libraries", "pipeline_ms", "uploads", "reuploads", "upload_mb", "upload_ms"),
            [round(sum(row[i] for row in selected), 2) for i in range(1, 8)]))
        if reasons:
            selected = [row for row in reasons if trip["trigger"] <= row[0] <= end]
            item["texture_checks_through_arrival"] = dict(zip(
                ("first", "evicted", "format", "dirty", "untracked", "identical"),
                [int(sum(row[i] for row in selected)) for i in range(1, 7)]))
            if any(row[7] is not None for row in reasons):
                item["uploaded_guest_bytes_through_arrival"] = {
                    "first": int(sum(row[7] for row in selected if row[7] is not None)),
                    "repeat": int(sum(row[8] for row in selected if row[8] is not None)),
                }
        # Align to the actual ready marker rather than a poll from the external driver.
        ready = next((row for row in phases if row[1].removesuffix("_Alternative") == trip["destination"]
                      and row[2:4] == ("0", "0") and trip["start"] <= float(row[0]) <= trip["moved"]), None)
        before = [row for row in phases if float(row[0]) <= trip["trigger"]]
        if ready and before:
            prev = before[-1]
            item["since_last_state_sample"] = dict(read_bytes=int(ready[4])-int(prev[4]),
                read_worker_ms=round(float(ready[5])-float(prev[5]), 2),
                decode_bytes=int(ready[7])-int(prev[7]), decode_worker_ms=round(float(ready[8])-float(prev[8]), 2))
            shown = presents.get(ready[0])
            item["ready_to_real_display_ms"] = round(1000*(float(shown)-float(ready[0])), 2) if shown else None
        result[name] = item
    result["field"] = display(run["start"], run["end"])
    result["field"]["distance"] = round(run["distance"], 2)
    result["actions"] = {leg["label"]: display(leg["t"], leg["end"]) for leg in run["legs"]}
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("log", "gates", "field"):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    print(json.dumps(report(args.log, args.gates, args.field), indent=2))
