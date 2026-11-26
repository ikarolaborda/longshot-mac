"""Measure ZL sword combat from a copied Death Mountain Trail save at a red Tektite.
Enable the damage multiplier and HOS_TRACE_ATTACK=1 on that copy. The damage
callback confirms a player hit on a non-player actor. Pass the live game log.
"""
import argparse
import json
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from longshot_bridge import Bridge, check


def fight(bridge, log):
    game = check(bridge.request("status"))["game"]
    if game["map"] != "DeathMountainTrail_Child" or game["loading"] or game["event"]:
        raise ValueError("Start in control on Death Mountain Trail near the red Tektite.")
    start = time.monotonic()
    with log.open(errors="replace") as source:
        source.seek(0, 2)
        try:
            for _ in range(36):
                check(bridge.request("sequence", steps=[dict(buttons=["ZL", "Y"], frames=7),
                    dict(at=7, buttons=["ZL"], frames=14)], exclusive=True, wait=True))
                hit = next((line.strip() for line in source.readlines() if "trainer attack: life=" in line), None)
                if hit:
                    time.sleep(.3)
                    return dict(start=start, end=time.monotonic(), evidence=hit, map=game["map"])
        finally:
            check(bridge.request("release"))
    raise RuntimeError("No player-to-enemy damage registered during the sword sequence.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("socket")
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    bridge = Bridge(args.socket)
    try:
        print(json.dumps(fight(bridge, args.log), indent=2))
    finally:
        bridge.close()
