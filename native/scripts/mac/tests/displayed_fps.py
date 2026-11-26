"""Check displayed FPS over a recorded gameplay route on macOS.

Run with a completed HOS_METAL_TIMING=2 log and a route JSON from
field_traversal.py or village_response.py. A JSON object with a "spans"
mapping from phase names to [start, end] timestamps is also accepted.
"""
import argparse
from bisect import bisect_left, bisect_right
import json
import math
from pathlib import Path
import re


DISPLAY = re.compile(r"Metal timing display: shown=([\d.]+) frame=\d+ generated=([01])")


def read_displays(path):
    frames = {}
    with path.open(errors="replace") as log:
        for line in log:
            match = DISPLAY.search(line)
            if match:
                shown = float(match[1])
                if shown > 0:
                    # Two callbacks for one display instant still represent one picture.
                    frames[shown] = frames.get(shown, False) or match[2] == "0"
    return frames


def measure(times, frames, start, end, minimum):
    if not math.isfinite(start) or not math.isfinite(end) or end <= start:
        raise ValueError("The route must have a positive, finite duration.")
    left, right = bisect_right(times, start), bisect_left(times, end)
    if left == 0 or right == len(times):
        raise ValueError("Record displays on both sides of the route to measure boundary stalls.")
    # Include the frame that was on screen as the route started, and the
    # presentation that ended its final interval. At an exact boundary,
    # the interval outside the route contributes no time.
    gaps = [times[i + 1] - times[i] for i in range(left - 1, right)]
    worst = max(gaps)
    stop = bisect_right(times, end)
    pictures = times[left:stop]
    one_second_low = None
    if end - start >= 1:
        # A sliding count can fall only when a presentation exits on the left.
        starts = [start, end - 1, *times[left:bisect_right(times, end - 1)]]
        one_second_low = min(bisect_right(times, t + 1) - bisect_right(times, t) for t in starts)
    return {
        "displayed_fps": round(len(pictures) / (end - start), 2),
        "displayed_game_fps": round(sum(frames[t] for t in pictures) / (end - start), 2),
        "lowest_one_second_fps": one_second_low,
        "worst_frame_ms": round(1000 * worst, 3),
        "minimum_frame_fps": round(1 / worst, 2),
        # Timing records round each presentedTime to the nearest nanosecond.
        "passed": worst <= 1 / minimum + 1e-9,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("route", type=Path)
    parser.add_argument("--minimum", type=float, default=120, help="required FPS for every display interval")
    args = parser.parse_args()
    if not math.isfinite(args.minimum) or args.minimum <= 0:
        parser.error("--minimum must be positive and finite")
    try:
        route = json.loads(args.route.read_text())
        if "route" in route:
            route = route["route"]
        phases = route["spans"] if "spans" in route else {"route": (route["start"], route["end"])}
        if not phases:
            raise ValueError("The route contains no phases.")
        frames = read_displays(args.log)
        times = sorted(frames)
        results = {name: measure(times, frames, a, b, args.minimum) for name, (a, b) in phases.items()}
    except (KeyError, OSError, ValueError, TypeError, AttributeError) as exc:
        parser.error(str(exc))
    print(json.dumps(results, indent=2))
    return 0 if all(v["passed"] for v in results.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
