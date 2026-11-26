"""Replay the Hyrule Field portion of the Metal benchmark from the same copied save.

Run this on macOS with a control socket and an adult Link standing in Hyrule Field.
The game mode is selected in Graphics before the run. Set HOS_METAL_TIMING=2 and
HOS_FPS_LOG=1 when launching the game to record drawable times and the game clock.
The JSON output uses the same monotonic clock as the Metal presentation records.
"""

import argparse
import json
import math
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from longshot_bridge import Bridge, check


LEGS = [
    ("Run onto the field", 2.6, {"lx": 0, "ly": .95}),
    ("Turn while running", 1.1, {"lx": 0, "ly": .95, "rx": .52}),
    ("Draw the sword while running", .20, {"buttons": ["Y"], "lx": 0, "ly": .9}),
    ("Cross the field", 3.2, {"lx": -.25, "ly": .92}),
    ("Look toward the road", .85, {"lx": 0, "ly": .88, "rx": -.7}),
    ("Run down the road", 2.8, {"lx": .2, "ly": .93}),
    ("Hold ZL and strafe", .65, {"buttons": ["ZL"], "lx": .8}),
    ("Strike while holding ZL", .20, {"buttons": ["ZL", "Y"], "lx": .15, "ly": .9}),
    ("Continue uphill", 2.7, {"lx": .48, "ly": .8}),
]


def field_state(bridge):
    game = check(bridge.request("status")).get("game") or {}
    if game.get("map") != "HyruleField_Adult" or game.get("loading") or game.get("event"):
        raise RuntimeError("The route requires adult Link in playable Hyrule Field.")
    return game


def traverse(bridge):
    legs = []
    start = time.monotonic()
    for label, duration, controls in LEGS:
        before = field_state(bridge)
        press = time.monotonic()
        try:
            check(bridge.request("sequence", steps=[dict(controls, frames=500)], exclusive=True, wait=False))
            time.sleep(max(0, press + duration - time.monotonic()))
        finally:
            check(bridge.request("release"))
        after = field_state(bridge)
        legs.append(dict(label=label, t=press, end=time.monotonic(), pos=before["pos"],
                         endpos=after["pos"], camera=before["camera"], end_camera=after["camera"], map=after["map"]))
    end = time.monotonic()
    travel = sum(math.dist(leg["pos"], leg["endpos"]) for leg in legs)
    if travel < 1:
        raise RuntimeError("Link did not traverse the field.")
    return dict(start=start, end=end, legs=legs, distance=travel)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("socket", help="HOS_CONTROL socket of the copied game")
    args = parser.parse_args()
    connection = Bridge(args.socket)
    try:
        print(json.dumps(traverse(connection), indent=2))
    finally:
        connection.close()
