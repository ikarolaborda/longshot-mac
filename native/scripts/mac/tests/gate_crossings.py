"""Time first/repeat Kakariko exits via normal movement. Start a copied adult
save at the village entrance, with a control socket enabled and gameplay active.
"""
import argparse
import json
import math
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from longshot_bridge import Bridge, check


def game(bridge):
    reply = check(bridge.request("status"))
    return reply["frame"], reply.get("game") or {}


def crossing(bridge, destination, target):
    _, initial = game(bridge)
    origin = initial["map"]
    start = time.monotonic()
    trigger = None
    next_input = start
    first_frame = None
    try:
        while time.monotonic() - start < 25:
            frame, state = game(bridge)
            now = time.monotonic()
            if trigger is None and (state.get("event") or state.get("loading") or state.get("map") != origin):
                trigger, first_frame = now, frame
                check(bridge.request("release"))
            if state.get("map") == destination and state.get("music") and not state.get("loading") and not state.get("event"):
                if trigger is None:
                    raise RuntimeError("Missed the gate trigger.")
                return dict(origin=origin, destination=destination, seconds=round(now - trigger, 3),
                            trigger_frame=first_frame, playable_frame=frame, arrival=state["pos"])
            if trigger is None and now >= next_input:
                x, _, z = state["pos"]
                heading = math.atan2(target[0] - x, target[1] - z)
                turn = math.radians(state["camera"]) - heading
                check(bridge.request("stick", stick="left", x=round(math.sin(turn), 4),
                                     y=round(math.cos(turn), 4), frames=180, exclusive=True, wait=False))
                next_input = now + .22
            time.sleep(.12)
        raise RuntimeError(f"The gate from {origin} to {destination} did not finish in 25 seconds.")
    finally:
        bridge.request("release")


def run(bridge):
    _, initial = game(bridge)
    if initial.get("map") != "KakarikoVillage_Adult" or initial.get("event") or initial.get("loading"):
        raise ValueError("Start with adult Link in control at the Kakariko village gate.")
    x, _, z = initial["pos"]
    if math.hypot(x + 120, z - 58.7) > 5:
        raise ValueError("Move the copied save to the village side of the Hyrule Field entrance.")
    legs = [("HyruleField_Adult", (-148, 44)), ("KakarikoVillage_Adult", (215, 6)), ("HyruleField_Adult", (-148, 44))]
    for destination, target in legs:
        print(json.dumps(crossing(bridge, destination, target)), flush=True)
        time.sleep(.6)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("socket")
    args = parser.parse_args()
    bridge = Bridge(args.socket)
    try:
        run(bridge)
    finally:
        bridge.close()
