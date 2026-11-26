"""Time first/repeat Kakariko exits via normal movement. Start a copied adult
save at the village entrance, with a control socket enabled and gameplay active.
Use HOS_METAL_TIMING=2 before launching the game. Pass --output route.json,
then run displayed_fps.py with the game log and that route to measure each
crossing and its first two seconds of displayed frames.
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


def steer(bridge, state, x, z):
    px, _, pz = state["pos"]
    turn = math.radians(state["camera"]) - math.atan2(x - px, z - pz)
    check(bridge.request("stick", stick="left", x=round(math.sin(turn), 4),
                         y=round(math.cos(turn), 4), frames=120, exclusive=True, wait=False))


def crossing(bridge, destination, target):
    _, initial = game(bridge)
    origin = initial["map"]
    destination_maps = (destination, destination + "_Alternative")
    start = time.monotonic()
    trigger = None
    try:
        while time.monotonic() - start < 40:
            frame, state = game(bridge)
            now = time.monotonic()
            busy = state.get("event") or state.get("loading")
            if trigger is None and (busy or state.get("map") != origin):
                trigger, first_frame = now, frame
                check(bridge.request("release"))
            if state.get("map") in destination_maps and not busy:
                break
            if state.get("map") == origin and not busy:
                steer(bridge, state, *target)
            time.sleep(.035)
        else:
            raise RuntimeError(f"Timed out crossing from {origin} to {destination}.")
        ready, ready_frame = now, frame
        check(bridge.request("release"))
        time.sleep(.09)
        _, state = game(bridge)
        arrival = state["pos"]
        if state["map"] not in destination_maps or state["loading"]:
            raise RuntimeError("Lost the destination before measuring input.")
        dx, dz = (-1, 1) if destination == "HyruleField_Adult" else (1, -1)
        probe = time.monotonic()
        steer(bridge, state, arrival[0] + 10 * dx, arrival[2] + 10 * dz)
        while time.monotonic() - probe < 4:
            _, state = game(bridge)
            moved = time.monotonic()
            if state["map"] not in destination_maps:
                raise RuntimeError("Left the destination during the input probe.")
            x, _, z = state["pos"]
            if (x - arrival[0]) * dx + (z - arrival[2]) * dz > .35:
                return dict(origin=origin, destination=destination, start=start, trigger=trigger,
                            ready=ready, input=probe, moved=moved, seconds=round(ready-trigger, 3),
                            trigger_frame=first_frame, playable_frame=ready_frame, arrival=arrival,
                            endpos=state["pos"])
            time.sleep(.025)
        raise RuntimeError("Link did not move in the commanded direction after arrival.")
    finally:
        bridge.request("release")


def run(bridge, output=None):
    _, initial = game(bridge)
    if initial.get("map") not in ("KakarikoVillage_Adult", "KakarikoVillage_Adult_Alternative") or initial.get("event") or initial.get("loading"):
        raise ValueError("Start with adult Link in control at the Kakariko village gate.")
    x, _, z = initial["pos"]
    if math.hypot(x + 120, z - 58.7) > 5:
        raise ValueError("Move the copied save to the village side of the Hyrule Field entrance.")
    legs = [("HyruleField_Adult", (-148, 44)), ("KakarikoVillage_Adult", (215, 6)), ("HyruleField_Adult", (-148, 44))]
    trips, spans = [], {}
    for name, (destination, target) in zip(("first", "return", "repeat"), legs):
        trip = crossing(bridge, destination, target)
        trips.append(trip)
        spans[name + "_crossing"] = [trip["trigger"], trip["ready"]]
        spans[name + "_arrival"] = [trip["ready"], trip["ready"] + 2]
        print(json.dumps(trip), flush=True)
        time.sleep(max(0, trip["ready"] + 2.1 - time.monotonic()))
    if output:
        output.write_text(json.dumps(dict(trips=trips, spans=spans), indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("socket")
    parser.add_argument("--output", type=Path, help="write route spans for displayed_fps.py")
    args = parser.parse_args()
    bridge = Bridge(args.socket)
    try:
        run(bridge, args.output)
    finally:
        bridge.close()
